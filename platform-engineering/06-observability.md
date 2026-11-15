# Module 6: observability

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 4 and 5.

**You need:** the lab running (`./scripts/start.sh` starts or repairs it), and `./scripts/port-forward.sh` running in a spare terminal for Jaeger (http://localhost:16686), Grafana and Kiali.

When something breaks, you need to see what happened, and the mesh helps because it measures every request it carries, with no code in the application. This module shows three things:

- what the mesh records
- where each kind of data lives
- how to follow a single request across metrics, traces and logs

## Concept: three signals, four tools

![Who produces metrics, traces and logs, where they live and where you look](../docs/diagrams/chapters/06-signals.svg)

The diagram reads from left to right: the parts that produce data, the stores that keep it, and the two tools you look at. Engineers call the three kinds of data signals:

| Signal | Answers | Produced by |
|---|---|---|
| Metrics | How many, how fast, how many failed, over time | ztunnel (TCP bytes and connections), waypoint and gateway (HTTP requests, codes, latency), the app (its own counters) |
| Traces | Where did this one request spend its time | gateway and waypoint spans, plus the backend's own spans |
| Logs | What did the code say while it happened | every container's stdout, collected into Loki |

## Concept: which proxy reports what

Each proxy reports only what it understands. ztunnel never reads HTTP, so it reports TCP facts: connections opened and closed, and bytes sent and received. HTTP metrics, which means request counts by status code and latency histograms, come from the two Envoy proxies, the gateway and the waypoint.

The exercises show the result: **traffic to a Service without a waypoint has no HTTP metrics.** The backend's traffic to Redis is TCP only, which suits Redis, and if you needed HTTP metrics for the frontend, you would give it a waypoint.

One request often passes two proxies and both record it, so the `reporter` label says which proxy recorded a metric:

| `reporter` | Recorded by |
|---|---|
| `source` | the client side, here the ingress gateway |
| `waypoint` | the waypoint |
| `destination` | the server side, in sidecar mode |

That table holds for the HTTP metric `istio_requests_total`. ztunnel's TCP metrics carry `reporter` too, set to `source` or `destination` depending on which end of the connection it sat on, so one connection often shows up twice. Always filter or group by `reporter`, because otherwise you count the same traffic twice.

The diagram's arrows show where data ends up, not who sends it, and metrics and spans travel in opposite directions:

- Nobody pushes metrics. Each proxy and app serves its numbers on a metrics port, and Prometheus pulls them every 15 seconds, guided by PodMonitors, small resources that list which pods to scrape.
- Spans travel the other way, because the gateway, the waypoint and the backend push them to Jaeger.

This difference explains the lag you saw in module 4, since a metric moves only after the next scrape and once the `rate()` window fills.

## Concept: how one trace crosses three processes

A single request passes through the gateway, the frontend, the waypoint and the backend, so to see its whole path each process has to record its part and tag it with the same id.

A span is one timed piece of work, such as "the waypoint handled this request", and a trace is a tree of spans that share a trace id. The id travels between processes in the W3C `traceparent` HTTP header:

```text
traceparent: 00-261b80c9d5032cc2619778fe9c1881c4-4f834e4ebc2759f7-01
                 trace id (32 hex)                 parent span id   sampled
```

Here is how one trace grows, hop by hop:

1. The gateway sees no `traceparent`, so it starts a trace, records a span and adds the header.
2. The frontend records nothing, but it copies the header onto its call to the backend. That's the only thing an app must do to keep a trace connected.
3. The waypoint records a span as a child of the gateway's span and passes the header on.
4. The backend's OpenTelemetry SDK, a tracing library inside the app, continues the same trace and adds its own spans, including the Redis calls.
5. The backend writes the trace id into its log lines.

Step 1 of the exercise follows exactly this chain, from a Jaeger trace to the backend's log line and back.

## Why this way

**Why do proxies record metrics, not the apps?** When the proxies record them, every service reports the same metrics with the same labels, whatever its language, so a dashboard you build once works for every service in the mesh.

**Why must the app forward headers?** A proxy has no way to know which incoming request caused the frontend's outgoing call, because only the application knows that. Forwarding `traceparent` tells the mesh "these two belong together".

**Why does the backend still use an SDK?** Proxies see the request enter and leave the backend, but not the Redis calls inside it, so the SDK adds those spans to the same trace.

**Why put the trace id in log lines?** The trace id links a trace to its logs, like an order number on both a receipt and a delivery note, so Grafana jumps from a span to the log lines it produced and from a log line back to its trace.

**Why 100% sampling here?** Sampling means keeping only some traces. The lab keeps all of them so that every request you send shows up in Jaeger, while production systems trace 1 to 5% of requests, because storing every trace costs a lot.

## The bigger picture: what to measure first

Three signal types and four tools make it easy to drown, so start with three numbers per service, which people call the RED method after their first letters:

- Rate, the number of requests per second
- Errors, the number of requests that fail
- Duration, how long requests take

The mesh gives you all three for every service without a line of code, from `istio_requests_total` and `istio_request_duration_milliseconds`.

Look at percentiles rather than averages. If 99 requests take 10 ms and one takes 5 seconds, the average comes out at about 60 ms and hides the problem completely. The 99th percentile, p99, is the time that 99% of requests stay under, so here it shows the 5 seconds. Real users remember the slow requests, which is why p95 and p99 tell you far more than the mean.

Each signal answers a different question:

| Signal | What it tells you | Cost |
|---|---|---|
| Metrics | *that* something is wrong | cheap, so you keep them for weeks |
| Traces | *where* in the chain the time went | higher, so you sample them |
| Logs | *why*: the error message, the stack trace, the order id | |

A good investigation moves in that order:

1. A dashboard turns red.
2. A trace points at one service.
3. That service's logs explain the failure.

The exercises in this module follow the same path.

Labels with too many values make a common trap. Prometheus stores one time series for every unique combination of label values, so a label like `user_id` or the full URL turns one metric into millions of series, and Prometheus runs out of memory. Istio avoids this on purpose: its metrics carry labels for the source and destination workloads, the response code and the response flags, but never the request path, which you confirm in Prometheus by looking for a path label on `istio_requests_total` and finding none.

## Do it

### 1. Follow one request from trace to log and back

```console
$ curl -s -X POST -H 'content-type: application/json' -d '{"item":"find-me","quantity":1}' http://localhost:8080/api/orders
{"version":"v1","order":{"id":"3","item":"find-me","quantity":"1","created_at":"2026-11-14T22:50:14.052832+00:00","created_by":"v1"}}
```

**What you should see.** The new order as JSON, created by v1. The `id` counts up from earlier orders, because Redis keeps them across resets.

1. Open **Jaeger** (http://localhost:16686). Pick service `backend` and operation `POST /api/orders`, then click **Find Traces**. Open the newest trace.
2. You see spans from three services: `shop-gateway-istio.shop-ingress`, `waypoint.shop` and `backend`. Expand them, and you find the Redis commands `INCRBY` and `HSET LPUSH LTRIM` among the backend's spans, each span nested inside the one above it. In the lab's trace the spans took these times:
   - the gateway span: 47 ms
   - the waypoint span: 7 ms
   - the backend's `POST /api/orders`: 4 ms
   - the two Redis calls: about 0.4 and 1.1 ms
3. Copy the trace id from the top of the page.
4. Open **Grafana**, Explore, data source **Loki**, and run:

   ```logql
   {namespace="shop", app="backend"} |= "<paste the trace id>"
   ```

   **What you should see.** Exactly one line, the backend's "request handled" log line for that request, with `"method":"POST"`, `"path":"/api/orders"` and the same `trace_id`.
5. To go back, copy the `trace_id` value from the log line and paste it into the search box at the top of the Jaeger page, which looks up a trace by id, and you land on the same trace.
6. Grafana also does both jumps with one click. In Explore, pick the **Jaeger** data source, find the same trace, click a `backend` span and choose **Logs for this span**, and Grafana runs the Loki query from step 4 for you. In a Loki result, the `trace_id` field carries an **Open trace in Jaeger** link back. Module 24 explains how these links work, and why they once came out empty.

### 2. Read the mesh's metrics

In Grafana, open Explore and pick the data source **Prometheus**. Run these queries:

```promql
# requests per second through the waypoint, by destination and status
sum by (destination_workload, response_code) (rate(istio_requests_total{reporter="waypoint"}[1m]))

# p95 latency in milliseconds, per backend version
histogram_quantile(0.95, sum by (le, destination_workload) (rate(istio_request_duration_milliseconds_bucket{reporter="waypoint"}[1m])))

# TCP connections ztunnel opened, per destination
sum by (destination_workload) (rate(istio_tcp_connections_opened_total[1m]))
```

Send traffic first with `./platform-engineering/load.sh 120` so the `rate()` window has data.

**What you should see.** With `load.sh` running at its default 5 requests per second, the three queries return this.

The first query shows `backend-v1` with `response_code="200"` at about 5 per second, plus a `201` series near 0 left over from the `POST` in step 1.

The second query shows `backend-v1` at `10`, which is an estimate sitting on a bucket edge rather than a measurement. Istio's histogram buckets run 0.5, 1, 5, 10, 25, 50 ms and up, and Prometheus knows only how many requests fell into each bucket, so it knows a request took between 5 and 10 ms but not whether it took 6 or 9.

The third query lists many workloads beyond the shop, such as `frontend`, `backend-v1`, `redis`, Grafana, Loki and istiod, because ztunnel counts every connection of every pod in an ambient namespace, including Prometheus's own scrapes.

### Concept: who decides to keep a trace

With sampling below 100%, something must decide which traces to keep. If each hop decided alone, you would get broken traces with missing spans, so the first hop decides for everyone and the decision travels in the header.

The last two digits of `traceparent` carry the decision: `01` means "sampled, record this trace", and `00` means "don't". It happens in three steps:

1. The first proxy that sees a request without a `traceparent` makes the choice. Here that's the ingress gateway.
2. The gateway rolls the dice once, using its `randomSamplingPercentage`, and writes the result into the header.
3. The waypoint and the backend's SDK follow the flag they receive.

So 10% sampling keeps 10% of whole traces, and you never get a trace with the gateway span but no backend span.

The Telemetry resource sets the sampling rate, with the same layering as PeerAuthentication:

- A Telemetry in `istio-system` covers the whole mesh.
- A Telemetry in a namespace overrides it for that namespace.
- A Telemetry with `targetRefs` or a `selector` overrides it for a single proxy.

A common mistake follows from the first-hop decision: you lower the sampling rate on the waypoint alone and see no change, because the gateway already decided for every request that reaches the waypoint.

### 3. Change the sampling rate

```console
$ kubectl -n istio-system patch telemetry mesh-default --type merge \
  -p '{"spec":{"tracing":[{"providers":[{"name":"jaeger-otlp"}],"randomSamplingPercentage":10}]}}'
telemetry.telemetry.istio.io/mesh-default patched

$ ./scripts/traffic-test.sh 200 10 /api/version
Sending 200 requests to http://localhost:8080/api/version with concurrency 10

Status codes
  200  200  (100%)

Backend versions
  v1  200  (100%)

Average latency 44 ms, slowest 165 ms
```

**What you should see.** `telemetry.telemetry.istio.io/mesh-default patched`, then 200 `200` answers, and Jaeger now holds about 20 new traces for the 200 requests, 19 in one run and 25 in another. The gateway rolls the dice for each new request, so the count wobbles around 10%. Put it back with `./platform-engineering/reset.sh`, which restores `randomSamplingPercentage: 100`.

### 4. Turn on access logs for one proxy

```console
$ kubectl apply -f platform-engineering/manifests/06-waypoint-access-logs.yaml
telemetry.telemetry.istio.io/waypoint-access-logs created

$ curl -s -o /dev/null http://localhost:8080/api/orders
$ kubectl -n shop logs deploy/waypoint --tail=1
[2026-11-14T22:50:31.359Z] "GET /api/orders HTTP/1.1" 200 - via_upstream - "-" 0 395 4 3 "-" "node" "fe2298dd-ead3-9d48-9687-d5f3b2fdeac1" "backend.shop.svc.cluster.local:8000" "envoy://connect_originate/10.42.0.157:8000" inbound-vip|8000|http|backend-v1.shop.svc.cluster.local envoy://internal_client_address/ 10.43.239.201:8000 10.42.0.42:48478 - shop.backend-route.0
```

**What you should see.** One access log line for your request, with a few fields worth reading:

- The user agent reads `node`, because the frontend, a Node.js app, made the call, not your curl.
- `395` is the response size in bytes, which grows as orders pile up in Redis.
- The `4` and the `3` are the total time and the backend's time, in milliseconds.

A `Telemetry` resource with `targetRefs` changes one proxy, while the mesh-wide one in `istio-system` changes all of them.

### 5. Read the logs as data

Logs are text, but you often want numbers from them, such as how many requests failed. Three parts make that work in this lab:

- Alloy collects every pod's output and sends it to Loki.
- Loki stores the logs. To keep storage cheap, it indexes only a few labels per stream, `namespace`, `app` and `pod`, and never the text itself.
- LogQL is Loki's query language, which filters the text at query time.

The backend writes one JSON line per request, so LogQL parses each line and turns its fields into numbers.

Send some traffic with errors in it, then open Grafana, Dashboards, **Shop logs**:

```console
$ for i in $(seq 1 30); do curl -s -o /dev/null localhost:8080/api/orders; curl -s -o /dev/null localhost:8080/api/nope; done
$ curl -s -o /dev/null "localhost:8080/api/slow?ms=400"
```

**What you should see.** Seven panels, all built from log lines:

| Panel | LogQL behind it | What it teaches |
|---|---|---|
| Log lines per second, by app | `sum by (app) (rate({namespace="shop"}[1m]))` | `rate()` works on log streams too |
| Backend responses by status | `count_over_time({...app="backend"} \| json \| message="request handled" [1m])` by `status` | `\| json` turns each JSON field into a label you group by |
| Log lines by level | the same, by `level` | `INFO` from the backend, `error` from the frontend |
| Backend p95 duration per path | `quantile_over_time(0.95, ... \| unwrap duration_ms ...) by (path)` | `unwrap` turns a field into a number: percentiles from text |
| Top failing paths | `topk(10, ... \| json \| status >= 400 ...)` | `/api/nope` with `404` |
| Errors in shop | `{namespace="shop"} \| json \| level=~"(?i)error\|warning" or status >= 500` | raw lines, filtered |
| Live logs | `{namespace="shop", app=~"$app"} \|= "$search"` | pick apps at the top, type into **Search text**, like a `grep` across every pod |

In the test run, the status panel showed `200`, `201`, `404`, `429` and `503`, where the last two came from the module 5 and 15 checks a few minutes earlier. The p95 panel put `/api/slow` near 400 ms and `/api/nope` below 1 ms. Click any line in a logs panel to open its fields, including the `trace_id` link to Jaeger.

Logs and metrics sometimes answer the same question, and the dashboard's status panel usually agrees with Prometheus' `istio_requests_total`. When the two disagree, the difference tells you something, as Investigate question 4 shows. Counting from logs reads every line, so it runs slower and costs more at scale, which means you keep it for apps that have no metrics or for questions that metrics leave open, like "which order ids failed?".

## Investigate

1. In Grafana Explore, run `sum by (reporter) (rate(istio_requests_total[5m]))`. Which reporters appear? Which do not, and why?
2. Run `sum by (destination_workload) (rate(istio_requests_total[5m]))`. Is `redis` in the result? Now run the same with `istio_tcp_sent_bytes_total`. Explain the difference.
3. Send one slow request with `curl -s -o /dev/null http://localhost:8080/api/slow?ms=1500`. In Kiali, open **Workloads**, then `waypoint`, then the **Traces** tab. These traces come from Jaeger. Which dot sits highest in the scatter plot, and why?
4. In Loki, compare `{namespace="shop", app="backend"} | json | status >= 400` with the "Backend responses by status code" panel during the module 5 fault injection. Why do the injected 503s appear in the panel but not in the backend's logs?
5. Find a trace with only two spans, from the gateway and the waypoint, and none from the backend. What kind of request produces that?

<details>
<summary>Answers</summary>

1. Two reporters appear, `source` and `waypoint`.
   - `source` comes from the ingress gateway, which reports the requests it sends to the frontend.
   - `waypoint` comes from the waypoint, which reports the frontend's calls to the backend.

   `destination` never appears, because only a sidecar on the receiving side reports it and the shop runs no sidecars. ztunnel reports no HTTP metrics at all.
2. No. `istio_requests_total` lists only `frontend` and `backend-v1`, plus `unknown` for requests that no backend answered. The bytes metric does list `redis`, along with `frontend`, the backends and `waypoint`, because Redis has no waypoint, so only ztunnel sees its traffic, and ztunnel counts bytes and connections, never requests. The same holds for any Service without a waypoint.
3. The dot for your slow request sits highest, at about 1500 ms, while every other dot sits near the bottom at a few milliseconds. Its root span comes from the gateway, `frontend.shop.svc.cluster.local:3000/*`, because the trace started there. The backend's `/api/slow` endpoint sleeps on purpose for the number of milliseconds you pass, so the time went into the backend rather than into the mesh, and opening the trace shows the backend's `GET /api/slow` span filling almost the whole bar.
4. The waypoint invented those 503s. It answered in place of the backend, so the request never reached the app and the app had nothing to log, while the panel reads `istio_requests_total`, which the waypoint writes for every response it sends, its own included. In the lab, `load.sh` counted 90 `503` and 690 `200` during a fault injection run, and Loki held 690 backend log lines for `/api/orders` in that window, with zero at `status >= 400`.
5. A request that the waypoint answered by itself produces it. Turn on the module 5 fault injection, then search Jaeger for service `waypoint.shop` with tag `http.status_code=503`. Each trace has exactly two spans, `shop-gateway-istio.shop-ingress` and `waypoint.shop`, and the waypoint's span carries `response_flags` `DI,FI`.

</details>

## Clean up

```console
$ ./platform-engineering/reset.sh
Removing course rules from the shop namespace
Applying the baseline Istio config from manifests/istio
Turning off the backend experiment settings
Asking ArgoCD to sync istio-config from Git
Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules.
```
