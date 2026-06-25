#!/usr/bin/bash

trap 'echo; echo "Stopped"; exit 0' INT

while true; do
  kubectl --context kind-primary -n istio-system port-forward svc/kiali 20002:20001 || true
  echo "port-forward broken, retrying in 2 seconds .. (Ctrl-C to stop)"
  sleep 2
done