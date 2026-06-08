#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig/kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_FILE"

NAMESPACE="sample"
REQUESTS=20
PORT=15080

if [[ "${1:-}" == "--cleanup" ]]; then
  echo "Cleaning up..."
  for CTX in kind-primary kind-remote-1 kind-remote-2; do
    kubectl --context="$CTX" -n "$NAMESPACE" delete -f "$SCRIPT_DIR/helloworld-gateway.yaml" \
      --ignore-not-found 2>/dev/null || true
    kubectl --context="$CTX" delete namespace "$NAMESPACE" --ignore-not-found
  done
  echo "Done."
  exit 0
fi

echo "[1] Creating '$NAMESPACE' namespace with sidecar injection on all clusters..."
for CTX in kind-primary kind-remote-1 kind-remote-2; do
  kubectl --context="$CTX" create namespace "$NAMESPACE" --dry-run=client -o yaml \
    | kubectl --context="$CTX" apply -f -
  kubectl --context="$CTX" label namespace "$NAMESPACE" istio-injection=enabled --overwrite
done

echo "[1b] Creating istio-ca-root-cert configmap in '$NAMESPACE' on remote clusters..."
for CTX in kind-remote-1 kind-remote-2; do
  ROOT_CERT=$(kubectl --context="$CTX" -n istio-system \
    get secret cacerts -o jsonpath='{.data.root-cert\.pem}' | base64 -d)
  kubectl --context="$CTX" -n "$NAMESPACE" create configmap istio-ca-root-cert \
    --from-literal="root-cert.pem=${ROOT_CERT}" \
    --dry-run=client -o yaml | kubectl --context="$CTX" apply -f -
done

echo "[2] Deploying helloworld: v1 on primary, v2 on remote-1 and remote-2..."
"$SCRIPT_DIR/gen-helloworld.sh" --version v1 \
  | kubectl --context="kind-primary" -n "$NAMESPACE" apply -f -
"$SCRIPT_DIR/gen-helloworld.sh" --version v2 \
  | kubectl --context="kind-remote-1" -n "$NAMESPACE" apply -f -
"$SCRIPT_DIR/gen-helloworld.sh" --version v2 \
  | kubectl --context="kind-remote-2" -n "$NAMESPACE" apply -f -

echo "[3] Applying ingress gateway on primary..."
kubectl --context="kind-primary" -n "$NAMESPACE" apply -f "$SCRIPT_DIR/helloworld-gateway.yaml"

echo "[4] Waiting for helloworld pods to be ready..."
for CTX in kind-primary kind-remote-1 kind-remote-2; do
  echo "  -> $CTX"
  kubectl --context="$CTX" -n "$NAMESPACE" wait \
    --for=condition=ready pod -l app=helloworld --timeout=120s
done

echo ""
echo "[5] Pod status (should be 2/2 — app + sidecar):"
for CTX in kind-primary kind-remote-1 kind-remote-2; do
  echo "  === $CTX ==="
  kubectl --context="$CTX" -n "$NAMESPACE" get pods -o wide | sed 's/^/    /'
done

echo ""
echo "[6] Port-forwarding ingress gateway on localhost:$PORT..."
kubectl --context="kind-primary" -n istio-system port-forward \
  svc/istio-ingressgateway "$PORT:80" &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
until curl -s --max-time 1 "http://localhost:$PORT/hello" >/dev/null 2>&1; do sleep 1; done

export GATEWAY_URL="localhost:$PORT"
echo "    GATEWAY_URL=$GATEWAY_URL"

echo ""
echo "[7] Sending $REQUESTS requests to helloworld (cross-cluster routing test)..."
V1=0; V2=0; ERRORS=0

for i in $(seq 1 $REQUESTS); do
  RESPONSE=$(curl -s --max-time 5 "http://$GATEWAY_URL/hello" 2>/dev/null || echo "ERROR")
  echo "  [$i] $RESPONSE"

  case "$RESPONSE" in
    *"version: v1"*) V1=$((V1+1)) ;;
    *"version: v2"*) V2=$((V2+1)) ;;
    *)               ERRORS=$((ERRORS+1)) ;;
  esac
done

echo ""
echo "Results:"
echo "  v1 (primary):            $V1 / $REQUESTS"
echo "  v2 (remote-1, remote-2): $V2 / $REQUESTS"
echo "  errors:                  $ERRORS / $REQUESTS"

echo ""
if [[ $V1 -gt 0 && $V2 -gt 0 && $ERRORS -eq 0 ]]; then
  echo "PASS: cross-cluster load balancing works — both v1 and v2 responded."
elif [[ $V1 -gt 0 && $V2 -gt 0 ]]; then
  echo "PASS (with errors): cross-cluster routing works, but $ERRORS requests failed."
  exit 1
else
  echo "FAIL: expected responses from both v1 and v2, got v1=$V1 v2=$V2 errors=$ERRORS."
  exit 1
fi

echo ""
echo "To clean up: $0 --cleanup"
