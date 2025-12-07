# Live Reactive Autoscaler - Kubernetes Deployment Guide

## 📋 Overview

This autoscaler is universal and works with **any Kubernetes cluster**. It:

- ✅ Monitors any microservice with Prometheus metrics
- ✅ Scales Kubernetes deployments automatically
- ✅ Runs as a pod in your cluster
- ✅ Works with existing infrastructure

## 🏗️ Architecture

```
┌─────────────────────────────────────────┐
│  Your Microservices (Deployments)       │
│  - frontend, checkout, api, etc.        │
└────────────────┬────────────────────────┘
                 │ (metrics)
                 ↓
┌─────────────────────────────────────────┐
│  Prometheus - Metrics Collection        │
│  (Collects http_requests_total, etc.)   │
└────────────────┬────────────────────────┘
                 │ (query)
                 ↓
┌─────────────────────────────────────────┐
│  Reactive Autoscaler Pod                │
│  (This system - real-time decisions)    │
└────────────────┬────────────────────────┘
                 │ (scale)
                 ↓
┌─────────────────────────────────────────┐
│  Kubernetes API - Updates Replicas      │
│  (Scales deployments up/down)           │
└─────────────────────────────────────────┘
```

## 📦 Prerequisites

### 1. Kubernetes Cluster
Any K8s cluster will work:
- EKS (AWS)
- GKE (Google Cloud)
- AKS (Azure)
- Minikube (local testing)
- DigitalOcean Kubernetes
- Self-hosted clusters

Ensure `kubectl` is configured and working:
```bash
kubectl cluster-info
kubectl get nodes
```

### 2. Prometheus
Prometheus must be deployed in your cluster collecting metrics from your services.

**Quick Prometheus Setup** (if you don't have it):
```bash
# Using Helm (recommended)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/prometheus

# Or using kubectl
kubectl apply -f https://github.com/prometheus-operator/prometheus-operator/releases/download/v0.70.0/bundle.yaml
```

### 3. Service Metrics
Your services must expose metrics in Prometheus format.

**Example for Flask microservice:**
```python
from prometheus_client import Counter, generate_latest, REGISTRY

request_counter = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['service', 'method', 'endpoint']
)

@app.route('/metrics')
def metrics():
    request_counter.labels(service='frontend', method='GET', endpoint='/').inc()
    return generate_latest(REGISTRY)
```

**Example for FastAPI:**
```python
from prometheus_client import Counter, generate_latest

request_counter = Counter(
    'http_requests_total',
    'Total requests',
    ['service']
)

app = FastAPI()

@app.middleware("http")
async def add_metrics(request, call_next):
    request_counter.labels(service='api').inc()
    response = await call_next(request)
    return response

@app.get("/metrics")
async def metrics():
    return Response(generate_latest())
```

## 🚀 Deployment Steps

### Step 1: Prepare Your Files

The deployment includes:
- `reactive.py` - The autoscaler code
- `Dockerfile` - Docker image definition
- `rbac.yaml` - Kubernetes RBAC configuration
- `config.yaml` - ConfigMap with settings
- `deployment.yaml` - Kubernetes deployment manifest
- `deploy.sh` - Automated deployment script

All files are included in this directory.

### Step 2: Build and Push Docker Image

```bash
# Set your registry
export REGISTRY="your-dockerhub-username"  # or your-registry.azurecr.io, etc.
export IMAGE_TAG="v1"

# Build the image
docker build -t $REGISTRY/reactive-autoscaler:$IMAGE_TAG .

# Push to registry
docker push $REGISTRY/reactive-autoscaler:$IMAGE_TAG
```

**For different registries:**

```bash
# Docker Hub
export REGISTRY="myusername"
docker push myusername/reactive-autoscaler:v1

# Azure Container Registry
docker tag reactive-autoscaler:v1 myregistry.azurecr.io/reactive-autoscaler:v1
docker push myregistry.azurecr.io/reactive-autoscaler:v1

# AWS ECR
aws ecr get-login-password | docker login --username AWS --password-stdin 123456.dkr.ecr.us-east-1.amazonaws.com
docker tag reactive-autoscaler:v1 123456.dkr.ecr.us-east-1.amazonaws.com/reactive-autoscaler:v1
docker push 123456.dkr.ecr.us-east-1.amazonaws.com/reactive-autoscaler:v1

# Google Container Registry
docker tag reactive-autoscaler:v1 gcr.io/my-project/reactive-autoscaler:v1
docker push gcr.io/my-project/reactive-autoscaler:v1
```

### Step 3: Deploy to Kubernetes (Automated)

The easiest way - use the deployment script:

```bash
# Set environment variables
export REGISTRY="your-registry"
export IMAGE_TAG="v1"
export NAMESPACE="default"

# Make script executable
chmod +x deploy.sh

# Run deployment
./deploy.sh
```

This script will:
- ✅ Check prerequisites
- ✅ Build Docker image
- ✅ Deploy RBAC configuration
- ✅ Deploy ConfigMap
- ✅ Deploy autoscaler pod
- ✅ Verify deployment
- ✅ Show monitoring commands

### Step 4: Deploy to Kubernetes (Manual)

If you prefer manual steps:

**Create RBAC (permissions):**
```bash
kubectl apply -f rbac.yaml
```

**Create ConfigMap (configuration):**
```bash
kubectl apply -f config.yaml
```

**Update deployment image:**
Edit `deployment.yaml` and replace:
```yaml
image: your-registry/reactive-autoscaler:v1
```

**Deploy the autoscaler:**
```bash
kubectl apply -f deployment.yaml
```

### Step 5: Verify Deployment

```bash
# Check if pod is running
kubectl get pods -l app=reactive-autoscaler

# View logs
kubectl logs -f deployment/reactive-autoscaler

# Should see output like:
# 2024-12-06 10:00:00 - Autoscaler - INFO - 🚀 Live Reactive Autoscaler initialized
# 2024-12-06 10:00:02 - Autoscaler - INFO - Monitoring 3 services: [frontend, checkout, api]
```

## 🔧 Configuration

### Environment Variables

Edit `deployment.yaml` to customize:

```yaml
env:
  - name: PROMETHEUS_URL
    value: "http://prometheus-server:9090"
  - name: KUBERNETES_NAMESPACE
    value: "default"
  - name: LOG_LEVEL
    value: "INFO"  # INFO, DEBUG, WARNING
```

### ConfigMap Settings

Edit `config.yaml` for advanced tuning:

```json
{
  "prometheus_url": "http://prometheus-server:9090",
  "namespace": "default",
  "control_interval": 30,        # Query metrics every 30 seconds
  "cooldown_period": 60,         # Wait 60s between scale actions
  "ema_alpha": 0.7,              # Smoothing factor (0.5=smooth, 0.9=responsive)
  "min_replicas": 1,             # Minimum pods
  "max_replicas": 10,            # Maximum pods
  "rps_thresholds": {
    "1": [10, 0],        # Scale to 1 pod: 0-10 RPS
    "2": [30, 8],        # Scale to 2 pods: 8-30 RPS
    "3": [60, 25],       # Scale to 3 pods: 25-60 RPS
    "4": [100, 50],      # Scale to 4 pods: 50-100 RPS
    "5": [999999, 90]    # Scale to 5+ pods: 90+ RPS
  }
}
```

### Scaling Strategies

**For Aggressive Scaling (React Faster):**
```yaml
env:
  - name: COOLDOWN_PERIOD
    value: "30"        # Scale every 30 seconds
  - name: EMA_ALPHA
    value: "0.9"       # Trust current data more
```

**For Conservative Scaling (Save Costs):**
```yaml
env:
  - name: COOLDOWN_PERIOD
    value: "120"       # Wait 2 minutes
  - name: EMA_ALPHA
    value: "0.5"       # More smoothing
```

**For High-Traffic Services:**
```json
"rps_thresholds": {
  "1": [50, 0],      # Higher thresholds
  "2": [100, 40],
  "3": [200, 80],
  "4": [400, 150],
  "5": [999999, 300]
}
```

**For Cost-Sensitive Services:**
```json
"rps_thresholds": {
  "1": [5, 0],       # Lower thresholds = fewer pods
  "2": [15, 3],
  "3": [30, 10],
  "4": [50, 25],
  "5": [999999, 40]
}
```

## 📊 Monitoring the Autoscaler

### View Real-Time Logs

```bash
# Follow autoscaler logs
kubectl logs -f deployment/reactive-autoscaler

# Filter for scaling actions only
kubectl logs deployment/reactive-autoscaler | grep "UPSCALE\|DOWNSCALE"
```

### Example Output

```
2024-12-06 10:05:23 - Autoscaler - INFO - 🚀 Live Reactive Autoscaler initialized
2024-12-06 10:05:25 - Autoscaler - INFO - Monitoring 3 services: [frontend, checkout, api]
2024-12-06 10:05:55 - Autoscaler - INFO - 📊 Metrics collected
2024-12-06 10:06:10 - Autoscaler - INFO - 🔄 UPSCALE: frontend 2→3 | Scale up: RPS 65.3 >= 60.0
2024-12-06 10:07:45 - Autoscaler - INFO - 🔄 DOWNSCALE: checkout 5→4 | Scale down: RPS 45.2 < 50.0
2024-12-06 10:08:00 - Autoscaler - INFO - ⏸️  BLOCKED: frontend | Cooldown: wait 37s
```

### Watch Pod Replicas Change

```bash
# Watch all deployments update in real-time
kubectl get deployment --watch

# Watch specific deployment
kubectl get deployment frontend --watch
```

### Prometheus Queries

Access Prometheus web UI:

```bash
# Port-forward to Prometheus
kubectl port-forward svc/prometheus-server 9090:80

# Open http://localhost:9090
```

**Example queries:**
```promql
# Request rate for a service
rate(http_requests_total{service="frontend"}[1m])

# Pod count over time
count(container_memory_usage_bytes{pod=~"frontend.*"})

# CPU usage per pod
rate(container_cpu_usage_seconds_total{pod=~"frontend.*"}[1m])
```

## 🧪 Testing Locally

### Test with Minikube

```bash
# Start minikube
minikube start

# Deploy Prometheus
helm install prometheus prometheus-community/prometheus

# Deploy a test service with metrics
kubectl create deployment nginx --image=nginx --replicas=1
kubectl expose deployment nginx --port=80

# Run autoscaler locally
python reactive.py
```

### Simulate Traffic

```bash
# Start load generator pod
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -- /bin/sh

# Inside the pod, generate traffic
while true; do wget -q -O- http://nginx; done
```

### Watch Scaling

```bash
# In another terminal
kubectl get deployment nginx --watch

# You should see replicas increase as traffic increases:
# nginx 1/1 1 1 5m
# nginx 2/2 2 2 6m <- Scaled up!
# nginx 3/3 3 3 7m <- Scaled up again!
# nginx 2/2 2 2 10m <- Scaled down as traffic decreased
```

## 🌍 Advanced Configuration

### Multiple Namespaces

```python
# In config.json
"namespaces": ["production", "staging", "qa"]  # Watch multiple namespaces
```

### Custom Metrics

```python
# Instead of RPS, scale based on CPU
"metric_query": "avg(rate(container_cpu_usage_seconds_total{pod=~'{service}.*'}[1m]))",
"metric_type": "cpu",
"cpu_thresholds": {
  "1": [0.1, 0.0],   # 0-10% CPU
  "2": [0.3, 0.1],   # 10-30% CPU
  "3": [0.5, 0.3],   # 30-50% CPU
  "4": [0.7, 0.5],   # 50-70% CPU
  "5": [1.0, 0.7]    # 70%+ CPU
}
```

### Service-Specific Thresholds

```python
# Different thresholds per service
"service_thresholds": {
  "frontend": {        # Frontend handles high traffic
    "1": [50, 0],
    "2": [100, 40],
    "3": [200, 80],
  },
  "checkout": {        # Checkout is critical
    "1": [10, 0],
    "2": [20, 5],
    "3": [40, 15],
  }
}
```

## 🔒 Production Checklist

- [ ] Autoscaler has sufficient RBAC permissions
- [ ] Prometheus is reliable and collecting metrics
- [ ] Minimum/maximum replica limits are set appropriately
- [ ] Cooldown period prevents rapid scaling
- [ ] Thresholds are tuned for your workload
- [ ] Resource requests/limits are set
- [ ] Pod disruption budgets are configured for critical services
- [ ] Monitoring and alerts are set up
- [ ] Dry-run testing completed
- [ ] Rollback plan documented

## 🗑️ Cleanup

Remove the autoscaler:

```bash
# Delete deployment
kubectl delete deployment reactive-autoscaler

# Delete ConfigMap
kubectl delete configmap autoscaler-config

# Delete RBAC
kubectl delete rolebinding autoscaler-binding
kubectl delete role autoscaler-role
kubectl delete serviceaccount autoscaler
```

Or all at once:

```bash
kubectl delete -f deployment.yaml
kubectl delete -f config.yaml
kubectl delete -f rbac.yaml
```

## 🆘 Troubleshooting

### Pod won't start

```bash
# Check pod logs
kubectl logs deployment/reactive-autoscaler

# Check events
kubectl describe pod -l app=reactive-autoscaler

# Check resource constraints
kubectl top pod -l app=reactive-autoscaler
```

### Can't connect to Prometheus

```bash
# Verify Prometheus is running
kubectl get svc -l app.kubernetes.io/name=prometheus

# Test connectivity
kubectl exec -it deployment/reactive-autoscaler -- curl http://prometheus-server:9090/api/v1/query?query=up

# Check Prometheus URL in ConfigMap
kubectl get configmap autoscaler-config -o yaml
```

### No metrics being collected

```bash
# Verify services expose metrics endpoint
kubectl port-forward svc/frontend 8000:8000
curl localhost:8000/metrics

# Check if metrics are in Prometheus
# Go to Prometheus UI and search for: http_requests_total
```

### Scaling not happening

```bash
# Check logs for errors
kubectl logs deployment/reactive-autoscaler | grep -i error

# Verify RBAC permissions
kubectl auth can-i patch deployments/scale --as=system:serviceaccount:default:autoscaler

# Check if services are being monitored
kubectl logs deployment/reactive-autoscaler | grep "Monitoring"
```

## 📚 Integration with Predictive Models

The autoscaler can be extended with your predictive model:

```python
# Hybrid approach: Combine reactive + predictive
reactive_decision = get_reactive_scaling()
predictive_decision = your_ml_model.predict()

if abs(reactive_decision - predictive_decision) > 2:
    # Large discrepancy - trust reactive (emergency response)
    final_replicas = reactive_decision
    reason = "Reactive override (spike detected)"
else:
    # Normal - trust predictive
    final_replicas = predictive_decision
    reason = "Predictive scaling"

execute_scaling(service, final_replicas)
```

## 📞 Support

For issues or questions:

1. Check logs: `kubectl logs -f deployment/reactive-autoscaler`
2. Review configuration: `kubectl get configmap autoscaler-config -o yaml`
3. Test Prometheus: `kubectl exec -it pod/reactive-autoscaler-xxx -- curl prometheus:9090/api/v1/query?query=up`
4. Review code: Check `reactive.py` for detailed implementation

## 📄 Files Summary

| File | Purpose |
|------|---------|
| `reactive.py` | Core autoscaler implementation |
| `Dockerfile` | Container image definition |
| `rbac.yaml` | Kubernetes permissions (ServiceAccount, Role, RoleBinding) |
| `config.yaml` | Configuration (prometheus URL, thresholds, intervals) |
| `deployment.yaml` | Kubernetes pod deployment manifest |
| `deploy.sh` | Automated deployment script |
| `README.md` | This file |

## 🎯 Next Steps

1. **Deploy the autoscaler**: Run `./deploy.sh`
2. **Monitor**: Watch logs with `kubectl logs -f deployment/reactive-autoscaler`
3. **Test**: Create a test deployment and generate traffic
4. **Tune**: Adjust thresholds based on your workload
5. **Integrate**: Combine with predictive models for hybrid scaling

---

**Version**: 1.0  
**Last Updated**: December 2024  
**Compatibility**: Kubernetes 1.20+, Python 3.9+
