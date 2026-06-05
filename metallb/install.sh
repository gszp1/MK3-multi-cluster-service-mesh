#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METALLB_VERSION="v0.14.9"
METALLB_MANIFEST="https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"

export KUBECONFIG="$SCRIPT_DIR/../kubeconfig/kubeconfig.yaml"

declare -A POOLS=(
  [kind-primary]="172.18.100.0/24"
  [kind-remote-1]="172.18.101.0/24"
  [kind-remote-2]="172.18.102.0/24"
)

echo "[1] Installing MetalLB in all clusters..."
for context in "${!POOLS[@]}"; do
  echo "  -> $context"
  kubectl --context "$context" apply -f "$METALLB_MANIFEST"
done

echo "[2] Waiting for MetalLB controller to be ready..."
for context in "${!POOLS[@]}"; do
  echo "  -> $context"
  kubectl --context "$context" -n metallb-system \
    rollout status deployment/controller --timeout=120s
done

echo "[3] Configuring IP address pools..."
for context in "${!POOLS[@]}"; do
  pool="${POOLS[$context]}"
  echo "  -> $context ($pool)"
  kubectl --context "$context" apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default
  namespace: metallb-system
spec:
  addresses:
  - ${pool}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default
  namespace: metallb-system
EOF
done

echo ""
echo "Done. MetalLB installed in all clusters."