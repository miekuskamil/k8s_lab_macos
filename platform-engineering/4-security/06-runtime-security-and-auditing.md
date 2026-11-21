# Module 4.6: Runtime security and auditing

> New to a term here, like audit policy or syscall? The [glossary](../glossary.md#the-practice-cluster-and-the-security-modules) explains every term the security modules use.

**Before this module:** the [practice cluster](../practice-cluster.md) running, ideally fresh from `./lab.sh practice reset`. The course's [module 3.21](../3-istio/21-ebpf-and-cilium.md#concept-what-ebpf-is) explains eBPF, the technique Falco uses to watch the kernel.

The other security modules try to keep attackers out, while this one assumes somebody got in anyway. Three questions then matter: what did they do through the API, what are they doing inside the container right now, and how much damage does the container let them do. Audit logs answer the first, Falco the second, and immutable root file systems, seccomp and AppArmor limit the third. This module has 11 tasks here and two in module 4.7, and takes about 2 hours.

## The module in one table

Each task answers one of those three questions, and one task joins the answers into a single story:

| Question | Tool | Task |
|---|---|---|
| What did they do through the API? | audit logs | 1, 10, 11 |
| What are they doing inside the container right now? | Falco | 2, 7, 8, 9 |
| How much damage does the container let them do? | read-only root, seccomp, AppArmor | 3, 4, 13; AppArmor in module 4.7, tasks 6 and 7 |
| What happened, from start to end? | audit log and Falco together | 6 |

## Concept: syscalls, the kernel boundary

Everything a container does that matters passes one border, the line between the process and the kernel. A **system call**, or syscall, is a request from a program to the kernel: opening a file is `openat`, starting a program is `execve`, opening a connection is `connect`, and changing a file's mode is `chmod`. A process has no other way to touch files, the network or other processes. The course's [module 3.21](../3-istio/21-ebpf-and-cilium.md#concept-kernel-space-and-user-space) explains this line between user space and kernel space.

That border is the best place to defend, for two reasons:

1. Every action passes it, so a check there misses nothing, whatever language or tool the attacker uses.
2. Attackers need syscalls too, because an exploit that breaks out of a container calls the kernel, a cryptominer opens connections, and a shell starts with `execve`.

Three tools in this module work at the border, each in its own way, and the diagram follows one `open()` call through them:

![One system call passes seccomp, then AppArmor, then reaches the kernel; Falco gets a copy and writes an alert](../../docs/diagrams/chapters/cks-runtime-layers.svg)

The call passes five steps:

1. The container's process makes the call.
2. **seccomp** checks the syscall's number against a filter and blocks the ones the profile forbids. It knows nothing about files or paths.
3. **AppArmor** checks the file path or capability against a profile and blocks what the profile denies.
4. The kernel does the work, and Falco's probe gets a copy of the event.
5. Falco matches a rule and writes an alert. It blocks nothing.

gVisor, from [module 4.4](04-hardening-workloads.md#concept-sandboxes-a-second-kernel), sits in a different place, because it answers the syscall itself before the host kernel ever sees it. The four tools layer like this:

| Tool | Decides by | Action | Stops |
|---|---|---|---|
| seccomp | syscall number, sometimes its arguments | block | whole families of kernel features, such as `mount` or `kexec_load` |
| AppArmor | file path, capability, network access | block | writes to `/etc`, reads of keys, raw sockets |
| gVisor | everything, by answering it in user space | replace the kernel | kernel bugs from reaching the host |
| Falco | any field of the event | alert only | nothing, but it tells you |

**Prevention** blocks an action before it happens, while **detection** notices an action and reports it. Prevention needs you to know in advance what to forbid, and a wrong rule breaks the app. Detection tolerates surprises, but by the time it reports, the action has already happened. A good setup uses both, with prevention for the things you know an app never does and detection for the rest.

## Concept: seccomp, a filter on syscalls

A typical web server needs a few dozen of the kernel's more than 300 syscalls, and the rest are attack surface, because each one is kernel code that a bug might hide in. **seccomp** (secure computing mode) is a kernel feature that attaches a filter to a process, and the kernel runs that filter on every syscall the process makes, before the syscall does anything.

A seccomp profile is a JSON file with a default action and a list of syscalls that get their own action:

| Action | Effect |
|---|---|
| `SCMP_ACT_ALLOW` | the syscall runs |
| `SCMP_ACT_ERRNO` | the syscall fails with an error, such as "Operation not permitted". The process keeps running |
| `SCMP_ACT_KILL_PROCESS` | the kernel kills the process |
| `SCMP_ACT_LOG` | the syscall runs, and the kernel logs it. Handy for learning what an app needs |

A pod picks a profile in `securityContext.seccompProfile`, with one of three types:

1. `RuntimeDefault` uses containerd's built-in profile, an allow list that leaves out dangerous syscalls such as `mount`, `reboot` and `kexec_load`. The `restricted` Pod Security level asks for it.
2. `Localhost` loads a profile from a file on the node, below the kubelet's seccomp folder `/var/lib/kubelet/seccomp/`. The pod names the path below that folder in `localhostProfile`.
3. `Unconfined` means no filter at all.

Without a setting, a pod runs `Unconfined`, unless the kubelet's `seccompDefault: true` makes `RuntimeDefault` the default.

**What this stops.** A seccomp profile stops a compromised process from reaching kernel code it never needed, which removes whole classes of container escapes before anybody finds the bug.

**Exam traps.** The profile file must exist on the node that runs the pod. With a wrong path, the pod hangs in `CreateContainerError`, and the test run's message named the full path it tried: `cannot load seccomp profile "/var/lib/kubelet/seccomp/profiles/missing.json"`. In task 4 the profile blocked `chmod`, so the container printed `chmod: /tmp/f: Operation not permitted` while writing the file still worked.

## Concept: AppArmor, a filter on paths

seccomp sees only syscall numbers, so it says "no `openat` at all" or "`openat` is fine", but never "`openat` is fine except on `/etc/shadow`". **AppArmor** fills that gap. It is a Linux security module, a hook inside the kernel that checks each access against a **profile**, which is a text file of rules about paths, capabilities and network access:

```text
profile cks-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /** w,
}
```

That profile, from [module 4.7, task 6](07-kernel-and-host-security.md#task-6-an-apparmor-profile), pulls in the basic rules every program needs, allows file access in general, and denies every write. A profile runs in one of two modes:

1. **Enforce** blocks what the rules deny and logs it.
2. **Complain** blocks nothing and only logs what enforce mode would block, which teams use to learn what an app does before they enforce.

A profile works only once it is loaded into the kernel of the node that runs the pod, and the sequence on the node is always the same:

```console
root@cks-lima:~# apparmor_parser -Q /root/cks/cks-deny-write            # parse only: finds syntax errors, loads nothing
root@cks-lima:~# cp /root/cks/cks-deny-write /etc/apparmor.d/           # the boot-time folder, so it survives a reboot
root@cks-lima:~# apparmor_parser -r /etc/apparmor.d/cks-deny-write      # load it, or replace an older version
root@cks-lima:~# aa-status | grep cks-deny-write                        # listed under "profiles are in enforce mode"
   cks-deny-write
```

A pod asks for a profile with `securityContext.appArmorProfile`, whose `type` is `RuntimeDefault` (the container runtime's default profile), `Localhost` (a profile loaded on the node, named in `localhostProfile`) or `Unconfined`. Before Kubernetes 1.30, an annotation did this job, and the exam still shows old tasks with it, but write the field.

**What this stops.** An AppArmor profile stops a compromised process from writing where it shouldn't, reading keys it never needed, or using capabilities the profile denies, even when it runs as root inside the container.

**Exam traps.** The name in `localhostProfile` is the name after `profile` in the file, not the file name. When the pod names a profile the node hasn't loaded, the kubelet refuses to create the container, and in the test run the pod sat in `CreateContainerError` with `apparmor profile not found cks-nginx`. A Deployment's pods land on any node, so every node needs the profile. The OrbStack machines have no AppArmor, because their kernel lacks it, and there the kubelet refuses every AppArmor pod with `Cannot enforce AppArmor: AppArmor is not enabled on the host`, which is why the AppArmor tasks run on the Lima VM.

## Concept: immutable containers

A container image is the whole truth about what should run, yet by default the container's root file system is writable. An attacker who gets a shell downloads tools into `/usr/bin`, changes a config file or replaces a binary, and the change lives as long as the container.

An **immutable** container never changes after it starts. `readOnlyRootFilesystem: true` makes the container's root file system read-only, so there is nowhere to drop a tool or change a file. Most programs still need a few writable folders for caches, sockets and temporary files, and each gets an `emptyDir` volume, a scratch folder that lives as long as the pod. Change then happens only by building and deploying a new image, which leaves a record.

**What this stops.** A read-only root stops an attacker from installing tools, planting a backdoor in a binary or changing configuration at run time. It also makes every change visible, because any write outside the `emptyDir` folders fails.

**Exam traps.** nginx needs three writable folders, `/var/cache/nginx`, `/run` and `/tmp`, and without them the test run's pod went into `CrashLoopBackOff` with `mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)`. A pod is immutable only when every container says `readOnlyRootFilesystem: true` and none is `privileged`, because a privileged container remounts any file system it likes, so its read-only root protects nothing. Task 13 finds both cases.

## Concept: audit logs, the API's flight recorder

The API server handles every change to the cluster, so it is the one place that sees who did what, and without a record an investigation after an incident has nothing to read. An **audit log** is that record, and kubeadm leaves it off.

![A request produces events at each stage inside the API server, the audit policy picks a level with the first rule that matches, and a backend writes the events to a log file or a webhook](../../docs/diagrams/chapters/cks-audit-pipeline.svg)

An event goes through three steps on its way into the log:

1. A request arrives, and the API server produces an event at each **stage** of its life.
2. The **audit policy** finds the first rule that matches the request and takes its level. Level `None` drops the event.
3. A **backend** writes the event: the log backend to a file, the webhook backend to an outside service.

The stages are `RequestReceived` (as soon as the request arrives), `ResponseStarted` (only for long-running requests such as a watch), `ResponseComplete` (when the answer is sent) and `Panic` (when the API server crashes on the request). `omitStages` in the policy drops stages you don't need, most often `RequestReceived`.

Each rule sets a level, and the level decides how much of the request the log keeps:

| Level | Records |
|---|---|
| `None` | nothing |
| `Metadata` | who, when, which verb on which object, the response code. No bodies |
| `Request` | metadata plus the object the client sent |
| `RequestResponse` | metadata plus both the request and the response bodies |

A rule matches on more than the resource, because it also takes `users`, `userGroups`, `verbs`, `namespaces` and `nonResourceURLs`, and all the fields in one rule must match. A single policy therefore logs everything a suspicious user does at `RequestResponse`, drops the noisy `system:kube-proxy` watches with `None`, and logs pod creations at `Request`. Order still decides, so a rule for Secrets at `Metadata` above the rule for that user keeps the user's Secret reads free of bodies.

The log backend writes one JSON object per line, and four flags control it: the policy file, the log path, and how many days, files and megabytes to keep. Both the policy and the log folder live on the node, so the API server pod needs two `hostPath` volumes, and the log one must be writable.

**What this stops.** An audit log blocks nothing, but it stops an attacker's API activity from going unseen, and it turns "somebody deleted the namespace" into a user name, a time and a source address.

**Exam traps.** Two habits keep the log useful. Put Secrets, ConfigMaps and TokenReviews at `Metadata` and near the top, because a body at `Request` or above would copy every password into a log file. End with a catch-all rule, usually `- level: None` or `- level: Metadata`, so you decide what happens to everything else instead of leaving it to chance. The API server reads the policy only at start, and in task 11 the restart took 42 seconds.

### Reading an audit log

Every line is one event, and each request produces up to four, so count only the `ResponseComplete` lines, or each request counts twice. A few fields answer most questions:

| Question | Field |
|---|---|
| who | `user.username`, and `user.groups` |
| from which pod, for a service account token | `user.extra["authentication.kubernetes.io/pod-name"]` |
| did what | `verb`, `objectRef.resource`, `objectRef.namespace`, `objectRef.name` |
| with which tool | `userAgent` |
| did it work | `responseStatus.code` |

`grep` finds the candidate lines and `python3 -m json.tool` makes one of them readable. A list request has no `objectRef.name`, which tells it apart from a `get`.

## Concept: Falco, a camera on the kernel

seccomp and AppArmor block what you predicted, but attackers do things nobody predicted. **Falco** is a CNCF runtime security tool that watches every syscall on the node and reports the ones that match its rules. It works like a security camera, which records and raises the alarm but locks no door.

![A container's syscall reaches the kernel, Falco's eBPF probe copies the event to user space, the rule engine matches it, and the output writes an alert line for you to read](../../docs/diagrams/chapters/cks-falco-path.svg)

An alert takes five steps from the syscall to the line you read:

1. A process in a container makes a syscall, for example `execve` for `bash`.
2. Falco's **driver** in the kernel sees it. The driver is the part that collects events: the modern eBPF probe on the practice cluster, or an older eBPF probe or kernel module elsewhere.
3. The driver copies the event into a buffer that Falco reads in user space. Falco adds context: the process tree, the container, the pod and its namespace.
4. The rule engine compares the event with every rule.
5. A match produces an alert line, sent to the configured **outputs**: standard output, a file, syslog, a program or HTTP. Falcosidekick, a companion service, forwards alerts to chat, SIEMs and more.

Falco runs its rules after the syscall happened, in user space, so it never slows the syscall down and never stops it.

### Rules, lists and macros

A rule has a condition, an output and a priority:

```yaml
- rule: Shell in container (cks)
  desc: A shell runs inside a container
  condition: spawned_process and container and proc.name in (sh, bash, ash, dash)
  output: "shell in container (user=%user.name ns=%k8s.ns.name pod=%k8s.pod.name cmd=%proc.cmdline)"
  priority: WARNING
```

`spawned_process` and `container` are **macros**, named conditions from Falco's default rules, and the `%` fields fill the output with details of the event. The **priority** is one of `EMERGENCY`, `ALERT`, `CRITICAL`, `ERROR`, `WARNING`, `NOTICE`, `INFORMATIONAL` and `DEBUG`, and Falco's `priority` setting drops alerts below a chosen level.

A rules file holds three kinds of items, and the exam uses all three:

1. A **list** names a set of values: `- list: cks_pkg_mgrs` with `items: [apk, apt, dpkg]`.
2. A **macro** names a piece of condition: `- macro: cks_in_pod` with `condition: (container and k8s.ns.name exists)`.
3. A **rule** uses both: `condition: spawned_process and cks_in_pod and proc.name in (cks_pkg_mgrs)`.

Lists and macros keep long conditions readable, and a change to a list reaches every rule that uses it.

Falco loads `/etc/falco/falco_rules.yaml`, then `falco_rules.local.yaml`, then every file in `/etc/falco/rules.d/`, and it watches those files and reloads by itself when one changes. Never edit `/etc/falco/falco_rules.yaml`, because a package upgrade overwrites it and `dpkg -V falco` shows that you touched it. Change a default rule from a file in `rules.d/` instead, with an `override` block:

```yaml
- rule: Read sensitive file untrusted
  priority: CRITICAL
  override:
    priority: replace

- rule: Terminal shell in container
  enabled: false
  override:
    enabled: replace
```

`replace` swaps the field's value, while `append` adds to it, which suits a condition (`and not proc.name = backup`) or an output. Files in `rules.d/` load after the default file, so the override finds its rule.

On the practice cluster, Falco runs as the systemd service `falco-modern-bpf` on `practice-worker` and logs to the journal, so `journalctl -u falco-modern-bpf` shows its alerts. Out of the box it already flags, among others, a read of `/etc/shadow` with `Sensitive file opened for reading by non-trusted program`.

**What this stops.** Falco stops attacks from going unnoticed, such as a shell in a production container, a package manager running at night or a process reading private keys, and it turns minutes of attacker activity into an alert with a pod name.

**Exam traps.** Falco 0.45 adds container and Kubernetes fields to every alert by itself, so `container_name=`, `k8s_pod_name=` and `k8s_ns_name=` appear at the end of each line, whatever the rule's own output says, and that is how you find the pod behind a default rule's alert. The alert shows the rule's output text rather than its name, so search the rules files for the text. Falco on OrbStack also sees more than its own node, because every machine shares one kernel. In the test run, Falco on `practice-worker` reported `Log files were tampered` for a file on `practice-control-plane`, and alerted on commands typed into the `practice-control-plane` shell with `ns=<NA>`, so filter alerts by `ns=` or `k8s_pod_name=` to see only pods.

## Concept: investigating an attack

An attack moves through phases, and each phase leaves different traces:

1. Get in: an exploited app, a stolen token, a leaked kubeconfig.
2. Look around: list pods and Secrets, read files, scan the network.
3. Gain more rights: read a token with more power, start a privileged pod.
4. Reach the goal: steal data, run a miner, plant a backdoor.
5. Cover the tracks: delete logs, remove the pod.

The audit log shows the API side of each phase. Since 1.30, a service account token's audit entry also names the pod and node it came from, so an API call leads back to a pod. Falco shows what happened inside containers, such as the shell, the file reads and the downloads, so the two side by side on one timeline show the whole path.

The response follows a fixed order. First contain the attack, by scaling the Deployment to zero or isolating the pod with a deny-all NetworkPolicy, so the attacker stops. Then keep the evidence, by copying the logs before anything rotates them, and only then remove the cause and every credential the attacker touched.

**Exam traps.** Exam tasks usually ask for a name, such as who deleted a Secret and from which pod, or which pod hunts for keys. In task 6, the audit entry's `user.username` named the service account and `user.extra` named the pod. For a Falco alert, take the pod from `k8s_pod_name=` and then its owner with `k get pod -o jsonpath='{.metadata.ownerReferences}'`, because deleting a pod that a ReplicaSet owns only brings a fresh copy back.

## The bigger picture: assume breach

Security teams used to aim for a perfect wall, and today the common stance is **assume breach**, which means planning as if an attacker is already inside and making sure you see them and limit them. This module is that stance in practice:

1. Limit: read-only roots, seccomp and AppArmor shrink what a compromised container does.
2. See: Falco watches the kernel, and the audit log watches the API.
3. Respond: the investigation joins both records into one story.

Real platform teams ship audit logs and Falco alerts off the node to a central system, often a SIEM (security information and event management system), so an attacker who gets root on a node finds no evidence there to erase. They roll out seccomp and AppArmor in learning mode first (`SCMP_ACT_LOG`, complain mode) and enforce later. They also tune Falco rules for weeks, because a tool that raises a hundred false alarms a day trains people to ignore it.

## Why this way

**Why both seccomp and AppArmor?** They see different things, because seccomp sees which kernel feature a process asks for and AppArmor sees which file or capability. A process that needs `openat` passes seccomp, and AppArmor still keeps it away from `/etc`.

**Why doesn't Falco block?** Falco reads a copy of each event in user space, after the kernel acted, and blocking would put a slow user-space program in the path of every syscall on the node. Falco leaves blocking to seccomp, AppArmor and admission, and does the one job they don't, which is noticing the unexpected.

**Why does the first matching audit rule win?** It makes the policy readable from the top, because you read down until a rule matches and that rule is the answer. Put the specific rules first and the catch-all last.

**Why log Secrets at Metadata and not at None?** You still want to know who read which Secret and when, but you don't want the Secret's value in a log file that many more people read than the Secret itself.

## Task 1: Turn on audit logging

**Time budget:** 10 minutes. **Host:** `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.1
== setup task 4.6.1
secret/token created
0
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

Order matters, because the first matching rule wins. The Secrets rule comes first, so a Secret in `audit-me` gets `Metadata` instead of `RequestResponse` with its contents.

In the API server manifest, after a backup, add the four flags and the two volumes:

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

When the API server is back, make a request and read the newest entry in the log:

```console
root@practice-control-plane:~# k -n audit-me get secret token
NAME    TYPE     DATA   AGE
token   Opaque   1      47s
root@practice-control-plane:~# tail -1 /var/log/kubernetes/audit/audit.log | python3 -m json.tool | head -20
{
    "kind": "Event",
    "apiVersion": "audit.k8s.io/v1",
    "level": "Metadata",
    "auditID": "628cd862-0cb0-45ad-b3fc-70fd076e7d21",
    "stage": "ResponseComplete",
    "requestURI": "/api/v1/namespaces/audit-me/secrets/token",
    "verb": "get",
    "user": {
        "username": "kubernetes-admin",
        "groups": [
            "kubeadm:cluster-admins",
            "system:authenticated"
        ],
        "extra": {
            "authentication.kubernetes.io/credential-id": [
                "X509SHA256=97f9c84ba597c45dc5d5a74c174c4500e4168c67d3cb664da3bcf1e17c6ba026"
            ]
        }
    },
```

</details>

```console
$ ./lab.sh task check 4.6.1
== check task 4.6.1
  PASS  --audit-policy-file is /etc/kubernetes/audit/policy.yaml
  PASS  --audit-log-path is /var/log/kubernetes/audit/audit.log
  PASS  --audit-log-maxage=30, maxbackup=10, maxsize=100
  PASS  a get on a Secret appears at level Metadata
  PASS  no Secret appears with its body
  PASS  a configmap create in audit-me appears at RequestResponse
  PASS  a configmap create in default does not appear
== task 4.6.1: 7 passed, 0 failed
```

The check makes three requests of its own and looks for each one in the log.

## Task 2: Catch a shell with Falco

**Time budget:** 8 minutes. **Host:** `practice-worker`.

```console
$ ./lab.sh task setup 4.6.2
== setup task 4.6.2
pod/target created
pod/target condition met
active
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

Save the file, and Falco reloads by itself. Check the reload in the journal, then fire the rule from `practice-control-plane`:

```console
root@practice-worker:~# journalctl -u falco-modern-bpf -n 20 | grep cks-shell        # "schema validation: ok"
Nov 15 15:17:26 practice-worker falco[35575]:    /etc/falco/rules.d/cks-shell.yaml | schema validation: ok
root@practice-control-plane:~# k -n falco-test exec target -- sh -c 'echo hello'             # on practice-control-plane
hello
root@practice-worker:~# journalctl -u falco-modern-bpf --since -1min | grep 'ns=falco-test'
Nov 15 15:17:33 practice-worker falco[35575]: 15:17:33.289362971: Warning shell in container (time=15:17:33.289362971 user=root ns=falco-test pod=target container=target cmd=sh -c echo hello) container_id=0d062466cf6a container_name=target container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=target k8s_ns_name=falco-test
```

Falco's documentation, which the exam allows, lists every field under "Supported Fields". When a task asks for a format such as `%evt.time,%user.name,%proc.name`, copy it into `output` exactly, because the check compares the text.

</details>

```console
$ ./lab.sh task check 4.6.2
== check task 4.6.2
  PASS  a rule named 'Shell in container (cks)' exists in /etc/falco/rules.d/
  PASS  falco accepts every rules file
  PASS  a shell in falco-test/target produces the alert with namespace, pod and command
== task 4.6.2: 3 passed, 0 failed
```

## Task 3: Make a container immutable

**Time budget:** 6 minutes. **Host:** `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.3
== setup task 4.6.3
deployment.apps/web created
service/web exposed
Waiting for deployment "web" rollout to finish: 0 of 1 updated replicas are available...
deployment "web" successfully rolled out
```

> Deployment `web` in namespace `immutable` runs nginx. Make its container's root file system read-only. nginx must keep serving.

<details>
<summary>Solution</summary>

Run `k -n immutable edit deploy web`, and add the setting and three writable folders to the pod template:

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

Without the volumes, nginx exits at start, and in the test run the pod went into `CrashLoopBackOff` with the log line `mkdir() "/var/cache/nginx/client_temp" failed (30: Read-only file system)`. Prove both sides, the refused write and the page that still serves:

```console
root@practice-control-plane:~# k -n immutable exec deploy/web -- touch /cks-was-here    # Read-only file system
touch: /cks-was-here: Read-only file system
command terminated with exit code 1
root@practice-control-plane:~# k -n immutable run t --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- http://web | head -4
All commands and output from this session will be recorded in container logs, including credentials and sensitive information passed through the command prompt.
If you don't see a command prompt, try pressing enter.
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

</details>

```console
$ ./lab.sh task check 4.6.3
== check task 4.6.3
  PASS  container web has readOnlyRootFilesystem: true
  PASS  the Deployment's pod is Ready
  PASS  writing to / fails inside the pod
  PASS  nginx still serves on the Service
== task 4.6.3: 4 passed, 0 failed
```

## Task 4: A seccomp profile

**Time budget:** 6 minutes. **Hosts:** `practice-worker`, then `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.4
== setup task 4.6.4
-rw-r--r-- 1 root root 149 Nov 15 15:17 /root/cks/no-chmod.json
```

> The seccomp profile `/root/cks/no-chmod.json` on `practice-worker` blocks the `chmod` family of syscalls. Install it where the kubelet finds it, as `profiles/no-chmod.json`. Then create pod `locked` in namespace `seccomp` on `practice-worker` with image `busybox:1.36` and command `sleep 1d`, using that profile.

<details>
<summary>Solution</summary>

Copy the profile into the kubelet's seccomp folder on `practice-worker`, the node that will run the pod:

```console
root@practice-worker:~# mkdir -p /var/lib/kubelet/seccomp/profiles
root@practice-worker:~# cp /root/cks/no-chmod.json /var/lib/kubelet/seccomp/profiles/
```

Then create the pod from `practice-control-plane`, pinned to `practice-worker`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: locked
  namespace: seccomp
spec:
  nodeName: practice-worker
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/no-chmod.json
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
```

```console
root@practice-control-plane:~# k -n seccomp exec locked -- sh -c 'touch /tmp/f && chmod 600 /tmp/f'
chmod: /tmp/f: Operation not permitted
command terminated with exit code 1
```

In the test run, that printed `chmod: /tmp/f: Operation not permitted`, while writing the file worked. The path in `localhostProfile` is relative to `/var/lib/kubelet/seccomp/`, and with a wrong path the pod hangs in `CreateContainerError`, where the test run's message named the full path it tried: `cannot load seccomp profile "/var/lib/kubelet/seccomp/profiles/missing.json": open ...: no such file or directory`.

</details>

```console
$ ./lab.sh task check 4.6.4
== check task 4.6.4
  PASS  the kubelet finds the profile at /var/lib/kubelet/seccomp/profiles/no-chmod.json
  PASS  pod locked in seccomp uses the Localhost profile profiles/no-chmod.json
  PASS  pod locked runs on practice-worker
  PASS  chmod fails inside pod locked
  PASS  other writes still work inside pod locked
== task 4.6.4: 5 passed, 0 failed
```

## Task 5: AppArmor, on a VM

The AppArmor tasks need a kernel with AppArmor turned on, which the kernel the kind nodes share lacks. Task 5 sits in [module 4.7](07-kernel-and-host-security.md#task-6-an-apparmor-profile) as its task 6.

## Task 6: Investigate an attack

**Time budget:** 8 minutes. **Host:** `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.6
== setup task 4.6.6
serviceaccount/ci-bot created
serviceaccount/docs-bot created
role.rbac.authorization.k8s.io/secret-admin created
rolebinding.rbac.authorization.k8s.io/ci-bot-secrets created
rolebinding.rbac.authorization.k8s.io/docs-bot-secrets created
secret/prod-db created
pod/nightly-cleanup created
Error from server (NotFound): secrets "prod-db" not found
```

The setup needs audit logging, so when task 1 isn't done, it applies task 1's solution first.

> Somebody deleted Secret `prod-db` in namespace `team-x`. Two service accounts there, `ci-bot` and `docs-bot`, may delete Secrets.
>
> 1. Use the audit log to find who deleted it, and from which pod. Write `<username> <pod name>` on one line to `/root/cks/culprit.txt`.
> 2. Remove the RoleBinding that gave that account the right. Leave the other account alone.

<details>
<summary>Solution</summary>

```console
root@practice-control-plane:~# grep '"verb":"delete"' /var/log/kubernetes/audit/audit.log | grep '"name":"prod-db"' | tail -1 | python3 -m json.tool
{
    "kind": "Event",
    "apiVersion": "audit.k8s.io/v1",
    "level": "Metadata",
    "auditID": "44486772-5b5f-4492-a70a-a0a2feadf0be",
    "stage": "ResponseComplete",
    "requestURI": "/api/v1/namespaces/team-x/secrets/prod-db",
    "verb": "delete",
    "user": {
        "username": "system:serviceaccount:team-x:ci-bot",
...
            "authentication.kubernetes.io/pod-name": [
                "nightly-cleanup"
            ],
...
    "sourceIPs": [
        "192.168.117.3"
    ],
    "userAgent": "curl/8.11.1",
...
```

The pod no longer exists, but its token carried the pod's name, so the log keeps it. The source IP is the node's rather than the pod's, because the request left the pod through the node.

```console
root@practice-control-plane:~# echo "system:serviceaccount:team-x:ci-bot nightly-cleanup" > /root/cks/culprit.txt
root@practice-control-plane:~# k -n team-x get rolebinding -o wide | grep ci-bot
ci-bot-secrets     Role/secret-admin   5s                     team-x/ci-bot
root@practice-control-plane:~# k -n team-x delete rolebinding ci-bot-secrets
rolebinding.rbac.authorization.k8s.io "ci-bot-secrets" deleted from team-x namespace
root@practice-control-plane:~# k auth can-i delete secrets -n team-x --as=system:serviceaccount:team-x:ci-bot    # no
no
```

`userAgent: curl/8.11.1` is a clue in a real investigation, because kubectl and controllers identify themselves differently, so a curl call with a service account token points to a person or a script inside a pod.

</details>

```console
$ ./lab.sh task check 4.6.6
== check task 4.6.6
  PASS  /root/cks/culprit.txt names the ServiceAccount and the pod
  PASS  RoleBinding ci-bot-secrets is gone
  PASS  docs-bot keeps its RoleBinding
  PASS  ci-bot may no longer delete Secrets in team-x
== task 4.6.6: 4 passed, 0 failed
```

## Task 7: A Falco rule with a list and a macro

**Time budget:** 8 minutes. **Host:** `practice-worker`.

```console
$ ./lab.sh task setup 4.6.7
== setup task 4.6.7
active
```

> Create `/etc/falco/rules.d/cks-pkg.yaml` on `practice-worker` with:
>
> 1. A list `cks_pkg_mgrs` with `apk`, `apt`, `apt-get`, `dpkg` and `pip`.
> 2. A macro `cks_in_pod` that is true for processes in a container that belongs to a Kubernetes pod.
> 3. A rule `Package manager in pod` with priority `ERROR` that fires when a process from the list starts in a pod. Its output is exactly `package manager in pod (ns=%k8s.ns.name pod=%k8s.pod.name proc=%proc.name)`.

<details>
<summary>Solution</summary>

```yaml
- list: cks_pkg_mgrs
  items: [apk, apt, apt-get, dpkg, pip]

- macro: cks_in_pod
  condition: (container and k8s.ns.name exists)

- rule: Package manager in pod
  desc: A package manager runs inside a Kubernetes pod
  condition: spawned_process and cks_in_pod and proc.name in (cks_pkg_mgrs)
  output: "package manager in pod (ns=%k8s.ns.name pod=%k8s.pod.name proc=%proc.name)"
  priority: ERROR
```

Falco reloads by itself, so check the reload in the journal and then fire the rule from `practice-control-plane`:

```console
root@practice-worker:~# journalctl -u falco-modern-bpf -n 20 | grep cks-pkg         # "schema validation: ok"
Nov 15 15:18:21 practice-worker falco[35575]:    /etc/falco/rules.d/cks-pkg.yaml | schema validation: ok
root@practice-control-plane:~# k -n falco-test exec target -- apk --version                # on practice-control-plane
apk-tools 2.14.6, compiled for aarch64.
root@practice-worker:~# journalctl -u falco-modern-bpf --since -1min | grep 'package manager'
Nov 15 15:17:59 practice-worker falco[35575]: 15:17:59.158277787: Warning shell in container (time=15:17:59.158277787 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:17:57'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:17:59 practice-worker falco[35575]: 15:17:59.160025966: Warning shell in container (time=15:17:59.160025966 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:17:57' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:01 practice-worker falco[35575]: 15:18:01.324540662: Warning shell in container (time=15:18:01.324540662 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:17:59'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:01 practice-worker falco[35575]: 15:18:01.328347354: Warning shell in container (time=15:18:01.328347354 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:17:59' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:03 practice-worker falco[35575]: 15:18:03.493870205: Warning shell in container (time=15:18:03.493870205 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:01'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:03 practice-worker falco[35575]: 15:18:03.495776405: Warning shell in container (time=15:18:03.495776405 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:01' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:05 practice-worker falco[35575]: 15:18:05.647359524: Warning shell in container (time=15:18:05.647359524 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:03'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:05 practice-worker falco[35575]: 15:18:05.650652035: Warning shell in container (time=15:18:05.650652035 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:03' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:07 practice-worker falco[35575]: 15:18:07.807076247: Warning shell in container (time=15:18:07.807076247 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:05'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:07 practice-worker falco[35575]: 15:18:07.808903124: Warning shell in container (time=15:18:07.808903124 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:05' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:09 practice-worker falco[35575]: 15:18:09.959029815: Warning shell in container (time=15:18:09.959029815 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:07'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:09 practice-worker falco[35575]: 15:18:09.962051988: Warning shell in container (time=15:18:09.962051988 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:07' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:12 practice-worker falco[35575]: 15:18:12.140395932: Warning shell in container (time=15:18:12.140395932 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:09'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:12 practice-worker falco[35575]: 15:18:12.143786722: Warning shell in container (time=15:18:12.143786722 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:09' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:14 practice-worker falco[35575]: 15:18:14.321263533: Warning shell in container (time=15:18:14.321263533 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:12'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:14 practice-worker falco[35575]: 15:18:14.323704702: Warning shell in container (time=15:18:14.323704702 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:12' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:16 practice-worker falco[35575]: 15:18:16.498213500: Warning shell in container (time=15:18:16.498213500 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:14'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:16 practice-worker falco[35575]: 15:18:16.501958783: Warning shell in container (time=15:18:16.501958783 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:14' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:18 practice-worker falco[35575]: 15:18:18.690149265: Warning shell in container (time=15:18:18.690149265 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c bash -c 'journalctl -u falco-modern-bpf --since '\"'\"'2026-11-15 15:18:16'\"'\"' --no-pager | grep -qE '\"'\"'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)'\"'\"'') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:18 practice-worker falco[35575]: 15:18:18.691812706: Warning shell in container (time=15:18:18.691812706 user=root ns=<NA> pod=<NA> container=<NA> cmd=bash -c journalctl -u falco-modern-bpf --since '2026-11-15 15:18:16' --no-pager | grep -qE 'Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)') container_id=container/01 container_name=<NA> container_image_repository=<NA> container_image_tag=<NA> k8s_pod_name=<NA> k8s_ns_name=<NA>
Nov 15 15:18:23 practice-worker falco[35575]: 15:18:23.930796842: Error package manager in pod (ns=falco-test pod=target proc=apk) container_id=0d062466cf6a container_name=target container_image_repository=docker.io/library/nginx container_image_tag=1.27-alpine k8s_pod_name=target k8s_ns_name=falco-test
```

In the alert, everything after the closing bracket is the part Falco 0.45 appends by itself. `falco -V <file>` validates a rules file without starting a second Falco.

</details>

```console
$ ./lab.sh task check 4.6.7
== check task 4.6.7
  PASS  /etc/falco/rules.d/cks-pkg.yaml defines the list cks_pkg_mgrs with apk, apt, apt-get, dpkg and pip
  PASS  /etc/falco/rules.d/cks-pkg.yaml defines the macro cks_in_pod, and the rule uses the macro and the list
  PASS  falco accepts the rules
  PASS  apk in falco-test/target raises an Error alert with ns, pod and process
== task 4.6.7: 4 passed, 0 failed
```

## Task 8: Change what a default Falco rule does

**Time budget:** 6 minutes. **Host:** `practice-worker`.

```console
$ ./lab.sh task setup 4.6.8
== setup task 4.6.8
  /etc/falco/falco_rules.yaml matches the package
```

> On `practice-worker`, without editing `/etc/falco/falco_rules.yaml`:
>
> 1. Raise the priority of the rule `Read sensitive file untrusted` to `CRITICAL`.
> 2. Turn off the rule `Terminal shell in container`.

<details>
<summary>Solution</summary>

Write the overrides from the theory into `/etc/falco/rules.d/cks-override.yaml`, one for each default rule:

```yaml
- rule: Read sensitive file untrusted
  priority: CRITICAL
  override:
    priority: replace

- rule: Terminal shell in container
  enabled: false
  override:
    enabled: replace
```

Test from `practice-control-plane`. A shell "with a terminal" needs `-t`, which is what the second command adds:

```console
root@practice-control-plane:~# k -n falco-test exec target -- cat /etc/shadow > /dev/null
root@practice-control-plane:~# k -n falco-test exec -it target -- sh -c 'echo hi'
hi
```

The transcript ran the second command inside `script`, which gives `kubectl exec -t` the terminal it needs outside an interactive shell.

On `practice-worker`, `journalctl -u falco-modern-bpf --since -1min` showed this line in the test run, and no line about a terminal shell:

```
Critical Sensitive file opened for reading by non-trusted program | file=/etc/shadow ... command=cat /etc/shadow ...
```

The rule's name and its output text differ, so find a rule by name with `grep -n 'rule: Read sensitive file untrusted' /etc/falco/falco_rules.yaml`, and an alert by its text.

</details>

```console
$ ./lab.sh task check 4.6.8
== check task 4.6.8
  PASS  /etc/falco/falco_rules.yaml is unchanged
  PASS  reading /etc/shadow in falco-test/target raises a Critical alert
  PASS  a shell with a terminal in falco-test/target raises no alert
== task 4.6.8: 3 passed, 0 failed
```

## Task 9: Which pod hunts for keys?

**Time budget:** 6 minutes. **Hosts:** `practice-worker`, then `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.9
== setup task 4.6.9
deployment.apps/cart created
deployment.apps/inventory created
deployment.apps/reports created
```

> One of the three Deployments in namespace `shop-runtime` searches the file system for private keys, and a default Falco rule catches it. Write two lines to `/root/cks/falco-finding.txt` on `practice-control-plane`: the name of the Falco rule, then `<namespace>/<deployment>`. Then delete that Deployment.

<details>
<summary>Solution</summary>

On `practice-worker`, filter the alerts by namespace, because Falco adds the namespace to every line:

```console
root@practice-worker:~# journalctl -u falco-modern-bpf --since -5min | grep 'k8s_ns_name=shop-runtime' | tail -1
Nov 15 20:24:18 practice-worker falco[35575]: 16:19:29.686354270: Warning Grep private keys or passwords activities found | evt_type=execve user=root user_uid=0 user_loginuid=-1 process=find proc_exepath=/bin/find parent=sh command=find / -name id_rsa terminal=0 exe_flags=EXE_WRITABLE|EXE_LOWER_LAYER container_id=937f47cf6f85 container_name=busybox container_image_repository=docker.io/library/busybox container_image_tag=1.36 k8s_pod_name=inventory-fcc7f8846-852zt k8s_ns_name=shop-runtime
```

In the test run, the line began `Warning Grep private keys or passwords activities found | ... process=find ... command=find / -name id_rsa` and ended with `k8s_pod_name=inventory-fcc7f88...`. The alert shows the rule's output text rather than its name, so find the name from the text:

```console
root@practice-worker:~# grep -B20 'Grep private keys or passwords activities found' /etc/falco/falco_rules.yaml | grep 'rule:' | tail -1
- rule: Search Private Keys or Passwords
```

That prints `- rule: Search Private Keys or Passwords`. On `practice-control-plane`, the pod's `app` label names its Deployment, which is what you delete:

```console
root@practice-control-plane:~# k -n shop-runtime get pod <pod> --show-labels
NAME                        READY   STATUS    RESTARTS   AGE   LABELS
inventory-fcc7f8846-852zt   1/1     Running   0          41s   app=inventory,pod-template-hash=fcc7f8846
root@practice-control-plane:~# printf 'Search Private Keys or Passwords\nshop-runtime/inventory\n' > /root/cks/falco-finding.txt
root@practice-control-plane:~# k -n shop-runtime delete deploy inventory
deployment.apps "inventory" deleted from shop-runtime namespace
```

The transcript ran the first command with the name of the inventory pod from the alert in place of `<pod>`.

</details>

```console
$ ./lab.sh task check 4.6.9
== check task 4.6.9
  PASS  /root/cks/falco-finding.txt holds the rule name and shop-runtime/inventory
  PASS  Deployment inventory is gone
  PASS  Deployments cart and reports still run
== task 4.6.9: 3 passed, 0 failed
```

## Task 10: Read the audit log like a detective

**Time budget:** 8 minutes. **Host:** `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.10
== setup task 4.6.10
role.rbac.authorization.k8s.io/secret-admin created
rolebinding.rbac.authorization.k8s.io/alice-secrets created
rolebinding.rbac.authorization.k8s.io/bob-secrets created
rolebinding.rbac.authorization.k8s.io/carol-secrets created
secret/salaries created
secret/old-salaries created
secret/bonus created
  somebody has been busy in namespace hr
```

The setup needs audit logging, so when task 1 isn't done, it applies task 1's solution first. Then three users, `alice`, `bob` and `carol`, work in namespace `hr` with client certificates.

> Use the audit log `/var/log/kubernetes/audit/audit.log` to answer three questions. Write one answer per line to `/root/cks/audit-answers.txt`:
>
> 1. Which user read Secret `salaries` in `hr`?
> 2. Which user deleted Secret `old-salaries` in `hr`?
> 3. How many times did `carol` list the Secrets in `hr`?
>
> Then take away the right to delete Secrets in `hr` from the user who deleted one. Leave the other two alone.

<details>
<summary>Solution</summary>

Search the log once for each question, and count only the `ResponseComplete` stage, because each request also produces other stages:

```console
root@practice-control-plane:~# L=/var/log/kubernetes/audit/audit.log
root@practice-control-plane:~# grep '"name":"salaries"' $L | grep '"verb":"get"' | grep ResponseComplete | python3 -m json.tool | grep username
        "username": "alice",
root@practice-control-plane:~# grep '"name":"old-salaries"' $L | grep '"verb":"delete"' | grep ResponseComplete | grep -o '"username":"[^"]*"'
"username":"bob"
root@practice-control-plane:~# grep '"verb":"list"' $L | grep '"resource":"secrets","namespace":"hr"' | grep '"username":"carol"' | grep -c ResponseComplete
2
```

In the test run, the answers were `alice`, `bob` and `2`. Task 1's policy logs Secrets at `Metadata`, so each line names the user and the object but holds no Secret data.

```console
root@practice-control-plane:~# printf 'alice\nbob\n2\n' > /root/cks/audit-answers.txt
root@practice-control-plane:~# k -n hr get rolebinding -o wide | grep bob
bob-secrets     Role/secret-admin   1s    bob              
root@practice-control-plane:~# k -n hr delete rolebinding bob-secrets
rolebinding.rbac.authorization.k8s.io "bob-secrets" deleted from hr namespace
```

`grep` on a JSON line depends on the order of its fields, so test each pattern against one line first, and fall back to `python3` when a pattern finds nothing.

</details>

```console
$ ./lab.sh task check 4.6.10
== check task 4.6.10
  PASS  line 1 of /root/cks/audit-answers.txt: alice read salaries
  PASS  line 2: bob deleted old-salaries
  PASS  line 3: carol listed the Secrets 2 times
  PASS  bob may no longer delete Secrets in hr, alice and carol keep their rights
== task 4.6.10: 4 passed, 0 failed
```

## Task 11: An audit policy per user and per resource

**Time budget:** 8 minutes. **Host:** `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.11
== setup task 4.6.11
rolebinding.rbac.authorization.k8s.io/alice-edit created
secret/s1 created
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

> Replace the audit policy `/etc/kubernetes/audit/policy.yaml`, keeping the API server's audit flags:
>
> 1. Log nothing from the user `system:kube-proxy`, and nothing about `events`.
> 2. Log Secrets and ConfigMaps at `Metadata`, for everybody.
> 3. Log everything else the user `alice` does at `RequestResponse`.
> 4. Log pod creations and deletions at `Request`.
> 5. Log nothing else. Skip the `RequestReceived` stage.

<details>
<summary>Solution</summary>

The order of the task is the order of the rules, because the first match wins:

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: None
  users: ["system:kube-proxy"]
- level: None
  resources:
  - group: ""
    resources: [events]
- level: Metadata
  resources:
  - group: ""
    resources: [secrets, configmaps]
- level: RequestResponse
  users: [alice]
- level: Request
  verbs: [create, delete]
  resources:
  - group: ""
    resources: [pods]
- level: None
```

The API server reads the policy only at start, and the manifest doesn't change, so restart it by moving the manifest out and back, as in [module 4.4, task 5](04-hardening-workloads.md#task-5-rotate-the-encryption-key). In the test run, that took 42 seconds. Then make some traffic and read the newest lines:

```console
root@practice-control-plane:~# k -n audit-11 run p1 --image=busybox:1.36 -- sleep 1
pod/p1 created
root@practice-control-plane:~# tail -3 /var/log/kubernetes/audit/audit.log | grep -o '"level":"[A-Za-z]*","auditID[^,]*,"stage":"[A-Za-z]*","requestURI":"[^"]*","verb":"[a-z]*"'
"level":"Metadata","auditID":"67d8da68-59fe-4e59-8bae-a7246e98ad01","stage":"ResponseStarted","requestURI":"/api/v1/namespaces/seccomp/configmaps?allowWatchBookmarks=true\u0026fieldSelector=metadata.name%3Dkube-root-ca.crt\u0026resourceVersion=1511\u0026resourceVersionMatch=NotOlderThan\u0026sendInitialEvents=true\u0026timeout=56m10s\u0026timeoutSeconds=3370\u0026watch=true","verb":"watch"
"level":"Metadata","auditID":"2fc51c1a-eaee-4119-95ba-0e8a2235e3c3","stage":"ResponseStarted","requestURI":"/api/v1/configmaps?allowWatchBookmarks=true\u0026labelSelector=OWNER%21%3DTILLER\u0026resourceVersion=1637\u0026resourceVersionMatch=NotOlderThan\u0026sendInitialEvents=true\u0026timeout=5m48s\u0026timeoutSeconds=348\u0026watch=true","verb":"watch"
"level":"Request","auditID":"e7e96e72-907f-4cb5-a7a3-3b6481421657","stage":"ResponseComplete","requestURI":"/api/v1/namespaces/audit-11/pods?fieldManager=kubectl-run","verb":"create"
```

</details>

```console
$ ./lab.sh task check 4.6.11
== check task 4.6.11
  PASS  alice's get on a Secret appears at Metadata
  PASS  alice's Deployment create appears at RequestResponse
  PASS  an admin's pod create appears at Request
  PASS  an admin's pod get does not appear
  PASS  a ConfigMap create appears at Metadata
  PASS  events appear nowhere in the log since the change
== task 4.6.11: 6 passed, 0 failed
```

The check makes requests as `alice` and as the admin, then looks for each one, and in the test run it failed three of six items before the solution.

## Task 12: AppArmor for a Deployment, on a VM

This task sits in [module 4.7](07-kernel-and-host-security.md#task-7-apparmor-for-a-deployment) as its task 7, for the same reason as task 5.

## Task 13: Pods that are not immutable

**Time budget:** 5 minutes. **Host:** `practice-control-plane`.

```console
$ ./lab.sh task setup 4.6.13
== setup task 4.6.13
pod/frozen created
pod/frozen-too created
pod/writable created
pod/half-frozen created
pod/frozen-but-privileged created
  frozen
  frozen-but-privileged
  frozen-too
  half-frozen
  writable
```

> Namespace `immutable-check` runs five pods. Delete every pod in which some container may write to its root file system, or runs privileged. Leave the others running.

<details>
<summary>Solution</summary>

Print each container's two settings, one line per pod, so the pods that fail the test stand out:

```console
root@practice-control-plane:~# k -n immutable-check get pods -o jsonpath='{range .items[*]}{.metadata.name}{": ro="}{.spec.containers[*].securityContext.readOnlyRootFilesystem}{" priv="}{.spec.containers[*].securityContext.privileged}{"\n"}{end}'
frozen: ro=true priv=
frozen-but-privileged: ro=true priv=true
frozen-too: ro=true priv=
half-frozen: ro=true priv=
writable: ro= priv=
```

A pod is immutable only when every container says `ro=true` and none says `priv=true`. In the test run, three pods failed that test: `writable` (no setting), `half-frozen` (one of its two containers has no setting) and `frozen-but-privileged`, whose read-only root protects nothing, because a privileged container remounts any file system it likes.

```console
root@practice-control-plane:~# k -n immutable-check delete pod writable half-frozen frozen-but-privileged
pod "writable" deleted from immutable-check namespace
pod "half-frozen" deleted from immutable-check namespace
pod "frozen-but-privileged" deleted from immutable-check namespace
```

</details>

```console
$ ./lab.sh task check 4.6.13
== check task 4.6.13
  PASS  writable, half-frozen and frozen-but-privileged are gone
  PASS  frozen and frozen-too still run
== task 4.6.13: 2 passed, 0 failed
```

## Clean up

Tasks 1, 10 and 11 changed the API server, and tasks 2, 4, 7 and 8 left files on `practice-worker`, so `./lab.sh practice reset` removes all of it, including the Falco rules.
