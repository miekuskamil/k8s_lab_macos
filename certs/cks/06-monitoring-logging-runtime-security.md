# CKS 06: Monitoring, logging and runtime security (20%)

> New to a term here, like audit policy or syscall? The [glossary](../../course/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) running, ideally fresh from `./certs/cks/cluster/reset.sh`. The course's [module 10](../../course/10-ebpf-and-cilium.md#concept-what-ebpf-is) explains eBPF, the technique Falco uses to watch the kernel.

The other domains try to keep attackers out. This one assumes somebody got in anyway. Then three questions matter: what did they do through the API, what are they doing inside the container right now, and how much damage does the container let them do. Audit logs answer the first, Falco the second, and immutable root file systems, seccomp and AppArmor limit the third. This domain has six tasks and takes about 60 minutes.

## Theory: watch the API, watch the kernel, limit the damage

### Audit logs

The API server handles every change to the cluster, so it's the one place that sees who did what. An **audit log** records those requests. kubeadm leaves it off. The **audit policy** decides what to record, rule by rule, and the first rule that matches a request wins. Each rule sets a level:

| Level | Records |
|---|---|
| `None` | nothing |
| `Metadata` | who, when, which verb on which object, the response code. No bodies |
| `Request` | metadata plus the object the client sent |
| `RequestResponse` | metadata plus both the request and the response bodies |

Two habits keep the log useful. Put Secrets, ConfigMaps and TokenReviews at `Metadata` and near the top, because a body at `Request` or above would copy every password into a log file. And end with a catch-all rule, usually `- level: None` or `- level: Metadata`, so you decide what happens to everything else instead of leaving it to chance.

The API server writes the log as one JSON object per line. Four flags control it: the policy file, the log path, and how many days, files and megabytes to keep. Both the policy and the log folder live on the node, so the API server pod needs two `hostPath` volumes, and the log one must be writable.

### Falco

A **system call**, or syscall, is a request from a program to the kernel: open a file, start a process, open a connection. Everything a container does turns into syscalls, and attackers do too. **Falco** is a CNCF runtime security tool that watches syscalls through an eBPF probe and compares each one with rules. A rule has a condition and an output:

```yaml
- rule: Shell in container (cks)
  desc: A shell runs inside a container
  condition: spawned_process and container and proc.name in (sh, bash, ash, dash)
  output: "shell in container (user=%user.name ns=%k8s.ns.name pod=%k8s.pod.name cmd=%proc.cmdline)"
  priority: WARNING
```

`spawned_process` and `container` are **macros**, named conditions from Falco's default rules. The `%` fields fill the output with details of the event. Falco loads `/etc/falco/falco_rules.yaml`, then `falco_rules.local.yaml`, then every file in `/etc/falco/rules.d/`. It watches those files and reloads by itself when one changes.

On the practice cluster, Falco runs as the systemd service `falco-modern-bpf` on `cks-w1` and logs to the journal. `journalctl -u falco-modern-bpf` shows its alerts. Out of the box it already flags, among others, a read of `/etc/shadow` with `Sensitive file opened for reading by non-trusted program`.

Falco on OrbStack sees more than its own node, because every machine shares one kernel. In the test run, Falco on `cks-w1` reported `Log files were tampered` for `/var/log/kubeadm-init.log` on `cks-cp`, and alerted on commands typed into the `cks-cp` shell, listed as `container_id=container/01` with `ns=<NA>`. Filter alerts by `ns=` or `k8s_pod_name=` to see only pods.

### Immutable containers

An **immutable** container never changes after it starts. Its image is the whole truth. An attacker who finds no writable file system has nowhere to drop a tool, change a config file or replace a binary. `readOnlyRootFilesystem: true` makes the container's root file system read-only. Most programs still need a few writable folders for caches, sockets and temporary files. Each gets an `emptyDir` volume. nginx needs three: `/var/cache/nginx`, `/run` and `/tmp`.

### seccomp and AppArmor

![One system call passes seccomp, then AppArmor, then reaches the kernel; Falco gets a copy and writes an alert](../../docs/diagrams/chapters/cks-runtime-layers.svg)

The diagram follows one `open()` call from a container:

1. The container's process makes the call.
2. **seccomp** checks the syscall's number against a filter and blocks the ones the profile forbids. It knows nothing about files or paths.
3. **AppArmor** checks the file path or capability against a profile and blocks what the profile denies.
4. The kernel does the work, and Falco's probe gets a copy of the event.
5. Falco matches a rule and writes an alert. It blocks nothing.

A seccomp profile is a JSON file with a default action and a list of syscalls with their own action. Kubernetes loads `Localhost` profiles from `/var/lib/kubelet/seccomp/` on the node that runs the pod, and the pod names the path below that folder. `RuntimeDefault` uses containerd's built-in profile, an allow list that leaves out dangerous syscalls such as `mount`, `reboot` and `kexec_load`. The `restricted` standard asks for it.

An AppArmor profile is a text file of path rules, loaded into the kernel with `apparmor_parser`. A pod asks for it with `securityContext.appArmorProfile`. Before Kubernetes 1.30, an annotation did this job. The exam still shows old tasks with it, but write the field.

The practice cluster has no AppArmor, because OrbStack's kernel lacks it. The test run showed what happens: the API server accepts the pod, and the kubelet refuses it with `Cannot enforce AppArmor: AppArmor is not enabled on the host`. `apparmor_parser -Q` still parses a profile without loading it, which catches every syntax error. In the exam, the full sequence on the node is:

```bash
apparmor_parser -q /etc/apparmor.d/cks-deny-write    # load it into the kernel
aa-status | grep cks-deny-write                       # check it's loaded
```

### Investigating an attack

An attack moves through phases: get in, look around, gain more rights, reach the goal, cover the tracks. Each phase leaves different traces. The audit log shows API calls, and since 1.30 a service account token's audit entry also names the pod and node it came from. Falco shows what happened inside containers. Put the two side by side, and you see the whole path.

## Task 1: Turn on audit logging

**Time budget:** 10 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 6.1
```

> Turn on audit logging in the API server:
>
> 1. The policy lives at `/etc/kubernetes/audit/policy.yaml`. It logs Secrets in every namespace at `Metadata`, everything in namespace `audit-me` at `RequestResponse`, and nothing else. Skip the `RequestReceived` stage.
> 2. The log goes to `/var/log/kubernetes/audit/audit.log`, kept 30 days, at most 10 old files of at most 100 MB each.

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
    resources: [secrets]
- level: RequestResponse
  namespaces: [audit-me]
- level: None
```

Order matters. The Secrets rule comes first, so a Secret in `audit-me` gets `Metadata`, not `RequestResponse` with its contents.

In the API server manifest, after a backup:

```yaml
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=30
    - --audit-log-maxbackup=10
    - --audit-log-maxsize=100
...
    volumeMounts:
    - mountPath: /etc/kubernetes/audit
      name: audit-policy
      readOnly: true
    - mountPath: /var/log/kubernetes/audit
      name: audit-log
      readOnly: false
...
  volumes:
  - hostPath:
      path: /etc/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-policy
  - hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-log
```

When the API server is back, make a request and read the log:

```bash
k -n audit-me get secret token
tail -1 /var/log/kubernetes/audit/audit.log | python3 -m json.tool | head -20
```

</details>

```bash
./certs/cks/task.sh check 6.1
```

The check makes three requests and looks for each one in the log. In the test run, after the solution:

```
  PASS  --audit-policy-file is /etc/kubernetes/audit/policy.yaml
  PASS  --audit-log-path is /var/log/kubernetes/audit/audit.log
  PASS  --audit-log-maxage=30, maxbackup=10, maxsize=100
  PASS  a get on a Secret appears at level Metadata
  PASS  no Secret appears with its body
  PASS  a configmap create in audit-me appears at RequestResponse
  PASS  a configmap create in default does not appear
```

## Task 2: Catch a shell with Falco

**Time budget:** 8 minutes. **Host:** `cks-w1`.

```bash
./certs/cks/task.sh setup 6.2
```

> Write a Falco rule named `Shell in container (cks)` in `/etc/falco/rules.d/cks-shell.yaml`. It fires with priority `WARNING` whenever `sh`, `bash`, `ash` or `dash` starts in a container. Its output contains the namespace as `ns=<namespace>`, the pod as `pod=<pod>`, the user and the command line. Then open a shell in pod `target` in namespace `falco-test` and find the alert.

<details>
<summary>Solution</summary>

```yaml
- rule: Shell in container (cks)
  desc: A shell runs inside a container
  condition: spawned_process and container and proc.name in (sh, bash, ash, dash)
  output: "shell in container (time=%evt.time user=%user.name ns=%k8s.ns.name pod=%k8s.pod.name container=%container.name cmd=%proc.cmdline)"
  priority: WARNING
```

Save it, and Falco reloads by itself. Check the reload and fire the rule:

```bash
journalctl -u falco-modern-bpf -n 20 | grep cks-shell        # "schema validation: ok"
k -n falco-test exec target -- sh -c 'echo hello'             # on cks-cp
journalctl -u falco-modern-bpf --since -1min | grep 'ns=falco-test'
```

In the test run, the alert read:

```
Warning shell in container (time=00:27:32.006475786 user=root ns=falco-test pod=target container=target cmd=sh -c echo marker42)
```

Falco's documentation, which the exam allows, lists every field under "Supported Fields". When a task asks for a format such as `%evt.time,%user.name,%proc.name`, copy it into `output` exactly.

</details>

```bash
./certs/cks/task.sh check 6.2
```

```
  PASS  a rule named 'Shell in container (cks)' exists in /etc/falco/rules.d/
  PASS  falco accepts every rules file
  PASS  a shell in falco-test/target produces the alert with namespace, pod and command
```

## Task 3: Make a container immutable

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 6.3
```

> Deployment `web` in namespace `immutable` runs nginx. Make its container's root file system read-only. nginx must keep serving.

<details>
<summary>Solution</summary>

`k -n immutable edit deploy web`, and add to the pod template:

```yaml
      containers:
      - name: nginx
        securityContext:
          readOnlyRootFilesystem: true
        volumeMounts:
        - {name: cache, mountPath: /var/cache/nginx}
        - {name: run, mountPath: /run}
        - {name: tmp, mountPath: /tmp}
      volumes:
      - {name: cache, emptyDir: {}}
      - {name: run, emptyDir: {}}
      - {name: tmp, emptyDir: {}}
```

Without the volumes, nginx exits at start. In the test run, the pod went into `CrashLoopBackOff`, and its log said `mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)`. Prove both sides:

```bash
k -n immutable exec deploy/web -- touch /cks-was-here    # Read-only file system
k -n immutable run t --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- http://web | head -4
```

</details>

```bash
./certs/cks/task.sh check 6.3
```

```
  PASS  container web has readOnlyRootFilesystem: true
  PASS  the Deployment's pod is Ready
  PASS  writing to / fails inside the pod
  PASS  nginx still serves on the Service
```

## Task 4: A seccomp profile

**Time budget:** 6 minutes. **Hosts:** `cks-w1`, then `cks-cp`.

```bash
./certs/cks/task.sh setup 6.4
```

> The seccomp profile `/root/cks/no-chmod.json` on `cks-w1` blocks the `chmod` family of syscalls. Install it where the kubelet finds it, as `profiles/no-chmod.json`. Then create pod `locked` in namespace `seccomp` on `cks-w1` with image `busybox:1.36` and command `sleep 1d`, using that profile.

<details>
<summary>Solution</summary>

On `cks-w1`:

```bash
mkdir -p /var/lib/kubelet/seccomp/profiles
cp /root/cks/no-chmod.json /var/lib/kubelet/seccomp/profiles/
```

On `cks-cp`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: locked
  namespace: seccomp
spec:
  nodeName: cks-w1
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/no-chmod.json
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
```

```bash
k -n seccomp exec locked -- sh -c 'touch /tmp/f && chmod 600 /tmp/f'
```

In the test run, that printed `chmod: /tmp/f: Operation not permitted`, while writing the file worked. The path in `localhostProfile` is relative to `/var/lib/kubelet/seccomp/`. With a wrong path, the pod hangs in `CreateContainerError`, and the test run's message named the full path it tried: `cannot load seccomp profile "/var/lib/kubelet/seccomp/profiles/missing.json": open ...: no such file or directory`.

</details>

```bash
./certs/cks/task.sh check 6.4
```

```
  PASS  the kubelet finds the profile at /var/lib/kubelet/seccomp/profiles/no-chmod.json
  PASS  pod locked in seccomp uses the Localhost profile profiles/no-chmod.json
  PASS  pod locked runs on cks-w1
  PASS  chmod fails inside pod locked
  PASS  other writes still work inside pod locked
```

## Task 5: An AppArmor profile

**Time budget:** 6 minutes. **Hosts:** `cks-w1`, then `cks-cp`.

```bash
./certs/cks/task.sh setup 6.5
```

The setup writes a profile with a mistake and shows the parser's complaint. In the test run: `syntax error, unexpected TOK_DENY, expecting TOK_ID or TOK_MODE or TOK_SET_VAR`.

> 1. Fix `/root/cks/cks-deny-write` on `cks-w1` so `apparmor_parser` accepts it. It must still deny every write.
> 2. Create pod `writer` in namespace `apparmor` on `cks-w1`, image `busybox:1.36`, command `sh -c "echo hi > /tmp/x; sleep 1d"`, with its container confined by the profile `cks-deny-write`.

On a real exam node you'd also load the profile and see the pod's write fail. On OrbStack, the pod stops at the kubelet, as the theory explains.

<details>
<summary>Solution</summary>

The parser points at line 6: the `file` rule above it lacks its comma. Every rule in an AppArmor profile ends with one.

```
profile cks-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /** w,
}
```

```bash
apparmor_parser -Q /root/cks/cks-deny-write && echo parses
```

The pod, on `cks-cp`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: apparmor
spec:
  nodeName: cks-w1
  containers:
  - name: c
    image: busybox:1.36
    command: [sh, -c, "echo hi > /tmp/x; sleep 1d"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: cks-deny-write
```

The name in `localhostProfile` is the name after `profile` in the file, not the file name. Here both are `cks-deny-write`. In the test run, the pod ended as `Failed AppArmor: Pod was rejected: Cannot enforce AppArmor: AppArmor is not enabled on the host`. On a node with AppArmor and the profile loaded, the pod runs and the profile denies its write to `/tmp/x`. This lab didn't verify that part, because no machine here has AppArmor.

</details>

```bash
./certs/cks/task.sh check 6.5
```

```
  PASS  apparmor_parser accepts /root/cks/cks-deny-write
  PASS  the profile still denies every write
  PASS  pod writer asks for the Localhost profile cks-deny-write
  PASS  pod writer sits on cks-w1 (OrbStack's kernel has no AppArmor, so the kubelet refuses to start it)
```

## Task 6: Investigate an attack

**Time budget:** 8 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 6.6
```

The setup needs audit logging. When task 1 isn't done, it applies task 1's solution first.

> Somebody deleted Secret `prod-db` in namespace `team-x`. Two service accounts there, `ci-bot` and `docs-bot`, may delete Secrets.
>
> 1. Use the audit log to find who deleted it, and from which pod. Write `<username> <pod name>` on one line to `/root/cks/culprit.txt`.
> 2. Remove the RoleBinding that gave that account the right. Leave the other account alone.

<details>
<summary>Solution</summary>

```bash
grep '"verb":"delete"' /var/log/kubernetes/audit/audit.log | grep '"name":"prod-db"' | tail -1 | python3 -m json.tool
```

The entry in the test run, shortened:

```json
    "verb": "delete",
    "user": {
        "username": "system:serviceaccount:team-x:ci-bot",
        "extra": {
            "authentication.kubernetes.io/node-name": ["cks-w1"],
            "authentication.kubernetes.io/pod-name": ["nightly-cleanup"]
        }
    },
    "sourceIPs": ["192.168.139.60"],
    "userAgent": "curl/8.11.1",
```

The pod no longer exists, but its token carried the pod's name, so the log keeps it. The source IP is the node's, not the pod's, because the request left the pod through the node.

```bash
echo "system:serviceaccount:team-x:ci-bot nightly-cleanup" > /root/cks/culprit.txt
k -n team-x get rolebinding -o wide | grep ci-bot
k -n team-x delete rolebinding ci-bot-secrets
k auth can-i delete secrets -n team-x --as=system:serviceaccount:team-x:ci-bot    # no
```

`userAgent: curl/8.11.1` is a clue in a real investigation: kubectl and controllers identify themselves differently, so a curl call with a service account token points to a person or a script inside a pod.

</details>

```bash
./certs/cks/task.sh check 6.6
```

```
  PASS  /root/cks/culprit.txt names the ServiceAccount and the pod
  PASS  RoleBinding ci-bot-secrets is gone
  PASS  docs-bot keeps its RoleBinding
  PASS  ci-bot may no longer delete Secrets in team-x
```

## Clean up

Task 1 changed the API server, and tasks 2, 4 and 5 left files on `cks-w1`. `./certs/cks/cluster/reset.sh` removes all of it, including the Falco rule.
