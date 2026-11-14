# CKS mock exam 3

> New to a term here? The [glossary](../../platform-engineering/glossary.md#cks-exam-track) explains every term this track uses.

**Before this mock exam:** [mock exam 2](mock-exam-2.md) under time. The [practice cluster](../README.md#the-practice-cluster) and the [Lima VM](../README.md#the-lima-vm-for-apparmor-and-cilium), both freshly reset.

This is the hardest of the three. When the clock starts, the API server refuses to start, the scheduler and the controller manager crash, every caller is cluster admin, and Secrets sit encrypted with a key you're asked to retire. Nothing tells you which of those to fix first, except the order in which the layers depend on each other. You get 2 hours for 17 tasks worth 100 points, on the OrbStack cluster and the Lima VM.

## Rules

1. Start fresh. On your Mac:

   ```bash
   ./certs/cks/cluster/reset.sh && ./certs/cks/cluster/lima.sh reset
   MOCK=3 ./certs/cks/mock-exam/setup.sh
   ```

   In the final test run, the OrbStack reset took 3 minutes 7 seconds, the Lima reset 1 minute 54 seconds, and the setup 1 minute 13 seconds. The setup breaks the control plane in its last steps, so it doesn't wait for any pods.

2. The clock starts when `setup.sh` ends, and `score.sh` prints the minutes since then.
3. Work only on the nodes: `orb -m cks-cp`, `orb -m cks-w1` and `./certs/cks/cluster/lima.sh shell`. Use only the documentation the exam allows.
4. Don't open the solutions while the clock runs.
5. Score from your Mac: `MOCK=3 ./certs/cks/mock-exam/score.sh`, or single tasks with `MOCK=3 ./certs/cks/mock-exam/score.sh 1 13`.

## Tasks

| # | Task | Points | Domain | Host |
|---|---|---|---|---|
| 1 | Pods stay Pending | 8 | 02 | cks-cp |
| 2 | One port range, two selectors | 5 | 01 | cks-cp |
| 3 | Keep a job off the internet | 6 | 01 | cks-lima |
| 4 | CIS findings and etcd TLS | 6 | 01 | cks-cp |
| 5 | An Ingress for two hosts | 4 | 01 | cks-cp |
| 6 | A role that grows by itself | 6 | 02 | cks-cp |
| 7 | Old tokens and mounted ones | 5 | 02 | cks-cp |
| 8 | Everyone is admin | 5 | 02 | cks-cp |
| 9 | SSH the right way | 4 | 03 | cks-w1 |
| 10 | Kernel modules nobody needs | 4 | 03 | cks-lima |
| 11 | Rotate to a new provider | 8 | 04 | cks-cp |
| 12 | gVisor where it exists | 5 | 04 | cks-cp |
| 13 | The API server doesn't start | 8 | 05 | cks-cp |
| 14 | Delete what's vulnerable | 5 | 05 | cks-cp |
| 15 | Tune Falco and act on it | 8 | 06 | cks-w1, cks-cp |
| 16 | An audit policy for one team | 7 | 06 | cks-cp |
| 17 | seccomp and a read-only root | 6 | 06 | cks-w1, cks-cp |

### Task 1: Pods stay Pending (8 points)

**Host:** `cks-cp`.

> Deployment `shop` in namespace `m3-app` must scale to 4 replicas, and the new pods never appear. Repair the control plane. Don't change what the components did before somebody edited them.

<details>
<summary>Solution</summary>

`kubectl` itself fails at first, because of task 13. Fix that first, then:

```bash
k -n kube-system get pods -l tier=control-plane
k -n kube-system logs kube-controller-manager-cks-cp | tail -2
k -n kube-system logs kube-scheduler-cks-cp | tail -2
```

In the test run, the scheduler said:

```
Error: invalid argument "127.0.0.1:10259" for "--bind-address" flag: failed to parse IP: "127.0.0.1:10259"
```

and the controller manager, once the API server answered again:

```
"Error building controllers" err="error parsing root-ca-file at /etc/kubernetes/pki/ca.pem: open /etc/kubernetes/pki/ca.pem: no such file or directory"
```

Somebody added a second `--bind-address` line with a port in it; the last copy of a flag wins, and a bind address takes an IP only. Delete that line from `kube-scheduler.yaml`, and set `--root-ca-file=/etc/kubernetes/pki/ca.crt` in `kube-controller-manager.yaml`. The controller manager first, because without it the Deployment gets no new ReplicaSet pods, and new namespaces get no `default` ServiceAccount either. Then `k -n m3-app scale deploy shop --replicas=4`.

</details>

### Task 2: One port range, two selectors (5 points)

**Host:** `cks-cp`.

> Pod `metrics` in namespace `m3-svc` listens on TCP 9100, 9150, 9200 and 9300. Create a NetworkPolicy `metrics-scrape` so that only pods labelled `app=prometheus` in namespaces labelled `team=observability` reach it, and only on ports 9100 to 9200. Use one port entry.

<details>
<summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: metrics-scrape, namespace: m3-svc}
spec:
  podSelector: {matchLabels: {app: metrics}}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {team: observability}}
      podSelector: {matchLabels: {app: prometheus}}
    ports: [{protocol: TCP, port: 9100, endPort: 9200}]
```

Two traps are checked: `grafana` sits in the right namespace with the wrong label, and a `prometheus` pod sits in a namespace without the label. Both stay out only with the two selectors in one item.

</details>

### Task 3: Keep a job off the internet (6 points)

**Host:** `cks-lima`.

> In namespace `m3-egress`:
>
> 1. CiliumNetworkPolicy `no-world` denies egress from every pod to everything outside the cluster.
> 2. Pod `job` may reach the Kubernetes API server, pod `web` on TCP port 80, and DNS. Nothing else, not even pod `other`. Name the policy as you like.

<details>
<summary>Solution</summary>

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: no-world, namespace: m3-egress}
spec:
  endpointSelector: {}
  egressDeny: [{toEntities: [world]}]
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: job-egress, namespace: m3-egress}
spec:
  endpointSelector: {matchLabels: {app: job}}
  egress:
  - toEntities: [kube-apiserver]
  - toEndpoints: [{matchLabels: {app: web}}]
    toPorts: [{ports: [{port: "80", protocol: TCP}]}]
  - toEndpoints: [{matchLabels: {k8s:io.kubernetes.pod.namespace: kube-system, k8s-app: kube-dns}}]
    toPorts: [{ports: [{port: "53", protocol: ANY}]}]
```

[01, task 11](01-cluster-setup.md#task-11-entities-and-an-explicit-deny-with-cilium) explains entities and deny rules.

</details>

### Task 4: CIS findings and etcd TLS (6 points)

**Host:** `cks-cp`.

> Fix kube-bench checks 1.2.15 and 1.3.2 on `cks-cp`. Also make etcd accept only TLS 1.3. The control plane keeps running.

<details>
<summary>Solution</summary>

`--profiling=false` in the API server and controller manager manifests, and `--tls-min-version=TLS1.3` in etcd's. Change etcd first and wait for it, then the API server, as [01, task 12](01-cluster-setup.md#task-12-tls-versions-and-ciphers-for-the-api-server-and-etcd) explains. Confirm with `kube-bench run --targets master --check 1.2.15,1.3.2`.

</details>

### Task 5: An Ingress for two hosts (4 points)

**Host:** `cks-cp`.

> Namespace `m3-web` runs Services `shop` and `blog` on port 80. `/root/mock/m3.crt` and `/root/mock/m3.key` hold one certificate for both `shop.m3.local` and `blog.m3.local`. Create an Ingress `sites` with class `nginx` that serves both hosts over HTTPS with it.

<details>
<summary>Solution</summary>

```bash
k -n m3-web create secret tls m3-tls --cert=/root/mock/m3.crt --key=/root/mock/m3.key
k -n m3-web create ingress sites --class=nginx \
  --rule="shop.m3.local/*=shop:80,tls=m3-tls" --rule="blog.m3.local/*=blog:80,tls=m3-tls"
curl -sk --resolve blog.m3.local:30443:127.0.0.1 https://blog.m3.local:30443/
```

One `tls` entry lists both hosts with the same Secret. The certificate's subject alternative names cover both, so the controller serves it for each.

</details>

### Task 6: A role that grows by itself (6 points)

**Host:** `cks-cp`.

> ServiceAccount `viewer` in namespace `m3-ops` is bound to the aggregated ClusterRole `ops-view`. It may read Secrets, and it must not. It must also list Deployments in every namespace. Keep `ops-view` aggregating, and keep everything else `viewer` reads.

<details>
<summary>Solution</summary>

```bash
k get clusterrole -l rbac.m3/aggregate=true
k get clusterrole ops-config -o yaml        # configmaps and secrets
```

Remove `secrets` from `ops-config`, so ConfigMaps stay readable, and add a labelled ClusterRole for Deployments:

```bash
k edit clusterrole ops-config                 # resources: [configmaps]
k create clusterrole ops-deploys --verb=get,list,watch --resource=deployments.apps $do > d.yaml
vim d.yaml                                    # labels: {rbac.m3/aggregate: "true"}
k apply -f d.yaml
```

Deleting `ops-config` would remove the Secrets too, and take ConfigMaps with it, which the check catches. [02, task 5](02-cluster-hardening.md#task-5-aggregated-clusterroles) has the theory.

</details>

### Task 7: Old tokens and mounted ones (5 points)

**Host:** `cks-cp`.

> In namespace `m3-ci`, delete every legacy service account token Secret. Make ServiceAccount `builder` mount no token by default, and make pod `build` run again without one. Keep the pod's name.

<details>
<summary>Solution</summary>

```bash
k -n m3-ci delete secret --field-selector type=kubernetes.io/service-account-token
k -n m3-ci patch sa builder -p '{"automountServiceAccountToken": false}'
k -n m3-ci get pod build -o yaml > build.yaml
vim build.yaml           # delete the kube-api-access volume and its volumeMount
k -n m3-ci replace --force -f build.yaml
```

A running pod keeps its token, so it needs recreating. The exported YAML spells out the `kube-api-access-...` volume the API server added. Left in, it mounts the token whatever the ServiceAccount says, so delete it and its mount.

</details>

### Task 8: Everyone is admin (5 points)

**Host:** `cks-cp`.

> Every authenticated caller may do anything. Restore the authorizers kubeadm sets.

<details>
<summary>Solution</summary>

`--authorization-mode=Node,RBAC`, as in [02, task 12](02-cluster-hardening.md#task-12-an-api-server-that-allows-everything).

</details>

### Task 9: SSH the right way (4 points)

**Host:** `cks-w1`.

> sshd on `cks-w1` must refuse root logins and password logins, and forward no X11. It keeps running.

<details>
<summary>Solution</summary>

```bash
sshd -T | grep -E '^(permitrootlogin|passwordauthentication|x11forwarding) '
grep -rnE '^(PermitRootLogin|PasswordAuthentication|X11Forwarding)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
```

All three come from `/etc/ssh/sshd_config.d/05-vendor.conf`, which sshd reads before the main file. Set each to `no` there, then `sshd -t && systemctl restart ssh`.

</details>

### Task 10: Kernel modules nobody needs (4 points)

**Host:** `cks-lima`.

> Unload the kernel modules `udf` and `dccp` on `cks-lima`, and make every later load fail. Use a file under `/etc/modprobe.d/`.

<details>
<summary>Solution</summary>

`install udf /bin/false`, `blacklist udf`, and the same two lines for `dccp`, in a file such as `/etc/modprobe.d/m3.conf`, then `modprobe -r udf dccp`. [03, task 7](03-system-hardening.md#task-7-keep-a-kernel-module-out) explains both lines.

</details>

### Task 11: Rotate to a new provider (8 points)

**Host:** `cks-cp`.

> The API server encrypts Secrets with the `aescbc` key `legacy` from `/etc/kubernetes/enc/m3.yaml`. Move every Secret to a new `secretbox` key named `new`, then remove the `aescbc` provider from the file.

<details>
<summary>Solution</summary>

The same four steps as [04, task 5](04-minimize-microservice-vulnerabilities.md#task-5-rotate-the-encryption-key), with a new provider instead of a new key. Put `secretbox` first and keep `aescbc` below it:

```yaml
  providers:
  - secretbox:
      keys:
      - name: new
        secret: <head -c 32 /dev/urandom | base64>
  - aescbc:
      keys:
      - name: legacy
        secret: <unchanged>
  - identity: {}
```

Restart the API server, run `k get secrets -A -o json | k replace -f -`, delete the `aescbc` block, and restart again. etcdctl then shows `k8s:enc:secretbox:v1:new:` for every Secret.

</details>

### Task 12: gVisor where it exists (5 points)

**Host:** `cks-cp`.

> Label `cks-w1` with `runtime=gvisor`. Create a RuntimeClass `sandbox` for the handler `runsc` that sends its pods only to nodes with that label, and pod `scan` in namespace `m3-sbx` (image `busybox:1.36`, command `sleep 1d`) that uses it.

<details>
<summary>Solution</summary>

`scheduling.nodeSelector: {runtime: gvisor}` in the RuntimeClass, as in [04, task 9](04-minimize-microservice-vulnerabilities.md#task-9-a-sandbox-only-on-the-nodes-that-have-it). `k -n m3-sbx exec scan -- dmesg` starts with `Starting gVisor...`.

</details>

### Task 13: The API server doesn't start (8 points)

**Host:** `cks-cp`.

> A colleague turned on ImagePolicyWebhook with the configuration `/etc/kubernetes/admission/m3.yaml`, and the API server hasn't answered since. Get it running with the plugin on and `defaultAllow: false`. The back end and its kubeconfig sit in `/etc/kubernetes/policy-webhook/`.

<details>
<summary>Solution</summary>

```bash
crictl ps -a --name kube-apiserver
crictl logs <id of the newest exited container>
```

In the test run, the log ended with:

```
"command failed" err="failed to apply admission: couldn't init admission plugin \"ImagePolicyWebhook\": stat /etc/kubernetes/policy-webhook/kube.yaml: no such file or directory"
```

`ls /etc/kubernetes/policy-webhook/` shows `kubeconfig.yaml`, so fix `kubeConfigFile` in `/etc/kubernetes/admission/m3.yaml`. The API server still doesn't start, with the same `stat ... no such file or directory`, now for the right file name: the colleague mounted `/etc/kubernetes/admission` into the pod, but not `/etc/kubernetes/policy-webhook`. Add a `volumeMount` and a `hostPath` volume for it, as [05, task 5](05-supply-chain-security.md#task-5-allow-only-approved-registries) shows. Do this task first: until the API server runs, no other task on `cks-cp` works.

</details>

### Task 14: Delete what's vulnerable (5 points)

**Host:** `cks-cp`.

> Delete every Deployment in namespace `m3-prod` whose image has at least one CRITICAL vulnerability, as trivy reports it. Keep the others.

<details>
<summary>Solution</summary>

```bash
k -n m3-prod get deploy -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
for img in redis:6.0.5 nginx:1.27-alpine registry.k8s.io/pause:3.10 busybox:1.36; do
  echo "$img $(trivy image --quiet --severity CRITICAL $img | grep -m1 Total)"
done
```

In the test run, trivy found 22 CRITICAL findings in `redis:6.0.5` and 3 in `nginx:1.27-alpine`, and none in the other two. So delete `session` and `front`:

```bash
k -n m3-prod delete deploy session front
```

The check runs trivy itself and compares, so it still agrees with you after the database changes. A fairly new image such as `nginx:1.27-alpine` has findings too; the task asks about CRITICAL ones, not about age.

</details>

### Task 15: Tune Falco and act on it (8 points)

**Hosts:** `cks-w1`, then `cks-cp`.

> 1. Without editing `/etc/falco/falco_rules.yaml`, raise the priority of Falco's rule `Search Private Keys or Passwords` to `ALERT`.
> 2. A Deployment in namespace `m3-run` searches files for private keys. Find it through that rule, write its name to `/root/mock/key-hunter.txt` on `cks-cp`, and scale it to 0.

<details>
<summary>Solution</summary>

```yaml
# /etc/falco/rules.d/m3.yaml on cks-w1
- rule: Search Private Keys or Passwords
  priority: ALERT
  override:
    priority: replace
```

```bash
journalctl -u falco-modern-bpf --since -2min | grep 'Alert Grep private keys' | grep -o 'k8s_pod_name=[^ ]*' | tail -1
```

The pod's `app` label names the Deployment `indexer`:

```bash
k -n m3-run get pod <pod> --show-labels
echo indexer > /root/mock/key-hunter.txt
k -n m3-run scale deploy indexer --replicas=0
```

`indexer` runs `grep -rs "BEGIN RSA PRIVATE" /etc` in a loop, which matches the rule's macro `private_key_or_password`. The alert line starts with the new priority, `Alert`, once the override has loaded.

</details>

### Task 16: An audit policy for one team (7 points)

**Host:** `cks-cp`.

> Turn on audit logging with the policy `/etc/kubernetes/audit/m3-policy.yaml` and the log `/var/log/kubernetes/audit/m3.log`:
>
> 1. Secrets anywhere at `Metadata`.
> 2. Deployments in namespace `m3-audit` at `RequestResponse` when a member of the group `cks-users` sends the request, and at `Metadata` for everybody else.
> 3. Nothing else.

<details>
<summary>Solution</summary>

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: Metadata
  resources: [{group: "", resources: [secrets]}]
- level: RequestResponse
  userGroups: [cks-users]
  namespaces: [m3-audit]
  resources: [{group: apps, resources: [deployments]}]
- level: Metadata
  namespaces: [m3-audit]
  resources: [{group: apps, resources: [deployments]}]
- level: None
```

Deployments live in the API group `apps`, not in the core group `""`. With `group: ""`, the rule never matches a Deployment. The flags and the two volumes follow [06, task 1](06-monitoring-logging-runtime-security.md#task-1-turn-on-audit-logging).

</details>

### Task 17: seccomp and a read-only root (6 points)

**Hosts:** `cks-w1`, then `cks-cp`.

> `/root/mock/no-mkdir.json` on `cks-w1` is a seccomp profile that blocks `mkdir`. Install it as `m3.json` in the kubelet's seccomp folder. Create pod `locked` in namespace `m3-sec` on `cks-w1` (image `busybox:1.36`, command `sleep 1d`) with that profile, a read-only root file system, and an `emptyDir` at `/data`.

<details>
<summary>Solution</summary>

```bash
cp /root/mock/no-mkdir.json /var/lib/kubelet/seccomp/m3.json          # on cks-w1
```

```yaml
apiVersion: v1
kind: Pod
metadata: {name: locked, namespace: m3-sec}
spec:
  nodeName: cks-w1
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
    securityContext:
      readOnlyRootFilesystem: true
      seccompProfile: {type: Localhost, localhostProfile: m3.json}
    volumeMounts: [{name: data, mountPath: /data}]
  volumes: [{name: data, emptyDir: {}}]
```

`k -n m3-sec exec locked -- mkdir /data/d` fails with `Operation not permitted`, while `echo ok > /data/f` works. The read-only root alone would allow both in `/data`; the seccomp profile makes the difference.

</details>

## Scoring

`score.sh` runs two to five checks per task, splits the task's points evenly over them, rounded down, and gives points only when a task's first check passes.

In the final test run, on clusters fresh from both resets and `setup.sh`, the score was `TOTAL: 0 of 100 points (0%).` with `TIME: 3 minutes since setup, 117 minutes left.` After `MOCK=3 ./certs/cks/mock-exam/solve.sh`, which applies every solution above in its order (13, 8, 1, 11, 4, 16, then the rest) in 7 minutes 47 seconds, it was `TOTAL: 100 of 100 points (100%).` The solve order is the lesson: the API server first, then the authorizer that keeps restarting it, then the scheduler and controller manager, and only then everything that needs a working cluster.

Three things broke the first test runs of this mock, and each became part of the text. Under `AlwaysAllow`, the API server's health probes get `401`, so the kubelet kills it every few minutes. Without a controller manager, a new namespace gets no `default` ServiceAccount, so no pod starts in it. And a check that asks "is it gone?" passes on a dead API server, so every such check here also asks the API server something that must succeed.
