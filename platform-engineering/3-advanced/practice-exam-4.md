# Timed practice exam 4: security, one topic per task

> New to a term here? The [glossary](../glossary.md#the-practice-cluster-and-the-security-modules) explains every term the security modules use.

**Before the practice exam:** modules 38 to 43, or the confidence to skip them, and the [practice cluster](../practice-cluster.md), freshly reset. This is the first of three practice exams, and [practice exam 5](practice-exam-5.md) and [practice exam 6](practice-exam-6.md) get harder.

The real exam gives you 2 hours for 15 to 20 tasks on several clusters, and this practice exam gives you 2 hours for 17 tasks on one cluster, worth 100 points in total. The points spread over modules 38 to 43 by their size, and a script checks the cluster's state and gives partial credit, the way the exam does.

## Rules

1. Start fresh with `./lab.sh practice reset`, then `./lab.sh exam setup 4`. In the test run, the reset took 67 seconds and the setup 19 seconds, because the nodes already had the images, while on a new cluster the first run also downloads them.
2. The clock starts when `setup.sh` ends, because it writes the start time, and `score.sh` prints the minutes since then and flags a run over 120 minutes.
3. Work only on the nodes, through `./lab.sh practice shell` and `./lab.sh practice shell worker`, and use only the documentation the exam allows: kubernetes.io, and the docs of Falco, bom, etcd, ingress-nginx, Cilium and Istio.
4. Don't open the solutions while the timer runs, because the score only means something when you worked without them.
5. When time is up, score from your Mac with `./lab.sh exam score 4`, or score single tasks with `./lab.sh exam score 4 4 9`.

**Do task 1 first.** `kubeadm upgrade apply` rewrites every static pod manifest from the cluster's stored configuration, so it wipes any API server flag you added before it. The real exam avoids this by giving the upgrade its own cluster, but this practice exam shares one cluster, so the order matters, and noticing that is part of the test.

Each task names the host it runs on, and `kubectl` always runs on `practice-control-plane`.

## Tasks

| # | Task | Points | Module |
|---|---|---|---|
| 1 | Upgrade the control plane | 7 | 39 |
| 2 | Protect the database | 7 | 38 |
| 3 | CIS findings | 6 | 38 |
| 4 | Ingress with TLS | 4 | 38 |
| 5 | Take cluster-admin away | 6 | 39 |
| 6 | No token in the metrics pod | 4 | 39 |
| 7 | Remove a web server from a node | 4 | 40 |
| 8 | An intern with root | 4 | 40 |
| 9 | Restricted namespace | 6 | 41 |
| 10 | Secrets encrypted with secretbox | 7 | 41 |
| 11 | A sandboxed pod | 5 | 41 |
| 12 | Vulnerable images | 5 | 42 |
| 13 | Approved registries only | 9 | 42 |
| 14 | A smaller Node.js image | 4 | 42 |
| 15 | Audit policy | 8 | 43 |
| 16 | Falco finds a snooper | 8 | 43 |
| 17 | Harden a Deployment | 6 | 43 |

### Task 1: Upgrade the control plane (7 points)

**Host:** `practice-control-plane`.

> Upgrade the control plane node `practice-control-plane` from v1.37.1 to v1.37.2: kubeadm, the control plane components, the kubelet and kubectl. Drain the node first and make it schedulable afterwards. Leave `practice-worker` alone.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# apt-mark unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.37.2-1.1 && apt-mark hold kubeadm
Canceled hold on kubeadm.
...
Unpacking kubeadm (1.37.2-1.1) over (1.37.1-1.1)…
Setting up kubeadm (1.37.2-1.1)…
kubeadm set on hold.
root@practice-control-plane:~# kubeadm upgrade apply v1.37.2 -y --ignore-preflight-errors=SystemVerification
...
[upgrade/preflight] You have chosen to upgrade the cluster version to "v1.37.2"
...
[upgrade] SUCCESS! A control plane node of your cluster was upgraded to "v1.37.2".
...
root@practice-control-plane:~# k drain practice-control-plane --ignore-daemonsets --delete-emptydir-data
node/practice-control-plane cordoned
...
node/practice-control-plane drained
root@practice-control-plane:~# apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.37.2-1.1 kubectl=1.37.2-1.1 && apt-mark hold kubelet kubectl
Canceled hold on kubelet.
Canceled hold on kubectl.
...
Setting up kubectl (1.37.2-1.1)…
Setting up kubelet (1.37.2-1.1)…
kubelet set on hold.
kubectl set on hold.
root@practice-control-plane:~# systemctl daemon-reload && systemctl restart kubelet
root@practice-control-plane:~# k uncordon practice-control-plane
node/practice-control-plane uncordoned
```

The worker stays at 1.37.1, which is fine, because a kubelet older than the API server is within the skew rule. [module 39, task 4](../2-intermediate/39-hardening-access-to-the-api.md#task-4-upgrade-the-cluster-with-kubeadm) explains the steps.

</details>

### Task 2: Protect the database (7 points)

**Host:** `practice-control-plane`.

> In namespace `m-db`, pod `db` (label `app=db`) serves on port 80. Create a NetworkPolicy `db-ingress` so that `db` accepts TCP port 80 only from pods labelled `app=backend` in `m-db`, and no other ingress. Pods with the same label in other namespaces must not get in.

<details>
<summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-ingress
  namespace: m-db
spec:
  podSelector:
    matchLabels: {app: db}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels: {app: backend}
    ports:
    - {protocol: TCP, port: 80}
```

A `podSelector` alone in `from` matches pods in the policy's own namespace only, so the `outsider` pod in `m-other`, which is also labelled `app=backend`, stays out.

</details>

### Task 3: CIS findings (6 points)

**Host:** `practice-control-plane`.

> kube-bench reports two failures you must fix on `practice-control-plane`: 1.4.1 (the scheduler's profiling) and 1.1.12 (the owner of etcd's data directory). Both components must keep running.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# kube-bench run --targets master --check 1.4.1,1.1.12      # read the remediations
...
[FAIL] 1.1.12 Ensure that the etcd data directory ownership is set to etcd:etcd (Automated)
...
[FAIL] 1.4.1 Ensure that the --profiling argument is set to false (Automated)
...
0 checks PASS
2 checks FAIL
...
0 checks PASS
2 checks FAIL
...
root@practice-control-plane:~# vim /etc/kubernetes/manifests/kube-scheduler.yaml          # add - --profiling=false
root@practice-control-plane:~# useradd -r -s /usr/sbin/nologin etcd
useradd: user 'etcd' already exists
root@practice-control-plane:~# chown -R etcd:etcd /var/lib/etcd
root@practice-control-plane:~# kube-bench run --targets master --check 1.4.1,1.1.12
...
[PASS] 1.1.12 Ensure that the etcd data directory ownership is set to etcd:etcd (Automated)
...
[PASS] 1.4.1 Ensure that the --profiling argument is set to false (Automated)
...
2 checks PASS
0 checks FAIL
...
2 checks PASS
0 checks FAIL
...
```

The transcript leaves out the editor session, which adds the flag. The practice node already has an `etcd` user, so `useradd` says so, and the `chown` works anyway.

etcd keeps running, because its container runs as root, and the owner change doesn't stop root from reading the files.

</details>

### Task 4: Ingress with TLS (4 points)

**Host:** `practice-control-plane`.

> Namespace `m-web` runs Deployment and Service `site` on port 80. Serve it at `https://site.cks.local` through an Ingress `site` of class `nginx`, with the certificate and key in `/root/mock/site.crt` and `/root/mock/site.key`, stored in a TLS Secret `site-tls`.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k -n m-web create secret tls site-tls --cert=/root/mock/site.crt --key=/root/mock/site.key
secret/site-tls created
root@practice-control-plane:~# k -n m-web create ingress site --class=nginx --rule="site.cks.local/*=site:80,tls=site-tls"
ingress.networking.k8s.io/site created
root@practice-control-plane:~# curl -sk --resolve site.cks.local:30443:127.0.0.1 https://site.cks.local:30443/ | head -4
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

</details>

### Task 5: Take cluster-admin away (6 points)

**Host:** `practice-control-plane`.

> ServiceAccount `deployer` in `m-ops` holds `cluster-admin` through ClusterRoleBinding `deployer-admin`. Remove that binding. Give `deployer` only `get`, `list`, `watch`, `create`, `update` and `patch` on Deployments in `m-ops`, through a Role and a RoleBinding both named `deployer`.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k delete clusterrolebinding deployer-admin
clusterrolebinding.rbac.authorization.k8s.io "deployer-admin" deleted
root@practice-control-plane:~# k -n m-ops create role deployer --verb=get,list,watch,create,update,patch --resource=deployments.apps
role.rbac.authorization.k8s.io/deployer created
root@practice-control-plane:~# k -n m-ops create rolebinding deployer --role=deployer --serviceaccount=m-ops:deployer
rolebinding.rbac.authorization.k8s.io/deployer created
root@practice-control-plane:~# k auth can-i delete deployments -n m-ops --as=system:serviceaccount:m-ops:deployer    # no
no
```

</details>

### Task 6: No token in the metrics pod (4 points)

**Host:** `practice-control-plane`.

> Pod `metrics` in `m-ops` doesn't need the Kubernetes API. Change the pod itself, not its ServiceAccount, so that the kubelet mounts no API token into it. Keep the name.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k -n m-ops get pod metrics -o yaml > metrics.yaml
root@practice-control-plane:~# vim metrics.yaml
root@practice-control-plane:~# k -n m-ops replace --force -f metrics.yaml
pod "metrics" deleted from m-ops namespace
pod/metrics replaced
root@practice-control-plane:~# k -n m-ops exec metrics -- ls /var/run/secrets/kubernetes.io/serviceaccount/
ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory
command terminated with exit code 1
```

The transcript leaves out the editor session, and it waited for the new pod to be Ready before the last command.

In `metrics.yaml`, add `automountServiceAccountToken: false` under `spec`, and delete two more things: the `kube-api-access-...` entry under `volumes`, and its entry under the container's `volumeMounts`. The export spells out the token volume that the API server added when it created the pod, and a spelled-out volume still mounts, whatever `automountServiceAccountToken` says. The test run proved it: with only the field changed, the new pod still listed `ca.crt`, `namespace` and `token`, and the task scored 2 of 4 points, while with the volume gone too, the `ls` failed with `No such file or directory`.

</details>

### Task 7: Remove a web server from a node (4 points)

**Host:** `practice-worker`.

> Something on `practice-worker` listens on TCP port 80. Stop it for good and remove its package.

<details>
<summary>Solution</summary>

```console
root@practice-worker:~# ss -tlnp | grep ':80 '          # names the process: lighttpd
LISTEN 0      1024         0.0.0.0:80         0.0.0.0:*    users:(("lighttpd",pid=88972,fd=5))   
LISTEN 0      1024            [::]:80            [::]:*    users:(("lighttpd",pid=88972,fd=4))   
root@practice-worker:~# dpkg -S "$(command -v lighttpd)"
lighttpd: /usr/sbin/lighttpd
root@practice-worker:~# systemctl disable --now lighttpd
Synchronizing state of lighttpd.service with SysV service script with /usr/lib/systemd/systemd-sysv-install.
Executing: /usr/lib/systemd/systemd-sysv-install disable lighttpd
Removed "/etc/systemd/system/multi-user.target.wants/lighttpd.service".
root@practice-worker:~# apt-get purge -y lighttpd
...
The following packages will be REMOVED:
  lighttpd* lighttpd-mod-deflate* lighttpd-mod-openssl*
...
Removing lighttpd (1.4.74-1ubuntu3)…
...
Purging configuration files for lighttpd (1.4.74-1ubuntu3)…
...
```

</details>

### Task 8: An intern with root (4 points)

**Host:** `practice-worker`.

> User `intern` on `practice-worker` must keep the account but lose every way to run commands as root through sudo.

<details>
<summary>Solution</summary>

```console
root@practice-worker:~# gpasswd -d intern sudo
Removing user intern from group sudo
root@practice-worker:~# grep -rl intern /etc/sudoers /etc/sudoers.d/
/etc/sudoers.d/intern
root@practice-worker:~# rm /etc/sudoers.d/intern
root@practice-worker:~# sudo -l -U intern
User intern is not allowed to run sudo on practice-worker.
```

</details>

### Task 9: Restricted namespace (6 points)

**Host:** `practice-control-plane`.

> Make namespace `m-secure` enforce the `restricted` Pod Security Standard. Deployment `api` must keep one ready pod under it, running as user 1000.

<details>
<summary>Solution</summary>

Label the namespace, then add to the pod template what the warning lists, as in [module 41, task 1](41-hardening-workloads.md#task-1-enforce-the-restricted-standard):

```console
root@practice-control-plane:~# k label ns m-secure pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "m-secure" violate the new PodSecurity enforce level "restricted:latest"
Warning: api-85c6769c7f-46w2c: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/m-secure labeled
root@practice-control-plane:~# k -n m-secure edit deploy api
```

The transcript leaves out the editor session, which makes the change the YAML below shows.

```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile: {type: RuntimeDefault}
      containers:
      - name: busybox
        securityContext:
          allowPrivilegeEscalation: false
          capabilities: {drop: ["ALL"]}
```

</details>

### Task 10: Secrets encrypted with secretbox (7 points)

**Host:** `practice-control-plane`.

> Encrypt Secrets at rest with the `secretbox` provider and a key named `mock`, configured in `/etc/kubernetes/enc/mock.yaml`. Secret `api-key` in `m-vault`, which already exists, must end up encrypted.

<details>
<summary>Solution</summary>

The steps are the same as in [module 41, task 2](41-hardening-workloads.md#task-2-encrypt-secrets-at-rest), with a different provider in the file:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: [secrets]
  providers:
  - secretbox:
      keys:
      - name: mock
        secret: <head -c 32 /dev/urandom | base64>
  - identity: {}
```

Add `--encryption-provider-config=/etc/kubernetes/enc/mock.yaml` with a mount for `/etc/kubernetes/enc`, wait for the API server, then run `k get secrets -A -o json | k replace -f -` so every Secret gets encrypted. etcd then shows the prefix `k8s:enc:secretbox:v1:mock:`.

</details>

### Task 11: A sandboxed pod (5 points)

**Host:** `practice-control-plane`.

> Create a RuntimeClass `sandboxed` for the handler `runsc`, and a pod `untrusted` in `m-sandbox` with image `busybox:1.36` and command `sleep 1d` that runs with it.

<details>
<summary>Solution</summary>

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: sandboxed}
handler: runsc
---
apiVersion: v1
kind: Pod
metadata: {name: untrusted, namespace: m-sandbox}
spec:
  runtimeClassName: sandboxed
  containers:
  - {name: c, image: busybox:1.36, command: [sleep, 1d]}
```

`k -n m-sandbox exec untrusted -- dmesg | head -1` prints `Starting gVisor...`, which proves the pod runs in the sandbox.

</details>

### Task 12: Vulnerable images (5 points)

**Host:** `practice-control-plane`.

> Delete every pod in `m-scan` whose image has at least one CRITICAL vulnerability according to trivy. Keep the rest.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k -n m-scan get pods -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image
POD             IMAGE
debug           busybox:1.36
legacy-web      nginx:1.19.0
session-store   redis:6.0.5
root@practice-control-plane:~# for i in nginx:1.19.0 redis:6.0.5 busybox:1.36; do echo "$i $(trivy image -q --severity CRITICAL $i | grep Total)"; done
nginx:1.19.0 Total: 44 (CRITICAL: 44)
redis:6.0.5 Total: 17 (CRITICAL: 17)
Total: 5 (CRITICAL: 5)
busybox:1.36 
root@practice-control-plane:~# k -n m-scan delete pod legacy-web session-store
pod "legacy-web" deleted from m-scan namespace
pod "session-store" deleted from m-scan namespace
```

</details>

### Task 13: Approved registries only (9 points)

**Host:** `practice-control-plane`.

> The image policy back end at `https://localhost:8443/review` decides which images may run. Its kubeconfig is `/etc/kubernetes/policy-webhook/kubeconfig.yaml`. Enable the ImagePolicyWebhook admission plugin with the admission configuration file `/etc/kubernetes/admission/mock-admission.yaml`, with TTLs of 50 seconds, a retry backoff of 500 ms, and pods refused when the back end doesn't answer.

<details>
<summary>Solution</summary>

The steps are the same as in [module 42, task 5](42-supply-chain-security.md#task-5-allow-only-approved-registries), with the file name `mock-admission.yaml`. Remember both mounts, `/etc/kubernetes/admission` and `/etc/kubernetes/policy-webhook`, because a missing one keeps the API server down. Then test an image the policy must refuse:

```console
root@practice-control-plane:~# k run t --image=quay.io/evil/miner:1 --dry-run=server     # refused
Error from server (Forbidden): pods "t" is forbidden: image policy webhook backend denied one or more images: image quay.io/evil/miner:1 is not from an allowed registry
```

</details>

### Task 14: A smaller Node.js image (4 points)

**Host:** `practice-control-plane`.

> Fix `/root/mock/build/Dockerfile`: base it on `node:22-alpine`, install no extra packages, and run as the image's `node` user. Don't build it.

<details>
<summary>Solution</summary>

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY server.js .
USER node
CMD ["node", "server.js"]
```

</details>

### Task 15: Audit policy (8 points)

**Host:** `practice-control-plane`.

> Turn on audit logging with the policy `/etc/kubernetes/audit/mock-policy.yaml`:
>
> - Secrets and ConfigMaps in every namespace at `Metadata`.
> - Pods in namespace `m-audit` at `Request`.
> - Nothing else. Skip the `RequestReceived` stage.
>
> Log to `/var/log/kubernetes/audit/mock.log`, keep 7 days, 5 files and 50 MB per file.

<details>
<summary>Solution</summary>

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: Metadata
  resources:
  - group: ""
    resources: [secrets, configmaps]
- level: Request
  namespaces: [m-audit]
  resources:
  - group: ""
    resources: [pods]
- level: None
```

The flags and the two mounts follow [module 43, task 1](43-runtime-security-and-auditing.md#task-1-turn-on-audit-logging), with `--audit-log-maxage=7`, `--audit-log-maxbackup=5` and `--audit-log-maxsize=50`.

</details>

### Task 16: Falco finds a snooper (8 points)

**Hosts:** `practice-worker`, then `practice-control-plane`.

> One of the two Deployments in `m-runtime` keeps reading `/etc/shadow`. Use Falco on `practice-worker` to find which one. Write the Deployment's name to `/root/mock/snooper.txt` on `practice-control-plane`, and scale that Deployment to 0. Leave the other one alone.

<details>
<summary>Solution</summary>

Start on `practice-worker`, where Falco runs, and filter its alerts by the file and the namespace:

```console
root@practice-worker:~# journalctl -u falco-modern-bpf --since -10min | grep 'file=/etc/shadow' | grep 'k8s_ns_name=m-runtime' | tail -1
Nov 15 20:38:21 practice-worker falco[83315]: 20:38:21.937670546: Warning Sensitive file opened for reading by non-trusted program | file=/etc/shadow gparent=containerd-shim ggparent=<NA> gggparent=<NA> evt_type=openat user=root user_uid=0 user_loginuid=-1 process=cat proc_exepath=/bin/cat parent=sh command=cat /etc/shadow terminal=0 container_id=6698b5affca2 container_name=busybox container_image_repository=docker.io/library/busybox container_image_tag=1.36 k8s_pod_name=reporter-6b5d764586-xdrzz k8s_ns_name=m-runtime
```

The alert comes from Falco's default rule `Sensitive file opened for reading by non-trusted program`, and it names the pod in `k8s_pod_name=`. On `practice-control-plane`, follow the pod to its Deployment and act on that, because scaling a ReplicaSet's pod away only brings a new one:

```console
root@practice-control-plane:~# k -n m-runtime get pod <pod> -o jsonpath='{.metadata.ownerReferences[0].name}'   # the ReplicaSet: reporter-<hash>
reporter-6b5d764586
root@practice-control-plane:~# echo reporter > /root/mock/snooper.txt
root@practice-control-plane:~# k -n m-runtime scale deploy reporter --replicas=0
deployment.apps/reporter scaled
```

The transcript ran the first command with the name of the reporter pod from the alert in place of `<pod>`.

</details>

### Task 17: Harden a Deployment (6 points)

**Host:** `practice-control-plane`.

> Deployment `app` in `m-hard` runs `busybox:1.36`. Make its container's root file system read-only, forbid privilege escalation, and give the container the runtime's default seccomp profile. It must keep running.

<details>
<summary>Solution</summary>

```yaml
      containers:
      - name: busybox
        securityContext:
          readOnlyRootFilesystem: true
          allowPrivilegeEscalation: false
          seccompProfile:
            type: RuntimeDefault
```

`sleep` writes nothing, so the container needs no `emptyDir` to survive the read-only root.

</details>

## Scoring

`score.sh` runs between two and six checks per task and splits the task's points evenly over them, rounded down, then prints each check, the points per task and the total.

In the test run, on a cluster fresh from `reset.sh` and `setup.sh`, the score was `TOTAL: 0 of 100 points (0%).` After `./lab.sh exam solve 4`, which applies every solution above in order and took 5 minutes 57 seconds in the final run, it was `TOTAL: 100 of 100 points (100%).` A task scores only when its first check, the main change, passes, because without that rule an untouched cluster scored 18, since checks such as "the scheduler still runs" pass by themselves.
