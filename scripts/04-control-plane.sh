#!/usr/bin/env bash
set -euo pipefail

# 0. Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root (or with sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/node-network.sh"

NODE_IP=$(detect_node_ip)
NODE_NAME=$(hostname -s)

# 1. etcd service
echo "==> 1. Configuring etcd systemd service..."
cat > /etc/systemd/system/etcd.service <<UNIT
[Unit]
Description=etcd key-value store
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name=${NODE_NAME} \\
  --data-dir=/var/lib/etcd \\
  --listen-client-urls=https://127.0.0.1:2379 \
  --advertise-client-urls=https://127.0.0.1:2379 \
  --listen-peer-urls=https://127.0.0.1:2380 \
  --initial-advertise-peer-urls=https://127.0.0.1:2380 \
  --initial-cluster=${NODE_NAME}=https://127.0.0.1:2380 \
  --initial-cluster-token=etcd-cluster-token \\
  --initial-cluster-state=new \\
  --cert-file=/etc/kubernetes/pki/etcd.crt \\
  --key-file=/etc/kubernetes/pki/etcd.key \\
  --trusted-ca-file=/etc/kubernetes/pki/etcd-ca.crt \\
  --client-cert-auth=true \\
  --peer-cert-file=/etc/kubernetes/pki/etcd.crt \\
  --peer-key-file=/etc/kubernetes/pki/etcd.key \\
  --peer-trusted-ca-file=/etc/kubernetes/pki/etcd-ca.crt \\
  --peer-client-cert-auth=true
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

# 2. kube-apiserver service
echo "==> 2. Configuring kube-apiserver systemd service..."
cat > /etc/systemd/system/kube-apiserver.service <<UNIT
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=network.target etcd.service

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${NODE_IP} \\
  --allow-privileged=false \\
  --authorization-mode=Node,RBAC \\
  --anonymous-auth=false \\
  --client-ca-file=/etc/kubernetes/pki/ca.crt \\
  --enable-admission-plugins=NodeRestriction,ServiceAccount \\
  --enable-bootstrap-token-auth=false \\
  --etcd-cafile=/etc/kubernetes/pki/etcd-ca.crt \\
  --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt \\
  --etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key \\
  --etcd-servers=https://127.0.0.1:2379 \\
  --bind-address=0.0.0.0 \\
  --secure-port=6443 \\
  --service-account-issuer=https://kubernetes.default.svc.cluster.local \\
  --service-account-key-file=/etc/kubernetes/pki/sa.pub \\
  --service-account-signing-key-file=/etc/kubernetes/pki/sa.key \\
  --service-cluster-ip-range=10.96.0.0/12 \\
  --tls-cert-file=/etc/kubernetes/pki/apiserver.crt \\
  --tls-private-key-file=/etc/kubernetes/pki/apiserver.key \\
  --kubelet-certificate-authority=/etc/kubernetes/pki/ca.crt \\
  --kubelet-client-certificate=/etc/kubernetes/pki/apiserver.crt \\
  --kubelet-client-key=/etc/kubernetes/pki/apiserver.key \\
  --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname \\
  --requestheader-client-ca-file=/etc/kubernetes/pki/front-proxy-ca.crt \\
  --proxy-client-cert-file=/etc/kubernetes/pki/front-proxy-client.crt \\
  --proxy-client-key-file=/etc/kubernetes/pki/front-proxy-client.key \\
  --requestheader-allowed-names=front-proxy-client \\
  --requestheader-extra-headers-prefix=X-Remote-Extra- \\
  --requestheader-group-headers=X-Remote-Group \\
  --requestheader-username-headers=X-Remote-User \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
UNIT

# 3. kube-controller-manager service
echo "==> 3. Configuring kube-controller-manager systemd service..."
cat > /etc/systemd/system/kube-controller-manager.service <<UNIT
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=network.target kube-apiserver.service

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=127.0.0.1 \\
  --cluster-cidr=10.244.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/etc/kubernetes/pki/ca.crt \\
  --cluster-signing-key-file=/etc/kubernetes/pki/ca.key \\
  --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \\
  --authentication-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \\
  --authorization-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/etc/kubernetes/pki/ca.crt \\
  --service-account-private-key-file=/etc/kubernetes/pki/sa.key \\
  --service-cluster-ip-range=10.96.0.0/12 \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# 4. kube-scheduler service
echo "==> 4. Configuring kube-scheduler systemd service..."
cat > /etc/systemd/system/kube-scheduler.service <<UNIT
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=network.target kube-apiserver.service

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \\
  --authentication-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \\
  --authorization-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \\
  --bind-address=127.0.0.1 \\
  --leader-elect=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

# 5. Reload systemd daemon and activate control plane
echo "==> 5. Starting services..."
systemctl daemon-reload
systemctl enable --now etcd kube-apiserver kube-controller-manager kube-scheduler

# 6. Apply RBAC permissions for kube-apiserver to kubelet
echo "==> 6. Waiting for API Server to become responsive..."
TIMEOUT=60
ELAPSED=0
until kubectl --kubeconfig=/etc/kubernetes/admin.kubeconfig get --raw='/readyz' >/dev/null 2>&1; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "[-] Error: Timed out waiting for kube-apiserver to report ready." >&2
    exit 1
  fi
  sleep 2
  ELAPSED=$((ELAPSED + 2))
done

echo "==> Applying kube-apiserver to kubelet RBAC rule..."
kubectl --kubeconfig=/etc/kubernetes/admin.kubeconfig apply -f - <<RBAC
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver-to-kubelet
subjects:
  - kind: User
    name: kube-apiserver
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: system:kubelet-api-admin
  apiGroup: rbac.authorization.k8s.io
RBAC

echo "--> Control plane services started and RBAC applied successfully."
