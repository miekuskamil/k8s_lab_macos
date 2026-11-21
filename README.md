# k8s_lab_macos

A Kubernetes platform lab and a hands-on course that run on your own machine, with no cloud account. This page is the whole guide: read it top to bottom once, then come back to the tables while you study.

1. [What this is](#what-this-is)
2. [Quick start](#quick-start)
3. [Logins and addresses](#logins-and-addresses)
4. [Everyday commands](#everyday-commands)
5. [The course](#the-course)
6. [Practice cluster and timed tasks](#practice-cluster-and-timed-tasks)
7. [AI models](#ai-models)
8. [Where it runs](#where-it-runs)
9. [Troubleshooting](#troubleshooting)
10. [Remove everything](#remove-everything)
11. [Reference](#reference)

## What this is

The lab is a small online shop that runs in a Kubernetes cluster on your laptop, together with the tools a platform team uses every day: Istio, ArgoCD, cert-manager, Prometheus, Grafana, Jaeger, Loki, Kiali and Headlamp. The shop has a Node.js frontend, a Python backend in two versions, and Redis. You change the cluster on purpose, for example by sending 10% of the traffic to the new backend, and then watch the result in the web UIs.

The course builds on that lab in four levels, from your first container image to AI agents in a service mesh. Its application and security modules need a cluster built the way teams build one by hand, so a second, smaller cluster runs next to the lab for them. A few kernel tasks need a virtual machine with a kernel of its own.

![How the lab fits together: your terminal and browser, the toolbox, the k3d lab and the practice cluster in one Docker engine, Ollama on your machine, and the VM for module 44](docs/diagrams/chapters/lab-map.svg)

Five names come back on every page of the course:

| Name | What it is |
|---|---|
| The lab | The k3d cluster `k8s-lab`: one k3s node in Docker with the shop, Istio ambient mesh, ArgoCD and every UI. Modules 0 to 32 and 45 run here. |
| The toolbox | A container with kubectl, helm, k3d, kind and istioctl at the tested versions. Your machine needs only Docker and git. |
| The practice cluster | Two kubeadm nodes that kind runs as containers, for the timed tasks of modules 33 to 43 and the six practice exams. |
| The VM | `cks-lima`, a Lima VM with its own kernel, only for module 44 and a few tasks of practice exams 5 and 6. |
| Ollama | A program on your machine that runs the language model for the AI modules 17, 18, 19 and 27. |

The [glossary](platform-engineering/glossary.md) explains every other term the course uses, so keep it open in a tab.

## Quick start

Your machine needs Docker and git. On a Mac, Docker comes from [OrbStack](https://orbstack.dev) with 8 GiB of memory or more. Linux, Proxmox and Windows have their own notes under [Where it runs](#where-it-runs).

1. Clone the repository.

   ```bash
   git clone https://github.com/miekuskamil/k8s_lab_macos.git
   cd k8s_lab_macos
   ```

2. Open a shell in the toolbox. The first time, Docker builds the toolbox image, which takes about 2 minutes. The prompt then starts with `(lab)`, and `kubectl` (alias `k`), `helm`, `k3d`, `kind` and `istioctl` are ready.

   ```bash
   ./lab.sh shell
   ```

3. Build the lab from inside the toolbox. The first run downloads the images and takes about 10 minutes. The command waits until every health check passes, and running it again is safe.

   ```bash
   ./lab.sh up
   ```

4. Open the shop at http://localhost:8080 in your browser.

5. Open the other web UIs. The command keeps running and Ctrl-C closes the UIs, so start it in its own terminal and open a second `./lab.sh shell` for your work.

   ```bash
   ./lab.sh ui
   ```

6. Check the lab. `./lab.sh status` shows the nodes, the ArgoCD applications and any pod that is not running, and `./lab.sh test` sends 100 requests to the shop and prints which backend version answered.

   ```bash
   ./lab.sh status
   ./lab.sh test
   ```

The clusters run as containers on your own Docker engine, not inside the toolbox, so they keep running after you leave the shell. Every `./lab.sh` command works the same inside and outside the toolbox. On a machine without kubectl, helm or k3d, a command run outside the toolbox goes through it by itself.

## Logins and addresses

The shop answers as soon as `./lab.sh up` finishes. Every other UI needs `./lab.sh ui` running.

| UI | Address | User | Password |
|---|---|---|---|
| The shop | http://localhost:8080 | none | none |
| ArgoCD | http://localhost:8081 | `admin` | `k8s-lab-admin` |
| Grafana, with Prometheus, Loki and Jaeger as data sources | http://localhost:3000 | `admin` | `k8s-lab-admin` |
| Prometheus | http://localhost:9090 | none | none |
| Alertmanager | http://localhost:9093 | none | none |
| Jaeger | http://localhost:16686 | none | none |
| Kiali, the Istio console | http://localhost:20001 | none | none |
| Headlamp, a web UI for the whole cluster | http://localhost:4466 | none | none |

Module 11 adds HTTPS for the shop on https://localhost:8443. Redis has no local port, and its password is `k8s-lab-redis`. On the practice cluster, ingress-nginx answers on http://localhost:30080 and https://localhost:30443.

Every secret is a fixed default stored in Git, so every copy of the lab behaves the same. That choice stays safe only because nothing listens outside your machine. Headlamp has no login and acts as `cluster-admin`, so never publish its port on a network.

### Where the passwords live

| Secret | Value | Defined in | To change it |
|---|---|---|---|
| Grafana `admin` | `k8s-lab-admin` | `manifests/base/03-lab-credentials.yaml`, Secret `observability/grafana-admin` | Edit it there and in `helm/kiali-values.yaml` under `external_services.grafana.auth.password`. |
| ArgoCD `admin` | `k8s-lab-admin` | `helm/argocd-values.yaml`, as a bcrypt hash | Make a new hash with the command in that file's comment, and update `argocdServerAdminPasswordMtime`. |
| Redis | `k8s-lab-redis` | `manifests/base/03-lab-credentials.yaml`, Secret `shop/redis-auth` | Edit it there, then restart Redis and the backends. |
| Kiali token signing key | `k8s-lab-kiali-signing-key-32chrs` | `helm/kiali-values.yaml`, `login_token.signing_key` | Use 16, 24 or 32 characters, and keep the value fixed, because Kiali restarts on every sync otherwise ([problem 16](docs/troubleshooting.md#16-kiali-restarts-every-few-minutes)). |
| Gitea `lab`, module 22 only | `lab-gitops-pass` | the `gitea admin user create` command in [module 22](platform-engineering/2-intermediate/22-gitops-with-argocd.md) | Use another password there and in your `git push` URL. |

## Everyday commands

Run every command from the repository folder. `./lab.sh help` prints the same list.

| Command | What it does |
|---|---|
| **The lab** | |
| `./lab.sh up` | Builds the images, creates the cluster, installs Istio and ArgoCD, and waits for the health checks. Use it the first time, or to repair a broken lab. |
| `./lab.sh start` | Starts the cluster again after a reboot, sleep or `./lab.sh stop`, and recreates pods whose mesh networking broke. |
| `./lab.sh stop` | Stops the cluster and keeps its data, to free memory. |
| `./lab.sh status` | Shows the nodes, the ArgoCD applications and every pod that is not running. |
| `./lab.sh ui` | Opens the web UIs on localhost until you press Ctrl-C. |
| `./lab.sh test` | Sends 100 requests to the shop and prints the status codes, the versions and the latency. |
| `./lab.sh test 4 5` | Runs the course checks for modules 4 and 5. `./lab.sh test all` runs every module that is safe to repeat, in about 50 minutes. |
| `./lab.sh reset` | Removes the course exercises and restores the Git baseline. `--all` also removes the course namespaces. |
| `./lab.sh down` | Deletes the cluster after it asks. `--yes` skips the question. |
| **The practice cluster** | |
| `./lab.sh practice up` | Builds the two-node practice cluster, about 3 minutes the first time. |
| `./lab.sh practice shell` | Opens a root shell on the control plane. Add `worker` for the worker node. |
| `./lab.sh practice reset` | Builds the practice cluster again from scratch. |
| `./lab.sh practice down` | Deletes the practice cluster after it asks. |
| **Timed tasks and exams** | |
| `./lab.sh task list` | Lists every timed task id, such as `38.3`. |
| `./lab.sh task setup 38.3` | Prepares a task. `check` scores it and `solve` applies the reference solution. |
| `./lab.sh exam setup 4` | Prepares practice exam 4 and starts its 2-hour clock. `score` and `solve` follow the same pattern. |
| **AI models** | |
| `./lab.sh ai` | Copies the AI settings from `lab.env` into the cluster. |
| `./lab.sh ollama` | Runs Ollama in a container and pulls the two models the course uses, for a machine without Ollama. |
| **The toolbox** | |
| `./lab.sh shell` | Starts the toolbox and opens a shell in it. A second call in another terminal joins the same toolbox. |
| `./lab.sh toolbox build` | Builds the toolbox image again after a change in `toolbox/`. |
| `./lab.sh toolbox stop` | Stops and removes the toolbox container. Your kubeconfig stays. |

Each command runs a script in [scripts/](scripts) or [platform-engineering/](platform-engineering), and the course text sometimes calls those scripts directly.

### Your first experiment

The baseline sends every request to backend v1. This experiment sends 10% to v2, measures the split, and then puts the baseline back. Give the mesh a few seconds after the `kubectl apply` before the second test.

```bash
./lab.sh test
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml
./lab.sh test
./lab.sh reset
```

The first test shows only v1, and the second shows about 90 answers from v1 and 10 from v2.

### Git and ArgoCD

ArgoCD deploys the lab from the `main` branch on GitHub, not from your working copy, so a change of your own reaches the cluster only after you push it. The course changes Istio resources by hand with `kubectl apply`. The `istio-config` application has self-heal off, so your change stays, ArgoCD shows `OutOfSync`, and `./lab.sh reset` puts the Git baseline back. When a new commit lands on `main`, ArgoCD syncs once and removes the exercise you are working on, so apply that step's manifests again.

## The course

[Start here: Istio in one picture](platform-engineering/start-here.md) takes 15 minutes, needs no cluster, and shows every Istio resource the mesh modules use on one diagram. Read it before module 0.

The course has four levels and one extra domain. Each level mixes topics, so the difficulty climbs while you work on applications, the mesh, platform tools and security side by side. Module numbers never change, so `./lab.sh test 4` always checks module 4. The last column names what a module runs on: *lab* is the k3d lab from the quick start, *practice* is the practice cluster with its timed tasks, *VM* is the Lima VM `cks-lima`, and *AI* means the module also calls a language model, as [AI models](#ai-models) explains.

### 1. Foundations

How an application gets built, shipped, configured, reached and debugged, and how the mesh adds identity, policy and routing on top.

| Module | You learn | Runs on |
|---|---|---|
| [33. Building and running applications](platform-engineering/1-foundations/33-building-and-running-applications.md) | Images, Jobs and CronJobs, init and sidecar containers, volumes | practice |
| [34. Deploying and updating applications](platform-engineering/1-foundations/34-deploying-and-updating-applications.md) | Rolling updates and rollbacks, blue-green and canary, Helm, Kustomize | practice |
| [35. Observing and debugging applications](platform-engineering/1-foundations/35-observing-and-debugging-applications.md) | Probes, logs, `kubectl top`, debugging containers without a shell, API deprecations | practice |
| [36. Configuration and secrets](platform-engineering/1-foundations/36-configuration-and-secrets.md) | ConfigMaps and Secrets, requests, limits and quotas, ServiceAccounts and RBAC, security contexts, CRDs | practice |
| [37. Services and networking](platform-engineering/1-foundations/37-services-and-networking.md) | Services, NodePorts, Ingress, NetworkPolicies | practice |
| [0. Setup](platform-engineering/1-foundations/00-setup.md) | Check the lab and the Istio command line | lab |
| [1. What a mesh adds](platform-engineering/1-foundations/01-what-a-mesh-adds.md) | What Kubernetes networking leaves out, and Istio's two data plane designs | lab |
| [2. Identity and mTLS](platform-engineering/1-foundations/02-identity-and-mtls.md) | Where workload identity comes from and how the tunnel works | lab |
| [3. Authorization](platform-engineering/1-foundations/03-authorization.md) | Policy at layer 4 and layer 7, and why you need both | lab |
| [4. Traffic routing](platform-engineering/1-foundations/04-traffic-routing.md) | Weighted and content-based routing with the Gateway API | lab |
| [5. Resilience](platform-engineering/1-foundations/05-resilience.md) | Timeouts, faults, circuit breaking, rate limiting | lab |
| [6. Observability](platform-engineering/1-foundations/06-observability.md) | What the mesh measures by itself, and how to follow one request | lab |
| [8. Incidents](platform-engineering/1-foundations/08-incidents.md) | Find and fix four broken setups without being told the cause | lab |
| [9. Command reference](platform-engineering/1-foundations/09-command-reference.md) | Troubleshooting commands for the cluster and for Istio, by layer | lab |
| [29. The life of a request](platform-engineering/1-foundations/29-life-of-a-request.md) | From kubectl to the API server, scheduler, kubelet and CNI, then one request with and without the mesh, hop by hop | lab |
| [Practice exams 1](platform-engineering/1-foundations/practice-exam-1.md), [2](platform-engineering/1-foundations/practice-exam-2.md) and [3](platform-engineering/1-foundations/practice-exam-3.md) | Modules 33 to 37 against a 2-hour clock, each harder than the one before | practice |

### 2. Intermediate

More of Istio, the everyday tools of a platform team, and the first steps in securing a cluster.

| Module | You learn | Runs on |
|---|---|---|
| [7. Sidecar mode](platform-engineering/2-intermediate/07-sidecar-mode.md) | The classic sidecar design, side by side with ambient | lab |
| [11. TLS at the edge](platform-engineering/2-intermediate/11-edge-tls.md) | HTTPS on the ingress gateway, cert-manager, redirects, renewal without downtime | lab |
| [12. Egress](platform-engineering/2-intermediate/12-egress.md) | ServiceEntry, TLS origination, rules on outbound calls, locking a pod in | lab |
| [13. JWT](platform-engineering/2-intermediate/13-jwt.md) | End-user identity, rules on token claims, 401 against 403 | lab |
| [15. Outlier detection and retries](platform-engineering/2-intermediate/15-outlier-detection-and-retries.md) | One bad pod out of three: retries hide it, outlier detection removes it | lab |
| [16. The Istio API](platform-engineering/2-intermediate/16-istio-api.md) | The same ingress and canary with Istio's Gateway, VirtualService and subsets | lab |
| [20. Nodes, drains and cleanup](platform-engineering/2-intermediate/20-nodes-and-cleanup.md) | A second node, drains under traffic, PodDisruptionBudgets, cleaning up what piles up | lab |
| [22. GitOps with ArgoCD](platform-engineering/2-intermediate/22-gitops-with-argocd.md) | Your own Git server, drift and self-heal, rollbacks, sync waves, AppProjects, ApplicationSets | lab |
| [23. Prometheus and alerting](platform-engineering/2-intermediate/23-prometheus-and-alerting.md) | PromQL, recording rules, an SLO with a burn-rate alert, Alertmanager routing | lab |
| [24. Grafana as code](platform-engineering/2-intermediate/24-grafana-as-code.md) | Dashboards from ConfigMaps, variables, Grafana-managed alerts, trace-to-logs links | lab |
| [26. Kyverno, policy as code](platform-engineering/2-intermediate/26-kyverno-policy-as-code.md) | Audit then Enforce, exceptions, mutation, generated defaults, PolicyReports | lab |
| [38. Setting up a secure cluster](platform-engineering/2-intermediate/38-setting-up-a-secure-cluster.md) | Default-deny NetworkPolicies, the metadata endpoint, kube-bench, Ingress with TLS, binary checksums | practice |
| [39. Hardening access to the API](platform-engineering/2-intermediate/39-hardening-access-to-the-api.md) | RBAC, service account tokens, anonymous access, a kubeadm upgrade, repairing the API server and etcd | practice |

### 3. Advanced

Hardening nodes, workloads and the supply chain, catching attacks at runtime, and the internals of the mesh and the platform tools.

| Module | You learn | Runs on |
|---|---|---|
| [40. Hardening nodes](platform-engineering/3-advanced/40-hardening-nodes.md) | Unneeded services, users with too much power, NodeRestriction, sshd, credentials on disk | practice |
| [41. Hardening workloads](platform-engineering/3-advanced/41-hardening-workloads.md) | Pod Security Standards, Secrets encrypted at rest, gVisor sandboxes | practice |
| [42. Supply chain security](platform-engineering/3-advanced/42-supply-chain-security.md) | Small images, vulnerability scans, SBOMs, static analysis, allowed registries | practice |
| [43. Runtime security and auditing](platform-engineering/3-advanced/43-runtime-security-and-auditing.md) | Audit logs, Falco rules, immutable containers, seccomp, investigating an attack | practice |
| [10. eBPF and Cilium](platform-engineering/3-advanced/10-ebpf-and-cilium.md) | The other sidecarless design, compared with ambient, in theory | lab |
| [14. Upgrading Istio](platform-engineering/3-advanced/14-upgrading-istio.md) | A canary upgrade with revisions, tags and rollback. One way: rebuild the lab afterwards | lab |
| [21. k3s certificates, backups, upgrades](platform-engineering/3-advanced/21-k3s-lifecycle.md) | Certificate rotation, a datastore backup and restore, a k3s upgrade. One way: rebuild afterwards | lab |
| [25. OpenTelemetry Collector and Tempo](platform-engineering/3-advanced/25-opentelemetry-and-tempo.md) | A Collector between apps and back ends, span metrics, Tempo and TraceQL | lab |
| [28. Continuous profiling with Pyroscope](platform-engineering/3-advanced/28-continuous-profiling.md) | Flame graphs, self against total time, memory allocations, the cost of profiling | lab |
| [30. Sidecar mode in depth](platform-engineering/3-advanced/30-sidecar-in-depth.md) | Injection webhooks, iptables capture, the Sidecar resource, sidecar against ambient | lab |
| [31. Debugging Envoy with istioctl](platform-engineering/3-advanced/31-debugging-envoy.md) | Listeners, routes, clusters and endpoints, response flags, four break-and-fix exercises | lab |
| [32. Installing Istio with istioctl](platform-engineering/3-advanced/32-installing-istio.md) | Install profiles, IstioOperator files, switching to ambient, on a throwaway cluster | its own k3d cluster |
| [45. The life of an outbound request](platform-engineering/3-advanced/45-life-of-an-outbound-request.md) | One call from a pod to the internet through every layer of NAT, then controlled egress | lab |
| [Practice exams 4](platform-engineering/3-advanced/practice-exam-4.md), [5](platform-engineering/3-advanced/practice-exam-5.md) and [6](platform-engineering/3-advanced/practice-exam-6.md) | Modules 38 to 43 against a 2-hour clock, each harder than the one before | practice, and the VM for exams 5 and 6 |

### 4. AI on Kubernetes

AI workloads in the mesh. Modules 17 to 19 build on modules 3 to 6 and 12, and module 27 needs only module 0.

| Module | You learn | Runs on |
|---|---|---|
| [17. An LLM as a mesh service](platform-engineering/4-ai/17-llm-in-the-mesh.md) | A shop assistant that calls a model, a locked-down model API, token metrics, GenAI traces | lab, AI |
| [18. Serving models in the cluster](platform-engineering/4-ai/18-serving-models.md) | Two small models on llama.cpp, readiness, why LLM load balancing is hard, the Inference Extension | lab, downloads about 900 MB |
| [19. AI agents and their tools](platform-engineering/4-ai/19-ai-agents.md) | kagent, MCP and A2A, mesh policy and RBAC around agents | lab, AI |
| [27. RAG on Kubernetes](platform-engineering/4-ai/27-rag-on-kubernetes.md) | Qdrant, embeddings, ingesting the course, retrieval misses, top-k against tokens | lab, AI |

### 5. Kernel and host security on a VM

The seven tasks that change the kernel itself. Take each task after the module it comes from: the Cilium tasks after module 38, the kernel module task after 40, WireGuard after 41, and AppArmor after 43.

| Module | You learn | Runs on |
|---|---|---|
| [44. Kernel and host security](platform-engineering/kernel-and-host/44-kernel-and-host-security.md) | Cilium policies at layers 3, 4 and 7, keeping kernel modules out, WireGuard between pods, AppArmor | VM |

### How to study

Every lab module follows the same pattern. It explains one problem and the design that solves it, then gives you commands to run, each followed by the output you should see, then questions you answer in the UIs, and it ends with a clean-up. Run `./lab.sh reset` after each exercise. Your pod names, IP addresses and timings differ from the printed output, while names, namespaces and ports stay the same.

The practice cluster modules open with theory and diagrams, then hand you timed tasks of 3 to 10 minutes each. You prepare a task, solve it against the clock, and let the script check your work, as [Practice cluster and timed tasks](#practice-cluster-and-timed-tasks) shows. Levels 1 and 3 each end with three practice exams of 2 hours, which score your cluster out of 100 points with partial credit.

![Routes through the lab modules: module 0, then the Istio, operations, platform and AI routes](docs/diagrams/chapters/readme-course-routes.svg)

The routes in the picture run on the lab. The application and security modules run on the practice cluster, so you take them alongside any lab route. A good order through the whole course:

1. [Start here](platform-engineering/start-here.md), then module 0.
2. Modules 33 to 37, then practice exams 1 to 3.
3. Modules 1 to 7, then 29 to tie them together, then 8 to test yourself.
4. Modules 11, 12, 13, 15 and 16, then 30, 31 and 45.
5. Modules 38 and 39, then 40 to 43 with module 44 alongside, then practice exams 4 to 6.
6. Modules 17 to 19, the AI route.
7. Modules 22 to 28, the platform tools. Module 27 is AI and needs a model.
8. Module 20.
9. Module 14, then rebuild the lab with `./lab.sh down --yes` and `./lab.sh up`.
10. Module 32, on its own throwaway cluster.
11. Module 21, then rebuild the lab again.

Modules 14 and 21 come last, because they upgrade Istio and k3s in place and only a rebuild brings the lab back. Keep module 9 open as a reference, and read module 10 any time after module 7.

### Check a module

Every lab module has automatic checks that apply its manifests, test the results and restore the baseline. Run them when a module behaves differently from its text.

```bash
./lab.sh test 4
./lab.sh test all
```

`./lab.sh test all` covers every lab module that is safe to repeat. Two groups stay out of it, so run them by number: modules 14, 21 and 32, which upgrade the lab or build a cluster of their own, and the AI modules 17, 18, 19 and 27, which need a language model or download one. Modules 9 and 10 have no checks, because one is a reference and the other is theory.

If you prepare for the CKAD or CKS exam, [Timed tasks and exam preparation](platform-engineering/timed-tasks.md#which-modules-cover-each-exam-domain) maps each exam domain to its modules.

## Practice cluster and timed tasks

The practice cluster is two kubeadm nodes, `practice-control-plane` and `practice-worker`, that kind runs as containers in the same Docker engine as the lab. kubeadm builds it the way teams build a cluster by hand, with the control plane as static pods, so the security tasks have real manifests, a kubelet and a journal to work with. It runs Kubernetes 1.37.1 and fits next to the running lab.

1. Build the practice cluster. The first run builds its node image and takes about 3 minutes.

   ```bash
   ./lab.sh practice up
   ```

2. For the application modules 33 to 37, add metrics-server. The command checks the extra tools and is safe to run again.

   ```bash
   ./platform-engineering/practice/app-extras/extras.sh
   ```

3. Prepare a task on your machine, in the repository folder. A task id joins the module and the task number, so task 3 of module 38 is `38.3`.

   ```bash
   ./lab.sh task setup 38.3
   ```

4. Read the brief in the module, start a timer, and solve the task in a root shell on the node the brief names.

   ```bash
   ./lab.sh practice shell
   ```

5. Back on your machine, check your work. The script prints PASS or FAIL for each thing the task asks.

   ```bash
   ./lab.sh task check 38.3
   ```

6. When the time runs out, apply the reference solution and read it in the module.

   ```bash
   ./lab.sh task solve 38.3
   ```

Every setup starts its task from scratch, so you repeat a task by running its setup again. Between modules, reset the cluster:

| After | Run |
|---|---|
| An application module, 33 to 37 | `./platform-engineering/practice/app-extras/reset.sh` |
| A security module, 38 to 43 | `./lab.sh practice reset`, then `extras.sh` again before the next application module |
| A task of module 44 | `./platform-engineering/practice/cluster/lima.sh reset` |

The practice exams work the same way for a whole exam. Each one gives you 2 hours for 16 or 17 tasks worth 100 points, and `score` prints the minutes since `setup` next to your points.

```bash
./lab.sh exam setup 4
./lab.sh exam score 4
./lab.sh exam solve 4
```

Aim for 80 points or more inside the time before you move on. [Timed tasks and exam preparation](platform-engineering/timed-tasks.md) has the terminal habits that save the most time, and [the practice cluster in depth](platform-engineering/practice-cluster.md) explains the nodes, the shared kernel, and how to run the same cluster on OrbStack machines or your own VMs.

## AI models

The AI modules use Ollama on your machine with the model `qwen2.5:3b` by default, for free and offline. Install it from [ollama.com](https://ollama.com), then pull the chat model and the embedding model that module 27 uses for search:

```bash
ollama pull qwen2.5:3b
ollama pull nomic-embed-text
```

A machine without Ollama runs it in a container instead. It runs on the CPU, so answers take much longer than from Ollama installed on a Mac.

```bash
./lab.sh ollama
```

To use another model or a hosted provider, write your settings in `lab.env`, which Git ignores, so your key stays on your machine:

1. Copy the example file.

   ```bash
   cp lab.env.example lab.env
   ```

2. Set the provider, the address, the model and the key. `LLM_PROVIDER` takes three values: `ollama` for Ollama's own API, `openai` for any server that speaks the OpenAI API (Ollama's `/v1`, vLLM, LM Studio, OpenAI, Gemini, Groq, OpenRouter), and `anthropic` for Claude. Pods reach your machine as `host.docker.internal`, never as `localhost`. For example, Ollama through its OpenAI-compatible endpoint:

   ```bash
   LLM_PROVIDER=openai
   LLM_URL=http://host.docker.internal:11434/v1
   LLM_MODEL=qwen2.5:3b
   ```

   A hosted provider adds its key, for example Claude:

   ```bash
   LLM_PROVIDER=anthropic
   LLM_MODEL=claude-opus-5-5
   LLM_API_KEY=sk-ant-...
   ```

3. Store the settings in the cluster. `./lab.sh up` and `./lab.sh start` do this too.

   ```bash
   ./lab.sh ai
   ```

4. Once module 17 has deployed the shop assistant, check which model it uses.

   ```bash
   curl -s localhost:8080/api/model
   ```

[Choosing the model](docs/ai-models.md) has the details: embeddings for module 27, kagent's own settings in module 19, and the mesh setup that sends module 17's calls to Claude over HTTPS.

## Where it runs

| Machine | Status |
|---|---|
| macOS with OrbStack | The main platform. Every module and check ran here. |
| Linux with Docker Engine | Tested on Ubuntu 24.04 with Docker Engine. |
| Proxmox | The lab on one Ubuntu VM, and the practice cluster on two VMs. |
| Windows with WSL2 | Untested. |

### macOS with OrbStack

Give OrbStack 8 GiB of memory or more, and keep OrbStack's own Kubernetes switched off, because Istio ambient needs the k3d cluster ([why](docs/build-from-scratch.md#step-1-the-cluster)). The lab installs k3s 1.31.5 and Istio 1.24.2. To work without the toolbox, install the tools with Homebrew:

```bash
brew install kubectl helm k3d istioctl
```

### Linux

Give the machine at least 12 GB of memory, because the lab needs about 8 GB and a language model adds about 2.5 GB while it answers.

1. Install Docker Engine and git, and add your user to the `docker` group. Log out and back in for the group to apply.

   ```bash
   sudo apt-get update
   sudo apt-get install -y docker.io git
   sudo usermod -aG docker $USER
   ```

2. Raise the inotify limits. The lab's many pods pass the kernel's default, and pods then fail with "too many open files". The file below keeps the setting after a reboot.

   ```bash
   echo -e "fs.inotify.max_user_instances=512\nfs.inotify.max_user_watches=524288" | sudo tee /etc/sysctl.d/99-k8s-lab.conf
   sudo sysctl --system
   ```

3. Follow the [quick start](#quick-start). On a remote machine, forward the ports over SSH to open the UIs, for example `ssh -L 8080:localhost:8080 <machine>`, with one `-L` for each port in [Logins and addresses](#logins-and-addresses).

<details>
<summary>Install the tools without the toolbox</summary>

`dpkg --print-architecture` prints `amd64` on Intel and AMD machines and `arm64` on ARM machines.

```bash
ARCH=$(dpkg --print-architecture)
sudo apt-get install -y curl python3

curl -fsSLO "https://dl.k8s.io/release/v1.31.5/bin/linux/$ARCH/kubectl"
sudo install kubectl /usr/local/bin/ && rm kubectl

curl -fsSL "https://get.helm.sh/helm-v4.3.1-linux-$ARCH.tar.gz" | tar xz
sudo install "linux-$ARCH/helm" /usr/local/bin/ && rm -r "linux-$ARCH"

curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | TAG=v5.9.0 bash

curl -fsSL "https://github.com/istio/istio/releases/download/1.32.0/istioctl-1.32.0-linux-$ARCH.tar.gz" | tar xz
sudo install istioctl /usr/local/bin/ && rm istioctl
```

</details>

#### Ollama on Linux

On a Mac, OrbStack answers the name `host.docker.internal` for every pod. Plain Docker Engine does not, so the AI modules need two extra steps after `./lab.sh up`.

1. Install Ollama and make it listen on every network interface. Pods reach your machine through the gateway of the k3d network, not through its loopback address.

   ```bash
   curl -fsSL https://ollama.com/install.sh | sh
   sudo mkdir -p /etc/systemd/system/ollama.service.d
   printf '[Service]\nEnvironment="OLLAMA_HOST=0.0.0.0"\n' | sudo tee /etc/systemd/system/ollama.service.d/listen.conf
   sudo systemctl daemon-reload
   sudo systemctl restart ollama
   ollama pull qwen2.5:3b
   ollama pull nomic-embed-text
   ```

2. Tell the cluster's DNS server that `host.docker.internal` means that gateway, then restart it.

   ```bash
   GW=$(docker network inspect k3d-k8s-lab -f '{{(index .IPAM.Config 0).Gateway}}')
   kubectl -n kube-system create configmap coredns-custom \
     --from-literal=hostdocker.server="host.docker.internal:53 {
       hosts {
         $GW host.docker.internal
       }
     }" --dry-run=client -o yaml | kubectl apply -f -
   kubectl -n kube-system rollout restart deploy/coredns
   ```

3. Check from inside the cluster. The command prints Ollama's list of models.

   ```bash
   kubectl run ollama-check --rm -i --restart=Never --image=curlimages/curl:8.11.1 -- curl -s http://host.docker.internal:11434/api/tags
   ```

Ollama now answers every machine on your network, so block port 11434 with a firewall, or stop it after the AI modules with `sudo systemctl stop ollama`. With `./lab.sh ollama` instead, set `LAB_OLLAMA_BIND=0.0.0.0` in `lab.env`.

### Proxmox

Two scripts in [proxmox/](proxmox) build VMs from the Ubuntu cloud image on a Proxmox host. One VM, `pe-lab`, holds the whole lab, and `./proxmox/pe-lab.sh install` sets it up over SSH from your laptop. Two more VMs, `cks-cp` and `cks-w1`, hold the practice cluster. [The lab on Proxmox](proxmox/README.md) has the steps, the addresses and the memory each set needs.

### Windows with WSL2

Nobody has tested the lab on Windows yet. The likely route is Docker Desktop with its WSL2 back end, or Docker Engine inside an Ubuntu distribution in WSL2, with the repository cloned inside the Linux file system and the [Linux](#linux) steps from there. Treat it as a starting point and check each step.

### The VM for module 44

The practice cluster's nodes share one kernel with every container on your machine. That kernel has no AppArmor and no WireGuard module, and Cilium would rewire every container's network if it loaded there. So the seven kernel tasks of module 44, and two tasks each in practice exams 5 and 6, run on a VM with a kernel of its own.

On a Mac, [Lima](https://lima-vm.io) runs that VM. `cks-lima` runs Ubuntu 24.04 with AppArmor and a one-node kubeadm cluster with Cilium as its network plugin, in 2 CPUs and 3 GiB of memory that come from the Mac directly, not from OrbStack.

1. Install Lima once.

   ```bash
   brew install lima
   ```

2. Build the VM and its cluster, about 2 minutes. Running it again is safe.

   ```bash
   ./platform-engineering/practice/cluster/lima.sh create
   ```

3. Open a root shell on the node. Module 44 marks each task that runs here with **Host:** `cks-lima`.

   ```bash
   ./platform-engineering/practice/cluster/lima.sh shell
   ```

| Command | What it does |
|---|---|
| `./platform-engineering/practice/cluster/lima.sh stop` | Frees the memory. `start` brings the VM back. |
| `./platform-engineering/practice/cluster/lima.sh reset` | Builds a fresh cluster and keeps the VM. |
| `./platform-engineering/practice/cluster/lima.sh destroy` | Deletes the VM. |

On Proxmox, `cks-w1` has a kernel of its own, so the AppArmor and kernel module tasks run there, while the Cilium tasks still need `cks-lima`. [Where each task runs](platform-engineering/practice-cluster.md#where-each-task-runs) lists the host of every task.

## Troubleshooting

Start with `./lab.sh status`. It shows the sync and health of every ArgoCD application and every pod that is not running.

| Problem | Fix |
|---|---|
| Everything broke after a reboot or sleep, CoreDNS shows `Unknown`, or ztunnel is not ready. | Run `./lab.sh start`. |
| `namespaces "argocd" not found`, because OrbStack switched kubectl to its own cluster. | Run `kubectl config use-context k3d-k8s-lab`. |
| `./lab.sh shell` says a UI port is already allocated. | A `./lab.sh ui` runs outside the toolbox. Stop it with Ctrl-C and try again. |
| http://localhost:8080 does not answer. | Find what holds the port with `lsof -i :8080`, then check the gateway with `kubectl -n shop-ingress get pods`. |
| An application shows `OutOfSync` after an exercise. | Run `./lab.sh reset`. |
| Your exercise disappeared in the middle of a module. | A new commit on `main` made ArgoCD sync. Apply the step's manifests again. |
| A pod never appears, because a quota or LimitRange refused it. | Run `kubectl get events -A --field-selector reason=FailedCreate`. |
| Pods fail with "too many open files" on Linux. | Raise the inotify limits as [Linux](#linux) shows. |
| The AI modules get no answer. | Check that Ollama runs and has the models with `ollama list`. After module 17, `curl -s localhost:8080/api/model` shows the model the assistant calls. |

To see the most recent warnings in the cluster:

```bash
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20
```

[The troubleshooting log](docs/troubleshooting.md) records every problem found so far, each with its symptom, diagnosis and fix.

## Remove everything

Delete the lab and the practice cluster. Each command asks first.

```bash
./lab.sh down
./lab.sh practice down
```

The built images stay in your local Docker store, so a new `./lab.sh up` takes about 2 minutes. To remove the Lima VM and the toolbox container as well:

```bash
./platform-engineering/practice/cluster/lima.sh destroy
./lab.sh toolbox stop
```

## Reference

| Page | What it holds |
|---|---|
| [Glossary](platform-engineering/glossary.md) | Every term in the course, explained in plain words |
| [Start here: Istio in one picture](platform-engineering/start-here.md) | Every Istio resource on one diagram, before module 0 |
| [Architecture](docs/architecture.md) | How a request travels, where mTLS applies, and how Git changes reach the cluster |
| [How the lab was built](docs/build-from-scratch.md) | The lab rebuilt step by step, with the reason behind each choice |
| [The life of a request](docs/life-of-a-request.md) | One request through every layer, from the API server to the packets, with real output |
| [Lab tour](docs/lab-guide.md) | Three traffic experiments, GitOps by hand, recipes, mTLS debugging and notes for production |
| [Troubleshooting log](docs/troubleshooting.md) | Every problem found so far, with symptom, diagnosis and fix |
| [Choosing the model](docs/ai-models.md) | Every AI setting, other models, and Claude through the Anthropic API |
| [The practice cluster in depth](platform-engineering/practice-cluster.md) | The kind nodes, the shared kernel, and the same cluster on OrbStack machines or your own VMs |
| [Timed tasks and exam preparation](platform-engineering/timed-tasks.md) | Terminal habits, the CKAD and CKS domains by module, and where the lab modules explain each topic |
| [The lab on Proxmox](proxmox/README.md) | VMs for the lab and the practice cluster on a Proxmox host |
| [Diagrams](docs/diagrams/) | Every diagram, drawn from Python with `bbg.py`, as SVG and Excalidraw files |
