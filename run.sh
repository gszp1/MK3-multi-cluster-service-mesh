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

# Create kubeconfig for connecting to clusters
echo "[5] Setting up kubeconfig for cluster access..."
./connect-clusters.sh

# Install MetalLB in all clusters
echo "[6] Installing MetalLB in all clusters..."
./metallb/install.sh

# Generate CA and client certificates for cluster authentication
echo "[7] Generating CA and client certificates for cluster authentication..."
./certs/generate.sh

# Configure Istio on primary cluster
echo "[8] Configuring Istio on primary cluster..."
./istio/istio-config-primary.sh

# Configure Istio on remote clusters
echo "[9] Configuring Istio on remote clusters..."
./istio/istio-config-remotes.sh