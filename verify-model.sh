#!/bin/bash

# ========================================================================
# AUTOMATED AUTOSCALER VERIFICATION SCRIPT
# ========================================================================
# Runs all verification checks automatically and reports status
# ========================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   AUTOSCALER MODEL - AUTOMATED VERIFICATION                   ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL_COUNT++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN_COUNT++))
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# ========================================================================
# CHECK 1: POD STATUS
# ========================================================================
echo -e "${BLUE}[1/8]${NC} Checking Pod Status..."
if kubectl get pods -l app=reactive-autoscaler &>/dev/null; then
    POD=$(kubectl get pod -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [ -z "$POD" ]; then
        fail "No autoscaler pods found"
    else
        pass "Pod found: $POD"
        
        READY=$(kubectl get pod "$POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
        if [ "$READY" = "True" ]; then
            pass "Pod is Ready (1/1)"
        else
            fail "Pod is NOT Ready"
        fi
        
        STATUS=$(kubectl get pod "$POD" -o jsonpath='{.status.phase}')
        if [ "$STATUS" = "Running" ]; then
            pass "Pod status: Running"
        else
            fail "Pod status: $STATUS (should be Running)"
        fi
        
        RESTARTS=$(kubectl get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}')
        if [ "$RESTARTS" -eq 0 ]; then
            pass "Restarts: 0"
        else
            warn "Restarts: $RESTARTS"
        fi
    fi
else
    fail "No autoscaler pods found"
fi
echo ""

# ========================================================================
# CHECK 2: RBAC COMPONENTS
# ========================================================================
echo -e "${BLUE}[2/8]${NC} Checking RBAC Components..."
if kubectl get sa autoscaler &>/dev/null; then
    pass "ServiceAccount 'autoscaler' exists"
else
    fail "ServiceAccount 'autoscaler' NOT found"
fi

if kubectl get role autoscaler-role &>/dev/null; then
    pass "Role 'autoscaler-role' exists"
else
    fail "Role 'autoscaler-role' NOT found"
fi

if kubectl get rolebinding autoscaler-binding &>/dev/null; then
    pass "RoleBinding 'autoscaler-binding' exists"
else
    fail "RoleBinding 'autoscaler-binding' NOT found"
fi
echo ""

# ========================================================================
# CHECK 3: CONFIGMAP
# ========================================================================
echo -e "${BLUE}[3/8]${NC} Checking ConfigMap..."
if kubectl get configmap autoscaler-config &>/dev/null; then
    pass "ConfigMap 'autoscaler-config' exists"
    
    # Try to parse and show key settings
    CONFIG=$(kubectl get configmap autoscaler-config -o jsonpath='{.data.config\.json}' 2>/dev/null || echo "")
    if [ -n "$CONFIG" ]; then
        PROMETHEUS_URL=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('prometheus_url', 'N/A'))" 2>/dev/null || echo "N/A")
        CONTROL_INTERVAL=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('control_interval', 'N/A'))" 2>/dev/null || echo "N/A")
        info "Prometheus URL: $PROMETHEUS_URL"
        info "Control Interval: ${CONTROL_INTERVAL}s"
    fi
else
    fail "ConfigMap 'autoscaler-config' NOT found"
fi
echo ""

# ========================================================================
# CHECK 4: PROMETHEUS CONNECTIVITY
# ========================================================================
echo -e "${BLUE}[4/8]${NC} Checking Prometheus Connectivity..."
if [ -z "$POD" ]; then
    fail "Cannot test Prometheus (no pod)"
else
    if kubectl exec "$POD" -- timeout 5 curl -s http://prometheus-server:80/api/v1/query?query=up &>/dev/null; then
        pass "Autoscaler can reach Prometheus"
    else
        fail "Autoscaler CANNOT reach Prometheus"
        warn "Try running: ./fix-prometheus.sh"
    fi
fi
echo ""

# ========================================================================
# CHECK 5: POD LOGS - INITIALIZATION
# ========================================================================
echo -e "${BLUE}[5/8]${NC} Checking Pod Logs (Initialization)..."
LOGS=$(kubectl logs deployment/reactive-autoscaler --tail=50 2>/dev/null || echo "")

if echo "$LOGS" | grep -q "initialized\|initialized successfully"; then
    pass "Autoscaler initialization message found"
else
    warn "Initialization message not found in recent logs"
fi

if echo "$LOGS" | grep -q "Monitoring.*services"; then
    pass "Autoscaler is monitoring services"
    SERVICES=$(echo "$LOGS" | grep "Monitoring" | tail -1 | sed 's/.*Monitoring //' | sed 's/ services.*//')
    info "Services: $SERVICES"
else
    warn "No 'Monitoring services' message in logs"
fi
echo ""

# ========================================================================
# CHECK 6: METRICS COLLECTION
# ========================================================================
echo -e "${BLUE}[6/8]${NC} Checking Metrics Collection..."
RECENT_LOGS=$(kubectl logs deployment/reactive-autoscaler --tail=100 2>/dev/null | tail -50 || echo "")

if echo "$RECENT_LOGS" | grep -q "RPS\|Collecting"; then
    pass "Metrics collection detected"
    RPS_LINES=$(echo "$RECENT_LOGS" | grep "RPS" | head -3)
    if [ -n "$RPS_LINES" ]; then
        info "Recent RPS readings:"
        echo "$RPS_LINES" | sed 's/^/  /'
    fi
else
    warn "No RPS metrics found in recent logs (wait a few seconds or check traffic)"
fi
echo ""

# ========================================================================
# CHECK 7: SCALING DECISIONS
# ========================================================================
echo -e "${BLUE}[7/8]${NC} Checking Scaling Decisions..."
ALL_LOGS=$(kubectl logs deployment/reactive-autoscaler --tail=500 2>/dev/null || echo "")

UPSCALE_COUNT=$(echo "$ALL_LOGS" | grep -c "UPSCALE" || echo 0)
DOWNSCALE_COUNT=$(echo "$ALL_LOGS" | grep -c "DOWNSCALE" || echo 0)

if [ "$UPSCALE_COUNT" -gt 0 ] || [ "$DOWNSCALE_COUNT" -gt 0 ]; then
    pass "Scaling decisions detected"
    info "UPSCALE events: $UPSCALE_COUNT"
    info "DOWNSCALE events: $DOWNSCALE_COUNT"
    
    # Show last scaling decision
    LAST_SCALE=$(echo "$ALL_LOGS" | grep -E "UPSCALE|DOWNSCALE" | tail -1 || echo "")
    if [ -n "$LAST_SCALE" ]; then
        info "Latest: $LAST_SCALE"
    fi
else
    warn "No scaling decisions found (this is normal if no traffic exists yet)"
    info "To test scaling: deploy a service, generate traffic, and watch logs"
fi
echo ""

# ========================================================================
# CHECK 8: DEPLOYMENT STATUS
# ========================================================================
echo -e "${BLUE}[8/8]${NC} Checking Deployments..."
if kubectl get deployment reactive-autoscaler &>/dev/null; then
    pass "Deployment 'reactive-autoscaler' exists"
    
    REPLICAS=$(kubectl get deployment reactive-autoscaler -o jsonpath='{.status.replicas}')
    READY=$(kubectl get deployment reactive-autoscaler -o jsonpath='{.status.readyReplicas}')
    info "Replicas: $READY/$REPLICAS ready"
else
    fail "Deployment 'reactive-autoscaler' NOT found"
fi
echo ""

# ========================================================================
# SUMMARY
# ========================================================================
TOTAL=$((PASS_COUNT + FAIL_COUNT + WARN_COUNT))
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                        SUMMARY                                 ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}Passed:${NC}  $PASS_COUNT/$TOTAL"
echo -e "  ${RED}Failed:${NC}  $FAIL_COUNT/$TOTAL"
echo -e "  ${YELLOW}Warnings:${NC} $WARN_COUNT/$TOTAL"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    if [ $WARN_COUNT -eq 0 ]; then
        echo -e "${GREEN}✓ All checks passed! Your autoscaler is working correctly.${NC}"
        echo ""
        echo "Next steps to verify full functionality:"
        echo "  1. Deploy a test service: kubectl create deployment test --image=nginx:latest"
        echo "  2. Generate traffic: kubectl run -i --tty load --rm --image=busybox --restart=Never -- /bin/sh"
        echo "     Inside the pod: while true; do wget -q -O- http://test; done"
        echo "  3. Watch scaling: kubectl logs -f deployment/reactive-autoscaler | grep -E 'UPSCALE|DOWNSCALE'"
        echo "  4. Watch replicas: kubectl get deployment test --watch"
    else
        echo -e "${YELLOW}✓ Most checks passed, but see warnings above.${NC}"
    fi
    EXIT=0
else
    echo -e "${RED}✗ Some checks failed. See details above.${NC}"
    echo ""
    echo "Troubleshooting:"
    if echo "$RECENT_LOGS" | grep -q "ConnectionError\|Connection refused"; then
        echo "  - Prometheus connectivity issue detected"
        echo "  - Run: ./fix-prometheus.sh"
    fi
    if ! kubectl get sa autoscaler &>/dev/null; then
        echo "  - RBAC not configured"
        echo "  - Run: kubectl apply -f rbac.yaml"
    fi
    if ! kubectl get configmap autoscaler-config &>/dev/null; then
        echo "  - ConfigMap not found"
        echo "  - Run: kubectl apply -f config.yaml"
    fi
    EXIT=1
fi

echo ""
exit $EXIT
