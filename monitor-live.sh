#!/bin/bash

# ========================================================================
# REAL-TIME AUTOSCALER MONITORING DASHBOARD
# ========================================================================
# Displays live autoscaler activity with color-coded output
# ========================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

clear

echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        AUTOSCALER REAL-TIME MONITORING DASHBOARD              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""
echo -e "${CYAN}Legend:${NC}"
echo -e "  ${GREEN}✓${NC} = Healthy/OK       ${YELLOW}⚠${NC} = Warning       ${RED}✗${NC} = Error"
echo -e "  ${MAGENTA}↑${NC} = Scale UP        ${BLUE}↓${NC} = Scale DOWN     ${CYAN}~${NC} = Cooldown/Blocked"
echo ""
echo "────────────────────────────────────────────────────────────────────"
echo ""

# Color code for RPS thresholds
color_rps() {
    local rps=$1
    if (( $(echo "$rps > 100" | bc -l) )); then
        echo -e "${RED}${rps}${NC}"
    elif (( $(echo "$rps > 50" | bc -l) )); then
        echo -e "${MAGENTA}${rps}${NC}"
    elif (( $(echo "$rps > 20" | bc -l) )); then
        echo -e "${YELLOW}${rps}${NC}"
    else
        echo -e "${GREEN}${rps}${NC}"
    fi
}

# Function to show status
show_status() {
    POD=$(kubectl get pod -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    # Pod status
    if [ -z "$POD" ]; then
        echo -e "${RED}✗ Pod not running${NC}"
        return 1
    fi
    
    READY=$(kubectl get pod "$POD" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$READY" = "True" ]; then
        echo -e "${GREEN}✓ Pod: $POD${NC}"
    else
        echo -e "${RED}✗ Pod: $POD (not ready)${NC}"
    fi
    
    # Age
    AGE=$(kubectl get pod "$POD" -o jsonpath='{.metadata.managedFields[0].time}' 2>/dev/null | cut -dT -f2 | cut -d: -f1-2)
    RESTARTS=$(kubectl get pod "$POD" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    echo "  Age: $(date +%H:%M:%S) | Restarts: $RESTARTS"
    echo ""
}

# Function to parse and display logs
show_logs() {
    LOGS=$(kubectl logs deployment/reactive-autoscaler --tail=200 2>/dev/null || echo "")
    
    echo -e "${CYAN}[Recent Activity]${NC}"
    echo ""
    
    # Count events
    UPSCALE=$(echo "$LOGS" | grep -c "UPSCALE" || echo 0)
    DOWNSCALE=$(echo "$LOGS" | grep -c "DOWNSCALE" || echo 0)
    
    echo "  Scaling Events:"
    echo -e "    ${MAGENTA}↑ UPSCALE${NC}: $UPSCALE times"
    echo -e "    ${BLUE}↓ DOWNSCALE${NC}: $DOWNSCALE times"
    echo ""
    
    # Show RPS trends
    echo "  Latest Metrics:"
    RPS_LINES=$(echo "$LOGS" | grep "RPS:" | tail -5 || echo "")
    if [ -n "$RPS_LINES" ]; then
        echo "$RPS_LINES" | while read line; do
            # Extract service name and RPS
            SERVICE=$(echo "$line" | sed -n 's/.*\([a-z-]*\) RPS:.*/\1/p' | tail -1)
            RPS=$(echo "$line" | sed -n 's/.*RPS: \([0-9.]*\).*/\1/p' | tail -1)
            if [ -n "$SERVICE" ] && [ -n "$RPS" ]; then
                echo "    $SERVICE: $(color_rps $RPS)"
            else
                echo "    $line" | head -c 60
            fi
        done
    else
        echo "    (no metrics yet)"
    fi
    echo ""
    
    # Show scaling decisions
    echo "  Latest Scaling Decisions:"
    SCALE_LINES=$(echo "$LOGS" | grep -E "UPSCALE|DOWNSCALE|BLOCKED" | tail -5 || echo "")
    if [ -n "$SCALE_LINES" ]; then
        echo "$SCALE_LINES" | while read line; do
            if echo "$line" | grep -q "UPSCALE"; then
                echo -e "    ${MAGENTA}↑${NC} $(echo $line | sed 's/.*UPSCALE//' | head -c 50)"
            elif echo "$line" | grep -q "DOWNSCALE"; then
                echo -e "    ${BLUE}↓${NC} $(echo $line | sed 's/.*DOWNSCALE//' | head -c 50)"
            elif echo "$line" | grep -q "BLOCKED"; then
                echo -e "    ${CYAN}~${NC} $(echo $line | sed 's/.*BLOCKED//' | head -c 50)"
            fi
        done
    else
        echo "    (no scaling events yet - generate traffic to test)"
    fi
    echo ""
}

# Function to show deployments being monitored
show_deployments() {
    echo -e "${CYAN}[Monitored Deployments]${NC}"
    echo ""
    
    DEPLOYMENTS=$(kubectl get deployment -o name 2>/dev/null | grep -v kube-system || echo "")
    if [ -z "$DEPLOYMENTS" ]; then
        echo "  (no deployments found)"
    else
        kubectl get deployment -o wide 2>/dev/null | tail -n +2 | while read line; do
            NAME=$(echo $line | awk '{print $1}')
            REPLICAS=$(echo $line | awk '{print $2}')
            READY=$(echo $line | awk '{print $3}')
            
            if [ "$REPLICAS" = "$READY" ]; then
                STATUS="${GREEN}✓${NC}"
            else
                STATUS="${YELLOW}⚠${NC}"
            fi
            
            echo "  $STATUS $NAME: $READY/$REPLICAS replicas"
        done
    fi
    echo ""
}

# Function to show errors/warnings
show_health() {
    echo -e "${CYAN}[Health Check]${NC}"
    echo ""
    
    POD=$(kubectl get pod -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$POD" ]; then
        echo -e "  ${RED}✗ Pod not found${NC}"
        return
    fi
    
    LOGS=$(kubectl logs deployment/reactive-autoscaler --tail=50 2>/dev/null || echo "")
    
    # Check for errors
    if echo "$LOGS" | grep -q "ERROR\|Exception\|ConnectionError"; then
        echo -e "  ${RED}✗ Errors detected in logs${NC}"
        echo "$LOGS" | grep "ERROR\|Exception\|ConnectionError" | tail -1
    else
        echo -e "  ${GREEN}✓ No errors${NC}"
    fi
    
    # Check for Prometheus connectivity
    if echo "$LOGS" | grep -q "Prometheus"; then
        echo -e "  ${GREEN}✓ Prometheus connected${NC}"
    else
        echo -e "  ${YELLOW}⚠ Prometheus status unknown${NC}"
    fi
    
    # Check if metrics are flowing
    METRICS_COUNT=$(echo "$LOGS" | grep -c "RPS:" || echo 0)
    if [ "$METRICS_COUNT" -gt 0 ]; then
        echo -e "  ${GREEN}✓ Metrics flowing ($METRICS_COUNT in last 50 lines)${NC}"
    else
        echo -e "  ${YELLOW}⚠ No recent metrics${NC}"
    fi
    
    echo ""
}

# Main loop
ITERATION=0
while true; do
    # Clear and show fresh data
    clear
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║        AUTOSCALER REAL-TIME MONITORING DASHBOARD              ║${NC}"
    echo -e "${CYAN}║  Updated: $(date '+%Y-%m-%d %H:%M:%S')                             ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    show_status
    show_health
    show_logs
    show_deployments
    
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────${NC}"
    echo -e "Updating every 5 seconds... (Iteration: $ITERATION, Press Ctrl+C to stop)"
    
    ((ITERATION++))
    sleep 5
done
