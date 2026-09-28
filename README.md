# V4 Vanilla Kubernetes on Bare-Metal

Modular, automated scripts for bootstrapping a Vanilla Kubernetes v1.36.4 cluster directly on Ubuntu 22.04 bare-metal/VM using native systemd units.

## Architecture

![Architecture Draft](docs/architecture-draft.png)

## Quickstart

```bash
git clone https://github.com/szelese/v4-vanilla-k8s.git
cd v4-vanilla-k8s
sudo ./install.sh
```

## Architectural Scope & Trade-offs

* **Single-Node Topology:** Designed specifically as a single-host control-plane + worker runtime lab using local bridge CNI (`10.244.0.0/24`) and loopback API routing (`127.0.0.1:6443`). For multi-node expansion, replace host-local IPAM with an overlay CNI (e.g. Cilium/Calico).
* **Static mTLS Baseline:** OpenSSL PKI issues long-lived (3650-day) certificates without dynamic Kubelet CSR rotation for educational determinism.

## Execution Pipeline

The cluster is bootstrapped sequentially through modular scripts:

1. **`scripts/01-host-prep.sh`**: Swap off, kernel modules (`overlay`, `br_netfilter`), containerd cgroup v2, and `crictl.yaml`.
2. **`scripts/02-binaries.sh`**: Fetches official k8s v1.36.4, etcd, CNI plugins, and crictl binaries.
3. **`scripts/03-pki.sh`**: OpenSSL mTLS generation (CA, Front-Proxy CA, etcd/apiserver SANs, embedded kubeconfigs).
4. **`scripts/04-control-plane.sh`**: Systemd units for etcd, apiserver, controller-manager, scheduler, and apiserver-to-kubelet RBAC.
5. **`scripts/05-worker-networking.sh`**: Bridge CNI (`10.244.0.0/24`), kubelet, and kube-proxy (iptables mode).
6. **`scripts/06-addons-rbac.sh`**: In-cluster CoreDNS deployment.
7. **`scripts/07-smoke-test.sh`**: Automated validation (pod scheduling, logs/exec mTLS, DNS resolution, and Service routing).


## ✍️ Author & Legal
Ervin Wallin © 2026.
This project is a Kubernetes runtime extension of my cloud-native architecture portfolio. This repository is provided for educational and portfolio purposes.
