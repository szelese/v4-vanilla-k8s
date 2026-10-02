#!/usr/bin/env bash
set -euo pipefail

# 0. Ensure script is run as root && check for existing Kubernetes installation
if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root (or with sudo)." >&2
  exit 1
fi

K8S_STATE_PATHS=(
  /etc/kubernetes/pki
  /etc/systemd/system/etcd.service
  /etc/systemd/system/kube-apiserver.service
  /etc/systemd/system/kubelet.service
  /etc/systemd/system/kube-proxy.service
  /var/lib/etcd/member
)

for path in "${K8S_STATE_PATHS[@]}"; do
  if [[ -e "${path}" ]]; then
    echo "Error: Existing or partial Kubernetes installation detected at ${path}." >&2
    echo "Run this installer only on a clean Ubuntu host." >&2
    exit 1
  fi
done

# 1. Disable swap memory
echo "==> 1. Disabling swap..."
swapoff -a
sed -i.bak -r '/\bswap\b/ s/^([^#].*)$/# \1/' /etc/fstab

# 2. Load necessary kernel modules for container runtime and CNI
echo "==> 2. Loading kernel modules..."
tee /etc/modules-load.d/k8s.conf <<MODULES
overlay
br_netfilter
MODULES

modprobe overlay
modprobe br_netfilter

# 3. Apply sysctl networking parameters
echo "==> 3. Applying sysctl networking parameters..."
tee /etc/sysctl.d/k8s.conf <<SYSCTL
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
SYSCTL

sysctl --system > /dev/null

# 4. Install containerd runtime and required network utilities
echo "==> 4. Installing runtime and networking utilities..."
apt-get update -y
apt-get install -y \
  containerd \
  socat \
  conntrack \
  ipset \
  curl \
  openssl \
  ca-certificates \
  iptables

# 5. Configure containerd with systemd cgroup driver

CONTAINERD_VERSION_OUTPUT=$(containerd --version)
echo "Detected runtime: ${CONTAINERD_VERSION_OUTPUT}"

if [[ "${CONTAINERD_VERSION_OUTPUT}" =~ ([0-9]+)\.[0-9]+\.[0-9]+ ]]; then
  CONTAINERD_MAJOR="${BASH_REMATCH[1]}"
else
  echo "[-] Could not parse containerd version: ${CONTAINERD_VERSION_OUTPUT}" >&2
  exit 1
fi

if (( CONTAINERD_MAJOR < 2 )); then
  echo "[-] This installer requires containerd 2.x or newer; found: ${CONTAINERD_VERSION_OUTPUT}" >&2
  exit 1
fi

echo "==> 5. Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  echo "[-] Error: Failed to configure SystemdCgroup in /etc/containerd/config.toml" >&2
  exit 1
fi

systemctl restart containerd
systemctl enable containerd

# 6. Configure crictl CLI endpoint
echo "==> 6. Configuring crictl endpoint..."
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

echo "--> Host preparation completed successfully."
