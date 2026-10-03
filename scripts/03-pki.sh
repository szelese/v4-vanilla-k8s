#!/usr/bin/env bash
set -euo pipefail

# 0. Ensure root
if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root (or with sudo)." >&2
  exit 1
fi

# Restrict newly created PKI files and kubeconfigs to the owner.
umask 077

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/node-network.sh"

NODE_IP=$(detect_node_ip)
NODE_NAME=$(hostname -s)

PKI_DIR="/etc/kubernetes/pki"
mkdir -p "${PKI_DIR}"
chmod 700 "${PKI_DIR}"
cd "${PKI_DIR}"

echo "==> Configuring PKI for Node: ${NODE_NAME} (IP: ${NODE_IP})"

# 1. Generate internal Certificate Authority (CA) and Service Account key pair (idempotent)
if [ ! -f ca.key ] || [ ! -f ca.crt ]; then
  echo "==> 1. Generating internal CA..."
  openssl genrsa -out ca.key 2048
  openssl req -x509 -new -nodes -key ca.key -subj "/CN=kubernetes-ca" -days 3650 -out ca.crt
else
  echo "==> 1. Internal CA already exists, skipping creation."
fi

if [ ! -f sa.key ] || [ ! -f sa.pub ]; then
  echo "==> Generating Service Account key pair..."
  openssl genrsa -out sa.key 2048
  openssl rsa -in sa.key -pubout -out sa.pub
else
  echo "==> Service Account key pair already exists, skipping creation."
fi

# Generate a dedicated etcd CA
if [ ! -f etcd-ca.key ] || [ ! -f etcd-ca.crt ]; then
  echo "==> Generating dedicated etcd CA..."
  openssl genrsa -out etcd-ca.key 2048
  openssl req -x509 -new -nodes \
    -key etcd-ca.key \
    -subj "/CN=etcd-ca" \
    -days 3650 \
    -out etcd-ca.crt
fi

# 2. Generate Front-Proxy CA and Client (idempotent)
if [ ! -f front-proxy-ca.key ] || [ ! -f front-proxy-ca.crt ]; then
  echo "==> 2. Generating Front-Proxy CA..."
  openssl genrsa -out front-proxy-ca.key 2048
  openssl req -x509 -new -nodes -key front-proxy-ca.key -subj "/CN=front-proxy-ca" -days 3650 -out front-proxy-ca.crt
else
  echo "==> 2. Front-Proxy CA already exists, skipping creation."
fi

openssl genrsa -out front-proxy-client.key 2048
openssl req -new -key front-proxy-client.key -subj "/CN=front-proxy-client" -out front-proxy-client.csr
openssl x509 -req -in front-proxy-client.csr -CA front-proxy-ca.crt -CAkey front-proxy-ca.key -CAcreateserial -out front-proxy-client.crt -days 3650

# 3. Generate etcd server certificate with SANs
echo "==> 3. Generating etcd server certificate..."
cat > etcd.cnf <<CONFIG
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = etcd-server
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
[alt_names]
IP.1 = 127.0.0.1
IP.2 = ${NODE_IP}
DNS.1 = localhost
DNS.2 = ${NODE_NAME}
CONFIG

openssl genrsa -out etcd.key 2048
openssl req -new -key etcd.key -out etcd.csr -config etcd.cnf
openssl x509 -req -in etcd.csr -CA etcd-ca.crt -CAkey etcd-ca.key -CAcreateserial -out etcd.crt -days 3650 -extensions v3_req -extfile etcd.cnf

# Generate the API server's etcd client certificate
cat > apiserver-etcd-client.cnf <<CONFIG
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = kube-apiserver-etcd-client

[v3_client]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth
CONFIG

openssl genrsa -out apiserver-etcd-client.key 2048
openssl req -new \
  -key apiserver-etcd-client.key \
  -out apiserver-etcd-client.csr \
  -config apiserver-etcd-client.cnf
openssl x509 -req \
  -in apiserver-etcd-client.csr \
  -CA etcd-ca.crt \
  -CAkey etcd-ca.key \
  -CAcreateserial \
  -out apiserver-etcd-client.crt \
  -days 3650 \
  -extensions v3_client \
  -extfile apiserver-etcd-client.cnf

# 4. Generate kube-apiserver certificate with internal routing SANs
echo "==> 4. Generating kube-apiserver server certificate..."
cat > apiserver.cnf <<CONFIG
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = kube-apiserver
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names
[alt_names]
IP.1 = 127.0.0.1
IP.2 = ${NODE_IP}
IP.3 = 10.96.0.1
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
DNS.5 = localhost
DNS.6 = ${NODE_NAME}
CONFIG

openssl genrsa -out apiserver.key 2048
openssl req -new -key apiserver.key -out apiserver.csr -config apiserver.cnf
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out apiserver.crt -days 3650 -extensions v3_req -extfile apiserver.cnf

# 5. Generate component client certificates
echo "==> 5. Generating component client certificates..."
for COMP in admin kube-controller-manager kube-scheduler kube-proxy; do
  SUBJ="/CN=${COMP}"
  [ "${COMP}" = "admin" ] && SUBJ="/CN=admin/O=system:masters"
  [ "${COMP}" = "kube-controller-manager" ] && SUBJ="/CN=system:kube-controller-manager"
  [ "${COMP}" = "kube-scheduler" ] && SUBJ="/CN=system:kube-scheduler"
  [ "${COMP}" = "kube-proxy" ] && SUBJ="/CN=system:kube-proxy"

  openssl genrsa -out "${COMP}.key" 2048
  openssl req -new -key "${COMP}.key" -subj "${SUBJ}" -out "${COMP}.csr"
  openssl x509 -req -in "${COMP}.csr" -CA ca.crt -CAkey ca.key -CAcreateserial -out "${COMP}.crt" -days 3650
done

# Generate kubelet client certificate with node authorization subject
openssl genrsa -out kubelet.key 2048
openssl req -new -key kubelet.key -subj "/CN=system:node:${NODE_NAME}/O=system:nodes" -out kubelet.csr
openssl x509 -req -in kubelet.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kubelet.crt -days 3650

# Generate kubelet SERVER certificate with SANs (for apiserver-to-kubelet mTLS)
echo "==> Generating kubelet server certificate..."
cat > kubelet-server.cnf <<CONFIG
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
prompt = no
[req_distinguished_name]
CN = ${NODE_NAME}
[v3_req]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names
[alt_names]
IP.1 = 127.0.0.1
IP.2 = ${NODE_IP}
DNS.1 = localhost
DNS.2 = ${NODE_NAME}
CONFIG

openssl genrsa -out kubelet-server.key 2048
openssl req -new -key kubelet-server.key -out kubelet-server.csr -config kubelet-server.cnf
openssl x509 -req -in kubelet-server.csr -CA ca.crt -CAkey ca.key -CAcreateserial -out kubelet-server.crt -days 3650 -extensions v3_req -extfile kubelet-server.cnf

# 6. Generate kubeconfigs with embedded certificates
echo "==> 6. Generating kubeconfig files..."
K8S_ENDPOINT="https://127.0.0.1:6443"

for USER in admin kube-controller-manager kube-scheduler kubelet kube-proxy; do
  CONFIG_PATH="/etc/kubernetes/${USER}.kubeconfig"

  kubectl config set-cluster vanilla-k8s \
    --certificate-authority=ca.crt \
    --embed-certs=true \
    --server="${K8S_ENDPOINT}" \
    --kubeconfig="${CONFIG_PATH}"

  kubectl config set-credentials "${USER}" \
    --client-certificate="${USER}.crt" \
    --client-key="${USER}.key" \
    --embed-certs=true \
    --kubeconfig="${CONFIG_PATH}"

  kubectl config set-context default \
    --cluster=vanilla-k8s \
    --user="${USER}" \
    --kubeconfig="${CONFIG_PATH}"

  kubectl config use-context default --kubeconfig="${CONFIG_PATH}"
done

# Configure root and local user kubectl context
mkdir -p /root/.kube
cp /etc/kubernetes/admin.kubeconfig /root/.kube/config
chmod 600 /root/.kube/config

if [ -n "${SUDO_USER:-}" ]; then
  USER_HOME=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
  mkdir -p "${USER_HOME}/.kube"
  if [ -f "${USER_HOME}/.kube/config" ]; then
    echo "==> Backing up existing ${USER_HOME}/.kube/config..."
    cp "${USER_HOME}/.kube/config" "${USER_HOME}/.kube/config.bak.$(date +%s)"
  fi
  cp /etc/kubernetes/admin.kubeconfig "${USER_HOME}/.kube/config"
  chown -R "${SUDO_USER}:${SUDO_USER}" "${USER_HOME}/.kube"
  chmod 600 "${USER_HOME}/.kube/config"
fi

# Cleanup temporary CSRs and lock permissions
rm -f -- *.csr *.cnf
chmod 600 -- *.key
echo "--> PKI and kubeconfigs generated successfully."
