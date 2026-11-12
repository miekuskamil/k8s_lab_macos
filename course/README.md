# Istio course

A hands-on Istio course built on this lab. It assumes you know Kubernetes well (CKA or CKAD level) and have never used a service mesh. Every module explains what Istio does, why it is built that way and not another, and how to see it happening in Kiali, Grafana, Jaeger and Loki.

Each module takes 30 to 60 minutes. Do them in order, because each one builds on the last.

| Module | You learn | Tools you use |
|---|---|---|
| [0. Setup](00-setup.md) | Check the lab and install `istioctl` | `kubectl`, `istioctl` |
| [1. What a mesh adds](01-what-a-mesh-adds.md) | What Kubernetes networking leaves out, and the two Istio data plane designs | Kiali, `istioctl` |
| [2. Identity and mTLS](02-identity-and-mtls.md) | Where workload identity comes from and how the tunnel works | Kiali, ztunnel logs |
| [3. Authorization](03-authorization.md) | L4 and L7 policy, and why you need both | `curl`, Kiali, ztunnel logs |
| [4. Traffic routing](04-traffic-routing.md) | Weighted and content-based routing with the Gateway API | Kiali, Grafana |
| [5. Resilience](05-resilience.md) | Timeouts, faults, circuit breaking, rate limiting | Grafana, Jaeger, access logs |
| [6. Observability](06-observability.md) | What the mesh measures by itself, and how to follow one request | Grafana, Jaeger, Loki, Kiali |
| [7. Sidecar mode](07-sidecar-mode.md) | The classic design, side by side with ambient | `istioctl`, Kiali |
| [8. Incidents](08-incidents.md) | Find and fix four broken setups without being told the cause | everything |
| [9. Command reference](09-command-reference.md) | Troubleshooting commands for the cluster and for Istio | |
| [10. eBPF and Cilium](10-ebpf-and-cilium.md) | The other sidecarless design, compared with ambient. Theory, no install. | `docker exec`, `kubectl top` |
| [11. TLS at the edge](11-edge-tls.md) | HTTPS on the ingress gateway, cert-manager, redirects, renewal without downtime | `curl`, `openssl`, Grafana |
| [12. Egress](12-egress.md) | ServiceEntry, TLS origination, L7 rules on outbound calls, locking a pod in | `curl`, Kiali, Prometheus |
| [13. JWT](13-jwt.md) | End-user identity: RequestAuthentication, rules on token claims, 401 versus 403 | `curl`, Prometheus |

## How the exercises work

Every module has the same parts:

- **Concept.** What problem the feature solves, with a diagram.
- **The bigger picture.** Where the idea comes from and how teams use it in real life, in modules 1 to 7.
- **Why this way.** The design choice and the alternatives Istio did not take.
- **Do it.** Commands to run, each followed by what you should see.
- **Investigate.** Questions you answer with the UIs, not with the manifests.
- **Clean up.** How to return the lab to its starting state.

Course files live in this folder:

| Path | What it is |
|---|---|
| `course/manifests/` | Every manifest the exercises apply, numbered by module |
| `course/reset.sh` | Returns routing, policies and experiment settings to the Git baseline |
| `course/load.sh` | Sends steady traffic so Grafana and Kiali have something to draw |
| `course/incident.sh` | Breaks the lab on purpose for module 8 |
| `course/verify.sh` | Replays every module's key exercise and checks the results |

## Before you start

The lab must be running (`./scripts/provision.sh`, or `./scripts/start.sh` after a reboot) and the UIs open (`./scripts/port-forward.sh` in a spare terminal).

| UI | URL | Login |
|---|---|---|
| Shop | http://localhost:8080 | none |
| Kiali | http://localhost:20001 | none |
| Headlamp | http://localhost:4466 | none |
| Grafana | http://localhost:3000 | `admin` / `k8s-lab-admin` |
| Jaeger | http://localhost:16686 | none |
| Prometheus | http://localhost:9090 | none |
| ArgoCD | http://localhost:8081 | `admin` / `k8s-lab-admin` |

## A note on ArgoCD

The course changes Istio resources by hand, with `kubectl apply`. ArgoCD manages the same resources from Git. The `istio-config` Application does not self-heal, so your changes stay until you run `./course/reset.sh`. ArgoCD shows that Application as `OutOfSync` while an exercise is active. That is expected. One catch: when a new commit lands on `main`, ArgoCD syncs `istio-config` once and wipes the exercise you're in the middle of. Re-apply the step's manifests if that happens. `./course/reset.sh` restores the Git baseline and asks ArgoCD to sync, so it ends `Synced` again.

## Check that the course works

```bash
./course/verify.sh        # every module, about 10 minutes
./course/verify.sh 4      # one module
```

The script applies each module's manifests, checks the results and restores the baseline. It was run against this lab before the course was published. The [last section of module 0](00-setup.md#what-the-verification-run-showed) has the results.
