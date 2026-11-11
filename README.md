# k8s_lab_macos

A local Kubernetes reference architecture for macOS with OrbStack. It runs Istio ambient mode, ArgoCD, Prometheus, Grafana, Jaeger and a three-tier shop (Node.js frontend, Python FastAPI backend, Redis).

## Quick start

Requirements: macOS, OrbStack with Kubernetes enabled, `kubectl`, `helm`, `git`, `docker`, `openssl`. Give the OrbStack VM at least 8 GiB of RAM.

```bash
git clone https://github.com/miekuskamil/k8s_lab_macos.git
cd k8s_lab_macos
./scripts/provision.sh
```

ArgoCD syncs the `main` branch of the GitHub repository, so push any local edits before you expect them in the cluster. The script prints the URLs and the generated passwords when it finishes.

| What | Where |
|---|---|
| Shop UI | http://localhost:8080 |
| ArgoCD, Grafana, Prometheus, Jaeger | `./scripts/port-forward.sh`, then ports 8081, 3000, 9090 and 16686 |

## Documents

- [architecture.md](architecture.md) covers the layout, the traffic flow diagram and the mTLS boundaries.
- [learning.md](learning.md) covers ambient versus sidecar mode, GitOps, the traffic scenarios, `istioctl` debugging and production practices.

## Clean up

```bash
./scripts/teardown.sh
```
