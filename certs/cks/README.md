# CKS: Certified Kubernetes Security Specialist

> New to a term here, like Pod Security Admission or Falco? The [glossary](../../platform-engineering/glossary.md#cks-exam-track) explains every term this track uses.

**Before this track:** a CKA, or the skills it tests. The Linux Foundation lets you book the CKS only after you pass the CKA. You need the [practice cluster](../README.md#the-practice-cluster) running, and for the AppArmor and Cilium tasks the [Lima VM](../README.md#the-lima-vm-for-apparmor-and-cilium). No Istio, no k3d lab.

A cluster that works is not yet a safe cluster. Out of the box, kubeadm leaves pods free to talk to each other, writes Secrets to etcd in plain text, logs no API calls, and lets any image from any registry run as root. The CKS exam checks that you close those gaps on a live cluster, quickly. This track walks through the six exam domains, each with short theory and 7 to 13 timed tasks, 65 in all, and ends with three scored mock exams that get harder one after another.

## The exam

The exam is a remote, proctored terminal session. You get a remote Linux desktop with a browser and a terminal, and you solve tasks on real clusters. The facts below come from the [Linux Foundation's CKS instructions](https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks) and the [CNCF curriculum](https://github.com/cncf/curriculum), as read on 13 November 2026:

| | |
|---|---|
| Kubernetes version | v1.37. The CNCF added the CKS curriculum for 1.37 on 3 November 2026 |
| Duration | 2 hours |
| Tasks | 15 to 20 performance-based tasks, each worth a share of the score |
| Prerequisite | a passed CKA |
| Where you work | each task names a host; you `ssh` to it, work there, and return. `sudo -i` gives you root |
| Tools on every host | `kubectl` with the `k` alias and Bash completion, `yq`, `curl`, `wget`, `man`, and a vi-style editor |
| Documentation allowed | kubernetes.io/docs and the Kubernetes blog, and the docs of Falco, bom, etcd, ingress-nginx, Cilium and Istio |

The documentation list matters. The browser opens the Kubernetes docs, but not GitHub, not the Trivy docs, and not AppArmor's wiki. So learn the flags of `trivy`, `kube-bench` and `apparmor_parser` by heart, or learn where `--help` hides them.

The exam spreads its tasks over several clusters. The practice setup has two: the two-node OrbStack cluster with Calico for most tasks, and the one-node Lima cluster with Cilium and AppArmor for the rest. Each task names its host.

## Domains and where you learn each one

The curriculum has six domains. The weight is the share of the score:

| File | Domain | Weight | Tasks |
|---|---|---|---|
| [01-cluster-setup.md](01-cluster-setup.md) | Cluster setup | 15% | 13 |
| [02-cluster-hardening.md](02-cluster-hardening.md) | Cluster hardening | 15% | 12 |
| [03-system-hardening.md](03-system-hardening.md) | System hardening | 10% | 7 |
| [04-minimize-microservice-vulnerabilities.md](04-minimize-microservice-vulnerabilities.md) | Minimize microservice vulnerabilities | 20% | 10 |
| [05-supply-chain-security.md](05-supply-chain-security.md) | Supply chain security | 20% | 10 |
| [06-monitoring-logging-runtime-security.md](06-monitoring-logging-runtime-security.md) | Monitoring, logging and runtime security | 20% | 13 |
| [mock-exam.md](mock-exam.md) | Mock exam 1: all six domains, one topic per task | | 17 |
| [mock-exam-2.md](mock-exam-2.md) | Mock exam 2: a broken API server at the start, tasks that share files | | 17 |
| [mock-exam-3.md](mock-exam-3.md) | Mock exam 3: a broken control plane, rotation, fail-closed admission | | 17 |

Every task's check failed after its setup and passed after its reference solution in the test run, on the live clusters. Each mock exam scored 0 on a fresh setup and 100 after its reference solution.

## Gap map

The table lists every competency of the 1.37 curriculum. The middle column says where the course already explains the idea, so read that part first and don't expect the track to repeat it. The right column says where you practise it the exam way.

| Competency | The course already explains | Practise it in |
|---|---|---|
| **Cluster setup** | | |
| Use network security policies to restrict cluster-level access | NetworkPolicy against Istio's AuthorizationPolicy in [module 3](../../platform-engineering/03-authorization.md#concept-authorizationpolicy-compared-with-networkpolicy); a NetworkPolicy that locks a pod in, in [module 12](../../platform-engineering/12-egress.md#4-lock-the-course-client-in); generated default-deny policies in [module 26](../../platform-engineering/26-kyverno-policy-as-code.md); where the kernel enforces policy (kube-router) in [module 29](../../platform-engineering/29-life-of-a-request.md#security-checkpoints-end-to-end); Cilium and eBPF in [module 10](../../platform-engineering/10-ebpf-and-cilium.md) | [01, tasks 1, 2 and 6 to 8](01-cluster-setup.md#task-1-default-deny-and-one-allowed-path); Cilium in [01, tasks 9 to 11](01-cluster-setup.md#task-9-a-ciliumnetworkpolicy-at-layers-3-and-4) |
| Use the CIS benchmark to review component configuration | nothing | [01, tasks 3 and 12](01-cluster-setup.md#task-3-fix-cis-findings-with-kube-bench) |
| Properly set up Ingress objects with TLS | TLS, certificates and trust in [module 11](../../platform-engineering/11-edge-tls.md#concept-how-a-client-decides-to-trust-a-certificate), with the Gateway API instead of Ingress | [01, task 4](01-cluster-setup.md#task-4-an-ingress-with-tls) |
| Protect node metadata and endpoints | nothing | [01, tasks 2 and 13](01-cluster-setup.md#task-2-block-the-node-metadata-endpoint) |
| Verify platform binaries before deploying | nothing | [01, task 5](01-cluster-setup.md#task-5-verify-a-platform-binary) |
| **Cluster hardening** | | |
| Use RBAC to minimize exposure | the API server's gates and `system:masters` in [module 29](../../platform-engineering/29-life-of-a-request.md#concept-inside-the-api-server); an agent that borrows cluster-admin in [module 19](../../platform-engineering/19-ai-agents.md#concept-whose-permissions-a-tool-uses) | [02, tasks 1, 5, 6 and 12](02-cluster-hardening.md#task-1-trim-an-over-broad-role) |
| Exercise caution with service accounts | service accounts as mesh identity in [module 2](../../platform-engineering/02-identity-and-mtls.md#concept-an-identity-per-service-account); a tool server's token in [module 19](../../platform-engineering/19-ai-agents.md#6-take-the-agents-write-access-away) | [02, tasks 2, 7 and 8](02-cluster-hardening.md#task-2-service-account-tokens) |
| Restrict access to the Kubernetes API | authentication, authorization and admission in [module 29](../../platform-engineering/29-life-of-a-request.md#concept-inside-the-api-server) | [02, task 3](02-cluster-hardening.md#task-3-restrict-anonymous-access-to-the-api); a broken control plane in [02, tasks 9 to 11](02-cluster-hardening.md#task-9-repair-the-api-server) |
| Upgrade Kubernetes to avoid vulnerabilities | why clusters fall behind, and a k3s upgrade in [module 21](../../platform-engineering/21-k3s-lifecycle.md#the-bigger-picture-why-clusters-fall-behind); drains in [module 20](../../platform-engineering/20-nodes-and-cleanup.md#concept-cordon-drain-delete) | [02, task 4](02-cluster-hardening.md#task-4-upgrade-the-cluster-with-kubeadm) |
| **System hardening** | | |
| Minimize host OS footprint | nothing | [03, tasks 1, 4 and 7](03-system-hardening.md#task-1-remove-a-service-nobody-needs) |
| Use least-privilege identity and access management | nothing on node users; the Node authorizer in [module 29](../../platform-engineering/29-life-of-a-request.md#concept-inside-the-api-server) | [03, tasks 2, 3, 5 and 6](03-system-hardening.md#task-2-a-user-with-too-much-power) |
| **Minimize microservice vulnerabilities** | | |
| Use appropriate Pod Security Standards | why sidecar mode needs more than `baseline`, in [module 7](../../platform-engineering/07-sidecar-mode.md#why-this-way-and-why-ambient-exists); policies that refuse workloads in [module 26](../../platform-engineering/26-kyverno-policy-as-code.md) | [04, tasks 1, 6, 7 and 8](04-minimize-microservice-vulnerabilities.md#task-1-enforce-the-restricted-standard) |
| Manage Kubernetes Secrets | etcd and the datastore in [module 21](../../platform-engineering/21-k3s-lifecycle.md#concept-where-k3s-keeps-its-state) | [04, tasks 2, 3 and 5](04-minimize-microservice-vulnerabilities.md#task-2-encrypt-secrets-at-rest) |
| Isolation techniques: multi-tenancy, sandboxed containers | namespaces as tenants with generated defaults in [module 26](../../platform-engineering/26-kyverno-policy-as-code.md); kernel space against user space in [module 10](../../platform-engineering/10-ebpf-and-cilium.md#concept-kernel-space-and-user-space) | [04, tasks 4 and 9](04-minimize-microservice-vulnerabilities.md#task-4-sandbox-a-pod-with-gvisor) |
| Pod-to-pod encryption with Cilium or Istio | Istio mTLS and HBONE in [module 2](../../platform-engineering/02-identity-and-mtls.md); Cilium's WireGuard and IPsec in [module 10](../../platform-engineering/10-ebpf-and-cilium.md#why-this-way-the-two-designs-share-one-idea) | [04, task 10](04-minimize-microservice-vulnerabilities.md#task-10-pod-to-pod-encryption-with-cilium), on one node: it proves the setting, not traffic between nodes |
| **Supply chain security** | | |
| Minimize base image footprint | nothing | [05, task 1](05-supply-chain-security.md#task-1-shrink-a-dockerfile) |
| Understand your supply chain: SBOM, CI/CD, artifact repositories | GitOps from a Git server in [module 22](../../platform-engineering/22-gitops-with-argocd.md) | [05, tasks 3 and 10](05-supply-chain-security.md#task-3-write-an-sbom) |
| Secure your supply chain: permitted registries, signatures | admission webhooks and Kyverno's `verifyImages` in [module 26](../../platform-engineering/26-kyverno-policy-as-code.md#concept-four-things-a-policy-does) | [05, tasks 5 to 8](05-supply-chain-security.md#task-5-allow-only-approved-registries); signatures in theory only |
| Static analysis of workloads and images | nothing | [05, tasks 2, 4 and 9](05-supply-chain-security.md#task-2-find-and-remove-vulnerable-images) |
| **Monitoring, logging and runtime security** | | |
| Behavioral analytics to detect malicious activity | eBPF, the technique Falco uses, in [module 10](../../platform-engineering/10-ebpf-and-cilium.md#concept-what-ebpf-is) | [06, tasks 2, 7 and 8](06-monitoring-logging-runtime-security.md#task-2-catch-a-shell-with-falco) |
| Minimize external access to the network | egress lock-down in [module 12](../../platform-engineering/12-egress.md#the-bigger-picture-why-egress-control-matters) | [01, tasks 1, 6 and 11](01-cluster-setup.md#task-6-egress-to-dns-and-the-api-server-only) |
| Detect threats in infrastructure, apps, networks, data, users and workloads | metrics and alerts in [module 23](../../platform-engineering/23-prometheus-and-alerting.md) | [06, tasks 2, 6 and 9](06-monitoring-logging-runtime-security.md#task-9-which-pod-hunts-for-keys) |
| Kernel hardening tools: AppArmor, seccomp | nothing | [06, tasks 4, 5 and 12](06-monitoring-logging-runtime-security.md#task-4-a-seccomp-profile); kernel modules in [03, task 7](03-system-hardening.md#task-7-keep-a-kernel-module-out) |
| Investigate phases of an attack and bad actors | incident hunting in [module 8](../../platform-engineering/08-incidents.md) | [06, tasks 6 and 10](06-monitoring-logging-runtime-security.md#task-6-investigate-an-attack) |
| Ensure immutability of containers at runtime | nothing | [06, tasks 3 and 13](06-monitoring-logging-runtime-security.md#task-3-make-a-container-immutable) |
| Use Kubernetes audit logs to monitor access | nothing | [06, tasks 1, 10 and 11](06-monitoring-logging-runtime-security.md#task-1-turn-on-audit-logging) |

Two things stay untested on this setup. Cilium's WireGuard runs on one node, so no packet crosses the tunnel. And cosign signatures need a registry you push to, so the track covers them in theory.

## How to use the track

The plan below takes about four weeks at an hour a day. The order follows how the topics build on each other, not the curriculum's numbering.

1. Build both clusters: `./certs/cks/cluster/create.sh`, then `./certs/cks/cluster/lima.sh create`.
2. Work through the domain files in order: 01, 02, 03, 04, 05, 06. Domain 02 teaches the static pod repairs that every later API server edit relies on, and domain 06 needs audit logging and Falco basics from its own first tasks. For each domain, read the theory, then do each task against its time budget. Open the solution only when the time runs out.
3. Run the task's check command. It prints `PASS` or `FAIL` for each thing the task asked.
4. Reset between domains: `./certs/cks/cluster/reset.sh`, and `./certs/cks/cluster/lima.sh reset` when you used the Lima VM. Some tasks change the API server, upgrade the cluster, or load kernel profiles.
5. Repeat the tasks you needed the solution for, a few days later, until each one fits its budget.
6. Take the mock exams in order, each on freshly reset clusters, each with its 2-hour clock: [mock exam 1](mock-exam.md), then [mock exam 2](mock-exam-2.md), then [mock exam 3](mock-exam-3.md). `score.sh` prints the minutes since `setup.sh` and flags a run over 120. Leave a few days between them, and review every lost point before the next one.
7. Aim for 80 points or more on mock 3 inside the time. A margin above the pass mark matters, because the exam clusters are less familiar than these.

Every command in the track runs on a node. Open a shell with `orb -m cks-cp`, `orb -m cks-w1` or `./certs/cks/cluster/lima.sh shell`. The track files sit in your Mac's home folder, and OrbStack and Lima both show that folder at the same path inside the machines. So `cd` to the repo inside the node, and the paths in the text work there too.

## Exam habits worth drilling

- Set up the shell once per exam: `export do="--dry-run=client -o yaml"`, so that `k run x --image=nginx $do > x.yaml` writes a manifest to edit. The practice cluster's `/etc/bash.bashrc` already sets `k`, completion and `$do`.
- Back up a static pod manifest before you edit it: `cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/`. Keep the copy outside the manifests folder, because the kubelet starts every file in that folder.
- After an API server edit, wait for it to come back: `watch crictl ps`, then `k get nodes`. When it doesn't come back, read `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log` or `crictl logs`.
- Read the task's namespace and host twice. A perfect answer in the wrong namespace scores zero.
