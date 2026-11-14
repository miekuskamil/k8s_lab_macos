# CKS: Certified Kubernetes Security Specialist

> New to a term here, like Pod Security Admission or Falco? The [glossary](../../course/glossary.md#cks-exam-track) explains every term this track uses.

**Before this track:** a CKA, or the skills it tests. The Linux Foundation lets you book the CKS only after you pass the CKA. You need the [practice cluster](../README.md#the-practice-cluster) running. No Istio, no k3d lab.

A cluster that works is not yet a safe cluster. Out of the box, kubeadm leaves pods free to talk to each other, writes Secrets to etcd in plain text, logs no API calls, and lets any image from any registry run as root. The CKS exam checks that you close those gaps on a live cluster, quickly. This track walks through the six exam domains, each with short theory and timed tasks, and ends with a scored mock exam.

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

## Domains and where you learn each one

The curriculum has six domains. The weight is the share of the score:

| File | Domain | Weight |
|---|---|---|
| [01-cluster-setup.md](01-cluster-setup.md) | Cluster setup | 15% |
| [02-cluster-hardening.md](02-cluster-hardening.md) | Cluster hardening | 15% |
| [03-system-hardening.md](03-system-hardening.md) | System hardening | 10% |
| [04-minimize-microservice-vulnerabilities.md](04-minimize-microservice-vulnerabilities.md) | Minimize microservice vulnerabilities | 20% |
| [05-supply-chain-security.md](05-supply-chain-security.md) | Supply chain security | 20% |
| [06-monitoring-logging-runtime-security.md](06-monitoring-logging-runtime-security.md) | Monitoring, logging and runtime security | 20% |
| [mock-exam.md](mock-exam.md) | All six, 17 tasks in 2 hours, scored by a script | |

## Gap map

The table lists every competency of the 1.37 curriculum. The middle column says where the course already explains the idea, so read that part first and don't expect the track to repeat it. The right column says where you practise it the exam way.

| Competency | The course already explains | Practise it in |
|---|---|---|
| **Cluster setup** | | |
| Use network security policies to restrict cluster-level access | NetworkPolicy against Istio's AuthorizationPolicy in [module 3](../../course/03-authorization.md#concept-authorizationpolicy-compared-with-networkpolicy); a NetworkPolicy that locks a pod in, in [module 12](../../course/12-egress.md#4-lock-the-course-client-in); generated default-deny policies in [module 26](../../course/26-kyverno-policy-as-code.md); where the kernel enforces policy (kube-router) in [module 29](../../course/29-life-of-a-request.md#security-checkpoints-end-to-end) | [01, tasks 1 and 2](01-cluster-setup.md#task-1-default-deny-and-one-allowed-path) |
| Use the CIS benchmark to review component configuration | nothing | [01, task 3](01-cluster-setup.md#task-3-fix-cis-findings-with-kube-bench) |
| Properly set up Ingress objects with TLS | TLS, certificates and trust in [module 11](../../course/11-edge-tls.md#concept-how-a-client-decides-to-trust-a-certificate), with the Gateway API instead of Ingress | [01, task 4](01-cluster-setup.md#task-4-an-ingress-with-tls) |
| Protect node metadata and endpoints | nothing | [01, task 2](01-cluster-setup.md#task-2-block-the-node-metadata-endpoint) |
| Verify platform binaries before deploying | nothing | [01, task 5](01-cluster-setup.md#task-5-verify-a-platform-binary) |
| **Cluster hardening** | | |
| Use RBAC to minimize exposure | the API server's gates and `system:masters` in [module 29](../../course/29-life-of-a-request.md#concept-inside-the-api-server); an agent that borrows cluster-admin in [module 19](../../course/19-ai-agents.md#concept-whose-permissions-a-tool-uses) | [02, task 1](02-cluster-hardening.md#task-1-trim-an-over-broad-role) |
| Exercise caution with service accounts | service accounts as mesh identity in [module 2](../../course/02-identity-and-mtls.md#concept-an-identity-per-service-account); a tool server's token in [module 19](../../course/19-ai-agents.md#6-take-the-agents-write-access-away) | [02, task 2](02-cluster-hardening.md#task-2-service-account-tokens) |
| Restrict access to the Kubernetes API | authentication, authorization and admission in [module 29](../../course/29-life-of-a-request.md#concept-inside-the-api-server) | [02, task 3](02-cluster-hardening.md#task-3-restrict-anonymous-access-to-the-api) |
| Upgrade Kubernetes to avoid vulnerabilities | why clusters fall behind, and a k3s upgrade in [module 21](../../course/21-k3s-lifecycle.md#the-bigger-picture-why-clusters-fall-behind); drains in [module 20](../../course/20-nodes-and-cleanup.md#concept-cordon-drain-delete) | [02, task 4](02-cluster-hardening.md#task-4-upgrade-the-cluster-with-kubeadm) |
| **System hardening** | | |
| Minimize host OS footprint | nothing | [03, task 1](03-system-hardening.md#task-1-remove-a-service-nobody-needs) |
| Use least-privilege identity and access management | nothing on node users; the Node authorizer in [module 29](../../course/29-life-of-a-request.md#concept-inside-the-api-server) | [03, tasks 2 and 3](03-system-hardening.md#task-2-a-user-with-too-much-power) |
| **Minimize microservice vulnerabilities** | | |
| Use appropriate Pod Security Standards | why sidecar mode needs more than `baseline`, in [module 7](../../course/07-sidecar-mode.md#why-this-way-and-why-ambient-exists); policies that refuse workloads in [module 26](../../course/26-kyverno-policy-as-code.md) | [04, task 1](04-minimize-microservice-vulnerabilities.md#task-1-enforce-the-restricted-standard) |
| Manage Kubernetes Secrets | etcd and the datastore in [module 21](../../course/21-k3s-lifecycle.md#concept-where-k3s-keeps-its-state) | [04, tasks 2 and 3](04-minimize-microservice-vulnerabilities.md#task-2-encrypt-secrets-at-rest) |
| Isolation techniques: multi-tenancy, sandboxed containers | namespaces as tenants with generated defaults in [module 26](../../course/26-kyverno-policy-as-code.md); kernel space against user space in [module 10](../../course/10-ebpf-and-cilium.md#concept-kernel-space-and-user-space) | [04, task 4](04-minimize-microservice-vulnerabilities.md#task-4-sandbox-a-pod-with-gvisor) |
| Pod-to-pod encryption with Cilium or Istio | Istio mTLS and HBONE in [module 2](../../course/02-identity-and-mtls.md); Cilium's WireGuard and IPsec in [module 10](../../course/10-ebpf-and-cilium.md#why-this-way-the-two-designs-share-one-idea) | [04, theory only](04-minimize-microservice-vulnerabilities.md#pod-to-pod-encryption) |
| **Supply chain security** | | |
| Minimize base image footprint | nothing | [05, task 1](05-supply-chain-security.md#task-1-shrink-a-dockerfile) |
| Understand your supply chain: SBOM, CI/CD, artifact repositories | GitOps from a Git server in [module 22](../../course/22-gitops-with-argocd.md) | [05, task 3](05-supply-chain-security.md#task-3-write-an-sbom) |
| Secure your supply chain: permitted registries, signatures | admission webhooks and Kyverno's `verifyImages` in [module 26](../../course/26-kyverno-policy-as-code.md#concept-four-things-a-policy-does) | [05, task 5](05-supply-chain-security.md#task-5-allow-only-approved-registries) |
| Static analysis of workloads and images | nothing | [05, tasks 2 and 4](05-supply-chain-security.md#task-2-find-and-remove-vulnerable-images) |
| **Monitoring, logging and runtime security** | | |
| Behavioral analytics to detect malicious activity | eBPF, the technique Falco uses, in [module 10](../../course/10-ebpf-and-cilium.md#concept-what-ebpf-is) | [06, task 2](06-monitoring-logging-runtime-security.md#task-2-catch-a-shell-with-falco) |
| Minimize external access to the network | egress lock-down in [module 12](../../course/12-egress.md#the-bigger-picture-why-egress-control-matters) | [01, task 1](01-cluster-setup.md#task-1-default-deny-and-one-allowed-path) |
| Detect threats in infrastructure, apps, networks, data, users and workloads | metrics and alerts in [module 23](../../course/23-prometheus-and-alerting.md) | [06, tasks 2 and 6](06-monitoring-logging-runtime-security.md#task-6-investigate-an-attack) |
| Kernel hardening tools: AppArmor, seccomp | nothing | [06, tasks 4 and 5](06-monitoring-logging-runtime-security.md#task-4-a-seccomp-profile) |
| Investigate phases of an attack and bad actors | incident hunting in [module 8](../../course/08-incidents.md) | [06, task 6](06-monitoring-logging-runtime-security.md#task-6-investigate-an-attack) |
| Ensure immutability of containers at runtime | nothing | [06, task 3](06-monitoring-logging-runtime-security.md#task-3-make-a-container-immutable) |
| Use Kubernetes audit logs to monitor access | nothing | [06, task 1](06-monitoring-logging-runtime-security.md#task-1-turn-on-audit-logging) |

## How to use the track

1. Build the cluster: `./certs/cks/cluster/create.sh`.
2. For each domain, read the theory, then do each task against its time budget. Open the solution only when the time runs out.
3. Run the task's check command. It prints `PASS` or `FAIL` for each thing the task asked.
4. Run `./certs/cks/cluster/reset.sh` between domains, because some tasks change the API server or upgrade the cluster.
5. At the end, take the [mock exam](mock-exam.md) on a fresh cluster, with a two-hour timer.

Every command in the track runs on a node. Open a shell with `orb -m cks-cp` or `orb -m cks-w1`. The track files sit in your Mac's home folder, and OrbStack shows that folder at the same path inside the machines. So `cd` to the repo inside the node, and the paths in the text work there too.

## Exam habits worth drilling

- Set up the shell once per exam: `export do="--dry-run=client -o yaml"`, so that `k run x --image=nginx $do > x.yaml` writes a manifest to edit. The practice cluster's `/etc/bash.bashrc` already sets `k`, completion and `$do`.
- Back up a static pod manifest before you edit it: `cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/`. Keep the copy outside the manifests folder, because the kubelet starts every file in that folder.
- After an API server edit, wait for it to come back: `watch crictl ps`, then `k get nodes`. When it doesn't come back, read `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log` or `crictl logs`.
- Read the task's namespace and host twice. A perfect answer in the wrong namespace scores zero.
