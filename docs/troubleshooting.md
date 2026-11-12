# Troubleshooting record

These are the problems hit while building and running this lab, in the order they appeared. Each entry gives the symptom, the command that exposed the cause, the cause and the fix that is now in the repo. If you change versions or move to another cluster type, expect to meet some of them again.

For the short list of common day-to-day issues, see the [README](../README.md#when-something-goes-wrong).

## Quick diagnosis commands

Start here when something is not working:

```bash
# Anything not running?
kubectl get pods -A | grep -vE "Running|Completed"

# What is Kubernetes complaining about?
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail -20

# What does ArgoCD think?
kubectl -n argocd get applications
```

The second command found most of the problems below. A pod that was never created does not appear in the first one, and ArgoCD can report Healthy while a ReplicaSet fails to create its pods.

## 1. istio-cni never becomes Ready on OrbStack's built-in Kubernetes

**Symptom.** `istio-cni-node` stays at 0/1 Ready and `provision.sh` times out.

**Found with.**

```bash
kubectl -n istio-system logs ds/istio-cni-node --tail=20
```

The log repeats `no networks found in /host/etc/cni/net.d` and `Waiting for CNI network config file to be written`.

**Cause.** Istio's CNI plugin adds itself to the node's existing CNI config file. OrbStack's built-in cluster has no such file in `/etc/cni/net.d`, so the installer waits forever.

**Fix.** The lab runs on a k3d cluster instead. OrbStack still provides the Docker engine. Whether OrbStack keeps its CNI config in another directory was not investigated.

## 2. ztunnel stuck in ContainerCreating

**Symptom.** `ztunnel` stays in `ContainerCreating` and Helm fails with `DaemonSet/istio-system/ztunnel not ready`.

**Found with.**

```bash
kubectl -n istio-system describe pod -l app=ztunnel | tail -5
```

The events say `plugin type="istio-cni" failed (add): failed to find plugin "istio-cni" in path [/bin]`.

**Cause.** containerd looks for CNI plugin binaries in one directory, and the Istio chart's k3s profile copies its binary to a different one. The directory depends on the k3s version: `/bin` on v1.31, `/var/lib/rancher/k3s/data/cni` on v1.35.

Confirm it on the node:

```bash
docker exec k3d-k8s-lab-server-0 grep bin_dir /var/lib/rancher/k3s/agent/etc/containerd/config.toml
kubectl -n istio-system get ds istio-cni-node \
  -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}{" -> "}{.hostPath.path}{"\n"}{end}' | grep bin
```

The two paths must match.

**Fix.** `provision.sh` reads `bin_dir` from the node and passes it to the chart as `cni.cniBinDir`. The key sits under `cni:` in the chart's values. A top-level `cniBinDir` is silently ignored, which `helm show values istio/cni` makes visible.

## 3. Helm upgrade fails with a webhook conflict

**Symptom.** A second run of `provision.sh` stops with `conflict occurred while applying object ... ValidatingWebhookConfiguration ... conflict with "pilot-discovery"`.

**Cause.** Helm 4 applies charts with server-side apply. istiod patches the `failurePolicy` field of its own validating webhook at runtime, so istiod owns a field the chart also sets, and the next `helm upgrade` is refused.

**Fix.** `provision.sh` adds `--force-conflicts` to the Istio charts when the installed Helm has that flag. Helm 3 does not need it.

## 4. Pods fail with "no IP addresses available"

**Symptom.** New pods stay in `ContainerCreating` with `plugin type="flannel" failed (add): failed to allocate for range 0: no IP addresses available`.

**Found with.**

```bash
docker exec k3d-k8s-lab-server-0 sh -c 'ls /var/lib/cni/networks/cbr0 | wc -l'
kubectl get pods -A --no-headers | wc -l
```

The first command returned 255 while only 6 pods existed.

**Cause.** A consequence of problem 2. For each sandbox attempt, flannel reserved an address and then the `istio-cni` step failed. The reservation was never released. The kubelet retried every few seconds until the node's /24 range was used up.

**Fix.** Delete and recreate the cluster (`./scripts/teardown.sh --yes`, then `./scripts/provision.sh`). With problem 2 fixed, no sandbox fails and nothing leaks.

## 5. Backend in CrashLoopBackOff

**Symptom.** All backend pods restart in a loop. The startup probe gets `connection refused`.

**Found with.**

```bash
kubectl -n shop logs deploy/backend-v1 --tail=5
```

`ValueError: invalid literal for int() with base 10: 'tcp://10.43.202.136:6379'`

**Cause.** For every Service, Kubernetes injects Docker-style link variables into pods in the same namespace. A Service named `redis` produces `REDIS_PORT=tcp://<ip>:6379`. The backend read `REDIS_PORT` and expected a number. Running the container outside Kubernetes never showed this.

**Fix.** The backend reads `REDIS_PORT_NUMBER`. Every Deployment also sets `enableServiceLinks: false`, which turns the injection off.

## 6. ArgoCD cannot compare kube-prometheus-stack

**Symptom.** The Application shows sync status `Unknown` with `error calculating structured merge diff ... .status.terminatingReplicas: field not declared in schema`.

**Found with.**

```bash
kubectl -n argocd get application kube-prometheus-stack -o jsonpath='{.status.conditions[*].message}'
```

**Cause.** k3d defaulted to Kubernetes 1.35. The ArgoCD version in this lab carries older API schemas and does not know the new Deployment status field. Istio 1.24 also supports Kubernetes only up to 1.31.

**Fix.** `provision.sh` pins the node image to `rancher/k3s:v1.31.5-k3s1` (override with `K3S_IMAGE`). Raise it only together with the Istio and ArgoCD versions.

## 7. Gateway and waypoint pods never appear

**Symptom.** `localhost:8080` does not answer. No gateway or waypoint pod exists, yet no pod is failing and ArgoCD shows every app as Healthy.

**Found with.**

```bash
kubectl get events -A --field-selector reason=FailedCreate
```

`pods "waypoint-..." is forbidden: maximum cpu usage per Container is 1, but limit is 2` and `exceeded quota: shop-ingress-quota, requested: limits.cpu=2`.

**Cause.** Istio creates the proxy Deployments with a default limit of 2 CPU and 1 GiB. The `shop` LimitRange capped containers at 1 CPU and 512 MiB, and the `shop-ingress` quota allowed 1 CPU of limits in total. The ReplicaSets could not create pods.

**Fix.** `manifests/base/02-quotas.yaml` now allows containers of 2 CPU and 1 GiB in `shop` and gives `shop-ingress` room for two gateway pods.

## 8. The rate limit experiment has no effect

**Symptom.** After `kubectl set env ... RATE_LIMIT_RPS=20`, every request still returns 200.

**Found with.**

```bash
kubectl -n shop get deploy backend-v1 \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RATE_LIMIT_RPS")].value}'
kubectl -n shop get pods -l app=backend
```

The value was back at `0` and the new pods were already terminating.

**Cause.** `shop-apps` self-heals. ArgoCD reverted the manual change within seconds, before the rollout finished.

**Fix.** The `shop-apps` Application lists `RATE_LIMIT_RPS` and `EXTRA_LATENCY_MS` under `ignoreDifferences` and sets `RespectIgnoreDifferences=true`. Manual changes to these two variables stay. Everything else on the Deployments is still reverted.

## 9. Jaeger fills with one-span PING traces

**Symptom.** The `backend` service in Jaeger lists mostly traces named `PING` with a single span.

**Cause.** The readiness probe calls `/readyz` every 5 seconds, which pings Redis. The HTTP span for `/readyz` is excluded from tracing, so the Redis span became a root span and was exported as its own trace.

**Fix.** The backend's span processor drops root-level `PING` spans (`DropProbeSpans` in `apps/backend/main.py`). A Redis `PING` inside a real request is still recorded.

## 10. The ArgoCD controller restarts during the first sync

**Symptom.** `argocd-application-controller-0` shows one restart, and the first sync takes longer than expected.

**Found with.**

```bash
kubectl -n argocd get pod argocd-application-controller-0 \
  -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}'
```

`OOMKilled`

**Cause.** The controller's memory limit was 512 MiB. Comparing the kube-prometheus-stack chart, with its large CRDs, pushed it over the limit. It recovered after the restart, so the install still finished.

**Fix.** `helm/argocd-values.yaml` sets the limit to 1 GiB. After the change the controller ran with zero restarts.

## 11. Everything breaks after a reboot or Docker restart

**Symptom.** After the Mac slept or rebooted, `localhost:8080` does not answer. Half the pods are not Ready: ztunnel, the gateway, the waypoint, the backends. CoreDNS shows `Unknown`.

**Found with.**

```bash
docker ps --filter name=k3d-k8s-lab --format '{{.Names}} {{.Status}}'
kubectl get events -A --field-selector type=Warning --sort-by=.lastTimestamp | tail
kubectl -n istio-system logs ds/ztunnel --tail=3
```

The containers were "Up 48 seconds", so Docker had just restarted them. The events said `configmap references non-existent config key: NodeHosts` for CoreDNS. ztunnel logged `dns error` while connecting to `istiod.istio-system.svc`.

**Cause.** When k3d starts a cluster, it adds a `NodeHosts` key to the CoreDNS ConfigMap. When Docker restarts the containers by itself, k3d is not involved, k3s rewrites the ConfigMap without that key, and the CoreDNS pod cannot mount it. With no cluster DNS, ztunnel cannot resolve istiod, gets no certificates or config, and every mesh pod fails its readiness check.

**Fix.** `./scripts/start.sh`. It runs `k3d cluster stop` and `k3d cluster start` when the key is missing, which lets k3d add it back, then waits for every pod. `provision.sh` calls the same script when the cluster already exists.

## 12. kubectl talks to the wrong cluster

**Symptom.** `./scripts/port-forward.sh` prints `namespaces "argocd" not found`, and course commands report that resources do not exist.

**Found with.**

```bash
kubectl config current-context
```

`orbstack`

**Cause.** When OrbStack restarts, it sets the current kubectl context to its own cluster.

**Fix.** `port-forward.sh` and the course scripts always pass `--context k3d-k8s-lab`. `start.sh` also switches the current context back, so plain `kubectl` commands you type reach the lab.

## 13. Grafana says Jaeger "plugin unavailable"

**Symptom.** The Jaeger data source's health check, and any query sent through Grafana's server API, fails with `[plugin.unavailable] plugin unavailable`.

**Cause.** Not a fault. In Grafana 11.3 the Jaeger data source runs in the browser and calls Jaeger through Grafana's proxy. There is no server-side part to answer a health check.

**Check it works.**

```bash
TRACE=$(curl -s "http://localhost:16686/api/traces?service=backend&limit=1&lookback=10m" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["traceID"])')
curl -s "http://admin:k8s-lab-admin@localhost:3000/api/datasources/proxy/uid/jaeger/api/traces/$TRACE" | head -c 200
```

A JSON trace means the data source works. In the browser, Explore with the Jaeger data source shows traces normally.

## 14. Request logs have no trace_id

**Symptom.** Jaeger has traces for the backend, but `kubectl -n shop logs deploy/backend-v1 | grep trace_id` finds nothing, so a trace cannot be matched to its logs.

**Cause.** The backend has two HTTP middlewares: the OpenTelemetry one that opens a span, and its own that writes the request log line. Starlette runs the middleware added last first. The tracing middleware was added first, so it ran inside the logging one: the span had already closed when the log line was written.

**Fix.** `apps/backend/main.py` instruments the app at the very end of the file, which makes tracing the outer middleware. Image `1.0.2` and later write `trace_id` and `span_id` into every request log.

## 15. One mesh pod never becomes Ready after a restart

**Symptom.** After the cluster restarted, one pod in `shop` (here the frontend) loops in `CrashLoopBackOff`. Its own logs look healthy: it starts, says it is listening, then gets `SIGTERM` 30 seconds later. The shop returns 503.

**Found with.**

```bash
kubectl -n shop describe pod -l app=frontend | tail -5
kubectl -n istio-system logs ds/ztunnel --tail=300 | grep frontend | grep error | tail -3
```

The pod events say `Startup probe failed: ... EOF`. ztunnel logs inbound connections from `src.addr=10.42.0.1` (the node, where the kubelet runs) to the frontend that fail with an error.

**Cause.** In ambient mode, `istio-cni` sets up traffic redirection inside each pod's network namespace and makes sure the kubelet's health probes bypass it. When the node container restarts, containerd recreates every pod's sandbox. A sandbox that comes back before the `istio-cni` agent is running again can end up with incomplete rules: ztunnel then captures the kubelet's plain probe as if it were mesh traffic, and the probe fails. The race hit one pod out of about twenty, once in three restarts.

**Fix.** Delete the pod. Its replacement is set up while `istio-cni` is running and becomes Ready at once:

```bash
kubectl -n shop delete pod -l app=frontend
```

`./scripts/start.sh` now does this by itself: if mesh pods are still not Ready after three minutes, it waits for `istio-cni` and ztunnel, recreates those pods once, and waits again.

## 16. Kiali restarts every few minutes

**Symptom.** `localhost:20001` stops answering while the other UIs still work. `port-forward.sh` lost its Kiali tunnel because the pod behind it was replaced. Kiali had six ReplicaSets after one hour.

**Found with.**

```bash
kubectl -n istio-system get rs -l app.kubernetes.io/name=kiali
kubectl -n istio-system get rs -o jsonpath='{range .items[*]}{.spec.template.metadata.annotations.checksum/config}{"\n"}{end}'
```

Every ReplicaSet had a different `checksum/config` annotation, and nothing in Git had changed.

**Cause.** When `login_token.signing_key` is empty, the Kiali chart generates a random one each time it renders. Helm renders once at install. ArgoCD renders on every poll, so each poll produced a new ConfigMap, a new checksum, a new pod template and a rollout.

**Fix.** `helm/kiali-values.yaml` sets a fixed 32-character `signing_key`. The same trap exists in any chart that calls `randAlphaNum` in a template: under ArgoCD, set the value yourself. After a rollout, restart `./scripts/port-forward.sh`.

## A note on watching long installs

Two habits would have shortened this build:

- Watch Warning events during the install, not only the script's exit code. Problems 2, 4 and 7 were visible in events minutes before any timeout.
- Test a monitoring one-liner once before relying on it. A watcher that fails silently looks identical to a healthy system.
