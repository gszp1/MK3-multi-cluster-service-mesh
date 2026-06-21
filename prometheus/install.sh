#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig/kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_FILE"

# Istio release branch to pull the Prometheus addon from (matches istioctl 1.30).
ISTIO_RELEASE="release-1.30"
PROM_ADDON="https://raw.githubusercontent.com/istio/istio/${ISTIO_RELEASE}/samples/addons/prometheus.yaml"

PRIMARY_CTX="kind-primary"
CONTEXTS=("kind-primary" "kind-remote-1" "kind-remote-2")

# Fixed LoadBalancer IPs for the remote Prometheus instances. Each address sits
# inside that cluster's MetalLB pool (see metallb/install.sh).
declare -A REMOTE_PROM_IP=(
  [kind-remote-1]="172.18.101.200"
  [kind-remote-2]="172.18.102.200"
)
PROM_PORT="9090"

echo "[1] Deploying Prometheus addon in all clusters..."
for ctx in "${CONTEXTS[@]}"; do
  echo "  -> $ctx"
  kubectl --context "$ctx" apply -f "$PROM_ADDON"
done

echo "[2] Waiting for Prometheus to be ready..."
for ctx in "${CONTEXTS[@]}"; do
  echo "  -> $ctx"
  kubectl --context "$ctx" -n istio-system \
    rollout status deployment/prometheus --timeout=120s
done

echo "[3] Exposing remote Prometheus instances via MetalLB LoadBalancer..."
for ctx in "${!REMOTE_PROM_IP[@]}"; do
  ip="${REMOTE_PROM_IP[$ctx]}"
  echo "  -> $ctx ($ip)"
  kubectl --context "$ctx" -n istio-system annotate svc prometheus \
    "metallb.universe.tf/loadBalancerIPs=${ip}" --overwrite
  kubectl --context "$ctx" -n istio-system patch svc prometheus \
    --type merge -p '{"spec":{"type":"LoadBalancer"}}'
done

echo "[4] Injecting federation job into primary Prometheus..."
CURRENT_CFG=$(kubectl --context "$PRIMARY_CTX" -n istio-system \
  get configmap prometheus -o jsonpath='{.data.prometheus\.yml}')

PATCH=$(printf '%s' "$CURRENT_CFG" | python3 "$SCRIPT_DIR/inject-federation.py" \
  "${REMOTE_PROM_IP[kind-remote-1]}:${PROM_PORT}" \
  "${REMOTE_PROM_IP[kind-remote-2]}:${PROM_PORT}")

kubectl --context "$PRIMARY_CTX" -n istio-system \
  patch configmap prometheus --type merge -p "$PATCH"

echo "[5] Restarting primary Prometheus to pick up the new config..."
kubectl --context "$PRIMARY_CTX" -n istio-system \
  rollout restart deployment/prometheus
kubectl --context "$PRIMARY_CTX" -n istio-system \
  rollout status deployment/prometheus --timeout=120s

echo ""
echo "Done. Prometheus installed in all clusters; primary federates the remotes."
echo "Kiali (primary) should now show cross-cluster traffic once requests flow."