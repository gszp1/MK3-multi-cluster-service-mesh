#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG="${SCRIPT_DIR}/kubeconfig/kubeconfig.yaml"

echo "KUBECONFIG set to $KUBECONFIG"
echo "Available contexts:"
kubectl config get-contexts -o name

exec "${SHELL:-/bin/bash}"
