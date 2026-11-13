# Module 7: sidecar mode

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 1 to 3.

Most Istio installations in production still use sidecars, and most Istio documentation assumes them. This module runs sidecar mode next to ambient in the same cluster, with the same istiod, so you compare them directly.

## Concept: both modes, one control plane

The lab installed Istio with the ambient profile, but istiod still contains the sidecar injector. A namespace chooses its mode with a label:

| Label on the namespace | Mode |
|---|---|
| `istio.io/dataplane-mode: ambient` | ambient, ztunnel and optional waypoints |
| `istio-injection: enabled` | sidecar, an Envoy in every pod |
| neither | not in the mesh |

![Ambient and sidecar namespaces configured by one istiod](../docs/diagrams/chapters/07-two-modes.svg)

## Concept: how a sidecar gets into the pod

The diagram below shows how a one-container Deployment ends up with three containers per pod:

1. You create a Deployment with one container.
2. The API server sends each new pod to istiod's injector for review.
3. The injector adds an init container, `istio-init`, and a proxy container, `istio-proxy`.
4. The kubelet starts `istio-init`, which sets iptables rules and exits.
5. The kubelet starts the app and `istio-proxy`.

![How the injector turns one container into three](../docs/diagrams/chapters/07-injection.svg)

You never add the proxy container yourself. Istio adds it for you, at the moment Kubernetes creates the pod. It does this with a mutating admission webhook, which you know from CKA. The API server sends each new pod spec to istiod first. In a labelled namespace, istiod edits the spec and adds the extra containers. Only then does the API server store the pod.

A common mistake follows from this. You label a namespace `istio-injection: enabled` and expect its running pods to join the mesh. They don't. The webhook only sees a pod when the pod is created. Running pods keep their old spec until you replace them with `kubectl rollout restart`.

## Concept: two proxies on every request

The app in the pod has no idea a proxy exists. It opens connections as usual, and the pod quietly hands them to Envoy. Think of a mail room in an office building. Staff drop letters in the outbox, and the mail room handles every letter, both outgoing and incoming.

The redirect works like this. Before the app starts, the `istio-init` container writes iptables rules into the pod's own network stack. You know iptables rules from kube-proxy, but these rules live inside the pod, not on the node. They do two things:

- They send every outgoing TCP connection to Envoy on port 15001.
- They send every incoming TCP connection to Envoy on port 15006.

Envoy's own connections need an exception, or Envoy would catch its own traffic in an endless loop. Envoy runs as user ID 1337, and the rules skip traffic from that user. So Envoy's connections leave the pod directly.

The result is that a call from `client` to `httpbin` passes two Envoys, one in each pod:

![A request passes two Envoy proxies, one in each pod](../docs/diagrams/chapters/07-two-proxies.svg)

The left Envoy works for the caller, and the right one works for the receiver. That split explains most of this module:

- The client's sidecar applies retries and faults (steps 5 and 6).
- The server's sidecar decides about mTLS and tells the app who called (steps 3 and 4).
- Both sidecars report metrics, so you get two numbers for one request (Investigate question 3).

Ambient keeps the same two roles but moves them out of the pod. The basic connection work, L4, is shared by two ztunnels, one on the caller's node and one on the receiver's node. The HTTP-level work, L7, moves to the waypoint, which acts for the receiver.

## Why this way, and why ambient exists

| | Sidecar | Ambient |
|---|---|---|
| Join the mesh | Restart every pod (the webhook only runs on create) | Label the namespace, no restart |
| Who applies routing rules | The **client's** sidecar | The **destination's** waypoint |
| Memory | One Envoy per pod | One ztunnel per node, one waypoint per namespace or service |
| Pod security | Init container needs `NET_ADMIN` and `NET_RAW` | Nothing extra in the pod |
| Upgrade Istio | Restart every pod to get the new proxy | Upgrade ztunnel and waypoints, pods untouched |
| Maturity | Since 2017, every feature | GA since Istio 1.24, some features still missing (for example `EnvoyFilter` on waypoints) |

**Why does the client apply the rules in sidecar mode?** The client's proxy already sits in the path, so letting it decide saves a trip. Each sidecar is a full Envoy that knows the whole mesh. So the client's sidecar picks the destination pod itself and skips a hop. The cost is that every sidecar holds config for every service. A rule change must also reach every pod.

**Why did ambient move L7 to the destination?** There are two reasons. First, a waypoint holds config only for the services it fronts, not for the whole mesh, so it stays small. Second, the rules now guard the backend's own front door. A rule about "traffic to the backend" applies to every caller, even a caller that is not in the mesh at all. In sidecar mode, a caller without a sidecar skips the client-side rules completely.

**Why does `course-sidecar` not enforce Pod Security `baseline`?** Writing iptables rules inside the pod needs extra Linux permissions, and `baseline` forbids them. The `istio-init` container needs two of these permissions, the `NET_ADMIN` and `NET_RAW` capabilities. Ambient needs neither, because the CNI agent sets up the redirection from outside the pod. Istio also offers a sidecar setup that uses its CNI plugin and drops that requirement. The lab keeps the classic setup so you see it.

## The bigger picture: what living with sidecars feels like

On paper, a sidecar is one more container. In practice, it brings a handful of everyday headaches, and those headaches pushed the Istio team towards ambient.

**Start order.** Kubernetes starts a pod's containers without waiting for each other. If your app starts first and makes a network call before Envoy is ready, the call fails. Istio added a setting, `holdApplicationUntilProxyStarts`, that makes the app wait. Shutdown has the mirror problem: Envoy sometimes stops before the app finishes its last requests.

**Jobs that never finish.** A Job completes when all its containers exit. The app exits, but the sidecar keeps running, so the Job hangs forever. For years people worked around it with scripts that called Envoy's `/quitquitquit` endpoint. Kubernetes finally fixed it with native sidecars. A native sidecar is an init container with `restartPolicy: Always`. The feature is beta and on by default since Kubernetes 1.29. Kubernetes starts that container before the app and stops it after the app.

**Upgrades.** A new Istio version brings a new Envoy, and the only way into a running pod is a restart. In a big cluster, every Istio upgrade turns into a rolling restart of every workload.

**Cost at scale.** Every sidecar reserves CPU and memory. By default it also holds configuration for every service in the mesh and takes updates from istiod. A thousand pods mean a thousand Envoys to feed.

Ambient swaps these problems for different ones. ztunnel runs once per node. A ztunnel crash hits every mesh pod on that node at the same time, while a sidecar crash hits one pod. A noisy workload also shares ztunnel with its neighbours. Neither model wins everywhere. That's why Istio keeps both, and why this lab runs them side by side.

## Do it

### 1. Create a sidecar namespace

```bash
cat course/manifests/07-sidecar-namespace.yaml
kubectl apply -f course/manifests/07-sidecar-namespace.yaml -f course/manifests/07-sidecar-apps.yaml \
  -f course/manifests/07-sidecar-podmonitor.yaml
kubectl -n course-sidecar rollout status deploy/httpbin
kubectl -n course-sidecar get pods
```

**What you should see.** First you see the namespace with the label `istio-injection: enabled`. Then `kubectl apply` prints `created` for the namespace, two service accounts, two Deployments, the Service and the PodMonitor. Both pods show `READY 2/2`, one container for the app and one for `istio-proxy`.

```text
NAME                      READY   STATUS    RESTARTS   AGE
client-588f9f56c-9p5k5    2/2     Running   0          5s
httpbin-fb884c77d-m5tkz   2/2     Running   0          5s
```

The PodMonitor asks Prometheus to scrape the sidecars. By default the lab only scrapes the gateway, the waypoint and ztunnel. Without the PodMonitor, no sidecar metric reaches Grafana or Kiali. Prometheus needs a few minutes to load it. That's why you apply it now, long before the questions at the end.

```bash
kubectl -n course-sidecar get pod -l app=httpbin \
  -o jsonpath='{range .items[0].spec.initContainers[*]}init: {.name}{"\n"}{end}{range .items[0].spec.containers[*]}container: {.name}{"\n"}{end}'
```

**What you should see.**

```text
init: istio-init
container: httpbin
container: istio-proxy
```

The Deployment you applied has one container. The injector added the other two when the API server created the pod. The `.items[0]` in the command matters, because `get pod -l` returns a list, even for one pod.

### 2. Look at the proxies

```bash
istioctl proxy-status
```

**What you should see.** Five rows now:

```text
NAME                                               ...  VERSION  SUBSCRIBED TYPES
client-588f9f56c-9p5k5.course-sidecar              ...  1.24.2   4 (CDS,LDS,EDS,RDS)
httpbin-fb884c77d-m5tkz.course-sidecar             ...  1.24.2   4 (CDS,LDS,EDS,RDS)
shop-gateway-istio-858774d7cd-fcnqh.shop-ingress   ...  1.24.2   4 (CDS,LDS,EDS,RDS)
waypoint-b9b76876f-pwzjr.shop                      ...  1.24.2   4 (CDS,LDS,EDS,WDS)
ztunnel-ttgf9.istio-system                         ...  1.24.2   2 (WADS,WDS)
```

The two sidecars appear next to the gateway, the waypoint and ztunnel. Look at the column "SUBSCRIBED TYPES". It lists the kinds of config each proxy receives from istiod. A proxy that does more work needs more kinds of config:

- Sidecars and the gateway receive `CDS, LDS, EDS, RDS`. These are Envoy's clusters, listeners, endpoints and routes.
- The waypoint takes `WDS` instead of `RDS`. It carries its routes inside its listeners, and it reads workload data like ztunnel does.
- ztunnel receives `WADS, WDS`, which stand for workloads and addresses. This is a much smaller protocol made for ztunnel.

```bash
istioctl x describe pod $(kubectl -n course-sidecar get pod -l app=httpbin -o jsonpath='{.items[0].metadata.name}').course-sidecar
```

**What you should see.**

```text
Pod: httpbin-fb884c77d-m5tkz
   Pod Revision: default
   Pod Ports: 8080 (httpbin), 15090 (istio-proxy)
--------------------
Service: httpbin
   Port: http 8000/HTTP targets pod port 8080
--------------------
Effective PeerAuthentication:
   Workload mTLS mode: PERMISSIVE
```

It shows the Service, the port and the effective mTLS mode. The mode is `PERMISSIVE`, because nothing in `course-sidecar` says otherwise yet. Envoy serves its metrics on port 15090 of `istio-proxy`, and the PodMonitor scrapes that port.

### 3. mTLS identity, seen by the app

```bash
kubectl -n course-sidecar exec deploy/client -c curl -- curl -s http://httpbin:8000/headers
```

**What you should see.** httpbin echoes the request headers it received, as JSON. Among them:

```text
"X-Forwarded-Client-Cert": [
  "By=spiffe://cluster.local/ns/course-sidecar/sa/httpbin;Hash=130e...;Subject=\"\";URI=spiffe://cluster.local/ns/course-sidecar/sa/client"
],
```

`URI=` names the caller, and `By=` names the receiver. The server-side sidecar adds this header. So the app sees who called, even though it never touched TLS. You also find `Traceparent` and `X-Envoy-Attempt-Count: 1`. The sidecars added those headers, not curl.

### 4. PERMISSIVE, then STRICT

```bash
kubectl apply -f course/manifests/02-outside-client.yaml
kubectl -n course-outside exec deploy/client -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.course-sidecar:8000/status/200
```

**What you should see.** `200`. A plaintext client from outside the mesh gets in. That is PERMISSIVE mode, the default for sidecars. If you kept `course-outside` from module 2, `kubectl apply` reports `unchanged`.

```bash
kubectl apply -f course/manifests/07-sidecar-strict-mtls.yaml
kubectl -n course-outside exec deploy/client -- curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://httpbin.course-sidecar:8000/status/200
kubectl -n course-sidecar exec deploy/client -c curl -- curl -s -o /dev/null -w "%{http_code}\n" http://httpbin:8000/status/200
```

**What you should see.** `peerauthentication.security.istio.io/default created`. The outside client now gets `000` with `command terminated with exit code 56`. httpbin's sidecar reset the plaintext connection. The sidecar client still gets `200`, because its own sidecar speaks mTLS for it. Run step 2's `istioctl x describe` again, and it reports `Workload mTLS mode: STRICT`.

### 5. Retries, applied by the client's sidecar

`/unstable?failure_rate=0.5` fails half of the time.

```bash
kubectl -n course-sidecar exec deploy/client -c curl -- sh -c 'ok=0; for i in $(seq 1 40); do c=$(curl -s -o /dev/null -w "%{http_code}" "http://httpbin:8000/unstable?failure_rate=0.5"); [ "$c" = 200 ] && ok=$((ok+1)); done; echo "$ok of 40"'
kubectl apply -f course/manifests/07-sidecar-retries.yaml
# run the same loop again
```

**What you should see.** Without retries, about half the requests succeed. The lab got `27 of 40` and `19 of 40` in two runs. With 3 retries, almost all succeed. The lab got `38 of 40` and `39 of 40`. Each request now gets up to four tries, and four failures in a row happen about one time in 16. The curl command did nothing different. The client's sidecar retried for it.

### 6. Fault injection on the client side

```bash
kubectl apply -f course/manifests/07-sidecar-fault.yaml
kubectl -n course-sidecar exec deploy/client -c curl -- curl -s -o /dev/null -w "%{http_code} in %{time_total}s\n" http://httpbin:8000/status/200
kubectl -n course-sidecar delete virtualservice httpbin
```

**What you should see.**

1. `virtualservice.networking.istio.io/httpbin configured`. The fault rule has the same name as the retry rule, so it replaces it.
2. `200 in 2.005436s` or close to it.
3. `deleted`.

httpbin answered at once. The client's own sidecar held the request for two seconds.

### 7. Compare the memory

```bash
kubectl top pod -n course-sidecar --containers
kubectl top pod -n istio-system | grep ztunnel
kubectl top pod -n shop | grep waypoint
```

**What you should see.**

```text
POD                       NAME          CPU(cores)   MEMORY(bytes)
client-588f9f56c-9p5k5    curl          0m           6Mi
client-588f9f56c-9p5k5    istio-proxy   3m           35Mi
httpbin-fb884c77d-m5tkz   httpbin       1m           8Mi
httpbin-fb884c77d-m5tkz   istio-proxy   3m           39Mi
ztunnel-ttgf9            5m           16Mi
waypoint-b9b76876f-pwzjr        2m           29Mi
```

The lab measured 35 to 39 MiB per sidecar, 12 to 16 MiB for ztunnel, and 29 to 36 MiB for the waypoint. Each sidecar weighs about five times the app it serves. Two sidecars already cost more than ztunnel and the waypoint together, and the sidecar cost grows with every pod.

### 8. Cross-mode traffic

```bash
kubectl -n course-sidecar exec deploy/client -c curl -- curl -s -o /dev/null -w "frontend %{http_code}\n" http://frontend.shop:3000/healthz
kubectl -n course-sidecar exec deploy/client -c curl -- curl -s -w " backend %{http_code}\n" http://backend.shop:8000/api/version
```

**What you should see.**

```text
frontend 200
upstream connect error or disconnect/reset before headers. reset reason: connection termination backend 503
```

A sidecar pod talks to ambient pods without trouble, unless an ambient rule expects traffic to pass through a waypoint. The frontend answers `200`, because sidecars and ztunnel speak the same mTLS. The backend refuses. Here is why, in order:

1. The client's sidecar sends traffic straight to a backend pod and skips the waypoint.
2. The L4 policy `backend-only-from-waypoint` admits only the waypoint.
3. So the backend's ztunnel closes the connection.
4. The client's sidecar turns the closed connection into a `503`.

ztunnel's log shows the rejection with these fields:

- `src.identity="spiffe://cluster.local/ns/course-sidecar/sa/client"`
- `dst.service="backend-v1.shop.svc.cluster.local"`
- `error="connection closed due to policy rejection: allow policies exist, but none allowed"`

Module 3 explains why that policy exists.

## Investigate

1. How does Kiali tell a sidecar workload from an ambient one? Open **Workloads** for `course-sidecar` and `shop`, then open `httpbin`, tab **Logs**. Which containers does it offer?
2. In Kiali **Traffic Graph** for `course-sidecar`, run step 5's loop again with the retry rule in place. How many errors does the edge from `client` to `httpbin` show, compared with what curl saw?
3. In Grafana Explore, run `sum by (reporter) (rate(istio_requests_total{destination_workload="httpbin"}[5m]))`. Sidecars report from both ends. Which `reporter` values appear?
4. Why does step 6's delay not appear in httpbin's own latency at all, while module 5's fault delay did appear at the waypoint?

<details>
<summary>Answers</summary>

1. Kiali looks at the pods. For `httpbin` and `client` it finds an `istio-proxy` container, so it marks them `istioSidecar: true`. The shop's workloads have one container each and live in an ambient-mode namespace. Kiali marks them `isAmbient: true` instead. Check it with `curl -s "http://localhost:20001/api/clusters/workloads?namespaces=course-sidecar,shop"`. The Logs tab for `httpbin` offers two containers, `httpbin` and `istio-proxy`. For `frontend` in module 2 it offered one container plus the `ztunnel` checkbox.
2. The edge shows many more errors than curl saw. In the lab, curl reported `38 of 40`, so two failures. In the same two minutes the edge showed about 61% errors:
   - `500` with no flag on 57% of the requests.
   - `500` with `URX` on about 4%. `URX` means the retry limit was exceeded.

   The sidecar at httpbin records every attempt, the failed ones included, and Kiali counts them all. The `URX` errors are the few requests where all four tries failed, so curl saw the error. Retries hide failures from users, not from your metrics.
3. You see `source` and `destination`. `source` comes from the client's sidecar and counts what the caller finally got. `destination` comes from httpbin's sidecar and counts every attempt that arrived. In the lab, after all of step 5, the numbers were:
   - `destination` held 161 `500` responses.
   - `source` held 34 plain `500` responses from the runs without retries, and 9 with `URX`.

   You only see this once Prometheus scrapes the sidecars. The PodMonitor from step 1 sets that up.
4. The client's sidecar applies the VirtualService. So it waits two seconds before it even sends the request. httpbin's sidecar starts measuring when the request arrives. In the lab, `istio_request_duration_milliseconds` averaged about 2050 ms for `reporter="source"`, with flag `DI`. It averaged about 2 ms for `reporter="destination"`. In module 5, the waypoint injected the delay. The waypoint is also the proxy that reports the metric, so its latency included the wait.

</details>

## Clean up

```bash
./course/reset.sh          # removes the VirtualService and PeerAuthentication
./course/reset.sh --all    # also deletes course-sidecar (with its PodMonitor) and course-outside
```
