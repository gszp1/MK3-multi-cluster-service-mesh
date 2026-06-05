#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_FILE="$SCRIPT_DIR/../kubeconfig/kubeconfig.yaml"
export KUBECONFIG="$KUBECONFIG_FILE"

CLUSTERS=(kind-primary kind-remote-1 kind-remote-2)

cd "$SCRIPT_DIR"

# ── Root CA ────────────────────────────────────────────────────────────────────

echo "[1] Generating root CA..."

cat > root-ca.conf <<'EOF'
[ req ]
default_bits       = 4096
prompt             = no
encrypt_key        = no
default_md         = sha256
distinguished_name = dn
x509_extensions    = v3_ca

[ dn ]
O  = Istio
CN = Root CA

[ v3_ca ]
subjectKeyIdentifier   = hash
basicConstraints       = critical,CA:true,pathlen:1
keyUsage               = critical,digitalSignature,keyCertSign
authorityKeyIdentifier = keyid:always,issuer:always
EOF

openssl genrsa -out root-key.pem 4096 2>/dev/null
openssl req -new -x509 -days 3650 -key root-key.pem -out root-cert.pem -config root-ca.conf
echo "  root-cert.pem generated"

# ── Intermediate CA per cluster ────────────────────────────────────────────────

echo "[2] Generating intermediate CAs..."

for cluster in "${CLUSTERS[@]}"; do
  name="${cluster#kind-}"   # strip "kind-" prefix: primary, remote-1, remote-2
  mkdir -p "$name"

  cat > "$name/ca.conf" <<EOF
[ req ]
default_bits       = 4096
prompt             = no
encrypt_key        = no
default_md         = sha256
distinguished_name = dn

[ dn ]
O  = Istio
CN = Intermediate CA ($name)

[ v3_ca ]
subjectKeyIdentifier   = hash
basicConstraints       = critical,CA:true,pathlen:0
keyUsage               = critical,digitalSignature,keyCertSign
authorityKeyIdentifier = keyid:always,issuer:always
EOF

  openssl genrsa -out "$name/ca-key.pem" 4096 2>/dev/null
  openssl req -new -key "$name/ca-key.pem" -out "$name/ca-cert.csr" -config "$name/ca.conf"
  openssl x509 -req -days 730 \
    -in "$name/ca-cert.csr" \
    -CA root-cert.pem -CAkey root-key.pem -CAcreateserial \
    -out "$name/ca-cert.pem" \
    -extfile "$name/ca.conf" -extensions v3_ca 2>/dev/null

  cat "$name/ca-cert.pem" root-cert.pem > "$name/cert-chain.pem"
  cp root-cert.pem "$name/root-cert.pem"

  echo "  $name: done"
done

# ── Apply cacerts secrets ──────────────────────────────────────────────────────

echo "[3] Creating istio-system namespaces and cacerts secrets..."

for cluster in "${CLUSTERS[@]}"; do
  name="${cluster#kind-}"

  kubectl --context "$cluster" create namespace istio-system --dry-run=client -o yaml \
    | kubectl --context "$cluster" apply -f -

  kubectl --context "$cluster" -n istio-system delete secret cacerts --ignore-not-found
  kubectl --context "$cluster" -n istio-system create secret generic cacerts \
    --from-file="$name/ca-cert.pem" \
    --from-file="$name/ca-key.pem" \
    --from-file="$name/root-cert.pem" \
    --from-file="$name/cert-chain.pem"

  echo "  $cluster: cacerts secret applied"
done

echo ""
echo "Done. All clusters have cacerts configured with a shared root CA."
