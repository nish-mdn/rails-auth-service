#!/bin/bash

# Kubernetes Deployment Script for Auth Service
# Usage: ./k8s-deploy.sh [deploy|destroy|logs|status]

set -e

# Configuration
NAMESPACE="auth-service"
KUBECONFIG="${KUBECONFIG:-~/.kube/config}"
ECR_REGISTRY="${ECR_REGISTRY:-YOUR_AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com}"
IMAGE_NAME="auth-service"
IMAGE_TAG="${IMAGE_TAG:-latest}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    
    # Check kubeconfig
    if [ ! -f "$KUBECONFIG" ]; then
        log_error "kubeconfig not found at $KUBECONFIG"
        exit 1
    fi
    
    # Check AWS CLI (optional but recommended)
    if ! command -v aws &> /dev/null; then
        log_warn "AWS CLI is not installed (recommended for ECR operations)"
    fi
    
    log_info "Prerequisites check passed"
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

create_secrets() {
    log_info "Creating secrets..."
    
    # Check if secret already exists
    if kubectl get secret auth-service-secrets -n "$NAMESPACE" &> /dev/null; then
        log_warn "Secret 'auth-service-secrets' already exists, skipping creation"
        return
    fi
    
    # Generate secure values
    local db_password=$(openssl rand -base64 32)
    local secret_key_base=$(openssl rand -hex 32)
    local jwt_secret=$(openssl rand -base64 32)
    
    # Create secret
    kubectl create secret generic auth-service-secrets \
        --from-literal=DB_USERNAME=auth_service_user \
        --from-literal=DB_PASSWORD="$db_password" \
        --from-literal=SECRET_KEY_BASE="$secret_key_base" \
        --from-literal=DEVISE_JWT_SECRET_KEY="$jwt_secret" \
        -n "$NAMESPACE"
    
    log_info "Secrets created successfully"
    log_warn "Store these values securely:"
    log_warn "  DB_PASSWORD: $db_password"
    log_warn "  SECRET_KEY_BASE: $secret_key_base"
    log_warn "  DEVISE_JWT_SECRET_KEY: $jwt_secret"
}

update_image_registry() {
    log_info "Updating image registry in manifests..."
    
    # Update the image reference in application.yaml
    sed -i.bak "s|YOUR_AWS_ECR_REGISTRY/auth-service|${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}|g" k8s/06-application.yaml
    
    log_info "Image registry updated to: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
}

deploy_manifests() {
    log_info "Deploying Kubernetes manifests..."
    
    # Apply manifests in order
    kubectl apply -f k8s/01-namespace.yaml
    log_info "✓ Namespace created"
    
    kubectl apply -f k8s/02-configmap.yaml
    log_info "✓ ConfigMap created"
    
    # Secrets should already exist
    # kubectl apply -f k8s/03-secret.yaml
    
    kubectl apply -f k8s/04-volumes.yaml
    log_info "✓ Volumes created"
    
    kubectl apply -f k8s/05-database.yaml
    log_info "✓ Database services deployed"
    
    kubectl apply -f k8s/06-application.yaml
    log_info "✓ Application deployed"
    
    kubectl apply -f k8s/07-ingress.yaml
    log_info "✓ Ingress configured"
    
    kubectl apply -f k8s/09-rbac.yaml
    log_info "✓ RBAC configured"
    
    # Monitoring (optional)
    if [ "${ENABLE_MONITORING:-false}" = "true" ]; then
        kubectl apply -f k8s/08-monitoring.yaml
        log_info "✓ Monitoring configured"
    fi
    
    log_info "All manifests deployed successfully"
}

wait_for_deployment() {
    log_info "Waiting for deployment to be ready..."
    
    kubectl wait --for=condition=available --timeout=600s \
        deployment/auth-service-app -n "$NAMESPACE"
    
    log_info "Deployment is ready"
}

check_deployment_status() {
    log_info "Checking deployment status..."
    
    # Check pods
    echo ""
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE" -o wide
    
    echo ""
    echo "Services:"
    kubectl get svc -n "$NAMESPACE"
    
    echo ""
    echo "Ingress:"
    kubectl get ingress -n "$NAMESPACE"
    
    echo ""
    echo "Deployment Status:"
    kubectl describe deployment auth-service-app -n "$NAMESPACE"
}

view_logs() {
    local pod=${1:-}
    
    if [ -z "$pod" ]; then
        # Get the first pod
        pod=$(kubectl get pods -n "$NAMESPACE" -l app=auth-service,component=application -o jsonpath='{.items[0].metadata.name}')
    fi
    
    if [ -z "$pod" ]; then
        log_error "No pods found"
        exit 1
    fi
    
    log_info "Viewing logs for pod: $pod"
    kubectl logs -f "$pod" -n "$NAMESPACE"
}

run_migrations() {
    log_info "Running database migrations..."
    
    local pod=$(kubectl get pods -n "$NAMESPACE" -l app=auth-service,component=application -o jsonpath='{.items[0].metadata.name}')
    
    if [ -z "$pod" ]; then
        log_error "No application pods found"
        exit 1
    fi
    
    kubectl exec -it "$pod" -n "$NAMESPACE" -- bundle exec rails db:migrate
    log_info "Migrations completed"
}

destroy_deployment() {
    log_warn "This will delete all resources in namespace: $NAMESPACE"
    read -p "Are you sure? (yes/no): " confirmation
    
    if [ "$confirmation" != "yes" ]; then
        log_info "Cancelled"
        return
    fi
    
    log_info "Destroying deployment..."
    kubectl delete namespace "$NAMESPACE"
    log_info "Namespace deleted"
}

print_ingress_info() {
    log_info "Ingress Information:"
    
    local ingress=$(kubectl get ingress auth-service-ingress -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    
    if [ -z "$ingress" ]; then
        log_warn "Ingress not yet assigned (may take a few minutes)"
        return
    fi
    
    echo "Access your application at: http://$ingress"
}

# Main script
main() {
    local command="${1:-deploy}"
    
    case "$command" in
        deploy)
            check_prerequisites
            create_namespace
            create_secrets
            update_image_registry
            deploy_manifests
            wait_for_deployment
            check_deployment_status
            print_ingress_info
            ;;
        status)
            check_deployment_status
            ;;
        logs)
            view_logs "${2:-}"
            ;;
        migrate)
            run_migrations
            ;;
        destroy)
            destroy_deployment
            ;;
        help|--help|-h)
            cat << EOF
Usage: ./k8s-deploy.sh [COMMAND] [OPTIONS]

Commands:
  deploy      Deploy all manifests to Kubernetes (default)
  status      Check deployment status
  logs        View application logs (optionally provide pod name)
  migrate     Run database migrations
  destroy     Delete all resources from Kubernetes
  help        Show this help message

Environment Variables:
  ECR_REGISTRY    AWS ECR registry (default: YOUR_AWS_ACCOUNT.dkr.ecr.us-east-1.amazonaws.com)
  IMAGE_TAG       Docker image tag (default: latest)
  KUBECONFIG      Path to kubeconfig file (default: ~/.kube/config)
  ENABLE_MONITORING  Enable Prometheus monitoring (default: false)

Examples:
  ./k8s-deploy.sh deploy
  ECR_REGISTRY=123456789.dkr.ecr.us-east-1.amazonaws.com ./k8s-deploy.sh deploy
  ./k8s-deploy.sh logs
  ./k8s-deploy.sh status
  ./k8s-deploy.sh migrate
EOF
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Run './k8s-deploy.sh help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
