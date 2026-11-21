# Module 8: incidents

> New to a term here, like VirtualService or waypoint? The [glossary](../glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 1 to 7: the incidents mix everything.

**You need:** the lab running (`./lab.sh start` starts or repairs it) and `istioctl`.

This module gives you four broken setups to fix, like real on-call shifts. For each one, `./platform-engineering/incident.sh` breaks something in the cluster and tells you only what the users see, not what it changed, so your job has three parts:

1. Find the cause with the tools.
2. Prove it with evidence.
3. Fix it.

Each incident ends with its answer folded away, and you should try for at least 15 minutes before you open one.

## How to investigate

Work from symptoms to cause, and from the outside in:

![Investigation order from symptom to fix](../../docs/diagrams/chapters/08-investigate.svg)

Keep traffic flowing during each incident so the graphs have data:

```console
$ ./platform-engineering/load.sh 600 /api/orders 5
Sending about 5 requests per second to http://localhost:8080/api/orders for 600s. Press Ctrl-C to stop.
```

Turn on the waypoint's access log once, because it helps in every incident:

```console
$ kubectl apply -f platform-engineering/manifests/06-waypoint-access-logs.yaml
telemetry.telemetry.istio.io/waypoint-access-logs created
```

When Envoy fails a request, it adds a short code, a response flag, that says why. You find the flag in the access log and in `istio_requests_total{response_flags=...}`, and it's the fastest clue you have:

| Flag | Meaning |
|---|---|
| `-` | no flag, Envoy passed the response through |
| `UO` | upstream overflow: circuit breaker rejected the request |
| `UT` | upstream request timeout |
| `UF` | upstream connection failure |
| `UH` | no healthy upstream |
| `NR` | no route configured |
| `DI`, `FI` | delay or fault injected on purpose |

## Concept: who wrote the error?

Without a mesh, an error came from your app or your ingress controller, but in the shop a request passes three more components on its way, so an error page has many possible authors:

- the gateway's Envoy, at the entrance,
- ztunnel, on every hop between pods,
- the waypoint's Envoy, in front of the backend.

Each of them writes errors of its own and leaves a different kind of evidence, so ask "which component answered?" before you ask "why?", or you search the wrong logs.

| What curl shows | Who wrote it | Where to look next |
|---|---|---|
| A status with a short plain-text body, such as `RBAC: access denied` or `no healthy upstream` | An Envoy: the gateway or the waypoint | That proxy's access log and its `response_flags` |
| `503` with `upstream connect error or disconnect/reset before headers` | An Envoy whose connection to the next hop failed or got reset, often by ztunnel | The ztunnel log on the node |
| `000`, a reset, no HTTP status at all | Nothing at L7 answered: ztunnel closed the connection, or nothing listens | The ztunnel log |
| The app's own JSON error | The app | The app's logs in Loki |

Traces give a second clue, because each component that handles a request adds a span to the trace, like a stamp in a passport. In this lab the gateway, the waypoint and the backend write spans while ztunnel writes none, so a trace that ends early shows you the last component that saw the request, and counting the spans comes before reading them.

One case leaves almost no trace at all. When ztunnel refuses a connection at L4 and no Envoy sits in front of it, the refusal shows up in no trace and no HTTP metric, so only the ztunnel log records it.

---

## Incident 1: "Every page says access denied"

```console
$ ./platform-engineering/incident.sh 1
Incident 1 is active. Users are complaining. Open http://localhost:8080 and investigate.
Repair the lab with: ./platform-engineering/incident.sh stop
```

**Users report.** The shop loads but shows no orders. Creating an order fails.

**Your questions.**

1. What status code does `curl -i http://localhost:8080/api/orders` return, and which component wrote the body?
2. Does the request reach the backend? Check Jaeger: how many spans do the new traces have?
3. In Grafana Explore, which `response_code` and `destination_workload` does `istio_requests_total{reporter="waypoint"}` show?
4. What does the waypoint access log give as the reason?
5. Which resource is wrong, and what is wrong with it?

<details>
<summary>Evidence the lab produced, and the answer</summary>

- `curl` returns `403` with body `RBAC: access denied`, which is Envoy's body, not the app's.
- New traces have 2 spans, from the gateway and the waypoint, so the backend never sees the request.
- Prometheus shows `response_code="403"` and `destination_workload="unknown"`, because the waypoint refused the request before it chose a backend pod.
- The access log shows `403 - rbac_access_denied_matched_policy[none]`, which means no ALLOW rule matched.
- The cause is a typo: `backend-allow-frontend` now names `cluster.local/ns/shop/sa/front-end`, while the real service account is `frontend`, without a hyphen. One wrong character in a principal locks out the only real caller.

```console
$ kubectl -n shop get authorizationpolicy backend-allow-frontend -o jsonpath='{.spec.rules[0].from[0].source.principals}'
["cluster.local/ns/shop/sa/front-end"]

$ kubectl -n shop get pod -l app=frontend -o jsonpath='{.items[0].spec.serviceAccountName}'
frontend
```

**Fix.** `./platform-engineering/incident.sh stop`, or `kubectl apply -f manifests/istio/security.yaml`.

**Lesson.** Istio treats a principal as a plain string and never checks that the service account exists. Kiali flags some of these broken references in **Istio Config**, but the reliable check is to test every policy change with a real request.

</details>

---

## Incident 2: "Slow pages fail, fast ones work"

```console
$ ./platform-engineering/incident.sh 2
Incident 2 is active. Users are complaining. Open http://localhost:8080 and investigate.
Repair the lab with: ./platform-engineering/incident.sh stop

$ ./platform-engineering/load.sh 300 "/api/slow?ms=300" 12
Sending about 12 requests per second to http://localhost:8080/api/slow?ms=300 for 300s. Press Ctrl-C to stop.

Status codes:
  200  580
  503  2960
Backend versions:
  unknown  2960
  v1  580
```

**Users report.** The shop works for some requests and returns errors for others, more often when it is busy.

**Your questions.**

1. What proportion of requests fail, and with which code?
2. Do the failed requests take long, or do they fail at once?
3. Which `response_flags` value do the failures carry in Prometheus?
4. Which Istio resource produces that flag? Look for it in every namespace.

<details>
<summary>Evidence the lab produced, and the answer</summary>

- With 12 requests per second to a 300 ms endpoint, 596 of 708 requests failed with `503` in one run, and the full 300 second run in the transcript above failed 2960 of 3540.
- The failures took 5 to 6 ms, which is too fast for a real call, so the waypoint rejected them without calling the backend.
- Prometheus shows `response_code="503", response_flags="UO"`, and the access log shows `503 UO upstream_reset_before_response_started{overflow}`.
- `UO` means a connection pool overflowed. A pool limits how many requests wait for the backend at once, and only a DestinationRule's `connectionPool` sets one, so `kubectl get destinationrule -A` finds `course-incident` on `backend-v1`, with `maxConnections: 1` and `http1MaxPendingRequests: 1`.
- In Jaeger, the failed traces have 2 spans, from the gateway and the waypoint, with the tag `response_flags=UO`.

**Fix.** `kubectl -n shop delete destinationrule course-incident`, or `./platform-engineering/incident.sh stop`.

**Lesson.** A pool limit that is too small hides at quiet times, when the service looks healthy, and under load behaves like an outage. Set limits from the number of concurrent requests you measured, which Grafana shows you.

</details>

---

## Incident 3: "No errors, but the shop got slow"

```console
$ ./platform-engineering/incident.sh 3
Incident 3 is active. Users are complaining. Open http://localhost:8080 and investigate.
Repair the lab with: ./platform-engineering/incident.sh stop
```

**Users report.** No errors at all. The shop is noticeably slower than yesterday.

**Your questions.**

1. Is every request slow, or only some? Look at the spread in `./scripts/traffic-test.sh 100 5`.
2. In Grafana, which panel shows the problem? Which backend version is slow?
3. Is the slowness in the network, the waypoint or the app? Compare "p95 latency at the waypoint" with "p95 latency measured in the app".
4. Why is more traffic going to the slow version than usual?
5. Open a slow trace in Jaeger. Which span has the time?

<details>
<summary>Evidence the lab produced, and the answer</summary>

- All 295 requests returned 200, with 97 going to v1 and 198 to v2.
- p95 latency, the time that 95% of requests stay under, was about 10 ms for v1 and about 975 ms for v2 at the waypoint, and 5 ms for v1 and 975 ms for v2 inside the app. So the app itself runs slowly, and the mesh adds almost nothing.
- Two changes work together here:
  - `backend-route` now sends 70% of traffic to v2. The baseline is 0%.
  - v2 runs with `EXTRA_LATENCY_MS=700`.

```console
$ kubectl -n shop get httproute backend-route -o jsonpath='{.spec.rules[0].backendRefs[*].weight}{"\n"}'
30 70

$ kubectl -n shop get deploy backend-v2 -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="EXTRA_LATENCY_MS")].value}{"\n"}'
700
```

- ArgoCD shows `istio-config` as OutOfSync, because the route in the cluster differs from Git, which is the fastest way to see that someone changed it.

**Fix.** `./platform-engineering/incident.sh stop`.

**Lesson.** A canary promoted too far looks like a general slowdown. The mesh measures latency per version for free, and that measurement tells "v2 is slow" apart from "everything is slow".

</details>

---

## Incident 4: "Bad gateway"

```console
$ ./platform-engineering/incident.sh 4
Incident 4 is active. Users are complaining. Open http://localhost:8080 and investigate.
Repair the lab with: ./platform-engineering/incident.sh stop
```

**Users report.** Every API request fails with 502. The shop's page itself still loads.

**Your questions.**

1. Which component returns the 502? Look at the response body and at the frontend's logs in Loki: `{namespace="shop", app="frontend"}`.
2. What does Kiali's Traffic Graph show between `frontend` and the backend?
3. How many spans do the new traces have? Which proxy is missing from them?
4. What do `istioctl waypoint list -n shop` and `istioctl ztunnel-config services | grep backend` say?
5. Why does the frontend not fall back to calling the backend pods directly?

<details>
<summary>Evidence the lab produced, and the answer</summary>

- The frontend returns the 502 itself: its logs show `"message":"backend unreachable"`, and the body is the frontend's own error JSON.
- New traces have 1 span, the gateway's, so nothing after the frontend reports.
- `istioctl waypoint list -n shop` says `No waypoints found`, and `ztunnel-config services` still lists `backend` with WAYPOINT `None`, while the Service keeps its `istio.io/use-waypoint: waypoint` label.
- Prometheus has no waypoint metrics at all for the period, while ztunnel's log fills with errors for connections to the backend.
- The cause is a missing waypoint, because someone deleted the `waypoint` Gateway. The chain of failure goes like this:
  1. The backend Services still say "use the waypoint".
  2. ztunnel has nowhere to send the traffic.
  3. The connection fails.

  A direct connection to the backend pods would fail too, because the L4 policy admits only the waypoint's identity.

**Fix.** Run `./platform-engineering/incident.sh stop`, which re-applies `manifests/istio/waypoint.yaml`. ArgoCD would also show `istio-config` as OutOfSync, with the Gateway missing.

**Lesson.** A waypoint is a real dependency on the request path, so when it disappears, requests stop. Monitor it like any other service, with alerts on its pods' readiness and on `istio_requests_total{reporter="waypoint"}` dropping to zero.

</details>

---

## After all four

```console
$ ./platform-engineering/incident.sh stop
Removing course rules from the shop namespace
Applying the baseline Istio config from manifests/istio
Turning off the backend experiment settings
Asking ArgoCD to sync istio-config from Git
Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules.

$ ./platform-engineering/verify.sh 8
Restoring the baseline before the checks

== Module 8: incidents
  ok    incident 1 shows 403
  ok    incident 2 shows 503 under parallel load (117)
  ok    incident 3 returns no errors (100)
  ok    incident 3 sends most traffic to v2 (70)
  ok    incident 3 makes v2 slow (v2 answers take 0.6 s or more)
  ok    incident 4 shows 502
  ok    after the repair the shop answers 200

Restoring the baseline

7 checks passed, 0 failed
```

The verify script reproduces each incident and checks its symptom, so it also tells you whether the lab is back to normal.
