# CKS mock exam 1

> New to a term here? The [glossary](../../course/glossary.md#cks-exam-track) explains every term this track uses.

**Before the mock exam:** all six domain files, or the confidence to skip them. The [practice cluster](../README.md#the-practice-cluster), freshly reset. This is the first of three mock exams; [mock exam 2](mock-exam-2.md) and [mock exam 3](mock-exam-3.md) get harder.

The real exam gives you 2 hours for 15 to 20 tasks on several clusters. This mock gives you 2 hours for 17 tasks on one cluster, worth 100 points in total. The weights follow the curriculum's domains roughly. A script checks the cluster's state and gives partial credit, the way the exam does.

## Rules

1. Start fresh: `./certs/cks/cluster/reset.sh`, then `./certs/cks/mock-exam/setup.sh`. In the test run, the setup took 8 seconds, because the node already had the images. On new machines, the first run also downloads them.
2. The clock starts when `setup.sh` ends: it writes the start time, and `score.sh` prints the minutes since then and flags a run over 120 minutes.
3. Work only on the nodes: `orb -m cks-cp` and `orb -m cks-w1`. Use only the documentation the exam allows: kubernetes.io, and the docs of Falco, bom, etcd, ingress-nginx, Cilium and Istio.
4. Don't open the solutions while the timer runs.
5. When time is up, score from your Mac: `./certs/cks/mock-exam/score.sh`. Single tasks score with `./certs/cks/mock-exam/score.sh 4 9`.

**Do task 1 first.** `kubeadm upgrade apply` rewrites every static pod manifest from the cluster's stored configuration, so it wipes any API server flag you added before it. The real exam avoids this by giving the upgrade its own cluster. This mock shares one cluster, so the order matters, and noticing that is part of the test.

Each task names the host. Run `kubectl` on `cks-cp`.

## Tasks

| # | Task | Points | Domain |
|---|---|---|---|
| 1 | Upgrade the control plane | 7 | 02 |
| 2 | Protect the database | 7 | 01 |
| 3 | CIS findings | 6 | 01 |
| 4 | Ingress with TLS | 4 | 01 |
| 5 | Take cluster-admin away | 6 | 02 |
| 6 | No token in the metrics pod | 4 | 02 |
| 7 | Remove a web server from a node | 4 | 03 |
| 8 | An intern with root | 4 | 03 |
| 9 | Restricted namespace | 6 | 04 |
| 10 | Secrets encrypted with secretbox | 7 | 04 |
| 11 | A sandboxed pod | 5 | 04 |
| 12 | Vulnerable images | 5 | 05 |
| 13 | Approved registries only | 9 | 05 |
| 14 | A smaller Node.js image | 4 | 05 |
| 15 | Audit policy | 8 | 06 |
| 16 | Falco finds a snooper | 8 | 06 |
| 17 | Harden a Deployment | 6 | 06 |

### Task 1: Upgrade the control plane (7 points)

**Host:** `cks-cp`.

> Upgrade the control plane node `cks-cp` from v1.37.1 to v1.37.2: kubeadm, the control plane components, the kubelet and kubectl. Drain the node first and make it schedulable afterwards. Leave `cks-w1` alone.

<details>
<summary>Solution</summary>

```bash
apt-mark unhold kubeadm && apt-get update && apt-get install -y kubeadm=1.37.2-1.1 && apt-mark hold kubeadm
kubeadm upgrade apply v1.37.2 -y
k drain cks-cp --ignore-daemonsets --delete-emptydir-data
apt-mark unhold kubelet kubectl && apt-get install -y kubelet=1.37.2-1.1 kubectl=1.37.2-1.1 && apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
k uncordon cks-cp
```

The worker stays at 1.37.1. A kubelet older than the API server is within the skew rule. [02, task 4](02-cluster-hardening.md#task-4-upgrade-the-cluster-with-kubeadm) explains the steps.

</details>

### Task 2: Protect the database (7 points)

**Host:** `cks-cp`.

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

A `podSelector` alone in `from` matches pods in the policy's own namespace only. So the `outsider` pod in `m-other`, also labelled `app=backend`, stays out.

</details>

### Task 3: CIS findings (6 points)

**Host:** `cks-cp`.

> kube-bench reports two failures you must fix on `cks-cp`: 1.4.1 (the scheduler's profiling) and 1.1.12 (the owner of etcd's data directory). Both components must keep running.

<details>
<summary>Solution</summary>

```bash
kube-bench run --targets master --check 1.4.1,1.1.12      # read the remediations
vim /etc/kubernetes/manifests/kube-scheduler.yaml          # add - --profiling=false
useradd -r -s /usr/sbin/nologin etcd
chown -R etcd:etcd /var/lib/etcd
kube-bench run --targets master --check 1.4.1,1.1.12
```

etcd keeps running, because its container runs as root and the owner change doesn't stop root from reading the files.

</details>

### Task 4: Ingress with TLS (4 points)

**Host:** `cks-cp`.

> Namespace `m-web` runs Deployment and Service `site` on port 80. Serve it at `https://site.cks.local` through an Ingress `site` of class `nginx`, with the certificate and key in `/root/mock/site.crt` and `/root/mock/site.key`, stored in a TLS Secret `site-tls`.

<details>
<summary>Solution</summary>

```bash
k -n m-web create secret tls site-tls --cert=/root/mock/site.crt --key=/root/mock/site.key
k -n m-web create ingress site --class=nginx --rule="site.cks.local/*=site:80,tls=site-tls"
curl -sk --resolve site.cks.local:30443:127.0.0.1 https://site.cks.local:30443/ | head -4
```

</details>

### Task 5: Take cluster-admin away (6 points)

**Host:** `cks-cp`.

> ServiceAccount `deployer` in `m-ops` holds `cluster-admin` through ClusterRoleBinding `deployer-admin`. Remove that binding. Give `deployer` only `get`, `list`, `watch`, `create`, `update` and `patch` on Deployments in `m-ops`, through a Role and a RoleBinding both named `deployer`.

<details>
<summary>Solution</summary>

```bash
k delete clusterrolebinding deployer-admin
k -n m-ops create role deployer --verb=get,list,watch,create,update,patch --resource=deployments.apps
k -n m-ops create rolebinding deployer --role=deployer --serviceaccount=m-ops:deployer
k auth can-i delete deployments -n m-ops --as=system:serviceaccount:m-ops:deployer    # no
```

</details>

### Task 6: No token in the metrics pod (4 points)

**Host:** `cks-cp`.

> Pod `metrics` in `m-ops` doesn't need the Kubernetes API. Change the pod itself, not its ServiceAccount, so that the kubelet mounts no API token into it. Keep the name.

<details>
<summary>Solution</summary>

```bash
k -n m-ops get pod metrics -o yaml > metrics.yaml
vim metrics.yaml
k -n m-ops replace --force -f metrics.yaml
k -n m-ops exec metrics -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

In `metrics.yaml`, add `automountServiceAccountToken: false` under `spec`, and delete two more things: the `kube-api-access-...` entry under `volumes`, and its entry under the container's `volumeMounts`. The export spells out the token volume that the API server added when it created the pod. A spelled-out volume mounts whatever the field says. The test run proved it: with only the field changed, the new pod still listed `ca.crt`, `namespace` and `token`, and the task scored 2 of 4 points. With the volume gone too, the `ls` fails with `No such file or directory`.

</details>

### Task 7: Remove a web server from a node (4 points)

**Host:** `cks-w1`.

> Something on `cks-w1` listens on TCP port 80. Stop it for good and remove its package.

<details>
<summary>Solution</summary>

```bash
ss -tlnp | grep ':80 '          # names the process: lighttpd
dpkg -S "$(command -v lighttpd)"
systemctl disable --now lighttpd
apt-get purge -y lighttpd
```

</details>

### Task 8: An intern with root (4 points)

**Host:** `cks-w1`.

> User `intern` on `cks-w1` must keep the account but lose every way to run commands as root through sudo.

<details>
<summary>Solution</summary>

```bash
gpasswd -d intern sudo
grep -rl intern /etc/sudoers /etc/sudoers.d/
rm /etc/sudoers.d/intern
sudo -l -U intern
```

</details>

### Task 9: Restricted namespace (6 points)

**Host:** `cks-cp`.

> Make namespace `m-secure` enforce the `restricted` Pod Security Standard. Deployment `api` must keep one ready pod under it, running as user 1000.

<details>
<summary>Solution</summary>

Label the namespace, then add to the pod template what the warning lists, as in [04, task 1](04-minimize-microservice-vulnerabilities.md#task-1-enforce-the-restricted-standard):

```bash
k label ns m-secure pod-security.kubernetes.io/enforce=restricted
k -n m-secure edit deploy api
```

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

**Host:** `cks-cp`.

> Encrypt Secrets at rest with the `secretbox` provider and a key named `mock`, configured in `/etc/kubernetes/enc/mock.yaml`. Secret `api-key` in `m-vault`, which already exists, must end up encrypted.

<details>
<summary>Solution</summary>

The same steps as [04, task 2](04-minimize-microservice-vulnerabilities.md#task-2-encrypt-secrets-at-rest), with a different provider:

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

Add `--encryption-provider-config=/etc/kubernetes/enc/mock.yaml` with a mount for `/etc/kubernetes/enc`, wait for the API server, then `k get secrets -A -o json | k replace -f -`. etcd then shows the prefix `k8s:enc:secretbox:v1:mock:`.

</details>

### Task 11: A sandboxed pod (5 points)

**Host:** `cks-cp`.

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

`k -n m-sandbox exec untrusted -- dmesg | head -1` prints `Starting gVisor...`.

</details>

### Task 12: Vulnerable images (5 points)

**Host:** `cks-cp`.

> Delete every pod in `m-scan` whose image has at least one CRITICAL vulnerability according to trivy. Keep the rest.

<details>
<summary>Solution</summary>

```bash
k -n m-scan get pods -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image
for i in nginx:1.19.0 redis:6.0.5 busybox:1.36; do echo "$i $(trivy image -q --severity CRITICAL $i | grep Total)"; done
k -n m-scan delete pod legacy-web session-store
```

</details>

### Task 13: Approved registries only (9 points)

**Host:** `cks-cp`.

> The image policy back end at `https://localhost:8443/review` decides which images may run. Its kubeconfig is `/etc/kubernetes/policy-webhook/kubeconfig.yaml`. Enable the ImagePolicyWebhook admission plugin with the admission configuration file `/etc/kubernetes/admission/mock-admission.yaml`, with TTLs of 50 seconds, a retry backoff of 500 ms, and pods refused when the back end doesn't answer.

<details>
<summary>Solution</summary>

The same steps as [05, task 5](05-supply-chain-security.md#task-5-allow-only-approved-registries), with the file name `mock-admission.yaml`. Remember both mounts: `/etc/kubernetes/admission` and `/etc/kubernetes/policy-webhook`. Then:

```bash
k run t --image=quay.io/evil/miner:1 --dry-run=server     # refused
```

</details>

### Task 14: A smaller Node.js image (4 points)

**Host:** `cks-cp`.

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

**Host:** `cks-cp`.

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

The flags and the two mounts follow [06, task 1](06-monitoring-logging-runtime-security.md#task-1-turn-on-audit-logging), with `--audit-log-maxage=7`, `--audit-log-maxbackup=5` and `--audit-log-maxsize=50`.

</details>

### Task 16: Falco finds a snooper (8 points)

**Hosts:** `cks-w1`, then `cks-cp`.

> One of the two Deployments in `m-runtime` keeps reading `/etc/shadow`. Use Falco on `cks-w1` to find which one. Write the Deployment's name to `/root/mock/snooper.txt` on `cks-cp`, and scale that Deployment to 0. Leave the other one alone.

<details>
<summary>Solution</summary>

On `cks-w1`:

```bash
journalctl -u falco-modern-bpf --since -10min | grep 'file=/etc/shadow' | grep 'k8s_ns_name=m-runtime' | tail -1
```

The alert is Falco's default rule `Sensitive file opened for reading by non-trusted program`. It names the pod in `k8s_pod_name=`. On `cks-cp`, find its Deployment and act:

```bash
k -n m-runtime get pod <pod> -o jsonpath='{.metadata.ownerReferences[0].name}'   # the ReplicaSet: reporter-<hash>
echo reporter > /root/mock/snooper.txt
k -n m-runtime scale deploy reporter --replicas=0
```

</details>

### Task 17: Harden a Deployment (6 points)

**Host:** `cks-cp`.

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

`sleep` writes nothing, so it needs no `emptyDir`.

</details>

## Scoring

`score.sh` runs between two and six checks per task and splits the task's points evenly over them, rounded down. It prints each check, the points per task, and the total.

In the test run, on a cluster fresh from `reset.sh` and `setup.sh`, the score was `TOTAL: 0 of 100 points (0%).` After `./certs/cks/mock-exam/solve.sh`, which applies every solution above in order in 5 minutes 57 seconds in the final run, it was `TOTAL: 100 of 100 points (100%).` A task scores only when its first check, the main change, passes. Without that rule, an untouched cluster scored 18, because checks such as "the scheduler still runs" pass by themselves.
