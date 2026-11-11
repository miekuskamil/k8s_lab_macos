# k8s_lab_macos

A small shop running on your Mac, wrapped in the tooling a real platform team uses. It is a place to try Istio ambient mode, ArgoCD and Prometheus/Grafana/Jaeger without touching a cloud account.

The shop is a Node.js frontend, a Python FastAPI backend (two versions) and Redis. You break it on purpose with traffic experiments: shift 10% of requests to a new version, inject faults, trip a circuit breaker. Then you watch what happened in Grafana and Jaeger.

## What you need

- A Mac with [OrbStack](https://orbstack.dev) installed, and at least 8 GiB of RAM given to it.
- `kubectl`, `helm`, `k3d`, `git`, `docker` and `openssl`. With Homebrew: `brew install kubectl helm k3d git openssl`.
- About 15 minutes for the first run, mostly image pulls.

OrbStack's own Kubernetes can stay switched off. The lab creates a k3d cluster named `k8s-lab` and uses OrbStack only as the Docker engine. See [why k3d](#why-k3d-and-not-orbstacks-kubernetes) below.

## Start it

```bash
git clone https://github.com/miekuskamil/k8s_lab_macos.git
cd k8s_lab_macos
./scripts/provision.sh
```

The script builds the images, creates the cluster, installs Istio and ArgoCD, and waits until everything is healthy. It is safe to run again if it stops halfway. At the end it prints the generated passwords.

ArgoCD deploys from the `main` branch on GitHub, not from your working copy. If you edit a manifest, push it before you expect the cluster to change.

## Open it

| What | Where |
|---|---|
| The shop | http://localhost:8080 |
| ArgoCD | http://localhost:8081 |
| Grafana | http://localhost:3000 |
| Prometheus | http://localhost:9090 |
| Jaeger | http://localhost:16686 |

Only the shop is reachable on its own. For the other four, run `./scripts/port-forward.sh` in a spare terminal and leave it running. Log in to ArgoCD and Grafana as `admin` with the passwords the provision script printed. To print them again:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 --decode; echo
kubectl -n observability get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 --decode; echo
```

## Try it

Send 200 requests and see which backend version answers:

```bash
./scripts/traffic-test.sh 200
```

Right now every request goes to v1. Send 10% to v2:

```bash
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml
./scripts/traffic-test.sh 200
```

You should see roughly 180 answers from v1 and 20 from v2. The Grafana dashboard "Shop mesh and traffic experiments" shows the same split over time. [learning.md](learning.md) has the full walkthrough, including fault injection and circuit breaking.

## Where things are

| Folder | Contents |
|---|---|
| `apps/` | Source and Dockerfiles for the frontend and backend |
| `manifests/` | Kubernetes YAML that ArgoCD syncs, plus `scenarios/` that you apply by hand |
| `helm/` | Value overrides for Istio, ArgoCD and the monitoring stack |
| `scripts/` | `provision.sh`, `teardown.sh`, `port-forward.sh`, `traffic-test.sh` |
| `docs/` | Diagram files |

Two more documents:

- [architecture.md](architecture.md) explains how a request travels through the mesh and where mTLS applies.
- [learning.md](learning.md) is the hands-on guide: ambient mode concepts, the three experiments, `istioctl` debugging and notes for production.

## When something goes wrong

**`provision.sh` stops with "not ready" on ztunnel or istio-cni.** Look at the pod events with `kubectl -n istio-system describe pod -l app=ztunnel`. A message about a missing `istio-cni` plugin means the CNI binary landed in the wrong directory. The script already sets the right directory for k3s, so this usually means an old cluster. Run `./scripts/teardown.sh --yes` and start again.

**`localhost:8080` does not answer.** Check that nothing else on your Mac uses port 8080 (`lsof -i :8080`). Then check the gateway pod with `kubectl -n shop-ingress get pods`. As a fallback, forward it yourself: `kubectl -n shop-ingress port-forward svc/shop-gateway-istio 8080:8080`.

**ArgoCD shows an app as OutOfSync after an experiment.** That is expected. The `istio-config` app does not self-heal, so your manual change stays in place and ArgoCD reports the difference. Press Sync in the UI to return to the Git state.

**A pod is stuck in Pending.** The namespaces have resource quotas sized for an 8 GiB machine. Run `kubectl describe resourcequota -A` to see what is used.

## Why k3d and not OrbStack's Kubernetes

Istio ambient mode needs its CNI plugin to chain onto the cluster's existing network config. OrbStack's built-in cluster has no CNI config directory on the node, so `istio-cni` waits forever with `no networks found in /host/etc/cni/net.d`. A k3d cluster uses k3s with flannel, a combination Istio supports, and it runs on the same OrbStack Docker engine. Port 8080 on your Mac maps to the cluster through the k3d load balancer.

## Remove everything

```bash
./scripts/teardown.sh
```

This deletes the k3d cluster. The built images stay in your local Docker store.
