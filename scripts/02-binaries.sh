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
  if [[ ! "${expected_hash}" =~ ^[[:xdigit:]]{64}$ ]]; then
    echo "[-] Missing or invalid SHA-256 checksum for ${file}" >&2
    exit 1
  fi

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
chmod 700 /var/lib/etcd

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

# 2. Download, verify and extract etcd
echo "==> Downloading etcd (${ETCD_VERSION}, ${ARCH})..."
ETCD_PKG="etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz"
ETCD_URL="https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}"
ETCD_SUMS="/tmp/etcd-${ETCD_VERSION}-SHA256SUMS"

curl -fsSL --retry 3 "${ETCD_URL}/${ETCD_PKG}" -o "/tmp/${ETCD_PKG}"
curl -fsSL --retry 3 "${ETCD_URL}/SHA256SUMS" -o "${ETCD_SUMS}"

ETCD_EXPECTED_SHA=$(awk -v file="${ETCD_PKG}" '
  {
    name = $NF
    sub(/^\*/, "", name)
    n = split(name, parts, "/")
    if (parts[n] == file) {
      print $1
      exit
    }
  }
' "${ETCD_SUMS}")

verify_sha256 "/tmp/${ETCD_PKG}" "${ETCD_EXPECTED_SHA}"
rm -f "${ETCD_SUMS}"

tar -zxf "/tmp/${ETCD_PKG}" -C /tmp/
install -m 755 "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcd" /usr/local/bin/etcd
install -m 755 "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl
rm -rf "/tmp/${ETCD_PKG}" "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}"

# 3. Download and extract CNI plugins
CNI_PKG="cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz"
CNI_URL="https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/${CNI_PKG}"
CNI_SHA_FILE="/tmp/${CNI_PKG}.sha256"

curl -fsSL --retry 3 "${CNI_URL}" -o "/tmp/${CNI_PKG}"
curl -fsSL --retry 3 "${CNI_URL}.sha256" -o "${CNI_SHA_FILE}"

CNI_EXPECTED_SHA=$(awk 'length($1) == 64 && $1 ~ /^[[:xdigit:]]+$/ { print $1; exit }' "${CNI_SHA_FILE}")
verify_sha256 "/tmp/${CNI_PKG}" "${CNI_EXPECTED_SHA}"
rm -f "${CNI_SHA_FILE}"

tar -zxf "/tmp/${CNI_PKG}" -C /opt/cni/bin/
rm -f "/tmp/${CNI_PKG}"

# 4. Download and install crictl (CRI CLI)
CRICTL_PKG="crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz"
CRICTL_URL="https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/${CRICTL_PKG}"
CRICTL_SHA_FILE="/tmp/${CRICTL_PKG}.sha256"

curl -fsSL --retry 3 "${CRICTL_URL}" -o "/tmp/${CRICTL_PKG}"
curl -fsSL --retry 3 "${CRICTL_URL}.sha256" -o "${CRICTL_SHA_FILE}"

CRICTL_EXPECTED_SHA=$(awk 'length($1) == 64 && $1 ~ /^[[:xdigit:]]+$/ { print $1; exit }' "${CRICTL_SHA_FILE}")
verify_sha256 "/tmp/${CRICTL_PKG}" "${CRICTL_EXPECTED_SHA}"
rm -f "${CRICTL_SHA_FILE}"

tar -zxf "/tmp/${CRICTL_PKG}" -C /usr/local/bin/
rm -f "/tmp/${CRICTL_PKG}"

echo "--> Binaries downloaded and installed successfully."
