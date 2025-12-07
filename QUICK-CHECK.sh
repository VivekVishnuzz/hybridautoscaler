#!/bin/bash

# ========================================================================
# QUICK START: HOW TO CHECK IF YOUR AUTOSCALER IS WORKING
# ========================================================================

cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║                      🚀 QUICK START GUIDE 🚀                             ║
║              How to Check If Your Autoscaler is Working                  ║
╚═══════════════════════════════════════════════════════════════════════════╝

FASTEST WAY (30 seconds):
─────────────────────────

  1. Check pod is running:
     $ kubectl get pods -l app=reactive-autoscaler
     
     Expected: Should show 1/1 Running

  2. View latest logs:
     $ kubectl logs deployment/reactive-autoscaler --tail=20
     
     Look for: "Monitoring X services", "RPS:", "initialized"

  3. Done! If pod is running and logs show metrics, it's working ✓


═════════════════════════════════════════════════════════════════════════════

TEST WITH REAL TRAFFIC (10 minutes):
────────────────────────────────────

Step 1: Deploy a test application
  $ kubectl create deployment my-app --image=nginx:latest --replicas=1
  $ kubectl expose deployment my-app --port=80

Step 2: Open 3 terminals:

  TERMINAL 1 - Watch autoscaler logs:
    $ kubectl logs -f deployment/reactive-autoscaler | grep -E "UPSCALE|DOWNSCALE|RPS"

  TERMINAL 2 - Watch replicas changing:
    $ kubectl get deployment my-app --watch

  TERMINAL 3 - Generate traffic:
    $ kubectl run -i --tty load --rm --image=busybox --restart=Never -- /bin/sh
    
    Inside the pod, run:
      # while true; do wget -q -O- http://my-app; done

Step 3: Watch the magic happen!
  - After ~30-60 seconds of traffic, replicas should increase (1 → 2 → 3)
  - Terminal 1 will show: "🔄 UPSCALE: my-app 1→2 | RPS: 65.3 >= 60.0"
  - Terminal 2 will show: replicas updating in real-time

Step 4: Stop traffic (Ctrl+C in Terminal 3)
  - After ~1 minute, replicas should decrease
  - Terminal 1 will show: "🔄 DOWNSCALE: my-app 3→1 | RPS: 8.2 < 25.0"

SUCCESS! 🎉 Your autoscaler is working!


═════════════════════════════════════════════════════════════════════════════

AUTOMATED STATUS CHECK:
──────────────────────

Run this for a complete automated check:
  $ bash verify-model.sh

This checks:
  ✓ Pod is running
  ✓ RBAC is configured
  ✓ ConfigMap exists
  ✓ Prometheus connection
  ✓ Metrics are flowing
  ✓ Scaling decisions are being made


═════════════════════════════════════════════════════════════════════════════

LIVE MONITORING DASHBOARD:
──────────────────────────

For real-time monitoring of the autoscaler:
  $ bash monitor-live.sh

This shows:
  ✓ Pod status and health
  ✓ Recent RPS metrics
  ✓ Scaling events (UPSCALE/DOWNSCALE)
  ✓ Deployment status
  ✓ Error detection


═════════════════════════════════════════════════════════════════════════════

DETAILED DOCUMENTATION:
──────────────────────

For comprehensive testing guide with all details:
  $ bash CHECK-MODEL-WORKING.sh

This includes:
  - 6 verification levels (health → metrics → scaling)
  - Full end-to-end test scenario
  - Troubleshooting guide
  - Metric details to look for


═════════════════════════════════════════════════════════════════════════════

KEY THINGS TO LOOK FOR IN LOGS:
────────────────────────────────

✓ Healthy logs contain:
  - "initialized successfully"
  - "Monitoring X services"
  - "RPS: 45.3" (numbers should vary)
  - Every 30 seconds: new RPS values
  - When traffic increases: "UPSCALE: service 1→2"
  - When traffic decreases: "DOWNSCALE: service 2→1"

✗ Error logs contain:
  - "ERROR", "Exception", "ConnectionError"
  - "Prometheus" (only if can't connect)
  - No "RPS:" messages (metrics not flowing)
  - "ServiceAccount" errors (RBAC not set up)


═════════════════════════════════════════════════════════════════════════════

CURRENT STATUS OF YOUR AUTOSCALER:
───────────────────────────────────

EOF

# Get current status
echo "Checking your autoscaler now..."
echo ""

POD=$(kubectl get pod -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$POD" ]; then
    echo "❌ Pod not found! Run: kubectl get pods"
    exit 1
fi

echo "Pod: $POD"
READY=$(kubectl get pod "$POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
if [ "$READY" = "True" ]; then
    echo "Status: ✓ READY (1/1)"
else
    echo "Status: ✗ NOT READY"
fi

echo ""
echo "Recent logs (last 15 lines):"
echo "────────────────────────────"
kubectl logs deployment/reactive-autoscaler --tail=15 | sed 's/^/  /'

echo ""
echo "════════════════════════════════════════════════════════════════════════════"
echo ""
echo "📊 TO TEST YOUR AUTOSCALER NOW:"
echo ""
echo "  Open 3 terminals:"
echo ""
echo "  Terminal 1: kubectl logs -f deployment/reactive-autoscaler | grep -E 'UPSCALE|DOWNSCALE|RPS'"
echo "  Terminal 2: kubectl get deployment --watch"
echo "  Terminal 3: kubectl create deployment test --image=nginx:latest && kubectl expose deployment test --port=80 && kubectl run -i --tty load --rm --image=busybox --restart=Never -- /bin/sh"
echo ""
echo "  Then inside the pod in Terminal 3, run:"
echo "    while true; do wget -q -O- http://test; done"
echo ""
echo "  Watch Terminals 1 & 2 - you should see scaling happen! 🚀"
echo ""
