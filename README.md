# k8s_lab_macos

A small shop running on your laptop, wrapped in the tooling a platform team uses: Istio ambient mesh, ArgoCD, Prometheus, Grafana, Jaeger, Loki and Kiali. It is a place to learn a service mesh and GitOps without a cloud account.

The shop is a Node.js frontend, a Python FastAPI backend in two versions, and Redis. You break it on purpose (shift 10% of traffic to a new version, inject faults, trip a circuit breaker) and watch what happens in the UIs. An [Istio course](course/README.md) takes you from zero to debugging incidents.

## What you need

| | macOS | Linux |
|---|---|---|
| Container engine | [OrbStack](https://orbstack.dev) with 8 GiB of RAM or more | Docker Engine, your user in the `docker` group |
| Tools | `brew install kubectl helm k3d git istioctl` | kubectl, helm, k3d, git, istioctl from their install pages, curl 7.84 or newer |
| Kernel setting | none | `sudo sysctl -w fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288` |

The first run takes about 10 minutes, mostly image downloads. A rebuild with cached images takes about 2.

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
| The shop | http://localhost:8080 | | |
| Kiali, the Istio console | http://localhost:20001 | | |
| Grafana, with Prometheus, Loki and Jaeger data sources | http://localhost:3000 | `admin` | `k8s-lab-admin` |
| Jaeger | http://localhost:16686 | | |
| Prometheus | http://localhost:9090 | | |
| ArgoCD | http://localhost:8081 | `admin` | `k8s-lab-admin` |

Redis has no local port. Its password is `k8s-lab-redis`.

These logins are fixed defaults stored in Git (`manifests/base/03-lab-credentials.yaml`, and a bcrypt hash in `helm/argocd-values.yaml`), so every copy of the lab behaves the same. That is acceptable only because nothing listens outside your machine. Kiali uses anonymous login for the same reason.

## Try it

```bash
./scripts/traffic-test.sh 200                                  # every request goes to v1
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml   # send 10% to v2
./scripts/traffic-test.sh 200                                  # about 180 v1, 20 v2
./course/reset.sh                                              # back to the baseline
```

Then start the [Istio course](course/README.md), or the shorter [lab guide](docs/lab-guide.md).

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
│   └── scenarios/    canary, fault and circuit-breaker experiments, applied by hand
├── helm/             value files for every Helm chart the lab installs
├── scripts/          provision, start, port-forward, traffic-test, teardown
├── course/           the Istio course: modules 0 to 9, their manifests and scripts
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

This deletes the k3d cluster. The built images stay in your local Docker store.
