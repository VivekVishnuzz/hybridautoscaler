#!/bin/bash
echo "=== Autoscaler Status ==="
kubectl get pods -l app=reactive-autoscaler
echo ""
echo "=== Service Deployments ==="
kubectl get deployments frontend checkoutservice recommendationservice
echo ""
echo "=== Recent Scaling Events ==="
kubectl logs deployment/reactive-autoscaler --tail=50 | grep -E 'UPSCALE|DOWNSCALE' || echo "No scaling events yet"
