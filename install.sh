#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Error: Installation script must be executed with root privileges (sudo)." >&2
  exit 1
fi

# Check the supported Ubuntu release before running any installation scripts.
if [[ ! -r /etc/os-release ]]; then
  echo "[-] Cannot identify the operating system." >&2
  exit 1
fi

. /etc/os-release

case "${ID:-}:${VERSION_ID:-}" in
  ubuntu:22.04|ubuntu:24.04|ubuntu:26.04) ;;
  *)
    echo "[-] Unsupported OS: ${PRETTY_NAME:-unknown}. Supported: Ubuntu 22.04, 24.04, 26.04." >&2
    exit 1
    ;;
esac

# Detect and normalize the supported architecture.
HOST_ARCH=$(uname -m)
case "${HOST_ARCH}" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "[-] Unsupported architecture: ${HOST_ARCH}. Supported: amd64 and arm64." >&2
    exit 1
    ;;
esac

export KUBECONFIG=/etc/kubernetes/admin.kubeconfig
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts

echo "================================================="
echo "   Starting V4 Vanilla Kubernetes Installation   "
echo "================================================="

INSTALL_START=$(date +%s)

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

INSTALL_END=$(date +%s)
ELAPSED_SECONDS=$((INSTALL_END - INSTALL_START))

printf -v ELAPSED_HUMAN '%02d:%02d:%02d' \
  "$((ELAPSED_SECONDS / 3600))" \
  "$(((ELAPSED_SECONDS % 3600) / 60))" \
  "$((ELAPSED_SECONDS % 60))"

echo
echo "OS: ${PRETTY_NAME:-unknown}"
echo "Architecture: ${ARCH} (${HOST_ARCH})"
echo "Total installer runtime: ${ELAPSED_HUMAN}"
echo "Smoke tests: passed"
