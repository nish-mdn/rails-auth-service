# Kubernetes Database Connection Troubleshooting

## Error: Database Authentication Failure
```
There is an issue connecting to your database with your username/password, username: auth_service.
```

## Root Causes Fixed

### Issue 1: Hardcoded Production Credentials
**Problem:** `config/database.yml` had hardcoded `username: auth_service` and expected `AUTH_SERVICE_DATABASE_PASSWORD` environment variable, but Kubernetes was providing `DB_USERNAME` and `DB_PASSWORD`.

**Solution:** Updated production section to use environment variables consistently:
```yaml
production:
  username: <%= ENV.fetch("DB_USERNAME", "auth_user") %>
  password: <%= ENV.fetch("DB_PASSWORD", "") %>
```

### Issue 2: Secret Username Mismatch
**Problem:** `03-secret.yaml` had `DB_USERNAME: "auth_service_user"` but the code expected `auth_user`.

**Solution:** Changed to consistent username across Docker and Kubernetes:
```yaml
DB_USERNAME: "auth_user"
```

### Issue 3: MySQL Environment Variables
**Problem:** The MySQL deployment wasn't getting the password environment variable properly.

**Solution:** Ensured both MYSQL_USER and MYSQL_PASSWORD are set from the same secret:
```yaml
- name: MYSQL_USER
  valueFrom:
    secretKeyRef:
      name: auth-service-secrets
      key: DB_USERNAME
- name: MYSQL_PASSWORD
  valueFrom:
    secretKeyRef:
      name: auth-service-secrets
      key: DB_PASSWORD
```

## Credential Flow (After Fix)

### Docker Compose
```
Environment Variables → Docker Compose → Container
DB_USERNAME: auth_user
DB_PASSWORD: auth_password
```

### Kubernetes
```
Secret (03-secret.yaml)
  ├── DB_USERNAME: auth_user
  └── DB_PASSWORD: <random>
         │
         ├─→ MySQL Deployment (05-database.yaml)
         │   MYSQL_USER + MYSQL_PASSWORD
         │
         └─→ Rails App Deployment (06-application.yaml)
             ENV variables
             ↓
             config/database.yml
             username/password
```

## Files Modified

1. **config/database.yml** - Production section now uses environment variables
2. **k8s/03-secret.yaml** - Changed DB_USERNAME to "auth_user" for consistency
3. **k8s/05-database.yaml** - Added explicit MYSQL_PASSWORD environment variable

## Verification Steps

### 1. Check Secret is Created
```bash
kubectl get secret -n auth-service auth-service-secrets -o yaml
```

Should show:
```yaml
data:
  DB_USERNAME: YXV0aF91c2Vy  # base64: auth_user
  DB_PASSWORD: <encoded_password>
```

### 2. Check ConfigMap
```bash
kubectl get configmap -n auth-service auth-service-config -o yaml
```

Verify DB_HOST, DB_PORT, DB_NAME match:
- DB_HOST: auth-service-mysql
- DB_PORT: 3306
- DB_NAME: auth_service_production

### 3. Verify MySQL Pod Environment Variables
```bash
kubectl exec -it -n auth-service deployment/auth-service-mysql -- env | grep MYSQL
```

Should show:
```
MYSQL_ROOT_PASSWORD=<password>
MYSQL_DATABASE=auth_service_production
MYSQL_USER=auth_user
MYSQL_PASSWORD=<password>
```

### 4. Check MySQL User Access
```bash
# Port forward to MySQL
kubectl port-forward -n auth-service svc/auth-service-mysql 3306:3306 &

# Test connection from host
mysql -h 127.0.0.1 -u auth_user -p -e "SELECT 1;"

# Or from within MySQL pod
kubectl exec -it -n auth-service deployment/auth-service-mysql -- \
  mysql -u auth_user -p -e "SELECT user FROM mysql.user;"
```

### 5. Check Rails App Logs
```bash
kubectl logs -n auth-service deployment/auth-service-app -f --all-containers
```

Look for successful migration:
```
✓ Database is ready!
Running database migrations...
✓ Database migrations completed successfully
```

### 6. Verify Rails App Environment Variables
```bash
kubectl exec -it -n auth-service deployment/auth-service-app -- env | grep -E "^DB_|RAILS_ENV"
```

Should show:
```
DB_USERNAME=auth_user
DB_PASSWORD=<password>
DB_HOST=auth-service-mysql
DB_PORT=3306
DB_NAME=auth_service_production
RAILS_ENV=production
```

### 7. Test Rails Database Connection
```bash
# Connect to Rails console
kubectl exec -it -n auth-service deployment/auth-service-app -- \
  bundle exec rails console

# In Rails console
> ActiveRecord::Base.connection.execute("SELECT 1")
```

## Deployment Steps (After Changes)

### 1. Update Secrets
```bash
# Delete old secret
kubectl delete secret -n auth-service auth-service-secrets

# Create new secret with proper values
kubectl create secret generic auth-service-secrets \
  --from-literal=DB_USERNAME=auth_user \
  --from-literal=DB_PASSWORD=$(openssl rand -base64 32) \
  --from-literal=SECRET_KEY_BASE=$(rails secret) \
  --from-literal=DEVISE_JWT_SECRET_KEY=$(openssl rand -base64 32) \
  -n auth-service
```

### 2. Rebuild Docker Image
If using ECR or Docker Hub, rebuild with updated database.yml:
```bash
docker build -t your-registry/auth-service:latest .
docker push your-registry/auth-service:latest
```

### 3. Apply Kubernetes Changes
```bash
# Apply in order
kubectl apply -f k8s/01-namespace.yaml
kubectl apply -f k8s/02-configmap.yaml
kubectl apply -f k8s/03-secret.yaml
kubectl apply -f k8s/04-volumes.yaml
kubectl apply -f k8s/05-database.yaml

# Wait for MySQL ready
kubectl rollout status deployment/auth-service-mysql -n auth-service

# Then apply application
kubectl apply -f k8s/06-application.yaml
kubectl rollout status deployment/auth-service-app -n auth-service
```

### 4. Monitor Startup
```bash
# Watch pod status
kubectl get pods -n auth-service -w

# Monitor logs in real-time
kubectl logs -n auth-service deployment/auth-service-app -f --tail=50
```

## Environment Variable Mapping Reference

| Environment Variable | Source | Used By | Value |
|----------------------|--------|---------|-------|
| DB_USERNAME | Secret (03-secret.yaml) | Rails app, MySQL env | auth_user |
| DB_PASSWORD | Secret (03-secret.yaml) | Rails app, MySQL env | <random> |
| DB_HOST | ConfigMap (02-configmap.yaml) | Rails app | auth-service-mysql |
| DB_PORT | ConfigMap (02-configmap.yaml) | Rails app | 3306 |
| DB_NAME | ConfigMap (02-configmap.yaml) | Rails app, MySQL | auth_service_production |
| RAILS_ENV | ConfigMap (02-configmap.yaml) | Rails app | production |
| RACK_ENV | ConfigMap (02-configmap.yaml) | Rails app | production |

## Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| `username: auth_service` error | database.yml has hardcoded username | Use environment variables in database.yml (DONE) |
| Pod CrashLoopBackOff | Database not ready | Check MySQL pod logs; ensure it's healthy |
| `Unknown database` error | Wrong DB_NAME | Verify DB_NAME in ConfigMap matches MySQL env |
| Connection refused | Wrong DB_HOST or port | Ensure MySQL service name is correct |
| `Access denied for user` | Wrong credentials | Verify DB_USERNAME and DB_PASSWORD in secret |
| `after_worker_fork` errors | Database pool exhausted | Increase connection pool or reduce replicas initially |

## Production Deployment Checklist

- [ ] Update Secret with secure, random DB_PASSWORD
- [ ] Update Secret with generated SECRET_KEY_BASE and DEVISE_JWT_SECRET_KEY
- [ ] Update ConfigMap CORS_ALLOWED_ORIGINS with actual domain
- [ ] Update 06-application.yaml with real ECR/Docker registry URL
- [ ] Rebuild and push Docker image to registry
- [ ] Test database connectivity before increasing replicas
- [ ] Set up database backup policy for the PVC
- [ ] Configure monitoring and alerts
- [ ] Document password rotation procedure

## Rollback Procedure

If changes cause issues:

```bash
# Revert Kubernetes files
git checkout k8s/

# Rollback Rails app deployment
kubectl rollout undo deployment/auth-service-app -n auth-service

# Rollback database
kubectl rollout undo deployment/auth-service-mysql -n auth-service

# Check status
kubectl get pods -n auth-service
```

## Security Best Practices

1. **Never commit secrets** to git - use external secret management
2. **Use sealed-secrets or external-secrets operator** for production
3. **Rotate passwords regularly**
4. **Use least privilege for database user**
5. **Encrypt communication** between app and database
6. **Use non-root user** in containers (already done)
7. **Implement backup and recovery** procedures

## Related Documentation

- [Kubernetes Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Rails Database Configuration](https://guides.rubyonrails.org/configuring.html#database-configuration)
- [MySQL Service Account Setup](https://dev.mysql.com/doc/mysql-shell/8.0/en/getting-connection-parameters.html)
