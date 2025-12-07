#!/bin/bash
# Quick restart script for your autoscaler

echo "🚀 Restarting Autoscaler System"
echo "================================"

# Start k3s
echo "▶ Starting k3s..."
sudo systemctl start k3s
sleep 5

# Check everything
echo "▶ Checking system status..."
kubectl get pods

echo ""
echo "✅ System Status:"
kubectl get deployment reactive-autoscaler frontend prometheus-server 2>/dev/null || echo "Some components not found"

echo ""
echo "📊 Quick Commands:"
echo "  Watch logs: kubectl logs -f deployment/reactive-autoscaler"
echo "  Generate load: for i in 1 2 3; do kubectl run load-\$i --image=busybox --restart=Never -- sh -c 'while true; do wget -q -O- http://frontend; done' & done"
echo "  Watch scaling: kubectl get deployment frontend --watch"
