#!/bin/bash

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/infrastructure" && pwd)"

# Delete infrastructure
echo "[1] Destroying infrastructure with Terraform..."
terraform -chdir="$INFRA_DIR" destroy -auto-approve

# Remove files
echo "[2] Cleaning up Terraform state files, SSH keys and config..."
rm -f "$INFRA_DIR/terraform.tfstate"
rm -f "$INFRA_DIR/terraform.tfstate.*"
rm -f "$INFRA_DIR/outputs/core-key.pem"
rm -f "$INFRA_DIR/outputs/config.json"

