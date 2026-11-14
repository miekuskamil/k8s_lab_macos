# Lab guide

This guide assumes `./scripts/provision.sh` finished and you can open http://localhost:8080. Run all commands from the repository root. Start `./scripts/port-forward.sh` in a spare terminal so Grafana, Jaeger and ArgoCD are open while you work.

This guide is the short tour. For a full introduction to Istio with diagrams, design reasons and investigation exercises in Kiali, Grafana, Jaeger and Loki, take the [Kubernetes Platform Engineering course](../course/README.md).

Contents:

1. [Ambient mode in two minutes](#1-ambient-mode-in-two-minutes)
2. [GitOps in practice](#2-gitops-in-practice)
3. [Three traffic experiments](#3-three-traffic-experiments)
4. [Recipes](#4-recipes)
5. [Debugging mTLS drops](#5-debugging-mtls-drops)
6. [Notes for production](#6-notes-for-production)
7. [Things to try next](#7-things-to-try-next)

## 1. Ambient mode in two minutes

A classic Istio mesh injects an Envoy proxy sidecar into every pod. Ambient mode removes the sidecars and splits the work into two layers:

- **ztunnel** runs once per node. It handles identity and mTLS for every pod on that node and enforces simple TCP-level policy. It never reads HTTP.
- **A waypoint** is an Envoy proxy you add for a namespace or a single Service when you need HTTP features: weighted routing, fault injection, retries, HTTP-aware policy.

You enroll a namespace by labeling it, and no pod restarts. In this lab the `shop` namespace carries `istio.io/dataplane-mode: ambient`, and only the three backend Services carry `istio.io/use-waypoint: waypoint`. Redis and the frontend get mTLS from ztunnel and nothing more.

### Why it matters on a laptop

A sidecar costs memory in every pod, whether or not the pod needs HTTP features. The lab has about 14 mesh pods across `shop` and `observability`, so sidecars would mean 14 extra Envoy processes. In ambient mode the whole cluster has one ztunnel and one waypoint. Sidecar Envoys commonly use tens of megabytes each, but the exact number depends on your traffic and config, so measure it:

```bash
kubectl top pods -n istio-system
kubectl top pods -n shop
```

The Grafana panel "ztunnel memory per node" shows the same number over time.

### Trade-offs

- Pods that share a waypoint share its capacity. A very busy service should get its own waypoint.
- L7 policy and routing only apply to Services bound to a waypoint. A policy aimed at a Service without one does nothing.
- Waypoints support fewer Envoy extensions than sidecars. `EnvoyFilter` is not available, which is why the lab does rate limiting inside the backend.

## 2. GitOps in practice

With GitOps, Git holds the state you want and ArgoCD makes the cluster match it. You do not run `kubectl apply` for the managed parts. You commit.

`manifests/argocd/root-app.yaml` is the entry point. It points at the folder `manifests/argocd/apps/`, which holds one ArgoCD Application per area of the lab. Add a file there and ArgoCD creates a new Application on its next sync (it checks Git about every three minutes).

### See drift being corrected

Scale the frontend by hand:

```bash
kubectl -n shop scale deploy/frontend --replicas=3
kubectl -n shop get pods -l app=frontend --watch
```

Within a few seconds ArgoCD notices the cluster no longer matches Git and scales back to one replica, because `shop-apps` has self-heal on. Open the ArgoCD UI to see the sync event.

### See drift being reported but not corrected

The `istio-config` Application has self-heal off. Apply an experiment by hand:

```bash
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml
kubectl -n argocd get application istio-config
```

The Application shows `OutOfSync` and the 90/10 split stays active. Sync it from the UI, or run the command below, and the route returns to the 100/0 state stored in Git:

```bash
kubectl -n argocd patch application istio-config --type merge -p '{"operation":{"sync":{}}}'
```

### Change the lab through Git

```bash
git checkout -b canary-20
# edit manifests/istio/backend-route.yaml and set the weights to 80 and 20
git commit -am "Send 20 percent of backend traffic to v2"
git push origin canary-20
# merge to main, then wait for ArgoCD or press Sync on istio-config
```

## 3. Three traffic experiments

Each experiment lists what to run, what you should see, and how to undo it. Wait a few seconds after you apply or remove a rule before you send traffic. While the waypoint loads the new config, a handful of requests can return 503. Use the shop UI at http://localhost:8080 (the "Burst traffic" box) or `./scripts/traffic-test.sh [requests] [concurrency] [path]`.

### A. Canary release, 90% to v1 and 10% to v2

```bash
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml
./scripts/traffic-test.sh 200
```

**What you should see.** About 180 responses from v1 and 20 from v2. Each run varies a little, because the split is random per request. In Grafana, the panel "Backend request rate by workload" shows two bands, one roughly nine times the other.

**Undo.** `kubectl apply -f manifests/istio/backend-route.yaml`

### B. Fault injection on /api/orders

Gateway API routes cannot inject faults, so this experiment uses an Istio VirtualService. A route and a VirtualService for the same host conflict, so remove the route first.

```bash
kubectl -n shop delete httproute backend-route
kubectl apply -f manifests/scenarios/b-fault-injection.yaml
./scripts/traffic-test.sh 200
```

**What you should see.** Every request to `/api/orders` takes at least 500 ms, and about 10% return HTTP 503. The 503 responses have no `x-app-version` header because the waypoint generates them and the backend never sees the request. In Jaeger, pick the `backend` service and look at a slow trace to see where the half second went.

**Undo.**

```bash
kubectl delete -f manifests/scenarios/b-fault-injection.yaml
kubectl apply -f manifests/istio/backend-route.yaml
```

### C. Circuit breaking and rate limiting

The first half limits connections at the waypoint. Fifty parallel requests to a slow endpoint overflow a pool of 5 connections plus 5 queued requests.

```bash
kubectl apply -f manifests/scenarios/c-circuit-breaker.yaml
./scripts/traffic-test.sh 200 50 "/api/slow?ms=300"
```

**What you should see.** Most responses are 503 and return in a few milliseconds. The waypoint rejects the overflow immediately and does not queue it. Compare with the same command after you remove the policy, where every request succeeds but takes longer.

**Undo.** `kubectl delete -f manifests/scenarios/c-circuit-breaker.yaml`

The second half limits request rate. A waypoint cannot do this, so the backend has its own token bucket, controlled by an environment variable:

```bash
kubectl -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=20
./scripts/traffic-test.sh 200 20
```

Wait for the rollout to finish (`kubectl -n shop rollout status deploy/backend-v1`) before you send traffic.

**What you should see.** Status 429 for the requests above the limit. Each pod has its own bucket of 20 requests per second, so the total allowed rate depends on how many pods receive traffic. The Grafana stat "Requests rejected by the backend rate limiter" goes up.

**Undo.** `kubectl -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=0`

`shop-apps` self-heals, so ArgoCD would normally revert a manual change to a Deployment within seconds. The Application lists `RATE_LIMIT_RPS` and `EXTRA_LATENCY_MS` under `ignoreDifferences`, so these two variables stay as you set them. Any other manual edit to the Deployments is still reverted.

## 4. Recipes

### Add a new service

This example adds a `payments` service in the `shop` namespace.

1. Create `apps/payments/` with code and a Dockerfile. Copy the backend as a starting point.
2. Build the image and load it into the cluster:
   ```bash
   docker build -t k8s-lab/payments:1.0.0 apps/payments
   k3d image import k8s-lab/payments:1.0.0 -c k8s-lab
   ```
3. Create `manifests/apps/payments.yaml` with a ServiceAccount, a Deployment and a Service. Copy the probes, resource block and security context from `manifests/apps/backend.yaml`. Name the Service port `http` and add the label `metrics: scrape` so Prometheus finds it.
4. If the service needs HTTP routing or HTTP-aware policy, add the label `istio.io/use-waypoint: waypoint` to the Service. Leave it off for plain TCP.
5. Add an AuthorizationPolicy to `manifests/istio/security.yaml` that names the allowed callers by service account.
6. Check there is quota left: `kubectl -n shop describe resourcequota shop-quota`.
7. Commit and push. ArgoCD picks the file up on its next sync.

### Change the canary percentage

For a quick experiment, patch the live route:

```bash
kubectl -n shop patch httproute backend-route --type json -p '[
  {"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
  {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}
]'
```

For a change you want to keep, edit the two `weight` values in `manifests/istio/backend-route.yaml`, commit and push. Weights are relative, so 1 and 1 also means 50/50. A weight of 0 keeps the backend in the route but sends it nothing, which is how the baseline parks v2.

## 5. Debugging mTLS drops

Install the CLI with `brew install istioctl`. Its version should match the control plane (`istioctl version`). Work from the outside in.

**1. Is the pod in the mesh?**

```bash
kubectl get ns shop --show-labels | grep dataplane-mode
istioctl ztunnel-config workloads | grep -E "NAMESPACE|shop"
```

The PROTOCOL column must say `HBONE`. `TCP` means the pod is not enrolled. A pod that started before you labeled the namespace needs a restart.

**2. Is the waypoint attached?**

```bash
istioctl waypoint list -n shop
istioctl ztunnel-config services | grep -E "NAMESPACE|backend"
```

The WAYPOINT column for `backend` should show `waypoint`. If it is empty, check that the Gateway is programmed with `kubectl -n shop get gateway waypoint`.

**3. Does the workload have a certificate?**

```bash
istioctl ztunnel-config certificates
```

Look for `spiffe://cluster.local/ns/shop/sa/backend`. If a certificate is missing or expired, check that istiod is running.

**4. What does ztunnel say about the dropped connection?**

```bash
kubectl -n istio-system logs ds/ztunnel --tail=100 | grep -iE "denied|error|rbac|tls"
```

A line about a policy rejection points to an AuthorizationPolicy. A handshake error usually means a client outside the mesh is talking to a workload that requires mTLS.

**5. Test the policies from a pod that should be refused.**

```bash
kubectl -n shop run probe --rm -i --restart=Never --quiet --image=redis:7.4-alpine --command -- sh -c '
  echo "redis:";   timeout 5 redis-cli --no-auth-warning -h redis -a k8s-lab-redis ping
  echo "backend:"; wget -T 5 -qO- http://backend:8000/api/version'
```

The probe pod runs as the `default` service account, so both policies refuse it. Redis prints `I/O error`, because ztunnel cuts the connection at layer 4 (`redis-allow-backend`). The backend prints `403 Forbidden`, because the waypoint rejects the request at layer 7 (`backend-allow-frontend`). Kubernetes also prints a PodSecurity warning for the probe pod, which is harmless. Then read the denial in the ztunnel log:

```bash
kubectl -n istio-system logs ds/ztunnel --tail=200 | grep -iE "denied|reject"
```

**6. Inspect the waypoint when routing looks wrong.**

```bash
istioctl proxy-config routes deploy/waypoint -n shop
istioctl proxy-config clusters deploy/waypoint -n shop | grep backend
kubectl -n shop logs deploy/waypoint --tail=50
```

**7. Let Istio check the configuration.**

```bash
istioctl analyze -n shop
```

This finds, among other things, an HTTPRoute and a VirtualService fighting over the same host.

**8. Raise the log level for a short time.**

```bash
POD=$(kubectl -n istio-system get pod -l app=ztunnel -o name | head -1 | cut -d/ -f2)
istioctl ztunnel-config log "$POD" --level debug
istioctl ztunnel-config log "$POD" --level info
```

The usual causes, roughly in the order they happen: the namespace label is missing, the pod started before the label, a client outside the mesh is calling a workload that requires mTLS, an AuthorizationPolicy names the wrong service account, or the waypoint pod is not Ready.

## 6. Notes for production

This lab runs on one laptop. These are the habits worth carrying to a real cluster, and what the lab does about each.

### Resources

- Give every container a request and a limit. The quotas in `manifests/base/02-quotas.yaml` reject pods without them, and a LimitRange fills the gap for third-party charts.
- Requests decide scheduling. Limits decide throttling and out-of-memory kills. Memory cannot be squeezed, so keep the memory limit close to the request.
- Do not set a CPU limit so low that startup gets throttled. A throttled startup fails its probe and restarts in a loop.
- Redis runs with `--maxmemory` below the container limit, so it evicts keys and does not get killed.

### Probes

The backend and frontend use all three kinds:

- The startup probe gives the app up to 40 seconds to boot. The other probes wait until it passes.
- The readiness probe takes a pod out of the Service when it cannot do its job. The backend checks Redis on `/readyz`, so a Redis outage drains the backends instead of returning errors.
- The liveness probe restarts a stuck process. It only checks the process itself (`/healthz`), never a dependency. If liveness checked Redis, a Redis outage would restart every backend and make things worse.

### Secrets

This lab commits its credentials to Git: two Secrets in `manifests/base/03-lab-credentials.yaml` and a password hash in `helm/argocd-values.yaml`. That choice makes the lab reproducible and lets the README list the logins. It is acceptable only for a cluster that never leaves your laptop. On any shared cluster:

- Keep secret values out of Git. Use External Secrets Operator (reads from a cloud secret manager), Sealed Secrets (encrypted blobs in Git) or SOPS with age keys.
- Remember that a Kubernetes Secret is base64, not encryption. Turn on encryption at rest for the API server.
- Read a secret from a mounted file if it rotates. An environment variable is fixed at container start, which is why changing the Redis password here needs a pod restart.
- Limit who can read them. The `shop-developer` Role in `manifests/base/01-rbac.yaml` has no access to Secrets.
- Rotate anything that was ever committed. Git history keeps the old value.

### Pod hardening in this lab

Containers run as a non-root user with a read-only root filesystem, no Linux capabilities and the default seccomp profile. None of the apps call the Kubernetes API, so service account tokens are not mounted. The `shop` namespace enforces the Pod Security `baseline` level and warns on `restricted`.

### Observability

- Alert on symptoms such as error ratio and latency before causes such as CPU. The lab runs Alertmanager (http://localhost:9093) with no rules by default; [course module 23](../course/23-prometheus-and-alerting.md) adds an SLO with a burn-rate alert and routes it to a receiver.
- Keep dashboards in Git. The lab's dashboard is a ConfigMap that Grafana's sidecar loads, and Grafana refuses edits to it in the UI. [Course module 24](../course/24-grafana-as-code.md) builds an SLO dashboard the same way.
- The lab samples 100% of traces. Use 1 to 5% in production, plus tail sampling to keep error traces.
- The backend writes the trace id into every log line. Search your logs by `trace_id` and open the matching trace in Jaeger.
- Log in JSON, and logs turn into data. The Grafana dashboard **Shop logs** counts the backend's requests by status and computes p95 latency per path from its JSON log lines with LogQL (course module 6, step 5).
- Keep probes out of your traces. The backend excludes `/healthz`, `/readyz` and `/metrics` from tracing and drops the Redis `PING` spans its readiness probe would create.

## 7. Things to try next

1. Set `EXTRA_LATENCY_MS=200` on `backend-v2` (`kubectl -n shop set env deploy/backend-v2 EXTRA_LATENCY_MS=200`), run experiment A and compare p95 latency per version in Grafana. Then find a slow v2 trace in Jaeger.
2. Move the canary to 50/50, then to 0/100, and watch the dashboard follow.
3. Change `redis-allow-backend` in `manifests/istio/security.yaml` so it allows only the `frontend` service account. Push, wait for the sync and see what the backend's `/readyz` returns.
4. Add a second waypoint for the frontend and measure its memory with `kubectl top pods -n shop`.
5. Push a manifest with a deliberate typo to `main` and read how ArgoCD reports the failed sync.

For more depth on the platform tools, the course has a module each: [GitOps with ArgoCD](../course/22-gitops-with-argocd.md) runs its own Git server, so you practise drift, rollbacks, hooks, project guardrails and ApplicationSets without pushing to this repository. Then [Prometheus and alerting](../course/23-prometheus-and-alerting.md) and [Grafana as code](../course/24-grafana-as-code.md).
