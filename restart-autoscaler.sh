#!/bin/bash
# Save this as: restart-autoscaler.sh

echo "🚀 Restarting Hybrid Autoscaler System"
echo "======================================"

# Step 1: Start k3s (if stopped)
echo "▶ Starting k3s..."
sudo systemctl start k3s
sleep 5

# Step 2: Verify k3s is running
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ k3s is not running properly"
    exit 1
fi
echo "✓ k3s is running"

# Step 3: Check if Prometheus is running
echo "▶ Checking Prometheus..."
PROM_POD=$(kubectl get pods -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$PROM_POD" ]; then
    echo "❌ Prometheus not found. Reinstalling..."
    helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
    helm repo update
    helm install prometheus prometheus-community/prometheus \
        --set alertmanager.enabled=false \
        --set pushgateway.enabled=false \
        --set nodeExporter.enabled=false
    
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus --timeout=180s
fi
echo "✓ Prometheus is running"

# Step 4: Check if autoscaler deployment exists
echo "▶ Checking autoscaler..."
if ! kubectl get deployment reactive-autoscaler &> /dev/null; then
    echo "❌ Autoscaler not deployed. Deploying..."
    cd ~/final
    kubectl apply -f rbac.yaml
    kubectl apply -f config.yaml
    kubectl apply -f deployment.yaml
    kubectl wait --for=condition=ready pod -l app=reactive-autoscaler --timeout=60s
fi
echo "✓ Autoscaler is deployed"

# Step 5: Check if demo app exists
echo "▶ Checking demo app..."
if ! kubectl get deployment frontend &> /dev/null; then
    echo "❌ Demo app not deployed. Deploying..."
    cd ~/final
    kubectl apply -f demo-app.yaml
    kubectl wait --for=condition=ready pod -l app=frontend --timeout=120s
fi
echo "✓ Demo app is running"

# Step 6: Verify everything
echo ""
echo "======================================"
echo "✅ SYSTEM STATUS"
echo "======================================"
kubectl get pods
echo ""
echo "🎯 Quick Commands:"
echo "  Watch autoscaler: kubectl logs -f deployment/reactive-autoscaler"
echo "  Watch deployments: kubectl get deployment frontend --watch"
echo "  Generate load: ./generate-load.sh"
echo ""
