# Troubleshooting record

These are the ten problems hit while building this lab, in the order they appeared. Each entry gives the symptom, the command that exposed the cause, the cause and the fix that is now in the repo. If you change versions or move to another cluster type, expect to meet some of them again.

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

## A note on watching long installs

Two habits would have shortened this build:

- Watch Warning events during the install, not only the script's exit code. Problems 2, 4 and 7 were visible in events minutes before any timeout.
- Test a monitoring one-liner once before relying on it. A watcher that fails silently looks identical to a healthy system.
