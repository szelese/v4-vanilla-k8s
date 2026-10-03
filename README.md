# V4 Vanilla Kubernetes on Bare-Metal and VMs

[![Compatibility: 6/6 verified](https://img.shields.io/badge/Compatibility-6%2F6%20verified-brightgreen?style=flat-square)](./docs/verification/)
[![ShellCheck](https://github.com/szelese/v4-vanilla-k8s/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/szelese/v4-vanilla-k8s/actions/workflows/shellcheck.yml)
[![Platform: amd64 + arm64](https://img.shields.io/badge/Platform-amd64%20%2B%20arm64-blue?style=flat-square)](#compatibility-matrix)

Modular, automated scripts for bootstrapping a Vanilla Kubernetes v1.36.5 cluster directly on Ubuntu 22.04, 24.04, and 26.04 LTS bare-metal/VM hosts using native systemd units.

## 🚧 Project Status & Scope

This repository represents an active engineering lab and reference architecture for Vanilla Kubernetes on bare-metal.

* **Status:** Compatibility testing is complete for all six combinations marked `X` below.
* **Target Architectures:** `amd64` (x86_64) and `arm64` (aarch64) with automated host detection.
* **Intended Use:** Educational baseline, cloud-native portfolio showcase, and low-dependency on-prem prototyping.

### Compatibility Matrix

| Ubuntu version | `amd64` (`x86_64`) | `arm64` (`aarch64`) |
| :--- | :---: | :---: |
| Ubuntu 22.04 LTS (Jammy) | X | X |
| Ubuntu 24.04 LTS (Noble) | X | X |
| Ubuntu 26.04 LTS (Resolute) | X | X |

`X` = clean installation and all smoke tests passed for that Ubuntu version and architecture.

Test environments: a physical laptop with a clean Ubuntu installation, local Multipass, and AWS EC2.

## Requirements

* **Operating system and architecture:** Ubuntu 22.04, 24.04, or 26.04 LTS on `amd64` (`x86_64`) or `arm64` (`aarch64`), as listed in the compatibility matrix.
* **Container runtime:** containerd 2.x or newer. The installer installs it from Ubuntu packages and exits if an older version is detected.
* **Host:** A clean, dedicated machine or VM with root access. The installer changes host-level settings, including swap, kernel modules, sysctl parameters, and containerd configuration.
* **Network access:** Outbound DNS and internet access to Ubuntu package repositories, `dl.k8s.io`, GitHub Releases, and the container registries used by the smoke tests.
* **Stable node IP:** The installer detects the node's primary IPv4 address during installation and uses it in certificate SANs and Kubernetes component configuration. Keep this address unchanged while the cluster is in use. If it changes, reinstall on a fresh host.

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
* **Security Scope:** This is an educational single-node lab, not a production-hardened security profile. The API server listens on `0.0.0.0:6443`, while local CLI tooling connects through `127.0.0.1:6443`; restrict external access with host or cloud firewall rules. The scripts do not configure etcd encryption at rest, API audit logging, or a restricted/baseline Pod Security Admission policy. Anonymous API authentication is disabled with `--anonymous-auth=false`.

## Architecture

![Architecture Draft](docs/architecture-draft.png)

## Execution Pipeline

The cluster is bootstrapped sequentially through modular scripts:

1. **`scripts/01-host-prep.sh`**: Swap off, kernel modules (`overlay`, `br_netfilter`), containerd configured with the systemd cgroup driver, and `crictl.yaml`.
2. **`scripts/02-binaries.sh`**: Downloads Kubernetes v1.36.5, etcd v3.5.34, CNI plugins v1.9.1, and crictl v1.36.0 for the detected architecture; verifies SHA-256 checksums before installation or extraction.
3. **`scripts/03-pki.sh`**: OpenSSL mTLS generation (CA, Front-Proxy CA, etcd/apiserver SANs, embedded kubeconfigs).
4. **`scripts/04-control-plane.sh`**: Systemd units for etcd, apiserver, controller-manager, scheduler, and apiserver-to-kubelet RBAC.
5. **`scripts/05-worker-networking.sh`**: Bridge CNI (`10.244.0.0/24`), kubelet, and kube-proxy (iptables mode).
6. **`scripts/06-addons-rbac.sh`**: Deploys CoreDNS v1.14.7 with RBAC, a ConfigMap, a ClusterIP Service, and liveness/readiness probes.
7. **`scripts/07-smoke-test.sh`**: Validates Pod scheduling/readiness, apiserver-to-kubelet logs/exec, internal and external DNS, ClusterIP Service routing, and Pod-to-own-Service hairpin connectivity.

## ✍️ Author & Legal
Ervin Wallin © 2026.
This project is a Kubernetes runtime extension of my cloud-native architecture portfolio. This repository is provided for educational and portfolio purposes.
