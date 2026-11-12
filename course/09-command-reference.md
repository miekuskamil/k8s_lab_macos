# Module 9: command reference

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** none; a reference to keep open while you work.

Troubleshooting commands for this lab, grouped by layer. Work down the layers: a mesh problem is often a cluster problem underneath. Every command here was run against the lab.

Set the context first. OrbStack switches it to `orbstack` when it restarts:

```bash
kubectl config use-context k3d-k8s-lab
```

## Layer 0: the host and the cluster containers

| Question | Command |
|---|---|
| Is Docker up? | `docker info --format '{{.ServerVersion}} {{.NCPU}} CPUs {{.MemTotal}}'` |
| Are the k3d containers running, and since when? | `docker ps --filter name=k3d-k8s-lab --format '{{.Names}} {{.Status}}'` |
| Repair after a reboot or Docker restart | `./scripts/start.sh` |
| What does containerd use for CNI plugins? | `docker exec k3d-k8s-lab-server-0 grep -E "bin_dir\|conf_dir" /var/lib/rancher/k3s/agent/etc/containerd/config.toml` |
| How many pod IPs are reserved on the node? | `docker exec k3d-k8s-lab-server-0 sh -c 'ls /var/lib/cni/networks/cbr0 \| wc -l'` |

## Layer 1: Kubernetes

| Question | Command |
|---|---|
| Is anything not running? | `kubectl get pods -A \| grep -vE "Running\|Completed"` |
| Running but not Ready? | `kubectl get pods -A --no-headers \| awk '{split($3,a,"/"); if (a[1]!=a[2]) print}'` |
| What is Kubernetes complaining about? | `kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp \| tail -20` |
| Pods that were never created (quota, admission) | `kubectl get events -A --field-selector reason=FailedCreate` |
| Why did a container restart? | `kubectl get pod <pod> -n <ns> -o jsonpath='{.status.containerStatuses[*].lastState.terminated.reason}'` |
| The previous container's last words | `kubectl logs <pod> -n <ns> --previous --tail=30` |
| Quota left in a namespace | `kubectl describe resourcequota -n shop` |
| Memory and CPU in use | `kubectl top pods -A --sort-by=memory \| head -15` and `kubectl top node` |
| Is cluster DNS working? | `kubectl -n shop exec deploy/course-client -- nslookup istiod.istio-system.svc.cluster.local` |
| Does CoreDNS have its NodeHosts key? | `kubectl -n kube-system get cm coredns -o jsonpath='{.data.NodeHosts}'` |

## Layer 2: GitOps

| Question | Command |
|---|---|
| Is everything synced and healthy? | `kubectl -n argocd get applications` |
| Why is an app unhealthy or out of sync? | `kubectl -n argocd get application <app> -o jsonpath='{.status.conditions[*].message}'` |
| Which resources in an app differ from Git? | `kubectl -n argocd get application <app> -o jsonpath='{range .status.resources[?(@.status=="OutOfSync")]}{.kind}/{.name}{"\n"}{end}'` |
| Make ArgoCD re-read Git now | `kubectl -n argocd annotate application <app> argocd.argoproj.io/refresh=hard --overwrite` |
| Sync an app now | `kubectl -n argocd patch application <app> --type merge -p '{"operation":{"sync":{}}}'` |

## Layer 3: the Istio control plane

| Question | Command |
|---|---|
| Versions of client, control plane and proxies | `istioctl version` |
| Is istiod healthy? | `kubectl -n istio-system get pods` and `kubectl -n istio-system logs deploy/istiod --tail=30` |
| Which proxies are connected, are they up to date? | `istioctl proxy-status` |
| Does my config have known problems? | `istioctl analyze -n shop` (or `-A` for every namespace) |
| Is one pod in the mesh, and through which waypoint? | `istioctl ztunnel-config workloads \| grep <pod>` (ambient). Do not use `istioctl x describe pod` for ambient pods: it only understands sidecars, reports "not part of mesh" and then fails. |

## Layer 4: ambient data plane (ztunnel and the CNI)

| Question | Command |
|---|---|
| Is a pod in the mesh? | `istioctl ztunnel-config workloads \| grep <pod>`: PROTOCOL `HBONE` means yes, `TCP` means no |
| Which Services go through a waypoint? | `istioctl ztunnel-config services \| grep -E "NAMESPACE\|shop"` |
| Which certificates does ztunnel hold? | `istioctl ztunnel-config certificates` |
| What did ztunnel do with each connection? | `kubectl -n istio-system logs ds/ztunnel --tail=50` |
| Only refused connections | `kubectl -n istio-system logs ds/ztunnel --tail=300 \| grep error=` |
| More detail from ztunnel for a while | `istioctl ztunnel-config log <ztunnel-pod> -n istio-system --level debug` then `--level info` to undo |
| Is the CNI agent working? | `kubectl -n istio-system logs ds/istio-cni-node --tail=20` |
| Which namespaces are ambient? | `kubectl get ns -L istio.io/dataplane-mode,istio-injection` |

## Layer 5: waypoints and gateways (Envoy)

| Question | Command |
|---|---|
| Which waypoints exist, are they programmed? | `istioctl waypoint list -A` and `kubectl get gateway -A` |
| Did my HTTPRoute get accepted? | `kubectl -n shop get httproute <name> -o jsonpath='{range .status.parents[0].conditions[*]}{.type}={.status} {.reason}{"\n"}{end}'` |
| Which routes does the waypoint use? | `istioctl proxy-config routes deploy/waypoint -n shop` |
| Which upstream clusters does it know? | `istioctl proxy-config clusters deploy/waypoint -n shop \| grep backend` |
| Which endpoints, and are they healthy? | `istioctl proxy-config endpoints deploy/waypoint -n shop \| grep backend` |
| Per-request log | `kubectl apply -f course/manifests/06-waypoint-access-logs.yaml` then `kubectl -n shop logs deploy/waypoint -f` |
| Same for the ingress gateway | `kubectl -n shop-ingress logs deploy/shop-gateway-istio --tail=20` |

## Layer 6: sidecars

| Question | Command |
|---|---|
| Is injection on for a namespace? | `kubectl get ns -L istio-injection` |
| Did a pod get a sidecar? | `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].name}'` |
| Routes the client sidecar uses | `istioctl proxy-config routes deploy/client -n course-sidecar` |
| Service, ports and effective mTLS mode of a sidecar pod | `istioctl x describe pod <pod> -n course-sidecar` (sidecar pods only) |
| Sidecar logs | `kubectl logs <pod> -n <ns> -c istio-proxy --tail=30` |

## Layer 7: the application path, from outside in

```bash
curl -sv http://localhost:8080/api/orders 2>&1 | grep -E "^< HTTP|^< server|^< x-"      # status and proxy headers
./scripts/traffic-test.sh 100 10                                                       # status and version split
kubectl -n shop exec deploy/course-client -- curl -s -m 5 -w " %{http_code}\n" http://backend:8000/api/version   # from inside the mesh
```

## Queries for the UIs

**Prometheus or Grafana Explore (PromQL).**

```promql
# requests through the waypoint by status code and Envoy response flag
sum by (response_code, response_flags) (rate(istio_requests_total{reporter="waypoint"}[1m]))

# p95 latency per backend version, at the waypoint
histogram_quantile(0.95, sum by (le, destination_workload) (rate(istio_request_duration_milliseconds_bucket{reporter="waypoint"}[1m])))

# who called the backend, and with what result, over the last 5 minutes
sum by (source_workload, response_code) (increase(istio_requests_total{destination_service_name=~"backend.*"}[5m]))

# TCP traffic ztunnel carried, per destination
sum by (destination_workload) (rate(istio_tcp_sent_bytes_total[1m]))

# ztunnel memory
container_memory_working_set_bytes{namespace="istio-system", pod=~"ztunnel.*", container!=""}
```

**Loki (LogQL) in Grafana Explore.**

```logql
{namespace="shop", app="backend"} | json | status >= 400       # backend requests that failed
{namespace="shop", app="frontend"} |= "unreachable"            # frontend could not reach the backend
{namespace="istio-system", container="istio-proxy"} |= "error="  # ztunnel refusals
{namespace="shop"} |= "<trace id>"                              # every log line for one request
```

**Jaeger.** Search by service `shop-gateway-istio.shop-ingress` to see whole requests from the edge. Use Tags such as `http.status_code=503` or `response_flags=UO`, and Min Duration such as `500ms` to find slow ones.

**Kiali.** Traffic Graph with Display: Security (padlocks), Response Time, and Traffic Distribution. **Istio Config** for validation errors (codes such as `KIA1402`). **Workloads**, a workload, then the Logs, Traces and Envoy tabs.
