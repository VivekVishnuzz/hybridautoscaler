#!/bin/bash
# COMPLETE SETUP: From Nothing to Working Autoscaler
# Installs: k3s + kubectl + Prometheus + Test Apps + Your Autoscaler
# Requirements: Ubuntu/Debian, 2GB RAM minimum

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
}

print_step() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    print_error "Don't run as root! Run as normal user. Script will ask for sudo when needed."
fi

print_header "🚀 COMPLETE AUTOSCALER SETUP - ZERO TO HERO"
echo ""
echo "This script will install:"
echo "  ✓ k3s (Lightweight Kubernetes)"
echo "  ✓ kubectl (Kubernetes CLI)"
echo "  ✓ Helm (Package manager)"
echo "  ✓ Prometheus (Metrics)"
echo "  ✓ Test microservices with metrics"
echo "  ✓ Your reactive autoscaler"
echo ""
echo "System Requirements:"
echo "  • Ubuntu/Debian (or similar)"
echo "  • 2GB RAM minimum"
echo "  • 10GB disk space"
echo ""
read -p "Continue? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
fi

# ==================== STEP 1: Install k3s ====================
print_header "STEP 1: Installing k3s (Lightweight Kubernetes)"

if command -v k3s &> /dev/null; then
    print_success "k3s already installed"
else
    print_step "Downloading and installing k3s..."
    curl -sfL https://get.k3s.io | sh -s - --write-kubeconfig-mode 644
    
    # Wait for k3s to be ready
    print_step "Waiting for k3s to start..."
    sudo systemctl enable k3s
    sudo systemctl start k3s
    sleep 10
    
    print_success "k3s installed successfully!"
fi

# ==================== STEP 2: Setup kubectl ====================
print_header "STEP 2: Setting up kubectl"

# k3s installs kubectl, but we need to configure it
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
chmod 600 ~/.kube/config

# Add to bashrc for persistence
if ! grep -q "KUBECONFIG" ~/.bashrc; then
    echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
fi

print_step "Testing kubectl..."
kubectl cluster-info
kubectl get nodes

print_success "kubectl configured and working!"

# ==================== STEP 3: Install Helm ====================
print_header "STEP 3: Installing Helm"

if command -v helm &> /dev/null; then
    print_success "Helm already installed"
else
    print_step "Installing Helm..."
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    print_success "Helm installed!"
fi

# ==================== STEP 4: Install Prometheus (Lightweight) ====================
print_header "STEP 4: Installing Prometheus (Lightweight Version)"

print_step "Adding Prometheus Helm repository..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Check if Prometheus is already installed
if helm list | grep -q prometheus; then
    print_success "Prometheus already installed"
else
    print_step "Installing Prometheus (minimal config, saves RAM)..."
    
    # Install with minimal components to save memory
    helm install prometheus prometheus-community/prometheus \
        --set alertmanager.enabled=false \
        --set pushgateway.enabled=false \
        --set nodeExporter.enabled=false \
        --set kubeStateMetrics.enabled=false \
        --set server.persistentVolume.enabled=false \
        --set server.retention=2h
    
    print_step "Waiting for Prometheus to be ready..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=prometheus --timeout=180s
    
    print_success "Prometheus installed and running!"
fi

PROM_SERVICE=$(kubectl get svc -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}')
print_success "Prometheus service: $PROM_SERVICE"

# ==================== STEP 5: Deploy Test Microservices ====================
print_header "STEP 5: Deploying Test Microservices with Metrics"

print_step "Creating test microservices..."

cat > test-microservices.yaml <<'EOF'
# Frontend Service with Metrics
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  replicas: 1
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "80"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: app
        image: nginxdemos/nginx-hello:latest
        ports:
        - containerPort: 8080
          name: http
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: frontend
  labels:
    app: frontend
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: frontend
---
# Checkout Service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkoutservice
  labels:
    app: checkoutservice
spec:
  replicas: 1
  selector:
    matchLabels:
      app: checkoutservice
  template:
    metadata:
      labels:
        app: checkoutservice
      annotations:
        prometheus.io/scrape: "true"
    spec:
      containers:
      - name: app
        image: nginxdemos/nginx-hello:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: checkoutservice
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: checkoutservice
---
# Recommendation Service
apiVersion: apps/v1
kind: Deployment
metadata:
  name: recommendationservice
  labels:
    app: recommendationservice
spec:
  replicas: 1
  selector:
    matchLabels:
      app: recommendationservice
  template:
    metadata:
      labels:
        app: recommendationservice
      annotations:
        prometheus.io/scrape: "true"
    spec:
      containers:
      - name: app
        image: nginxdemos/nginx-hello:latest
        ports:
        - containerPort: 8080
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
---
apiVersion: v1
kind: Service
metadata:
  name: recommendationservice
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    app: recommendationservice
EOF

kubectl apply -f test-microservices.yaml

print_step "Waiting for services to be ready..."
kubectl wait --for=condition=ready pod -l app=frontend --timeout=60s
kubectl wait --for=condition=ready pod -l app=checkoutservice --timeout=60s
kubectl wait --for=condition=ready pod -l app=recommendationservice --timeout=60s

print_success "Test microservices deployed!"

# ==================== STEP 6: Configure Prometheus for Services ====================
print_header "STEP 6: Configuring Prometheus to Monitor Services"

print_step "Updating Prometheus config..."

cat > prometheus-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: prometheus-server
data:
  prometheus.yml: |
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    
    scrape_configs:
      - job_name: 'kubernetes-pods'
        kubernetes_sd_configs:
        - role: pod
        relabel_configs:
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
          action: keep
          regex: true
        - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
          action: replace
          target_label: __metrics_path__
          regex: (.+)
        - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
          action: replace
          regex: ([^:]+)(?::\d+)?;(\d+)
          replacement: \$1:\$2
          target_label: __address__
        - action: labelmap
          regex: __meta_kubernetes_pod_label_(.+)
        - source_labels: [__meta_kubernetes_namespace]
          action: replace
          target_label: kubernetes_namespace
        - source_labels: [__meta_kubernetes_pod_name]
          action: replace
          target_label: kubernetes_pod_name
EOF

kubectl apply -f prometheus-config.yaml
kubectl rollout restart deployment prometheus-server 2>/dev/null || true

print_success "Prometheus configured to scrape pod metrics!"

# ==================== STEP 7: Prepare Autoscaler Files ====================
print_header "STEP 7: Preparing Autoscaler Deployment Files"

# Check if files exist in current directory
if [ ! -f "reactive.py" ]; then
    print_warning "reactive.py not found in current directory"
    echo "Please make sure you're in the ~/final directory with your autoscaler files"
    exit 1
fi

# Update deployment.yaml with correct Prometheus URL
if [ -f "deployment.yaml" ]; then
    print_step "Updating deployment.yaml with Prometheus URL..."
    
    # Backup
    cp deployment.yaml deployment.yaml.backup 2>/dev/null || true
    
    # Update Prometheus URL
    sed -i "s|http://prometheus-server:9090|http://${PROM_SERVICE}:80|g" deployment.yaml
    
    # For k3s, we don't need to push to registry - we can build locally
    sed -i 's|imagePullPolicy: Always|imagePullPolicy: Never|g' deployment.yaml
    sed -i 's|image:.*reactive-autoscaler.*|image: reactive-autoscaler:v1|g' deployment.yaml
    
    print_success "deployment.yaml updated"
fi

# ==================== STEP 8: Build Autoscaler Docker Image ====================
print_header "STEP 8: Building Autoscaler Docker Image"

if [ ! -f "Dockerfile" ]; then
    print_error "Dockerfile not found!"
fi

print_step "Building Docker image (this may take a minute)..."

# k3s uses containerd, we need to import image differently
sudo docker build -t reactive-autoscaler:v1 . || {
    # If docker not available, use k3s ctr
    sudo k3s ctr images import reactive-autoscaler:v1
}

# Import to k3s
if command -v docker &> /dev/null; then
    sudo docker save reactive-autoscaler:v1 | sudo k3s ctr images import -
fi

print_success "Docker image built and imported to k3s!"

# ==================== STEP 9: Deploy Autoscaler ====================
print_header "STEP 9: Deploying Reactive Autoscaler"

# Apply RBAC
if [ -f "rbac.yaml" ]; then
    print_step "Applying RBAC..."
    kubectl apply -f rbac.yaml
    print_success "RBAC applied"
fi

# Apply ConfigMap
if [ -f "config.yaml" ]; then
    print_step "Applying ConfigMap..."
    kubectl apply -f config.yaml
    print_success "ConfigMap applied"
fi

# Apply Deployment
if [ -f "deployment.yaml" ]; then
    print_step "Deploying autoscaler..."
    kubectl apply -f deployment.yaml
    
    print_step "Waiting for autoscaler to start..."
    sleep 10
    kubectl wait --for=condition=ready pod -l app=reactive-autoscaler --timeout=60s 2>/dev/null || {
        print_warning "Autoscaler taking longer than expected..."
    }
    
    print_success "Autoscaler deployed!"
fi

# ==================== STEP 10: Verify Everything ====================
print_header "STEP 10: Verification & Status Check"

echo ""
echo "=== Cluster Status ==="
kubectl get nodes
echo ""

echo "=== All Deployments ==="
kubectl get deployments
echo ""

echo "=== All Pods ==="
kubectl get pods
echo ""

echo "=== Autoscaler Logs (last 20 lines) ==="
POD=$(kubectl get pods -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -n "$POD" ]; then
    kubectl logs "$POD" --tail=20 2>/dev/null || echo "Logs not available yet..."
else
    print_warning "Autoscaler pod not found yet"
fi

# ==================== STEP 11: Create Helper Scripts ====================
print_header "STEP 11: Creating Helper Scripts"

# Watch script
cat > watch-autoscaler.sh <<'WATCHSCRIPT'
#!/bin/bash
POD=$(kubectl get pods -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}')
echo "Watching autoscaler: $POD"
kubectl logs -f "$POD" | grep --color=auto -E 'UPSCALE|DOWNSCALE|ERROR|$'
WATCHSCRIPT
chmod +x watch-autoscaler.sh

# Load generator script
cat > generate-load.sh <<'LOADSCRIPT'
#!/bin/bash
echo "Generating load on frontend service..."
echo "Press Ctrl+C to stop"
kubectl run load-gen --rm -i --tty --image=busybox --restart=Never -- sh -c \
  'while true; do 
     for i in $(seq 1 10); do
       wget -q -O- http://frontend.default.svc.cluster.local &
     done
     sleep 1
   done'
LOADSCRIPT
chmod +x generate-load.sh

# Status check script
cat > check-status.sh <<'STATUSSCRIPT'
#!/bin/bash
echo "=== Autoscaler Status ==="
kubectl get pods -l app=reactive-autoscaler
echo ""
echo "=== Service Deployments ==="
kubectl get deployments frontend checkoutservice recommendationservice
echo ""
echo "=== Recent Scaling Events ==="
kubectl logs deployment/reactive-autoscaler --tail=50 | grep -E 'UPSCALE|DOWNSCALE' || echo "No scaling events yet"
STATUSSCRIPT
chmod +x check-status.sh

print_success "Helper scripts created!"

# ==================== SUCCESS ====================
print_header "✅ SETUP COMPLETE!"

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║           🎉 EVERYTHING IS READY! 🎉                  ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📊 What's Running:"
echo "  ✓ k3s Kubernetes cluster"
echo "  ✓ Prometheus monitoring"
echo "  ✓ 3 test microservices (frontend, checkout, recommendation)"
echo "  ✓ Your reactive autoscaler"
echo ""
echo "🎯 Next Steps - Try These Commands:"
echo ""
echo "1️⃣  Watch autoscaler in real-time:"
echo "   ./watch-autoscaler.sh"
echo ""
echo "2️⃣  Generate load to trigger scaling (in another terminal):"
echo "   ./generate-load.sh"
echo ""
echo "3️⃣  Watch deployments scale:"
echo "   kubectl get deployment frontend --watch"
echo ""
echo "4️⃣  Check status anytime:"
echo "   ./check-status.sh"
echo ""
echo "5️⃣  View Prometheus UI:"
echo "   kubectl port-forward svc/${PROM_SERVICE} 9090:80"
echo "   Then open: http://localhost:9090"
echo ""
echo "📝 Useful Commands:"
echo "   kubectl get pods                    # See all pods"
echo "   kubectl get deployments             # See deployments"
echo "   kubectl logs -f deployment/reactive-autoscaler  # Live logs"
echo ""
echo "🧪 Expected Behavior:"
echo "   • Without load: Services stay at 1 replica"
echo "   • With load: Services scale up to 2-5 replicas"
echo "   • Load stops: Services scale back down after cooldown"
echo ""
echo "🗑️  To Clean Up Later:"
echo "   kubectl delete -f test-microservices.yaml"
echo "   kubectl delete -f deployment.yaml"
echo "   helm uninstall prometheus"
echo "   sudo /usr/local/bin/k3s-uninstall.sh"
echo ""
echo "Happy auto-scaling! 🚀"
echo ""