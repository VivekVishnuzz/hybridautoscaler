#!/bin/bash
# Deploy a simple Python app that exposes Prometheus metrics
# This will let you see your autoscaler in action!

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

echo "=========================================="
echo "  DEPLOY DEMO APP WITH METRICS"
echo "=========================================="

print_step "Creating demo app with Prometheus metrics..."

# Create a simple Flask app with metrics
cat > demo-app.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: demo-app-code
data:
  app.py: |
    from flask import Flask, Response
    from prometheus_client import Counter, generate_latest, REGISTRY
    import time
    
    app = Flask(__name__)
    
    # Prometheus counter for tracking requests
    request_counter = Counter(
        'http_requests_total',
        'Total HTTP requests',
        ['service', 'endpoint']
    )
    
    @app.route('/')
    def index():
        request_counter.labels(service='frontend', endpoint='/').inc()
        time.sleep(0.01)  # Simulate some work
        return 'Hello from Demo App! This request was counted.\n'
    
    @app.route('/api')
    def api():
        request_counter.labels(service='frontend', endpoint='/api').inc()
        time.sleep(0.02)
        return 'API response\n'
    
    @app.route('/metrics')
    def metrics():
        return Response(generate_latest(REGISTRY), mimetype='text/plain')
    
    @app.route('/health')
    def health():
        return 'OK\n'
    
    if __name__ == '__main__':
        app.run(host='0.0.0.0', port=8080)
---
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
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
      - name: app
        image: python:3.11-slim
        command: ["/bin/sh", "-c"]
        args:
          - |
            pip install flask prometheus-client
            python /app/app.py
        ports:
        - containerPort: 8080
          name: http
        volumeMounts:
        - name: app-code
          mountPath: /app
        resources:
          requests:
            cpu: 50m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
      volumes:
      - name: app-code
        configMap:
          name: demo-app-code
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
EOF

print_success "Demo app manifest created"

print_step "Deleting old frontend deployment..."
kubectl delete deployment frontend --ignore-not-found=true
kubectl delete service frontend --ignore-not-found=true
sleep 3

print_step "Deploying demo app with metrics..."
kubectl apply -f demo-app.yaml

print_step "Waiting for app to be ready..."
sleep 10
kubectl wait --for=condition=ready pod -l app=frontend --timeout=120s

print_success "Demo app deployed!"

# Get pod name
POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')
print_success "App pod: $POD"

print_step "Testing metrics endpoint..."
sleep 5
kubectl exec $POD -- wget -q -O- http://localhost:8080/metrics | head -20

echo ""
print_step "Configuring Prometheus to scrape the app..."

# Prometheus should auto-discover the pod due to annotations
# Let's verify
sleep 10

echo ""
echo "=========================================="
print_success "SETUP COMPLETE!"
echo "=========================================="
echo ""
echo "🎯 Your demo app is running with Prometheus metrics!"
echo ""
echo "📊 Now let's see the autoscaler in action:"
echo ""
echo "Terminal 1 - Watch autoscaler logs:"
echo "  kubectl logs -f deployment/reactive-autoscaler | grep -E 'frontend|UPSCALE|DOWNSCALE'"
echo ""
echo "Terminal 2 - Generate traffic (start with this):"
echo "  kubectl run traffic-gen --rm -i --tty --image=busybox --restart=Never -- sh -c 'while true; do wget -q -O- http://frontend.default.svc.cluster.local; sleep 0.5; done'"
echo ""
echo "Terminal 3 - Watch frontend scale:"
echo "  kubectl get deployment frontend --watch"
echo ""
echo "🔥 What to expect:"
echo "  1. Initial RPS will be low → 1 replica"
echo "  2. As traffic increases → autoscaler sees RPS climbing"
echo "  3. When RPS > 30 → UPSCALE to 2 replicas"
echo "  4. When RPS > 60 → UPSCALE to 3 replicas"
echo "  5. Stop traffic → RPS drops → DOWNSCALE back to 1"
echo ""
echo "💡 To increase load faster:"
echo "  # Run multiple traffic generators"
echo "  for i in 1 2 3; do"
echo "    kubectl run traffic-gen-\$i --image=busybox --restart=Never -- sh -c 'while true; do wget -q -O- http://frontend; done' &"
echo "  done"
echo ""