#!/bin/bash
echo "Starting load test..."
echo "This will generate traffic to frontend service"
echo "Press Ctrl+C to stop"
echo ""

# Generate moderate load
kubectl run load-generator \
  --image=busybox \
  --restart=Never \
  --rm -i --tty \
  -- sh -c '
  echo "Load generator started"
  echo "Hitting frontend service every 0.1 seconds"
  i=0
  while true; do
    wget -q -O- http://frontend.default.svc.cluster.local >/dev/null 2>&1 &
    i=$((i+1))
    if [ $((i % 10)) -eq 0 ]; then
      echo "Sent $i requests..."
    fi
    sleep 0.1
  done
'
