# Module 5: resilience

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** module 4.

Networks fail and services slow down. This module adds timeouts, fault injection, circuit breaking and rate limiting, and uses Grafana, Jaeger and the waypoint's access log to see each one act.

## Concept: four tools for four failure modes

| Failure | Tool | Where it lives | What the caller sees |
|---|---|---|---|
| A call hangs | Timeout | HTTPRoute `timeouts.request` | `504` after the budget |
| You want to know if callers cope with failure | Fault injection | VirtualService `fault` | Delays and errors you chose |
| A slow backend drags everyone down | Circuit breaker | DestinationRule `connectionPool` | Immediate `503` once the pool is full |
| One client floods the service | Rate limit | the backend itself, in this lab | `429` over the limit |

```mermaid
sequenceDiagram
  participant C as caller
  participant W as waypoint
  participant B as backend
  Note over C,B: timeout 1 s
  C->>W: GET /api/slow?ms=3000
  W->>B: forward
  Note over W: 1 s passes
  W-->>C: 504 upstream request timeout
  Note over B: still working, its answer is thrown away
  Note over C,B: circuit breaker, pool of 5
  C->>W: request 6 while 5 run and 5 wait in the queue
  W-->>C: 503 immediately, flag UO (upstream overflow)
  Note over B: never sees request 6
```

## Why this way

**Why put these in the mesh, not in the code?** Every team would otherwise implement timeouts and retries in its own language, with its own bugs and its own defaults. In the waypoint you configure them once, they look the same for every service, and they show up in the same metrics.

**Why a timeout in the route, not in the client?** The waypoint is the one place that sees every caller. A route timeout protects the backend's callers even if one of them forgot to set its own.

**Why fail fast with a circuit breaker?** Without one, requests to a slow backend pile up in queues, each holding a connection and memory in every hop in front of it, until the whole chain is slow. Rejecting the excess immediately keeps the callers responsive and gives the backend room to recover. That is the "UO" response flag you will see: Envoy refused to send the request because the upstream pool overflowed.

**Why fault injection?** Waiting for the backend to turn slow by itself makes a poor test plan. A delay injected in the waypoint tests the real code paths with real traffic, and you switch it off in seconds.

**Why is rate limiting in the app and not the waypoint?** Envoy has a local rate limiter, but Istio exposes it only through `EnvoyFilter`, which waypoints do not support in 1.24. A global limiter needs a separate rate-limit service. For a lab, a token bucket in the backend (`RATE_LIMIT_RPS`) shows the behaviour with no extra component.

**Why does fault injection need a VirtualService?** Gateway API has no fault injection field. Istio still supports its own API for features the standard lacks. Istio defines no result when an HTTPRoute and a VirtualService both target the same Service, so you delete the route first.

## The bigger picture: how one slow service takes down ten

Failures in distributed systems rarely stay where they start. Picture the backend slowing from 50 ms to 5 seconds per request. The frontend keeps sending at the same rate, so requests pile up. Each one holds a connection, a thread or a slice of memory in every hop in front of the backend. Soon the frontend runs out of those as well, and users see the frontend fail, not just the backend. Engineers call this a cascading failure.

Careless retries make it worse. Say the gateway, the frontend and the waypoint each make up to 3 attempts. One click turns into as many as 27 requests at the backend, at the exact moment it struggles most. That's a retry storm. The rule of thumb: retry in one layer only, and only for errors where a second try makes sense, like a reset connection. Never blindly retry a POST that creates an order.

Timeouts need the same care. The outer layer has to wait longer than the inner one. Imagine the frontend gives up after 1 second while the waypoint waits 3 seconds for the backend. The frontend has already shown the user an error, and the backend keeps working on a request nobody wants. Think of it as a budget. Each layer spends part of the time its caller gave it.

Istio puts two different features under the name "circuit breaking", and people mix them up:

- **Connection pool limits** (`connectionPool` in a DestinationRule) cap how many connections and waiting requests go to a service. Above the limit, Envoy rejects the request at once with the `UO` flag. The exercise below uses this one.
- **Outlier detection** (`outlierDetection`) watches each backend pod separately. When a pod returns several 5xx errors in a row, Envoy takes it out of the load-balancing pool for a while. Each time Envoy ejects the same pod again, the break grows longer.

The first protects a service from too much traffic. The second protects callers from one bad pod.

## Do it

Turn on the waypoint's access log for this module. It is off by default because it is verbose:

```bash
cat course/manifests/06-waypoint-access-logs.yaml
kubectl apply -f course/manifests/06-waypoint-access-logs.yaml
```

**What you should see.** A `Telemetry` resource with `targetRefs` pointing at the Gateway `waypoint` and the provider `envoy`, then `telemetry.telemetry.istio.io/waypoint-access-logs created`. Only the waypoint changes. The gateway and ztunnel keep their logging as it was.

Keep a terminal open on it:

```bash
kubectl -n shop logs deploy/waypoint -f | grep -v "Envoy proxy"
```

**What you should see.** A few startup lines from the waypoint, then one line per request through it, starting with a timestamp in square brackets: `[2026-11-12T19:05:52.385Z] "GET /api/slow?ms=300 HTTP/1.1" 200 - via_upstream ...`. After the status code come the response flags (`-` means Envoy added nothing) and a short reason.

### 1. Timeout

```bash
kubectl apply -f course/manifests/05-timeout.yaml
curl -s -o /dev/null -w "%{http_code} in %{time_total}s\n" "http://localhost:8080/api/slow?ms=300"
curl -s -w " %{http_code} in %{time_total}s\n" "http://localhost:8080/api/slow?ms=3000"
```

**What you should see.**

```text
200 in 0.329724s
upstream request timeout 504 in 1.019298s
```

The 300 ms call fits in the 1 second budget. The 3 second call gets cut off after one second. The waypoint wrote the body `upstream request timeout`, and the frontend passed the 504 on to you. The access log shows the reason in its fourth and fifth fields:

```text
"GET /api/slow?ms=3000 HTTP/1.1" 504 UT response_timeout
```

`UT` is Envoy's response flag for "upstream request timeout".

### 2. Fault injection

```bash
kubectl -n shop delete httproute backend-route
kubectl apply -f manifests/scenarios/b-fault-injection.yaml
./scripts/traffic-test.sh 200 10
./scripts/traffic-test.sh 40 5 /api/version
```

**What you should see.** For `/api/orders`, about 10% `503`, and an average latency just above 500 ms. The lab got:

```text
Status codes
  503  20  (10%)
  200  180  (90%)

Backend versions
  v1  159  (80%)
  v2  21  (10%)
  unknown  20  (10%)

Average latency 525 ms, slowest 581 ms
```

Every request waits 500 ms, then one in ten gets a 503. The 503s show version `unknown`, because no backend answered them and so nobody set the `x-app-version` header. The VirtualService also splits traffic 90/10 between v1 and v2, so a few v2 answers appear. `/api/version` returns 40 `200` with an average around 13 ms: the fault rule matches only the `/api/orders` prefix, so `/api/version` stays clean.

In the access log, the response flags show what the waypoint did: `DI` (delay injected) on every request, and `DI,FI` (delayed, then fault injected) on the 503s:

```text
"GET /api/orders HTTP/1.1" 200 DI ...
"GET /api/orders HTTP/1.1" 503 DI,FI ...
```

### 3. Circuit breaking

First without a breaker, to see the baseline:

```bash
./course/reset.sh
./scripts/traffic-test.sh 200 50 "/api/slow?ms=300"
```

**What you should see.** All 200 return `200`, every one from v1. The average latency sits above the 300 ms the backend sleeps (the lab measured 414 ms, slowest 704 ms): 50 requests at a time queue up in front of the two v1 pods.

Now with a pool of 5 connections and 5 queued requests:

```bash
kubectl apply -f manifests/scenarios/c-circuit-breaker.yaml
./scripts/traffic-test.sh 200 50 "/api/slow?ms=300"
```

**What you should see.** Most requests now return `503`, between 85% and 92% in the lab's runs. The average latency drops (248 ms in one run), because a rejected request returns at once instead of waiting its turn. The access log shows `503 UO upstream_reset_before_response_started{overflow}` for each of them. The few that fit into the pool, about 25 of the 200, return `200` from v1.

### 4. Rate limiting

```bash
./course/reset.sh
kubectl -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=20
kubectl -n shop rollout status deploy/backend-v1
./scripts/traffic-test.sh 400 40
```

**What you should see.** `env updated` for both Deployments, a rolling update of the v1 pods, then most of the 400 return `429`: the lab got 318 `429` and 82 `200`. Each pod has its own bucket of 20 per second, so the total allowed rate grows with the number of pods. That is the main weakness of local rate limiting, and the reason production systems use a shared rate-limit service.

## Investigate

Run each step again with `./course/load.sh 120 <path> 10` in a second terminal, so the graphs have a full minute of data.

1. **Grafana**, dashboard "Shop mesh and traffic experiments". During fault injection, which panel shows the errors, and which shows the delay? Why does "Backend p95 latency measured in the app" not show the 500 ms?
2. **Grafana, Explore, Prometheus.** Run this query during the circuit breaker step:

   ```promql
   sum by (response_code, response_flags) (rate(istio_requests_total{reporter="waypoint", destination_service_name=~"backend.*"}[1m]))
   ```

   Which `response_flags` value appears with the 503s? Compare it with the fault injection step.
3. **Jaeger**, service `shop-gateway-istio.shop-ingress`, Tags `http.status_code=504`. Open a timed-out trace. The waypoint's span lasts about 1 s, but the backend's `GET /api/slow` span lasts about 3 s. What does that tell you about what a timeout does and does not do? What goes wrong if the slow request is a `POST` that a client retried after the 504?
4. **Kiali**, Traffic Graph with "Response Time" edge labels. During the circuit breaker step, which edge turns red?
5. During rate limiting, which component returned the 429: the waypoint or the backend? Prove it with the access log or Jaeger.

<details>
<summary>Answers</summary>

1. "Backend responses by status code" shows the errors: a `503` line at about one tenth of the total. "Backend p95 latency at the waypoint" shows the delay. The lab measured 975 ms there, not 525 ms, because the histogram's buckets jump from 500 to 1000 ms and the p95 estimate lands near the top of that bucket. "Backend p95 latency measured in the app" stays at about 10 ms. The waypoint holds each request for 500 ms before it forwards it, so the backend's own timer only starts when the request arrives and never sees the wait.
2. `UO` (upstream overflow), on `response_code="503"`. The lab saw `{response_code="503", response_flags="UO"}` next to `{response_code="200", response_flags="-"}`. During fault injection the 503s carry `DI,FI` instead and the 200s carry `DI`. Same status code, different cause, and the flag tells them apart. Note that `load.sh` at 10 per second produces only a few overflows, because 10 requests of 300 ms rarely fill a pool of 5 plus 5. A burst like `./scripts/traffic-test.sh 200 50 "/api/slow?ms=300"` fills it at once.
3. In the lab's trace, the gateway span lasted 1017 ms with status 504, the waypoint span 1004 ms with `response_flags` `UT`, and the backend's `GET /api/slow` span 3008 ms with status 200. A timeout stops the waiting, not the work. The backend finished the job and answered, and nobody listened. With a `POST` that creates an order, the first attempt still writes its order after the 504. If the client retries, a second order appears. Retry only requests that are safe to repeat, or give each request an idempotency key so the server spots the duplicate.
4. The HTTP edge from `frontend` to the `backend` service node: in the lab, 90% of its requests were `503` with the flag `UO`, and its response time sits near 0 ms, because the waypoint rejects at once. The edge from `shop-gateway-istio` to `frontend` turns red too (85% errors), because the frontend passes the 503 on. The edge from the `backend` service node to the `backend v1` pods stays clean: only `200`. The rejected requests never reached a pod.
5. The backend. The waypoint's access log shows `"GET /api/orders HTTP/1.1" 429 - via_upstream`: no response flag, and `via_upstream` means the answer came from upstream, the backend pod. Compare with the `UO` and `UT` lines, where the waypoint itself answered. The 429 responses also carry `x-app-version: v1`, a header only the app sets: `./scripts/traffic-test.sh` counted all 400 answers as `v1`.

</details>

## Clean up

```bash
./course/reset.sh
```
