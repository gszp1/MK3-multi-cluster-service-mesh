#!/bin/bash

# Usage:
#   ./kwok/add-cluster.sh [NAME] [NETWORK] [APISERVER_PORT]
#
# Defaults: NAME=remote-kwok NETWORK=network4 APISERVER_PORT=6444

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NAME="${1:-remote-kwok}"
NETWORK="${2:-network4}"
APISERVER_PORT="${3:-6444}"

CTX="kwok-$NAME"
APISERVER_CONTAINER="kwok-$NAME-kube-apiserver"
KIND_NETWORK="kind"

CONFIG="$REPO_DIR/infrastructure/outputs/config.json"
KEY="$REPO_DIR/infrastructure/outputs/core-key.pem"
CERTS_DIR="$REPO_DIR/certs"
KUBECONFIG_DIR="$REPO_DIR/kubeconfig"
MERGED_KUBECONFIG="$KUBECONFIG_DIR/kubeconfig.yaml"
TMPL_DIR="$REPO_DIR/istio/remote-manifests"

export KUBECONFIG="$MERGED_KUBECONFIG"


if [[ ! -f "$CONFIG" ]]; then
  echo "Error: $CONFIG not found. Run ./run.sh first."
  exit 1
fi
if [[ ! -f "$CERTS_DIR/root-cert.pem" || ! -f "$CERTS_DIR/root-key.pem" ]]; then
  echo "Error: shared root CA not found in $CERTS_DIR. Run ./certs/generate.sh first."
  exit 1
fi

HOST=$(jq -r '.core.public_ip' "$CONFIG")
if [[ -z "$HOST" || "$HOST" == "null" ]]; then
  echo "Error: Could not read public IP from $CONFIG."
  exit 1
fi

SSH_OPTS="-i $KEY -o StrictHostKeyChecking=no -o BatchMode=yes"
ssh_core() { ssh $SSH_OPTS ec2-user@"$HOST" "$@"; }


echo "[1] Creating kwok cluster '$NAME' on $HOST (docker runtime)..."
ssh_core "kwokctl get clusters | grep -qx '$NAME' || \
  kwokctl create cluster --name '$NAME' --runtime docker --kube-apiserver-port $APISERVER_PORT"

echo "[2] Adding a schedulable fake node..."

ssh_core "kwokctl --name '$NAME' kubectl apply -f -" <<'EOF'
apiVersion: v1
kind: Node
metadata:
  name: kwok-node-0
  annotations:
    kwok.x-k8s.io/node: fake
    node.alpha.kubernetes.io/ttl: "0"
  labels:
    type: kwok
    kubernetes.io/hostname: kwok-node-0
    kubernetes.io/os: linux
    kubernetes.io/arch: amd64
status:
  allocatable: { cpu: "32", memory: 256Gi, pods: "256" }
  capacity:    { cpu: "32", memory: 256Gi, pods: "256" }
  nodeInfo: { kubeletVersion: fake }
  phase: Running
EOF

echo "[3] Connecting kwok apiserver to the '$KIND_NETWORK' docker network..."
ssh_core "docker network connect '$KIND_NETWORK' '$APISERVER_CONTAINER' 2>/dev/null || true"

echo "[4] Fetching kubeconfig and opening SSH tunnel on :$APISERVER_PORT..."
mkdir -p "$KUBECONFIG_DIR"
TMP_KCFG="$KUBECONFIG_DIR/kubeconfig-$NAME.yaml"
ssh_core "kwokctl get kubeconfig --name '$NAME'" > "$TMP_KCFG"
sed -i "s|server: https://127.0.0.1:[0-9]*|server: https://127.0.0.1:$APISERVER_PORT|g" "$TMP_KCFG"

fuser -k "${APISERVER_PORT}/tcp" 2>/dev/null || true
ssh $SSH_OPTS -L "$APISERVER_PORT:localhost:$APISERVER_PORT" -N -f ec2-user@"$HOST"

echo "    Merging into $MERGED_KUBECONFIG..."
KUBECONFIG="$MERGED_KUBECONFIG:$TMP_KCFG" kubectl config view --flatten > "$MERGED_KUBECONFIG.new"
mv "$MERGED_KUBECONFIG.new" "$MERGED_KUBECONFIG"
chmod 600 "$MERGED_KUBECONFIG"
rm -f "$TMP_KCFG"

echo "[5] Generating intermediate CA from the shared root and creating cacerts..."
cd "$CERTS_DIR"
mkdir -p "$NAME"
cat > "$NAME/ca.conf" <<EOF
[ req ]
default_bits       = 4096
prompt             = no
encrypt_key        = no
default_md         = sha256
distinguished_name = dn

[ dn ]
O  = Istio
CN = Intermediate CA ($NAME)

[ v3_ca ]
subjectKeyIdentifier   = hash
basicConstraints       = critical,CA:true,pathlen:0
keyUsage               = critical,digitalSignature,keyCertSign
authorityKeyIdentifier = keyid:always,issuer:always
EOF

openssl genrsa -out "$NAME/ca-key.pem" 4096 2>/dev/null
openssl req -new -key "$NAME/ca-key.pem" -out "$NAME/ca-cert.csr" -config "$NAME/ca.conf"
openssl x509 -req -days 730 \
  -in "$NAME/ca-cert.csr" \
  -CA root-cert.pem -CAkey root-key.pem -CAcreateserial \
  -out "$NAME/ca-cert.pem" \
  -extfile "$NAME/ca.conf" -extensions v3_ca 2>/dev/null
cat "$NAME/ca-cert.pem" root-cert.pem > "$NAME/cert-chain.pem"
cp root-cert.pem "$NAME/root-cert.pem"

kubectl --context "$CTX" create namespace istio-system --dry-run=client -o yaml \
  | kubectl --context "$CTX" apply -f -
kubectl --context "$CTX" -n istio-system delete secret cacerts --ignore-not-found
kubectl --context "$CTX" -n istio-system create secret generic cacerts \
  --from-file="$NAME/ca-cert.pem" \
  --from-file="$NAME/ca-key.pem" \
  --from-file="$NAME/root-cert.pem" \
  --from-file="$NAME/cert-chain.pem"

echo "[6] Fetching east-west gateway address from primary..."
ISTIOD_REMOTE_ADDRESS=$(kubectl --context="kind-primary" -n istio-system \
  get svc istio-eastwestgateway -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
if [[ -z "$ISTIOD_REMOTE_ADDRESS" ]]; then
  echo "Error: Could not get east-west gateway IP from primary. Run istio/istio-config-primary.sh first."
  exit 1
fi
echo "    istiod address: $ISTIOD_REMOTE_ADDRESS"

echo "  [6a] Labeling istio-system namespace with network=$NETWORK..."
kubectl --context="$CTX" label namespace istio-system \
  topology.istio.io/network="$NETWORK" --overwrite

echo "  [6b] Installing Istio data plane (remote profile)..."
CLUSTER_NAME="$NAME" NETWORK="$NETWORK" ISTIOD_REMOTE_ADDRESS="$ISTIOD_REMOTE_ADDRESS" \
  envsubst < "$TMPL_DIR/remote-operator.yml.tmpl" \
  | istioctl install --context="$CTX" -y -f -

echo "  [6c] Pointing istiod endpoints at the primary east-west gateway..."
ISTIOD_REMOTE_ADDRESS="$ISTIOD_REMOTE_ADDRESS" \
  envsubst < "$TMPL_DIR/istiod-endpoints.yml.tmpl" \
  | kubectl --context="$CTX" -n istio-system apply -f -

echo "  [6d] Patching sidecar-injector webhook (caBundle + failurePolicy)..."

CACERT=$(kubectl --context="$CTX" -n istio-system \
  get secret cacerts -o jsonpath='{.data.root-cert\.pem}')
for MWC in istio-sidecar-injector istio-revision-tag-default; do
  kubectl --context="$CTX" get mutatingwebhookconfiguration "$MWC" -o json \
    | jq --arg ca "$CACERT" '.webhooks[] |= (.clientConfig.caBundle = $ca | .failurePolicy = "Ignore")' \
    | kubectl --context="$CTX" replace -f -
done

echo "  [6e] Creating remote secret on primary..."
REMOTE_API_SERVER="https://${APISERVER_CONTAINER}:6443"
istioctl create-remote-secret \
  --context="$CTX" \
  --name="$NAME" \
  --server="$REMOTE_API_SERVER" \
  | sed -E 's/( *)certificate-authority-data:.*/\1insecure-skip-tls-verify: true/' \
  | kubectl --context="kind-primary" apply -f -

echo "  [6f] Creating istio-ca-root-cert configmap on the kwok cluster..."
ROOT_CERT=$(kubectl --context="$CTX" -n istio-system \
  get secret cacerts -o jsonpath='{.data.root-cert\.pem}' | base64 -d)
kubectl --context="$CTX" -n istio-system create configmap istio-ca-root-cert \
  --from-literal="root-cert.pem=${ROOT_CERT}" \
  --dry-run=client -o yaml | kubectl --context="$CTX" apply -f -

echo "  [6g] Installing east-west gateway..."
NETWORK="$NETWORK" envsubst < "$TMPL_DIR/eastwest-operator.yml.tmpl" \
  | istioctl install --context="$CTX" -y -f -

echo "  [6h] Waiting for east-west gateway to be ready..."
kubectl --context="$CTX" -n istio-system \
  rollout status deployment/istio-eastwestgateway --timeout=120s

echo "  [6i] Exposing services through east-west gateway..."
kubectl --context="$CTX" apply -f "$TMPL_DIR/expose-services.yml"

echo ""
echo "Done. kwok cluster '$NAME' joined the mesh (context: $CTX, network: $NETWORK)."
echo "Verify from the primary:"
echo "  kubectl --context kind-primary get secret -n istio-system -l istio/multiCluster=true"
echo "  istioctl --context kind-primary remote-clusters"