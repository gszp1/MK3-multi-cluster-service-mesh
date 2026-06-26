#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$ROOT_DIR/infrastructure"
CERTS_DIR="$ROOT_DIR/certs"

# Delete infrastructure
echo "[1] Destroying infrastructure with Terraform..."
terraform -chdir="$INFRA_DIR" destroy -auto-approve

# Remove files
echo "[2] Cleaning up Terraform state files, SSH keys and config..."
rm -f "$INFRA_DIR/terraform.tfstate"
rm -f "$INFRA_DIR/terraform.tfstate.*"
rm -f "$INFRA_DIR/terraform.tfstate.backup"
rm -f "$INFRA_DIR/outputs/config.json"

# Remove KWOK clusters info
echo "[3] Removing file with KWOK clusters information"
rm -f "$ROOT_DIR/kwok/kwok-clusters.json"

# Remove certs
echo "[4] Removing certs (generated root CA + per-cluster intermediate CAs)..."
rm -f "$INFRA_DIR/outputs/core-key.pem"
find "$CERTS_DIR" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
rm -f "$CERTS_DIR"/root-key.pem "$CERTS_DIR"/root-cert.pem \
      "$CERTS_DIR"/root-cert.srl "$CERTS_DIR"/*.csr


