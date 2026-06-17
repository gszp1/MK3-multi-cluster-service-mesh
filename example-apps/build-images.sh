#!/bin/bash

set -euo pipefail

APPS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TAG="${1:-latest}"

for app in responder sender; do
  echo "[*] Building ${app} image (${app}:${TAG})..."
  docker build -t "${app}:${TAG}" "${APPS_DIR}/${app}"
  echo "[+] Done: ${app}:${TAG}"
done