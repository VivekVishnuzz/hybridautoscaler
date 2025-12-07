#!/bin/bash

# ========================================================================
# AUTOSCALER MODEL - COMPREHENSIVE TESTING & VERIFICATION GUIDE
# ========================================================================
# This guide shows how to check if your autoscaler is working correctly
# ========================================================================

cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║              🔍 AUTOSCALER MODEL - HOW TO CHECK IF IT'S WORKING          ║
╚═══════════════════════════════════════════════════════════════════════════╝

Your model (autoscaler) works through these steps:
  1. Reads metrics from Prometheus every 30 seconds
  2. Calculates RPS (requests per second) for each service
  3. Compares RPS against thresholds
  4. Makes scaling decisions
  5. Updates Kubernetes deployment replicas

Let's verify each step is working!

═══════════════════════════════════════════════════════════════════════════

🔍 LEVEL 1: BASIC HEALTH CHECK (30 seconds)
─────────────────────────────────────────────

Check if autoscaler pod is running:

  kubectl get pods -l app=reactive-autoscaler

Expected output:
  NAME                                  READY   STATUS    RESTARTS
  reactive-autoscaler-6d96c9d9d-9gmqh   1/1     Running   0

If NOT running:
  → Check: kubectl describe pod -l app=reactive-autoscaler
  → Check: kubectl logs deployment/reactive-autoscaler

───────────────────────────────────────────────────────────────────────────

Check if ConfigMap exists:

  kubectl get configmap autoscaler-config

Expected output:
  NAME                  DATA   AGE
  autoscaler-config     1      2m

If NOT found:
  → Redeploy: kubectl apply -f config.yaml

───────────────────────────────────────────────────────────────────────────

Check if RBAC permissions are set:

  kubectl get serviceaccount autoscaler
  kubectl get role autoscaler-role
  kubectl get rolebinding autoscaler-binding

Expected output: All three resources should exist

If NOT found:
  → Redeploy: kubectl apply -f rbac.yaml

═══════════════════════════════════════════════════════════════════════════

🔍 LEVEL 2: CHECK LOGS FOR INITIALIZATION (1 minute)
─────────────────────────────────────────────────────

View initialization logs:

  kubectl logs deployment/reactive-autoscaler

Look for these messages (should appear in order):
  ✓ "Autoscaler initialized"
  ✓ "Monitoring X services"
  ✓ "Prometheus: http://..."
  ✓ "Collecting metrics from Prometheus"

Example expected output:
  2024-12-06 18:00:15 - INFO - 🚀 Autoscaler initialized
  2024-12-06 18:00:15 - INFO - Monitoring 2 services: [frontend, checkout]
  2024-12-06 18:00:15 - INFO - Prometheus: http://prometheus-server:80
  2024-12-06 18:00:45 - INFO - Collecting metrics from Prometheus

If you see ERRORS:
  ✗ "ConnectionError" → Prometheus not reachable
  ✗ "ServiceAccount" → RBAC permissions missing
  ✗ "ConfigMap" → Config not found

═══════════════════════════════════════════════════════════════════════════

🔍 LEVEL 3: CHECK PROMETHEUS CONNECTION (2 minutes)
────────────────────────────────────────────────────

Get the autoscaler pod name:

  POD=$(kubectl get pod -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}')
  echo $POD

Test Prometheus connectivity:

  kubectl exec $POD -- curl -s http://prometheus-server:80/api/v1/query?query=up | head -20

Expected output: JSON response with Prometheus status
  {"status":"success","data":{"resultType":"vector",...

If FAILS (curl error):
  → Check Prometheus service: kubectl get svc -l app.kubernetes.io/name=prometheus
  → Check Prometheus pod: kubectl get pods -l app.kubernetes.io/name=prometheus
  → Check network: kubectl exec $POD -- ping prometheus-server

═══════════════════════════════════════════════════════════════════════════

🔍 LEVEL 4: CHECK METRICS COLLECTION (3-5 minutes)
────────────────────────────────────────────────────

Watch logs for metric collection:

  kubectl logs -f deployment/reactive-autoscaler | grep -i "metrics\|rps\|collecting"

Expected output every 30 seconds:
  Collecting metrics...
  frontend RPS: 45.3
  checkout RPS: 12.1

If NO metrics appear:
  → Services might not be emitting http_requests_total metric
  → Check if services have /metrics endpoint
  → Query Prometheus directly:
    kubectl exec $POD -- curl -s 'http://prometheus-server:80/api/v1/query?query=http_requests_total' | grep -o '"value"'

═══════════════════════════════════════════════════════════════════════════

🔍 LEVEL 5: CHECK SCALING DECISIONS (5-10 minutes)
────────────────────────────────────────────────────

Watch logs for scaling decisions:

  kubectl logs -f deployment/reactive-autoscaler | grep -E "UPSCALE|DOWNSCALE|BLOCKED"

Expected output when traffic increases:
  🔄 UPSCALE: frontend 2→3 | RPS: 75.2 >= 60.0
  🔄 UPSCALE: frontend 3→4 | RPS: 95.1 >= 90.0

Expected output when traffic decreases:
  🔄 DOWNSCALE: frontend 4→2 | RPS: 35.2 < 50.0
  🔄 DOWNSCALE: checkout 2→1 | RPS: 8.5 < 10.0

Expected blocking messages (cooldown period):
  ⏸️  BLOCKED: frontend | In cooldown: wait 42 seconds

If NO scaling decisions:
  → No traffic being generated (generate traffic!)
  → RPS not changing enough to trigger scaling
  → Thresholds might be too high/low

═══════════════════════════════════════════════════════════════════════════

🧪 LEVEL 6: FULL END-TO-END TEST (10-15 minutes)
──────────────────────────────────────────────────

This test verifies the complete workflow:

1️⃣  Deploy a test application:

  kubectl create deployment frontend --image=nginx:latest --replicas=1
  kubectl expose deployment frontend --port=80 --target-port=80

2️⃣  Check autoscaler is monitoring it:

  kubectl logs deployment/reactive-autoscaler | grep "frontend"

  Expected: "Monitoring X services: [frontend, ...]"

3️⃣  Generate traffic to the service:

  # Terminal 1: Start load generator
  kubectl run -i --tty load-gen --rm --image=busybox --restart=Never -- /bin/sh
  
  # Inside pod, run:
  while true; do wget -q -O- http://frontend; done

4️⃣  Watch scaling happen in real-time:

  # Terminal 2: Watch replicas
  kubectl get deployment frontend --watch

  # Terminal 3: Watch autoscaler logs
  kubectl logs -f deployment/reactive-autoscaler | grep -E "frontend|UPSCALE|DOWNSCALE"

5️⃣  Expected sequence:

  Initial:
    frontend 1/1   (1 replica)
  
  After traffic starts (30-60 seconds):
    ✓ Logs show: "frontend RPS: 120.5"
    ✓ Logs show: "🔄 UPSCALE: frontend 1→2"
    ✓ Deployment updates: frontend 2/2
  
  More traffic:
    ✓ Logs show: "frontend RPS: 250.3"
    ✓ Logs show: "🔄 UPSCALE: frontend 2→3"
    ✓ Deployment updates: frontend 3/3

6️⃣  Stop traffic and watch scaling down:

  # Ctrl+C in load generator pod
  
  After 1-2 minutes:
    ✓ Logs show: "frontend RPS: 2.1 (decreasing)"
    ✓ Logs show: "🔄 DOWNSCALE: frontend 3→2"
    ✓ Deployment updates: frontend 2/2

═══════════════════════════════════════════════════════════════════════════

📊 QUICK HEALTH CHECK COMMANDS
───────────────────────────────

All in one command - quick status check:

  echo "=== POD STATUS ===" && \
  kubectl get pods -l app=reactive-autoscaler && \
  echo "" && \
  echo "=== RECENT LOGS ===" && \
  kubectl logs --tail=20 deployment/reactive-autoscaler && \
  echo "" && \
  echo "=== CONFIG ===" && \
  kubectl get configmap autoscaler-config -o jsonpath='{.data.config\.json}' | python3 -m json.tool | head -15

═══════════════════════════════════════════════════════════════════════════

📈 MONITORING DASHBOARD COMMANDS
──────────────────────────────────

1. Watch scaling in real-time (3 terminals):

  Terminal 1: kubectl logs -f deployment/reactive-autoscaler
  Terminal 2: kubectl get deployment --watch
  Terminal 3: kubectl top pod -l app=reactive-autoscaler

2. Filter for key events only:

  kubectl logs deployment/reactive-autoscaler | grep -E "UPSCALE|DOWNSCALE|ERROR|Monitoring|initialized"

3. Export logs for analysis:

  kubectl logs deployment/reactive-autoscaler > autoscaler.log
  grep "UPSCALE\|DOWNSCALE" autoscaler.log | tail -20

═══════════════════════════════════════════════════════════════════════════

❌ TROUBLESHOOTING - WHAT IF NOTHING IS HAPPENING?
────────────────────────────────────────────────────

Problem: Pod is running but logs are empty
  Solution: Check if metrics are being collected
  $ kubectl exec $POD -- curl -s 'http://prometheus-server:80/api/v1/query?query=http_requests_total'

Problem: Pod won't start
  Solution: Check pod description
  $ kubectl describe pod -l app=reactive-autoscaler
  $ kubectl logs deployment/reactive-autoscaler

Problem: Prometheus connection error
  Solution: Verify Prometheus is running
  $ kubectl get svc -l app.kubernetes.io/name=prometheus
  $ kubectl get pods -l app.kubernetes.io/name=prometheus

Problem: No services are being monitored
  Solution: Deploy a test service with metrics
  $ kubectl create deployment test --image=nginx:latest
  $ kubectl expose deployment test --port=80

Problem: Scaling happens but too fast/slow
  Solution: Check configuration
  $ kubectl get configmap autoscaler-config -o yaml
  Edit: cooldown_period, ema_alpha, rps_thresholds

═══════════════════════════════════════════════════════════════════════════

✅ VERIFICATION CHECKLIST - MARK THESE OFF
────────────────────────────────────────────

Basic Health:
  ☐ Pod is running (kubectl get pods)
  ☐ Pod has 1/1 ready
  ☐ No restarts (RESTARTS = 0)
  ☐ Pod age is recent

Configuration:
  ☐ ConfigMap exists (kubectl get configmap)
  ☐ RBAC ServiceAccount exists
  ☐ RBAC Role exists
  ☐ RBAC RoleBinding exists

Prometheus Connection:
  ☐ Prometheus pod is running
  ☐ Prometheus service exists
  ☐ Autoscaler can connect to Prometheus
  ☐ Metrics are available in Prometheus

Metrics Collection:
  ☐ Logs show "Monitoring X services"
  ☐ Logs show periodic "Collecting metrics"
  ☐ Logs show RPS values for each service

Scaling Logic:
  ☐ When traffic increases: UPSCALE messages appear
  ☐ When traffic decreases: DOWNSCALE messages appear
  ☐ Kubernetes replicas actually update
  ☐ Cooldown period is respected (no rapid scaling)

═══════════════════════════════════════════════════════════════════════════

🎯 QUICK TEST SCENARIO (15 minutes)
─────────────────────────────────────

This is the fastest way to verify everything is working:

Step 1 (0m): Check health
  kubectl get pods -l app=reactive-autoscaler
  kubectl logs --tail=10 deployment/reactive-autoscaler

Step 2 (1m): Deploy test app
  kubectl create deployment my-app --image=nginx:latest --replicas=1
  kubectl expose deployment my-app --port=80

Step 3 (3m): Generate traffic (terminal 1)
  kubectl run -i --tty load --rm --image=busybox --restart=Never -- /bin/sh
  # Inside: while true; do wget -q -O- http://my-app; done

Step 4 (5m): Watch autoscaler decisions (terminal 2)
  kubectl logs -f deployment/reactive-autoscaler | grep -E "my-app|UPSCALE|DOWNSCALE"

Step 5 (7m): Watch Kubernetes updates (terminal 3)
  kubectl get deployment my-app --watch

Step 6 (10m): Stop traffic and watch scale-down
  # Ctrl+C in terminal 1

Expected Result:
  ✓ Replicas increase (1 → 2 → 3)
  ✓ Logs show UPSCALE messages
  ✓ After stopping traffic, replicas decrease
  ✓ Logs show DOWNSCALE messages

═══════════════════════════════════════════════════════════════════════════

📊 METRIC DETAILS TO LOOK FOR
──────────────────────────────

In the logs, you should see patterns like:

1. RPS (Requests Per Second):
   "frontend RPS: 123.45"      ← High traffic
   "frontend RPS: 8.20"        ← Low traffic
   "frontend RPS: 0.0"         ← No traffic

2. Smoothed RPS (EMA):
   "frontend Smoothed RPS: 95.3"  ← Value is smoothed
   "frontend Smoothed RPS: 87.2"  ← Reacts to changes gradually

3. Scaling Decisions:
   "🔄 UPSCALE: frontend 1→2 | RPS 65.3 >= 60.0"
   "🔄 DOWNSCALE: frontend 2→1 | RPS 15.2 < 25.0"
   "⏸️  BLOCKED: frontend | Cooldown: wait 30s"

4. Hysteresis Effect (prevents oscillation):
   Scale UP at: RPS >= 60.0
   Scale DOWN at: RPS < 25.0 (not 60.0)
   This prevents rapid up/down cycling

═══════════════════════════════════════════════════════════════════════════

🎓 UNDERSTANDING THE THRESHOLDS
─────────────────────────────────

Check your current thresholds:

  kubectl get configmap autoscaler-config -o jsonpath='{.data.config\.json}' | \
  python3 -c "import sys, json; data=json.load(sys.stdin); print(json.dumps(data['rps_thresholds'], indent=2))"

Default thresholds:
  {
    "1": [10, 0],        ← 1 pod handles: 0-10 RPS (up at 10, down at 0)
    "2": [30, 8],        ← 2 pods handle: 8-30 RPS (up at 30, down at 8)
    "3": [60, 25],       ← 3 pods handle: 25-60 RPS (up at 60, down at 25)
    "4": [100, 50],      ← 4 pods handle: 50-100 RPS (up at 100, down at 50)
    "5": [999999, 90]    ← 5+ pods handle: 90+ RPS (unlimited up)
  }

The key insight:
  - First number: Scale UP threshold
  - Second number: Scale DOWN threshold
  - Gap prevents rapid oscillation (hysteresis)

═══════════════════════════════════════════════════════════════════════════

🔗 PUTTING IT ALL TOGETHER
────────────────────────────

Your model works like this:

  [Prometheus Metrics]
         ↓ (http_requests_total)
  [Autoscaler Pod]
         ↓ (queries every 30s)
  [Calculate RPS]
         ↓
  [Compare vs Thresholds]
         ↓
  [Make Decision: UP/DOWN/BLOCK]
         ↓
  [Update Kubernetes Deployment]
         ↓
  [Replicas Change]

To verify each step:
  1. Check Prometheus has metrics
  2. Check autoscaler logs show RPS values
  3. Check logs show UP/DOWN/BLOCK decisions
  4. Check kubectl shows replica count changing

═══════════════════════════════════════════════════════════════════════════

💡 TIPS FOR SUCCESS
─────────────────────

1. Always monitor 3 terminals simultaneously:
   - Terminal 1: kubectl logs -f deployment/reactive-autoscaler
   - Terminal 2: kubectl get deployment --watch
   - Terminal 3: kubectl exec $POD -- watch -n 1 'curl -s http://prom:80/api/v1/query?query=rate(http_requests_total[1m])'

2. Generate sustained traffic (at least 2-3 minutes) before expecting scaling

3. Remember cooldown period - no scaling happens for 60 seconds after a scale event

4. Watch for smoothed RPS (EMA) not just raw RPS - it responds more gradually

5. Check timestamps in logs - if nothing happens for 5 minutes, something is wrong

═══════════════════════════════════════════════════════════════════════════

📞 QUICK REFERENCE - COPY & PASTE COMMANDS
─────────────────────────────────────────────

# Get pod name
POD=$(kubectl get pod -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}')

# Watch logs with filtering
kubectl logs -f deployment/reactive-autoscaler | grep -E "UPSCALE|DOWNSCALE|RPS|ERROR"

# Check all components
kubectl get pods,svc,configmap,role,rolebinding -l app

# Test prometheus
kubectl exec $POD -- curl -s http://prometheus-server:80/api/v1/query?query=up

# See current config
kubectl get configmap autoscaler-config -o yaml

# Restart autoscaler
kubectl rollout restart deployment/reactive-autoscaler

# View resources
kubectl top pod -l app=reactive-autoscaler
kubectl top nodes

═══════════════════════════════════════════════════════════════════════════

🎉 WHEN IT'S WORKING
──────────────────────

You'll see a pattern like this in logs:

  ✓ "Autoscaler initialized"
  ✓ "Monitoring 2 services: [frontend, checkout]"
  ✓ Every 30 seconds: "frontend RPS: 45.2"
  ✓ After 60 seconds of high traffic: "UPSCALE: frontend 1→2"
  ✓ Kubernetes replicas increase (watch shows it)
  ✓ After traffic decreases: "DOWNSCALE: frontend 2→1"
  ✓ Kubernetes replicas decrease

Congratulations! Your autoscaler is working! 🎊

═══════════════════════════════════════════════════════════════════════════

EOF
