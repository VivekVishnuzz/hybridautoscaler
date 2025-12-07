#!/bin/bash

# ========================================================================
# Live Reactive Autoscaler - Complete Deployment Script
# ========================================================================
# This script deploys the autoscaler to a Kubernetes cluster
# Follows the deployment guide from the PDF
# ========================================================================

set -e

echo "🚀 Live Reactive Autoscaler - Deployment Script"
echo "================================================"
echo ""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
REGISTRY="${REGISTRY:-your-registry}"
IMAGE_TAG="${IMAGE_TAG:-v1}"
NAMESPACE="${NAMESPACE:-default}"
DOCKER_BUILD="${DOCKER_BUILD:-true}"
DOCKER_PUSH="${DOCKER_PUSH:-true}"

# Functions
print_section() {
    echo ""
    echo -e "${BLUE}▶ $1${NC}"
    echo "---"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

check_prerequisites() {
    print_section "Checking Prerequisites"
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed"
        exit 1
    fi
    print_success "kubectl found"
    
    # Check if connected to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Not connected to a Kubernetes cluster"
        exit 1
    fi
    print_success "Connected to Kubernetes cluster"
    
    # Get cluster info
    CLUSTER_NAME=$(kubectl config current-context)
    echo "   Cluster: $CLUSTER_NAME"
    
    # Check if Prometheus is deployed
    if kubectl get deployment prometheus -n $NAMESPACE &> /dev/null 2>&1 || \
       kubectl get deployment prometheus-server -n $NAMESPACE &> /dev/null 2>&1; then
        print_success "Prometheus found in cluster"
    else
        print_warning "Prometheus not found - you may need to deploy it"
        echo "   Quick Prometheus setup:"
        echo "   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts"
        echo "   helm install prometheus prometheus-community/prometheus -n $NAMESPACE"
    fi
}

build_docker_image() {
    if [ "$DOCKER_BUILD" != "true" ]; then
        print_warning "Skipping Docker build (DOCKER_BUILD=false)"
        return
    fi
    
    print_section "Building Docker Image"
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        return 1
    fi
    
    IMAGE_NAME="$REGISTRY/reactive-autoscaler:$IMAGE_TAG"
    echo "   Building: $IMAGE_NAME"
    
    if docker build -t "$IMAGE_NAME" .; then
        print_success "Docker image built successfully"
    else
        print_error "Failed to build Docker image"
        return 1
    fi
    
    if [ "$DOCKER_PUSH" = "true" ]; then
        echo "   Pushing to registry..."
        if docker push "$IMAGE_NAME"; then
            print_success "Docker image pushed successfully"
        else
            print_error "Failed to push Docker image"
            return 1
        fi
    fi
}

deploy_rbac() {
    print_section "Deploying RBAC Configuration"
    
    echo "   Creating ServiceAccount, Role, and RoleBinding..."
    if kubectl apply -f rbac.yaml -n $NAMESPACE; then
        print_success "RBAC configuration deployed"
    else
        print_error "Failed to deploy RBAC"
        return 1
    fi
    
    # Verify RBAC
    if kubectl get serviceaccount autoscaler -n $NAMESPACE &> /dev/null; then
        print_success "ServiceAccount 'autoscaler' created"
    fi
}

deploy_config() {
    print_section "Deploying ConfigMap"
    
    echo "   Creating configuration..."
    if kubectl apply -f config.yaml -n $NAMESPACE; then
        print_success "ConfigMap deployed"
    else
        print_error "Failed to deploy ConfigMap"
        return 1
    fi
    
    # Verify config
    if kubectl get configmap autoscaler-config -n $NAMESPACE &> /dev/null; then
        print_success "ConfigMap 'autoscaler-config' created"
    fi
}

deploy_autoscaler() {
    print_section "Deploying Autoscaler"
    
    # Update deployment with correct image
    TEMP_DEPLOYMENT=$(mktemp)
    sed "s|your-registry/reactive-autoscaler:v1|$REGISTRY/reactive-autoscaler:$IMAGE_TAG|g" deployment.yaml > "$TEMP_DEPLOYMENT"
    
    echo "   Deploying autoscaler pod..."
    if kubectl apply -f "$TEMP_DEPLOYMENT" -n $NAMESPACE; then
        print_success "Autoscaler deployment created"
    else
        print_error "Failed to deploy autoscaler"
        rm "$TEMP_DEPLOYMENT"
        return 1
    fi
    
    rm "$TEMP_DEPLOYMENT"
}

verify_deployment() {
    print_section "Verifying Deployment"
    
    echo "   Waiting for autoscaler pod to start..."
    for i in {1..30}; do
        if kubectl get pod -l app=reactive-autoscaler -n $NAMESPACE 2>/dev/null | grep -q "Running"; then
            print_success "Autoscaler pod is running"
            break
        fi
        
        if [ $i -eq 30 ]; then
            print_warning "Autoscaler pod did not start within 30 seconds"
            echo "   Checking pod status..."
            kubectl get pods -l app=reactive-autoscaler -n $NAMESPACE
            return 1
        fi
        
        echo "   Waiting... ($i/30)"
        sleep 1
    done
    
    # Get pod name
    POD_NAME=$(kubectl get pod -l app=reactive-autoscaler -n $NAMESPACE -o jsonpath='{.items[0].metadata.name}')
    echo "   Pod name: $POD_NAME"
    
    # Check logs
    echo ""
    echo "   Recent logs:"
    kubectl logs "$POD_NAME" -n $NAMESPACE --tail=20 2>/dev/null || echo "   (Logs not yet available)"
}

show_commands() {
    print_section "Useful Commands"
    
    echo ""
    echo "📋 Monitor autoscaler:"
    echo "   kubectl logs -f deployment/reactive-autoscaler -n $NAMESPACE"
    echo ""
    echo "📊 View pod status:"
    echo "   kubectl get pods -l app=reactive-autoscaler -n $NAMESPACE"
    echo ""
    echo "🔧 View configuration:"
    echo "   kubectl get configmap autoscaler-config -n $NAMESPACE -o yaml"
    echo ""
    echo "📈 Watch scaling in action:"
    echo "   kubectl get deployment --watch"
    echo ""
    echo "🗑️  Remove deployment:"
    echo "   kubectl delete deployment reactive-autoscaler -n $NAMESPACE"
    echo "   kubectl delete configmap autoscaler-config -n $NAMESPACE"
    echo "   kubectl delete rolebinding autoscaler-binding -n $NAMESPACE"
    echo "   kubectl delete role autoscaler-role -n $NAMESPACE"
    echo "   kubectl delete serviceaccount autoscaler -n $NAMESPACE"
}

# Main execution
main() {
    echo -e "${BLUE}========================================${NC}"
    echo "Configuration:"
    echo "  Namespace: $NAMESPACE"
    echo "  Registry: $REGISTRY"
    echo "  Image Tag: $IMAGE_TAG"
    echo "  Docker Build: $DOCKER_BUILD"
    echo "  Docker Push: $DOCKER_PUSH"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    
    check_prerequisites
    build_docker_image
    deploy_rbac
    deploy_config
    deploy_autoscaler
    verify_deployment
    show_commands
    
    echo ""
    echo -e "${GREEN}✅ Deployment Complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Monitor the logs: kubectl logs -f deployment/reactive-autoscaler"
    echo "2. Create test deployments with Prometheus metrics"
    echo "3. The autoscaler will automatically scale them based on RPS"
    echo ""
}

# Run main
main "$@"
