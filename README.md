# 🚀 Hybrid Reactive Autoscaler - Complete Documentation

## 📋 Table of Contents
1. [Project Overview](#project-overview)
2. [System Architecture](#system-architecture)
3. [What You Built](#what-you-built)
4. [Prerequisites](#prerequisites)
5. [Quick Start Guide](#quick-start-guide)
6. [Starting Everything After Shutdown](#starting-everything-after-shutdown)
7. [Monitoring & Verification](#monitoring--verification)
8. [Troubleshooting](#troubleshooting)
9. [Configuration Guide](#configuration-guide)
10. [Integration with Predictive Model](#integration-with-predictive-model)

---

## 🎯 Project Overview

You have successfully built a **production-ready hybrid reactive autoscaler** for Kubernetes microservices.

### What It Does
- **Monitors** microservice traffic in real-time via Prometheus
- **Analyzes** Request Per Second (RPS) metrics
- **Scales** Kubernetes deployments automatically based on load
- **Optimizes** resource usage with intelligent thresholds

### Key Features
✅ **Reactive Scaling**: Responds to current traffic patterns  
✅ **Cooldown Period**: Prevents flapping (60s between scale actions)  
✅ **Exponential Moving Average**: Smooths RPS data for stable decisions  
✅ **Hysteresis**: Different thresholds for scale-up vs scale-down  
✅ **Production-Ready**: Running live in Kubernetes with real metrics  

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                  YOUR AUTOSCALER                        │
│  ┌──────────────────────────────────────────────────┐  │
│  │  1. Queries Prometheus every 30s                 │  │
│  │  2. Calculates smoothed RPS (EMA)                │  │
│  │  3. Compares with thresholds (with hysteresis)   │  │
│  │  4. Makes scaling decision                       │  │
│  │  5. Executes via Kubernetes API                  │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
                          ↓                    ↑
                    Queries RPS          Scales Pods
                          ↓                    ↑
        ┌─────────────────┴────────────────────┴─────────┐
        │                                                  │
        ↓                                                  ↑
┌──────────────┐                              ┌──────────────────┐
│  Prometheus  │←─── Scrapes Metrics ─────────│   Microservices  │
│  (Metrics)   │                              │   (Frontend, etc)│
└──────────────┘                              └──────────────────┘
```

---

## 📦 What You Built

### File Structure
```
~/final/
├── reactive.py                 # Main autoscaler code
├── Dockerfile                  # Container image definition
├── deployment.yaml            # Kubernetes deployment
├── rbac.yaml                  # Permissions
├── config.yaml                # ConfigMap
├── demo-app.yaml              # Test app with metrics
├── watch-autoscaler.sh        # Helper: Watch logs
├── generate-load.sh           # Helper: Generate traffic
└── check-status.sh            # Helper: Check status
```

### Components Running

| Component | Purpose | Status Check |
|-----------|---------|--------------|
| **k3s** | Lightweight Kubernetes | `sudo systemctl status k3s` |
| **Prometheus** | Metrics collection | `kubectl get pods -l app.kubernetes.io/name=prometheus` |
| **Reactive Autoscaler** | Your scaling engine | `kubectl get pods -l app=reactive-autoscaler` |
| **Frontend (Demo App)** | Test microservice with metrics | `kubectl get pods -l app=frontend` |

---

## ✅ Prerequisites

Your system is already set up with:
- ✅ k3s (Lightweight Kubernetes)
- ✅ kubectl (Kubernetes CLI)
- ✅ Helm (Package manager)
- ✅ Prometheus (Metrics)
- ✅ Docker (Container runtime)

---

## 🚀 Quick Start Guide

### Starting Everything Fresh

```bash
# 1. Ensure k3s is running
sudo systemctl start k3s
sudo systemctl status k3s

# 2. Check all pods are running
kubectl get pods --all-namespaces

# 3. Verify autoscaler is running
kubectl get pods -l app=reactive-autoscaler

# 4. Check logs
kubectl logs -f deployment/reactive-autoscaler
```

If everything is already running, you're good to go! ✅

---

## 🔄 Starting Everything After Shutdown

### Scenario: You closed everything and want to run it again

```bash
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
```

### Make it executable and run:
```bash
cd ~/final
chmod +x restart-autoscaler.sh
./restart-autoscaler.sh
```

---

## 📊 Monitoring & Verification

### Check if Autoscaler is Working

```bash
# 1. Check autoscaler pod is running
kubectl get pods -l app=reactive-autoscaler

# Expected output:
# NAME                                   READY   STATUS    RESTARTS   AGE
# reactive-autoscaler-xxxxx-xxxxx        1/1     Running   0          5m

# 2. Watch autoscaler logs (should see no errors)
kubectl logs -f deployment/reactive-autoscaler

# Expected output (every 30 seconds):
# Monitoring 7 services: ['checkoutservice', 'frontend', ...]
# No connection timeout errors!

# 3. Check if Prometheus has metrics
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') -c prometheus-server -- \
  wget -q -O- 'http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{service="frontend"}[1m]))'

# Expected: Should return JSON with a value (RPS number)
```

### See Autoscaling in Action

**Terminal 1: Watch Autoscaler Logs**
```bash
kubectl logs -f deployment/reactive-autoscaler | grep -E 'frontend|UPSCALE|DOWNSCALE'
```

**Terminal 2: Generate Traffic**
```bash
# Generate load
for i in 1 2 3 4 5; do
  kubectl run traffic-gen-$i --image=busybox --restart=Never -- sh -c \
    'while true; do wget -q -O- http://frontend.default.svc.cluster.local >/dev/null 2>&1; done' &
done
```

**Terminal 3: Watch Scaling**
```bash
kubectl get deployment frontend --watch
```

**Expected Result:**
```
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
frontend   1/1     1            1           5m
frontend   2/2     2            2           6m    ← Scaled up!
frontend   3/3     3            3           7m    ← Scaled up again!
frontend   5/5     5            5           9m    ← At maximum!
```

**Stop Traffic and Watch Scale Down:**
```bash
kubectl delete pod traffic-gen-1 traffic-gen-2 traffic-gen-3 traffic-gen-4 traffic-gen-5

# Watch it scale back down after cooldown period
kubectl get deployment frontend --watch
```

---

## 🔧 Troubleshooting

### Problem: Autoscaler pod not starting

```bash
# Check pod status
kubectl describe pod -l app=reactive-autoscaler

# Common fixes:
# 1. Rebuild image
cd ~/final
sudo docker build -t reactive-autoscaler:v1 .
sudo docker save reactive-autoscaler:v1 | sudo k3s ctr images import -
kubectl delete pod -l app=reactive-autoscaler

# 2. Check RBAC permissions
kubectl apply -f rbac.yaml
```

### Problem: "No RPS data" warnings

```bash
# Check if Prometheus is working
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') -c prometheus-server -- \
  wget -q -O- 'http://localhost:9090/-/healthy'

# Check if demo app has metrics
kubectl exec -it $(kubectl get pod -l app=frontend -o jsonpath='{.items[0].metadata.name}') -- \
  wget -q -O- http://localhost:8080/metrics | head -20

# Restart autoscaler
kubectl delete pod -l app=reactive-autoscaler
```

### Problem: k3s not starting

```bash
# Check status
sudo systemctl status k3s

# Restart k3s
sudo systemctl restart k3s

# Check logs
sudo journalctl -u k3s -f
```

### Problem: Scaling not happening

```bash
# 1. Verify metrics exist in Prometheus
kubectl exec -it $(kubectl get pod -l app.kubernetes.io/name=prometheus -o jsonpath='{.items[0].metadata.name}') -c prometheus-server -- \
  wget -q -O- 'http://localhost:9090/api/v1/query?query=sum(rate(http_requests_total{service="frontend"}[1m]))' | jq .

# 2. Check autoscaler can reach Prometheus
kubectl exec $(kubectl get pod -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}') -- \
  wget -q -O- http://prometheus-server.default.svc.cluster.local:80/-/healthy

# 3. Manually test scaling
kubectl scale deployment frontend --replicas=1
# Wait 30 seconds and check if it scales back up
kubectl get deployment frontend --watch
```

---

## ⚙️ Configuration Guide

### Scaling Thresholds

Edit `~/final/reactive.py`, find `RPS_THRESHOLDS` (around line 42):

```python
# Current configuration
RPS_THRESHOLDS = {
    1: (10, 0),      # 1 replica: scale up at 10 RPS
    2: (30, 8),      # 2 replicas: scale up at 30, down at 8
    3: (60, 25),     # 3 replicas: scale up at 60, down at 25
    4: (100, 50),    # 4 replicas: scale up at 100, down at 50
    5: (float('inf'), 90)  # 5 replicas: max, scale down at 90
}
```

**For More Aggressive Scaling (scale earlier):**
```python
RPS_THRESHOLDS = {
    1: (5, 0),       # Scale up at just 5 RPS
    2: (15, 4),
    3: (30, 12),
    4: (50, 25),
    5: (float('inf'), 45)
}
```

**For Conservative Scaling (save costs):**
```python
RPS_THRESHOLDS = {
    1: (20, 0),      # Wait for 20 RPS before scaling
    2: (50, 15),
    3: (100, 40),
    4: (150, 80),
    5: (float('inf'), 120)
}
```

**After changing, rebuild:**
```bash
cd ~/final
sudo docker build -t reactive-autoscaler:v1 .
sudo docker save reactive-autoscaler:v1 | sudo k3s ctr images import -
kubectl delete pod -l app=reactive-autoscaler
```

### Cooldown Period

Edit `reactive.py`, line 38:
```python
COOLDOWN_PERIOD = 60  # Seconds between scaling actions
```

- **Faster response**: Set to `30` (scales more frequently)
- **More stable**: Set to `120` (scales less often)

### Smoothing (EMA Alpha)

Edit `reactive.py`, line 39:
```python
EMA_ALPHA = 0.7  # Weight for current vs historical RPS
```

- **Trust current data more**: Set to `0.9` (more reactive)
- **More smoothing**: Set to `0.5` (more stable, less reactive)

---

## 🤝 Integration with Predictive Model

Your friend built a **TGN + PPO predictive model**. Here's how to integrate:

### Architecture
```
┌─────────────────────┐        ┌──────────────────────┐
│  Predictive Model   │        │   Reactive Model     │
│  (TGN + PPO)        │        │   (Your Autoscaler)  │
│                     │        │                      │
│  Forecasts future   │        │  Responds to current │
│  load patterns      │        │  traffic spikes      │
└──────────┬──────────┘        └──────────┬───────────┘
           │                              │
           │         Hybrid Decision      │
           └──────────────┬───────────────┘
                          ↓
                  ┌───────────────┐
                  │  Final Scale  │
                  │   Decision    │
                  └───────────────┘
                          ↓
                  ┌───────────────┐
                  │  Kubernetes   │
                  └───────────────┘
```

### Integration Code

Add this to `reactive.py`:

```python
class HybridAutoscaler:
    """Combines reactive and predictive scaling"""
    
    def __init__(self, reactive_engine, predictive_model):
        self.reactive = reactive_engine
        self.predictive = predictive_model
        self.logger = logging.getLogger('HybridAutoscaler')
    
    def make_hybrid_decision(self, service: str, current_rps: float, 
                            current_replicas: int) -> tuple[int, str]:
        """
        Combine reactive and predictive models
        
        Strategy: Use predictive for planned scaling,
                 reactive for emergency response
        """
        # Get predictive recommendation (5 minutes ahead)
        try:
            predictive_replicas = self.predictive.predict(
                service=service,
                horizon=300  # 5 minutes
            )
        except Exception as e:
            self.logger.warning(f"Predictive model failed: {e}")
            predictive_replicas = current_replicas
        
        # Get reactive recommendation (current state)
        reactive_replicas, reactive_reason = self.reactive.desired_replicas(
            current_replicas, 
            current_rps
        )
        
        # Hybrid decision logic
        diff = abs(reactive_replicas - predictive_replicas)
        
        if diff > 2:
            # Large discrepancy - emergency situation
            # Trust reactive model (immediate spike)
            final_replicas = reactive_replicas
            reason = f"REACTIVE OVERRIDE: {reactive_reason}"
            self.logger.warning(
                f"Large discrepancy: Reactive={reactive_replicas}, "
                f"Predictive={predictive_replicas}. Using reactive."
            )
        else:
            # Normal operation - trust predictive
            final_replicas = predictive_replicas
            reason = f"PREDICTIVE: Forecast-based scaling"
            self.logger.info(
                f"Using predictive: {predictive_replicas} "
                f"(reactive suggested {reactive_replicas})"
            )
        
        return final_replicas, reason
```

### Alternative Strategies

**Strategy 1: Safety-First (Max)**
```python
# Always take the higher recommendation
final_replicas = max(reactive_replicas, predictive_replicas)
reason = f"MAX(reactive={reactive_replicas}, predictive={predictive_replicas})"
```

**Strategy 2: Weighted Average**
```python
# Blend both recommendations
final_replicas = int(0.7 * predictive_replicas + 0.3 * reactive_replicas)
reason = f"WEIGHTED: 70% predictive, 30% reactive"
```

**Strategy 3: Time-Based**
```python
# Use predictive during business hours, reactive during night
hour = datetime.now().hour
if 9 <= hour <= 17:  # Business hours
    final_replicas = predictive_replicas
    reason = "PREDICTIVE: Business hours"
else:
    final_replicas = reactive_replicas
    reason = "REACTIVE: Off-hours"
```

---

## 📝 Quick Reference Commands

### Daily Operations

```bash
# Start everything
sudo systemctl start k3s
cd ~/final && ./restart-autoscaler.sh

# Check status
kubectl get pods
kubectl get deployments

# Watch autoscaler
kubectl logs -f deployment/reactive-autoscaler

# Generate test load
for i in 1 2 3; do
  kubectl run load-$i --image=busybox --restart=Never -- \
    sh -c 'while true; do wget -q -O- http://frontend; done' &
done

# Stop test load
kubectl delete pod load-1 load-2 load-3

# Check Prometheus metrics
kubectl port-forward svc/prometheus-server 9090:80
# Open: http://localhost:9090

# Restart autoscaler
kubectl delete pod -l app=reactive-autoscaler

# Stop everything
sudo systemctl stop k3s
```

---

## 🎓 Summary

### What You Accomplished

✅ **Built a production-ready reactive autoscaler**  
✅ **Deployed it live in Kubernetes**  
✅ **Integrated with Prometheus for metrics**  
✅ **Successfully scaled microservices automatically**  
✅ **Implemented advanced features** (cooldown, EMA, hysteresis)  
✅ **Created a complete testing environment**  

### Your System Specifications

- **Control Interval**: 30 seconds
- **Cooldown Period**: 60 seconds
- **Smoothing**: EMA with α=0.7
- **Min Replicas**: 1
- **Max Replicas**: 10
- **Scaling Strategy**: RPS-based with hysteresis

### Files Location

All your project files are in: **`~/final/`**

### Next Steps

1. **Integrate with TGN+PPO** predictive model
2. **Add more services** to monitor
3. **Customize thresholds** for your workload
4. **Deploy to production** cluster
5. **Add monitoring dashboard** (Grafana)

---

## 🆘 Support

If you encounter issues:

1. Check logs: `kubectl logs deployment/reactive-autoscaler`
2. Verify Prometheus: `kubectl get pods -l app.kubernetes.io/name=prometheus`
3. Restart k3s: `sudo systemctl restart k3s`
4. Rebuild image: `cd ~/final && sudo docker build -t reactive-autoscaler:v1 .`

---


