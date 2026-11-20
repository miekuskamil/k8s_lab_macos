# Module 15: outlier detection, retries and failover

> New to a term here, like VirtualService or waypoint? The [glossary](../glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 4 and 5.

**You need:** the lab running (`./scripts/start.sh` starts or repairs it).

Module 5 broke the whole backend at once with a delay, a fault and a full connection pool, but real outages often look different, because only one pod out of three goes bad. Its disk fills up, a node problem leaves it with a broken config, or it leaks memory, while the Service keeps sending it its share of traffic, so a third of your users see errors. This module adds a misbehaving pod, fixes the damage in two ways, and compares the two fixes.

Time: about 40 minutes.

## Concept: two different fixes

A bad pod causes two problems: the user who just hit it needs a second chance, and the next users should stop hitting it at all. Istio has one tool for each.

**Retries** send a failed request again, hopefully to a different pod, so the user never sees the first failure.

**Outlier detection** watches each pod's answers, and when a pod fails several times in a row, the proxy takes it out of load balancing for a while, so nobody sends it requests at all.

![The waypoint ejects the faulty backend pod after 3 errors in a row](../../docs/diagrams/chapters/15-outlier-detection.svg)

In the diagram the waypoint keeps sending requests to the two healthy pods and stops sending them to the faulty one after 3 errors in a row.

The two tools sound alike but do different jobs, because a retry hides one failure from one user while outlier detection stops the failures from happening. Think of a restaurant with a sick cook: a retry sends the bad dish back for another cook to remake, and outlier detection sends the sick cook home for a while. The exercise puts numbers on that difference.

## Concept: the waypoint keeps the score, not Kubernetes

Outlier detection runs inside a single Envoy proxy, which in this lab is the shop's waypoint, so Kubernetes never learns that a pod is out. Ejection works in four steps:

1. The waypoint counts the answers from each `backend-v1` pod in its own memory.
2. A pod returns three 5xx errors in a row.
3. The waypoint marks that pod as ejected and stops picking it.
4. When the ejection time runs out, the waypoint tries the pod again.

Nothing outside the waypoint changes:

| Who | What it sees after the ejection |
|---|---|
| Kubernetes (`kubectl -n shop get endpointslices`) | three pods, all ready |
| istiod | three pods, and it keeps sending all three to the waypoint |
| The waypoint's Envoy | three pods, one of them marked as ejected, so it picks from two |

So no `kubectl` command shows an ejection, and you see it only through its effects: the 503s stop, and the faulty pod's log goes quiet.

Each proxy also judges on its own:

- The lab's waypoint runs as one pod, so one set of three errors is enough.
- With two waypoint pods, each pod would need its own three errors.
- In sidecar mode, every client sidecar keeps a separate score, so some clients still call a pod that other clients already ejected.

An ejection always ends by itself, as step 4 says, because Envoy tries the pod again whether anyone fixed it or not.

Retries help only when the second attempt reaches a different pod. Istio configures Envoy's retries to skip the pods that this request already tried, so after the faulty pod returns a 503, the second attempt almost always lands on a healthy pod.

## The bigger picture: failing gracefully

Large systems never run fully healthy, because with hundreds of pods across dozens of nodes, something is always broken somewhere. The goal is to keep a broken part from turning into a broken product, rather than zero failures.

The industry calls this idea graceful degradation, and it changes how you think about health checks. A Kubernetes readiness probe asks the pod "are you OK?", and a broken pod often answers "yes", because its `/readyz` endpoint works fine while every real request fails. Outlier detection asks a better question, "how are your real answers going?", so it judges the pod by what users actually get. That's why big platforms rely on both checks:

- Readiness probes catch pods that are clearly dead.
- Outlier detection catches pods that are quietly wrong.

Retries come with a warning label, and module 5's "bigger picture" section explained three rules for them:

- Retry in one layer only.
- Cap the number of attempts.
- Only retry requests that are safe to repeat.

A GET is safe to repeat, while a POST that charges a credit card twice isn't.

## Concept: failover between zones

Cloud regions consist of zones, where a zone is a separate data centre a few kilometres from the others, with its own power and network. Kubernetes labels every node with its zone (`topology.kubernetes.io/zone`), and Istio reads that label, so with a little configuration a proxy prefers pods in its own zone, which is faster and cheaper, and sends traffic to another zone only when the local pods fail:

```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata:
  name: backend-v1-locality
spec:
  host: backend-v1.shop.svc.cluster.local
  trafficPolicy:
    loadBalancer:
      localityLbSetting:
        enabled: true
        failover:
          - from: eu-west-1a
            to: eu-west-1b
    outlierDetection:          # required: it decides when local pods count as failed
      consecutive5xxErrors: 3
      interval: 5s
      baseEjectionTime: 30s
```

Failover depends on the `outlierDetection` block, because Istio moves traffic to another zone only after outlier detection has ejected the local pods. The ejection you learn in this module is therefore the engine behind zone failover.

This lab runs on one node in one zone, so it has no other zone to fail over to and the course doesn't run this example. The k3s operations module adds a second node, and if you label the two nodes as different zones, the same rule applies.

## Why this way

**Why consecutive errors and not an error percentage?** Consecutive errors react fast and need no statistics, because three 5xx answers in a row from one pod rarely happen by chance. For pods that fail only some of the time, Envoy also supports percentage-based ejection (`failurePercentageThreshold`).

**Why does the ejection time grow?** A pod that comes back and fails again is probably still broken. Envoy multiplies `baseEjectionTime` by the number of times it ejected that pod, so a flapping pod spends less and less time hurting users.

**Why `maxEjectionPercent: 50`?** If every pod fails at once, the cause is probably shared, like a database outage, and ejecting all of them would leave no pod to serve even the requests that might succeed. The cap keeps at least half the pods in rotation.

**Why does the retry need a VirtualService?** The Gateway API version in this lab (v1.2) has no retry field on HTTPRoute in its standard channel, while Istio's VirtualService has had retries since the start. As in module 5, delete the HTTPRoute for the same host first.

**Why `retryOn: 5xx,connect-failure,refused-stream`?** The list names the failures worth a second try:

- `5xx` is a server error.
- `connect-failure` is a connection that never opened.
- `refused-stream` is a stream the server refused.

It leaves out timeouts on purpose, because otherwise a slow backend would receive every request three times.

## Do it

### 1. Add a faulty pod

```console
$ kubectl apply -f platform-engineering/manifests/15-faulty-pod.yaml
deployment.apps/backend-v1-faulty created

$ kubectl -n shop get pods -l app=backend,version=v1
NAME                                 READY   STATUS    RESTARTS   AGE
backend-v1-54c86bf9b-glmrn           1/1     Running   0          24m
backend-v1-54c86bf9b-xqdkd           1/1     Running   0          24m
backend-v1-faulty-7648f4474b-t47sj   1/1     Running   0          8s
```

**What you should see.** Three `backend-v1` pods, the two usual ones and `backend-v1-faulty-...`, all `Running` and `1/1` Ready, so Kubernetes thinks everything is fine.

Now send 90 requests and count the answers:

```console
$ for i in $(seq 1 90); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/orders; done | sort | uniq -c
  59 200
  31 503
```

**What you should see.** About 60 `200` and 30 `503`, because one pod in three fails, so one request in three fails. The test runs for this module counted 34 and 31 out of 90.

### 2. Eject the bad pod

```console
$ kubectl apply -f platform-engineering/manifests/15-outlier-detection.yaml
destinationrule.networking.istio.io/backend-v1-outlier created

$ for i in $(seq 1 30); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/orders; done | sort | uniq -c
  27 200
   3 503

$ for i in $(seq 1 90); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/orders; done | sort | uniq -c
  90 200
```

**What you should see.** The first 30 requests still show about three `503`, which are the "3 errors in a row" that the rule waits for, and then the next 90 requests all return `200`, because the waypoint stopped sending the faulty pod anything.

Wait 40 seconds and repeat the 90 requests, and you'll see about three `503` again:

1. The ejection time ran out.
2. The waypoint gave the pod another chance.
3. The pod failed three more times.
4. The waypoint ejected it again, for longer this time.

### 3. Retries instead

Remove the outlier detection and try retries on their own:

```console
$ kubectl -n shop delete destinationrule backend-v1-outlier
destinationrule.networking.istio.io "backend-v1-outlier" deleted

$ kubectl -n shop delete httproute backend-route
httproute.gateway.networking.k8s.io "backend-route" deleted

$ kubectl apply -f platform-engineering/manifests/15-retries.yaml
virtualservice.networking.istio.io/backend-retries created

$ calls() { kubectl -n shop logs deploy/backend-v1-faulty --since=30m | grep -c /api/orders; }
$ before=$(calls)
$ for i in $(seq 1 90); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/orders; done | sort | uniq -c
  90 200

$ echo "the faulty pod got $(( $(calls) - before )) of those requests"
the faulty pod got 32 of those requests
```

**What you should see.** All 90 return `200`, so users notice nothing. The faulty pod still got about 30 of those requests and failed every one, though, and each failure cost a wasted call, a retry and extra latency for that user, so retries hid the problem without fixing it.

### 4. Both together

```console
$ kubectl apply -f platform-engineering/manifests/15-outlier-detection.yaml
destinationrule.networking.istio.io/backend-v1-outlier created

$ before=$(calls)
$ for i in $(seq 1 90); do curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080/api/orders; done | sort | uniq -c
  90 200

$ echo "the faulty pod got $(( $(calls) - before )) of those requests"
the faulty pod got 3 of those requests
```

**What you should see.** All 90 requests return `200`, while the faulty pod got about three requests, the ones it took to eject it. Retries covered those three and outlier detection handled the rest, which is the pairing production setups use.

| Setup | Failures users saw (of 90) | Requests the faulty pod still got |
|---|---|---|
| Nothing | about 30 | about 30 |
| Outlier detection only | about 3 at the start, then none | about 3 |
| Retries only | none | about 30 |
| Retries and outlier detection | none | about 3 |

## Investigate

1. The faulty pod shows `1/1 Ready` the whole time. Why doesn't Kubernetes take it out of the Service?
2. In step 2, why do exactly about three requests fail before the ejection, and not one?
3. Change `maxEjectionPercent` to `0` and repeat step 2. What happens, and why would anyone set it that way?
4. Your team adds retries everywhere: the gateway retries 2 times, the frontend 2 times, the waypoint 2 times. The backend goes down. How many requests reach it for each click?

<details>
<summary>Answers</summary>

1. Its readiness probe calls `/readyz`, which still works because `ERROR_RATE` breaks only `/api/` paths, and Kubernetes trusts the probe, so the pod stays in the Service's endpoints. Outlier detection judges the pod by its real answers instead, and it exists because of this gap between "the probe says fine" and "users say broken".
2. The rule sets `consecutive5xxErrors: 3`, so Envoy ejects a pod once it has returned three 5xx answers in a row, and the third answer still reaches a user. A lower number would eject pods after a single unlucky error.
3. Envoy ejects nothing, and the 503 rate goes back to about one in three: in a test run, 25 of 90 requests failed with `0`, and none of 90 failed with `50`. With `0`, outlier detection still counts errors but never acts on them, which teams use during a rollout to watch which pods it would eject, without the risk of an unexpected change.
4. Each layer makes up to 3 attempts (1 plus 2 retries), so 3 × 3 × 3 = 27 requests reach the backend for each click, at the moment it struggles most, which engineers call a retry storm. Retry in one layer only, usually the layer closest to the failing service, which here is the waypoint.

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

This deletes the faulty pod, the VirtualService and the DestinationRule, and restores the HTTPRoute.
