#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$ROOT_DIR/infrastructure/outputs/config.json"
KEY="$ROOT_DIR/infrastructure/outputs/core-key.pem"

TAG="${1:-latest}"
CLUSTERS=(primary remote-1 remote-2)
IMAGES=("responder:${TAG}" "sender:${TAG}")
REMOTE_ARCHIVE="/tmp/example-apps-images.tar"

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: $CONFIG not found. Run ./run.sh first to provision infrastructure."
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "Error: $KEY not found. Run ./run.sh first to provision infrastructure."
  exit 1
fi

HOST=$(jq -r '.core.public_ip' "$CONFIG")

if [[ -z "$HOST" || "$HOST" == "null" ]]; then
  echo "Error: Could not read public IP from $CONFIG."
  exit 1
fi

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o BatchMode=yes"

echo "[1] Building images..."
"$SCRIPT_DIR/build-images.sh" "$TAG"

echo "[2] Saving images to archive..."
LOCAL_ARCHIVE="$(mktemp --suffix=.tar)"
trap 'rm -f "$LOCAL_ARCHIVE"' EXIT
docker save "${IMAGES[@]}" -o "$LOCAL_ARCHIVE"

echo "[3] Copying archive to $HOST..."
scp $SSH_OPTS "$LOCAL_ARCHIVE" ec2-user@"$HOST":"$REMOTE_ARCHIVE"

echo "[4] Loading images into kind clusters..."
for cluster in "${CLUSTERS[@]}"; do
  echo "    -> $cluster"
  ssh $SSH_OPTS ec2-user@"$HOST" "kind load image-archive $REMOTE_ARCHIVE --name $cluster"
done

echo "[5] Cleaning up remote archive..."
ssh $SSH_OPTS ec2-user@"$HOST" "rm -f $REMOTE_ARCHIVE"

echo ""
echo "Done. Loaded ${IMAGES[*]} into: ${CLUSTERS[*]}"