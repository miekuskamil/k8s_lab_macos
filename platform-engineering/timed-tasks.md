# Timed tasks and exam preparation

> New to a term here? The [glossary](glossary.md) explains every term in the course, with the security terms under [the practice cluster and the security modules](glossary.md#the-practice-cluster-and-the-security-modules) and the application terms under [applications on Kubernetes](glossary.md#applications-on-kubernetes).

Modules 1.2 to 1.6 and 4.1 to 4.7 teach in a different rhythm from the lab modules. Each one opens with course-style theory, concepts and diagrams, and then hands you short tasks on the [practice cluster](practice-cluster.md), each with a time budget, because fixing a known problem quickly from a terminal is a skill of its own. This page explains how a task works, where you type, an order through the modules, and the terminal habits that save the most time. Its appendix lists, topic by topic, where the lab modules already explain an idea that a timed task drills.

## A task, step by step

Every task has a title, a time budget and a host, then a short brief in a quote block, then the solution inside a folded `<details>` block. The task id joins the module number and the task number, so task 3 of module 4.1 is `4.1.3`, and `./lab.sh task list` prints all 115 ids. The guide's [Practice cluster and timed tasks](../README.md#practice-cluster-and-timed-tasks) section walks through one task: `setup` seeds the starting state, `check` prints PASS or FAIL for each thing the task asks, and `solve` applies the reference solution.

Read the brief, start a timer, and solve the task on the node the brief names. Open the solution only when the time runs out, and run the check either way. Every setup starts its namespace from scratch, so you repeat a task by running its setup again.

The six timed practice exams work the same way for a whole exam, through `./lab.sh exam`. Exams 1 to 3 cover the application modules and sit at the end of [track 1](../README.md#1-applications), and exams 4 to 6 cover the security modules and sit at the end of [track 4](../README.md#4-cluster-security). Each gives you 2 hours for 16 or 17 tasks worth 100 points, and `score` prints the minutes since `setup` and flags a run over 120. Two forms go beyond the guide: `./lab.sh exam score 4 3 9` scores only tasks 3 and 9, and `./lab.sh exam solve 4 9` applies the reference solution of task 9 alone.

In the test run on the live clusters, every task's check failed after its setup and passed after its reference solution, and each practice exam scored 0 on a fresh setup and 100 after its reference solution. The run on 21 November 2026 repeated all six exams from a fresh clone with only Docker, git and Lima on the PATH, with the resets from the guide between them. Exam 2 scored 94 at first, because the reference LimitRange of task 6 filled the quota and the rolling restart waited for room, and after a fix to its defaults it scored 100 like the other five. A whole exam cycle of setup, score, solve and score took between 3 and 14 minutes.

## Where you type

Every command except the `./lab.sh` commands and the scripts they call runs on a node, in a root shell. `./lab.sh practice shell` opens that shell on the control plane, and `./lab.sh practice shell worker` opens it on the worker, already as root and with the `k` alias set. `./platform-engineering/practice/cluster/lima.sh shell` opens a root shell on the Lima VM that [module 4.7](../README.md#the-vm-for-the-kernel-tasks) needs. On OrbStack machines or your own VMs the same command works too, because `./lab.sh` follows the platform setting that the [practice cluster page](practice-cluster.md#other-platforms-orbstack-machines-and-your-own-vms) describes.

The tasks need no repo files on the nodes, because each setup writes what its task needs onto the node itself. The application tasks keep their files under `/opt/apps` on `practice-control-plane`, the way many teams keep a task's files under a folder like `/opt/course`.

The command blocks are terminal transcripts, where each prompt line holds a command and the lines under it hold the real output of the test run. The prompt says where to type: `$` is your Mac, in the repo folder, while `root@practice-control-plane:~#`, `root@practice-worker:~#` and `root@cks-lima:~#` are root shells on the nodes. A line with only `...` marks output the transcript leaves out, and pod names, IP addresses, container IDs, ages, digests and keys differ on your run.

## An order through the modules

The application modules 1.2 to 1.6 take about three weeks at an hour a day:

1. Build the cluster and the extras, as steps 1 and 2 of the guide's [practice cluster section](../README.md#practice-cluster-and-timed-tasks) show.
2. Work through modules 1.2 to 1.6 in order. Module 1.2 teaches pods and workloads that every later task builds on, and module 1.6 assumes the Services of module 1.4's debugging task. For each module, read the theory, then do each task against its time budget.
3. Reset between modules with the command from the guide's reset table.
4. Repeat the tasks you needed the solution for, a few days later, until each one fits its budget.
5. Take practice exams 1, 2 and 3 in order, each after a reset and with its 2-hour clock, and review every lost point before the next one. 80 points or more on exam 3 inside the time leaves a safe margin.

The security modules 4.1 to 4.7 take about four weeks at an hour a day:

1. Build both clusters: the practice cluster from the guide's [practice cluster section](../README.md#practice-cluster-and-timed-tasks), and the Lima VM from [the VM for module 4.7](../README.md#the-vm-for-the-kernel-tasks).
2. Work through modules 4.1 to 4.6 in order, and take each task of module 4.7 after the module it comes from. Module 4.2 teaches the static pod repairs that every later API server edit relies on, and module 4.6 builds on audit logging and Falco basics from its own first tasks.
3. Reset between modules with the commands from the guide's reset table, because some tasks change the API server, upgrade the cluster or load kernel profiles.
4. Repeat the tasks you needed the solution for, a few days later, until each one fits its budget.
5. Take practice exams 4, 5 and 6 in order, each on freshly reset clusters and with its 2-hour clock. Leave a few days between them, and aim for 80 points or more on exam 6 inside the time.

## Which modules cover each exam domain

These modules cover the curricula of the Certified Kubernetes Application Developer (CKAD) and the Certified Kubernetes Security Specialist (CKS) exams for Kubernetes v1.37, as read in November 2026. Both exams last 2 hours with 15 to 20 tasks on live clusters. The CKAD has no prerequisite and passes at 66%, and the CKS asks for a passed CKA first. The browser in both exams opens the Kubernetes docs, so practise finding an example on kubernetes.io quickly.

| Exam domain (weight) | Modules |
|---|---|
| CKAD: Application design and build (20%) | 33 |
| CKAD: Application deployment (20%) | 34 |
| CKAD: Application observability and maintenance (15%) | 35 |
| CKAD: Application environment, configuration and security (25%) | 36 |
| CKAD: Services and networking (20%) | 37 |
| CKAD: mock exams | practice exams 1 to 3 |
| CKS: Cluster setup (15%) | 38, and 44 tasks 1 to 3 |
| CKS: Cluster hardening (15%) | 39 |
| CKS: System hardening (10%) | 40, and 44 task 4 |
| CKS: Minimize microservice vulnerabilities (20%) | 41, and 44 task 5 |
| CKS: Supply chain security (20%) | 42 |
| CKS: Monitoring, logging and runtime security (20%) | 43, and 44 tasks 6 and 7 |
| CKS: mock exams | practice exams 4 to 6 |

## Working fast at the terminal

Speed decides these tasks more than any single topic, because 16 tasks in 120 minutes leave about 7 minutes each, reading included. The practice cluster's `/etc/bash.bashrc` already sets the `k` alias with completion and the variable `do`, which turns any imperative command into a YAML generator: `export do="--dry-run=client -o yaml"`. So `k create deploy web --image=nginx:1.27-alpine $do > web.yaml` writes a complete Deployment that you then edit, which is faster and safer than typing YAML from memory. The imperative commands below cover most objects the tasks ask for:

| Object | Command that writes it |
|---|---|
| Pod | `k run NAME --image=IMG --port=80 -l app=x $do -- sleep 1d` |
| Deployment | `k create deploy NAME --image=IMG --replicas=3 --port=80 $do` |
| Service | `k expose deploy NAME --port=80 --target-port=8080 [--type=NodePort]` |
| Job, CronJob | `k create job NAME --image=IMG $do -- CMD`, `k create cronjob NAME --image=IMG --schedule='*/5 * * * *' $do -- CMD` |
| ConfigMap, Secret | `k create cm NAME --from-literal=K=V --from-file=F`, `k create secret generic NAME --from-literal=K=V` |
| ServiceAccount, Role, RoleBinding | `k create sa NAME`, `k create role NAME --verb=get,list --resource=pods`, `k create rolebinding NAME --role=R --serviceaccount=NS:SA` |
| Ingress | `k create ingress NAME --class=nginx --rule='host/path*=svc:80'` |
| ResourceQuota | `k create quota NAME --hard=pods=5,requests.cpu=1` |
| Token | `k create token SA --duration=1h` |

A few edits never need YAML at all, because `kubectl` changes the field directly: `k set image deploy/web nginx=nginx:1.28-alpine`, `k set env deploy/web KEY=V`, `k set resources deploy/web --requests=cpu=100m`, `k set serviceaccount deploy web SA`, `k scale`, `k label` and `k annotate`.

When you forget where a field goes, `k explain` answers from the cluster's own API schema: `k explain pod.spec.containers.livenessProbe` describes one field, and `k explain deploy.spec --recursive | less` shows the whole tree. `k api-resources` lists every resource with its short name and API group, which settles the right `apiVersion` for a manifest.

The security tasks edit static pods, and three habits keep those edits safe. Back up a static pod manifest before you edit it with `cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/`, and keep the copy outside the manifests folder, because the kubelet starts every file in that folder. After an API server edit, wait for it to come back with `watch crictl ps`, then `k get nodes`. When it doesn't come back, read `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log` or `crictl logs`.

Three more habits pay off in every task. Read the task's namespace and host twice, because a perfect answer in the wrong namespace scores zero. Set the namespace once per task with `k config set-context --current --namespace=NS` when a task has many commands. And delete a pod you are about to recreate with `k delete pod NAME --force --grace-period=0`, which skips the 30-second wait that [module 1.2](1-applications/02-building-and-running-applications.md#task-2-change-a-dockerfile-and-roll-the-new-image-out) measured for a `sh` process. A `~/.vimrc` with `set expandtab tabstop=2 shiftwidth=2` keeps `vim` from writing tabs into YAML, which `kubectl` refuses.

## Appendix: where the lab modules explain each topic

The tables list every topic the timed tasks drill. The middle column says where a lab module already explains the idea, so read that part first when it exists, and the right column says where you practise it against the clock.

### Application modules

| Competency | The lab modules already show | Practise it in |
|---|---|---|
| **Application design and build** | | |
| Define, build and modify container images | nothing | [module 1.2, tasks 1 and 2](1-applications/02-building-and-running-applications.md#task-1-build-an-image-and-push-it) |
| Choose and use the right workload resource | Deployments everywhere; a Job in [module 2.6](2-observability/06-gitops-with-argocd.md) | [module 1.2, tasks 5, 6, 7 and 9](1-applications/02-building-and-running-applications.md#task-5-a-job-with-parallel-completions) |
| Understand multi-container pod design patterns | sidecar injection and native sidecars in [module 3.9](3-istio/09-sidecar-mode.md) | [module 1.2, tasks 3, 4 and 10](1-applications/02-building-and-running-applications.md#task-3-an-init-container-prepares-the-content) |
| Utilize persistent and ephemeral volumes | nothing | [module 1.2, tasks 3 and 8](1-applications/02-building-and-running-applications.md#task-8-a-persistentvolume-a-claim-and-a-pod) |
| **Application deployment** | | |
| Use primitives for blue/green or canary | a canary with Istio weights in [module 3.14](3-istio/14-istio-api.md) | [module 1.3, tasks 3 and 4](1-applications/03-deploying-and-updating-applications.md#task-3-blue-green) |
| Understand Deployments and rolling updates | nothing | [module 1.3, tasks 1, 2 and 10](1-applications/03-deploying-and-updating-applications.md#task-1-roll-back-a-broken-update) |
| Use the Helm package manager to deploy existing packages | Helm installs in [module 2.6](2-observability/06-gitops-with-argocd.md) and [module 2.7](2-observability/07-kyverno-policy-as-code.md) | [module 1.3, tasks 5, 6 and 7](1-applications/03-deploying-and-updating-applications.md#task-5-install-a-helm-chart-from-a-registry) |
| Kustomize | base and overlays in the GitOps repo of [module 2.6](2-observability/06-gitops-with-argocd.md) | [module 1.3, tasks 8 and 9](1-applications/03-deploying-and-updating-applications.md#task-8-a-kustomize-overlay-for-production) |
| **Application observability and maintenance** | | |
| Understand API deprecations | nothing | [module 1.4, task 7](1-applications/04-observing-and-debugging-applications.md#task-7-manifests-written-for-apis-that-no-longer-exist) |
| Implement probes and health checks | nothing | [module 1.4, tasks 1 and 2](1-applications/04-observing-and-debugging-applications.md#task-1-readiness-liveness-and-startup-probes) |
| Use built-in CLI tools to monitor applications | metrics with Prometheus in [module 2.1](2-observability/01-prometheus-and-alerting.md) | [module 1.4, task 4](1-applications/04-observing-and-debugging-applications.md#task-4-which-pod-uses-the-most-cpu) |
| Utilize container logs | logs in an incident in [module 3.7](3-istio/07-incidents.md) | [module 1.4, task 3](1-applications/04-observing-and-debugging-applications.md#task-3-logs-of-a-container-that-crashed) |
| Debugging in Kubernetes | incident hunting in [module 3.7](3-istio/07-incidents.md) | [module 1.4, tasks 5, 6 and 8](1-applications/04-observing-and-debugging-applications.md#task-5-debug-a-container-that-has-no-shell) |
| **Application environment, configuration and security** | | |
| Discover and use resources that extend Kubernetes (CRD, operators) | Istio's and Kyverno's CRDs in [module 3.14](3-istio/14-istio-api.md) and [module 2.7](2-observability/07-kyverno-policy-as-code.md) | [module 1.5, task 11](1-applications/05-configuration-and-secrets.md#task-11-use-a-customresourcedefinition) |
| Understand authentication, authorization and admission control | the API server's gates in [module 3.15](3-istio/15-life-of-a-request.md) | [module 1.5, tasks 8, 9 and 12](1-applications/05-configuration-and-secrets.md#task-8-a-role-for-a-ci-pipeline) |
| Understand requests, limits, quotas | nothing | [module 1.5, tasks 4, 5 and 6](1-applications/05-configuration-and-secrets.md#task-4-a-deployment-that-a-quota-keeps-from-starting) |
| Define resource requirements | nothing | [module 1.5, task 4](1-applications/05-configuration-and-secrets.md#task-4-a-deployment-that-a-quota-keeps-from-starting) |
| Understand ConfigMaps | ConfigMaps as files in [module 2.2](2-observability/02-grafana-as-code.md) | [module 1.5, tasks 1 and 3](1-applications/05-configuration-and-secrets.md#task-1-a-configmap-from-a-file-and-a-literal) |
| Create and consume Secrets | nothing | [module 1.5, task 2](1-applications/05-configuration-and-secrets.md#task-2-a-secret-as-an-environment-variable-and-as-a-file) |
| Understand ServiceAccounts | service accounts as mesh identity in [module 3.2](3-istio/02-identity-and-mtls.md) | [module 1.5, tasks 7 and 9](1-applications/05-configuration-and-secrets.md#task-7-serviceaccounts-and-their-tokens) |
| Understand application security (SecurityContexts, capabilities) | nothing; [module 4.4](4-security/04-hardening-workloads.md) goes deeper | [module 1.5, tasks 10 and 12](1-applications/05-configuration-and-secrets.md#task-10-a-security-context-field-by-field) |
| **Services and networking** | | |
| Demonstrate basic understanding of NetworkPolicies | NetworkPolicy against Istio's AuthorizationPolicy in [module 3.3](3-istio/03-authorization.md) | [module 1.6, tasks 6 to 9](1-applications/06-services-and-networking.md#task-6-deny-by-default-then-allow-one-path) |
| Provide and troubleshoot access to applications via services | a request through kube-proxy in [module 3.15](3-istio/15-life-of-a-request.md) | [module 1.6, tasks 1, 2, 3 and 10](1-applications/06-services-and-networking.md#task-1-a-clusterip-service); [module 1.4, task 8](1-applications/04-observing-and-debugging-applications.md#task-8-a-client-that-never-reaches-its-backend) |
| Use Ingress rules to expose applications | the Gateway API instead of Ingress in [module 3.10](3-istio/10-edge-tls.md) | [module 1.6, tasks 4 and 5](1-applications/06-services-and-networking.md#task-4-an-ingress-with-two-paths) |

The application modules cover Ingress and leave the Gateway API to the lab modules, which use it from module 3.4 on.

### Security modules

| Competency | The lab modules already explain | Practise it in |
|---|---|---|
| **Cluster setup** | | |
| Use network security policies to restrict cluster-level access | NetworkPolicy against Istio's AuthorizationPolicy in [module 3.3](3-istio/03-authorization.md#concept-authorizationpolicy-compared-with-networkpolicy); a NetworkPolicy that locks a pod in, in [module 3.11](3-istio/11-egress.md#4-lock-the-course-client-in); generated default-deny policies in [module 2.7](2-observability/07-kyverno-policy-as-code.md); where the kernel enforces policy (kube-router) in [module 3.15](3-istio/15-life-of-a-request.md#security-checkpoints-end-to-end); Cilium and eBPF in [module 3.21](3-istio/21-ebpf-and-cilium.md) | [module 4.1, tasks 1, 2 and 6 to 8](4-security/01-setting-up-a-secure-cluster.md#task-1-default-deny-and-one-allowed-path); Cilium in [module 4.7, tasks 1 to 3](4-security/07-kernel-and-host-security.md#task-1-a-ciliumnetworkpolicy-at-layers-3-and-4) |
| Use the CIS benchmark to review component configuration | nothing | [module 4.1, tasks 3 and 12](4-security/01-setting-up-a-secure-cluster.md#task-3-fix-cis-findings-with-kube-bench) |
| Properly set up Ingress objects with TLS | TLS, certificates and trust in [module 3.10](3-istio/10-edge-tls.md#concept-how-a-client-decides-to-trust-a-certificate), with the Gateway API instead of Ingress | [module 4.1, task 4](4-security/01-setting-up-a-secure-cluster.md#task-4-an-ingress-with-tls) |
| Protect node metadata and endpoints | nothing | [module 4.1, tasks 2 and 13](4-security/01-setting-up-a-secure-cluster.md#task-2-block-the-node-metadata-endpoint) |
| Verify platform binaries before deploying | nothing | [module 4.1, task 5](4-security/01-setting-up-a-secure-cluster.md#task-5-verify-a-platform-binary) |
| **Cluster hardening** | | |
| Use RBAC to minimize exposure | the API server's gates and `system:masters` in [module 3.15](3-istio/15-life-of-a-request.md#concept-inside-the-api-server); an agent that borrows cluster-admin in [module 5.3](5-ai/03-ai-agents.md#concept-whose-permissions-a-tool-uses) | [module 4.2, tasks 1, 5, 6 and 12](4-security/02-hardening-access-to-the-api.md#task-1-trim-an-over-broad-role) |
| Exercise caution with service accounts | service accounts as mesh identity in [module 3.2](3-istio/02-identity-and-mtls.md#concept-an-identity-per-service-account); a tool server's token in [module 5.3](5-ai/03-ai-agents.md#6-take-the-agents-write-access-away) | [module 4.2, tasks 2, 7 and 8](4-security/02-hardening-access-to-the-api.md#task-2-service-account-tokens) |
| Restrict access to the Kubernetes API | authentication, authorization and admission in [module 3.15](3-istio/15-life-of-a-request.md#concept-inside-the-api-server) | [module 4.2, task 3](4-security/02-hardening-access-to-the-api.md#task-3-restrict-anonymous-access-to-the-api); a broken control plane in [module 4.2, tasks 9 to 11](4-security/02-hardening-access-to-the-api.md#task-9-repair-the-api-server) |
| Upgrade Kubernetes to avoid vulnerabilities | why clusters fall behind, and a k3s upgrade in [module 2.9](2-observability/09-k3s-lifecycle.md#the-bigger-picture-why-clusters-fall-behind); drains in [module 2.8](2-observability/08-nodes-and-cleanup.md#concept-cordon-drain-delete) | [module 4.2, task 4](4-security/02-hardening-access-to-the-api.md#task-4-upgrade-the-cluster-with-kubeadm) |
| **System hardening** | | |
| Minimize host OS footprint | nothing | [module 4.3, tasks 1, 4 and 7](4-security/03-hardening-nodes.md#task-1-remove-a-service-nobody-needs) |
| Use least-privilege identity and access management | nothing on node users; the Node authorizer in [module 3.15](3-istio/15-life-of-a-request.md#concept-inside-the-api-server) | [module 4.3, tasks 2, 3, 5 and 6](4-security/03-hardening-nodes.md#task-2-a-user-with-too-much-power) |
| **Minimize microservice vulnerabilities** | | |
| Use appropriate Pod Security Standards | why sidecar mode needs more than `baseline`, in [module 3.9](3-istio/09-sidecar-mode.md#why-this-way-and-why-ambient-exists); policies that refuse workloads in [module 2.7](2-observability/07-kyverno-policy-as-code.md) | [module 4.4, tasks 1, 6, 7 and 8](4-security/04-hardening-workloads.md#task-1-enforce-the-restricted-standard) |
| Manage Kubernetes Secrets | etcd and the datastore in [module 2.9](2-observability/09-k3s-lifecycle.md#concept-where-k3s-keeps-its-state) | [module 4.4, tasks 2, 3 and 5](4-security/04-hardening-workloads.md#task-2-encrypt-secrets-at-rest) |
| Isolation techniques: multi-tenancy, sandboxed containers | namespaces as tenants with generated defaults in [module 2.7](2-observability/07-kyverno-policy-as-code.md); kernel space against user space in [module 3.21](3-istio/21-ebpf-and-cilium.md#concept-kernel-space-and-user-space) | [module 4.4, tasks 4 and 9](4-security/04-hardening-workloads.md#task-4-sandbox-a-pod-with-gvisor) |
| Pod-to-pod encryption with Cilium or Istio | Istio mTLS and HBONE in [module 3.2](3-istio/02-identity-and-mtls.md); Cilium's WireGuard and IPsec in [module 3.21](3-istio/21-ebpf-and-cilium.md#why-this-way-the-two-designs-share-one-idea) | [module 4.7, task 5](4-security/07-kernel-and-host-security.md#task-5-pod-to-pod-encryption-with-cilium), on one node: it proves the setting, not traffic between nodes |
| **Supply chain security** | | |
| Minimize base image footprint | nothing | [module 4.5, task 1](4-security/05-supply-chain-security.md#task-1-shrink-a-dockerfile) |
| Understand your supply chain: SBOM, CI/CD, artifact repositories | GitOps from a Git server in [module 2.6](2-observability/06-gitops-with-argocd.md) | [module 4.5, tasks 3 and 10](4-security/05-supply-chain-security.md#task-3-write-an-sbom) |
| Secure your supply chain: permitted registries, signatures | admission webhooks and Kyverno's `verifyImages` in [module 2.7](2-observability/07-kyverno-policy-as-code.md#concept-four-things-a-policy-does) | [module 4.5, tasks 5 to 8](4-security/05-supply-chain-security.md#task-5-allow-only-approved-registries); signatures in theory only |
| Static analysis of workloads and images | nothing | [module 4.5, tasks 2, 4 and 9](4-security/05-supply-chain-security.md#task-2-find-and-remove-vulnerable-images) |
| **Monitoring, logging and runtime security** | | |
| Behavioral analytics to detect malicious activity | eBPF, the technique Falco uses, in [module 3.21](3-istio/21-ebpf-and-cilium.md#concept-what-ebpf-is) | [module 4.6, tasks 2, 7 and 8](4-security/06-runtime-security-and-auditing.md#task-2-catch-a-shell-with-falco) |
| Minimize external access to the network | egress lock-down in [module 3.11](3-istio/11-egress.md#the-bigger-picture-why-egress-control-matters) | [module 4.1, tasks 1, 6 and 11](4-security/01-setting-up-a-secure-cluster.md#task-6-egress-to-dns-and-the-api-server-only) |
| Detect threats in infrastructure, apps, networks, data, users and workloads | metrics and alerts in [module 2.1](2-observability/01-prometheus-and-alerting.md) | [module 4.6, tasks 2, 6 and 9](4-security/06-runtime-security-and-auditing.md#task-9-which-pod-hunts-for-keys) |
| Kernel hardening tools: AppArmor, seccomp | nothing | [module 4.6, task 4](4-security/06-runtime-security-and-auditing.md#task-4-a-seccomp-profile) and [module 4.7, tasks 6 and 7](4-security/07-kernel-and-host-security.md#task-6-an-apparmor-profile); kernel modules in [module 4.7, task 4](4-security/07-kernel-and-host-security.md#task-4-keep-a-kernel-module-out) |
| Investigate phases of an attack and bad actors | incident hunting in [module 3.7](3-istio/07-incidents.md) | [module 4.6, tasks 6 and 10](4-security/06-runtime-security-and-auditing.md#task-6-investigate-an-attack) |
| Ensure immutability of containers at runtime | nothing | [module 4.6, tasks 3 and 13](4-security/06-runtime-security-and-auditing.md#task-3-make-a-container-immutable) |
| Use Kubernetes audit logs to monitor access | nothing | [module 4.6, tasks 1, 10 and 11](4-security/06-runtime-security-and-auditing.md#task-1-turn-on-audit-logging) |

Two things stay untested on this setup. Cilium's WireGuard runs on one node, so no packet crosses the tunnel, and cosign signatures need a registry you push to, so the modules cover them in theory only.
