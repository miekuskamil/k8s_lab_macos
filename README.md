# k8s_lab_macos

A small shop running on your laptop, wrapped in the tooling a platform team uses: Istio ambient mesh, ArgoCD, cert-manager, Prometheus, Grafana, Jaeger, Loki, Kiali and Headlamp. It is a place to learn a service mesh and GitOps without a cloud account.

The shop is a Node.js frontend, a Python FastAPI backend in two versions, and Redis. You break it on purpose (shift 10% of traffic to a new version, inject faults, trip a circuit breaker) and watch what happens in the UIs. An [Istio course](course/README.md) takes you from zero to debugging incidents.

## What you need

| | macOS | Linux |
|---|---|---|
| Container engine | [OrbStack](https://orbstack.dev) with 8 GiB of RAM or more | Docker Engine, your user in the `docker` group |
| Tools | `brew install kubectl helm k3d git istioctl` | kubectl, helm, k3d, git, istioctl from their install pages, curl 7.84 or newer |
| Kernel setting | none | `sudo sysctl -w fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288` |

The first run takes about 10 minutes, mostly image downloads. A rebuild with cached images takes about 2.

Both platforms are tested. On macOS (OrbStack) and on Ubuntu 24.04 (Docker Engine 29.1 from Ubuntu's packages, curl 8.5), a single `./scripts/provision.sh` from nothing passed every health check, and `./course/verify.sh` passed all 54 checks it had at the time. The latest full run, on macOS only, is below. Other Linux distributions should work if they meet the table above.

OrbStack's own Kubernetes can stay switched off. The lab runs its own k3d cluster on the Docker engine. [docs/build-from-scratch.md](docs/build-from-scratch.md#step-1-the-cluster) explains why.

## Start it

```bash
git clone https://github.com/miekuskamil/k8s_lab_macos.git
cd k8s_lab_macos
./scripts/provision.sh
```

The script builds the images, creates the cluster, installs Istio and ArgoCD, then waits until ArgoCD has deployed everything else and every health check passes. It is safe to run again at any time.

After a reboot, or when the Mac woke up and the lab looks broken:

```bash
./scripts/start.sh
```

ArgoCD deploys from the `main` branch on GitHub, not from your working copy. Push a change before you expect the cluster to show it.

## Open it

Run `./scripts/port-forward.sh` in a spare terminal and leave it running. The shop works without it.

| UI | URL | User | Password |
|---|---|---|---|
| The shop | http://localhost:8080 (https://localhost:8443 during [course module 11](course/11-edge-tls.md)) | | |
| Kiali, the Istio console | http://localhost:20001 | | |
| Headlamp, a web UI for the whole cluster: pods, logs, shells, events, YAML | http://localhost:4466 | | |
| Grafana, with Prometheus, Loki and Jaeger data sources | http://localhost:3000 | `admin` | `k8s-lab-admin` |
| Jaeger | http://localhost:16686 | | |
| Prometheus | http://localhost:9090 | | |
| Alertmanager | http://localhost:9093 | | |
| ArgoCD | http://localhost:8081 | `admin` | `k8s-lab-admin` |

Redis has no local port. Its password is `k8s-lab-redis`.

Headlamp has no login. It acts as a service account bound to `cluster-admin`, so anyone who can open the page can change or delete anything in the cluster.

Every secret the lab uses is a fixed default stored in Git, so every copy of the lab behaves the same. That is acceptable only because nothing listens outside your machine. Kiali and Headlamp have no login for the same reason.

| Secret | Value | Defined in | To change it |
|---|---|---|---|
| Grafana `admin` password | `k8s-lab-admin` | `manifests/base/03-lab-credentials.yaml` (Secret `observability/grafana-admin`) | Edit it there and in `helm/kiali-values.yaml` (`external_services.grafana.auth.password`), which Kiali uses to reach Grafana |
| ArgoCD `admin` password | `k8s-lab-admin` | `helm/argocd-values.yaml`, as a bcrypt hash | Generate a hash with the command in that file's comment, and update `argocdServerAdminPasswordMtime` |
| Redis password | `k8s-lab-redis` | `manifests/base/03-lab-credentials.yaml` (Secret `shop/redis-auth`) | Edit it there, then restart Redis and the backends |
| Kiali token signing key | `k8s-lab-kiali-signing-key-32chrs` | `helm/kiali-values.yaml` (`login_token.signing_key`) | Any 16, 24 or 32 characters. It must be fixed, or Kiali restarts on every ArgoCD poll ([problem 16](docs/troubleshooting.md#16-kiali-restarts-every-few-minutes)) |
| Gitea `lab` password (course module 22 only) | `lab-gitops-pass` | the `gitea admin user create` command in `course/22-gitops-with-argocd.md` | Use another password in that command and in your `git push` URL |

ArgoCD applies all of these from Git, so push a change before you expect it in the cluster. `provision.sh` also applies the two Secrets before ArgoCD starts, so pods that need them start on the first try.

## Try it

```bash
./scripts/traffic-test.sh 200                                  # every request goes to v1
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml   # send 10% to v2
./scripts/traffic-test.sh 200                                  # about 180 v1, 20 v2
./course/reset.sh                                              # back to the baseline
```

Then start the [Istio course](course/README.md) with its 15-minute pre-reading, [Istio in one picture](course/start-here.md), or the shorter [lab guide](docs/lab-guide.md).

## Where things are

```text
k8s_lab_macos/
├── README.md         you are here
├── apps/             source code and Dockerfiles: frontend (Node.js), backend (Python)
├── manifests/        Kubernetes YAML; ArgoCD syncs everything here except scenarios/
│   ├── argocd/       the root Application and one Application per area
│   ├── base/         namespaces, RBAC, quotas, lab credentials
│   ├── apps/         the shop: frontend, backend v1 and v2, redis
│   ├── istio/        gateway, waypoint, routes, security policies, tracing
│   ├── observability/ Jaeger, Prometheus monitors, Grafana dashboard
│   ├── cert-manager/ the lab certificate authority
│   └── scenarios/    canary, fault and circuit-breaker experiments, applied by hand
├── helm/             value files for every Helm chart the lab installs
├── scripts/          provision, start, port-forward, traffic-test, teardown
├── course/           the course: modules 0 to 24, their manifests and scripts
└── docs/             build guide, architecture, lab guide, troubleshooting, diagrams
```

| Document | For |
|---|---|
| [docs/build-from-scratch.md](docs/build-from-scratch.md) | How the lab was built, step by step: every decision, the alternatives, and what went wrong |
| [docs/architecture.md](docs/architecture.md) | How a request travels, where mTLS applies, what was measured |
| [course/README.md](course/README.md) | The Istio course |
| [docs/lab-guide.md](docs/lab-guide.md) | The lab's experiments and GitOps workflow, without the course depth |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Every problem hit so far, with symptom, diagnosis and fix |
| [course/09-command-reference.md](course/09-command-reference.md) | Troubleshooting commands for the cluster and Istio, by layer |

## When something goes wrong

Start with these three commands:

```bash
kubectl get pods -A | grep -vE "Running|Completed"
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20
kubectl -n argocd get applications
```

| Symptom | Likely cause | Fix |
|---|---|---|
| Everything broken after a reboot or sleep; CoreDNS `Unknown`; ztunnel not Ready | Docker restarted the cluster without k3d | `./scripts/start.sh` |
| `namespaces "argocd" not found` | OrbStack switched kubectl to its own cluster | `kubectl config use-context k3d-k8s-lab` |
| `localhost:8080` does not answer | Port 8080 taken, or the gateway pod is missing | `lsof -i :8080`, then `kubectl -n shop-ingress get pods` |
| An app shows OutOfSync after an experiment | Expected: `istio-config` reports drift but does not undo it | `./course/reset.sh` |
| A pod never appears | Quota or LimitRange refused it | `kubectl get events -A --field-selector reason=FailedCreate` |

[docs/troubleshooting.md](docs/troubleshooting.md) has the full record.

## Remove everything

```bash
./scripts/teardown.sh
```

It asks before deleting. Add `--yes` to skip the question, for example in a script. This deletes the k3d cluster. The built images stay in your local Docker store.

To rebuild from nothing: `./scripts/teardown.sh --yes && ./scripts/provision.sh`. On 12 November 2026 that took 2 minutes 13 seconds with cached images. On a fresh rebuild the same evening, `./course/verify.sh` passed 177 of its 178 checks (the one miss, a check that read a window still holding the previous module's errors, was fixed and rerun), and `./course/verify.sh 21`, the one-way k3s upgrade, passed all 9 of its own.
