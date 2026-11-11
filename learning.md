# Learning guide

Concepts first, then a hands-on playbook, then production practices. Every command assumes you ran `./scripts/provision.sh` and you are in the repository root.

## 1. Istio ambient mode and sidecars

### The difference in one picture

A sidecar mesh puts one Envoy in every pod. An ambient mesh splits the work in two layers.

| | Sidecar mode | Ambient mode |
|---|---|---|
| L4 (mTLS, identity, TCP policy) | Envoy in each pod | `ztunnel`, one per node |
| L7 (HTTP routing, retries, faults) | Envoy in each pod | `waypoint`, only where you ask for it |
| Pod restart to join the mesh | Yes, to inject the sidecar | No, label the namespace |
| Per-pod overhead | An Envoy, typically 50 to 150 MiB | None |
| Application containers see | Iptables rules from an init container | Traffic redirected by `istio-cni` outside the pod |

### Why ztunnel saves RAM on a k3d node

The k3s node runs as one container in the OrbStack VM, so all pods share that VM. Every sidecar costs memory in that VM whether the pod needs HTTP features or not.

- This lab runs 6 pods in `shop` and about 8 in `observability`. With sidecars that is 14 Envoy processes. At roughly 60 MiB each, that is about 840 MiB.
- With ambient mode there is one ztunnel (set to request 64 MiB) plus one waypoint for the namespace (default request 64 MiB). The total is roughly 130 MiB.
- The saving grows with every pod you add, because ztunnel does not scale with pod count.
- Sidecars also add startup time, which matters when you recreate the cluster often.

You can measure it. The dashboard panel "ztunnel memory per node" shows the real number. Compare it with `kubectl top pods -A`.

### What each layer does here

- ztunnel handles identity (SPIFFE certificates per service account), mTLS between pods, `PeerAuthentication` and L4 `AuthorizationPolicy`. Redis traffic stops at this layer.
- The waypoint handles everything that reads HTTP. The backend Services carry the label `istio.io/use-waypoint: waypoint`, so only they pay for L7.
- Traffic between ztunnel and a waypoint uses HBONE, an HTTP/2 CONNECT tunnel on port 15008 with mTLS inside.

### Trade-offs

- A waypoint is a shared proxy. A noisy backend can slow a neighbor behind the same waypoint. Give busy services their own waypoint.
- L7 policy applies only to Services bound to a waypoint. A policy aimed at a Service without a waypoint does nothing.
- Some Envoy extensions (`EnvoyFilter`, Wasm) have limited support on waypoints. Check the Istio docs for your version.

## 2. GitOps with ArgoCD

### Declarative state

You describe the desired cluster state in Git. ArgoCD compares Git with the live cluster and reports the difference. You never run `kubectl apply` for the managed parts. You commit.

This repository uses the app-of-apps pattern. `manifests/argocd/root-app.yaml` points at a folder of Application objects. Adding a file to `manifests/argocd/apps/` creates a new Application on the next sync.

### Drift detection

Drift means the live state no longer matches Git. Try it:

```bash
kubectl -n shop scale deploy/frontend --replicas=3
kubectl -n argocd get application shop-apps
```

`shop-apps` has `selfHeal: true`, so ArgoCD resets the replica count to 1 within a few seconds. The `istio-config` Application has `selfHeal: false`. Apply a scenario by hand and the Application turns `OutOfSync` but keeps your experiment. See the difference:

```bash
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml
kubectl -n argocd get application istio-config
```

Return to the Git state with `kubectl -n argocd patch application istio-config --type merge -p '{"operation":{"sync":{}}}'`, or press Sync in the UI.

### Sync options used here

- `automated.prune` deletes cluster objects that you removed from Git. It is off for `shop-base` so a bad commit cannot delete a namespace.
- `ServerSideApply=true` is required for the large CRDs in kube-prometheus-stack.
- `SkipDryRunOnMissingResource=true` lets `observability-config` apply ServiceMonitors before the CRDs exist, then retry.
- Sync waves order the Applications. Namespaces first (wave 0), workloads and the monitoring chart next (wave 1), Istio config and monitors last (wave 2).

### Changing the lab through Git

```bash
git checkout -b canary-20
# edit manifests/istio/backend-route.yaml and set weights 80 and 20
git commit -am "Send 20 percent of backend traffic to v2"
git push origin canary-20
# open a pull request, merge to main
argocd app sync istio-config   # or wait for the poll, about 3 minutes
```

## 3. Playbook

### 3.1 Run the three scenarios

Open the UI at http://localhost:8080 or use the script. Start the port-forwards in another terminal with `./scripts/port-forward.sh` so Grafana is available.

Scenario A, canary 90/10:

```bash
kubectl apply -f manifests/scenarios/a-canary-httproute.yaml
./scripts/traffic-test.sh 200
```

Expect about 180 responses from `v1` and 20 from `v2`. Grafana panel "Backend request rate by workload" shows the split.

Scenario B, fault injection on `/api/orders`:

```bash
kubectl -n shop delete httproute backend-route
kubectl apply -f manifests/scenarios/b-fault-injection.yaml
./scripts/traffic-test.sh 200
```

Expect about 20 responses with status 503 and an average latency above 500 ms. The 503 responses carry no `x-app-version` header because the waypoint answers them. Find a delayed request in Jaeger under the `backend` service. Revert with:

```bash
kubectl delete -f manifests/scenarios/b-fault-injection.yaml
kubectl apply -f manifests/istio/backend-route.yaml
```

Scenario C, circuit breaking and rate limiting:

```bash
kubectl apply -f manifests/scenarios/c-circuit-breaker.yaml
./scripts/traffic-test.sh 200 50 "/api/slow?ms=300"
```

With 50 concurrent requests against a limit of 5 connections plus 5 queued requests, most responses are 503 and come back fast. Then try the rate limiter:

```bash
kubectl delete -f manifests/scenarios/c-circuit-breaker.yaml
kubectl -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=20
./scripts/traffic-test.sh 200 20
kubectl -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=0
```

Status 429 responses show the in-app limiter at work. Note that `kubectl set env` changes the Deployment, so `shop-apps` (self-heal on) reverts it on its own. That is the drift detection from section 2 applied to your own experiment.

### 3.2 Add a new service

Example, a `payments` service in `shop`.

1. Create `apps/payments/` with a `Dockerfile` and the code. Use the backend as a template.
2. Build the image with `docker build -t k8s-lab/payments:1.0.0 apps/payments`, then load it into the cluster with `k3d image import k8s-lab/payments:1.0.0 -c k8s-lab`.
3. Create `manifests/apps/payments.yaml` with a ServiceAccount, a Deployment and a Service. Copy the security context, probes and resource blocks from `backend.yaml`. Give the Service a port named `http` and the label `metrics: scrape` so Prometheus finds it.
4. To get L7 features, add the label `istio.io/use-waypoint: waypoint` to the Service. Leave it off for plain TCP services.
5. Add an `AuthorizationPolicy` in `manifests/istio/security.yaml` that names the callers by service account.
6. Check that the namespace quota has room: `kubectl -n shop describe resourcequota shop-quota`.
7. Commit and push. `shop-apps` picks up the new file on the next poll.

### 3.3 Change the canary percentage

Live, for an experiment:

```bash
kubectl -n shop patch httproute backend-route --type json -p '[
  {"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
  {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}
]'
```

Through Git, for a change you keep: edit the two `weight` values in `manifests/istio/backend-route.yaml`, commit and push. Weights are relative, so `1` and `1` also gives 50/50. A weight of `0` keeps the route defined but sends no traffic, which is how the baseline parks v2.

### 3.4 Debug mTLS connection drops with istioctl

Install the CLI matching your control plane:

```bash
brew install istioctl
istioctl version
```

Work from the outside in.

1. Confirm the namespace and pods are in the mesh.

   ```bash
   kubectl get ns shop --show-labels | grep dataplane-mode
   istioctl ztunnel-config workloads | grep -E 'shop|NAMESPACE'
   ```

   The PROTOCOL column must say `HBONE`. `TCP` means the pod is not enrolled. Restart the pod after labeling the namespace if a pod predates the label.

2. Check that the waypoint is attached and programmed.

   ```bash
   istioctl waypoint list -n shop
   kubectl -n shop get gateway waypoint
   istioctl ztunnel-config services | grep backend
   ```

   The WAYPOINT column for `backend` must show `waypoint`.

3. Look at the identity and certificate of a workload.

   ```bash
   istioctl ztunnel-config certificates
   ```

   Look for an expired or missing certificate for `spiffe://cluster.local/ns/shop/sa/backend`. If `istiod` is down, certificates stop renewing.

4. Read ztunnel logs. A dropped connection shows a reason.

   ```bash
   kubectl -n istio-system logs ds/ztunnel --tail=100 | grep -iE 'denied|error|rbac|tls'
   ```

   `connection closed due to policy rejection` points at an AuthorizationPolicy. `unknown source` or a handshake error points at a non-enrolled client talking to a STRICT workload.

5. Test the policy directly. From a pod that is not the frontend:

   ```bash
   kubectl -n shop run probe --rm -it --restart=Never --image=curlimages/curl:8.11.1 -- \
     curl -sv http://backend:8000/api/version
   ```

   The `backend-allow-frontend` policy must return `403 RBAC: access denied` from the waypoint. A plain connection reset means the L4 layer rejected it first.

6. Inspect the waypoint config when routing looks wrong.

   ```bash
   istioctl proxy-config routes deploy/waypoint -n shop
   istioctl proxy-config clusters deploy/waypoint -n shop | grep backend
   kubectl -n shop logs deploy/waypoint --tail=50
   ```

7. Validate the whole config for the namespace.

   ```bash
   istioctl analyze -n shop
   ```

   A conflict between an `HTTPRoute` and a `VirtualService` for the same host shows up here.

8. Turn on debug logging for a short time, then turn it off.

   ```bash
   istioctl admin log ztunnel --level debug
   istioctl admin log ztunnel --level info
   ```

Common causes, in the order they happen: namespace label missing, pod started before the label, STRICT mode with a client outside the mesh, an AuthorizationPolicy that names the wrong service account, a waypoint pod that is not Ready, and a time skew between the OrbStack VM and the host after a laptop sleep (restart the VM with `orb restart`, then run `k3d cluster start k8s-lab`).

## 4. Production practices

### Resource constraints

- Set requests and limits on every container. Quotas reject pods without them, and the LimitRange fills in the gaps for third-party charts.
- Requests drive scheduling. Limits drive throttling and OOM kills. Keep memory limit close to the request, because memory is not compressible.
- Python and Node processes stay near their steady size, so a limit 2 times the request is plenty. Redis uses `--maxmemory` below its container limit so it evicts keys and does not get OOM-killed.
- Do not set a CPU limit lower than what the startup needs. A throttled startup fails its probe and loops.

### Probes

The backend and frontend use all three:

- `startupProbe` gives the app up to 40 seconds to boot and disables the other two while it runs.
- `readinessProbe` removes a pod from Service endpoints when a dependency fails. The backend checks Redis on `/readyz`, so a Redis outage drains backends instead of serving errors.
- `livenessProbe` restarts a stuck process. It checks only the process (`/healthz`) and never a dependency. A liveness probe on Redis health would restart every backend during a Redis outage and make it worse.

Probe endpoints are excluded from tracing and request metrics, so they do not flood Jaeger.

### Secrets

- Never commit a Secret. The lab creates them in `provision.sh` from `openssl rand`.
- Secrets in Kubernetes are base64, not encrypted. Enable encryption at rest on the API server in a real cluster.
- For GitOps with secrets, use one of these:
  - External Secrets Operator, which reads from a cloud secret manager and creates the Secret in the cluster.
  - Sealed Secrets, which stores an encrypted blob in Git that only the cluster can decrypt.
  - SOPS with age keys and the ArgoCD SOPS plugin.
- Mount secrets as environment variables only for values read once at boot. Use a mounted file for anything that rotates.
- Restrict who can read them. The `shop-developer` Role in `01-rbac.yaml` has no access to `secrets`.

### Pod hardening used here

- Non-root user, read-only root filesystem, all capabilities dropped, `RuntimeDefault` seccomp profile.
- `automountServiceAccountToken: false`, since none of the apps call the Kubernetes API.
- Pod Security Admission at `baseline` enforce and `restricted` warn on `shop`.

### Observability habits

- Alert on symptoms (error ratio, latency) before causes (CPU).
- Keep trace sampling at 100% only in a lab. In production, use 1 to 5% and tail sampling for errors.
- Put the trace id in every log line. The backend does this already. In Grafana, search logs by `trace_id` and open the trace in Jaeger.

## 5. Exercises

1. Raise the v2 weight to 50 and compare p95 latency per version in Grafana. Both versions run the same code, so the numbers should match until you set `EXTRA_LATENCY_MS` on one of them.
2. Set `EXTRA_LATENCY_MS=200` on `backend-v2`, run Scenario A, and find the slow traces in Jaeger.
3. Delete the `redis-allow-backend` policy, then apply a copy that allows only the `frontend` service account. Observe what the backend `/readyz` returns.
4. Add a second waypoint for `frontend` and measure the extra memory with `kubectl top pods -n shop`.
5. Break the `main` branch on purpose with an invalid manifest and read how ArgoCD reports the failed sync.
