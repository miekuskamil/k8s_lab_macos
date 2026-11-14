# CKS mock exam 2

> New to a term here? The [glossary](../../platform-engineering/glossary.md#cks-exam-track) explains every term this track uses.

**Before this mock exam:** [mock exam 1](mock-exam.md) under time, and all 13 tasks of each domain file. The [practice cluster](../README.md#the-practice-cluster) and the [Lima VM](../README.md#the-lima-vm-for-apparmor-and-cilium), both freshly reset.

Mock exam 1 checks that you know each topic. This one checks that you keep your head when topics collide. The API server is down when you start. Two tasks write the same admission configuration file. One fix makes the cluster refuse every new pod until a second fix lands. That's how the real exam feels after the first hour. You get 2 hours for 17 tasks worth 100 points, on two clusters: the OrbStack cluster and the Lima VM.

## Rules

1. Start fresh. On your Mac:

   ```bash
   ./certs/cks/cluster/reset.sh && ./certs/cks/cluster/lima.sh reset
   MOCK=2 ./certs/cks/mock-exam/setup.sh
   ```

   In the final test run, the OrbStack reset took 4 minutes 59 seconds, the Lima reset 1 minute 24 seconds, and the setup 2 minutes 11 seconds. The setup breaks the API server in its last step, so it doesn't wait for any pods.

2. The clock starts when `setup.sh` ends. It writes the start time, and `score.sh` prints the minutes since then and says when you went over 120.
3. Work only on the nodes: `orb -m cks-cp`, `orb -m cks-w1` and `./certs/cks/cluster/lima.sh shell`. Use only the documentation the exam allows.
4. Don't open the solutions while the clock runs.
5. Score from your Mac: `MOCK=2 ./certs/cks/mock-exam/score.sh`, or single tasks with `MOCK=2 ./certs/cks/mock-exam/score.sh 3 9`.

Each task names its host. Run `kubectl` on `cks-cp` for the OrbStack cluster, and on `cks-lima` for the tasks marked Lima.

## Tasks

| # | Task | Points | Domain | Host |
|---|---|---|---|---|
| 1 | The API server is down | 8 | 02 | cks-cp |
| 2 | Lock down the payments namespace | 6 | 01 | cks-cp |
| 3 | HTTP rules with Cilium | 6 | 01 | cks-lima |
| 4 | Harden the worker's kubelet | 6 | 01 | cks-w1 |
| 5 | TLS 1.3 only | 5 | 01 | cks-cp |
| 6 | Who may exec into pods? | 6 | 02 | cks-cp |
| 7 | A token for the vault | 5 | 02 | cks-cp |
| 8 | A backdoor on the worker | 4 | 03 | cks-w1 |
| 9 | AppArmor for the web Deployment | 7 | 06 | cks-lima |
| 10 | Read a Secret from etcd | 5 | 04 | cks-cp |
| 11 | Pod Security for every namespace | 7 | 04 | cks-cp |
| 12 | Pods with host access | 4 | 04 | cks-cp |
| 13 | The image policy fails open | 7 | 05 | cks-cp |
| 14 | Pin by digest | 4 | 05 | cks-cp |
| 15 | Catch package managers with Falco | 8 | 06 | cks-w1, cks-cp |
| 16 | Who deleted the Secret? | 6 | 06 | cks-cp |
| 17 | Immutable nginx | 6 | 06 | cks-cp |

### Task 1: The API server is down (8 points)

**Host:** `cks-cp`.

> The API server on `cks-cp` doesn't answer. Somebody edited its manifest. Get it running again without changing what it did before the edit.

<details>
<summary>Solution</summary>

```bash
crictl ps -a --name kube-apiserver
crictl logs <id of the newest exited container>
```

In the test run, the first exited container said:

```
"command failed" err="open /etc/kubernetes/pki/apiserver.pem: no such file or directory"
```

`ls /etc/kubernetes/pki/` shows `apiserver.key`. Fix that line, wait, and read the newest container's log again: the API server now starts but fails to reach etcd. Compare its `--etcd-servers` with etcd's own flags, as [02, task 10](02-cluster-hardening.md#task-10-repair-etcd) does:

```bash
grep etcd-servers /etc/kubernetes/manifests/kube-apiserver.yaml
grep listen-client-urls /etc/kubernetes/manifests/etcd.yaml
```

Two lines changed: `--tls-private-key-file` points to `apiserver.pem` instead of `apiserver.key`, and `--etcd-servers` names port 2380, etcd's peer port, instead of 2379. Fix both, one restart at a time, reading the log after each. [02, tasks 9 and 10](02-cluster-hardening.md#task-9-repair-the-api-server) practise the same hunt.

</details>

### Task 2: Lock down the payments namespace (6 points)

**Host:** `cks-cp`.

> In namespace `m2-pay`:
>
> 1. Create a NetworkPolicy `deny-all` that blocks all ingress and egress for every pod.
> 2. Pod `gateway` (`app=gateway`) may reach pod `ledger` (`app=ledger`) on TCP port 80.
> 3. `ledger` may reach pods labelled `app=postgres` on TCP port 80, but only in namespaces labelled `tier=data`.
> 4. Both pods resolve Service names. Nothing else is allowed.

<details>
<summary>Solution</summary>

Five small policies keep each path readable: `deny-all`, an ingress rule on `ledger`, egress for `gateway`, egress for `ledger`, and DNS for every pod.

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

The `namespaceSelector` and `podSelector` sit in one item, so both must match: `m2-fake` also runs a pod labelled `app=postgres`, and the check makes sure `ledger` doesn't reach it. `deny-all` blocks ingress too, so `ledger` needs an ingress policy that admits `gateway`:

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

`postgres` lives in another namespace without policies, so it accepts the connection. The `gateway` egress rule and the DNS rule follow [01, task 1](01-cluster-setup.md#task-1-default-deny-and-one-allowed-path).

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

Each item under `http` is one allowed kind of request, and a request passes when any item matches. nginx answers a `POST` to a static file with `405 Not Allowed`. That still counts here: the policy let the request through, and only Cilium's refusals say `403`.

</details>

### Task 4: Harden the worker's kubelet (6 points)

**Host:** `cks-w1`.

> The kubelet on `cks-w1` accepts anonymous requests, allows every authenticated caller everything, and serves the read-only port. Fix all three in its config file. The node stays Ready.

<details>
<summary>Solution</summary>

In `/var/lib/kubelet/config.yaml`: `authentication.anonymous.enabled: false`, `authorization.mode: Webhook`, `readOnlyPort: 0`. Then `systemctl restart kubelet`. [01, task 13](01-cluster-setup.md#task-13-harden-the-kubelet) explains each setting.

</details>

### Task 5: TLS 1.3 only (5 points)

**Host:** `cks-cp`.

> The API server must refuse every TLS version older than 1.3.

<details>
<summary>Solution</summary>

```yaml
    - --tls-min-version=VersionTLS13
```

Test with `echo | openssl s_client -connect 127.0.0.1:6443 -tls1_2 2>/dev/null | grep 'Cipher is'`, which must print `(NONE)`. TLS 1.3 has its own fixed suites, so no `--tls-cipher-suites` is needed. Every client in this cluster, from the kubelet to Calico, speaks TLS 1.3.

</details>

### Task 6: Who may exec into pods? (6 points)

**Host:** `cks-cp`.

> 1. One ServiceAccount in namespace `m2-team` may exec into pods in every namespace. Write its name to `/root/mock/exec-sa.txt` and remove that right. Keep the account.
> 2. That account still needs to restart Deployment `web` in `m2-team`. Create a Role `restart-web` and a RoleBinding `restart-web` that allow `get` and `patch` on that one Deployment only.

<details>
<summary>Solution</summary>

```bash
for sa in ci docs ops; do echo "$sa $(k auth can-i create pods/exec -A --as=system:serviceaccount:m2-team:$sa)"; done
echo docs > /root/mock/exec-sa.txt
k get clusterrolebinding -o wide | grep m2-team/docs
k delete clusterrolebinding debug-helper
k -n m2-team create role restart-web --verb=get,patch --resource=deployments.apps --resource-name=web
k -n m2-team create rolebinding restart-web --role=restart-web --serviceaccount=m2-team:docs
```

`kubectl rollout restart` is a `patch` on the Deployment, which is why `patch` is enough.

</details>

### Task 7: A token for the vault (5 points)

**Host:** `cks-cp`.

> Create pod `agent` in namespace `m2-vault`, image `busybox:1.36`, command `sleep 1d`, running as ServiceAccount `reader`. It gets no default API token, and it gets a token for the audience `vault.m2`, valid for 1800 seconds, at `/var/run/secrets/tokens/vault-token`.

<details>
<summary>Solution</summary>

`automountServiceAccountToken: false` in the pod spec, and a projected volume with a `serviceAccountToken` source (`audience: vault.m2`, `expirationSeconds: 1800`, `path: vault-token`) mounted at `/var/run/secrets/tokens`. [02, task 7](02-cluster-hardening.md#task-7-a-bound-token-for-another-audience) shows the full YAML.

</details>

### Task 8: A backdoor on the worker (4 points)

**Host:** `cks-w1`.

> Something listens on TCP port 5555 on `cks-w1`. Remove it for good: the process, what starts it, and its binary.

<details>
<summary>Solution</summary>

```bash
ss -tlnp | grep ':5555 '
systemctl status <pid> | head -1          # node-exporter-lite.service
systemctl cat node-exporter-lite          # ExecStart=/opt/.cache/nel ... EXEC:/bin/bash
systemctl disable --now node-exporter-lite
rm /etc/systemd/system/node-exporter-lite.service /opt/.cache/nel
systemctl daemon-reload
```

The name copies a real monitoring tool, and the binary hides in a dot folder. Trust what the process does, not what it's called.

</details>

### Task 9: AppArmor for the web Deployment (7 points)

**Host:** `cks-lima`.

> `/root/mock/m2-profile` on `cks-lima` holds an AppArmor profile named `m2-readonly-html`. Load it so it survives a reboot, and make Deployment `web` in namespace `m2-aa` run its nginx container under it.

<details>
<summary>Solution</summary>

```bash
cp /root/mock/m2-profile /etc/apparmor.d/m2-readonly-html
apparmor_parser -r /etc/apparmor.d/m2-readonly-html
aa-status | grep m2-readonly-html
k -n m2-aa edit deploy web
```

```yaml
      containers:
      - name: nginx
        securityContext:
          appArmorProfile:
            type: Localhost
            localhostProfile: m2-readonly-html
```

The profile name comes from the line `profile m2-readonly-html` inside the file, not from the file's name. Prove it: `k -n m2-aa exec deploy/web -- sh -c 'echo x >> /etc/nginx/nginx.conf'` fails with `Permission denied`.

The first draft of this task's profile denied writes to everything under `/etc/nginx`. In the test run, the pod then crashed at start: nginx's entrypoint script rewrites `/etc/nginx/conf.d/default.conf`, and its log said `sed: can't create temp file '/etc/nginx/conf.d/default.confXXXXXX': Permission denied`. A profile has to allow what the program itself writes, so check the pod's log after every profile change.

</details>

### Task 10: Read a Secret from etcd (5 points)

**Host:** `cks-cp`.

> Read Secret `root-cred` in namespace `m2-etcd` straight from etcd with `etcdctl`. Write its etcd key to `/root/mock/root-cred-key.txt` and the value of its `password` field to `/root/mock/root-cred.txt`.

<details>
<summary>Solution</summary>

```bash
echo /registry/secrets/m2-etcd/root-cred > /root/mock/root-cred-key.txt
etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt --key=/etc/kubernetes/pki/apiserver-etcd-client.key \
  get /registry/secrets/m2-etcd/root-cred --print-value-only | tr -cs '[:print:]' '\n' | grep -A1 -x password
```

Secrets sit under `/registry/secrets/<namespace>/<name>`. Without encryption, the value is protobuf with the plain password inside. `tr` turns every run of unprintable bytes into one line break, so the field name `password` lands on one line and its value on the next. `strings` does the same job where binutils is installed, and `cks-cp` lacks it. Search for the exact line `password`: the object's `managedFields` also contain the text `f:password`, earlier in the value. That this works at all is the reason for [04, task 2](04-minimize-microservice-vulnerabilities.md#task-2-encrypt-secrets-at-rest).

</details>

### Task 11: Pod Security for every namespace (7 points)

**Host:** `cks-cp`.

> Make every namespace without Pod Security labels enforce `baseline` and warn and audit at `restricted`, with the newest rules. Exempt the namespaces `kube-system` and `m2-agents`. The API server already reads the admission configuration `/etc/kubernetes/admission/config.yaml`; put the new configuration there too.

<details>
<summary>Solution</summary>

The file already configures ImagePolicyWebhook for task 13. One `AdmissionConfiguration` holds every plugin, so add PodSecurity as a second item of its `plugins` list, the way [04, task 7](04-minimize-microservice-vulnerabilities.md#task-7-cluster-wide-pod-security-defaults-with-exemptions) writes it:

```yaml
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults: {enforce: baseline, enforce-version: latest, warn: restricted, warn-version: latest, audit: restricted, audit-version: latest}
    exemptions: {usernames: [], runtimeClasses: [], namespaces: [kube-system, m2-agents]}
```

Then restart the API server by moving its manifest out and back. The flag `--admission-control-config-file` takes one file, so every plugin's configuration shares it.

</details>

### Task 12: Pods with host access (4 points)

**Host:** `cks-cp`.

> Delete every pod in namespace `m2-legacy` that shares a host namespace, mounts a `hostPath` volume, or has any privileged container.

<details>
<summary>Solution</summary>

Use the `jsonpath` from [04, task 8](04-minimize-microservice-vulnerabilities.md#task-8-pods-that-reach-into-the-node), and add `{.spec.hostIPC}`. `shell` shares IPC, `backup` mounts `/etc`, and `sidecar-priv` hides a privileged container in second place. Only `app` stays.

</details>

### Task 13: The image policy fails open (7 points)

**Host:** `cks-cp`.

> ImagePolicyWebhook is on, but pods from any registry get in. Make the API server refuse new pods whenever the back end doesn't answer, and bring the back end `image-policy` back, also after a reboot.

<details>
<summary>Solution</summary>

`defaultAllow: true` in `/etc/kubernetes/admission/config.yaml`, and the service is stopped and disabled. Set `defaultAllow: false`, run `systemctl enable --now image-policy`, and restart the API server. [05, task 7](05-supply-chain-security.md#task-7-the-back-end-is-down-and-nobody-noticed) explains the order. Do this one early: once `defaultAllow` is false and the back end is down, every pod that another task creates fails.

</details>

### Task 14: Pin by digest (4 points)

**Host:** `cks-cp`.

> Deployment `worker` in namespace `m2-pin` runs `busybox:1.36`. Make it name the exact image it runs now by digest.

<details>
<summary>Solution</summary>

```bash
k -n m2-pin get pod -l app=worker -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'; echo
k -n m2-pin set image deploy/worker busybox=busybox@sha256:<digest>
```

</details>

### Task 15: Catch package managers with Falco (8 points)

**Hosts:** `cks-w1`, then `cks-cp`.

> 1. In `/etc/falco/rules.d/m2.yaml` on `cks-w1`, write a list `m2_pkg` (`apk`, `apt`, `apt-get`, `pip`, `npm`), a macro `m2_k8s` that matches processes in a Kubernetes pod, and a rule `Package manager in container (mock)` with priority `CRITICAL` and the output `pkg (ns=%k8s.ns.name pod=%k8s.pod.name cmd=%proc.cmdline)`.
> 2. One Deployment in namespace `m2-run` runs a package manager over and over. Find it with your rule, write its name to `/root/mock/pkg-deploy.txt` on `cks-cp`, and scale it to 0.

<details>
<summary>Solution</summary>

The rules file follows [06, task 7](06-monitoring-logging-runtime-security.md#task-7-a-falco-rule-with-a-list-and-a-macro). Once Falco has reloaded it:

```bash
journalctl -u falco-modern-bpf --since -2min | grep 'Critical pkg (ns=m2-run'
```

In the test run, the line read:

```
Critical pkg (ns=m2-run pod=updater-564c95db65-lmh5l cmd=apk info) container_id=a6a476a0a0b9 container_name=nginx ...
```

Ignore the lines with `cmd=apk --version` if you tested your rule by hand. The pod name starts with its Deployment's name, and `k -n m2-run get pod <pod> --show-labels` confirms it:

```bash
echo updater > /root/mock/pkg-deploy.txt
k -n m2-run scale deploy updater --replicas=0
```

</details>

### Task 16: Who deleted the Secret? (6 points)

**Host:** `cks-cp`.

> Secret `api-keys` in namespace `m2-audit` is gone. Find the user who deleted it in the audit log `/var/log/kubernetes/audit/audit.log`, write the name to `/root/mock/deleter.txt`, and remove that user's RoleBinding in `m2-audit`.

<details>
<summary>Solution</summary>

```bash
grep '"verb":"delete"' /var/log/kubernetes/audit/audit.log | grep '"name":"api-keys"' | grep ResponseComplete | grep -o '"username":"[^"]*"'
echo erin > /root/mock/deleter.txt
k -n m2-audit delete rolebinding erin
```

`frank` deleted a Secret too, `tls-old`, and `dave` read `api-keys` before it went. The question names one object, so only one user is the answer.

</details>

### Task 17: Immutable nginx (6 points)

**Host:** `cks-cp`.

> Deployment `web` in namespace `m2-hard` runs nginx. Make its root file system read-only, forbid privilege escalation, and give it the runtime's default seccomp profile. nginx keeps serving.

<details>
<summary>Solution</summary>

`readOnlyRootFilesystem: true`, `allowPrivilegeEscalation: false` and `seccompProfile: {type: RuntimeDefault}` in the container's `securityContext`, plus `emptyDir` volumes at `/var/cache/nginx`, `/run` and `/tmp`, as in [06, task 3](06-monitoring-logging-runtime-security.md#task-3-make-a-container-immutable).

</details>

## Scoring

`score.sh` runs two to six checks per task, splits the task's points evenly over them, rounded down, and gives points only when a task's first check passes.

In the final test run, on clusters fresh from both resets and `setup.sh`, the score was `TOTAL: 0 of 100 points (0%).` with `TIME: 2 minutes since setup, 118 minutes left.` After `MOCK=2 ./certs/cks/mock-exam/solve.sh`, which applies every solution above in its order (1, 13, 11, 5, then the rest) in 3 minutes 43 seconds, it was `TOTAL: 100 of 100 points (100%).`

Earlier test runs found three faults in the scoring, and each changed the checks. A check that asks "is it gone?" passed while the API server was down, so it now also asks something that must succeed. Right after the API server restarts for task 5, Calico needed longer than 30 seconds to apply new policies, so the reachability checks of task 2 retry for up to 3 minutes while the API server answers. And `wget` exits with an error on a `403`, which the scorer read as a failed check until it looked at the output instead. While the API server is down, `score.sh` takes a few minutes, because the network checks retry before they give up.
