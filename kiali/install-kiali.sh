#!/usr/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig/kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_FILE"

CTX="kind-primary"

helm repo add kiali https://kiali.org/helm-charts

helm repo update

helm upgrade --install \
  --kube-context="$CTX" \
  --namespace istio-system \
  --set auth.strategy="anonymous" \
  --set server.web_port=20001 \
  --set deployment.service_type=LoadBalancer \
  --set external_services.prometheus.url="http://prometheus.istio-system:9090" \
  --repo https://kiali.org/helm-charts \
  kiali-server \
  kiali-server
