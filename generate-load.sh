#!/bin/bash
echo "Generating load on frontend service..."
echo "Press Ctrl+C to stop"
kubectl run load-gen --rm -i --tty --image=busybox --restart=Never -- sh -c \
  'while true; do 
     for i in $(seq 1 10); do
       wget -q -O- http://frontend.default.svc.cluster.local &
     done
     sleep 1
   done'
