#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/infrastructure/outputs/config.json"
KEY="$SCRIPT_DIR/infrastructure/outputs/core-key.pem"
KUBECONFIG_DIR="$SCRIPT_DIR/kubeconfig"
MERGED_KUBECONFIG="$KUBECONFIG_DIR/kubeconfig.yaml"

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

echo "[1] Fetching kubeconfigs from $HOST..."
mkdir -p "$KUBECONFIG_DIR"

for cluster in primary remote-1 remote-2; do
  ssh $SSH_OPTS ec2-user@"$HOST" "kind get kubeconfig --name $cluster" \
    > "$KUBECONFIG_DIR/kubeconfig-$cluster.yaml"
done

echo "[2] Patching server addresses to localhost..."
# primary -> 6441, remote-1 -> 6442, remote-2 -> 6443
sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://127.0.0.1:6441|g" \
  "$KUBECONFIG_DIR/kubeconfig-primary.yaml"
sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://127.0.0.1:6442|g" \
  "$KUBECONFIG_DIR/kubeconfig-remote-1.yaml"
sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://127.0.0.1:6443|g" \
  "$KUBECONFIG_DIR/kubeconfig-remote-2.yaml"

echo "[3] Merging kubeconfigs..."
KUBECONFIG="$KUBECONFIG_DIR/kubeconfig-primary.yaml:$KUBECONFIG_DIR/kubeconfig-remote-1.yaml:$KUBECONFIG_DIR/kubeconfig-remote-2.yaml" \
  kubectl config view --flatten > "$MERGED_KUBECONFIG"
chmod 600 "$MERGED_KUBECONFIG"
rm -f "$KUBECONFIG_DIR/kubeconfig-primary.yaml" \
      "$KUBECONFIG_DIR/kubeconfig-remote-1.yaml" \
      "$KUBECONFIG_DIR/kubeconfig-remote-2.yaml"

echo "[4] Starting SSH tunnels (background)..."
# Kill any existing tunnels for these ports
for port in 6441 6442 6443; do
  fuser -k "${port}/tcp" 2>/dev/null || true
done

ssh $SSH_OPTS \
  -L 6441:localhost:6441 \
  -L 6442:localhost:6442 \
  -L 6443:localhost:6443 \
  -N -f ec2-user@"$HOST"

echo ""
echo "Done. Export the kubeconfig and switch contexts:"
echo ""
echo "  export KUBECONFIG=$MERGED_KUBECONFIG"
echo ""
echo "  kubectl config use-context kind-primary"
echo "  kubectl config use-context kind-remote-1"
echo "  kubectl config use-context kind-remote-2"
echo ""
echo "To stop tunnels: kill \$(pgrep -f 'ssh.*6441.*6442.*6443')"