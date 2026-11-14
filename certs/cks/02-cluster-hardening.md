# CKS 02: Cluster hardening (15%)

> New to a term here, like resourceNames or AuthenticationConfiguration? The [glossary](../../course/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) at v1.37.1, so run `./certs/cks/cluster/reset.sh` after domain 01. The course's [module 29](../../course/29-life-of-a-request.md#concept-inside-the-api-server) walks one request through authentication, authorization and admission. Read it first, because this domain changes each of those gates.

Every attack on a cluster ends at the API server. A stolen service account token, a forgotten anonymous binding or a known bug in an old version all turn into API calls that change something. This domain shrinks what each caller may do and keeps the API server patched. It has four tasks and takes about 45 minutes.

## Theory: who may call the API, and with what power

A request passes three gates in order, as module 29 shows:

1. Authentication decides who the caller is: a client certificate, a token, or nobody (`system:anonymous`).
2. Authorization decides whether that caller may do this verb on this resource. kubeadm turns on the Node authorizer and RBAC.
3. Admission decides whether the object is acceptable, and may change it.

Tasks 1 and 2 tighten gate 2 for workloads. Task 3 tightens gate 1 for strangers. Task 4 replaces the whole API server with a patched one.

### RBAC: grant the verb, the resource, and sometimes the name

**RBAC** (role-based access control) has four objects. A Role lists permissions inside one namespace, and a ClusterRole lists them cluster-wide. A RoleBinding or ClusterRoleBinding hands a role to users, groups or service accounts. Permissions only add: no rule ever takes a right away.

A rule has three parts, and each one narrows the grant:

| Part | Example | Too broad |
|---|---|---|
| `verbs` | `get`, `list`, `watch` | `*`, which includes `delete`, `escalate` and `impersonate` |
| `resources` | `pods` | `*`, which includes Secrets |
| `resourceNames` | `report-key` | missing, which means every object of that kind |

Two details trip people up. First, `list` on Secrets returns their contents, not only their names. So "may list secrets" equals "may read every secret". Second, `resourceNames` covers `get`, `update` and `delete` on the named object. It never covers `create`, and it covers a plain `list` or `watch` neither, because those requests name no single object.

`kubectl auth can-i` answers the question for any caller, without becoming that caller: `k auth can-i list secrets --as=system:serviceaccount:finance:reporter -n finance`.

### Service account tokens

Every pod runs as a **service account**. Unless told otherwise, the kubelet mounts a short-lived token for that account into `/var/run/secrets/kubernetes.io/serviceaccount/`. Most applications never call the Kubernetes API, yet each one carries a key to it. An attacker who gets a shell in the pod picks up the key.

Two settings remove it. `automountServiceAccountToken: false` on the ServiceAccount stops the mount for every pod that uses the account. The same field on a pod spec overrides the account's setting for that pod. Give each application its own account, too. Then a permission granted to one app never leaks to the others through the shared `default` account.

### Anonymous requests

kubeadm leaves anonymous authentication on. A request without credentials becomes the user `system:anonymous` in the group `system:unauthenticated`. Out of the box, RBAC lets that user read only health and version endpoints. One careless ClusterRoleBinding to `system:anonymous` opens the cluster to the internet.

Turning anonymous access off completely breaks the cluster in a slow way. The test run measured it. kubeadm's probes for the API server call `/livez`, `/readyz` and the startup endpoint without credentials. With anonymous access off, they get `401`:

1. The kubelet restarts the API server, and the new process starts serving within seconds.
2. The startup probe keeps failing with `HTTP probe failed with statuscode: 401`, so the pod stays `Ready: False`.
3. After 24 failures, 10 seconds apart, the kubelet kills the API server. In the test run, that took 4 minutes, and the loop repeats forever.

The **AuthenticationConfiguration** file fixes this. It lets you keep anonymous access only for named paths. The API server reads it from the `--authentication-config` flag. Think of a shop that lets anyone read the opening hours on the door, but lets nobody walk in without a badge.

### Upgrades

Each Kubernetes minor release gets patches for about 14 months. A patch release such as 1.37.2 fixes bugs and security holes without changing APIs, so patch upgrades are cheap and urgent. kubeadm upgrades one node at a time, control plane first, and keeps the kubelet's version skew rule: a kubelet must never be newer than the API server.

The order on each node is the same:

1. Upgrade the `kubeadm` package.
2. Run `kubeadm upgrade apply` on the first control plane node, or `kubeadm upgrade node` on every other node.
3. Drain the node.
4. Upgrade the `kubelet` and `kubectl` packages and restart the kubelet.
5. Uncordon the node.

The test run found a trap. `kubeadm upgrade apply` rewrites every static pod manifest from the cluster's stored kubeadm configuration. Flags you added by hand disappear. After the upgrade, `--profiling=false` from domain 01 and `--authentication-config` from task 3 were gone, and an anonymous request for pods got `403` again instead of `401`. To make a flag survive upgrades, add it to the `kubeadm-config` ConfigMap in `kube-system` under `apiServer.extraArgs`, with `extraVolumes` for any file it reads.

## Task 1: Trim an over-broad Role

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 2.1
```

> In namespace `finance`, ServiceAccount `reporter` is bound to Role `reporter-role`, which allows every verb on every resource.
>
> 1. Change `reporter-role` so it allows only `get`, `list` and `watch` on pods.
> 2. `reporter` must also read the Secret `report-key`, and no other Secret. Create a Role `secret-reader` and a RoleBinding `secret-reader` for that.

<details>
<summary>Solution</summary>

`kubectl create role ... --dry-run=client -o yaml | kubectl replace -f -` rewrites the existing Role in one line:

```bash
k -n finance create role reporter-role --verb=get,list,watch --resource=pods $do | k replace -f -
k -n finance create role secret-reader --verb=get --resource=secrets --resource-name=report-key
k -n finance create rolebinding secret-reader --role=secret-reader --serviceaccount=finance:reporter
```

Then ask the API server as the account:

```bash
for q in "list pods" "delete pods" "get secret/report-key" "get secret/db-password" "list secrets"; do
  echo "$q: $(k auth can-i $q --as=system:serviceaccount:finance:reporter -n finance)"
done
```

`list secrets` must say `no`. With `--resource-name`, the Role allows `get` on one Secret only, and `list` never matches a named rule.

</details>

```bash
./certs/cks/task.sh check 2.1
```

In the test run, the setup's Role failed three of the seven checks: it allowed deleting pods, reading `db-password` and listing Secrets. After the solution:

```
  PASS  reporter lists pods
  PASS  reporter watches pods
  PASS  reporter does not delete pods
  PASS  reporter does not create deployments
  PASS  reporter gets the Secret report-key
  PASS  reporter does not get the Secret db-password
  PASS  reporter does not list Secrets
```

## Task 2: Service account tokens

**Time budget:** 5 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 2.2
```

> In namespace `payments`, Deployment `checkout` runs with the `default` ServiceAccount and never calls the Kubernetes API.
>
> 1. Stop the `default` ServiceAccount in `payments` from mounting tokens.
> 2. Create a ServiceAccount `checkout` that mounts no token either, and make the Deployment use it.

<details>
<summary>Solution</summary>

```bash
k -n payments patch sa default -p '{"automountServiceAccountToken": false}'
k -n payments create sa checkout
k -n payments patch sa checkout -p '{"automountServiceAccountToken": false}'
k -n payments set serviceaccount deploy checkout checkout
k -n payments rollout status deploy checkout
k -n payments exec deploy/checkout -- ls /var/run/secrets/kubernetes.io/serviceaccount/
```

`set serviceaccount` changes the pod template, so the Deployment rolls out new pods. The old pods keep their token until they stop: a ServiceAccount change never reaches running pods. The last command fails with `No such file or directory`, which is the goal.

</details>

```bash
./certs/cks/task.sh check 2.2
```

```
  PASS  ServiceAccount default in payments has automountServiceAccountToken: false
  PASS  ServiceAccount checkout exists, also without automount
  PASS  Deployment checkout runs as ServiceAccount checkout
  PASS  the running pod has no API token mounted
```

## Task 3: Restrict anonymous access to the API

**Time budget:** 8 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 2.3
```

The setup creates a binding and prints what an anonymous caller gets. In the test run: `anonymous list of pods: 200`.

> Somebody bound the ClusterRole `view` to `system:anonymous`.
>
> 1. Remove that ClusterRoleBinding.
> 2. Configure the API server so that anonymous requests work only for `/livez`, `/readyz` and `/healthz`. Use the file `/etc/kubernetes/auth/auth-config.yaml`.
> 3. The API server must stay healthy.

<details>
<summary>Solution</summary>

Find and delete the binding:

```bash
k get clusterrolebinding -o wide | grep system:anonymous
k delete clusterrolebinding anonymous-view
```

Write the configuration:

```bash
mkdir -p /etc/kubernetes/auth
vim /etc/kubernetes/auth/auth-config.yaml
```

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
anonymous:
  enabled: true
  conditions:
  - path: /livez
  - path: /readyz
  - path: /healthz
```

The API server runs in a container, so it sees the file only through a volume. Edit `/etc/kubernetes/manifests/kube-apiserver.yaml` after a backup, in three places:

```yaml
  - command:
    - kube-apiserver
    - --authentication-config=/etc/kubernetes/auth/auth-config.yaml
...
    volumeMounts:
    - mountPath: /etc/kubernetes/auth
      name: auth-config
      readOnly: true
...
  volumes:
  - hostPath:
      path: /etc/kubernetes/auth
      type: DirectoryOrCreate
    name: auth-config
```

Don't also set `--anonymous-auth`. With both, the API server exits at once: `--anonymous-auth flag cannot be set when anonymous field is configured in authentication configuration file`.

Wait for the API server to come back, then test with curl, which sends no credentials:

```bash
watch crictl ps --name kube-apiserver
IP=$(hostname -I | cut -d' ' -f1)
curl -sk -o /dev/null -w '%{http_code}\n' https://$IP:6443/api/v1/namespaces/default/pods   # 401
curl -sk -o /dev/null -w '%{http_code}\n' https://$IP:6443/livez                            # 200
```

In the test run, the API server answered again within a minute of the manifest change.

</details>

```bash
./certs/cks/task.sh check 2.3
```

```
  PASS  ClusterRoleBinding anonymous-view is gone
  PASS  an anonymous request for pods gets 401
  PASS  an anonymous request for /livez still gets 200
  PASS  the API server uses --authentication-config
  PASS  the API server pod is Ready
```

`401` means "I don't know who you are". Before the fix, an anonymous caller without the binding got `403`, "I know you're anonymous, and anonymous may not". Both refuse, but `401` refuses earlier, at gate 1.

## Task 4: Upgrade the cluster with kubeadm

**Time budget:** 12 minutes. **Hosts:** `cks-cp`, then `cks-w1`.

```bash
./certs/cks/task.sh setup 2.4     # prints the node versions; both must say v1.37.1
```

> Upgrade the control plane and the worker from v1.37.1 to v1.37.2. Drain each node before you upgrade its kubelet, and make it schedulable again afterwards. Keep the packages on hold.

<details>
<summary>Solution</summary>

On `cks-cp`:

```bash
apt-mark unhold kubeadm
apt-get update && apt-get install -y kubeadm=1.37.2-1.1
apt-mark hold kubeadm
kubeadm upgrade plan v1.37.2
kubeadm upgrade apply v1.37.2 -y
k drain cks-cp --ignore-daemonsets --delete-emptydir-data
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.37.2-1.1 kubectl=1.37.2-1.1
apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
k uncordon cks-cp
k drain cks-w1 --ignore-daemonsets --delete-emptydir-data --force
```

`--force` lets the drain delete bare pods that no controller owns, such as the ones earlier tasks created. Then on `cks-w1`:

```bash
apt-mark unhold kubeadm kubelet kubectl
apt-get update && apt-get install -y kubeadm=1.37.2-1.1
kubeadm upgrade node
apt-get install -y kubelet=1.37.2-1.1 kubectl=1.37.2-1.1
apt-mark hold kubeadm kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
```

And back on `cks-cp`: `k uncordon cks-w1`, then `k get nodes`.

`apt-cache madison kubeadm` lists the exact package versions when you don't know the `-1.1` suffix. In the test run, the whole upgrade took 2 minutes 39 seconds, and `kubeadm` left backups of the old manifests and etcd data in `/etc/kubernetes/tmp/`.

</details>

```bash
./certs/cks/task.sh check 2.4
```

```
  PASS  cks-cp kubelet reports v1.37.2
  PASS  cks-w1 kubelet reports v1.37.2
  PASS  the API server runs image v1.37.2
  PASS  both nodes are schedulable
  PASS  kubeadm, kubelet and kubectl stay on hold on cks-w1
```

## Clean up

Task 4 is one-way: the packages stay at 1.37.2. `./certs/cks/cluster/reset.sh` puts both nodes back at 1.37.1 and rebuilds the cluster.
