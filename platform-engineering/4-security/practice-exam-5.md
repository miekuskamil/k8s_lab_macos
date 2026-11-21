# Timed practice exam 5: security, when topics collide

> New to a term here? The [glossary](../glossary.md#the-practice-cluster-and-the-security-modules) explains every term the security modules use.

**Before this practice exam:** [practice exam 4](practice-exam-4.md) under time, all tasks of modules 4.1 to 4.7, and the [practice cluster](../practice-cluster.md) and the [Lima VM](../../README.md#the-vm-for-module-44), both freshly reset.

Practice exam 4 checks that you know each topic, while this one checks that you keep your head when topics collide. The API server is down when you start, two tasks write the same admission configuration file, and one fix makes the cluster refuse every new pod until a second fix lands, which is how the real exam feels after the first hour. You get 2 hours for 17 tasks worth 100 points, on two clusters, the OrbStack cluster and the Lima VM.

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
   $ ./lab.sh exam setup 5
   == setting up task 13: The image policy fails open
   == setting up task 16: Who deleted the Secret?
   ...
   Ready. The clock runs from now: 2 hours. Open platform-engineering/4-security/practice-exam-5.md.
   Score yourself at any time with ./lab.sh exam score 5
   ```

   In the final test run, the practice cluster reset took 71 seconds, the Lima reset 2 minutes 5 seconds, and the setup 2 minutes 22 seconds. The setup breaks the API server in its last step, so it doesn't wait for any pods to start.

2. The clock starts when `setup.sh` ends, because it writes the start time, and `score.sh` prints the minutes since then and says when you went over 120.
3. Work only on the nodes, through `./lab.sh practice shell`, `./lab.sh practice shell worker` and `./platform-engineering/practice/cluster/lima.sh shell`, and use only the documentation the exam allows.
4. Don't open the solutions while the clock runs, because the score only means something when you worked without them.
5. Score from your Mac with `./lab.sh exam score 5`, or score single tasks with `./lab.sh exam score 5 3 9`.

Each task names its host, and `kubectl` runs on `practice-control-plane` for the practice cluster and on `cks-lima` for the tasks marked Lima.

## Tasks

| # | Task | Points | Module | Host |
|---|---|---|---|---|
| 1 | The API server is down | 8 | 39 | practice-control-plane |
| 2 | Lock down the payments namespace | 6 | 38 | practice-control-plane |
| 3 | HTTP rules with Cilium | 6 | 38 | cks-lima |
| 4 | Harden the worker's kubelet | 6 | 38 | practice-worker |
| 5 | TLS 1.3 only | 5 | 38 | practice-control-plane |
| 6 | Who may exec into pods? | 6 | 39 | practice-control-plane |
| 7 | A token for the vault | 5 | 39 | practice-control-plane |
| 8 | A backdoor on the worker | 4 | 40 | practice-worker |
| 9 | AppArmor for the web Deployment | 7 | 43 | cks-lima |
| 10 | Read a Secret from etcd | 5 | 41 | practice-control-plane |
| 11 | Pod Security for every namespace | 7 | 41 | practice-control-plane |
| 12 | Pods with host access | 4 | 41 | practice-control-plane |
| 13 | The image policy fails open | 7 | 42 | practice-control-plane |
| 14 | Pin by digest | 4 | 42 | practice-control-plane |
| 15 | Catch package managers with Falco | 8 | 43 | practice-worker, practice-control-plane |
| 16 | Who deleted the Secret? | 6 | 43 | practice-control-plane |
| 17 | Immutable nginx | 6 | 43 | practice-control-plane |

### Task 1: The API server is down (8 points)

**Host:** `practice-control-plane`.

> The API server on `practice-control-plane` doesn't answer. Somebody edited its manifest. Get it running again without changing what it did before the edit.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# crictl ps -a --name kube-apiserver
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                     NAMESPACE
7d5d0af53edf6       98d6e75e244ec       20 seconds ago      Exited              kube-apiserver      4                   dee2b9a849738       kube-apiserver-practice-control-plane   kube-system
root@practice-control-plane:~# crictl logs <id of the newest exited container>
I1115 20:48:41.870434       1 options.go:261] external host was not specified, using 192.168.117.2
I1115 20:48:41.872447       1 server.go:151] Version: v1.37.1
I1115 20:48:41.872476       1 server.go:153] "Golang settings" GOGC="" GOMAXPROCS="" GOTRACEBACK=""
E1115 20:48:41.880392       1 run.go:72] "command failed" err="open /etc/kubernetes/pki/apiserver.pem: no such file or directory"
```

The transcript ran `crictl logs` with the ID of the newest exited container.

The last log line names the file the API server misses, and `ls /etc/kubernetes/pki/` shows `apiserver.key`. Fix that line, wait, and read the newest container's log again, which shows that the API server now starts but fails to reach etcd. Compare its `--etcd-servers` with etcd's own flags, as [module 4.2, task 10](02-hardening-access-to-the-api.md#task-10-repair-etcd) does:

```console
root@practice-control-plane:~# grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
    - --etcd-servers=https://127.0.0.1:2380
root@practice-control-plane:~# grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml
    - --listen-client-urls=https://127.0.0.1:2379,https://192.168.117.2:2379
```

Two lines changed: `--tls-private-key-file` points to `apiserver.pem` instead of `apiserver.key`, and `--etcd-servers` names port 2380, etcd's peer port, instead of 2379. Fix both, one restart at a time, and read the log after each. [module 4.2, tasks 9 and 10](02-hardening-access-to-the-api.md#task-9-repair-the-api-server) practise the same hunt.

</details>

### Task 2: Lock down the payments namespace (6 points)

**Host:** `practice-control-plane`.

> In namespace `m2-pay`:
>
> 1. Create a NetworkPolicy `deny-all` that blocks all ingress and egress for every pod.
> 2. Pod `gateway` (`app=gateway`) may reach pod `ledger` (`app=ledger`) on TCP port 80.
> 3. `ledger` may reach pods labelled `app=postgres` on TCP port 80, but only in namespaces labelled `tier=data`.
> 4. Both pods resolve Service names. Nothing else is allowed.

<details>
<summary>Solution</summary>

Five small policies keep each path readable, which matters when you debug one of them under time: `deny-all`, an ingress rule on `ledger`, egress for `gateway`, egress for `ledger`, and DNS for every pod.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: ledger-egress, namespace: m2-pay}
spec:
  podSelector: {matchLabels: {app: ledger}}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector: {matchLabels: {tier: data}}
      podSelector: {matchLabels: {app: postgres}}
    ports: [{protocol: TCP, port: 80}]
```

The `namespaceSelector` and `podSelector` sit in one item, so both must match, because `m2-fake` also runs a pod labelled `app=postgres`, and the check makes sure `ledger` doesn't reach it. `deny-all` blocks ingress too, so `ledger` needs an ingress policy that admits `gateway`:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: ledger-ingress, namespace: m2-pay}
spec:
  podSelector: {matchLabels: {app: ledger}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: gateway}}}]
    ports: [{protocol: TCP, port: 80}]
```

`postgres` lives in another namespace without policies, so it accepts the connection. The `gateway` egress rule and the DNS rule follow [module 4.1, task 1](01-setting-up-a-secure-cluster.md#task-1-default-deny-and-one-allowed-path).

</details>

### Task 3: HTTP rules with Cilium (6 points)

**Host:** `cks-lima`.

> Pod `api` in namespace `m2-api` serves `/v1/items/`, `/v1/orders/` and `/internal/` on port 80. Create a CiliumNetworkPolicy `api-http`: pods labelled `app=web` may send `GET` to any path under `/v1/`, and `POST` to paths under `/v1/orders/`. Every other request from `web` gets an HTTP refusal, and no other pod reaches `api`.

<details>
<summary>Solution</summary>

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: api-http, namespace: m2-api}
spec:
  endpointSelector: {matchLabels: {app: api}}
  ingress:
  - fromEndpoints: [{matchLabels: {app: web}}]
    toPorts:
    - ports: [{port: "80", protocol: TCP}]
      rules:
        http:
        - {method: GET, path: "/v1/.*"}
        - {method: POST, path: "/v1/orders/.*"}
```

Each item under `http` is one allowed kind of request, and a request passes when any item matches. nginx answers a `POST` to a static file with `405 Not Allowed`, which still counts here, because the policy let the request through, and only Cilium's refusals say `403`.

</details>

### Task 4: Harden the worker's kubelet (6 points)

**Host:** `practice-worker`.

> The kubelet on `practice-worker` accepts anonymous requests, allows every authenticated caller everything, and serves the read-only port. Fix all three in its config file. The node stays Ready.

<details>
<summary>Solution</summary>

Set `authentication.anonymous.enabled: false`, `authorization.mode: Webhook` and `readOnlyPort: 0` in `/var/lib/kubelet/config.yaml`, then run `systemctl restart kubelet`. [module 4.1, task 13](01-setting-up-a-secure-cluster.md#task-13-harden-the-kubelet) explains each setting.

</details>

### Task 5: TLS 1.3 only (5 points)

**Host:** `practice-control-plane`.

> The API server must refuse every TLS version older than 1.3.

<details>
<summary>Solution</summary>

```yaml
    - --tls-min-version=VersionTLS13
```

Test with `echo | openssl s_client -connect 127.0.0.1:6443 -tls1_2 2>/dev/null | grep 'Cipher is'`, which must print `(NONE)`. TLS 1.3 has its own fixed suites, so no `--tls-cipher-suites` is needed, and every client in this cluster, from the kubelet to Calico, speaks TLS 1.3.

</details>

### Task 6: Who may exec into pods? (6 points)

**Host:** `practice-control-plane`.

> 1. One ServiceAccount in namespace `m2-team` may exec into pods in every namespace. Write its name to `/root/mock/exec-sa.txt` and remove that right. Keep the account.
> 2. That account still needs to restart Deployment `web` in `m2-team`. Create a Role `restart-web` and a RoleBinding `restart-web` that allow `get` and `patch` on that one Deployment only.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# for sa in ci docs ops; do echo "$sa $(k auth can-i create pods --subresource=exec -A --as=system:serviceaccount:m2-team:$sa)"; done
ci no
docs yes
ops no
root@practice-control-plane:~# echo docs > /root/mock/exec-sa.txt
root@practice-control-plane:~# k get clusterrolebinding -o wide | grep m2-team/docs
debug-helper                                                            ClusterRole/debug-helper                                                            6m9s                                                                                       m2-team/docs
root@practice-control-plane:~# k delete clusterrolebinding debug-helper
clusterrolebinding.rbac.authorization.k8s.io "debug-helper" deleted
root@practice-control-plane:~# k -n m2-team create role restart-web --verb=get,patch --resource=deployments.apps --resource-name=web
role.rbac.authorization.k8s.io/restart-web created
root@practice-control-plane:~# k -n m2-team create rolebinding restart-web --role=restart-web --serviceaccount=m2-team:docs
rolebinding.rbac.authorization.k8s.io/restart-web created
```

`kubectl rollout restart` is a `patch` on the Deployment, which is why `get` and `patch` are enough for the new Role.

</details>

### Task 7: A token for the vault (5 points)

**Host:** `practice-control-plane`.

> Create pod `agent` in namespace `m2-vault`, image `busybox:1.36`, command `sleep 1d`, running as ServiceAccount `reader`. It gets no default API token, and it gets a token for the audience `vault.m2`, valid for 1800 seconds, at `/var/run/secrets/tokens/vault-token`.

<details>
<summary>Solution</summary>

Set `automountServiceAccountToken: false` in the pod spec, and add a projected volume with a `serviceAccountToken` source (`audience: vault.m2`, `expirationSeconds: 1800`, `path: vault-token`) mounted at `/var/run/secrets/tokens`. [module 4.2, task 7](02-hardening-access-to-the-api.md#task-7-a-bound-token-for-another-audience) shows the full YAML.

</details>

### Task 8: A backdoor on the worker (4 points)

**Host:** `practice-worker`.

> Something listens on TCP port 5555 on `practice-worker`. Remove it for good: the process, what starts it, and its binary.

<details>
<summary>Solution</summary>

```console
root@practice-worker:~# ss -tlnp | grep ':5555 '
LISTEN 0      5                  *:5555             *:*    users:(("nel",pid=106964,fd=5))        
root@practice-worker:~# systemctl status <pid> | head -1          # node-exporter-lite.service
● node-exporter-lite.service - Node exporter (lite)
root@practice-worker:~# systemctl cat node-exporter-lite          # ExecStart=/opt/.cache/nel ... EXEC:/bin/bash
# /etc/systemd/system/node-exporter-lite.service
[Unit]
Description=Node exporter (lite)
[Service]
ExecStart=/opt/.cache/nel TCP-LISTEN:5555,fork,reuseaddr EXEC:/bin/bash
Restart=always
...
root@practice-worker:~# systemctl disable --now node-exporter-lite
Removed "/etc/systemd/system/multi-user.target.wants/node-exporter-lite.service".
root@practice-worker:~# rm /etc/systemd/system/node-exporter-lite.service /opt/.cache/nel
root@practice-worker:~# systemctl daemon-reload
```

The transcript ran `systemctl status` with the PID that `ss` printed.

The name copies a real monitoring tool, and the binary hides in a dot folder, so trust what the process does rather than what it is called.

</details>

### Task 9: AppArmor for the web Deployment (7 points)

**Host:** `cks-lima`.

> `/root/mock/m2-profile` on `cks-lima` holds an AppArmor profile named `m2-readonly-html`. Load it so it survives a reboot, and make Deployment `web` in namespace `m2-aa` run its nginx container under it.

<details>
<summary>Solution</summary>

```console
root@cks-lima:~# cp /root/mock/m2-profile /etc/apparmor.d/m2-readonly-html
root@cks-lima:~# apparmor_parser -r /etc/apparmor.d/m2-readonly-html
root@cks-lima:~# aa-status | grep m2-readonly-html
   m2-readonly-html
root@cks-lima:~# k -n m2-aa edit deploy web
```

The transcript leaves out the editor session, which makes the change the YAML below shows.

```yaml
      containers:
      - name: nginx
        securityContext:
          appArmorProfile:
            type: Localhost
            localhostProfile: m2-readonly-html
```

The profile name comes from the line `profile m2-readonly-html` inside the file, not from the file's name. Prove it with `k -n m2-aa exec deploy/web -- sh -c 'echo x >> /etc/nginx/nginx.conf'`, which fails with `Permission denied`.

The first draft of this task's profile denied writes to everything under `/etc/nginx`. In the test run, the pod then crashed at start, because nginx's entrypoint script rewrites `/etc/nginx/conf.d/default.conf`, and its log said `sed: can't create temp file '/etc/nginx/conf.d/default.confXXXXXX': Permission denied`. A profile has to allow what the program itself writes, so check the pod's log after every profile change.

</details>

### Task 10: Read a Secret from etcd (5 points)

**Host:** `practice-control-plane`.

> Read Secret `root-cred` in namespace `m2-etcd` straight from etcd with `etcdctl`. Write its etcd key to `/root/mock/root-cred-key.txt` and the value of its `password` field to `/root/mock/root-cred.txt`.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# echo /registry/secrets/m2-etcd/root-cred > /root/mock/root-cred-key.txt
root@practice-control-plane:~# etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt --key=/etc/kubernetes/pki/apiserver-etcd-client.key \
  get /registry/secrets/m2-etcd/root-cred --print-value-only | tr -cs '[:print:]' '\n' | grep -A1 -x password | tail -1 | tee /root/mock/root-cred.txt
VWVdGs0ADxi6ev1R
```

Secrets sit under `/registry/secrets/<namespace>/<name>`, and without encryption the value is protobuf with the plain password inside. `tr` turns every run of unprintable bytes into one line break, so the field name `password` lands on one line and its value on the next, and `tail -1 | tee` writes that value to the file while it shows it. `strings` does the same job where binutils is installed, but `practice-control-plane` lacks it. Search for the exact line `password`, because the object's `managedFields` also contain the text `f:password`, earlier in the value. That this works at all is the reason for [module 4.4, task 2](04-hardening-workloads.md#task-2-encrypt-secrets-at-rest).

</details>

### Task 11: Pod Security for every namespace (7 points)

**Host:** `practice-control-plane`.

> Make every namespace without Pod Security labels enforce `baseline` and warn and audit at `restricted`, with the newest rules. Exempt the namespaces `kube-system` and `m2-agents`. The API server already reads the admission configuration `/etc/kubernetes/admission/config.yaml`; put the new configuration there too.

<details>
<summary>Solution</summary>

The file already configures ImagePolicyWebhook for task 13, and one `AdmissionConfiguration` holds every plugin, so add PodSecurity as a second item of its `plugins` list, the way [module 4.4, task 7](04-hardening-workloads.md#task-7-cluster-wide-pod-security-defaults-with-exemptions) writes it:

```yaml
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults: {enforce: baseline, enforce-version: latest, warn: restricted, warn-version: latest, audit: restricted, audit-version: latest}
    exemptions: {usernames: [], runtimeClasses: [], namespaces: [kube-system, m2-agents]}
```

Then restart the API server by moving its manifest out and back. The flag `--admission-control-config-file` takes one file, which is why every plugin's configuration shares it.

</details>

### Task 12: Pods with host access (4 points)

**Host:** `practice-control-plane`.

> Delete every pod in namespace `m2-legacy` that shares a host namespace, mounts a `hostPath` volume, or has any privileged container.

<details>
<summary>Solution</summary>

Use the `jsonpath` from [module 4.4, task 8](04-hardening-workloads.md#task-8-pods-that-reach-into-the-node), and add `{.spec.hostIPC}`. `shell` shares IPC, `backup` mounts `/etc`, and `sidecar-priv` hides a privileged container in second place, so only `app` stays.

</details>

### Task 13: The image policy fails open (7 points)

**Host:** `practice-control-plane`.

> ImagePolicyWebhook is on, but pods from any registry get in. Make the API server refuse new pods whenever the back end doesn't answer, and bring the back end `image-policy` back, also after a reboot.

<details>
<summary>Solution</summary>

The setup left `defaultAllow: true` in `/etc/kubernetes/admission/config.yaml` and stopped and disabled the service. Set `defaultAllow: false`, run `systemctl enable --now image-policy`, and restart the API server, in the order [module 4.5, task 7](05-supply-chain-security.md#task-7-the-back-end-is-down-and-nobody-noticed) explains. Do this one early, because once `defaultAllow` is false and the back end is down, every pod that another task creates fails.

</details>

### Task 14: Pin by digest (4 points)

**Host:** `practice-control-plane`.

> Deployment `worker` in namespace `m2-pin` runs `busybox:1.36`. Make it name the exact image it runs now by digest.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# k -n m2-pin get pod -l app=worker -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'; echo
docker.io/library/busybox@sha256:73aaf090f3d85aa34ee199857f03fa3a95c8ede2ffd4cc2cdb5b94e566b11662
root@practice-control-plane:~# k -n m2-pin set image deploy/worker busybox=busybox@sha256:<digest>
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "busybox" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "busybox" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "busybox" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "busybox" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/worker image updated
```

The transcript ran the second command with the digest that the first command printed.

</details>

### Task 15: Catch package managers with Falco (8 points)

**Hosts:** `practice-worker`, then `practice-control-plane`.

> 1. In `/etc/falco/rules.d/m2.yaml` on `practice-worker`, write a list `m2_pkg` (`apk`, `apt`, `apt-get`, `pip`, `npm`), a macro `m2_k8s` that matches processes in a Kubernetes pod, and a rule `Package manager in container (mock)` with priority `CRITICAL` and the output `pkg (ns=%k8s.ns.name pod=%k8s.pod.name cmd=%proc.cmdline)`.
> 2. One Deployment in namespace `m2-run` runs a package manager over and over. Find it with your rule, write its name to `/root/mock/pkg-deploy.txt` on `practice-control-plane`, and scale it to 0.

<details>
<summary>Solution</summary>

The rules file follows [module 4.6, task 7](06-runtime-security-and-auditing.md#task-7-a-falco-rule-with-a-list-and-a-macro). Once Falco has reloaded it, search the journal for the new alert:

```console
root@practice-worker:~# journalctl -u falco-modern-bpf --since -2min | grep 'Critical pkg (ns=m2-run'
Nov 15 20:53:01 practice-worker falco[100721]: 20:53:01.700568680: Critical pkg (ns=m2-run pod=updater-564c95db65-s8km4 cmd=apk info) container_id=2ca2f179f12d container_name=nginx container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=updater-564c95db65-s8km4 k8s_ns_name=m2-run
Nov 15 20:53:11 practice-worker falco[100721]: 20:53:11.716044499: Critical pkg (ns=m2-run pod=updater-564c95db65-s8km4 cmd=apk info) container_id=2ca2f179f12d container_name=nginx container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=updater-564c95db65-s8km4 k8s_ns_name=m2-run
Nov 15 20:53:21 practice-worker falco[100721]: 20:53:21.727186484: Critical pkg (ns=m2-run pod=updater-564c95db65-s8km4 cmd=apk info) container_id=2ca2f179f12d container_name=nginx container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=updater-564c95db65-s8km4 k8s_ns_name=m2-run
Nov 15 20:53:31 practice-worker falco[100721]: 20:53:31.742812428: Critical pkg (ns=m2-run pod=updater-564c95db65-s8km4 cmd=apk info) container_id=2ca2f179f12d container_name=nginx container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=updater-564c95db65-s8km4 k8s_ns_name=m2-run
Nov 15 20:53:41 practice-worker falco[100721]: 20:53:41.755952372: Critical pkg (ns=m2-run pod=updater-564c95db65-s8km4 cmd=apk info) container_id=2ca2f179f12d container_name=nginx container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=updater-564c95db65-s8km4 k8s_ns_name=m2-run
Nov 15 20:53:51 practice-worker falco[100721]: 20:53:51.763119148: Critical pkg (ns=m2-run pod=updater-564c95db65-s8km4 cmd=apk info) container_id=2ca2f179f12d container_name=nginx container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=updater-564c95db65-s8km4 k8s_ns_name=m2-run
```

Ignore the lines with `cmd=apk --version` if you tested your rule by hand. The pod name starts with its Deployment's name, and `k -n m2-run get pod <pod> --show-labels` confirms it:

```console
root@practice-control-plane:~# echo updater > /root/mock/pkg-deploy.txt
root@practice-control-plane:~# k -n m2-run scale deploy updater --replicas=0
deployment.apps/updater scaled
```

</details>

### Task 16: Who deleted the Secret? (6 points)

**Host:** `practice-control-plane`.

> Secret `api-keys` in namespace `m2-audit` is gone. Find the user who deleted it in the audit log `/var/log/kubernetes/audit/audit.log`, write the name to `/root/mock/deleter.txt`, and remove that user's RoleBinding in `m2-audit`.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# grep '"verb":"delete"' /var/log/kubernetes/audit/audit.log | grep '"name":"api-keys"' | grep ResponseComplete | grep -o '"username":"[^"]*"'
"username":"erin"
root@practice-control-plane:~# echo erin > /root/mock/deleter.txt
root@practice-control-plane:~# k -n m2-audit delete rolebinding erin
rolebinding.rbac.authorization.k8s.io "erin" deleted from m2-audit namespace
```

`frank` deleted a Secret too, `tls-old`, and `dave` read `api-keys` before it went, but the question names one object, so only one user is the answer.

</details>

### Task 17: Immutable nginx (6 points)

**Host:** `practice-control-plane`.

> Deployment `web` in namespace `m2-hard` runs nginx. Make its root file system read-only, forbid privilege escalation, and give it the runtime's default seccomp profile. nginx keeps serving.

<details>
<summary>Solution</summary>

Set `readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false` and `seccompProfile: {type: RuntimeDefault}` in the container's `securityContext`, and add `emptyDir` volumes at `/var/cache/nginx`, `/run` and `/tmp`, as in [module 4.6, task 3](06-runtime-security-and-auditing.md#task-3-make-a-container-immutable).

</details>

## Scoring

`score.sh` runs two to six checks per task, splits the task's points evenly over them, rounded down, and gives points only when a task's first check passes.

In the final test run, on clusters fresh from both resets and `setup.sh`, the score was `TOTAL: 0 of 100 points (0%).` with `TIME: 2 minutes since setup, 118 minutes left.` After `./lab.sh exam solve 5`, which applies every solution above in its order (1, 13, 11, 5, then the rest) in 3 minutes 43 seconds, it was `TOTAL: 100 of 100 points (100%).`

Earlier test runs found three faults in the scoring, and each changed the checks. A check that asks "is it gone?" passed while the API server was down, so it now also asks something that must succeed. Right after the API server restarts for task 5, Calico needed longer than 30 seconds to apply new policies, so the reachability checks of task 2 retry for up to 3 minutes while the API server answers. `wget` also exits with an error on a `403`, which the scorer read as a failed check until it looked at the output instead. While the API server is down, `score.sh` takes a few minutes, because the network checks retry before they give up.
