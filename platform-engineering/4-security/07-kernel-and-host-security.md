# Module 4.7: Kernel and host security

> New to a term here, like AppArmor or WireGuard? The [glossary](../glossary.md#the-practice-cluster-and-the-security-modules) explains every term the security modules use.

**Before this module:** the theory in the modules these tasks come from. [Module 4.1](01-setting-up-a-secure-cluster.md#concept-layer-3-and-4-and-layer-7) explains Cilium's policies, [module 4.3](03-hardening-nodes.md#concept-kernel-modules) kernel modules, [module 4.4](04-hardening-workloads.md#concept-pod-to-pod-encryption) pod-to-pod encryption, and [module 4.6](06-runtime-security-and-auditing.md#concept-apparmor-a-filter-on-paths) AppArmor.

**You need:** a virtual machine with a kernel of its own, as [The VM for module 4.7](../../README.md#the-vm-for-the-kernel-tasks) explains. On a Mac that is the Lima VM `cks-lima`, which `./platform-engineering/practice/cluster/lima.sh create` builds.

The practice cluster runs on two kind nodes, which are containers that share one Linux kernel with each other and with every other container in the Docker engine. Most security controls live in Kubernetes or in a container runtime, so the shared kernel never gets in their way. Seven tasks are different, because they change the kernel itself: three Cilium tasks load eBPF programs into it, one task keeps kernel modules out of it, one turns on WireGuard encryption in it, and two load AppArmor profiles into it. That shared kernel has no AppArmor and no WireGuard, and Cilium there would rewire the network of every container at once. So these tasks run on a VM whose kernel belongs to it alone, and they sit together in this module.

gVisor and Falco stay in their modules on the practice cluster. gVisor brings its own user-space kernel, and Falco only watches system calls, so neither needs a kernel to itself, and the test runs passed both on kind.

Each task names its host. On a Mac, `cks-lima` is the Lima VM, and `./platform-engineering/practice/cluster/lima.sh shell` opens a root shell there. On [Proxmox](../practice-cluster.md#the-practice-cluster-on-proxmox-vms), the kernel module and AppArmor tasks run on `cks-w1` from the toolbox on `pe-lab`, as [the VM page](../practice-cluster.md#where-each-task-runs) explains, and the Cilium tasks need the Cilium VM `practice-cilium` that a later version of `create-vms.sh` adds. Task ids run from 4.7.1 to 4.7.7, so `./lab.sh task setup 4.7.6` prepares task 6. Run the task commands in a terminal on your Mac, outside `./lab.sh shell`, because they reach the VM with `limactl`, which only your Mac has. In the test run on 21 November 2026, from a fresh clone with only Docker, git and Lima on the PATH, every task failed its check after setup and passed after its solution.

| Task | Topic | Kernel feature |
|---|---|---|
| 1 | A CiliumNetworkPolicy at layers 3 and 4 | eBPF programs from Cilium |
| 2 | An HTTP rule with Cilium | eBPF programs and Cilium's Envoy |
| 3 | Entities and an explicit deny with Cilium | eBPF programs from Cilium |
| 4 | Keep a kernel module out | modprobe rules |
| 5 | Pod-to-pod encryption with Cilium | the WireGuard module |
| 6 | An AppArmor profile | AppArmor |
| 7 | AppArmor for a Deployment | AppArmor |

## Task 1: A CiliumNetworkPolicy at layers 3 and 4

**Time budget:** 5 minutes. **Host:** `cks-lima`.

```console
$ ./platform-engineering/practice/cluster/lima.sh start      # once, when the VM is off
...
time="2026-11-14T22:52:45Z" level=info msg="READY. Run `limactl shell cks-lima` to open the shell."
cluster ready
$ ./lab.sh task setup 4.7.1
== setup task 4.7.1
pod/backend created
service/backend created
pod/frontend created
pod/other created
pod/backend condition met
pod/frontend condition met
pod/other condition met
```

> Namespace `cilium-l4` runs pods `backend` (label `app=backend`, Service `backend` on port 80), `frontend` (`app=frontend`) and `other` (`app=other`). Create a CiliumNetworkPolicy `backend-ingress` so that `backend` accepts only TCP port 80, and only from `frontend`.

<details>
<summary>Solution</summary>

The Cilium docs' pages "Layer 3 examples" and "Layer 4 examples" hold this shape, so you copy it from there in the exam:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-ingress
  namespace: cilium-l4
spec:
  endpointSelector:
    matchLabels: {app: backend}
  ingress:
  - fromEndpoints:
    - matchLabels: {app: frontend}
    toPorts:
    - ports:
      - {port: "80", protocol: TCP}
```

The port is a string in a CiliumNetworkPolicy. A peer in `fromEndpoints` without a namespace label matches pods in the policy's own namespace only, the same way a plain `podSelector` does.

```console
root@cks-lima:~# k -n cilium-l4 get cnp
NAME              AGE   VALID
backend-ingress   20s   True
root@cks-lima:~# k -n cilium-l4 exec frontend -- wget -qO- -T 3 http://backend | head -4
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
root@cks-lima:~# k -n cilium-l4 exec other -- wget -qO- -T 3 http://backend          # download timed out
wget: download timed out
command terminated with exit code 1
```

</details>

```console
$ ./lab.sh task check 4.7.1
== check task 4.7.1
  PASS  CiliumNetworkPolicy backend-ingress selects app=backend and opens only TCP 80
  PASS  frontend reaches backend on port 80
  PASS  other does not reach backend
== task 4.7.1: 3 passed, 0 failed
```

## Task 2: An HTTP rule with Cilium

**Time budget:** 6 minutes. **Host:** `cks-lima`.

```console
$ ./lab.sh task setup 4.7.2
== setup task 4.7.2
pod/api created
service/api created
pod/client created
pod/other created
pod/api condition met
pod/client condition met
pod/other condition met
```

> Pod `api` in namespace `cilium-l7` serves `/public/` and `/admin/` on port 80. Create a CiliumNetworkPolicy `api-l7`:
>
> 1. Pods labelled `app=client` may send `GET` requests for paths under `/public/`.
> 2. Every other request from `client` gets refused at the HTTP layer.
> 3. No other pod reaches `api`.

<details>
<summary>Solution</summary>

A layer 7 rule hangs under `toPorts`, next to the port whose traffic it filters:

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-l7
  namespace: cilium-l7
spec:
  endpointSelector:
    matchLabels: {app: api}
  ingress:
  - fromEndpoints:
    - matchLabels: {app: client}
    toPorts:
    - ports:
      - {port: "80", protocol: TCP}
      rules:
        http:
        - method: GET
          path: "/public/.*"
```

`path` is a regular expression, so `/public/.*` covers everything under the folder. Test three requests, one allowed and two refused:

```console
root@cks-lima:~# k -n cilium-l7 exec client -- wget -qO- -T 5 http://api/public/                  # public
public
root@cks-lima:~# k -n cilium-l7 exec client -- wget -qO- -T 5 http://api/admin/                   # 403
wget: server returned error: HTTP/1.1 403 Forbidden
command terminated with exit code 1
root@cks-lima:~# k -n cilium-l7 exec client -- wget -qO- -T 5 --post-data=x http://api/public/    # 403
wget: server returned error: HTTP/1.1 403 Forbidden
command terminated with exit code 1
```

In the test run, the second and third commands printed `wget: server returned error: HTTP/1.1 403 Forbidden`, an answer from Cilium's Envoy proxy rather than from nginx. A request from `other` printed `wget: download timed out` instead, because layer 4 dropped it before any HTTP happened.

</details>

```console
$ ./lab.sh task check 4.7.2
== check task 4.7.2
  PASS  CiliumNetworkPolicy api-l7 has an HTTP rule
  PASS  client gets /public/ with GET
  PASS  client gets 403 for /admin/
  PASS  client gets 403 for a POST to /public/
  PASS  other does not reach api at all
== task 4.7.2: 5 passed, 0 failed
```

In the test run, the check failed four of five items before the solution.

## Task 3: Entities and an explicit deny with Cilium

**Time budget:** 6 minutes. **Host:** `cks-lima`.

```console
$ ./lab.sh task setup 4.7.3
== setup task 4.7.3
pod/agent created
pod/web created
service/web created
pod/agent condition met
pod/web condition met
  web reaches 1.1.1.1:443 before any policy: yes
```

> In namespace `cilium-egress`:
>
> 1. Create a CiliumNetworkPolicy `deny-world` that denies egress from every pod to everything outside the cluster. Use an entity and a deny rule.
> 2. Create a CiliumNetworkPolicy `agent-egress` so that pod `agent` reaches the Kubernetes API server, through an entity, and DNS, and nothing else.

<details>
<summary>Solution</summary>

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-world
  namespace: cilium-egress
spec:
  endpointSelector: {}
  egressDeny:
  - toEntities: [world]
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: agent-egress
  namespace: cilium-egress
spec:
  endpointSelector:
    matchLabels: {app: agent}
  egress:
  - toEntities: [kube-apiserver]
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - {port: "53", protocol: ANY}
```

Three details make these policies behave as the task asks:

- `deny-world` has no allow rules, so it doesn't turn `web`'s egress into an allow list. `web` still reaches other pods and only loses the world.
- `kube-apiserver` matches the API server wherever it runs, so the Service-address trap of [module 4.1, task 6](01-setting-up-a-secure-cluster.md#task-6-egress-to-dns-and-the-api-server-only) doesn't exist here, because Cilium works out the real address itself.
- `protocol: ANY` covers DNS over UDP and TCP in one entry.

```console
root@cks-lima:~# k -n cilium-egress exec agent -- nc -z -w 3 kubernetes.default.svc.cluster.local 443 && echo api ok
api ok
root@cks-lima:~# k -n cilium-egress exec web -- nc -z -w 3 1.1.1.1 443 || echo world blocked
command terminated with exit code 1
world blocked
```

In the test run, the setup printed `web reaches 1.1.1.1:443 before any policy: yes`, and after the solution the second command printed `world blocked`.

</details>

```console
$ ./lab.sh task check 4.7.3
== check task 4.7.3
  PASS  CiliumNetworkPolicy deny-world denies egress to the world entity for every pod
  PASS  CiliumNetworkPolicy agent-egress uses the kube-apiserver entity
  PASS  agent resolves names and reaches the API server
  PASS  agent does not reach web
  PASS  web reaches nothing outside the cluster
== task 4.7.3: 5 passed, 0 failed
```

## Task 4: Keep a kernel module out

**Time budget:** 4 minutes. **Host:** `cks-lima`.

```console
$ ./platform-engineering/practice/cluster/lima.sh start      # once, when the VM is off
cluster ready
$ ./lab.sh task setup 4.7.4
== setup task 4.7.4
dccp                  114688  0
tipc                  425984  0
```

> On `cks-lima`, the kernel holds the modules `dccp` and `tipc`. Unload them, and make sure no later request loads them again. Put the rules in a file under `/etc/modprobe.d/`.

<details>
<summary>Solution</summary>

```console
root@cks-lima:~# cat > /etc/modprobe.d/cks-blacklist.conf <<EOF
install dccp /bin/false
blacklist dccp
install tipc /bin/false
blacklist tipc
EOF
root@cks-lima:~# modprobe -r dccp tipc
root@cks-lima:~# lsmod | grep -E '^(dccp|tipc) '       # prints nothing
root@cks-lima:~# modprobe -n -v tipc                    # install /bin/false
install /bin/false 
```

In the test run, a direct `modprobe tipc` afterwards failed with `Error running install command '/bin/false' for module tipc: retcode 1`. The `sctp` module sat in the kernel too, with 8 users, and refused to unload, which is why the task picks two modules nobody uses.

</details>

```console
$ ./lab.sh task check 4.7.4
== check task 4.7.4
  PASS  tipc is not loaded
  PASS  modprobe refuses to load tipc
  PASS  dccp is not loaded, and modprobe refuses it
  PASS  the rule lives in a file under /etc/modprobe.d
== task 4.7.4: 4 passed, 0 failed
```

## Task 5: Pod-to-pod encryption with Cilium

**Time budget:** 5 minutes. **Host:** `cks-lima`.

```console
$ ./platform-engineering/practice/cluster/lima.sh start      # once, when the VM is off
...
time="2026-11-15T12:56:22Z" level=info msg="READY. Run `limactl shell cks-lima` to open the shell."
cluster ready
$ ./lab.sh task setup 4.7.5
== setup task 4.7.5
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
$ ./lab.sh task check 4.7.5
== check task 4.7.5
  PASS  cilium-config has enable-wireguard: true
  PASS  cilium encrypt status reports Wireguard on every node
  PASS  the node has the WireGuard interface cilium_wg0
  PASS  pods still reach each other
== task 4.7.5: 4 passed, 0 failed
```

## Task 6: An AppArmor profile

**Time budget:** 7 minutes. **Host:** `cks-lima`.

```console
$ ./platform-engineering/practice/cluster/lima.sh start      # once, when the VM is off
cluster ready
$ ./lab.sh task setup 4.7.6
== setup task 4.7.6
AppArmor parser error for /root/cks/cks-deny-write in profile /root/cks/cks-deny-write at line 6: syntax error, unexpected TOK_DENY, expecting TOK_ID or TOK_MODE or TOK_SET_VAR
```

The setup writes a profile with a mistake and shows the parser's complaint, which in the test run was `syntax error, unexpected TOK_DENY, expecting TOK_ID or TOK_MODE or TOK_SET_VAR`.

> On `cks-lima`:
>
> 1. Fix `/root/cks/cks-deny-write` so `apparmor_parser` accepts it. It must still deny every write.
> 2. Load the profile into the kernel, so that it also loads after a reboot.
> 3. Create pod `writer` in namespace `apparmor`, image `busybox:1.36`, command `sh -c "echo hi > /tmp/x; sleep 1d"`, with its container confined by the profile `cks-deny-write`.

<details>
<summary>Solution</summary>

The parser points at line 6, but the mistake sits one line higher, because the `file` rule above it lacks its comma, and every rule in an AppArmor profile ends with one:

```
profile cks-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /** w,
}
```

Then load the profile the way the theory shows:

```console
root@cks-lima:~# apparmor_parser -Q /root/cks/cks-deny-write && echo parses
parses
root@cks-lima:~# cp /root/cks/cks-deny-write /etc/apparmor.d/
root@cks-lima:~# apparmor_parser -r /etc/apparmor.d/cks-deny-write
root@cks-lima:~# aa-status | grep cks-deny-write
   cks-deny-write
```

The pod names the profile in its container's `securityContext`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: apparmor
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: [sh, -c, "echo hi > /tmp/x; sleep 1d"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: cks-deny-write
```

```console
root@cks-lima:~# k -n apparmor logs writer
sh: can't create /tmp/x: Permission denied
root@cks-lima:~# k -n apparmor exec writer -- cat /proc/1/attr/current
cks-deny-write (enforce)
```

In the test run, the log said `sh: can't create /tmp/x: Permission denied`, and the process's AppArmor label read `cks-deny-write (enforce)`. The name in `localhostProfile` is the name after `profile` in the file, not the file name, and here both are `cks-deny-write`. Before Kubernetes 1.30, the annotation `container.apparmor.security.beta.kubernetes.io/<container>: localhost/<profile>` did this job, and old exam tasks still show it, but write the field.

</details>

```console
$ ./lab.sh task check 4.7.6
== check task 4.7.6
  PASS  the profile in /root/cks/cks-deny-write parses and still denies every write
  PASS  profile cks-deny-write is loaded in enforce mode
  PASS  pod writer asks for the Localhost profile cks-deny-write
  PASS  pod writer runs, confined by the profile
  PASS  the write to /tmp/x was denied
== task 4.7.6: 5 passed, 0 failed
```

In the test run, every check failed before the solution.

## Task 7: AppArmor for a Deployment

**Time budget:** 6 minutes. **Host:** `cks-lima`.

```console
$ ./lab.sh task setup 4.7.7
== setup task 4.7.7
deployment.apps/web created
  web-6c48cbcc8b-87qfj CreateContainerError
  Error: failed to get container spec opts: failed to generate apparmor spec opts: apparmor profile not found cks-nginx
```

The setup shows the Deployment's pod and its error, which in the test run were `CreateContainerError` and `failed to generate apparmor spec opts: apparmor profile not found cks-nginx`.

> Deployment `web` in namespace `aa-web` asks for the AppArmor profile `cks-nginx`, and its pod doesn't start. The profile file is `/etc/apparmor.d/cks-nginx` on `cks-lima`. Make the Deployment run confined by that profile.

<details>
<summary>Solution</summary>

The profile file exists, but nothing loaded it into the kernel, so load it and restart the Deployment:

```console
root@cks-lima:~# aa-status | grep cks-nginx || echo not loaded
not loaded
root@cks-lima:~# apparmor_parser -r /etc/apparmor.d/cks-nginx
root@cks-lima:~# aa-status | grep cks-nginx
   cks-nginx
root@cks-lima:~# k -n aa-web rollout restart deploy web
deployment.apps/web restarted
root@cks-lima:~# k -n aa-web rollout status deploy web
Waiting for deployment "web" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "web" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "web" rollout to finish: 1 old replicas are pending termination...
deployment "web" successfully rolled out
```

The profile allows nginx everything except writes below `/usr/share/nginx/html`, so prove both sides:

```console
root@cks-lima:~# k -n aa-web exec deploy/web -- sh -c 'echo x > /usr/share/nginx/html/index.html'    # Permission denied
sh: can't create /usr/share/nginx/html/index.html: Permission denied
command terminated with exit code 1
root@cks-lima:~# k -n aa-web exec deploy/web -- wget -qO- http://127.0.0.1 | head -4                  # the nginx page
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

A process started with `kubectl exec` runs under the container's profile too, which is why the first command fails. The kubelet retries a failed container with a growing delay, so `rollout restart` gets a new pod at once instead of waiting for the next retry.

</details>

```console
$ ./lab.sh task check 4.7.7
== check task 4.7.7
  PASS  profile cks-nginx is loaded in enforce mode
  PASS  Deployment web has a ready pod
  PASS  a write below /usr/share/nginx/html fails with Permission denied
  PASS  a write to /tmp still works, and nginx serves
== task 4.7.7: 4 passed, 0 failed
```

## Clean up

Every task here changes only the Lima VM, so one reset returns it to a fresh cluster with Cilium and without the profiles and modprobe rules. It took 3 minutes 27 seconds in the test run:

```console
$ ./platform-engineering/practice/cluster/lima.sh reset
=== wiping the cluster on cks-lima
...
=== 4/4 Cilium 1.20.4
cilium 1.20.4 ready
cluster ready
```

On Proxmox, tasks 4, 6 and 7 changed `cks-w1`, and `./platform-engineering/practice/cluster/reset.sh` rebuilds the cluster.
