#!/bin/bash

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/infrastructure" && pwd)"

# Initialize Terraform
echo "[1] Initializing Terraform..."
terraform -chdir="$INFRA_DIR" init

# Validate Terraform configuration
echo "[2] Validating Terraform configuration..."
terraform -chdir="$INFRA_DIR" validate

# Apply Terraform configuration
echo "[3] Applying Terraform configuration..."
terraform -chdir="$INFRA_DIR" apply -auto-approve

# Show the Terraform state
echo "[4] Showing Terraform state..."
terraform -chdir="$INFRA_DIR" show

