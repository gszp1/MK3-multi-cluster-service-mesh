#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig/kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_FILE"

declare -A CLUSTER_NETWORKS=(
  [kind-remote-1]="network2"
  [kind-remote-2]="network3"
)

echo "[1] Fetching east-west gateway address from primary..."
ISTIOD_REMOTE_ADDRESS=$(kubectl --context="kind-primary" -n istio-system \
  get svc istio-eastwestgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [[ -z "$ISTIOD_REMOTE_ADDRESS" ]]; then
  echo "Error: Could not get east-west gateway IP from primary. Run istio-config-primary.sh first."
  exit 1
fi

echo "    istiod address: $ISTIOD_REMOTE_ADDRESS"

for CTX in "${!CLUSTER_NETWORKS[@]}"; do
  NETWORK="${CLUSTER_NETWORKS[$CTX]}"
  CLUSTER_NAME="${CTX#kind-}"

  echo ""
  echo "=== Configuring $CTX (network: $NETWORK) ==="

  echo "  [2] Labeling istio-system namespace..."
  kubectl --context="$CTX" label namespace istio-system \
    topology.istio.io/network="$NETWORK" --overwrite

  echo "  [3] Installing Istio data plane..."
  CLUSTER_NAME="$CLUSTER_NAME" NETWORK="$NETWORK" ISTIOD_REMOTE_ADDRESS="$ISTIOD_REMOTE_ADDRESS" \
    envsubst < "$SCRIPT_DIR/remote-manifests/remote-operator.yml.tmpl" \
    | istioctl install --context="$CTX" -y -f -

  echo "  [4] Installing east-west gateway..."
  NETWORK="$NETWORK" envsubst < "$SCRIPT_DIR/remote-manifests/eastwest-operator.yml.tmpl" \
    | istioctl install --context="$CTX" -y -f -

  echo "  [5] Waiting for east-west gateway to be ready..."
  kubectl --context="$CTX" -n istio-system \
    rollout status deployment/istio-eastwestgateway --timeout=120s

  echo "  [6] Exposing services through east-west gateway..."
  kubectl --context="$CTX" apply -f "$SCRIPT_DIR/remote-manifests/expose-services.yml"

  echo "  [7] Creating remote secret on primary..."
  istioctl create-remote-secret \
    --context="$CTX" \
    --name="$CLUSTER_NAME" \
    | kubectl --context="kind-primary" apply -f -

  echo "  -> $CTX done."
done

echo ""
echo "Done. All remote clusters configured."
