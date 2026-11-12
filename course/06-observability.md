# Module 6: observability

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 4 and 5.

The mesh measures every request it carries, with no code in the application. This module shows what it records, where each signal lives, and how to follow a single request across metrics, traces and logs.

## Concept: three signals, four tools

```mermaid
flowchart LR
  subgraph sources["Who produces the data"]
    gw["gateway Envoy"]
    wp["waypoint Envoy"]
    zt["ztunnel"]
    app["backend app<br/>(OpenTelemetry SDK)"]
    pods["every container's stdout"]
  end
  subgraph store["Where it lives"]
    prom[("Prometheus<br/>metrics")]
    jaeger[("Jaeger<br/>traces")]
    loki[("Loki<br/>logs")]
  end
  subgraph ui["Where you look"]
    kiali["Kiali"]
    grafana["Grafana"]
  end
  gw -- "L7 metrics" --> prom
  wp -- "L7 metrics" --> prom
  zt -- "L4 metrics" --> prom
  app -- "app metrics" --> prom
  gw -- "spans" --> jaeger
  wp -- "spans" --> jaeger
  app -- "spans" --> jaeger
  pods -- "Alloy reads via the API" --> loki
  prom --> kiali
  prom --> grafana
  jaeger --> grafana
  loki --> grafana
  jaeger --> kiali
```

| Signal | Answers | Produced by |
|---|---|---|
| Metrics | How many, how fast, how many failed, over time | ztunnel (TCP bytes and connections), waypoint and gateway (HTTP requests, codes, latency), the app (its own counters) |
| Traces | Where did this one request spend its time | gateway and waypoint spans, plus the backend's own spans |
| Logs | What did the code say while it happened | every container's stdout, collected into Loki |

## Concept: which proxy reports what

ztunnel never parses HTTP, so it reports only TCP: connections opened and closed, bytes sent and received. HTTP metrics (request counts by status code, latency histograms) come from the Envoy proxies: the gateway and the waypoint. That has a consequence you will see in the exercises: **traffic to a Service without a waypoint has no HTTP metrics**. Frontend to Redis is TCP only, which is fine for Redis. If you needed HTTP metrics for the frontend, you would give it a waypoint.

The `reporter` label says which proxy recorded a metric:

| `reporter` | Recorded by |
|---|---|
| `source` | the client side, here the ingress gateway |
| `waypoint` | the waypoint |
| `destination` | the server side, in sidecar mode |

## Concept: how one trace crosses three processes

A trace is a tree of spans that share a trace id. The id travels in the W3C `traceparent` HTTP header:

```text
traceparent: 00-261b80c9d5032cc2619778fe9c1881c4-4f834e4ebc2759f7-01
                 trace id (32 hex)                 parent span id   sampled
```

1. The gateway sees no `traceparent`, so it starts a trace, records a span and adds the header.
2. The frontend does not trace, but it copies the header onto its call to the backend. That is the only thing an app must do to keep a trace connected.
3. The waypoint records a span as a child and passes the header on.
4. The backend's OpenTelemetry SDK continues the same trace with its own spans, including the Redis calls, and writes the trace id into its log lines.

## Why this way

**Why do proxies record metrics, not the apps?** Every service then reports the same metrics with the same labels, whatever its language. You build a dashboard once, and it works for every service in the mesh.

**Why must the app forward headers?** A proxy has no way to know which incoming request caused the frontend's outgoing call. Only the application knows that. Forwarding `traceparent` is the app telling the mesh "these two belong together".

**Why does the backend still use an SDK?** Proxies see the request enter and leave. The Redis calls inside the backend stay hidden from them. The SDK adds those spans to the same trace.

**Why put the trace id in log lines?** It is the join key between a trace and its logs. Grafana uses it to jump from a span to the log lines it produced, and from a log line back to its trace.

**Why 100% sampling here?** So every request you send is in Jaeger. In production you would trace 1 to 5% of requests, because storing every trace is expensive.

## The bigger picture: what to measure first

Three signal types and four tools make it easy to drown. Start with three numbers per service. People call them the RED method: **R**ate (requests per second), **E**rrors (how many fail) and **D**uration (how long they take). The mesh gives you all three for every service without a line of code, through `istio_requests_total` and `istio_request_duration_milliseconds`.

Look at percentiles, not averages. Say 99 requests take 10 ms and one takes 5 seconds. The average comes out at about 60 ms and hides the problem completely. The 99th percentile, p99, shows the 5 seconds. Real users remember the slow requests, so p95 and p99 tell you far more than the mean.

Each signal answers a different question:

- **Metrics** tell you *that* something is wrong. They cost little, so you keep them for weeks.
- **Traces** tell you *where* in the chain the time went. They cost more, so you sample them.
- **Logs** tell you *why*: the error message, the stack trace, the order id.

A good investigation moves in that order. A dashboard turns red, a trace points at one service, and that service's logs explain the failure. The exercises in this module follow the same path.

Watch out for one trap: labels with too many values. Prometheus stores one time series for every unique combination of label values. Add a label like `user_id` or the full URL, and one metric explodes into millions of series until Prometheus runs out of memory. Istio avoids this on purpose. Its metrics carry labels for the source and destination workloads, the response code and the response flags, but never the request path. Check it yourself in Prometheus: no label on `istio_requests_total` holds a path.

## Do it

### 1. Follow one request from trace to log and back

```bash
curl -s -X POST -H 'content-type: application/json' -d '{"item":"find-me","quantity":1}' http://localhost:8080/api/orders
```

**What you should see.** The new order as JSON, created by v1:

```text
{"version":"v1","order":{"id":"2","item":"find-me","quantity":"1","created_at":"2026-11-12T19:15:42.309483+00:00","created_by":"v1"}}
```

The `id` counts up from earlier orders, because Redis keeps them across resets.

1. Open **Jaeger** (http://localhost:16686). Service `backend`, operation `POST /api/orders`, **Find Traces**. Open the newest.
2. You see spans from three services: `shop-gateway-istio.shop-ingress`, `waypoint.shop` and `backend`. Expand them. The backend's spans include `INCRBY` and `HSET LPUSH LTRIM`: the Redis commands. In the lab's trace, the gateway span took 47 ms, the waypoint span 7 ms, the backend's `POST /api/orders` 4 ms, and the two Redis calls about 0.4 and 1.1 ms. Each span sits inside the one above it.
3. Copy the trace id from the top of the page.
4. Open **Grafana**, Explore, data source **Loki**, and run:

   ```logql
   {namespace="shop", app="backend"} |= "<paste the trace id>"
   ```

   **What you should see.** Exactly one line, the backend's "request handled" log line for that request, with `"method":"POST"`, `"path":"/api/orders"` and the same `trace_id`.
5. To go back, copy the `trace_id` value from the log line, and paste it into the search box at the top of the Jaeger page (it looks up a trace by id). You land on the same trace.

### 2. Read the mesh's metrics

In Grafana, Explore, data source **Prometheus**:

```promql
# requests per second through the waypoint, by destination and status
sum by (destination_workload, response_code) (rate(istio_requests_total{reporter="waypoint"}[1m]))

# p95 latency in milliseconds, per backend version
histogram_quantile(0.95, sum by (le, destination_workload) (rate(istio_request_duration_milliseconds_bucket{reporter="waypoint"}[1m])))

# TCP connections ztunnel opened, per destination
sum by (destination_workload) (rate(istio_tcp_connections_opened_total[1m]))
```

Send traffic first with `./course/load.sh 120` so the `rate()` window has data.

**What you should see.** With `load.sh` running at its default 5 requests per second:

- The first query shows `backend-v1` with `response_code="200"` at about 5 per second. A `201` series appears too, near 0, left over from the `POST` in step 1.
- The second shows `backend-v1` at `10`. That's an estimate sitting on a bucket edge, not a measurement. Istio's histogram buckets run 0.5, 1, 5, 10, 25, 50 ms and up, and Prometheus only knows how many requests fell into each bucket, not their exact times.
- The third lists many workloads, not only the shop: `frontend`, `backend-v1`, `redis`, Grafana, Loki, istiod and more, because ztunnel counts every connection of every pod in an ambient namespace, Prometheus's own scrapes included.

### 3. Change the sampling rate

```bash
kubectl -n istio-system patch telemetry mesh-default --type merge \
  -p '{"spec":{"tracing":[{"providers":[{"name":"jaeger-otlp"}],"randomSamplingPercentage":10}]}}'
./scripts/traffic-test.sh 200 10 /api/version
```

**What you should see.** `telemetry.telemetry.istio.io/mesh-default patched`, then 200 `200` answers. Jaeger now holds about 20 new traces for the 200 requests: the lab counted 19 in one run and 25 in another. The gateway rolls the dice for each new request, so the count wobbles around 10%. Put it back with `./course/reset.sh`, which restores `randomSamplingPercentage: 100`.

### 4. Turn on access logs for one proxy

```bash
kubectl apply -f course/manifests/06-waypoint-access-logs.yaml
curl -s -o /dev/null http://localhost:8080/api/orders
kubectl -n shop logs deploy/waypoint --tail=1
```

**What you should see.** One access log line for your request:

```text
[2026-11-12T19:19:00.868Z] "GET /api/orders HTTP/1.1" 200 - via_upstream - "-" 0 290 4 4 "-" "node" "21e5901f-..." "backend.shop.svc.cluster.local:8000" "envoy://connect_originate/10.42.0.91:8000" inbound-vip|8000|http|backend-v1.shop.svc.cluster.local ...
```

The user agent reads `node`, because the frontend (a Node.js app) made the call, not your curl. `290` is the response size in bytes, and the two `4`s are the total time and the backend's time in milliseconds. A `Telemetry` resource with `targetRefs` changes one proxy. The mesh-wide one in `istio-system` changes all of them.

## Investigate

1. In Grafana Explore, run `sum by (reporter) (rate(istio_requests_total[5m]))`. Which reporters appear? Which do not, and why?
2. Run `sum by (destination_workload) (rate(istio_requests_total[5m]))`. Is `redis` in the result? Now run the same with `istio_tcp_sent_bytes_total`. Explain the difference.
3. Send one slow request: `curl -s -o /dev/null http://localhost:8080/api/slow?ms=1500`. In Kiali, open **Workloads**, `waypoint`, tab **Traces**. These come from Jaeger. Which dot sits highest in the scatter plot, and why?
4. In Loki, compare `{namespace="shop", app="backend"} | json | status >= 400` with the "Backend responses by status code" panel during the module 5 fault injection. Why do the injected 503s appear in the panel but not in the backend's logs?
5. Find a trace with only two spans (gateway and waypoint, no backend). What kind of request produces that?

<details>
<summary>Answers</summary>

1. `source` and `waypoint`. `source` comes from the ingress gateway, which reports the requests it sends to the frontend. `waypoint` comes from the waypoint, for the frontend's calls to the backend. `destination` never appears: only a sidecar on the receiving side reports that, and the shop runs no sidecars. ztunnel reports no HTTP metrics at all.
2. No. `istio_requests_total` lists only `frontend` and `backend-v1` (plus `unknown` for requests no backend answered). The bytes metric does list `redis`, along with `frontend`, the backends and `waypoint`. Redis has no waypoint, so only ztunnel sees its traffic, and ztunnel counts bytes and connections, never requests. The same holds for any Service without a waypoint.
3. The dot for your slow request, at about 1500 ms. Every other dot sits near the bottom, at a few milliseconds. Its root span comes from the gateway, `frontend.shop.svc.cluster.local:3000/*`, because the trace started there. The backend's `/api/slow` endpoint sleeps on purpose for the number of milliseconds you pass, so the time went into the backend, not into the mesh. Open the trace to see the backend's `GET /api/slow` span fill almost the whole bar.
4. The waypoint invented those 503s. It answered for the backend, so the request never reached the app, and the app had nothing to log. The panel reads `istio_requests_total`, which the waypoint writes for every response it sends, its own included. In the lab, `load.sh` counted 90 `503` and 690 `200` during a fault injection run. Loki held 690 backend log lines for `/api/orders` in that window, and zero with `status >= 400`.
5. A request the waypoint answered by itself. With the module 5 fault injection on, search Jaeger for service `waypoint.shop` with tag `http.status_code=503`: each trace has exactly two spans, `shop-gateway-istio.shop-ingress` and `waypoint.shop`, and the waypoint's span carries `response_flags` `DI,FI`.

</details>

## Clean up

```bash
./course/reset.sh
```
