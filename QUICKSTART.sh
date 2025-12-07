#!/bin/bash

# ========================================================================
# Quick Start Guide - Kubernetes Deployment
# ========================================================================
# This is a quick reference for common deployment tasks
# ========================================================================

cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║    🚀 LIVE REACTIVE AUTOSCALER - QUICK START GUIDE                       ║
╚═══════════════════════════════════════════════════════════════════════════╝

📋 PREREQUISITES
────────────────
Before deploying, ensure you have:
  1. kubectl configured and connected to a Kubernetes cluster
  2. Prometheus deployed in the cluster
  3. Your services exposing Prometheus metrics (/metrics endpoint)
  4. Docker CLI (for building the image)
  5. Access to a container registry (Docker Hub, ECR, ACR, etc.)

Check prerequisites:
  kubectl cluster-info
  kubectl get svc -l app.kubernetes.io/name=prometheus

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 CONFIGURATION BEFORE DEPLOYMENT
────────────────────────────────────

1. Build and push your Docker image:

   export REGISTRY="your-dockerhub-username"
   export IMAGE_TAG="v1"
   docker build -t $REGISTRY/reactive-autoscaler:$IMAGE_TAG .
   docker push $REGISTRY/reactive-autoscaler:$IMAGE_TAG

2. (Optional) Customize configuration in config.yaml:
   - Edit Prometheus URL if different from default
   - Adjust RPS thresholds for your workload
   - Change cooldown period and smoothing factor

3. (Optional) Customize rbac.yaml for your namespace

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚀 DEPLOY USING AUTOMATED SCRIPT (RECOMMENDED)
────────────────────────────────────────────────

This deploys all components with a single command:

  export REGISTRY="your-registry"
  export IMAGE_TAG="v1"
  export NAMESPACE="default"
  ./deploy.sh

The script will:
  ✓ Verify prerequisites
  ✓ Build Docker image
  ✓ Deploy RBAC configuration
  ✓ Deploy ConfigMap
  ✓ Deploy autoscaler pod
  ✓ Verify deployment
  ✓ Show monitoring commands

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚀 DEPLOY MANUALLY (STEP BY STEP)
──────────────────────────────────

Step 1: Deploy RBAC (permissions)
  kubectl apply -f rbac.yaml -n default

Step 2: Deploy ConfigMap (configuration)
  kubectl apply -f config.yaml -n default

Step 3: Update and deploy the autoscaler
  # Edit deployment.yaml and replace:
  #   image: your-registry/reactive-autoscaler:v1
  # Then deploy:
  kubectl apply -f deployment.yaml -n default

Step 4: Verify deployment
  kubectl get pods -l app=reactive-autoscaler
  kubectl logs -f deployment/reactive-autoscaler

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ VERIFY DEPLOYMENT
────────────────────

Check if everything is running:

  # Pod status
  kubectl get pods -l app=reactive-autoscaler

  # Pod logs (should show initialization and metric collection)
  kubectl logs -f deployment/reactive-autoscaler

  # View configuration
  kubectl get configmap autoscaler-config -o yaml

  # Check RBAC
  kubectl get serviceaccount autoscaler
  kubectl get role autoscaler-role
  kubectl get rolebinding autoscaler-binding

Expected output in logs:
  "🚀 Live Reactive Autoscaler initialized"
  "Monitoring X services: [service1, service2, ...]"
  "📊 Metrics collected from Prometheus"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 MONITOR SCALING IN ACTION
─────────────────────────────

Watch autoscaler logs:
  kubectl logs -f deployment/reactive-autoscaler

Filter for scaling actions:
  kubectl logs deployment/reactive-autoscaler | grep "UPSCALE\|DOWNSCALE"

Watch deployment replicas change:
  kubectl get deployment --watch

Check pod resource usage:
  kubectl top pod -l app=reactive-autoscaler

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🧪 TESTING (LOCAL WITH MINIKUBE)
─────────────────────────────────

1. Start minikube:
   minikube start

2. Deploy Prometheus:
   helm install prometheus prometheus-community/prometheus

3. Deploy test service:
   kubectl create deployment test-app --image=nginx --replicas=1
   kubectl expose deployment test-app --port=80

4. Generate load:
   kubectl run -i --tty load-gen --rm --image=busybox --restart=Never -- /bin/sh
   # Inside: while true; do wget -q -O- http://test-app; done

5. Watch scaling:
   kubectl get deployment test-app --watch

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 COMMON CUSTOMIZATIONS
─────────────────────────

1. Change Prometheus URL:
   kubectl set env deployment/reactive-autoscaler \
     PROMETHEUS_URL="http://custom-prometheus:9090"

2. Change cooldown period:
   # Edit config.yaml, change "cooldown_period": 60
   kubectl delete configmap autoscaler-config
   kubectl apply -f config.yaml

3. Watch multiple namespaces:
   # Requires code modification in reactive.py

4. Custom metric thresholds:
   # Edit RPS_THRESHOLDS in config.yaml

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🆘 TROUBLESHOOTING
──────────────────

Pod not starting?
  kubectl describe pod -l app=reactive-autoscaler
  kubectl logs deployment/reactive-autoscaler

Can't connect to Prometheus?
  kubectl exec -it deployment/reactive-autoscaler -- \
    curl http://prometheus-server:9090/api/v1/query?query=up

Scaling not happening?
  # Check logs for errors
  kubectl logs deployment/reactive-autoscaler | grep -i error

  # Verify RBAC permissions
  kubectl auth can-i patch deployments/scale --as=system:serviceaccount:default:autoscaler

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🗑️  CLEANUP
───────────

Remove autoscaler and all resources:

  # Delete deployment and dependencies
  kubectl delete deployment reactive-autoscaler
  kubectl delete configmap autoscaler-config
  kubectl delete rolebinding autoscaler-binding
  kubectl delete role autoscaler-role
  kubectl delete serviceaccount autoscaler

  # Or all at once
  kubectl delete -f deployment.yaml -f config.yaml -f rbac.yaml

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📚 DOCUMENTATION
────────────────

For detailed information, see:
  • README.md - Complete deployment guide
  • reactive.py - Source code with comments
  • deploy.sh - Automated deployment script

Key configuration files:
  • deployment.yaml - Kubernetes pod configuration
  • config.yaml - Autoscaler settings
  • rbac.yaml - Kubernetes permissions
  • Dockerfile - Container image

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 NEXT STEPS
─────────────

1. Update your Docker registry in deploy.sh or manually in deployment.yaml
2. Run ./deploy.sh or deploy manually
3. Watch logs: kubectl logs -f deployment/reactive-autoscaler
4. Generate traffic to test scaling
5. Tune thresholds based on your workload
6. Integrate with your monitoring/alerting system

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For help:
  • kubectl logs -f deployment/reactive-autoscaler
  • kubectl describe pod -l app=reactive-autoscaler
  • kubectl get events

EOF
