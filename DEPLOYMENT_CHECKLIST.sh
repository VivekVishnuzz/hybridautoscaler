#!/bin/bash

# ========================================================================
# KUBERNETES AUTOSCALER - DEPLOYMENT CHECKLIST
# ========================================================================
# Follow this checklist to ensure everything is ready for deployment
# ========================================================================

cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════════════╗
║         ✅ KUBERNETES AUTOSCALER - DEPLOYMENT CHECKLIST                  ║
╚═══════════════════════════════════════════════════════════════════════════╝

📋 BEFORE YOU START
═══════════════════════════════════════════════════════════════════════════

Prerequisites (check all):
  ☐ Kubernetes cluster is running and accessible
  ☐ kubectl is installed and configured
  ☐ Docker is installed (for building images)
  ☐ Access to container registry (Docker Hub, ECR, ACR, etc.)
  ☐ Prometheus is deployed in your cluster
  ☐ Your services expose /metrics endpoint with Prometheus format

Test prerequisites:
  $ kubectl cluster-info
  $ kubectl get nodes
  $ docker version
  $ kubectl get svc -l app.kubernetes.io/name=prometheus

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📦 DEPLOYMENT PACKAGE CONTENTS
═══════════════════════════════════════════════════════════════════════════

Files provided (verify all present):
  ☐ reactive.py - Core autoscaler code
  ☐ Dockerfile - Container image definition
  ☐ rbac.yaml - Kubernetes permissions
  ☐ config.yaml - Configuration/ConfigMap
  ☐ deployment.yaml - Deployment manifest
  ☐ deploy.sh - Automated deployment script
  ☐ README.md - Complete documentation
  ☐ QUICKSTART.sh - Quick reference guide
  ☐ DEPLOYMENT_SUMMARY.md - This package summary

Check:
  $ cd /home/vivek/final
  $ ls -l *.py *.yaml *.sh *.md

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 STEP 1: PREPARE CONFIGURATION
═══════════════════════════════════════════════════════════════════════════

Configure Docker registry:
  ☐ Decide where to push image (Docker Hub, ECR, ACR, etc.)
  ☐ Note your registry URL/username
  ☐ Ensure you can authenticate with the registry

Update deployment files:
  ☐ Edit deploy.sh and set REGISTRY variable
     OR
  ☐ Edit deployment.yaml and update image field
     Replace: your-registry/reactive-autoscaler:v1
     With: your-actual-registry/reactive-autoscaler:v1

Optional configuration customization:
  ☐ Review config.yaml - adjust if needed
    - Prometheus URL
    - RPS thresholds
    - Cooldown period
    - EMA smoothing factor
    - Min/Max replicas

Check:
  $ cat deploy.sh | grep REGISTRY=
  $ cat deployment.yaml | grep "image:"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🏗️  STEP 2: BUILD AND PUSH DOCKER IMAGE
═══════════════════════════════════════════════════════════════════════════

Build Docker image:
  ☐ Run: docker build -t REGISTRY/reactive-autoscaler:v1 .
  ☐ Verify build succeeded without errors
  ☐ Check image exists: docker images | grep reactive-autoscaler

Push to registry:
  ☐ Authenticate with registry (if needed)
  ☐ Run: docker push REGISTRY/reactive-autoscaler:v1
  ☐ Verify push completed successfully
  ☐ Check image in registry (web UI or CLI)

Verify image:
  $ docker inspect REGISTRY/reactive-autoscaler:v1
  $ docker run --rm REGISTRY/reactive-autoscaler:v1 python -c "import kubernetes; print('OK')"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚀 STEP 3: DEPLOY TO KUBERNETES
═══════════════════════════════════════════════════════════════════════════

OPTION A: Automated Deployment (Recommended)
─────────────────────────────────────────────
  ☐ Set environment variables:
    export REGISTRY="your-registry"
    export IMAGE_TAG="v1"
    export NAMESPACE="default"

  ☐ Make script executable:
    chmod +x deploy.sh

  ☐ Run deployment script:
    ./deploy.sh

  ☐ Script will automatically:
    ✓ Check prerequisites
    ✓ Build Docker image
    ✓ Deploy RBAC
    ✓ Deploy ConfigMap
    ✓ Deploy autoscaler
    ✓ Verify deployment

OPTION B: Manual Deployment
──────────────────────────
  ☐ Deploy RBAC:
    kubectl apply -f rbac.yaml

  ☐ Deploy ConfigMap:
    kubectl apply -f config.yaml

  ☐ Deploy autoscaler:
    kubectl apply -f deployment.yaml

  ☐ Verify each step:
    kubectl get serviceaccount autoscaler
    kubectl get configmap autoscaler-config
    kubectl get deployment reactive-autoscaler

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ STEP 4: VERIFY DEPLOYMENT
═══════════════════════════════════════════════════════════════════════════

Check deployment status:
  ☐ Run: kubectl get pods -l app=reactive-autoscaler
  ☐ Pod should show status: Running
  ☐ Run: kubectl get deployment reactive-autoscaler
  ☐ Deployment should show: 1/1 ready

View pod logs:
  ☐ Run: kubectl logs -f deployment/reactive-autoscaler
  ☐ Should see initialization messages
  ☐ Should see: "Autoscaler initialized"
  ☐ Should see: "Monitoring X services"
  ☐ Should see: "Metrics collected"

Verify RBAC:
  ☐ ServiceAccount created: kubectl get serviceaccount autoscaler
  ☐ Role created: kubectl get role autoscaler-role
  ☐ RoleBinding created: kubectl get rolebinding autoscaler-binding

Verify ConfigMap:
  ☐ Run: kubectl get configmap autoscaler-config
  ☐ Run: kubectl get configmap autoscaler-config -o yaml
  ☐ Verify configuration looks correct

Test autoscaler connectivity:
  ☐ Get pod name: kubectl get pods -l app=reactive-autoscaler
  ☐ Test Prometheus connection:
    kubectl exec -it POD_NAME -- curl http://prometheus-server:9090/api/v1/query?query=up

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📊 STEP 5: MONITOR SCALING
═══════════════════════════════════════════════════════════════════════════

Watch autoscaler in action:
  ☐ Terminal 1: kubectl logs -f deployment/reactive-autoscaler
  ☐ Terminal 2: kubectl get deployment --watch
  ☐ Terminal 3: Generate traffic to trigger scaling

Generate test traffic:
  ☐ Create test deployment with metrics
  ☐ Run load generator to increase traffic
  ☐ Watch replicas increase/decrease
  ☐ Observe scaling decisions in logs

Monitor logs for scaling actions:
  ☐ Watch for "UPSCALE" messages (scale up)
  ☐ Watch for "DOWNSCALE" messages (scale down)
  ☐ Watch for "BLOCKED" messages (cooldown active)
  ☐ All messages should show scaling reasoning

Check resource usage:
  ☐ Run: kubectl top pod -l app=reactive-autoscaler
  ☐ CPU usage should be low (< 100m typically)
  ☐ Memory usage should be moderate (< 256Mi)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🧪 STEP 6: TESTING (OPTIONAL BUT RECOMMENDED)
═══════════════════════════════════════════════════════════════════════════

Local testing with Minikube:
  ☐ Start minikube: minikube start
  ☐ Deploy Prometheus: helm install prometheus prometheus-community/prometheus
  ☐ Create test service: kubectl create deployment test-app --image=nginx
  ☐ Generate load: kubectl run load-gen --image=busybox -- /bin/sh
  ☐ Watch scaling: kubectl get deployment test-app --watch

Test dry-run mode:
  ☐ Edit config to set DRY_RUN=true
  ☐ Verify scaling decisions logged but not executed
  ☐ Review decisions before enabling actual scaling

Test different traffic patterns:
  ☐ Gradual increase (scaling up should work)
  ☐ Gradual decrease (scaling down should work)
  ☐ Spike (rapid increase then decrease)
  ☐ Cooldown period (should prevent rapid oscillation)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔧 STEP 7: TUNING (OPTIONAL)
═══════════════════════════════════════════════════════════════════════════

If scaling is too aggressive:
  ☐ Increase COOLDOWN_PERIOD (60 → 120 seconds)
  ☐ Decrease EMA_ALPHA (0.7 → 0.5 for more smoothing)
  ☐ Adjust RPS thresholds upward
  ☐ Edit config.yaml and reapply ConfigMap

If scaling is too conservative:
  ☐ Decrease COOLDOWN_PERIOD (60 → 30 seconds)
  ☐ Increase EMA_ALPHA (0.7 → 0.9 for quicker response)
  ☐ Adjust RPS thresholds downward
  ☐ Edit config.yaml and reapply ConfigMap

For service-specific tuning:
  ☐ Review service resource needs
  ☐ Adjust min/max replicas per service
  ☐ Set different thresholds per service

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔒 PRODUCTION CHECKLIST
═══════════════════════════════════════════════════════════════════════════

Before going to production, verify:
  ☐ Autoscaler pod is running
  ☐ RBAC permissions are correct
  ☐ Prometheus connectivity works
  ☐ Services expose metrics correctly
  ☐ Scaling thresholds are appropriate
  ☐ Resource limits are set
  ☐ Cooldown prevents rapid scaling
  ☐ Monitoring/logging works
  ☐ Alerting is configured (optional but recommended)
  ☐ Rollback plan exists
  ☐ Team is trained on troubleshooting

Additional production recommendations:
  ☐ Run multiple autoscaler replicas with leader election
  ☐ Set up Prometheus alerts for autoscaler issues
  ☐ Configure log aggregation (ELK, Splunk, etc.)
  ☐ Document thresholds and why chosen
  ☐ Monitor costs (replica count trends)
  ☐ Regular review of scaling decisions

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🆘 TROUBLESHOOTING
═══════════════════════════════════════════════════════════════════════════

Pod won't start:
  ☐ Check logs: kubectl logs deployment/reactive-autoscaler
  ☐ Check events: kubectl describe pod POD_NAME
  ☐ Verify image exists: docker images
  ☐ Check resource constraints: kubectl top nodes

Can't connect to Prometheus:
  ☐ Verify Prometheus is running: kubectl get pods -l app.kubernetes.io/name=prometheus
  ☐ Check service name: kubectl get svc -l app.kubernetes.io/name=prometheus
  ☐ Test connectivity: kubectl exec POD_NAME -- curl prometheus:9090/api/v1/query
  ☐ Update PROMETHEUS_URL if different

No scaling happening:
  ☐ Check logs for errors: kubectl logs deployment/reactive-autoscaler
  ☐ Verify metrics exist in Prometheus
  ☐ Check RBAC permissions: kubectl auth can-i patch deployments/scale
  ☐ Verify services are in config
  ☐ Check if in cooldown period

Rapid scaling up/down (thrashing):
  ☐ Increase COOLDOWN_PERIOD
  ☐ Adjust EMA_ALPHA for more smoothing
  ☐ Review RPS thresholds

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📚 REFERENCE COMMANDS
═══════════════════════════════════════════════════════════════════════════

Basic commands:
  kubectl get pods -l app=reactive-autoscaler
  kubectl logs -f deployment/reactive-autoscaler
  kubectl describe deployment reactive-autoscaler

Configuration:
  kubectl get configmap autoscaler-config -o yaml
  kubectl get configmap autoscaler-config -o json

Troubleshooting:
  kubectl get events
  kubectl top pod
  kubectl top nodes

Cleanup:
  kubectl delete deployment reactive-autoscaler
  kubectl delete configmap autoscaler-config
  kubectl delete rolebinding autoscaler-binding
  kubectl delete role autoscaler-role
  kubectl delete serviceaccount autoscaler

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📋 SIGN-OFF
═══════════════════════════════════════════════════════════════════════════

When all items are checked, deployment is complete!

Deployment Date: ________________
Deployed By: ____________________
Kubernetes Cluster: ______________
Namespace: _______________________
Registry: ________________________
Image Tag: _______________________

✅ All prerequisites verified
✅ All files created and validated
✅ Docker image built and pushed
✅ RBAC deployed
✅ ConfigMap deployed
✅ Autoscaler deployed
✅ Scaling verified working
✅ Production ready

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📞 Need Help?
═══════════════════════════════════════════════════════════════════════════

1. Check logs:
   kubectl logs -f deployment/reactive-autoscaler

2. Read documentation:
   cat README.md
   cat QUICKSTART.sh

3. Verify configuration:
   kubectl get configmap autoscaler-config -o yaml

4. Test components:
   kubectl exec POD_NAME -- python -c "import kubernetes; print('OK')"

5. Check Prometheus:
   kubectl exec POD_NAME -- curl prometheus:9090/api/v1/query?query=up

EOF
