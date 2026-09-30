#!/usr/bin/env bash
set -euo pipefail

# 0. Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root (or with sudo)." >&2
  exit 1
fi

# 0. 1. Define versions and architecture
HOST_ARCH=$(uname -m)
case "${HOST_ARCH}" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "[-] Unsupported architecture: ${HOST_ARCH}. Only amd64 and arm64 are supported." >&2
    exit 1
    ;;
esac

K8S_VERSION="v1.36.5"
ETCD_VERSION="v3.5.34"
CNI_VERSION="v1.9.1"
CRICTL_VERSION="v1.36.0"

# 0. 2. Function to verify SHA256 checksum of downloaded files
verify_sha256() {
  local file="$1"
  local expected_hash="$2"
  local actual_hash
  actual_hash=$(sha256sum "${file}" | awk '{print $1}')
  if [ "${actual_hash}" != "${expected_hash}" ]; then
    echo "[-] Checksum mismatch for ${file} (Expected: ${expected_hash}, Got: ${actual_hash})" >&2
    exit 1
  fi
}

# Create essential directories
echo "==> Creating required directories..."
mkdir -p /etc/kubernetes/pki \
         /etc/kubernetes/manifests \
         /var/lib/kubelet \
         /var/lib/etcd \
         /opt/cni/bin

# 1. Download official Kubernetes binaries
echo "==> Downloading Kubernetes binaries (${K8S_VERSION}, ${ARCH})..."
for BIN in kube-apiserver kube-controller-manager kube-scheduler kubelet kubectl kube-proxy; do
  echo "    -> ${BIN}"
  URL="https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/${BIN}"
  curl -fsSL --retry 3 "${URL}" -o "/usr/local/bin/${BIN}"
  EXPECTED_SHA=$(curl -fsSL "${URL}.sha256")
  verify_sha256 "/usr/local/bin/${BIN}" "${EXPECTED_SHA}"
  chmod +x "/usr/local/bin/${BIN}"
done

# 2. Download and extract etcd
echo "==> Downloading etcd (${ETCD_VERSION}, ${ARCH})..."
ETCD_PKG="etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"
curl -fsSL --retry 3 "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/${ETCD_PKG}" -o "/tmp/${ETCD_PKG}"
tar -zxf "/tmp/${ETCD_PKG}" -C /tmp/
install -m 755 "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcd" /usr/local/bin/etcd
install -m 755 "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl
rm -rf "/tmp/${ETCD_PKG}" "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}"

# 3. Download and extract CNI plugins
echo "==> Downloading CNI plugins (${CNI_VERSION}, ${ARCH})..."
CNI_PKG="cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz"
curl -fsSL --retry 3 "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/${CNI_PKG}" -o "/tmp/${CNI_PKG}"
tar -zxf "/tmp/${CNI_PKG}" -C /opt/cni/bin/
rm -f "/tmp/${CNI_PKG}"

# 4. Download and install crictl (CRI CLI)
echo "==> Downloading crictl (${CRICTL_VERSION}, ${ARCH})..."
CRICTL_PKG="crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz"
curl -fsSL --retry 3 "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/${CRICTL_PKG}" -o "/tmp/${CRICTL_PKG}"
tar -zxf "/tmp/${CRICTL_PKG}" -C /usr/local/bin/
rm -f "/tmp/${CRICTL_PKG}"

echo "--> Binaries downloaded and installed successfully."
