# Docker & Kubernetes Deployment Guide

A comprehensive guide for containerizing and deploying the Auth Service on AWS self-managed Kubernetes cluster.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Docker Build & Registry](#docker-build--registry)
3. [Local Testing with Docker Compose](#local-testing-with-docker-compose)
4. [Kubernetes Deployment](#kubernetes-deployment)
5. [Production Configuration](#production-configuration)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
- **Docker** 20.10+
- **Kubernetes** 1.23+ (self-managed or managed)
- **kubectl** 1.23+
- **AWS CLI** v2 (for ECR access)
- **Helm** 3.0+ (optional, for package management)

### AWS Requirements
- AWS ECR repository for storing Docker images
- AWS EKS/Self-managed K8s cluster
- RDS or self-managed MySQL database (optional)
- Application Load Balancer (ALB) or Ingress Controller

### Kubernetes Resources
- Storage class configured (local-storage recommended for self-managed)
- Ingress controller installed (ALB or Nginx)
- Optional: Prometheus for monitoring

---

## Docker Build & Registry

### 1. Build Docker Image

```bash
# Navigate to project directory
cd auth-service

# Build image
docker build -t auth-service:latest .

# Tag image for ECR
docker tag auth-service:latest YOUR_AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest

# Verify image
docker images | grep auth-service
```

### 2. Push to AWS ECR

```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin YOUR_AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com

# Push image
docker push YOUR_AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest

# Verify in ECR
aws ecr describe-images --repository-name auth-service --region us-east-1
```

### 3. Image Tagging Strategy

```bash
# Development tag
docker tag auth-service:latest YOUR_ECR/auth-service:dev

# Staging tag
docker tag auth-service:latest YOUR_ECR/auth-service:staging

# Production tag (semver)
docker tag auth-service:latest YOUR_ECR/auth-service:1.0.0

# Push all tags
docker push YOUR_ECR/auth-service:dev
docker push YOUR_ECR/auth-service:staging
docker push YOUR_ECR/auth-service:1.0.0
```

---

## Local Testing with Docker Compose

### 1. Set Environment Variables

```bash
# Copy example file
cp .env.example .env

# Edit with your values
nano .env
```

### 2. Start Services

```bash
# Build and start all services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f app

# Follow specific service logs
docker-compose logs -f db
docker-compose logs -f redis
```

### 3. Test Application

```bash
# Wait for initialization (30-40 seconds)

# Sign up
curl -X POST http://localhost:3000/users \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "test@example.com",
      "password": "Password123",
      "password_confirmation": "Password123"
    }
  }'

# Sign in
curl -X POST http://localhost:3000/users/sign_in \
  -H "Content-Type: application/json" \
  -d '{
    "user": {
      "email": "test@example.com",
      "password": "Password123"
    }
  }'

# Get public key
curl http://localhost:3000/api/v1/public_keys/show

# Health check
curl http://localhost:3000/health
```

### 4. Stop Services

```bash
# Stop containers
docker-compose down

# Remove volumes (⚠️ deletes data)
docker-compose down -v
```

---

## Kubernetes Deployment

### 1. Update Configuration

Edit `k8s/02-configmap.yaml`:
```yaml
data:
  CORS_ALLOWED_ORIGINS: "yourdomain.com,api.yourdomain.com"
  # ... other settings
```

Edit `k8s/03-secret.yaml`:
```yaml
stringData:
  DB_USERNAME: "your_username"
  DB_PASSWORD: "your_secure_password"
  SECRET_KEY_BASE: "your_rails_secret"
  DEVISE_JWT_SECRET_KEY: "your_jwt_secret"
```

Edit `k8s/06-application.yaml`:
```yaml
image: YOUR_AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com/auth-service:latest
```

Edit `k8s/07-ingress.yaml`:
```yaml
rules:
  - host: auth.yourdomain.com
    http:
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: auth-service-app
              port:
                number: 80
```

### 2. Create Storage Class (if needed)

```bash
# For local storage on self-managed cluster
cat << EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
EOF
```

### 3. Deploy Using Script

```bash
# Make script executable
chmod +x k8s-deploy.sh

# Deploy to Kubernetes
./k8s-deploy.sh deploy

# Check status
./k8s-deploy.sh status

# View logs
./k8s-deploy.sh logs

# Run migrations
./k8s-deploy.sh migrate
```

### 4. Manual Kubernetes Deployment

```bash
# Create namespace
kubectl create namespace auth-service

# Create secrets
kubectl create secret generic auth-service-secrets \
  --from-literal=DB_USERNAME=auth_user \
  --from-literal=DB_PASSWORD=$(openssl rand -base64 32) \
  --from-literal=SECRET_KEY_BASE=$(openssl rand -hex 32) \
  --from-literal=DEVISE_JWT_SECRET_KEY=$(openssl rand -base64 32) \
  -n auth-service

# Apply configs
kubectl apply -f k8s/02-configmap.yaml

# Apply volumes
kubectl apply -f k8s/04-volumes.yaml

# Note: Volumes must have valid nodeAffinity if using local-storage
# Edit k8s/04-volumes.yaml to match your node names

# Apply database
kubectl apply -f k8s/05-database.yaml

# Wait for database
kubectl wait --for=condition=ready pod -l component=mysql -n auth-service --timeout=300s

# Apply application
kubectl apply -f k8s/06-application.yaml

# Apply ingress
kubectl apply -f k8s/07-ingress.yaml

# Check deployment
kubectl get all -n auth-service
```

### 5. Verify Deployment

```bash
# Check pods
kubectl get pods -n auth-service -w

# Check services
kubectl get svc -n auth-service

# Check ingress
kubectl get ingress -n auth-service

# Describe deployment
kubectl describe deployment auth-service-app -n auth-service

# Check logs
kubectl logs -f deployment/auth-service-app -n auth-service
```

---

## Production Configuration

### 1. Database Configuration

**Option A: AWS RDS**
```yaml
# In k8s/02-configmap.yaml
DB_HOST: "auth-service-prod.c2eftr8dv7fq.us-east-1.rds.amazonaws.com"
DB_PORT: "3306"
DB_NAME: "auth_service_production"
```

**Option B: Self-managed MySQL**
```yaml
# Ensure MySQL pod is configured for persistence
# Update k8s/04-volumes.yaml with proper storage backend
# Consider using EBS volumes instead of local storage

apiVersion: aws.amazon.com/v1
kind: BlockStore
metadata:
  name: auth-service-mysql-ebs
spec:
  availabilityZone: us-east-1a
  size: 100Gi
```

### 2. SSL/TLS Configuration

**Using AWS ALB Ingress:**
```yaml
# k8s/07-ingress.yaml
annotations:
  alb.ingress.kubernetes.io/certificate-arn: "arn:aws:acm:region:account:certificate/xxx"
  alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
  alb.ingress.kubernetes.io/ssl-redirect: '443'
```

**Using Nginx + Cert-Manager:**
```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace

# Create ClusterIssuer
kubectl apply -f - << EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF

# Update ingress annotations
# cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

### 3. Resource Limits

Production-recommended resource allocation:

```yaml
# In k8s/06-application.yaml
resources:
  requests:
    memory: "1Gi"      # Minimum memory
    cpu: "500m"        # Minimum CPU
  limits:
    memory: "2Gi"      # Maximum memory
    cpu: "1000m"       # Maximum CPU
```

### 4. High Availability

```yaml
# Minimum 3 replicas
replicas: 3

# Pod Disruption Budget
minAvailable: 1

# Pod Anti-Affinity
podAntiAffinity:
  requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
          - key: app
            operator: In
            values:
              - auth-service
      topologyKey: kubernetes.io/hostname
```

### 5. Monitoring & Logging

```bash
# Install Prometheus (if not already installed)
helm install prometheus prometheus-community/kube-prometheus-stack

# Apply monitoring manifests
kubectl apply -f k8s/08-monitoring.yaml

# Install ELK Stack or CloudWatch
# Configure log aggregation
```

### 6. Backup & Disaster Recovery

```bash
# Create backup of persistent volumes
kubectl get pvc -n auth-service
aws ec2 create-snapshot --volume-id vol-xxxxx

# Setup automated backups
# Use Velero for cluster-level backups
helm install velero vmware-tanzu/velero --namespace velero --create-namespace

# Database backups
kubectl exec -it auth-service-mysql-0 -n auth-service -- mysqldump -u root -p auth_service_production | gzip > backup.sql.gz
```

---

## Troubleshooting

### Common Issues

#### 1. Pods stuck in `Pending` state

```bash
# Check events
kubectl describe pod <pod-name> -n auth-service

# Common causes:
# - Insufficient resources
# - Node affinity not matching
# - PVC not bound

# Check node availability
kubectl get nodes

# Update node affinity if needed
kubectl edit deployment auth-service-app -n auth-service
```

#### 2. ImagePullBackOff error

```bash
# Check image registry access
aws ecr describe-images --repository-name auth-service

# Verify credentials
kubectl get secrets -n auth-service

# Create/update image pull secret
kubectl create secret docker-registry ecr-secret \
  --docker-server=YOUR_ECR \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password) \
  -n auth-service

# Update deployment to use secret
# imagePullSecrets:
#   - name: ecr-secret
```

#### 3. Database connection failures

```bash
# Check MySQL pod status
kubectl get pods -l component=mysql -n auth-service

# View database logs
kubectl logs -f deployment/auth-service-mysql -n auth-service

# Test connection from app pod
kubectl exec -it <app-pod> -n auth-service -- \
  mysql -h auth-service-mysql -u auth_service_user -p auth_service_production

# Check connectivity
kubectl exec -it <app-pod> -n auth-service -- \
  wget -qO- auth-service-mysql:3306
```

#### 4. Migrations failing

```bash
# Check application logs
./k8s-deploy.sh logs

# Run migrations manually
./k8s-deploy.sh migrate

# Or manually:
kubectl exec -it <app-pod> -n auth-service -- \
  bundle exec rails db:migrate

# Rollback migrations if needed
kubectl exec -it <app-pod> -n auth-service -- \
  bundle exec rails db:rollback
```

#### 5. Ingress not working

```bash
# Check ingress status
kubectl describe ingress auth-service-ingress -n auth-service

# For AWS ALB:
# Check if ALB was created
aws elbv2 describe-load-balancers | grep auth-service

# Check ingress controller logs
kubectl logs -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller

# For Nginx:
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx
```

### Debug Commands

```bash
# Get all resources in namespace
kubectl get all -n auth-service

# Describe resource
kubectl describe pod <pod-name> -n auth-service

# View events
kubectl get events -n auth-service --sort-by='.lastTimestamp'

# Port forward for local testing
kubectl port-forward svc/auth-service-app 3000:80 -n auth-service

# SSH into pod
kubectl exec -it <pod-name> -n auth-service -- /bin/bash

# Check resource usage
kubectl top nodes
kubectl top pods -n auth-service

# View persistent volumes
kubectl get pv,pvc -n auth-service

# Check ConfigMaps and Secrets
kubectl get cm,secrets -n auth-service
```

### Performance Tuning

```bash
# Increase replicas for load
kubectl scale deployment auth-service-app --replicas=5 -n auth-service

# Adjust resource limits
kubectl set resources deployment auth-service-app \
  --limits=cpu=1,memory=2Gi \
  --requests=cpu=500m,memory=1Gi \
  -n auth-service

# Check HPA status
kubectl get hpa -n auth-service
kubectl describe hpa auth-service-app-hpa -n auth-service
```

---

## Cleanup

```bash
# Delete entire namespace (all resources)
kubectl delete namespace auth-service

# Delete specific resources
kubectl delete deployment auth-service-app -n auth-service
kubectl delete pvc --all -n auth-service
kubectl delete pv --all

# Using script
./k8s-deploy.sh destroy
```

---

## Summary

This setup provides:
- ✅ Multi-stage Docker builds for optimization
- ✅ Docker Compose for local development
- ✅ Complete Kubernetes manifests for production
- ✅ High availability (3+ replicas, pod affinity)
- ✅ Database persistence with PVCs
- ✅ Self-managed SSL/TLS
- ✅ Health checks and readiness probes
- ✅ Monitoring and alerting ready
- ✅ Network policies for security
- ✅ Automated deployment scripts

For questions or issues, refer to the main README.md and inline manifest comments.
