# CKS 04: Minimize microservice vulnerabilities (20%)

> New to a term here, like Pod Security Admission or RuntimeClass? The [glossary](../../course/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) running. The course's [module 2](../../course/02-identity-and-mtls.md) explains mTLS between pods, and [module 10](../../course/10-ebpf-and-cilium.md#concept-kernel-space-and-user-space) explains the kernel boundary that gVisor moves. Read them for the pod-to-pod encryption topic, which this domain covers in theory only.

A container is a process with a few fences around it. It shares the node's kernel, and by default it runs as root, keeps a dozen Linux capabilities, and sees its API token and its Secrets as plain text. This domain tightens each fence: what a pod may ask for, where Secrets rest, how a pod receives them, and which kernel a risky pod talks to. It has four tasks and takes about 45 minutes.

## Theory: four fences around a workload

### Pod Security Standards and Pod Security Admission

The **Pod Security Standards** are three fixed levels that say how much power a pod may ask for:

| Level | Allows | Typical user |
|---|---|---|
| `privileged` | everything | CNI agents, storage drivers |
| `baseline` | most apps; refuses host namespaces, privileged mode, extra capabilities | ordinary apps that run as root |
| `restricted` | only hardened pods: non-root, no privilege escalation, all capabilities dropped, a seccomp profile | everything you write yourself |

**Pod Security Admission** is the built-in admission plugin that applies a level to a namespace. You set it with labels, one per mode:

1. `pod-security.kubernetes.io/enforce` refuses pods that break the level.
2. `pod-security.kubernetes.io/warn` lets them in and prints a warning to the client.
3. `pod-security.kubernetes.io/audit` lets them in and writes a note into the audit log.

Enforce never touches pods that already run, the same lesson the course's [module 26](../../course/26-kyverno-policy-as-code.md#concept-two-paths-to-a-verdict) teaches for Kyverno. A Deployment's existing pods keep running after you label the namespace. The refusal hits the next pod the ReplicaSet creates, and it shows up only as an event on the ReplicaSet. A server-side dry run of the label lists the pods that would break the rule before you apply it:

```bash
k label --dry-run=server --overwrite ns secure-apps pod-security.kubernetes.io/enforce=restricted
```

In the test run, that printed `Warning: existing pods in namespace "secure-apps" violate the new PodSecurity enforce level "restricted:latest"`, then the four reasons for the one pod.

### Secrets at rest

A Secret is base64, and base64 is an encoding, not a cipher. The API server stores Secrets in etcd exactly as it stores ConfigMaps. Anybody with a copy of etcd's data or a backup file reads every password in the cluster.

An **EncryptionConfiguration** file tells the API server to encrypt chosen resources before it writes them to etcd. It lists **providers** in order:

1. The API server encrypts every new write with the first provider in the list.
2. On a read, it tries each provider until one decrypts the value.
3. `identity` means "no encryption". Keeping it last lets the API server still read the Secrets stored before you turned encryption on.

Turning encryption on changes nothing that's already stored. Each Secret gets encrypted the next time someone writes it. So the last step rewrites every Secret once: `k get secrets -A -o json | k replace -f -`.

The test run showed the difference with `etcdctl`. A plain object starts with `k8s` and a zero byte, followed by readable protobuf. After encryption, the value starts with `k8s:enc:aescbc:v1:key1:`, and everything after it is noise.

### Secrets inside the pod

A Secret reaches a container in one of two ways, and the file is the safer one:

| | Environment variable | Mounted file |
|---|---|---|
| Visible in | `/proc/<pid>/environ`, crash dumps, child processes, logs that print the environment | only the file, readable by the container's user |
| On rotation | stays old until the pod restarts | the kubelet updates the file within about a minute |

### Sandboxed containers

Every container on a node shares the node's kernel. One kernel bug reachable through a system call lets a container break out and own the node. A **sandboxed runtime** puts a second kernel between the container and the host. **gVisor** does it in user space: its `runsc` runtime catches the container's system calls and answers most of them itself. The host kernel sees only a small, fixed set of calls from gVisor. The cost is speed, so teams use it for untrusted code: CI jobs, customer plugins, scanners.

Kubernetes picks the runtime per pod with a **RuntimeClass**. Its `handler` names a runtime that containerd knows. The practice cluster's `cks-w1` has a `runsc` handler in `/etc/containerd/config.toml`. A pod asks for it with `runtimeClassName`.

### Pod-to-pod encryption

NetworkPolicy decides who may talk. It doesn't hide what they say: traffic between nodes crosses the network in clear text. The curriculum names two ways to encrypt it.

| | Istio | Cilium |
|---|---|---|
| How | mTLS between proxies, with a certificate per service account | WireGuard or IPsec tunnels between nodes |
| Proves | which workload sent the request | which node sent the packet |
| Turn on | label the namespace for the mesh, then a `PeerAuthentication` with `mode: STRICT` | Helm values `encryption.enabled=true` and `encryption.type=wireguard` |
| In this repo | the whole Istio route of the course, [module 2](../../course/02-identity-and-mtls.md) first | compared in [module 10](../../course/10-ebpf-and-cilium.md#why-this-way-the-two-designs-share-one-idea) |

The practice cluster doesn't run either. OrbStack's kernel has no WireGuard module, and Calico's own encryption needs WireGuard too. For an exam task, read the Istio or Cilium documentation, which the exam allows, and remember the two checks: `istioctl x describe pod` or the PeerAuthentication for Istio, and `cilium encrypt status` for Cilium.

## Task 1: Enforce the restricted standard

**Time budget:** 8 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 4.1
```

> 1. Make namespace `secure-apps` enforce the `restricted` Pod Security Standard, and warn about it too.
> 2. Deployment `app` in that namespace runs `busybox:1.36` with `sleep`. Change it so that its pods run under `restricted`, as user 1000.

<details>
<summary>Solution</summary>

Label first, and read the warning:

```bash
k label ns secure-apps pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted
```

The warning names the four gaps: `allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true, seccompProfile`. Fix each one in the pod template with `k -n secure-apps edit deploy app`:

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

Then `k -n secure-apps rollout status deploy app`. The new pod starts, and the old one goes away. `runAsUser` matters for `busybox`: the image's default user is root, and `runAsNonRoot` alone makes the kubelet refuse to start it.

</details>

```bash
./certs/cks/task.sh check 4.1
```

```
  PASS  namespace secure-apps enforces the restricted standard
  PASS  Deployment app has a ready pod that the namespace admitted
  PASS  no running pod in secure-apps violates restricted
  PASS  a privileged pod is refused in secure-apps
```

## Task 2: Encrypt Secrets at rest

**Time budget:** 10 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 4.2
```

The setup creates Secret `db-creds` in namespace `vault-test` and prints the password as it sits in etcd, in clear text.

> 1. Encrypt Secrets in etcd with the `aescbc` provider, using the configuration file `/etc/kubernetes/enc/enc.yaml` and a key named `key1`.
> 2. Encrypt the Secrets that already exist, too.
> 3. Prove it with `etcdctl` for `vault-test/db-creds`.

<details>
<summary>Solution</summary>

Make a 32-byte key and the file:

```bash
mkdir -p /etc/kubernetes/enc
head -c 32 /dev/urandom | base64
vim /etc/kubernetes/enc/enc.yaml
```

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

When the API server is back, rewrite every Secret and look at etcd:

```bash
k get secrets -A -o json | k replace -f -
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt \
  --key=/etc/kubernetes/pki/apiserver-etcd-client.key \
  get /registry/secrets/vault-test/db-creds --print-value-only | head -c 48 | od -c
```

The certificate paths come from the API server's own `--etcd-*` flags, so `grep etcd /etc/kubernetes/manifests/kube-apiserver.yaml` finds them when you forget. etcdctl 3.7 no longer needs `ETCDCTL_API=3` and prints a warning about it, but older versions in exam environments still need it. In the test run, the value started with `k8s:enc:aescbc:v1:key1:`, and the replace rewrote 4 Secrets.

</details>

```bash
./certs/cks/task.sh check 4.2
```

```
  PASS  the API server runs with --encryption-provider-config
  PASS  Secret db-creds is stored with prefix k8s:enc:aescbc:v1:
  PASS  the password no longer appears in etcd in clear text
  PASS  kubectl still reads the Secret
```

## Task 3: A Secret as a file, not an environment variable

**Time budget:** 5 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 4.3
```

> Pod `api` in namespace `orders` reads Secret `api-token` through the environment variable `API_TOKEN`. Change it to read the Secret as a read-only file at `/etc/api/token`, and remove the variable. Keep the pod name.

<details>
<summary>Solution</summary>

A pod's containers don't change in place, so save, delete and recreate:

```bash
k -n orders get pod api -o yaml > api.yaml
vim api.yaml       # remove env, add volumeMounts and volumes
k -n orders replace --force -f api.yaml
```

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

`replace --force` deletes the pod and creates it again in one step. `k -n orders exec api -- cat /etc/api/token` prints `t0k3n-123`.

</details>

```bash
./certs/cks/task.sh check 4.3
```

```
  PASS  pod api has no environment variable from a Secret
  PASS  pod api mounts Secret api-token read-only at /etc/api
  PASS  the token is readable at /etc/api/token
```

## Task 4: Sandbox a pod with gVisor

**Time budget:** 5 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 4.4
```

> 1. Create a RuntimeClass `gvisor` for the containerd handler `runsc`.
> 2. Make Deployment `untrusted` in namespace `sandbox` run its pods with it.

<details>
<summary>Solution</summary>

The RuntimeClass page in the Kubernetes docs has this YAML:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```

```bash
k apply -f rc.yaml
k -n sandbox patch deploy untrusted -p '{"spec":{"template":{"spec":{"runtimeClassName":"gvisor"}}}}'
k -n sandbox rollout status deploy untrusted
k -n sandbox exec deploy/untrusted -- dmesg | head -2
```

`dmesg` inside a gVisor pod shows gVisor's own made-up kernel log. In the test run: `[   0.000000] Starting gVisor...`. A normal pod gets `dmesg: klogctl: Operation not permitted` instead, because it shares the host kernel and may not read its log.

</details>

```bash
./certs/cks/task.sh check 4.4
```

```
  PASS  RuntimeClass gvisor uses handler runsc
  PASS  Deployment untrusted uses RuntimeClass gvisor
  PASS  the running pod's kernel is gVisor
```

## Clean up

Task 2 changed the API server. `./certs/cks/cluster/reset.sh` returns to a fresh cluster.
