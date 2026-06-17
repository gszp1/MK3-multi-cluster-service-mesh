#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export KUBECONFIG="${KUBECONFIG:-$ROOT_DIR/kubeconfig/kubeconfig.yaml}"

SENDER_CLUSTER="kind-remote-1"
RESPONDER_CLUSTER="kind-remote-2"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "Error: kubeconfig $KUBECONFIG not found. Run ./connect-clusters.sh first."
  exit 1
fi

# Namespaces + services exist on BOTH clusters so the east-west gateway can
# resolve service DNS cross-cluster, even where the workload does not run.
apply_shared() {
  local ctx="$1"
  echo "  - namespaces (sender-ns, responder-ns)"
  kubectl --context "$ctx" apply -f "$SCRIPT_DIR/sender-ns.yml"
  kubectl --context "$ctx" apply -f "$SCRIPT_DIR/responder-ns.yml"
  echo "  - services (sender-svc, responder-svc)"
  kubectl --context "$ctx" apply -n sender-ns    -f "$SCRIPT_DIR/sender-svc.yml"
  kubectl --context "$ctx" apply -n responder-ns -f "$SCRIPT_DIR/responder-svc.yml"
}

echo "[1] Applying shared resources on $SENDER_CLUSTER..."
apply_shared "$SENDER_CLUSTER"

echo "[2] Applying shared resources on $RESPONDER_CLUSTER..."
apply_shared "$RESPONDER_CLUSTER"

echo "[3] Deploying sender to $SENDER_CLUSTER (sender-ns)..."
kubectl --context "$SENDER_CLUSTER" apply -n sender-ns -f "$SCRIPT_DIR/sender.yaml"

echo "[4] Deploying responder to $RESPONDER_CLUSTER (responder-ns)..."
kubectl --context "$RESPONDER_CLUSTER" apply -n responder-ns -f "$SCRIPT_DIR/responder.yml"

echo "[5] Waiting for rollouts..."
kubectl --context "$SENDER_CLUSTER"    -n sender-ns    rollout status deployment/sender
kubectl --context "$RESPONDER_CLUSTER" -n responder-ns rollout status deployment/responder

echo ""
echo "Done."
echo "  sender    -> $SENDER_CLUSTER    (sender-ns)"
echo "  responder -> $RESPONDER_CLUSTER (responder-ns)"