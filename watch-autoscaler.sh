#!/bin/bash
POD=$(kubectl get pods -l app=reactive-autoscaler -o jsonpath='{.items[0].metadata.name}')
echo "Watching autoscaler: $POD"
kubectl logs -f "$POD" | grep --color=auto -E 'UPSCALE|DOWNSCALE|ERROR|$'
