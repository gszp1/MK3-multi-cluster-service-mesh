#!/bin/bash

# Usage:
#   ./kwok/remove-cluster.sh NAME

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NAME="${1:-}"
if [[ -z "$NAME" ]]; then
  echo "Usage: ./kwok/remove-cluster.sh NAME"
  exit 1
fi

CTX="kwok-$NAME"
REMOTE_SECRET="istio-remote-secret-$NAME"

CONFIG="$REPO_DIR/infrastructure/outputs/config.json"
KEY="$REPO_DIR/infrastructure/outputs/core-key.pem"
CERTS_DIR="$REPO_DIR/certs"
KUBECONFIG_DIR="$REPO_DIR/kubeconfig"
MERGED_KUBECONFIG="$KUBECONFIG_DIR/kubeconfig.yaml"
REGISTRY="$SCRIPT_DIR/kwok-clusters.json"

export KUBECONFIG="$MERGED_KUBECONFIG"

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: $CONFIG not found. Run ./run.sh first."
  exit 1
fi

HOST=$(jq -r '.core.public_ip' "$CONFIG")
if [[ -z "$HOST" || "$HOST" == "null" ]]; then
  echo "Error: Could not read public IP from $CONFIG."
  exit 1
fi

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o BatchMode=yes"
ssh_core() { ssh $SSH_OPTS ec2-user@"$HOST" "$@"; }

APISERVER_PORT=""
if [[ -f "$REGISTRY" ]]; then
  APISERVER_PORT=$(jq -r --arg n "$NAME" \
    '.clusters[] | select(.name==$n) | .apiserver_port // empty' "$REGISTRY")
fi
if [[ -z "$APISERVER_PORT" ]]; then
  SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name==\"$CTX\")].cluster.server}" 2>/dev/null || true)
  APISERVER_PORT="${SERVER##*:}"
fi

echo "Removing kwok cluster '$NAME' (context: $CTX, port: ${APISERVER_PORT:-unknown})."

echo "[1] Deleting remote secret '$REMOTE_SECRET' on primary..."
kubectl --context="kind-primary" -n istio-system delete secret "$REMOTE_SECRET" --ignore-not-found || true

echo "[2] Deleting kwok cluster '$NAME' on $HOST..."
ssh_core "kwokctl get clusters | grep -qx '$NAME' && kwokctl delete cluster --name '$NAME' || echo '    (cluster not present on host)'" || true

echo "[3] Closing SSH tunnel on :${APISERVER_PORT:-?}..."
if [[ -n "$APISERVER_PORT" ]]; then
  fuser -k "${APISERVER_PORT}/tcp" 2>/dev/null || true
else
  echo "    (port unknown, skipping)"
fi

echo "[4] Removing kubeconfig context/cluster/user '$CTX'..."
kubectl config delete-context "$CTX" 2>/dev/null || true
kubectl config delete-cluster "$CTX" 2>/dev/null || true
kubectl config delete-user "$CTX" 2>/dev/null || true

echo "[5] Removing per-cluster certs dir..."
rm -rf "${CERTS_DIR:?}/$NAME"

echo "[6] Removing entry from $REGISTRY..."
if [[ -f "$REGISTRY" ]]; then
  jq --arg n "$NAME" '.clusters |= map(select(.name != $n))' "$REGISTRY" > "$REGISTRY.new"
  mv "$REGISTRY.new" "$REGISTRY"
fi

echo "[7] Re-running Kiali install so the removed cluster disappears from its view..."
if kubectl --context="kind-primary" -n istio-system get deployment/kiali >/dev/null 2>&1; then
  bash "$REPO_DIR/kiali/install-kiali.sh"
  kubectl --context="kind-primary" -n istio-system rollout status deployment/kiali --timeout=120s || true
else
  echo "    (Kiali not installed, skipping)"
fi

echo ""
echo "Done. kwok cluster '$NAME' removed from the mesh."
echo "Verify from the primary:"
echo "  istioctl --context kind-primary remote-clusters"
