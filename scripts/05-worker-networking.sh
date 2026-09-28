#!/usr/bin/env bash
set -euo pipefail

# 0. Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root (or with sudo)." >&2
  exit 1
fi

NODE_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I | awk '{print $1}')
NODE_NAME=$(hostname -s)

# 1. CNI network configuration
echo "==> 1. Configuring CNI network plugins..."
mkdir -p /etc/cni/net.d
cat > /etc/cni/net.d/10-bridge.conflist <<CONFIG
{
  "cniVersion": "0.4.0",
  "name": "bridge-net",
  "plugins": [
    {
      "type": "bridge",
      "bridge": "cbr0",
      "isGateway": true,
      "ipMasq": true,
      "ipam": {
        "type": "host-local",
        "subnet": "10.244.0.0/24",
        "routes": [
          { "dst": "0.0.0.0/0" }
        ]
      }
    },
    {
      "type": "portmap",
      "capabilities": {
        "portMappings": true
      }
    }
  ]
}
CONFIG

cat > /etc/cni/net.d/99-loopback.conf <<CONFIG
{
  "cniVersion": "0.4.0",
  "name": "lo",
  "type": "loopback"
}
CONFIG

# 2. Kubelet configuration and service
echo "==> 2. Configuring Kubelet service..."
mkdir -p /var/lib/kubelet
cat > /var/lib/kubelet/config.yaml <<CONFIG
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
clusterDomain: cluster.local
clusterDNS:
  - 10.96.0.10
cgroupDriver: systemd
containerRuntimeEndpoint: unix:///run/containerd/containerd.sock
failSwapOn: true
serializeImagePulls: false
CONFIG

cat > /etc/systemd/system/kubelet.service <<UNIT
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/config.yaml \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --hostname-override=${NODE_NAME} \\
  --node-ip=${NODE_IP} \\
  --register-node=true \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

# 3. Kube-proxy configuration and service
echo "==> 3. Configuring Kube-proxy service (iptables mode)..."
mkdir -p /var/lib/kube-proxy
cat > /var/lib/kube-proxy/config.yaml <<CONFIG
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
clientConnection:
  kubeconfig: "/etc/kubernetes/kube-proxy.kubeconfig"
mode: "iptables"
clusterCIDR: "10.244.0.0/16"
CONFIG

cat > /etc/systemd/system/kube-proxy.service <<UNIT
[Unit]
Description=Kubernetes Kube-Proxy
Documentation=https://github.com/kubernetes/kubernetes
After=network.target

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/config.yaml \\
  --hostname-override=${NODE_NAME} \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

# 4. Reload systemd daemon and activate worker components
echo "==> 4. Starting Kubelet and Kube-proxy..."
systemctl daemon-reload
systemctl enable --now kubelet kube-proxy

# 5. Node status check
echo "==> 5. Waiting for node to register and become Ready..."
NODE_READY=false
for i in {1..30}; do
  STATUS=$(kubectl --kubeconfig=/etc/kubernetes/admin.kubeconfig get nodes "${NODE_NAME}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [ "${STATUS}" = "True" ]; then
    echo "--> Node ${NODE_NAME} is Ready!"
    NODE_READY=true
    break
  fi
  echo "    Waiting for Ready status... (${i}/30)"
  sleep 2
done

if [ "$NODE_READY" != "true" ]; then
  echo "[-] Error: Node ${NODE_NAME} failed to reach Ready status within 60s." >&2
  kubectl --kubeconfig=/etc/kubernetes/admin.kubeconfig describe node "${NODE_NAME}" || true
  exit 1
fi

kubectl --kubeconfig=/etc/kubernetes/admin.kubeconfig get nodes -o wide
echo "--> Worker components initialized successfully."
