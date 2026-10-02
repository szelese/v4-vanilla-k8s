#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "[-] This script must be run as root (or with sudo)." >&2
  exit 1
fi

export KUBECONFIG=/etc/kubernetes/admin.kubeconfig
TEST_NS="smoke-test-$(date +%s)-$$"

echo "================================================="
echo "        Running Cluster Smoke Tests             "
echo "================================================="

# Trap to guarantee cleanup on exit or failure
cleanup() {
  local exit_code=$?
  trap - EXIT

  echo "==> Cleaning up test namespace..."
  if ! kubectl delete namespace "${TEST_NS}" \
    --ignore-not-found=true \
    --wait=true \
    --timeout=60s >/dev/null 2>&1; then
    echo "[!] Could not confirm deletion of smoke-test namespace ${TEST_NS}." >&2
  fi

  exit "${exit_code}"
}

trap cleanup EXIT

# 1. Create temporary namespace
kubectl create namespace "${TEST_NS}"

# 2. Deploy test workload
echo "==> 1. Deploying test nginx workload..."
kubectl run nginx --image=registry.k8s.io/e2e-test-images/nginx:1.14-4 -n "${TEST_NS}" --port=80
kubectl expose pod nginx -n "${TEST_NS}" --port=80 --name=nginx-svc

echo "==> Waiting for test pod to be Running..."
kubectl wait --namespace "${TEST_NS}" --for=condition=Ready pod/nginx --timeout=60s

# 3. Test apiserver-to-kubelet logs and exec
echo "==> 2. Verifying apiserver-to-kubelet communication (logs & exec)..."
kubectl logs nginx -n "${TEST_NS}" >/dev/null
kubectl exec nginx -n "${TEST_NS}" -- echo "Exec OK" >/dev/null
echo "    -> API logs and exec functional."

# 4. Test DNS resolution and Service routing
echo "==> 3. Verifying DNS resolution and Service routing..."
kubectl run test-client --image=curlimages/curl:8.7.1 -n "${TEST_NS}" --restart=Never -- sleep 3600
kubectl wait --namespace "${TEST_NS}" --for=condition=Ready pod/test-client --timeout=60s

# Internal DNS lookup to CoreDNS
echo "    -> Testing internal DNS resolution (nginx-svc.${TEST_NS}.svc.cluster.local)..."
kubectl exec test-client -n "${TEST_NS}" -- nslookup "nginx-svc.${TEST_NS}.svc.cluster.local" >/dev/null

# External DNS lookup (upstream host resolver)
echo "    -> Testing external DNS resolution (example.com)..."
kubectl exec test-client -n "${TEST_NS}" -- nslookup example.com >/dev/null

# Service ClusterIP connectivity
echo "    -> Testing Service ClusterIP connectivity..."
kubectl exec test-client -n "${TEST_NS}" -- curl -fsS --max-time 5 "http://nginx-svc.${TEST_NS}.svc.cluster.local" >/dev/null

echo "================================================="
echo "  [SUCCESS] All Smoke Tests Passed! Cluster is OK "
echo "================================================="
