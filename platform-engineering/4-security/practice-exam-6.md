# Timed practice exam 6: security, a broken control plane

> New to a term here? The [glossary](../glossary.md#the-practice-cluster-and-the-security-modules) explains every term the security modules use.

**Before this practice exam:** [practice exam 5](practice-exam-5.md) under time, and the [practice cluster](../practice-cluster.md) and the [Lima VM](../../README.md#the-vm-for-the-kernel-tasks), both freshly reset.

This is the hardest of the three. When the clock starts, the API server refuses to start, the scheduler and the controller manager crash, every caller is cluster admin, and Secrets sit encrypted with a key you're asked to retire. Nothing tells you which of those to fix first, except the order in which the layers depend on each other, so reading that order is part of the test. You get 2 hours for 17 tasks worth 100 points, on the OrbStack cluster and the Lima VM.

## Rules

1. Start fresh, with both resets and the setup on your Mac:

   ```console
   $ ./lab.sh practice reset && ./platform-engineering/practice/cluster/lima.sh reset
   Deleting cluster "practice" ...
   ...
   === 1/6 node image practice-node:v1.37.1
   ...
   === 6/6 ingress-nginx 1.15.1 on NodePorts 30080 and 30443
   ...
   === ready
   ...
   === wiping the cluster on cks-lima
   ...
   === 4/4 Cilium 1.20.4
   ...
   cluster ready
   $ ./lab.sh exam setup 6
   == setting up task 11: Rotate to a new provider
   == setting up task 2: One port range, two selectors
   ...
   Ready. The clock runs from now: 2 hours. Open platform-engineering/4-security/practice-exam-6.md.
   Score yourself at any time with ./lab.sh exam score 6
   ```

   In the final test run, the practice cluster reset took 95 seconds, the Lima reset 2 minutes 6 seconds, and the setup 1 minute 26 seconds. The setup breaks the control plane in its last steps, so it doesn't wait for any pods to start.

   On [Proxmox](../practice-cluster.md#the-practice-cluster-on-proxmox-vms), run the same steps in `./lab.sh shell` on `pe-lab`, with `./lab.sh practice cilium reset` in place of the Lima reset. The setup then needs `cks-cp`, `cks-w1` and the Cilium VM `practice-cilium` running together with `pe-lab`, about 17 GB of memory, and task 3 runs on `practice-cilium`.

2. The clock starts when `setup.sh` ends, and `score.sh` prints the minutes since then.
3. Work only on the nodes, through `./lab.sh practice shell`, `./lab.sh practice shell worker` and `./platform-engineering/practice/cluster/lima.sh shell`, or `./lab.sh practice cilium shell` on Proxmox, and use only the documentation the exam allows.
4. Don't open the solutions while the clock runs, because the score only means something when you worked without them.
5. Score from your Mac with `./lab.sh exam score 6`, or score single tasks with `./lab.sh exam score 6 1 13`.

## Tasks

| # | Task | Points | Module | Host |
|---|---|---|---|---|
| 1 | Pods stay Pending | 8 | 39 | practice-control-plane |
| 2 | One port range, two selectors | 5 | 38 | practice-control-plane |
| 3 | Keep a job off the internet | 6 | 38 | cks-lima |
| 4 | CIS findings and etcd TLS | 6 | 38 | practice-control-plane |
| 5 | An Ingress for two hosts | 4 | 38 | practice-control-plane |
| 6 | A role that grows by itself | 6 | 39 | practice-control-plane |
| 7 | Old tokens and mounted ones | 5 | 39 | practice-control-plane |
| 8 | Everyone is admin | 5 | 39 | practice-control-plane |
| 9 | SSH the right way | 4 | 40 | practice-worker |
| 10 | Kernel modules nobody needs | 4 | 40 | cks-lima |
| 11 | Rotate to a new provider | 8 | 41 | practice-control-plane |
| 12 | gVisor where it exists | 5 | 41 | practice-control-plane |
| 13 | The API server doesn't start | 8 | 42 | practice-control-plane |
| 14 | Delete what's vulnerable | 5 | 42 | practice-control-plane |
| 15 | Tune Falco and act on it | 8 | 43 | practice-worker, practice-control-plane |
| 16 | An audit policy for one team | 7 | 43 | practice-control-plane |
| 17 | seccomp and a read-only root | 6 | 43 | practice-worker, practice-control-plane |

### Task 1: Pods stay Pending (8 points)

**Host:** `practice-control-plane`.

> Deployment `shop` in namespace `m3-app` must scale to 4 replicas, and the new pods never appear. Repair the control plane. Don't change what the components did before somebody edited them.

<details>
<summary>Solution</summary>

`kubectl` itself fails at first, because of task 13, so fix that task first and then look at the control plane pods:

```console
root@practice-control-plane:~# k -n kube-system get pods -l tier=control-plane
NAME                             READY   STATUS             RESTARTS      AGE
etcd-practice-control-plane                      1/1     Running            10            9m37s
kube-apiserver-practice-control-plane            1/1     Running            0             4s
kube-controller-manager-practice-control-plane   0/1     CrashLoopBackOff   1 (10s ago)   27s
kube-scheduler-practice-control-plane            0/1     CrashLoopBackOff   5 (68s ago)   9m37s
root@practice-control-plane:~# k -n kube-system logs kube-controller-manager-practice-control-plane | tail -2
I1115 21:06:14.835680       1 leaderelection.go:304] "Failed to renew lease" lock="kube-system/kube-controller-manager" err="context canceled"
E1115 21:06:14.835729       1 controllermanager.go:413] "leaderelection lost/stopped"
root@practice-control-plane:~# k -n kube-system logs kube-scheduler-practice-control-plane | tail -2
Error: invalid argument "127.0.0.1:10259" for "--bind-address" flag: failed to parse IP: "127.0.0.1:10259"
```

In the test run, the scheduler said:

```
Error: invalid argument "127.0.0.1:10259" for "--bind-address" flag: failed to parse IP: "127.0.0.1:10259"
```

and the controller manager, once the API server answered again:

```
"Error building controllers" err="error parsing root-ca-file at /etc/kubernetes/pki/ca.pem: open /etc/kubernetes/pki/ca.pem: no such file or directory"
```

Somebody added a second `--bind-address` line with a port in it, and since the last copy of a flag wins and a bind address takes an IP only, the scheduler exits. Delete that line from `kube-scheduler.yaml`, and set `--root-ca-file=/etc/kubernetes/pki/ca.crt` in `kube-controller-manager.yaml`. Fix the controller manager first, because without it the Deployment gets no new ReplicaSet pods and new namespaces get no `default` ServiceAccount either. Then run `k -n m3-app scale deploy shop --replicas=4`.

</details>

### Task 2: One port range, two selectors (5 points)

**Host:** `practice-control-plane`.

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

The check tests two traps: `grafana` sits in the right namespace with the wrong label, and a `prometheus` pod sits in a namespace without the label. Both stay out only when the two selectors share one item.

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

[module 4.7, task 3](07-kernel-and-host-security.md#task-3-entities-and-an-explicit-deny-with-cilium) explains entities and deny rules.

</details>

### Task 4: CIS findings and etcd TLS (6 points)

**Host:** `practice-control-plane`.

> Fix kube-bench checks 1.2.15 and 1.3.2 on `practice-control-plane`. Also make etcd accept only TLS 1.3. The control plane keeps running.

<details>
<summary>Solution</summary>

Set `--profiling=false` in the API server and controller manager manifests, and `--tls-min-version=TLS1.3` in etcd's. Change etcd first and wait for it, then the API server, as [module 4.1, task 12](01-setting-up-a-secure-cluster.md#task-12-tls-versions-and-ciphers-for-the-api-server-and-etcd) explains, and confirm with `kube-bench run --targets master --check 1.2.15,1.3.2`.

</details>

### Task 5: An Ingress for two hosts (4 points)

**Host:** `practice-control-plane`.

> Namespace `m3-web` runs Services `shop` and `blog` on port 80. `/root/mock/m3.crt` and `/root/mock/m3.key` hold one certificate for both `shop.m3.local` and `blog.m3.local`. Create an Ingress `sites` with class `nginx` that serves both hosts over HTTPS with it.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k -n m3-web create secret tls m3-tls --cert=/root/mock/m3.crt --key=/root/mock/m3.key
secret/m3-tls created
root@practice-control-plane:~# k -n m3-web create ingress sites --class=nginx \
  --rule="shop.m3.local/*=shop:80,tls=m3-tls" --rule="blog.m3.local/*=blog:80,tls=m3-tls"
ingress.networking.k8s.io/sites created
root@practice-control-plane:~# curl -sk --resolve blog.m3.local:30443:127.0.0.1 https://blog.m3.local:30443/
blog
```

One `tls` entry lists both hosts with the same Secret, and the certificate's subject alternative names cover both, so the controller serves it for each host.

</details>

### Task 6: A role that grows by itself (6 points)

**Host:** `practice-control-plane`.

> ServiceAccount `viewer` in namespace `m3-ops` is bound to the aggregated ClusterRole `ops-view`. It may read Secrets, and it must not. It must also list Deployments in every namespace. Keep `ops-view` aggregating, and keep everything else `viewer` reads.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k get clusterrole -l rbac.m3/aggregate=true
NAME         CREATED AT
ops-config   2026-11-15T21:01:53Z
ops-pods     2026-11-15T21:01:53Z
root@practice-control-plane:~# k get clusterrole ops-config -o yaml        # configmaps and secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
...
  labels:
    rbac.m3/aggregate: "true"
  name: ops-config
...
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - secrets
  verbs:
  - get
  - list
```

Remove `secrets` from `ops-config`, so that ConfigMaps stay readable, and add a labelled ClusterRole for Deployments:

```console
root@practice-control-plane:~# k edit clusterrole ops-config                 # resources: [configmaps]
root@practice-control-plane:~# k create clusterrole ops-deploys --verb=get,list,watch --resource=deployments.apps $do > d.yaml
root@practice-control-plane:~# vim d.yaml                                    # labels: {rbac.m3/aggregate: "true"}
root@practice-control-plane:~# k apply -f d.yaml
clusterrole.rbac.authorization.k8s.io/ops-deploys created
```

The transcript leaves out both editor sessions: the first removes `secrets` from the rules of `ops-config`, the second adds the label to `d.yaml`.

Deleting `ops-config` would remove the Secrets too, but it would take ConfigMaps with it, which the check catches. [module 4.2, task 5](02-hardening-access-to-the-api.md#task-5-aggregated-clusterroles) has the theory.

</details>

### Task 7: Old tokens and mounted ones (5 points)

**Host:** `practice-control-plane`.

> In namespace `m3-ci`, delete every legacy service account token Secret. Make ServiceAccount `builder` mount no token by default, and make pod `build` run again without one. Keep the pod's name.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k -n m3-ci delete secret --field-selector type=kubernetes.io/service-account-token
secret "builder-token" deleted from m3-ci namespace
root@practice-control-plane:~# k -n m3-ci patch sa builder -p '{"automountServiceAccountToken": false}'
serviceaccount/builder patched
root@practice-control-plane:~# k -n m3-ci get pod build -o yaml > build.yaml
root@practice-control-plane:~# vim build.yaml           # delete the kube-api-access volume and its volumeMount
root@practice-control-plane:~# k -n m3-ci replace --force -f build.yaml
pod "build" deleted from m3-ci namespace
pod/build replaced
```

The transcript leaves out the editor session.

A running pod keeps its token, so it needs recreating. The exported YAML spells out the `kube-api-access-...` volume that the API server added, and left in, it mounts the token whatever the ServiceAccount says, so delete the volume and its mount.

</details>

### Task 8: Everyone is admin (5 points)

**Host:** `practice-control-plane`.

> Every authenticated caller may do anything. Restore the authorizers kubeadm sets.

<details>
<summary>Solution</summary>

Set `--authorization-mode=Node,RBAC`, as in [module 4.2, task 12](02-hardening-access-to-the-api.md#task-12-an-api-server-that-allows-everything), so the Node authorizer and RBAC decide again instead of `AlwaysAllow`.

</details>

### Task 9: SSH the right way (4 points)

**Host:** `practice-worker`.

> sshd on `practice-worker` must refuse root logins and password logins, and forward no X11. It keeps running.

<details>
<summary>Solution</summary>

```console
root@practice-worker:~# sshd -T | grep -E '^(permitrootlogin|passwordauthentication|x11forwarding) '
permitrootlogin yes
passwordauthentication yes
x11forwarding yes
root@practice-worker:~# grep -rnE '^(PermitRootLogin|PasswordAuthentication|X11Forwarding)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
/etc/ssh/sshd_config:99:X11Forwarding yes
/etc/ssh/sshd_config.d/05-vendor.conf:1:PasswordAuthentication yes
/etc/ssh/sshd_config.d/05-vendor.conf:2:PermitRootLogin yes
/etc/ssh/sshd_config.d/05-vendor.conf:3:X11Forwarding yes
```

All three values come from `/etc/ssh/sshd_config.d/05-vendor.conf`, which sshd reads before the main file. Set each to `no` there, then run `sshd -t && systemctl restart ssh`.

</details>

### Task 10: Kernel modules nobody needs (4 points)

**Host:** `cks-lima`.

> Unload the kernel modules `udf` and `dccp` on `cks-lima`, and make every later load fail. Use a file under `/etc/modprobe.d/`.

<details>
<summary>Solution</summary>

Write `install udf /bin/false`, `blacklist udf` and the same two lines for `dccp` into a file such as `/etc/modprobe.d/m3.conf`, then run `modprobe -r udf dccp`. [module 4.7, task 4](07-kernel-and-host-security.md#task-4-keep-a-kernel-module-out) explains both lines.

</details>

### Task 11: Rotate to a new provider (8 points)

**Host:** `practice-control-plane`.

> The API server encrypts Secrets with the `aescbc` key `legacy` from `/etc/kubernetes/enc/m3.yaml`. Move every Secret to a new `secretbox` key named `new`, then remove the `aescbc` provider from the file.

<details>
<summary>Solution</summary>

The steps are the four of [module 4.4, task 5](04-hardening-workloads.md#task-5-rotate-the-encryption-key), with a new provider instead of a new key, so put `secretbox` first and keep `aescbc` below it:

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

Restart the API server, run `k get secrets -A -o json | k replace -f -`, delete the `aescbc` block and restart again. etcdctl then shows `k8s:enc:secretbox:v1:new:` for every Secret.

</details>

### Task 12: gVisor where it exists (5 points)

**Host:** `practice-control-plane`.

> Label `practice-worker` with `runtime=gvisor`. Create a RuntimeClass `sandbox` for the handler `runsc` that sends its pods only to nodes with that label, and pod `scan` in namespace `m3-sbx` (image `busybox:1.36`, command `sleep 1d`) that uses it.

<details>
<summary>Solution</summary>

Put `scheduling.nodeSelector: {runtime: gvisor}` in the RuntimeClass, as in [module 4.4, task 9](04-hardening-workloads.md#task-9-a-sandbox-only-on-the-nodes-that-have-it). Afterwards, `k -n m3-sbx exec scan -- dmesg` starts with `Starting gVisor...`.

</details>

### Task 13: The API server doesn't start (8 points)

**Host:** `practice-control-plane`.

> A colleague turned on ImagePolicyWebhook with the configuration `/etc/kubernetes/admission/m3.yaml`, and the API server hasn't answered since. Get it running with the plugin on and `defaultAllow: false`. The back end and its kubeconfig sit in `/etc/kubernetes/policy-webhook/`.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# crictl ps -a --name kube-apiserver
CONTAINER           IMAGE               CREATED              STATE               NAME                ATTEMPT             POD ID              POD                     NAMESPACE
ef0e95360c41f       98d6e75e244ec       About a minute ago   Exited              kube-apiserver      4                   a507ff2270144       kube-apiserver-practice-control-plane   kube-system
root@practice-control-plane:~# crictl logs <id of the newest exited container>
I1115 21:04:10.180684       1 options.go:261] external host was not specified, using 192.168.117.2
W1115 21:04:10.180739       1 authentication.go:841] AnonymousAuth is not allowed with the AlwaysAllow authorizer. Resetting AnonymousAuth to false. You should use a different authorizer
I1115 21:04:10.182935       1 server.go:151] Version: v1.37.1
I1115 21:04:10.182950       1 server.go:153] "Golang settings" GOGC="" GOMAXPROCS="" GOTRACEBACK=""
E1115 21:04:10.448200       1 options.go:205] The manifest file is empty, ignoring.
E1115 21:04:10.459263       1 run.go:72] "command failed" err="failed to apply admission: couldn't init admission plugin \"ImagePolicyWebhook\": stat /etc/kubernetes/policy-webhook/kube.yaml: no such file or directory"
```

The transcript ran `crictl logs` with the ID of the newest exited container.

The last log line names the file the API server misses. `ls /etc/kubernetes/policy-webhook/` shows `kubeconfig.yaml`, so fix `kubeConfigFile` in `/etc/kubernetes/admission/m3.yaml`. The API server still doesn't start, with the same `stat ... no such file or directory`, now for the right file name, because the colleague mounted `/etc/kubernetes/admission` into the pod but not `/etc/kubernetes/policy-webhook`. Add a `volumeMount` and a `hostPath` volume for it, as [module 4.5, task 5](05-supply-chain-security.md#task-5-allow-only-approved-registries) shows. Do this task first, because until the API server runs, no other task on `practice-control-plane` works.

</details>

### Task 14: Delete what's vulnerable (5 points)

**Host:** `practice-control-plane`.

> Delete every Deployment in namespace `m3-prod` whose image has at least one CRITICAL vulnerability, as trivy reports it. Keep the others.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k -n m3-prod get deploy -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[0].image
NAME      IMAGE
front     nginx:1.27-alpine
idle      registry.k8s.io/pause:3.10
session   redis:6.0.5
tools     busybox:1.36
root@practice-control-plane:~# for img in redis:6.0.5 nginx:1.27-alpine registry.k8s.io/pause:3.10 busybox:1.36; do
  echo "$img $(trivy image --quiet --severity CRITICAL $img | grep -m1 Total)"
done
redis:6.0.5 Total: 17 (CRITICAL: 17)
nginx:1.27-alpine Total: 3 (CRITICAL: 3)
registry.k8s.io/pause:3.10 
busybox:1.36 
```

In an earlier test run, trivy found 22 CRITICAL findings in `redis:6.0.5` and 3 in `nginx:1.27-alpine`, and none in the other two, while the transcript's newer database counted 17 for redis. Either way, delete `session` and `front`:

```console
root@practice-control-plane:~# k -n m3-prod delete deploy session front
deployment.apps "session" deleted from m3-prod namespace
deployment.apps "front" deleted from m3-prod namespace
```

The check runs trivy itself and compares, so it still agrees with you after the database changes. A fairly new image such as `nginx:1.27-alpine` has findings too, because the task asks about CRITICAL findings, not about age.

</details>

### Task 15: Tune Falco and act on it (8 points)

**Hosts:** `practice-worker`, then `practice-control-plane`.

> 1. Without editing `/etc/falco/falco_rules.yaml`, raise the priority of Falco's rule `Search Private Keys or Passwords` to `ALERT`.
> 2. A Deployment in namespace `m3-run` searches files for private keys. Find it through that rule, write its name to `/root/mock/key-hunter.txt` on `practice-control-plane`, and scale it to 0.

<details>
<summary>Solution</summary>

```yaml
# /etc/falco/rules.d/m3.yaml on practice-worker
- rule: Search Private Keys or Passwords
  priority: ALERT
  override:
    priority: replace
```

```console
root@practice-worker:~# journalctl -u falco-modern-bpf --since -2min | grep 'Alert Grep private keys' | grep -o 'k8s_pod_name=[^ ]*' | tail -1
k8s_pod_name=indexer-7d5f9f7b4d-zgcnl
```

The pod's `app` label names the Deployment `indexer`, which you scale to zero:

```console
root@practice-control-plane:~# k -n m3-run get pod <pod> --show-labels
NAME                       READY   STATUS    RESTARTS   AGE   LABELS
indexer-7d5f9f7b4d-zgcnl   1/1     Running   0          16m   app=indexer,pod-template-hash=7d5f9f7b4d
root@practice-control-plane:~# echo indexer > /root/mock/key-hunter.txt
root@practice-control-plane:~# k -n m3-run scale deploy indexer --replicas=0
deployment.apps/indexer scaled
```

The transcript ran the first command with the pod name that the alert printed in place of `<pod>`.

`indexer` runs `grep -rs "BEGIN RSA PRIVATE" /etc` in a loop, which matches the rule's macro `private_key_or_password`, and once the override has loaded, the alert line starts with the new priority, `Alert`.

</details>

### Task 16: An audit policy for one team (7 points)

**Host:** `practice-control-plane`.

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

Deployments live in the API group `apps`, not in the core group `""`, so with `group: ""` the rule never matches a Deployment. The flags and the two volumes follow [module 4.6, task 1](06-runtime-security-and-auditing.md#task-1-turn-on-audit-logging).

</details>

### Task 17: seccomp and a read-only root (6 points)

**Hosts:** `practice-worker`, then `practice-control-plane`.

> `/root/mock/no-mkdir.json` on `practice-worker` is a seccomp profile that blocks `mkdir`. Install it as `m3.json` in the kubelet's seccomp folder. Create pod `locked` in namespace `m3-sec` on `practice-worker` (image `busybox:1.36`, command `sleep 1d`) with that profile, a read-only root file system, and an `emptyDir` at `/data`.

<details>
<summary>Solution</summary>

```console
root@practice-worker:~# mkdir -p /var/lib/kubelet/seccomp && cp /root/mock/no-mkdir.json /var/lib/kubelet/seccomp/m3.json          # on practice-worker
```

```yaml
apiVersion: v1
kind: Pod
metadata: {name: locked, namespace: m3-sec}
spec:
  nodeName: practice-worker
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

A fresh kubeadm node has no `/var/lib/kubelet/seccomp` folder until somebody creates it, which is why the command starts with `mkdir -p`. Afterwards, `k -n m3-sec exec locked -- mkdir /data/d` fails with `Operation not permitted`, while `echo ok > /data/f` works. The read-only root alone would allow both in `/data`, so the seccomp profile makes the difference.

</details>

## Scoring

`score.sh` runs two to five checks per task, splits the task's points evenly over them, rounded down, and gives points only when a task's first check passes.

In the final test run, on clusters fresh from both resets and `setup.sh`, the score was `TOTAL: 0 of 100 points (0%).` with `TIME: 3 minutes since setup, 117 minutes left.` After `./lab.sh exam solve 6`, which applies every solution above in its order (13, 8, 1, 11, 4, 16, then the rest) in 7 minutes 47 seconds, it was `TOTAL: 100 of 100 points (100%).` The solve order is the lesson, because each layer needs the one below it: the API server first, then the authorizer that keeps restarting it, then the scheduler and controller manager, and only then everything that needs a working cluster.

Three things broke the first test runs of this practice exam, and each became part of the text. Under `AlwaysAllow`, the API server's health probes get `401`, so the kubelet kills it every few minutes. Without a controller manager, a new namespace gets no `default` ServiceAccount, so no pod starts in it. A check that asks "is it gone?" also passes on a dead API server, so every such check here also asks the API server something that must succeed.
