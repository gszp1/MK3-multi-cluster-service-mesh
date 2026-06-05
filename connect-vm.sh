#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/infrastructure/outputs/config.json"
KEY="$SCRIPT_DIR/infrastructure/outputs/core-key.pem"

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

echo "Connecting to ec2-user@$HOST..."
exec ssh -i "$KEY" -o StrictHostKeyChecking=no ec2-user@"$HOST"
