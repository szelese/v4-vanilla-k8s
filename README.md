# V4 Vanilla Kubernetes on Bare-Metal and VMs

Modular, automated scripts for bootstrapping a Vanilla Kubernetes v1.36.5 cluster directly on Ubuntu 22.04, 24.04, and 26.04 LTS bare-metal/VM hosts using native systemd units.

## 🚧 Project Status & Scope

This repository represents an active engineering lab and reference architecture for Vanilla Kubernetes on bare-metal.

* **Status:** Final compatibility testing is pending. Add `X` after a clean installation and all smoke tests pass for that Ubuntu version and architecture.
* **Target Architectures:** `amd64` (x86_64) and `arm64` (aarch64) with automated host detection.
* **Intended Use:** Educational baseline, cloud-native portfolio showcase, and low-dependency on-prem prototyping.

### Compatibility Matrix

| Ubuntu version | `amd64` (`x86_64`) | `arm64` (`aarch64`) |
| :--- | :---: | :---: |
| Ubuntu 22.04 LTS (Jammy) |  |  |
| Ubuntu 24.04 LTS (Noble) |  |  |
| Ubuntu 26.04 LTS (Resolute) |  |  |

`X` = clean installation and all smoke tests passed for that Ubuntu version and architecture.

Testing was performed across local Multipass/KVM and AWS EC2 environments.

## Requirements

* **Operating system and architecture:** Ubuntu 22.04, 24.04, or 26.04 LTS on `amd64` (`x86_64`) or `arm64` (`aarch64`), as listed in the compatibility matrix.
* **Host:** A clean, dedicated machine or VM with root access. The installer changes host-level settings, including swap, kernel modules, sysctl parameters, and containerd configuration.
* **Network access:** Outbound DNS and internet access to Ubuntu package repositories, `dl.k8s.io`, GitHub Releases, and the container registries used by the smoke tests.

## Quickstart

> **Fresh-host install only:** Run `install.sh` once on a clean Ubuntu host. The installer does not support rerunning after a successful or partial installation. To retry after a failure, provision a fresh VM.

```bash
git clone https://github.com/szelese/v4-vanilla-k8s.git
cd v4-vanilla-k8s
sudo ./install.sh
```

## Architectural Scope & Trade-offs

* **Single-Node Topology:** Designed specifically as a single-host control-plane + worker runtime lab using local bridge CNI (`10.244.0.0/24`). The kube-apiserver binds to `0.0.0.0:6443` for cluster and Pod reachability, while local CLI tooling connects via `127.0.0.1:6443`.
* **Multi-Node Expansion Requirements:** Expanding beyond a single node requires more than replacing host-local IPAM with an overlay CNI (e.g. Cilium/Calico): it also requires a dedicated control-plane load balancer / VIP, expanded certificate SANs, and controller-managed PodCIDR allocation.
* **Static mTLS Lab Baseline:** OpenSSL-generated X.509 certificates secure etcd, control-plane components, and Kubelet client-server communication. Certificates are valid for 3650 days and are not rotated through the Kubernetes CSR workflow; this keeps the lab setup simple and is not intended as a production certificate lifecycle.
* **NetworkPolicy Limitation:** The current bridge CNI and host-local IPAM setup provides Pod networking and IP allocation but does not enforce Kubernetes NetworkPolicy resources. Policy enforcement requires a CNI implementation that supports NetworkPolicy.
* **Security Scope:** This is an educational single-node lab, not a production-hardened security profile. The API server listens on `0.0.0.0:6443`, while local CLI tooling connects through `127.0.0.1:6443`; restrict external access with host or cloud firewall rules. The scripts do not configure etcd encryption at rest, API audit logging, or a restricted/baseline Pod Security Admission policy, and do not explicitly disable anonymous API authentication (`--anonymous-auth` defaults to `true`).

## Architecture

![Architecture Draft](docs/architecture-draft.png)

## Execution Pipeline

The cluster is bootstrapped sequentially through modular scripts:

1. **`scripts/01-host-prep.sh`**: Swap off, kernel modules (`overlay`, `br_netfilter`), containerd cgroup v2, and `crictl.yaml`.
2. **`scripts/02-binaries.sh`**: Fetches official k8s v1.36.5, etcd, CNI plugins, and crictl binaries.
3. **`scripts/03-pki.sh`**: OpenSSL mTLS generation (CA, Front-Proxy CA, etcd/apiserver SANs, embedded kubeconfigs).
4. **`scripts/04-control-plane.sh`**: Systemd units for etcd, apiserver, controller-manager, scheduler, and apiserver-to-kubelet RBAC.
5. **`scripts/05-worker-networking.sh`**: Bridge CNI (`10.244.0.0/24`), kubelet, and kube-proxy (iptables mode).
6. **`scripts/06-addons-rbac.sh`**: In-cluster CoreDNS deployment.
7. **`scripts/07-smoke-test.sh`**: Automated validation (pod scheduling, logs/exec mTLS, DNS resolution, and Service routing).


## ✍️ Author & Legal
Ervin Wallin © 2026.
This project is a Kubernetes runtime extension of my cloud-native architecture portfolio. This repository is provided for educational and portfolio purposes.
