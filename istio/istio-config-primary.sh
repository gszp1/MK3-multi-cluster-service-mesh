#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig/kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_FILE"

CTX="kind-primary"

echo "[1] Labeling istio-system namespace with network topology..."
kubectl --context="$CTX" label namespace istio-system \
  topology.istio.io/network=network1 --overwrite

echo "[2] Installing Istio control plane on primary..."
istioctl install --context="$CTX" -f "$SCRIPT_DIR/primary-manifests/primary-operator.yml" -y

echo "[3] Waiting for istiod to be ready..."
kubectl --context="$CTX" -n istio-system \
  rollout status deployment/istiod --timeout=120s

echo "[4] Installing east-west gateway..."
istioctl install --context="$CTX" -y -f "$SCRIPT_DIR/primary-manifests/eastwest-operator.yml"

echo "[5] Waiting for east-west gateway to be ready..."
kubectl --context="$CTX" -n istio-system \
  rollout status deployment/istio-eastwestgateway --timeout=120s

echo "[6] Exposing istiod for remote clusters..."
kubectl --context="$CTX" apply -f "$SCRIPT_DIR/primary-manifests/expose-istiod.yml"

echo "[7] Exposing services through east-west gateway..."
kubectl --context="$CTX" apply -f "$SCRIPT_DIR/primary-manifests/expose-services.yml"

echo ""
echo "Done. Primary cluster configured."
echo ""
echo "East-west gateway external IP:"
kubectl --context="$CTX" -n istio-system \
  get svc istio-eastwestgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
echo ""
