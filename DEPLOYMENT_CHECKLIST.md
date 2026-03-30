# 🚀 Complete Deployment Checklist & Getting Started

**Project**: Auth Service - Container & Kubernetes Ready  
**Current Status**: ✅ **100% Complete** - All files created and ready  
**Last Updated**: March 30, 2026

---

## 📋 QUICK START (5 Minutes)

### Option 1: Local Development with Docker Compose

```bash
# 1. Navigate to project
cd auth-service

# 2. Start all services
docker-compose up -d

# 3. Wait 30 seconds for initialization
sleep 30

# 4. Test the service
curl http://localhost:3000/health

# 5. View logs
docker-compose logs -f app

# 6. Stop
docker-compose down
```

### Option 2: Deploy to Kubernetes

```bash
# 1. Update configuration files (see "Pre-Deployment Steps" below)

# 2. Make script executable
chmod +x k8s-deploy.sh

# 3. Deploy
./k8s-deploy.sh deploy

# 4. Check status
./k8s-deploy.sh status

# 5. View logs
./k8s-deploy.sh logs

# 6. Run migrations
./k8s-deploy.sh migrate
```

---

## ⚠️ PRE-DEPLOYMENT STEPS (Required Before Going to Production)

### Step 1: Update Configuration Files

#### File: `k8s/02-configmap.yaml`
```yaml
Update these values:
  CORS_ALLOWED_ORIGINS: "https://yourapp.com,https://anotherapp.com"
  WEB_CONCURRENCY: "2"  (adjust based on your pod CPU requests)
  RAILS_MAX_THREADS: "16"  (adjust based on your workload)
```

#### File: `k8s/03-secret.yaml`
```yaml
# Generate secure values BEFORE deployment:
DB_USERNAME: auth_service_user
DB_PASSWORD: $(openssl rand -base64 32)
SECRET_KEY_BASE: $(rails secret)
DEVISE_JWT_SECRET_KEY: $(openssl rand -base64 32)
SMTP_PASSWORD: your-smtp-password
```

**⚠️ CRITICAL**: Never commit real secrets to git. Use:
- AWS Secrets Manager (recommended)
- HashiCorp Vault
- Sealed Secrets
- External Secrets Operator

#### File: `k8s/04-volumes.yaml`
```yaml
Update node affinity to match YOUR actual node names:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - "your-actual-node-name-1"  # CHANGE THIS
          - "your-actual-node-name-2"  # CHANGE THIS

# Get actual node names:
kubectl get nodes --show-labels
```

#### File: `k8s/06-application.yaml`
```yaml
Update ECR registry URL:
  image: ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
  
Replace ACCOUNT with your AWS account ID
Replace us-east-1 with your AWS region
```

#### File: `k8s/07-ingress.yaml`
```yaml
Update domain names and certificate:
  hosts:
  - auth.yourdomain.com       # CHANGE TO YOUR DOMAIN
  - auth-staging.yourdomain.com  # CHANGE IF NEEDED
  
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"
  OR
  alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:..."
```

### Step 2: Build & Push Docker Image

```bash
# Set AWS credentials
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Build image
DOCKER_BUILDKIT=1 docker build -t auth-service:latest .

# Tag for ECR
docker tag auth-service:latest $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/auth-service:latest

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Push
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/auth-service:latest
```

### Step 3: Verify Kubernetes Cluster Prerequisites

```bash
# 1. Check kubectl access
kubectl cluster-info

# 2. Verify storage class exists
kubectl get storageclass
# Expected: local-storage OR your storage class name

# 3. Verify ingress controller
kubectl get pods -A | grep -E "nginx|alb"

# 4. Check available nodes
kubectl get nodes
# Most show at least 1 node with capacity for 3 replicas

# 5. Verify resource availability
kubectl top nodes  # Shows resource usage
```

### Step 4: Set Up Local Storage (if using local-storage)

```bash
# SSH into each Kubernetes worker node and create local paths:

for node in worker-node-1 worker-node-2 worker-node-3; do
  ssh ubuntu@$node <<'EOF'
    sudo mkdir -p /mnt/data/auth-service-mysql
    sudo mkdir -p /mnt/data/auth-service-app
    sudo chown -R nobody:nogroup /mnt/data
    sudo chmod -R 755 /mnt/data
  EOF
done
```

---

## 📁 File Structure Overview

```
auth-service/
├── 📄 Dockerfile                          (Multi-stage container image)
├── 📄 docker-entrypoint.sh               (Container initialization script)
├── 📄 docker-compose.yml                 (Local development environment)
├── 📄 .dockerignore                      (Build optimization)
├── 📁 docker/
│   ├── 📄 nginx.conf                     (Nginx reverse proxy config)
│   └── 📄 mysql-init.sql                 (Database initialization)
├── 📁 k8s/
│   ├── 📄 01-namespace.yaml              (K8s namespace isolation)
│   ├── 📄 02-configmap.yaml              (Non-secret environment config)
│   ├── 📄 03-secret.yaml                 (Secrets template)
│   ├── 📄 04-volumes.yaml                (Persistent volumes for MySQL/App)
│   ├── 📄 05-database.yaml               (MySQL & Redis deployments)
│   ├── 📄 06-application.yaml            (Rails app with HPA & PDB)
│   ├── 📄 07-ingress.yaml                (Ingress & NetworkPolicy)
│   ├── 📄 08-monitoring.yaml             (Prometheus monitoring)
│   └── 📄 09-rbac.yaml                   (Kubernetes RBAC)
├── 📄 k8s-deploy.sh                      (Automated deployment script)
├── 📄 config/puma.rb                     (Rails process server config)
├── 📄 Gemfile                            (Ruby dependencies)
├── 📁 app/                               (Rails application code)
├── 📁 config/                            (Rails configuration)
├── 📁 db/                                (Database migrations)
├── 📁 lib/                               (Custom tasks)
├── 📁 keys/                              (RSA keys - generated at runtime)
├── 📄 .env.example                       (Environment variables template)
├── 📄 README.md                          (Project overview)
├── 📄 QUICKSTART.md                      (5-minute setup guide)
├── 📄 GETTING_STARTED.md                 (Detailed setup guide)
├── 📄 API_REFERENCE.md                   (API endpoint documentation)
├── 📄 ARCHITECTURE.md                    (System design)
├── 📄 DEPLOYMENT.md                      (Traditional deployment guide)
├── 📄 BUILD_SUMMARY.md                   (Build details)
├── 📄 INDEX.md                           (Documentation index)
├── 📄 DOCKER_K8S_GUIDE.md                (Comprehensive container guide)
├── 📄 DOCKER_K8S_QUICK_REFERENCE.md     (Quick command reference)
└── 📄 DOCKER_K8S_IMPLEMENTATION.md       (This file - implementation details)
```

---

## 🎯 DEPLOYMENT COMMAND REFERENCE

### Docker Compose Commands

```bash
# Start services in background
docker-compose up -d

# View logs (follow mode)
docker-compose logs -f app

# View specific service logs
docker-compose logs -f mysql
docker-compose logs -f redis
docker-compose logs -f nginx

# Execute command in container
docker-compose exec app bash
docker-compose exec db mysql -u root -p

# Stop all services
docker-compose down

# Stop with data removal
docker-compose down -v

# Rebuild image
docker-compose build --no-cache

# Run migrations
docker-compose run --rm app bundle exec rails db:migrate

# Create database
docker-compose run --rm app bundle exec rails db:create
```

### Kubernetes Deployment Commands

```bash
# One-command deployment (recommended)
./k8s-deploy.sh deploy

# Check deployment status
./k8s-deploy.sh status

# View application logs
./k8s-deploy.sh logs

# Run database migrations
./k8s-deploy.sh migrate

# Destroy everything
./k8s-deploy.sh destroy

# Get help
./k8s-deploy.sh help
```

### Manual Kubernetes Commands

```bash
# Apply all manifests
kubectl apply -f k8s/

# Check namespace
kubectl get namespace auth-service

# View all resources
kubectl get all -n auth-service

# View pods with details
kubectl get pods -n auth-service -o wide

# View pod logs
kubectl logs -f deployment/auth-service-app -n auth-service

# Port forward to local
kubectl port-forward svc/auth-service-app 3000:80 -n auth-service

# Execute command in pod
kubectl exec -it deployment/auth-service-app -n auth-service -- bash

# Scale replicas
kubectl scale deployment auth-service-app --replicas=5 -n auth-service

# Update image
kubectl set image deployment/auth-service-app \
  app=ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:v1.0.0 \
  -n auth-service

# Rollback to previous version
kubectl rollout undo deployment/auth-service-app -n auth-service

# View deployment history
kubectl rollout history deployment/auth-service-app -n auth-service

# Delete everything
kubectl delete namespace auth-service
```

---

## ✅ VERIFICATION CHECKLIST

### After Docker Compose Startup

- [ ] All 4 services show "healthy"
  ```bash
  docker-compose ps
  ```

- [ ] Rails app responds to health check
  ```bash
  curl http://localhost:3000/health
  # Expected: 200 OK
  ```

- [ ] Database is running
  ```bash
  docker-compose exec db mysql -u auth_user -p -e "SELECT 1"
  ```

- [ ] Migrations completed
  ```bash
  docker-compose logs app | grep "db:migrate"
  ```

- [ ] RSA keys generated
  ```bash
  ls -la keys/
  # Expected: private.pem, public.pem
  ```

- [ ] Can access web interface
  ```bash
  Open http://localhost:3000 in browser
  ```

### After Kubernetes Deployment

- [ ] Namespace created
  ```bash
  kubectl get namespace auth-service
  ```

- [ ] ConfigMap loaded
  ```bash
  kubectl get configmap -n auth-service
  ```

- [ ] Secret created
  ```bash
  kubectl get secret -n auth-service
  ```

- [ ] Volumes bound
  ```bash
  kubectl get pvc -n auth-service
  # Expected: Bound status
  ```

- [ ] MySQL pod running
  ```bash
  kubectl get pod -n auth-service | grep mysql
  # Expected: Running, Ready 1/1
  ```

- [ ] Redis pod running
  ```bash
  kubectl get pod -n auth-service | grep redis
  # Expected: Running, Ready 1/1
  ```

- [ ] App pods running (3 replicas)
  ```bash
  kubectl get pod -n auth-service | grep auth-service-app
  # Expected: Running, Ready 1/1 (×3)
  ```

- [ ] Service created
  ```bash
  kubectl get svc -n auth-service
  ```

- [ ] Ingress created with IP/hostname
  ```bash
  kubectl get ingress -n auth-service
  ```

- [ ] HPA working
  ```bash
  kubectl get hpa -n auth-service
  # Expected: REFERENCE shows statuses
  ```

- [ ] Health endpoint responds
  ```bash
  kubectl port-forward svc/auth-service-app 3000:80 -n auth-service &
  curl http://localhost:3000/health
  ```

---

## 🐛 TROUBLESHOOTING

### Docker Compose Issues

**Problem**: Services won't start
```bash
# Check logs
docker-compose logs

# Remove everything and start fresh
docker-compose down -v
docker-compose up -d

# Rebuild image
docker-compose build --no-cache
docker-compose up -d
```

**Problem**: Database connection error
```bash
# Check if MySQL is actually running
docker-compose ps

# Check MySQL logs
docker-compose logs db

# Verify credentials in .env
cat .env | grep DB_
```

**Problem**: Health check failing
```bash
# Check application logs
docker-compose logs app

# Verify app is listening on port 3000
docker-compose exec app netstat -tuln | grep 3000
```

### Kubernetes Issues

**Problem**: Pods not starting
```bash
# Check pod status
kubectl describe pod <pod-name> -n auth-service

# View event logs
kubectl get events -n auth-service --sort-by='.lastTimestamp'

# Check logs
kubectl logs <pod-name> -n auth-service --previous  # If crashed
```

**Problem**: Database migration failing
```bash
# Run migrations manually
./k8s-deploy.sh migrate

# Or manually:
kubectl exec -it deployment/auth-service-app -n auth-service -- \
  bundle exec rails db:migrate
```

**Problem**: PVC not binding
```bash
# Check PV and PVC status
kubectl get pv,pvc -n auth-service

# Check node affinity
kubectl get nodes -L kubernetes.io/hostname

# Update 04-volumes.yaml with correct node names
```

**Problem**: Ingress not accessible
```bash
# Check ingress status
kubectl get ingress -n auth-service

# Check ingress controller logs
kubectl logs -n kube-system -l app=nginx-ingress

# Check NetworkPolicy
kubectl get networkpolicy -n auth-service
```

### General Docker Issues

```bash
# Check Docker daemon
docker info

# Restart Docker daemon
systemctl restart docker

# Check image size
docker images | grep auth-service

# Clean up unused images
docker image prune

# Check disk space
docker system df
```

### General Kubernetes Issues

```bash
# Check cluster status
kubectl cluster-info

# Check nodes
kubectl get nodes
kubectl describe node <node-name>

# Check API server logs (if self-managed)
journalctl -u kubelet -f

# Check storage class
kubectl get storageclass
```

---

## 🔐 Security Checklist

- [ ] Secrets are stored in AWS Secrets Manager, not in git
- [ ] Database credentials are at least 32 characters
- [ ] SECRET_KEY_BASE is generated with `rails secret`
- [ ] JWT_SECRET is generated with `openssl rand -base64 32`
- [ ] Container runs as non-root
- [ ] ResourceQuotas are set
- [ ] NetworkPolicy restricts pod-to-pod traffic
- [ ] RBAC limits ServiceAccount permissions
- [ ] SSL/TLS is configured in Ingress
- [ ] CORS_ALLOWED_ORIGINS only lists trusted domains
- [ ] Health endpoint doesn't expose sensitive data
- [ ] Logs don't contain secrets
- [ ] Image is scanned for vulnerabilities

---

## 📊 MONITORING SETUP

### Docker Compose Monitoring

```bash
# CPU and memory usage
docker stats

# Show container resource limits
docker inspect auth-service_app | grep -A 20 "HostConfig"
```

### Kubernetes Monitoring

```bash
# Enable metrics
kubectl top nodes
kubectl top pods -n auth-service

# Watch HPA scaling
kubectl get hpa -n auth-service -w

# Install Prometheus (optional)
helm install prometheus prometheus-community/kube-prometheus-stack

# View alerts
kubectl logs deployment/auth-service-app -n auth-service
```

---

## 📞 SUPPORT RESOURCES

### Documentation Files
- **README.md** - Overview and features
- **QUICKSTART.md** - 5-minute setup guide
- **DOCKER_K8S_GUIDE.md** - Comprehensive deployment guide
- **DOCKER_K8S_QUICK_REFERENCE.md** - Quick command lookup
- **API_REFERENCE.md** - API endpoint details

### External Resources
- [Docker Documentation](https://docs.docker.com/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Rails Deployment Guide](https://guides.rubyonrails.org/deployment.html)
- [Puma Server](https://puma.io/)

---

## 🎯 NEXT STEPS

1. **Update configuration files** (see pre-deployment steps)
2. **Test locally** with docker-compose
3. **Build and push** image to ECR
4. **Verify K8s prerequisites**
5. **Deploy to Kubernetes** using k8s-deploy.sh
6. **Monitor deployment** using kubectl
7. **Set up monitoring** with Prometheus
8. **Configure backups** for database
9. **Document custom configurations**
10. **Set up CI/CD** for automated deployments

---

**Status**: ✅ All files created and ready for deployment  
**Last Updated**: March 30, 2026  
**Estimated Time to First Deployment**: 30 minutes (with all prerequisites met)

---

## 📋 QUICK LINKS

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | Project overview |
| [QUICKSTART.md](QUICKSTART.md) | 5-minute setup |
| [API_REFERENCE.md](API_REFERENCE.md) | API endpoints |
| [DOCKER_K8S_GUIDE.md](DOCKER_K8S_GUIDE.md) | Full container guide |
| [DOCKER_K8S_QUICK_REFERENCE.md](DOCKER_K8S_QUICK_REFERENCE.md) | Command reference |
| [DOCKER_K8S_IMPLEMENTATION.md](DOCKER_K8S_IMPLEMENTATION.md) | Implementation details |
