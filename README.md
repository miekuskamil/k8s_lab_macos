# k8s_lab_macos

A small shop runs on your laptop inside a k3d cluster, together with the tools a platform team uses: Istio ambient mesh, ArgoCD, cert-manager, Prometheus, Grafana, Jaeger, Loki, Kiali and Headlamp. The shop is a Node.js frontend, a Python FastAPI backend in two versions, and Redis. You break it on purpose, for example by sending 10% of traffic to the new version, and watch the result in the UIs. A [course](platform-engineering/README.md) in four levels builds on it, and you need no cloud account. [This diagram](docs/diagrams/chapters/architecture-request-path.svg) shows how a request travels through the lab.

## What you need

| | macOS | Linux |
|---|---|---|
| Container engine | [OrbStack](https://orbstack.dev) with 8 GiB of RAM or more | Docker Engine, your user in the `docker` group |
| Tools | git; the toolbox brings the rest (or `brew install kubectl helm k3d istioctl` to work without it) | git; the toolbox brings the rest (or kubectl, helm, k3d, istioctl and curl 7.84 or newer) |
| Kernel setting | none | `sudo sysctl -w fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288` |

The lab installs k3s 1.31.5, Istio 1.24.2, Gateway API 1.2.1 and the ArgoCD Helm chart 7.7.11. OrbStack's own Kubernetes stays switched off, because Istio ambient needs the k3d cluster ([why](docs/build-from-scratch.md#step-1-the-cluster)).

## Quick start

Your machine needs Docker (OrbStack on macOS) and git, nothing else. Every other tool runs in the toolbox, a container that `./lab.sh shell` builds and opens for you.

1. Clone the repository.
   ```bash
   git clone https://github.com/miekuskamil/k8s_lab_macos.git
   cd k8s_lab_macos
   ```

2. Open a shell in the toolbox. The first time, this builds the toolbox image in about 2 minutes. The prompt then starts with `(lab)`, the repository is the current folder, and `kubectl` (alias `k`), `helm`, `k3d`, `kind` and `istioctl` are ready at the versions the course was tested with.
   ```bash
   ./lab.sh shell
   ```

3. Build the lab from inside the toolbox. The first run takes about 10 minutes, mostly image downloads, and a rebuild with cached images takes about 2. The command waits until every health check passes, and it is safe to run again.
   ```bash
   ./lab.sh up
   ```

4. Open the shop at http://localhost:8080 in your browser.

5. Open the other UIs and leave the command running. A second `./lab.sh shell` in another terminal joins the same toolbox, so you keep working there. Ctrl-C closes the UIs.
   ```bash
   ./lab.sh ui
   ```

Every `./lab.sh` command works the same inside the toolbox and outside it. On a machine without kubectl, helm or k3d, `./lab.sh up` and the other commands go through the toolbox by themselves. The toolbox runs the clusters as containers on your own Docker engine, so they keep running after you leave the shell.

ArgoCD deploys from the `main` branch on GitHub, not from your working copy, so push a change before you expect the cluster to show it.

The AI modules use Ollama on your machine with `qwen2.5:3b` by default. To use another model, Ollama's OpenAI-compatible endpoint, or a hosted provider, copy `lab.env.example` to `lab.env`, set `LLM_PROVIDER`, `LLM_URL`, `LLM_MODEL` and `LLM_API_KEY` there, and run `./lab.sh ai`. Git ignores `lab.env`, so your key stays on your machine. Without Ollama, `./lab.sh ollama` runs it in a container and pulls the two models the course uses. [Choosing the model](docs/ai-models.md) has the details.

## Everyday commands

Run them from the repository root. `./lab.sh help` prints the same list.

| Command | What it does | When to use it |
|---|---|---|
| `./lab.sh up` | Builds images, creates the cluster, installs Istio and ArgoCD, waits for health checks | First run, or to repair a broken lab |
| `./lab.sh start` | Restarts the cluster through k3d and recreates pods whose mesh networking broke | After a reboot, sleep, or `./lab.sh stop` |
| `./lab.sh stop` | Stops the k3d cluster and keeps its data | To free memory for other work |
| `./lab.sh status` | Shows nodes, ArgoCD applications, and pods that are not Running | To check the lab is healthy |
| `./lab.sh ui` | Opens the UIs below on localhost | While you work in the UIs |
| `./lab.sh test` | Sends 100 requests and prints status codes, versions and latency | After a routing change |
| `./lab.sh test 4 5` | Runs the course checks for modules 4 and 5 (`all` runs every module, about 40 minutes) | To check a module works |
| `./lab.sh reset` | Removes course exercises and restores the Git baseline (`--all` also removes the course namespaces) | After each exercise |
| `./lab.sh down` | Deletes the cluster after asking (`--yes` skips the question) | To remove the lab |

Each command runs a script in [scripts/](scripts) or [platform-engineering/](platform-engineering), and the course text calls those scripts directly.

Try an experiment:

```bash
./lab.sh test                                                  # every request goes to v1
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml   # send 10% to v2
./lab.sh test                                                  # about 90 v1, 10 v2
./lab.sh reset                                                 # back to the baseline
```

## Open the UIs

The shop works without `./lab.sh ui`. Every other UI needs it running.

| UI | Address | User | Password |
|---|---|---|---|
| The shop | http://localhost:8080 (https://localhost:8443 in [module 11](platform-engineering/2-intermediate/11-edge-tls.md)) | | |
| ArgoCD | http://localhost:8081 | `admin` | `k8s-lab-admin` |
| Grafana, with Prometheus, Loki and Jaeger data sources | http://localhost:3000 | `admin` | `k8s-lab-admin` |
| Prometheus | http://localhost:9090 | | |
| Alertmanager | http://localhost:9093 | | |
| Jaeger | http://localhost:16686 | | |
| Kiali, the Istio console | http://localhost:20001 | | |
| Headlamp, a web UI for the whole cluster | http://localhost:4466 | | |

Redis has no local port. Headlamp has no login and acts as `cluster-admin`, so anyone who opens the page controls the cluster. Every secret is a fixed default stored in Git, so every copy of the lab behaves the same. This is safe only because nothing listens outside your machine.

[Lab credentials](docs/credentials.md) lists where each secret lives and how to change it.

## Learn

The [course](platform-engineering/README.md) is one path in four levels, from building your first application to AI workloads. Read [Istio in one picture](platform-engineering/start-here.md) first, about 15 minutes.

1. [Foundations](platform-engineering/1-foundations/README.md): building, deploying, configuring, observing and networking applications, and the service mesh basics.
2. [Intermediate](platform-engineering/2-intermediate/README.md): the mesh in practice, platform operations from GitOps to policy as code, and setting up a secure cluster.
3. [Advanced](platform-engineering/3-advanced/README.md): hardening nodes and workloads, supply chain and runtime security, and platform internals.
4. [AI on Kubernetes](platform-engineering/4-ai/README.md): an LLM in the mesh, model serving, AI agents and RAG.

The mesh and platform modules run on this lab. The application and security modules run on a [practice cluster](platform-engineering/practice-cluster.md) of two kubeadm nodes with timed tasks and six timed practice exams, and a few kernel tasks run on a [VM](platform-engineering/kernel-and-host/README.md).

The [lab guide](docs/lab-guide.md) is a shorter tour without the course depth. To run the AI modules on another model or on Claude, see [Choosing the model](docs/ai-models.md).

To understand the lab itself, read [how a request travels](docs/architecture.md), [the life of a request](docs/life-of-a-request.md) through every layer, [how the lab was built](docs/build-from-scratch.md), and the [command reference](platform-engineering/1-foundations/09-command-reference.md) for troubleshooting by layer.

## Other platforms

- Linux: the same `./lab.sh` commands work. [Running the lab on Linux](docs/linux.md) has the Ubuntu install steps and Ollama for the AI modules.
- Proxmox: one script builds the course on an Ubuntu VM. See [The lab on Proxmox](proxmox/README.md#platform-engineering-course).

## Troubleshooting

Start with `./lab.sh status`. It shows the sync and health of every ArgoCD application and lists every pod that is not Running.

| Problem | Fix |
|---|---|
| Everything broke after a reboot or sleep; CoreDNS shows `Unknown`; ztunnel is not Ready | `./lab.sh start` |
| `namespaces "argocd" not found`, because OrbStack switched kubectl to its own cluster | `kubectl config use-context k3d-k8s-lab` |
| http://localhost:8080 does not answer | `lsof -i :8080` to find what holds the port, then `kubectl -n shop-ingress get pods` |
| An app shows OutOfSync after an experiment | `./lab.sh reset`; `istio-config` reports drift but does not undo it |
| A pod never appears, because a quota or LimitRange refused it | `kubectl get events -A --field-selector reason=FailedCreate` |

To see recent warnings:

```bash
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20
```

[docs/troubleshooting.md](docs/troubleshooting.md) records every problem hit so far, with symptom, diagnosis and fix.

## Remove everything

```bash
./lab.sh down
```

It deletes the k3d cluster after you confirm, and the built images stay in your local Docker store. To rebuild from nothing, run `./lab.sh down --yes`, then `./lab.sh up`.

Tested on macOS (OrbStack) and Ubuntu 24.04 (Docker Engine 29.1, curl 8.5). On 13 November 2026 a rebuild with cached images took 2 minutes 16 seconds, and on that fresh cluster `./platform-engineering/verify.sh` passed all 232 checks across 22 modules in 41 minutes. Module 27 (RAG, Ollama on the host) passed all 11 checks, and module 21, the one-way k3s upgrade, passed all 9 on 12 November.
