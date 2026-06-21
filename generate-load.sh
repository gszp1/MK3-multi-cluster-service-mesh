#!/bin/bash
#
# Generates continuous load against the sender service so that cross-cluster
# traffic stays visible in the Kiali traffic graph. Runs the load loop ON the
# EC2 instance over SSH (the sender is only reachable via the remote-1 kind
# node's internal IP, which exists on the instance), so you don't need to copy
# anything or log in manually.
#
# Usage:
#   ./generate-load.sh [-i interval] [-m message] [-c concurrency] [-H host]
#
# Options:
#   -i  seconds to wait between requests per worker   (default: 1)
#   -m  message content sent to the sender            (default: hello-kiali)
#   -c  number of parallel request loops              (default: 1)
#   -H  override the remote-1 node host/IP            (default: auto-detected)
#
# Stop with Ctrl-C.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/infrastructure/outputs/config.json"
KEY="$SCRIPT_DIR/infrastructure/outputs/core-key.pem"
PAYLOAD="$SCRIPT_DIR/example-apps/generate-load.sh"

if [[ ! -f "$CONFIG" ]]; then
  echo "Error: $CONFIG not found. Run ./run.sh first to provision infrastructure." >&2
  exit 1
fi

if [[ ! -f "$KEY" ]]; then
  echo "Error: $KEY not found. Run ./run.sh first to provision infrastructure." >&2
  exit 1
fi

if [[ ! -f "$PAYLOAD" ]]; then
  echo "Error: load payload $PAYLOAD not found." >&2
  exit 1
fi

HOST=$(jq -r '.core.public_ip' "$CONFIG")

if [[ -z "$HOST" || "$HOST" == "null" ]]; then
  echo "Error: Could not read public IP from $CONFIG." >&2
  exit 1
fi

# Forward all flags (e.g. -i 0.5 -c 4) to the remote payload, safely quoted.
REMOTE_ARGS=""
for arg in "$@"; do
  REMOTE_ARGS+=" $(printf '%q' "$arg")"
done

echo "Starting load generation on ec2-user@$HOST (Ctrl-C to stop)..."

# -t allocates a TTY so Ctrl-C propagates and terminates the remote loop.
# `bash -s` runs the piped payload; args after `--` become its positional args.
exec ssh -t -i "$KEY" -o StrictHostKeyChecking=no ec2-user@"$HOST" \
  "bash -s --${REMOTE_ARGS}" < "$PAYLOAD"
