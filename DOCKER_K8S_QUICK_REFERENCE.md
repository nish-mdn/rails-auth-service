# Docker & Kubernetes Quick Reference

## 📦 Project Files Summary

### Docker Files Created
```
├── Dockerfile                 # Multi-stage production Dockerfile
├── docker-entrypoint.sh      # Container initialization script (migrations, keys)
├── .dockerignore             # Docker build optimization
├── docker-compose.yml        # Complete dev/test environment
└── docker/
    ├── nginx.conf            # Nginx reverse proxy config
    └── mysql-init.sql        # Database initialization script
```

### Kubernetes Files Created
```
k8s/
├── 01-namespace.yaml         # Kubernetes namespace
├── 02-configmap.yaml         # Non-sensitive configuration
├── 03-secret.yaml            # Sensitive configuration (DB, JWT keys)
├── 04-volumes.yaml           # Persistent volumes and claims
├── 05-database.yaml          # MySQL and Redis deployments
├── 06-application.yaml       # Rails app deployment + HPA + PDB
├── 07-ingress.yaml           # Ingress + NetworkPolicy
├── 08-monitoring.yaml        # Prometheus monitoring (optional)
└── 09-rbac.yaml              # Role-based access control

Deployment Script
├── k8s-deploy.sh             # Complete deployment automation
```

### Documentation
```
├── DOCKER_K8S_GUIDE.md       # Complete deployment guide
└── This file                 # Quick reference
```

---

## 🚀 Quick Start

### Option 1: Docker Compose (Local Development)

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f app

# Test the service
curl http://localhost:3000/health

# Stop services
docker-compose down
```

**Services started:**
- Rails app on localhost:3000
- MySQL on localhost:3306
- Redis on localhost:6379
- Nginx on localhost:80

### Option 2: Kubernetes (Production)

```bash
# 1. Update configuration
nano k8s/02-configmap.yaml
nano k8s/03-secret.yaml
nano k8s/06-application.yaml  # Update ECR registry

# 2. Deploy
chmod +x k8s-deploy.sh
./k8s-deploy.sh deploy

# 3. Check status
./k8s-deploy.sh status

# 4. View logs
./k8s-deploy.sh logs
```

---

## 🐳 Docker Operations

### Build Image

```bash
# Build locally
docker build -t auth-service:latest .

# Build with buildkit (faster)
DOCKER_BUILDKIT=1 docker build -t auth-service:latest .

# Build specific stage
docker build --target runtime -t auth-service:prod .
```

### ECR Operations

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Tag image
docker tag auth-service:latest ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest

# Push image
docker push ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest

# Pull image
docker pull ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
```

### Container Management

```bash
# Run container
docker run -d -p 3000:3000 \
  -e DB_HOST=db \
  -e DB_PASSWORD=secret \
  auth-service:latest

# Execute command in running container
docker exec -it container_name bundle exec rails console

# View logs
docker logs -f container_name

# Inspect container
docker inspect container_name

# Copy files from container
docker cp container_name:/app/keys/public.pem ./public.pem
```

---

## ☸️ Kubernetes Operations

### Deployment

```bash
# Deploy all manifests
./k8s-deploy.sh deploy

# Or manually
kubectl apply -f k8s/

# Kustomize (if using overlays)
kubectl apply -k k8s/
```

### Checking Status

```bash
# Watch pods
kubectl get pods -n auth-service -w

# Get all resources
kubectl get all -n auth-service

# Get detailed status
kubectl describe deployment auth-service-app -n auth-service

# Get events
kubectl get events -n auth-service
```

### Scaling

```bash
# Manual scaling
kubectl scale deployment auth-service-app --replicas=5 -n auth-service

# Check HPA status
kubectl get hpa -n auth-service

# Current HPA settings:
# - Min replicas: 3
# - Max replicas: 10
# - CPU target: 70%
# - Memory target: 80%
```

### Pod Management

```bash
# Get pod name
POD=$(kubectl get pods -n auth-service -l component=application -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs $POD -n auth-service
kubectl logs -f $POD -n auth-service  # Follow logs

# SSH into pod
kubectl exec -it $POD -n auth-service -- /bin/bash

# Run command in pod
kubectl exec $POD -n auth-service -- rails db:migrate

# Port forward
kubectl port-forward $POD 3000:3000 -n auth-service
```

### Updating Deployment

```bash
# Update image
kubectl set image deployment/auth-service-app \
  rails-app=ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:v1.0.1 \
  -n auth-service

# Rollout status
kubectl rollout status deployment/auth-service-app -n auth-service

# View rollout history
kubectl rollout history deployment/auth-service-app -n auth-service

# Rollback to previous version
kubectl rollout undo deployment/auth-service-app -n auth-service
```

### Configuration Updates

```bash
# Update ConfigMap
kubectl set env deployment/auth-service-app \
  CORS_ALLOWED_ORIGINS="yourdomain.com" \
  -n auth-service

# Or edit directly
kubectl edit configmap auth-service-config -n auth-service

# Update secret
kubectl create secret generic auth-service-secrets \
  --from-literal=DB_PASSWORD=newpassword \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up changes
kubectl rollout restart deployment/auth-service-app -n auth-service
```

### Database Operations

```bash
# Run migrations in Kubernetes
./k8s-deploy.sh migrate

# Or manually
kubectl exec -it MYSQL_POD -- mysql -u root -p auth_service_production < schema.sql

# Backup database
kubectl exec MYSQL_POD -- mysqldump -u root -p auth_service_production > backup.sql

# Restore from backup
kubectl exec -i MYSQL_POD -- mysql -u root -p auth_service_production < backup.sql
```

---

## 🔑 Environment Variables

### Critical Variables
```yaml
# Database
DB_HOST: "auth-service-mysql"
DB_PORT: "3306"
DB_USERNAME: "auth_service_user"
DB_PASSWORD: "secure_random_password"  # CHANGE THIS!
DB_NAME: "auth_service_production"

# Rails
SECRET_KEY_BASE: "from_rails_secret"  # Generate with: rails secret
RAILS_ENV: "production"

# JWT
DEVISE_JWT_SECRET_KEY: "secure_random_key"  # Generate with: openssl rand -base64 32

# CORS
CORS_ALLOWED_ORIGINS: "yourdomain.com,api.yourdomain.com"
```

### Where to Set
- **Docker Compose**: `.env` file
- **Kubernetes**: `k8s/02-configmap.yaml` and `k8s/03-secret.yaml`
- **Docker Runtime**: `-e` flag or `.env` file

---

## 🐛 Troubleshooting

### Docker Issues

```bash
# Container won't start
docker logs container_name

# Port already in use
docker ps --filter ancestor=auth-service

# Memory issues
docker stats  # Monitor container resource usage

# Network issues
docker network ls
docker network inspect docker_auth-network
```

### Kubernetes Issues

```bash
# Pod stuck in pending
kubectl describe pod POD_NAME -n auth-service

# ImagePullBackOff
kubectl describe pod POD_NAME -n auth-service
# Check: ECR credentials, image exists, image spelling

# Database connection failed
kubectl exec POD_NAME -n auth-service -- \
  mysql -h auth-service-mysql -u root -p

# Check resource availability
kubectl describe nodes
kubectl top nodes
kubectl top pods -n auth-service
```

---

## 📊 Monitoring

### Database Monitoring

```bash
# Check MySQL queries
kubectl exec MYSQL_POD -n auth-service -- \
  mysql -u root -p -e "SHOW PROCESSLIST;"

# Monitor MySQL performance
kubectl exec MYSQL_POD -n auth-service -- \
  mysql -u root -p -e "SHOW STATUS LIKE '%Queries%';"
```

### Application Monitoring

```bash
# View metrics
kubectl top pods -n auth-service

# Check logs for errors
kubectl logs -f deployment/auth-service-app -n auth-service | grep ERROR

# Monitor requests
kubectl logs -f deployment/auth-service-app -n auth-service | grep "Completed"
```

### Prometheus Metrics (if enabled)

```bash
# Access Prometheus
kubectl port-forward -n prometheus svc/prometheus 9090:9090

# Visit: http://localhost:9090
# Query: up{job="auth-service"}
```

---

## 🔒 Security Checklist

### Docker
- ✅ Multi-stage build (smaller image size)
- ✅ Non-root user (UID 1000)
- ✅ No hardcoded secrets (use environment variables)
- ✅ Health checks configured
- ✅ Read-only filesystem where possible

### Kubernetes
- ✅ Network policies enabled
- ✅ Security context configured (non-root)
- ✅ Pod security policy enforced
- ✅ RBAC rules defined
- ✅ Secrets not logged
- ✅ Resource limits set
- ✅ Health probes configured

### Database
- ✅ Strong passwords (openssl rand -base64 32)
- ✅ Limited privileges (app user only)
- ✅ Encrypted connections
- ✅ Regular backups
- ✅ Read replicas for DR

---

## 📈 Performance Tips

### Docker Compose
```bash
# Increase log buffer
docker-compose --log-level=warning up -d

# Use specific service
docker-compose up -d app  # Only start Rails app

# Resource limits
# In docker-compose.yml:
# services:
#   app:
#     deploy:
#       resources:
#         limits:
#           cpus: '0.5'
#           memory: 1G
```

### Kubernetes
```bash
# Horizontal Pod Autoscaler status
kubectl get hpa auth-service-app-hpa -n auth-service --watch

# Vertical Pod Autoscaler (VPA)
# Recommendations for resource requests/limits
# kubectl describe vpa auth-service-vpa -n auth-service

# Pod Disruption Budget
kubectl describe pdb auth-service-app-pdb -n auth-service
```

---

## 📋 Pre-Deployment Checklist

### Docker
- [ ] Updated `Dockerfile`
- [ ] Built image: `docker build -t auth-service:latest .`
- [ ] Tested with `docker-compose up -d`
- [ ] API responding to requests
- [ ] Logs show no errors
- [ ] Pushed to ECR

### Kubernetes
- [ ] Updated `k8s/02-configmap.yaml` with your values
- [ ] Updated `k8s/03-secret.yaml` with secure values
- [ ] Updated `k8s/06-application.yaml` with ECR registry
- [ ] Updated `k8s/07-ingress.yaml` with your domain
- [ ] Updated `k8s/04-volumes.yaml` with node names
- [ ] Storage class created on cluster
- [ ] Ingress controller installed
- [ ] Verified ECR access
- [ ] Run: `./k8s-deploy.sh deploy`
- [ ] Check: `./k8s-deploy.sh status`

---

## 🎯 Key Files to Understand

| File | Purpose | When to Edit |
|------|---------|-------------|
| `Dockerfile` | Container image definition | Change base image, add dependencies |
| `docker-entrypoint.sh` | Container startup script | Add initialization steps |
| `docker-compose.yml` | Local dev environment | Add services, change ports |
| `k8s/02-configmap.yaml` | Non-secret config | CORS, env settings |
| `k8s/03-secret.yaml` | Secret credentials | DB password, JWT secret |
| `k8s/06-application.yaml` | App deployment | Replicas, resources, image |
| `k8s/07-ingress.yaml` | External access | Domain, SSL, routing |

---

## 🚀 Deployment Summary

### Step 1: Prepare
- Update configuration files with your values
- Push Docker image to ECR
- Test locally with docker-compose

### Step 2: Deploy
```bash
./k8s-deploy.sh deploy
```

### Step 3: Verify
```bash
./k8s-deploy.sh status
./k8s-deploy.sh logs
```

### Step 4: Monitor
```bash
kubectl get pods -w -n auth-service
kubectl top pods -n auth-service
```

---

## 📞 Support

For detailed information, see:
- **Full Guide**: `DOCKER_K8S_GUIDE.md`
- **Deployment Script**: `./k8s-deploy.sh --help`
- **Project README**: `README.md`

---

**Last Updated**: March 30, 2026  
**Status**: ✅ Production Ready
