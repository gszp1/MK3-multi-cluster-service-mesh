#!/bin/bash
#
# Load-generation payload that runs ON the EC2 instance. It discovers the
# remote-1 kind node IP via docker and continuously hits the sender service so
# that cross-cluster traffic stays visible in the Kiali traffic graph (edges
# only appear while traffic flows).
#
# You normally don't call this directly: the repo-root ./generate-load.sh
# wrapper pipes it over SSH. If you are already on the instance (./connect-vm.sh)
# you can also run it here.
#
# Options: -i interval  -m message  -c concurrency  -H host  (see usage below)
# Stop with Ctrl-C.

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: generate-load.sh [-i interval] [-m message] [-c concurrency] [-H host]
  -i  seconds to wait between requests per worker   (default: 1)
  -m  message content sent to the sender            (default: hello-kiali)
  -c  number of parallel request loops              (default: 1)
  -H  override the remote-1 node host/IP            (default: auto-detected)
EOF
}

INTERVAL=1
MESSAGE="hello-kiali"
CONCURRENCY=1
HOST=""
NODE_PORT=30080
NODE_CONTAINER="remote-1-control-plane"

while getopts ":i:m:c:H:h" opt; do
  case "$opt" in
    i) INTERVAL="$OPTARG" ;;
    m) MESSAGE="$OPTARG" ;;
    c) CONCURRENCY="$OPTARG" ;;
    H) HOST="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "Unknown option: -$OPTARG" >&2; usage >&2; exit 1 ;;
    :)  echo "Option -$OPTARG requires an argument" >&2; exit 1 ;;
  esac
done

if [[ -z "$HOST" ]]; then
  if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker not found. Run this on the EC2 instance, or pass -H <remote-1-node-ip>." >&2
    exit 1
  fi
  HOST="$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$NODE_CONTAINER" 2>/dev/null || true)"
  if [[ -z "$HOST" ]]; then
    echo "Error: could not determine IP of '$NODE_CONTAINER'. Is the cluster running? You can pass -H <ip> manually." >&2
    exit 1
  fi
fi

URL="http://${HOST}:${NODE_PORT}/api?content=${MESSAGE}"

echo "Generating load against: $URL"
echo "  interval=${INTERVAL}s  concurrency=${CONCURRENCY}"
echo "Press Ctrl-C to stop."

# Make sure Ctrl-C kills the background worker loops too.
trap 'echo; echo "Stopping load generation..."; kill 0' INT TERM

worker() {
  local id="$1"
  while true; do
    response="$(curl -s -o /dev/null -w '%{http_code}' "$URL" || echo "ERR")"
    printf 'worker %s -> %s\n' "$id" "$response"
    sleep "$INTERVAL"
  done
}

for ((w = 1; w <= CONCURRENCY; w++)); do
  worker "$w" &
done

wait
