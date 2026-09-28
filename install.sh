#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Error: Installation script must be executed with root privileges (sudo)." >&2
  exit 1
fi

export KUBECONFIG=/etc/kubernetes/admin.kubeconfig
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts

echo "================================================="
echo "   Starting V4 Vanilla Kubernetes Installation   "
echo "================================================="

"${SCRIPT_DIR}/01-host-prep.sh"
"${SCRIPT_DIR}/02-binaries.sh"
"${SCRIPT_DIR}/03-pki.sh"
"${SCRIPT_DIR}/04-control-plane.sh"
"${SCRIPT_DIR}/05-worker-networking.sh"
"${SCRIPT_DIR}/06-addons-rbac.sh"
"${SCRIPT_DIR}/07-smoke-test.sh"

echo "================================================="
echo "   Installation completed. Cluster status:       "
echo "================================================="
kubectl get nodes -o wide
kubectl get pods -A
