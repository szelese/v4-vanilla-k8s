#!/usr/bin/env bash
set -euo pipefail

# 0. Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root (or with sudo)." >&2
  exit 1
fi

K8S_VERSION="v1.31.4"
ETCD_VERSION="v3.5.14"
CNI_VERSION="v1.5.0"
CRICTL_VERSION="v1.30.0"
ARCH="amd64"

# Create essential directories
echo "==> Creating required directories..."
mkdir -p /etc/kubernetes/pki \
         /etc/kubernetes/manifests \
         /var/lib/kubelet \
         /var/lib/etcd \
         /opt/cni/bin

# 1. Download official Kubernetes binaries
echo "==> Downloading Kubernetes binaries (${K8S_VERSION})..."
for BIN in kube-apiserver kube-controller-manager kube-scheduler kubelet kubectl kube-proxy; do
  echo "    -> ${BIN}"
  curl -fsSL --retry 3 "https://dl.k8s.io/release/${K8S_VERSION}/bin/linux/${ARCH}/${BIN}" -o "/usr/local/bin/${BIN}"
  chmod +x "/usr/local/bin/${BIN}"
done

# 2. Download and extract etcd
echo "==> Downloading etcd (${ETCD_VERSION})..."
curl -fsSL --retry 3 "https://github.com/etcd-io/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-${ARCH}.tar.gz" -o /tmp/etcd.tar.gz
tar -zxf /tmp/etcd.tar.gz -C /tmp/
install -m 755 "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcd" /usr/local/bin/etcd
install -m 755 "/tmp/etcd-${ETCD_VERSION}-linux-${ARCH}/etcdctl" /usr/local/bin/etcdctl
rm -rf /tmp/etcd*

# 3. Download and extract CNI plugins
echo "==> Downloading CNI plugins (${CNI_VERSION})..."
curl -fsSL --retry 3 "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-${ARCH}-${CNI_VERSION}.tgz" -o /tmp/cni.tgz
tar -zxf /tmp/cni.tgz -C /opt/cni/bin/
rm -f /tmp/cni.tgz

# 4. Download and install crictl (CRI CLI)
echo "==> Downloading crictl (${CRICTL_VERSION})..."
curl -fsSL --retry 3 "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${ARCH}.tar.gz" -o /tmp/crictl.tar.gz
tar -zxf /tmp/crictl.tar.gz -C /usr/local/bin/
rm -f /tmp/crictl.tar.gz

echo "--> Binaries downloaded and installed successfully."
