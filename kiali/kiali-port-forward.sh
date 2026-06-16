#!/usr/bin/bash

kubectl --context kind-primary -n istio-system port-forward svc/kiali 20002:20001