# CKS 04: Minimize microservice vulnerabilities (20%)

> New to a term here, like Pod Security Admission or RuntimeClass? The [glossary](../../platform-engineering/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) running. The course's [module 2](../../platform-engineering/02-identity-and-mtls.md) explains mTLS between pods, and [module 10](../../platform-engineering/10-ebpf-and-cilium.md#concept-kernel-space-and-user-space) explains the kernel boundary that gVisor moves. Read them for the pod-to-pod encryption topic. Task 10 runs on the [Lima VM](../README.md#the-lima-vm-for-apparmor-and-cilium).

A container is a process with a few fences around it. It shares the node's kernel, and by default it runs as root, keeps a dozen Linux capabilities, and sees its API token and its Secrets as plain text. This domain tightens each fence in turn: what a pod may ask for, where Secrets rest, how a pod receives them, and which kernel a risky pod talks to. It has ten tasks and takes about 1 hour 45 minutes.

## The domain in one table

A workload runs inside four fences, and this domain tightens each one, so each task answers one question about a fence:

| Question | Tool | Task |
|---|---|---|
| How much power may a pod ask for? | Pod Security Admission, `securityContext` | 1, 6, 7, 8 |
| Do Secrets rest in etcd as plain text? | EncryptionConfiguration | 2, 5 |
| How does a Secret reach the container? | a volume instead of an environment variable | 3 |
| Which kernel does a risky pod talk to? | RuntimeClass and gVisor | 4, 9 |
| Who reads the traffic between pods? | Cilium WireGuard, or Istio mTLS | 10 |

## Concept: what a container shares with its node

A container feels like a small machine of its own, but it is a normal Linux process that the kernel wraps in a few fences:

1. **Namespaces** give it its own view of processes, network, mounts and host name.
2. **cgroups** limit how much CPU and memory it uses.
3. **Capabilities**, seccomp and AppArmor limit which privileged actions it may take.

Under all of that, every container on the node talks to the same kernel. By default it also runs as root, keeps about a dozen Linux capabilities, and sees its API token and its Secrets as plain text. Each default makes sense for compatibility, but together they leave a compromised container a short step away from the node.

Classic Unix had two kinds of user, root, who may do everything, and everybody else, which made every privileged program all-powerful. Linux split root's power into about forty slices called **Linux capabilities**, such as `NET_ADMIN` to change network settings, `SYS_ADMIN` to mount file systems and much more, and `NET_BIND_SERVICE` to listen on ports below 1024. A process holds only the capabilities it was given, so dropping them shrinks what even a root process may do.

## Concept: securityContext, field by field

The **securityContext** is the part of a pod or container spec that sets these fences, and each of its fields blocks one specific attack:

| Field | Safe value | What it blocks |
|---|---|---|
| `runAsNonRoot` | `true` | a container that starts as user 0. The kubelet refuses to start it |
| `runAsUser` | a non-zero ID, such as `1000` | root inside the container, which owns every file the container sees |
| `allowPrivilegeEscalation` | `false` | a process that gains rights later, for example through a setuid binary such as `sudo` |
| `capabilities.drop` | `[ALL]` | every slice of root power, such as changing network settings or loading kernel modules |
| `privileged` | `false` (the default) | nearly every capability and every device of the node |
| `readOnlyRootFilesystem` | `true` | an attacker writing tools or changing binaries, which [domain 06](06-monitoring-logging-runtime-security.md#concept-immutable-containers) covers |
| `seccompProfile.type` | `RuntimeDefault` | dangerous syscalls such as `mount` and `kexec_load`, also in domain 06 |

`allowPrivilegeEscalation: false` sets a kernel flag called `no_new_privs` on the process, which means no child process ever gets more rights than its parent, whatever binary it runs. That is the line that makes a setuid `sudo` inside the image useless.

**What this stops.** A container that runs as a normal user, with no capabilities and no way to gain rights, leaves an attacker with a shell and very little else, because most container escapes need root or a capability inside the container first.

## Concept: Pod Security Standards and Pod Security Admission

Writing a safe `securityContext` is one problem, and making sure every team writes one is another. Nobody reviews every pod by hand, so the cluster has to refuse unsafe pods by itself.

The **Pod Security Standards** give that refusal a shared vocabulary, with three fixed levels that say how much power a pod may ask for:

| Level | Allows | Typical user |
|---|---|---|
| `privileged` | everything | CNI agents, storage drivers |
| `baseline` | most apps; refuses host namespaces, privileged mode, `hostPath` volumes, host ports and extra capabilities | ordinary apps that run as root |
| `restricted` | only hardened pods: `runAsNonRoot`, no privilege escalation, all capabilities dropped (only `NET_BIND_SERVICE` may come back), a `RuntimeDefault` or `Localhost` seccomp profile, and a short list of volume types | everything you write yourself |

**Pod Security Admission** is the built-in admission plugin that applies a level to a namespace. It runs at the validating admission step of [domain 02's request chain](02-cluster-hardening.md#concept-one-request-six-steps), and you set it with namespace labels, one per mode:

1. `pod-security.kubernetes.io/enforce` refuses pods that break the level.
2. `pod-security.kubernetes.io/warn` lets them in and prints a warning to the client.
3. `pod-security.kubernetes.io/audit` lets them in and writes a note into the audit log.

Each mode also takes a version label, such as `pod-security.kubernetes.io/enforce-version: v1.37`, because the rules of a level grow a little with each Kubernetes release. A pinned version keeps the rules of that release, so an upgrade never starts refusing pods that ran yesterday, while `latest`, the default, always means the newest rules. A common pattern pins `enforce` and leaves `warn` and `audit` on `latest`, so the warnings show what the next upgrade would break. Task 6 sets all three.

**What this stops.** Pod Security stops a developer, a Helm chart or an attacker with `create pods` rights from starting a pod that owns the node, because it turns the securityContext table into a rule the API server enforces.

**Exam traps.** Enforce never touches pods that already run, the same lesson the course's [module 26](../../platform-engineering/26-kyverno-policy-as-code.md#concept-two-paths-to-a-verdict) teaches for Kyverno. A Deployment's existing pods keep running after you label the namespace, and the refusal hits the next pod the ReplicaSet creates, where it shows up only as an event on the ReplicaSet. A server-side dry run of the label lists the pods that would break the rule before you apply it:

```console
root@cks-cp:~# k label --dry-run=server --overwrite ns secure-apps pod-security.kubernetes.io/enforce=restricted
Warning: existing pods in namespace "secure-apps" violate the new PodSecurity enforce level "restricted:latest"
Warning: app-7459c748d4-h5vfj: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/secure-apps labeled (server dry run)
```

In the test run, that printed `Warning: existing pods in namespace "secure-apps" violate the new PodSecurity enforce level "restricted:latest"`, followed by the four reasons for the one pod.

### Pod Security for the whole cluster

Namespace labels cover one namespace each, and a new namespace starts with none, so a team that forgets the label gets no protection. The PodSecurity admission plugin therefore also reads a cluster-wide configuration, which applies to every namespace without labels:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults:
      enforce: baseline
      enforce-version: latest
      warn: restricted
      warn-version: latest
      audit: restricted
      audit-version: latest
    exemptions:
      usernames: []
      runtimeClasses: []
      namespaces: [kube-system, monitoring-agents]
```

Three kinds of **exemption** switch Pod Security off completely: for pods in named namespaces, for pods created by named users, and for pods that ask for named RuntimeClasses. Exempt `kube-system`, because the CNI and other node agents there need host access. A label on a namespace still beats the defaults, so a namespace labelled `enforce=privileged` stays open.

The API server reads the file from `--admission-control-config-file`, the same flag that [domain 05](05-supply-chain-security.md#allowing-only-approved-registries) uses for ImagePolicyWebhook, and one file holds the configuration of every plugin that has one, as items in its `plugins` list. Task 7 writes it. In the test run, the restart took 61 seconds, and the defaults hit every unlabelled namespace from then on, including ones created later.

### Pods that reach into the node

Pod Security names the fields that matter most, because a pod with any of them shares something with its node, and a compromised container then takes the node with it:

| Field | What the pod shares |
|---|---|
| `hostPID: true` | the node's process list: it sees and signals every process |
| `hostNetwork: true` | the node's network: every port, and traffic of other pods on the node |
| `hostIPC: true` | the node's shared memory |
| a `hostPath` volume | any folder of the node, `/` included |
| `privileged: true` | nearly every kernel capability and every device |

The `baseline` level refuses all five. On an old cluster without Pod Security you find such pods by hand, which is what task 8 does, and in the test run four pods had something: one with `hostPID`, one with a `hostPath` of `/`, one with `hostNetwork` and one privileged.

## Concept: Secrets at rest

Run `kubectl get secret db-creds -o yaml` and the password field shows a string of scrambled characters, which makes the Secret look protected. It isn't. That string is base64, an **encoding** that only changes how the data looks so it travels safely through YAML and JSON, and anyone reverses it with `base64 -d`. A **cipher** is different, because reversing it needs a key. A Secret by default gets the encoding and no cipher.

The weak spot is where the API server keeps Secrets. It writes them to etcd exactly as it writes ConfigMaps, so the stored value is the plain password. Anyone who gets a copy of etcd's data folder, an etcd backup file or the etcd client certificate therefore reads every password in the cluster. That is a realistic path rather than a theory, because backups get copied to storage buckets, shared drives and engineers' laptops.

![A client creates a Secret, the API server hands it to the first provider in its EncryptionConfiguration, and etcd stores only ciphertext with a prefix that names the provider and key](../../docs/diagrams/chapters/cks-encryption-rest.svg)

**Encryption at rest** closes that path by encrypting Secrets before they reach etcd. You switch it on with an **EncryptionConfiguration** file, which lists the resources to encrypt and, for each, an ordered list of providers. A provider is one method of encryption with its own key. A write then goes through three steps:

1. A client sends a Secret in plain text, over TLS, to the API server.
2. The API server hands the value to the first provider in the configuration's list.
3. The provider encrypts it, and the API server stores the result in etcd behind a short label such as `k8s:enc:aescbc:v1:key1:`, which records the provider and the key that were used.

A read runs the other way. The API server looks at the label, picks the matching provider and key, and decrypts, and when no provider in the list decrypts the value, the read fails. That label is why the order of the list matters, and why the last entry is usually `identity`, the provider that means "no encryption":

1. The API server encrypts every new write with the first provider in the list.
2. On a read, it tries the providers until one decrypts the value.
3. Older Secrets were stored before encryption existed, so they carry no label, and keeping `identity` last lets the API server still read them.

The providers differ in where the key lives and how strong the algorithm is. The exam usually asks for `aescbc` or `secretbox`, and the table shows the trade-offs:

| Provider | What it does | Notes |
|---|---|---|
| `identity` | no encryption | the default when no file exists |
| `aescbc` | AES in CBC mode, key in the file | the exam's usual choice. The docs advise against it, because CBC is open to padding oracle attacks |
| `aesgcm` | AES in GCM mode, key in the file | fast, but the key must change every 200,000 writes |
| `secretbox` | XSalsa20 and Poly1305, key in the file | strong and fast |
| `kms` (v2) | envelope encryption with an outside key service | the key never sits on the node |

Every provider with a key in the file shares one weakness, because that file sits on the control plane node next to etcd, and an attacker who copies the node's disk gets both. The `kms` provider removes that weakness with **envelope encryption**. The API server encrypts the data with a data encryption key (DEK), and an outside key management service, such as a cloud KMS or Vault, encrypts that DEK with a key encryption key (KEK) that never leaves the service. etcd stores only the encrypted DEK next to the data. A safe deposit box works the same way: the bank holds the master key, and your own key alone opens nothing.

**What this stops.** A stolen etcd backup or data folder no longer reveals any Secret. A user or service account with RBAC permission to read Secrets still reads them through the API, because the API server decrypts for every authorized caller. Encryption at rest protects the stored copy, and RBAC protects the front door, so you need both.

**Exam traps.** Turning encryption on changes nothing that is already stored, because each Secret gets encrypted only the next time someone writes it. So the last step rewrites every Secret once with `k get secrets -A -o json | k replace -f -`. The test run showed the difference with `etcdctl`: a plain object starts with `k8s` and a zero byte, followed by readable protobuf, while an encrypted one starts with `k8s:enc:aescbc:v1:key1:`. The file also needs a `hostPath` volume in the API server pod, like every file in this track.

### Key rotation

The label names the key as well as the provider, and that makes **key rotation** safe. Rotation replaces the key that encrypts the data, for example after somebody saw the config file, and on a cluster with one API server it takes four steps:

1. Add the new key at the top of the provider's `keys` list, above the old one.
2. Restart the API server. New writes use the new key, and the old key still decrypts old data.
3. Rewrite every Secret with `k get secrets -A -o json | k replace -f -`.
4. Remove the old key and restart once more.

Remove the old key before step 3, and the API server fails to read every Secret it hasn't rewritten yet, because their labels still name `key1`. With several API servers, add the new key in second place on all of them first, so that every server reads it before any server writes with it. In task 5, the value afterwards started with `k8s:enc:aescbc:v1:key2:`, and the whole rotation took 71 seconds.

## Concept: how a Secret reaches the container

A Secret reaches a container in one of two ways, and the file is the safer one:

| | Environment variable | Mounted file |
|---|---|---|
| Visible in | `/proc/<pid>/environ`, crash dumps, child processes, logs that print the environment | only the file, readable by the container's user |
| On rotation | stays old until the pod restarts | the kubelet updates the file within about a minute |

An environment variable spreads, because every child process inherits it, and many frameworks print the whole environment in a debug page or an error report. A file stays where it is, and the kubelet keeps Secret volumes in memory (`tmpfs`), so they never touch the node's disk.

**What this stops.** A file mount stops a password from leaking through error pages, crash dumps and child processes, and it lets a rotated password reach the app without a restart.

## Concept: sandboxes, a second kernel

Every fence so far still leaves one shared thing, the kernel. A **container escape** is an attack that breaks out of the container's fences onto the node, and most serious escapes use a kernel bug that some system call reaches. A **system call**, or syscall, is a request from a program to the kernel, such as "open this file", and the Linux kernel offers more than 300 of them, each one code that might hold a bug. One reachable bug lets a container own the node and every pod on it.

A **sandboxed runtime** puts a second kernel between the container and the host, so a bug in the first one no longer reaches the node. Two designs exist:

1. **gVisor** writes a kernel in user space. Its core, the **Sentry**, is a Go program that implements the Linux syscall interface itself. The container's syscalls go to the Sentry, which answers most of them without the host kernel. The Sentry itself calls the host kernel with only a small, fixed set of syscalls, behind its own seccomp filter.
2. **Kata Containers** starts each pod in a lightweight virtual machine with its own real Linux kernel. The host kernel sees only a virtual machine.

![A runc container sends every syscall through seccomp and AppArmor to the host kernel. A gVisor container sends its syscalls to the Sentry, which passes only a few to the host kernel](../../docs/diagrams/chapters/cks-sandbox-kernel.svg)

The diagram compares the two paths. On the left, runc, the normal runtime, lets every syscall through to the shared kernel, filtered only by seccomp and AppArmor. On the right, gVisor's runtime `runsc` sends the container's syscalls to the Sentry first, so an attacker now needs a bug in the Sentry and then a bug in the few host syscalls the Sentry uses. The course's [module 10](../../platform-engineering/10-ebpf-and-cilium.md#concept-kernel-space-and-user-space) explains the line between kernel space and user space that gVisor moves.

The cost is speed, because every syscall takes a longer path, and apps that do a lot of file or network work notice it. Teams therefore use sandboxes for untrusted code, such as CI jobs, customer plugins, scanners and anything else that runs code somebody else wrote.

Kubernetes picks the runtime per pod with a **RuntimeClass**, whose `handler` names a runtime that containerd knows. The practice cluster's `cks-w1` has a `runsc` handler in `/etc/containerd/config.toml`, and a pod asks for it with `runtimeClassName`.

**What this stops.** A sandbox stops a kernel bug from turning a compromised container into a compromised node, which makes it the only control in this domain that protects against bugs in the kernel itself.

**Exam traps.** Usually only some nodes have the sandbox installed, and a pod for `runsc` on a node without it fails to start. A RuntimeClass fixes that with a `scheduling.nodeSelector`, because the RuntimeClass admission plugin copies the selector into every pod that asks for the class, so the scheduler only picks nodes with the right label. In the test run, a pod of task 9 showed `nodeSelector: {"sandbox":"gvisor"}` without its Deployment ever naming it. To prove a pod runs in gVisor, run `dmesg` inside it: the test run printed `Starting gVisor...`, while a normal pod got `dmesg: klogctl: Operation not permitted`.

## Concept: pod-to-pod encryption

NetworkPolicy decides who may talk, but it doesn't hide what they say, because traffic between nodes crosses the network in clear text. Anybody who reads that network, through a compromised switch, a cloud provider's tap or a pod with `hostNetwork`, reads every password and token the pods send. The curriculum names two ways to encrypt it:

| | Istio | Cilium |
|---|---|---|
| How | mTLS between proxies, with a certificate per service account | WireGuard or IPsec tunnels between nodes |
| Proves | which workload sent the request | which node sent the packet |
| Turn on | label the namespace for the mesh, then a `PeerAuthentication` with `mode: STRICT` | Helm values `encryption.enabled=true` and `encryption.type=wireguard` |
| In this repo | the whole Istio route of the course, [module 2](../../platform-engineering/02-identity-and-mtls.md) first | compared in [module 10](../../platform-engineering/10-ebpf-and-cilium.md#why-this-way-the-two-designs-share-one-idea) |

**mTLS** (mutual TLS) means both sides of a connection show a certificate, so each knows who the other is, while **WireGuard** is a small, fast VPN protocol built into the Linux kernel. The two answer different questions. WireGuard encrypts every packet between two nodes, whatever pod sent it, while mTLS encrypts per connection and also proves which workload is calling, which authorization rules then use.

The OrbStack cluster runs neither, because its kernel has no WireGuard module and Calico's own encryption needs WireGuard too. The Lima VM's kernel has the module, so task 10 turns on Cilium's WireGuard there and checks it with `cilium encrypt status`.

**What this stops.** Encryption between pods stops anybody on the network path from reading or changing traffic, and mTLS also stops a pod from pretending to be another workload.

**Exam traps.** The Lima VM has one node, and WireGuard encrypts traffic between nodes, so no packet actually crosses the tunnel, and the task proves the setting and the interface rather than encrypted traffic. Cilium's agents read the setting only at start: in the test run, `cilium encrypt status` said `Disabled` until the agents restarted, then `Encryption: Wireguard (1/1 nodes)` 12 seconds later.

## The bigger picture: four fences, each for a different failure

Each fence in this domain assumes that the previous one failed:

1. The `securityContext` and Pod Security assume the app has a bug, and keep the attacker from gaining root powers inside the container.
2. Encryption at rest assumes somebody copies etcd, and keeps the copy useless.
3. File-mounted Secrets assume the app leaks its environment, and keep the password out of it.
4. Sandboxes assume the attacker reaches a kernel bug, and put a second kernel in the way.

Pod-to-pod encryption adds a fifth fence, for the network between the pods.

Real platform teams set these fences once, centrally, so app teams never think about them. Every new namespace gets `enforce=restricted` from a template, with a short, reviewed list of exemptions. Secrets come from a cloud KMS or Vault, often through an operator that writes them as files, untrusted workloads land on a separate node pool with gVisor or Kata, and a service mesh or the CNI encrypts all traffic by default.

## Why this way

**Why three fixed levels and not custom policies?** Fixed levels are easy to reason about and ship inside every cluster. Teams that need custom rules, such as "only images from our registry", add a policy engine like Kyverno on top.

**Why does enforce leave running pods alone?** Admission only sees requests, and a running pod sends no request, so nothing checks it until its controller creates a new one. That also keeps a label change from deleting production pods.

**Why does `identity` stay in the provider list?** Old Secrets in etcd stay plain text until you rewrite them, and without `identity` the API server fails to read them.

**Why not run every pod in gVisor?** It costs speed, and gVisor doesn't implement every syscall, so some apps fail inside it. Most of your own apps are trusted code that the other fences cover well, so sandboxes earn their price where the code itself is untrusted.

## Task 1: Enforce the restricted standard

**Time budget:** 8 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.1
== setup task 4.1
deployment.apps/app created
Waiting for deployment "app" rollout to finish: 0 of 1 updated replicas are available...
deployment "app" successfully rolled out
```

> 1. Make namespace `secure-apps` enforce the `restricted` Pod Security Standard, and warn about it too.
> 2. Deployment `app` in that namespace runs `busybox:1.36` with `sleep`. Change it so that its pods run under `restricted`, as user 1000.

<details>
<summary>Solution</summary>

Label the namespace first, and read the warning that names what the running pod lacks:

```console
root@cks-cp:~# k label ns secure-apps pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
Warning: existing pods in namespace "secure-apps" violate the new PodSecurity enforce level "restricted:latest"
Warning: app-7459c748d4-h5vfj: allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile
namespace/secure-apps labeled
```

The warning names the four gaps, `allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile`. Fix each one in the pod template with `k -n secure-apps edit deploy app`:

```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: busybox
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

Then run `k -n secure-apps rollout status deploy app`, and the new pod starts while the old one goes away. `runAsUser` matters for `busybox`, because the image's default user is root, and `runAsNonRoot` alone makes the kubelet refuse to start it.

</details>

```console
$ ./certs/cks/task.sh check 4.1
== check task 4.1
  PASS  namespace secure-apps enforces the restricted standard
  PASS  Deployment app has a ready pod that the namespace admitted
  PASS  no running pod in secure-apps violates restricted
  PASS  a privileged pod is refused in secure-apps
== task 4.1: 4 passed, 0 failed
```

## Task 2: Encrypt Secrets at rest

**Time budget:** 10 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.2
== setup task 4.2
secret/db-creds created
Sup3rS3cret
```

The setup creates Secret `db-creds` in namespace `vault-test` and prints the password as it sits in etcd, in clear text.

> 1. Encrypt Secrets in etcd with the `aescbc` provider, using the configuration file `/etc/kubernetes/enc/enc.yaml` and a key named `key1`.
> 2. Encrypt the Secrets that already exist, too.
> 3. Prove it with `etcdctl` for `vault-test/db-creds`.

<details>
<summary>Solution</summary>

Make a 32-byte key and write the configuration file around it:

```console
root@cks-cp:~# mkdir -p /etc/kubernetes/enc
root@cks-cp:~# head -c 32 /dev/urandom | base64
E0Go46ihI4xopds2NYObxwfMWXzBzQ/ClXMezcOs0Mw=
root@cks-cp:~# vim /etc/kubernetes/enc/enc.yaml
```

The transcript leaves out the editor session.

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: [secrets]
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <the base64 key>
  - identity: {}
```

Back up the API server manifest, then add the flag, a volume mount and a volume, as in [02, task 3](02-cluster-hardening.md#task-3-restrict-anonymous-access-to-the-api):

```yaml
    - --encryption-provider-config=/etc/kubernetes/enc/enc.yaml
...
    - mountPath: /etc/kubernetes/enc
      name: enc
      readOnly: true
...
  - hostPath:
      path: /etc/kubernetes/enc
      type: DirectoryOrCreate
    name: enc
```

When the API server is back, rewrite every Secret so each one gets encrypted, and look at etcd:

```console
root@cks-cp:~# k get secrets -A -o json | k replace -f -
secret/ingress-nginx-admission replaced
secret/bootstrap-token-6uqqt7 replaced
secret/bootstrap-token-acm1tv replaced
secret/db-creds replaced
root@cks-cp:~# ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt \
  --key=/etc/kubernetes/pki/apiserver-etcd-client.key \
  get /registry/secrets/vault-test/db-creds --print-value-only | head -c 48 | od -c
{"level":"warn","ts":"2026-11-15T12:45:23.919374Z","caller":"flags/flag.go:94","msg":"unrecognized environment variable","environment-variable":"ETCDCTL_API=3"}
0000000   k   8   s   :   e   n   c   :   a   e   s   c   b   c   :   v
0000020   1   :   k   e   y   1   : 021 372 257 242 365 263   E 353 177
0000040   G 362 240 201 250   [   w 316   G   d   G 353 200 225 206 025
0000060
```

The certificate paths come from the API server's own `--etcd-*` flags, so `grep etcd /etc/kubernetes/manifests/kube-apiserver.yaml` finds them when you forget. etcdctl 3.7 no longer needs `ETCDCTL_API=3` and prints a warning about it, but older versions in exam environments still need it. In the test run, the value started with `k8s:enc:aescbc:v1:key1:`, and the replace rewrote 4 Secrets.

</details>

```console
$ ./certs/cks/task.sh check 4.2
== check task 4.2
  PASS  the API server runs with --encryption-provider-config
  PASS  Secret db-creds is stored with prefix k8s:enc:aescbc:v1:
  PASS  the password no longer appears in etcd in clear text
  PASS  kubectl still reads the Secret
== task 4.2: 4 passed, 0 failed
```

## Task 3: A Secret as a file, not an environment variable

**Time budget:** 5 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.3
== setup task 4.3
secret/api-token created
pod/api created
pod/api condition met
```

> Pod `api` in namespace `orders` reads Secret `api-token` through the environment variable `API_TOKEN`. Change it to read the Secret as a read-only file at `/etc/api/token`, and remove the variable. Keep the pod name.

<details>
<summary>Solution</summary>

A pod's containers don't change in place, so save the pod, delete it and create it again:

```console
root@cks-cp:~# k -n orders get pod api -o yaml > api.yaml
root@cks-cp:~# vim api.yaml       # remove env, add volumeMounts and volumes
root@cks-cp:~# k -n orders replace --force -f api.yaml
pod "api" deleted from orders namespace
pod/api replaced
```

The transcript leaves out the editor session, which makes the change the YAML below shows.

```yaml
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: [sleep, 1d]
    volumeMounts:
    - {name: token, mountPath: /etc/api, readOnly: true}
  volumes:
  - name: token
    secret: {secretName: api-token}
```

`replace --force` deletes the pod and creates it again in one step, and afterwards `k -n orders exec api -- cat /etc/api/token` prints `t0k3n-123`.

</details>

```console
$ ./certs/cks/task.sh check 4.3
== check task 4.3
  PASS  pod api has no environment variable from a Secret
  PASS  pod api mounts Secret api-token read-only at /etc/api
  PASS  the token is readable at /etc/api/token
== task 4.3: 3 passed, 0 failed
```

## Task 4: Sandbox a pod with gVisor

**Time budget:** 5 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.4
== setup task 4.4
deployment.apps/untrusted created
Waiting for deployment "untrusted" rollout to finish: 0 of 1 updated replicas are available...
deployment "untrusted" successfully rolled out
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
  runtime_type = 'io.containerd.runsc.v1'
```

> 1. Create a RuntimeClass `gvisor` for the containerd handler `runsc`.
> 2. Make Deployment `untrusted` in namespace `sandbox` run its pods with it.

<details>
<summary>Solution</summary>

The RuntimeClass page in the Kubernetes docs has this YAML, which you copy and adjust:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

```console
root@cks-cp:~# k apply -f rc.yaml
runtimeclass.node.k8s.io/gvisor created
root@cks-cp:~# k -n sandbox patch deploy untrusted -p '{"spec":{"template":{"spec":{"runtimeClassName":"gvisor"}}}}'
deployment.apps/untrusted patched
root@cks-cp:~# k -n sandbox rollout status deploy untrusted
Waiting for deployment "untrusted" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "untrusted" rollout to finish: 1 old replicas are pending termination...
deployment "untrusted" successfully rolled out
root@cks-cp:~# k -n sandbox exec deploy/untrusted -- dmesg | head -2
[   0.000000] Starting gVisor...
[   0.577100] Recruiting cron-ies...
```

`dmesg` inside a gVisor pod shows gVisor's own made-up kernel log, which in the test run began `[   0.000000] Starting gVisor...`. A normal pod gets `dmesg: klogctl: Operation not permitted` instead, because it shares the host kernel and may not read its log.

</details>

```console
$ ./certs/cks/task.sh check 4.4
== check task 4.4
  PASS  RuntimeClass gvisor uses handler runsc
  PASS  Deployment untrusted uses RuntimeClass gvisor
  PASS  the running pod's kernel is gVisor
== task 4.4: 3 passed, 0 failed
```

## Task 5: Rotate the encryption key

**Time budget:** 10 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.5
== setup task 4.5
secret/app-secret created
  - aescbc:
      keys:
      - name: key1
        secret: <hidden>
  - identity: {}
  stored as: k8s:enc:aescbc:v1:key1:
```

The setup starts from task 2's result and applies its solution when encryption is off. It prints how the Secret sits in etcd, which in the test run was `stored as: k8s:enc:aescbc:v1:key1:`.

> The API server encrypts Secrets with the `aescbc` key `key1` from `/etc/kubernetes/enc/enc.yaml`. Rotate to a new key `key2`: every Secret in etcd ends up encrypted with `key2`, and the file no longer holds `key1`. Keep the file's path.

<details>
<summary>Solution</summary>

Step 1 puts the new key on top of the list:

```console
root@cks-cp:~# cp /etc/kubernetes/enc/enc.yaml /root/
root@cks-cp:~# head -c 32 /dev/urandom | base64
VvafQ3jl97ZKzGW2k5m9h7sM6DnRbNypf8PEEsrWgO4=
root@cks-cp:~# vim /etc/kubernetes/enc/enc.yaml
```

The transcript leaves out the editor session.

```yaml
  - aescbc:
      keys:
      - name: key2
        secret: <the new base64 key>
      - name: key1
        secret: <the old key, unchanged>
```

Step 2 is a restart. The API server reads the file only at start, and the manifest didn't change, so the kubelet sees no reason to restart it, which means you move the manifest out of the folder and back:

```console
root@cks-cp:~# mv /etc/kubernetes/manifests/kube-apiserver.yaml /root/
root@cks-cp:~# watch crictl ps --name kube-apiserver        # wait until the container is gone
CONTAINER           IMAGE               CREATED             STATE               NAME                ATTEMPT             POD ID              POD                 NAMESPACE
root@cks-cp:~# mv /root/kube-apiserver.yaml /etc/kubernetes/manifests/
```

`watch` redraws its screen every 2 seconds until you press Ctrl-C, and the transcript shows the last screen, with the container gone.

Step 3 rewrites every Secret, once `k get nodes` answers again:

```console
root@cks-cp:~# k get secrets -A -o json | k replace -f -
secret/ingress-nginx-admission replaced
secret/bootstrap-token-6uqqt7 replaced
secret/bootstrap-token-acm1tv replaced
secret/api-token replaced
secret/app-secret replaced
secret/db-creds replaced
```

Step 4 deletes the two `key1` lines and restarts the API server the same way. Then prove the result with etcdctl, using the variables from task 2:

```console
root@cks-cp:~# etcdctl ... get /registry/secrets/rotate-me/app-secret --print-value-only | head -c 23; echo
{"level":"warn","ts":"2026-11-15T12:48:03.539579Z","caller":"flags/flag.go:94","msg":"unrecognized environment variable","environment-variable":"ETCDCTL_API=3"}
k8s:enc:aescbc:v1:key2:
```

The `...` in the command stands for the etcdctl flags of task 2, and the transcript ran it with them.

In the test run, that printed `k8s:enc:aescbc:v1:key2:`. The rewrite touched 5 Secrets in one test run and 6 in another, and the two restarts made the whole rotation take 71 seconds.

</details>

```console
$ ./certs/cks/task.sh check 4.5
== check task 4.5
  PASS  app-secret is stored with key2
  PASS  every Secret in etcd is stored with key2
  PASS  the configuration no longer holds key1, and key2 comes first
  PASS  kubectl still reads app-secret
== task 4.5: 4 passed, 0 failed
```

## Task 6: Pod Security levels, modes and versions

**Time budget:** 4 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.6
== setup task 4.6
deployment.apps/legacy created
Waiting for deployment "legacy" rollout to finish: 0 of 1 updated replicas are available...
deployment "legacy" successfully rolled out
```

> Namespace `psa-levels` runs Deployment `legacy` with nginx as root. Configure Pod Security for the namespace:
>
> 1. Enforce `baseline`, pinned to the rules of Kubernetes v1.37.
> 2. Warn and audit at `restricted`, with the newest rules.
>
> `legacy` keeps running.

<details>
<summary>Solution</summary>

```console
root@cks-cp:~# k label ns psa-levels \
  pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/enforce-version=v1.37 \
  pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/audit-version=latest
namespace/psa-levels labeled
```

Write `latest` explicitly even though it is the default, because the task asks for it and a check reads the label. Then test both levels with server-side dry runs:

```console
root@cks-cp:~# k -n psa-levels run t1 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1   # Forbidden
Error from server (Forbidden): pods "t1" is forbidden: violates PodSecurity "baseline:v1.37": privileged (container "t1" must not set securityContext.privileged=true)
root@cks-cp:~# k -n psa-levels run t2 --image=nginx:1.27-alpine --dry-run=server                      # Warning, then created
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "t2" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "t2" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "t2" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "t2" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/t2 created (server dry run)
```

In the test run, the second command printed `Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false ...` and then `pod/t2 created (server dry run)`. nginx as root passes `baseline`, so `legacy` keeps running.

</details>

```console
$ ./certs/cks/task.sh check 4.6
== check task 4.6
  PASS  enforce is baseline, pinned to v1.37
  PASS  warn and audit are restricted, at version latest
  PASS  a privileged pod is refused
  PASS  a root nginx pod is admitted, with a restricted warning
  PASS  Deployment legacy keeps its ready pod
== task 4.6: 5 passed, 0 failed
```

## Task 7: Cluster-wide Pod Security defaults with exemptions

**Time budget:** 10 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.7
== setup task 4.7
  a privileged pod in psa-default today: pod/t created (server dry run)
```

The setup shows the cluster's default today, and in the test run a privileged pod in an unlabelled namespace got `pod/t created (server dry run)`.

> Configure Pod Security for every namespace without labels, through the file `/etc/kubernetes/admission/psa.yaml`:
>
> 1. Enforce `baseline`. Warn and audit at `restricted`. Use the newest rules for all three.
> 2. Exempt the namespaces `kube-system` and `monitoring-agents`.

<details>
<summary>Solution</summary>

Write the file from the theory section, then point the API server at it, after a backup of the manifest:

```yaml
    - --admission-control-config-file=/etc/kubernetes/admission/psa.yaml
...
    - mountPath: /etc/kubernetes/admission
      name: admission
      readOnly: true
...
  - hostPath:
      path: /etc/kubernetes/admission
      type: DirectoryOrCreate
    name: admission
```

The "Enforce Pod Security Standards by configuring the built-in admission controller" page in the Kubernetes docs holds the YAML. Once the API server answers, test three namespaces:

```console
root@cks-cp:~# k -n psa-default run t1 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1        # Forbidden
Error from server (Forbidden): pods "t1" is forbidden: violates PodSecurity "baseline:latest": privileged (container "t1" must not set securityContext.privileged=true)
root@cks-cp:~# k -n psa-default run t2 --image=nginx:1.27-alpine --dry-run=server                           # Warning, then created
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "t2" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "t2" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "t2" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "t2" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/t2 created (server dry run)
root@cks-cp:~# k -n monitoring-agents run t3 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1  # created, exempt
pod/t3 created (server dry run)
```

In the test run, the restart took 61 seconds, and the defaults hit every namespace without labels from then on, including ones created later.

</details>

```console
$ ./certs/cks/task.sh check 4.7
== check task 4.7
  PASS  the API server reads /etc/kubernetes/admission/psa.yaml
  PASS  a privileged pod in the unlabelled namespace psa-default is refused
  PASS  a root nginx pod in psa-default gets a restricted warning but runs
  PASS  a privileged pod in monitoring-agents is admitted
  PASS  the API server pod is Ready
== task 4.7: 5 passed, 0 failed
```

## Task 8: Pods that reach into the node

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.8
== setup task 4.8
pod/web created
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "c" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "c" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "c" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "c" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
Warning: would violate PodSecurity "restricted:latest": host namespaces (hostPID=true), allowPrivilegeEscalation != false (container "c" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "c" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "c" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "c" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/node-debug created
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "c" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "c" must set securityContext.capabilities.drop=["ALL"]), restricted volume types (volume "host" uses restricted volume type "hostPath"), runAsNonRoot != true (pod or container "c" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "c" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/log-reader created
pod/api created
Warning: would violate PodSecurity "restricted:latest": host namespaces (hostNetwork=true), allowPrivilegeEscalation != false (container "c" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "c" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "c" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "c" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/net-tool created
Warning: would violate PodSecurity "restricted:latest": privileged (container "c" must not set securityContext.privileged=true), allowPrivilegeEscalation != false (container "c" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "c" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "c" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "c" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
pod/metrics created
pod/cache created
  team-blue/log-reader
  team-blue/node-debug
  team-blue/web
  team-green/api
  team-green/cache
  team-green/metrics
  team-green/net-tool
```

> Namespaces `team-blue` and `team-green` run seven pods. Delete every pod that shares a host namespace (PID, network or IPC), mounts a `hostPath` volume, or runs a privileged container. Leave the others running.

<details>
<summary>Solution</summary>

`jsonpath` prints the fields side by side, one pod per line, so the risky ones stand out:

```console
root@cks-cp:~# for n in team-blue team-green; do
  k -n $n get pods -o jsonpath='{range .items[*]}{.metadata.name}{" pid="}{.spec.hostPID}{" net="}{.spec.hostNetwork}{" ipc="}{.spec.hostIPC}{" priv="}{.spec.containers[*].securityContext.privileged}{" vols="}{.spec.volumes[*].hostPath.path}{"\n"}{end}'
done
log-reader pid= net= ipc= priv= vols=/
node-debug pid=true net= ipc= priv= vols=
web pid= net= ipc= priv= vols=
api pid= net= ipc= priv= vols=
cache pid= net= ipc= priv= vols=
metrics pid= net= ipc= priv=true vols=
net-tool pid= net=true ipc= priv= vols=
```

Empty fields mean "not set". In the test run, four pods had something: `node-debug` (hostPID), `log-reader` (a hostPath of `/`), `net-tool` (hostNetwork) and `metrics` (privileged). `cache` mounts an `emptyDir`, which lives inside the pod's own storage and is harmless here.

```console
root@cks-cp:~# k -n team-blue delete pod node-debug log-reader
pod "node-debug" deleted from team-blue namespace
pod "log-reader" deleted from team-blue namespace
root@cks-cp:~# k -n team-green delete pod net-tool metrics
pod "net-tool" deleted from team-green namespace
pod "metrics" deleted from team-green namespace
```

Both namespaces carry `pod-security.kubernetes.io/enforce=privileged`, which explains how those pods got in, and changing the label to `baseline` afterwards keeps new ones out.

</details>

```console
$ ./certs/cks/task.sh check 4.8
== check task 4.8
  PASS  node-debug (hostPID) is gone
  PASS  log-reader (hostPath /) is gone
  PASS  net-tool (hostNetwork) is gone
  PASS  metrics (privileged) is gone
  PASS  web, api and cache still run
== task 4.8: 5 passed, 0 failed
```

## Task 9: A sandbox only on the nodes that have it

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```console
$ ./certs/cks/task.sh setup 4.9
== setup task 4.9
  runsc on cks-w1: /usr/local/bin/runsc   runsc on cks-cp: none
```

> Only `cks-w1` has gVisor. Label it `sandbox=gvisor`. Create a RuntimeClass `gvisor-pinned` for the handler `runsc` that sends its pods only to nodes with that label. Then create Deployment `scanner` in namespace `sandbox-sched`, image `busybox:1.36`, command `sleep 1d`, 3 replicas, with that RuntimeClass.

<details>
<summary>Solution</summary>

```console
root@cks-cp:~# k label node cks-w1 sandbox=gvisor
node/cks-w1 labeled
```

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor-pinned
handler: runsc
scheduling:
  nodeSelector:
    sandbox: gvisor
```

```console
root@cks-cp:~# k -n sandbox-sched create deploy scanner --image=busybox:1.36 --replicas=3 $do -- sleep 1d > scanner.yaml
root@cks-cp:~# vim scanner.yaml      # add runtimeClassName: gvisor-pinned under the pod template's spec
root@cks-cp:~# k apply -f scanner.yaml
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "busybox" must set securityContext.allowPrivilegeEscalation=false), unrestricted capabilities (container "busybox" must set securityContext.capabilities.drop=["ALL"]), runAsNonRoot != true (pod or container "busybox" must set securityContext.runAsNonRoot=true), seccompProfile (pod or container "busybox" must set securityContext.seccompProfile.type to "RuntimeDefault" or "Localhost")
deployment.apps/scanner created
root@cks-cp:~# k -n sandbox-sched get pods -o wide
NAME                       READY   STATUS    RESTARTS   AGE   IP              NODE     NOMINATED NODE   READINESS GATES
scanner-85dff684c9-hssgc   1/1     Running   0          1s    10.244.135.82   cks-w1   <none>           <none>
scanner-85dff684c9-rh2lt   1/1     Running   0          1s    10.244.135.80   cks-w1   <none>           <none>
scanner-85dff684c9-xxxts   1/1     Running   0          1s    10.244.135.81   cks-w1   <none>           <none>
```

The transcript leaves out the editor session, which adds `runtimeClassName: gvisor-pinned`.

In the test run, all three pods landed on `cks-w1`, and each one carried `nodeSelector: {"sandbox":"gvisor"}`, copied in from the RuntimeClass.

</details>

```console
$ ./certs/cks/task.sh check 4.9
== check task 4.9
  PASS  cks-w1 carries the label sandbox=gvisor, cks-cp does not
  PASS  RuntimeClass gvisor-pinned uses runsc and schedules onto sandbox=gvisor
  PASS  Deployment scanner has 3 ready pods, all on cks-w1, all under gVisor
== task 4.9: 3 passed, 0 failed
```

## Task 10: Pod-to-pod encryption with Cilium

**Time budget:** 5 minutes. **Host:** `cks-lima`.

```console
$ ./certs/cks/cluster/lima.sh start      # once, when the VM is off
...
time="2026-11-15T12:56:22Z" level=info msg="READY. Run `limactl shell cks-lima` to open the shell."
cluster ready
$ ./certs/cks/task.sh setup 4.10
== setup task 4.10
pod/web created
service/web created
pod/client created
Encryption: Disabled (1/1 nodes)
```

> Turn on WireGuard encryption for pod traffic in Cilium on `cks-lima`. Pods must keep reaching each other.

<details>
<summary>Solution</summary>

The Cilium docs' "WireGuard Transparent Encryption" page gives the Helm values, and the `cilium` command line tool applies them to the installed release:

```console
root@cks-lima:~# cilium upgrade --version 1.20.4 --reuse-values --set encryption.enabled=true --set encryption.type=wireguard
ℹ️  Using Cilium version 1.20.4
🔮 Auto-detected cluster name: cks-lima
🔮 Auto-detected kube-proxy has been installed
⚠️  You maybe need to restart Cilium pods for configmap changes to take effect
root@cks-lima:~# k -n kube-system rollout restart ds/cilium
daemonset.apps/cilium restarted
root@cks-lima:~# k -n kube-system rollout status ds/cilium
Waiting for daemon set "cilium" rollout to finish: 0 out of 1 new pods have been updated...
Waiting for daemon set "cilium" rollout to finish: 0 out of 1 new pods have been updated...
Waiting for daemon set "cilium" rollout to finish: 0 of 1 updated pods are available...
daemon set "cilium" successfully rolled out
root@cks-lima:~# cilium encrypt status
Encryption: Wireguard (1/1 nodes)
root@cks-lima:~# ip link show cilium_wg0
16: cilium_wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1405 qdisc noqueue state UNKNOWN mode DEFAULT group default 
    link/none 
```

The upgrade only changes the `cilium-config` ConfigMap, and the agents read it at start, so the restart is part of the job. The test run missed it once: the upgrade printed `You maybe need to restart Cilium pods for configmap changes to take effect`, and `cilium encrypt status` kept saying `Disabled`. After the restart, it said `Encryption: Wireguard (1/1 nodes)` 12 seconds later.

</details>

```console
$ ./certs/cks/task.sh check 4.10
== check task 4.10
  PASS  cilium-config has enable-wireguard: true
  PASS  cilium encrypt status reports Wireguard on every node
  PASS  the node has the WireGuard interface cilium_wg0
  PASS  pods still reach each other
== task 4.10: 4 passed, 0 failed
```

## Clean up

Tasks 2, 5 and 7 changed the API server, and task 9 labelled a node, so `./certs/cks/cluster/reset.sh` returns to a fresh cluster, and `./certs/cks/cluster/lima.sh reset` turns WireGuard off again.
