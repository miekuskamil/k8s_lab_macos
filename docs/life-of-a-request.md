# The life of a request

You type `curl localhost:8080/api/orders` on your Mac, and JSON comes back in about 20 milliseconds. This document follows that request, and the pod that answers it, through every layer of the lab. On the way, it passes through these layers and back:

- the API server's gates
- the controllers
- the scheduler
- the kubelet
- the Linux network stack
- kube-proxy's rules
- ztunnel's tunnels
- the waypoint's HTTP checks

Every step shows the command, the real output from one run of this lab, and what the output proves. Your IPs, names and timings will differ. The overall pattern stays the same.

[Module 29](../platform-engineering/29-life-of-a-request.md) is the hands-on version, with fewer explanations. Terms are in the [glossary](../platform-engineering/glossary.md).

**Contents**

1. [The control plane: one write, many watchers](#part-1-the-control-plane-one-write-many-watchers)
2. [From an object to a ready pod](#part-2-from-an-object-to-a-ready-pod)
3. [Scenario A: a request without a mesh](#part-3-scenario-a-a-request-without-a-mesh)
4. [Scenario B: a request through the ambient mesh](#part-4-scenario-b-a-request-through-the-ambient-mesh)
5. [Security, layer by layer](#part-5-security-layer-by-layer)
6. [What breaks when a component is down](#part-6-what-breaks-when-a-component-is-down)

**The cast in this run**

| Thing | Value |
|---|---|
| Node | `k3d-k8s-lab-server-0`, a Docker container, IP `192.168.107.2` |
| Pod network, this node's range | `10.42.0.0/16`, `10.42.0.0/24` |
| Service network | `10.43.0.0/16` |
| Scenario A | client pod `10.42.0.198`, Service `hello` `10.43.76.137`, nginx pod `10.42.0.197` |
| Scenario B | serverlb container `192.168.107.3`, gateway pod `10.42.0.88`, frontend `10.42.0.13`, backend Service `10.43.239.201`, waypoint `10.42.0.81`, backend-v1 `10.42.0.58`, redis `10.42.0.14` |

**Your values will differ.** These addresses come from one run of the lab. Kubernetes hands out pod IPs and Service IPs fresh every time it creates a pod or a Service. So a rebuild, a pod restart or a rollout gives you new numbers. The names, ports and ranges stay the same: `hello` is always `hello`, the backend always listens on 8000, pods always get `10.42.x.x` and Services `10.43.x.x`.

To follow along, print your own cast and keep it next to this page:

```bash
./platform-engineering/my-values.sh
```

It prints every row of the table above with your lab's current values, in the same order. When the text says `10.42.0.197`, read the "hello pod" line of your output instead. The commands in this document never hard-code an IP: they look it up first, for example `SVCIP=$(kubectl -n course-life get svc hello -o jsonpath='{.spec.clusterIP}')`, so they work on any run. Only the outputs quoted here show this run's numbers.

---

## Part 1: The control plane: one write, many watchers

![The control plane](diagrams/life-1-control-plane.svg)

Before any packet flows, a pod must exist. It starts as one HTTP request to the API server. Everything else in Kubernetes reacts to what that request stores.

The diagram numbers the same six steps as this list:

1. kubectl sends the request to the API server over HTTPS.
2. Authentication: the API server checks who you are.
3. Authorization: the API server checks what you may do, first with the Node authorizer and then with RBAC.
4. Admission: webhooks and built-in plugins may change the object or refuse it.
5. Storage: kine writes the object to SQLite. Other clusters use etcd here.
6. Watch: every interested component hears about the change.

A refusal at step 2, 3 or 4 goes straight back to kubectl. The answer is 401, 403, or 400/422. The sections below take these steps one at a time.

### 1.1 kubectl is an HTTP client

kubectl has no private line into the cluster. It sends ordinary web requests to the API server, the front door of the cluster, and you see them if you ask. With `-v=6`, kubectl logs every request it makes. Here is the log for a new Deployment called `v6demo`. The lab created it and then deleted it again.

```bash
kubectl -n course-life create deployment v6demo --image=nginx:1.27-alpine --dry-run=client -o yaml \
  | kubectl apply -f - -v=6 2>&1 | grep -oE 'verb="[A-Z]+" url="[^"]*" status="[^"]*"'
```

```text
verb="GET" url="/openapi/v3?timeout=32s" status="200 OK"
verb="GET" url="/openapi/v3/apis/apps/v1?hash=0258D876...&timeout=32s" status="200 OK"
verb="GET" url="/apis/apps/v1/namespaces/course-life/deployments/v6demo" status="404 Not Found"
verb="GET" url="/api/v1/namespaces/course-life" status="200 OK"
verb="POST" url="/apis/apps/v1/namespaces/course-life/deployments?fieldManager=kubectl-client-side-apply&fieldValidation=Strict" status="201 Created"
```

1. kubectl downloads the API's OpenAPI schema for the `apps/v1` group. The schema is a description of every field a Deployment may have, so kubectl knows the shape of the object it sends. The `hash` lets kubectl keep the schema between runs instead of downloading it every time.
2. It asks for the object. `404 Not Found` tells kubectl to create it. A `200` would tell kubectl to compute the difference and send a PATCH instead. On the client side, `apply` does nothing more than this.
3. It sends a `POST` to `/apis/apps/v1/namespaces/course-life/deployments`. The path works like a postal address. It spells out the API group (`apps`), the version (`v1`), the namespace and the kind of resource. Two settings come at the end:
   - `fieldValidation=Strict` tells the API server to refuse unknown fields. Without it, a typo in a field name would vanish silently.
   - `fieldManager` records who owns which fields, so a later `apply` from someone else doesn't overwrite them by accident.
4. `201 Created` comes back only after the object passed every gate below and landed in storage.

kubectl is nothing special. Any HTTP client with the right credentials does the same.

Before the API server stores anything, the request passes a series of checks. This document calls them gates. The API server's start-up flags decide how each gate behaves. k3s runs the API server inside its own process, so the k3s log shows those flags:

```bash
docker logs k3d-k8s-lab-server-0 2>&1 | grep -m1 "Running kube-apiserver" | tr ' ' '\n' \
  | grep -E "authorization-mode|anonymous-auth|etcd-servers|enable-admission|client-ca-file|service-account-issuer|service-cluster-ip-range"
```

```text
--anonymous-auth=false
--authorization-mode=Node,RBAC
--client-ca-file=/var/lib/rancher/k3s/server/tls/client-ca.crt
--enable-admission-plugins=NodeRestriction
--etcd-servers=unix://kine.sock
--service-account-issuer=https://kubernetes.default.svc.cluster.local
--service-cluster-ip-range=10.43.0.0/16
```

Each flag sets up one of the gates in the diagram. Read the gates top to bottom, and you follow the request's path.

### 1.2 Gate 1, authentication: who are you?

This is step 2 in the diagram. The first gate asks who is calling. The API server needs a name before it decides what that caller may do, so it accepts a request only when the request proves an identity. Two methods matter here, one for people and one for pods:

- You prove who you are with a **client certificate**, a digital ID card stored in your kubeconfig. The cluster's certificate authority signed it with `client-ca.crt`. The API server checks that signature, like a guard checking the stamp on a passport. It reads your user name from the certificate's subject (CN) field. It reads your groups from the organisation (O) fields.
- A pod proves who it is with a **service account token**. The token is a signed JWT, a small signed text that names the pod's identity. The kubelet places it in the pod's file system at `/var/run/secrets/kubernetes.io/serviceaccount/token`.

```bash
kubectl auth whoami
```

```text
ATTRIBUTE   VALUE
Username    system:admin
Groups      [system:masters system:authenticated]
```

Now the pod's side. This decodes the client pod's token without printing it:

```text
header {'alg': 'RS256'}
iss https://kubernetes.default.svc.cluster.local
aud ['https://kubernetes.default.svc.cluster.local', 'k3s']
sub system:serviceaccount:course-life:default
lifetime_s 31536000
bound to pod client-7695f5987b-7r8w7
```

A token is a list of statements, called claims. Each one limits where and how long the token works, so a stolen copy is worth less. What each claim means:

1. `iss` (the issuer) matches `--service-account-issuer`. The API server trusts only tokens it signed itself.
2. `aud` (the audience) lists who the token is for. The API server refuses a token meant for another audience.
3. `sub` (the subject) is the identity. Here it is service account `default` in namespace `course-life`.
4. The token is **bound to the pod**. If you delete the pod, the token stops working, even before it expires. The kubelet also replaces the token on disk well before the end of its lifetime.

`--anonymous-auth=false` means the API server stops any request that carries no identity at all. Here is what the client pod gets when it asks to list pods, first with its token and then without it:

```text
403 Forbidden pods is forbidden: User "system:serviceaccount:course-life:default" cannot list resource "pods" in API group "" in the namespace "course-life"
401 Unauthorized Unauthorized
```

Two different gates refused these requests:

- With the token, authentication worked, because the message names the user. Then authorization said no, and the answer is **403**.
- Without the token, authentication failed, and the answer is **401**.

The status code tells you which gate stopped you.

### 1.3 Gate 2, authorization: may you do this?

This is step 3 in the diagram. The second gate asks whether this caller may do this action. Knowing who you are isn't enough. A cluster has many users and programs, and each one should touch only what its job needs. An authorizer is a rule checker that answers yes or no. `--authorization-mode=Node,RBAC` tells the API server to ask two authorizers, in this order. The first one that says yes wins. If neither says yes, the answer is 403.

- The **Node** authorizer serves kubelets only. A kubelet is the agent on each node that runs pods. It logs in as user `system:node:<name>`. It may read the pods, secrets and config maps for pods on its own node, and nothing else. So a broken-into node doesn't expose the secrets of every other node.
- **RBAC** (role-based access control) handles everyone else. A Role or ClusterRole is a list of allowed actions. A binding attaches that list to a user, a group or a service account. RBAC checks those bindings.

```bash
kubectl auth can-i create deployments -n course-life
kubectl auth can-i create deployments -n course-life --as=system:serviceaccount:shop:frontend
kubectl auth can-i --list --as=system:kube-scheduler | grep -E "pods/binding|bindings|^pods "
```

```text
yes
no
bindings        []   []   [create]
pods/binding    []   []   [create]
pods            []   []   [delete get list watch]
```

You get `yes` because you belong to `system:masters`. This is a special group, and the API server lets it through before RBAC even runs. For this reason, only emergency "break-glass" credentials should carry it. The frontend's service account gets `no`, because the shop's apps have no Kubernetes API permissions at all.

The last command shows that the scheduler is just another API client with a narrow role. The scheduler's job is to choose a node for each pod. To do that, it may watch pods and create `pods/binding`. Creating a `pods/binding` is exactly what "binding a pod to a node" means at the API level. The scheduler may not create pods or change their specs.

### 1.4 Gates 3 to 5, admission: should the object change, and is it allowed?

The next gates look at the object itself, not at the caller. They exist so the cluster stores only objects that make sense and follow its rules. They may also fill in or add parts of the object before it is saved. This stage is called admission, step 4 in the diagram. It runs after authorization, and only for writes. The headings count it as three gates, because it has three steps, in this order:

1. Mutating admission may change the object. For example, it may add a default value or an extra container.
2. The API server checks the object against the schema, the list of allowed fields and values.
3. Validating admission may refuse the object.

Two kinds of checkers take part in the admission steps. Built-in plugins, compiled into the API server, run first. For example, `NodeRestriction`, which the flag above turns on, stops a kubelet from changing other nodes' objects. Webhooks run after the built-in plugins. A webhook is a call from the API server, over HTTPS, to a program running in the cluster. It lets tools such as Istio add their own rules without changing the API server.

```bash
kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations
```

```text
NAME                                                                               WEBHOOKS
mutatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook     1
mutatingwebhookconfiguration.admissionregistration.k8s.io/istio-sidecar-injector   4

NAME                                                                                       WEBHOOKS
validatingwebhookconfiguration.admissionregistration.k8s.io/cert-manager-webhook           1
validatingwebhookconfiguration.admissionregistration.k8s.io/istio-validator-istio-system   1
validatingwebhookconfiguration.admissionregistration.k8s.io/istiod-default-validator       1
```

Istio's sidecar injector is a mutating webhook. It adds a proxy container to pods, and it matters in [module 7](../platform-engineering/07-sidecar-mode.md). Istio's validator is a validating webhook. It checks every Istio resource you write. Here are two refusals, one from each kind of check:

```text
The Deployment "bad" is invalid: spec.replicas: Invalid value: -1: must be greater than or equal to 0
Error from server: error when creating "STDIN": admission webhook "validation.istio.io" denied the request: configuration is invalid: 2 errors occurred:
	* invalid policy broken.course-life: invalid `value` for `key` request.colour: unknown attribute: request.colour
	* invalid policy broken.course-life: invalid `notValue` for `key` request.colour: unknown attribute: request.colour
```

1. The first refusal came from the API server's own schema validation. No webhook took part.
2. The second refusal came from istiod, Istio's control program. The API server sent the AuthorizationPolicy to istiod. istiod found the unknown condition key `request.colour`. The API server then passed the refusal back to you word for word.

A refused write stops here. The API server stores nothing, uses no `resourceVersion`, and no controller ever hears about it. Every write in the cluster passes through this one point, like every letter passing one post office. For this reason, policy tools such as Kyverno ([module 26](../platform-engineering/26-kyverno-policy-as-code.md)) plug in at admission.

### 1.5 Gate 6, storage: kine instead of etcd

This is step 5 in the diagram. The last gate saves the object, so it survives restarts and every component sees the same truth. Normal Kubernetes stores its data in etcd, a database built for clusters. k3s swaps in something lighter. `--etcd-servers=unix://kine.sock` tells the API server to talk to a local socket file as if it were etcd. On the other end sits **kine**, a translator that is part of k3s. kine turns each etcd call into SQL against a single SQLite file:

```bash
docker exec k3d-k8s-lab-server-0 ls -la /var/lib/rancher/k3s/server/db/
```

```text
-rw-r--r-- 1 root root 75644928 Nov 13 13:11 state.db
-rw-r--r-- 1 root root    65536 Nov 13 13:11 state.db-shm
-rw-r--r-- 1 root root 32992992 Nov 13 13:11 state.db-wal
```

The whole cluster's state lives in that 75 MB file and its write-ahead log, a journal of recent changes. Each write becomes a new row with a revision number that only grows. That number becomes the object's `resourceVersion`. A multi-node production cluster uses etcd for the same job. etcd keeps several copies on different machines. Before it confirms a write, it copies the write to a majority of those machines with the Raft protocol. So losing one machine loses no data.

`resourceVersion` also prevents lost updates. Imagine two controllers read the same object, and both change it. Without a check, the second write would silently erase the first. To prevent this, every update carries the version the writer last read. If somebody else wrote in between, the API server answers **409 Conflict**. The writer then reads the object again and retries. Controllers rely on this all the time. The name for this pattern is optimistic concurrency.

### 1.6 The watch: how everybody else finds out

Step 6 in the diagram starts here. Once the object is stored, the other components need to learn about it. Asking the API server "anything new?" every second would waste work, so controllers never poll. Instead, each one opens a **watch**. A watch is a long HTTP response that never ends. The API server sends an event down it every time a matching object changes, like a news feed. Open one yourself:

```bash
kubectl get --raw "/api/v1/namespaces/course-life/pods?watch=1&timeoutSeconds=3&labelSelector=app%3Dhello" | cut -c1-120
```

```text
{"type":"ADDED","object":{"kind":"Pod","apiVersion":"v1","metadata":{"name":"hello-76fb6c6b6f-sj879",...,"resourceVersion":"16403",...
```

The API server keeps a **watch cache** in memory. Because of it, a thousand watchers don't cause a thousand database reads. kine itself polls its table for new rows and turns them into watch events for the API server. If a watcher's connection drops, the watcher reconnects with its last `resourceVersion`. The API server then sends only the events it missed.

Inside a controller, an **informer** holds the watch. The informer is a client-side cache that keeps a local copy of every object the controller cares about. The controller reads from that copy, not from the API server.

One more control-plane detail matters in a cluster with several servers. There, the controller manager and the scheduler run on each server for safety. If two copies acted at once, they would fight over the same objects, so only one copy acts. The copies choose that leader with **Lease** objects. A Lease works like a sign-in sheet: the holder renews it every few seconds, and if it stops, another copy takes over. This lab has a single server, so k3s starts the scheduler with `--leader-elect=false`. The leases you see belong to the API server itself and to cert-manager:

```text
NAME                                      HOLDER
apiserver-vflphtfe6p3awncxc7x4iejdh4      apiserver-vflphtfe6p3awncxc7x4iejdh4_11dc13d5-...
cert-manager-cainjector-leader-election   cert-manager-cainjector-7986dd69f7-74jnf_...
cert-manager-controller                   cert-manager-5db8fdc797-rhdbp-external-cert-manager-controller
```

---

## Part 2: From an object to a ready pod

![From an object to a ready pod](diagrams/life-2-pod-startup.svg)

A stored Deployment is only a wish. This part follows the chain of components that turns it into a pod that answers requests. In the diagram, each arrow is one component reacting to a change it watched. The numbered steps match this list:

1. The Deployment controller creates a ReplicaSet.
2. The ReplicaSet controller creates a Pod with no node.
3. The scheduler picks a node for the Pod.
4. The kubelet on that node asks containerd for a sandbox.
5. The CNI plugins give the pod an IP address. flannel does this everywhere, and istio-cni adds its rules in ambient namespaces.
6. The containers start, and the readiness probe passes.
7. The EndpointSlice controller adds the pod's IP to its Service. Then kube-proxy, CoreDNS and istiod update.

Sections 2.1 and 2.2 cover steps 1 to 3. Sections 2.3 to 2.5 cover steps 4 to 7.

### 2.1 The controllers hand the work along

You created a Deployment, but a Deployment doesn't run anything. Several components turn it, step by step, into a running container. Each one watches for its own kind of object, does one small job, and writes the result back. The event log shows the hand-offs:

```bash
kubectl -n course-life get events --sort-by=.firstTimestamp \
  -o custom-columns=TIME:.firstTimestamp,WHO:.source.component,KIND:.involvedObject.kind,REASON:.reason,MESSAGE:.message
```

```text
13:11:34Z    deployment-controller  Deployment ScalingReplicaSet  Scaled up replica set hello-76fb6c6b6f to 1
13:11:34Z    replicaset-controller  ReplicaSet SuccessfulCreate   Created pod: hello-76fb6c6b6f-sj879
13:11:34.046 default-scheduler      Pod        Scheduled          Successfully assigned course-life/hello-76fb6c6b6f-sj879 to k3d-k8s-lab-server-0
13:11:34Z    kubelet                Pod        Pulled             Container image "nginx:1.27-alpine" already present on machine
13:11:34Z    kubelet                Pod        Created            Created container web
13:11:34Z    kubelet                Pod        Started            Started container web
```

Four components made four writes, all inside one second. None of them called another. Each one only reacted to what the previous one stored:

1. The **Deployment controller** saw a new Deployment. It computed a short fingerprint, a hash, of the pod template (`pod-template-hash=76fb6c6b6f`). It then created a ReplicaSet with that hash in its name. If you change the template, the hash changes, and the controller creates a new ReplicaSet. A rolling update is the Deployment controller scaling the new ReplicaSet up and the old one down, in steps.
2. The **ReplicaSet controller** saw a ReplicaSet that wants one pod and has zero. It created a Pod with no node.
3. The **scheduler** saw a Pod with an empty `spec.nodeName`. It picked a node and wrote a binding.
4. The **kubelet** on that node saw a Pod assigned to it and started it.

This design means no component depends on another being up at the same moment. If one is down for a minute, it catches up from the stored objects when it returns.

Each object points to its creator:

```text
pod=hello-76fb6c6b6f-sj879
ReplicaSet/hello-76fb6c6b6f
Deployment/hello  pod-template-hash=76fb6c6b6f
```

These links are called **owner references**. They are how `kubectl delete deployment hello` also removes the ReplicaSet and the pods. A background cleaner, the garbage collector, deletes every object whose owner is gone. Without it, deleting a Deployment would leave its pods running with nobody managing them.

### 2.2 The scheduler decides: filter, score, bind

The scheduler's job is to put each pod on a node that has room for it and meets its rules. It works on one pod at a time, in phases:

1. **Filter.** The scheduler drops every node where the pod doesn't fit. A node drops out for any of these reasons:
   - It has too little free CPU or memory for the pod's *requests*.
   - Its labels don't match the pod's `nodeSelector` or affinity rules.
   - It has a taint, a "keep out" mark, that the pod doesn't tolerate.
   - A host port the pod needs is already in use.
2. **Score.** The scheduler ranks the remaining nodes. It prefers to spread replicas apart, to use nodes that already have the image, and to balance resource use.
3. **Bind.** The scheduler writes the winner into the pod through the `pods/binding` subresource you saw in 1.3.
4. **Preemption.** If filtering leaves no node, the scheduler looks for lower-priority pods to evict so this one fits. If evicting doesn't help, the pod stays `Pending`, and the scheduler retries later.

Here are two pods that fail on purpose. One is too big, and the other is too picky:

```text
greedy: 0/1 nodes are available: 1 Insufficient memory. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
picky: 0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

Read each message as the filter's report. It examined one node and gives one reason that node failed. For `picky`, the scheduler doesn't even try preemption, because evicting pods won't add a label to a node.

A pod states two numbers for memory and CPU. The *request* is what it reserves. The *limit* is the most it may use. The filter counts only requests. It ignores limits and the real use:

```text
  Resource           Requests      Limits
  cpu                1785m (11%)   19850m (132%)
  memory             3620Mi (30%)  12842Mi (106%)
```

Requests fill 30% of the node's memory, so new pods keep fitting. Limits add up to 106%. That is fine most of the time, because pods rarely all use their full limit at once. If they did, the node would run out of memory. The kernel's OOM ("out of memory") killer would then pick processes to kill.

To decide who goes first, Kubernetes sorts pods into quality-of-service (QoS) classes. The `hello` pod sets a memory request (16Mi) lower than its limit (64Mi). So Kubernetes puts it in the **Burstable** QoS class (`qosClass=Burstable`). When memory runs short, the kubelet evicts pods in this order:

1. BestEffort pods, which set no requests or limits.
2. Burstable pods that use more than they requested.
3. Guaranteed pods, last.

### 2.3 The kubelet: sandbox first, then network, then containers

The kubelet doesn't run containers itself. It asks a container runtime, containerd, to do it. The two talk over the **CRI** (Container Runtime Interface), a fixed set of commands sent through a local socket file. The kubelet starts every pod in the same order:

1. **RunPodSandbox.** containerd starts a tiny `pause` container. Its only job is to hold the pod's Linux namespaces. A namespace is a private view of one part of the system. The most important one here is the network namespace, the pod's own copy of the network stack. The app containers join that namespace later. That is why all containers in a pod share one IP address and one `localhost`. The `pause` container keeps the namespace alive even when an app container restarts.
2. **CNI.** The network plugins, called CNI plugins, connect that namespace to the node. containerd runs the plugins listed in `/var/lib/rancher/k3s/agent/etc/cni/net.d/10-flannel.conflist`. Section 2.4 shows what they build.
3. **Containers.** The kubelet pulls the image (here, it was already present). It creates the container with its cgroup limits, the kernel's caps on CPU and memory. Then it starts the container.
4. **Probes.** The kubelet runs the readiness probe, a `GET /` every 2 s. The pod becomes `Ready` only when the probe passes.

```bash
docker exec k3d-k8s-lab-server-0 crictl pods --namespace course-life
```

```text
POD ID              CREATED             STATE    NAME                      NAMESPACE
09787aa3406d6       5 seconds ago       Ready    client-7695f5987b-7r8w7   course-life
2f1f973ea4a59       5 seconds ago       Ready    hello-76fb6c6b6f-sj879    course-life
```

The pod's conditions record each stage:

```text
PodScheduled=2026-11-13T13:11:34Z
Initialized=2026-11-13T13:11:34Z
PodReadyToStartContainers=2026-11-13T13:11:35Z
ContainersReady=2026-11-13T13:11:35Z
Ready=2026-11-13T13:11:35Z
```

`PodReadyToStartContainers` means the sandbox and its network are ready. From binding to Ready took about one second, because the image was already on the node.

### 2.4 The pod's network, from Layer 2 up

A new pod starts with an empty, private network. The CNI plugin gives it an address and connects it to the node, so packets get in and out. Think of the pod as a room and the node as the building. The plugin runs a cable from the room to a switch in the building. Look from inside the pod first:

```bash
kubectl -n course-life exec deploy/hello -- ip addr show eth0
kubectl -n course-life exec deploy/hello -- ip route
```

```text
2: eth0@if200: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1450 qdisc noqueue state UP qlen 1000
    link/ether ae:8e:15:12:a9:a6 brd ff:ff:ff:ff:ff:ff
    inet 10.42.0.197/24 brd 10.42.0.255 scope global eth0

default via 10.42.0.1 dev eth0
10.42.0.0/24 dev eth0 scope link  src 10.42.0.197
10.42.0.0/16 via 10.42.0.1 dev eth0
```

1. `eth0@if200` is one end of a **veth pair**. A veth pair is a virtual network cable with one end in each room. `@if200` says the other end is interface number 200, in another namespace.
2. The pod has the address `10.42.0.197/24`, from this node's range. flannel is the CNI plugin in this lab. Its address manager, host-local IPAM, hands out free addresses from that range.
3. The routes give two rules. Pods on this node (`10.42.0.0/24`) are reachable directly on `eth0`. Everything else goes to the gateway `10.42.0.1`.
4. The MTU, the largest packet size, is **1450**, not 1500. The reason is the trip to other nodes. flannel wraps those packets in an extra 50-byte VXLAN header. With 50 bytes kept free, a wrapped pod packet still fits in one 1500-byte frame.

Now the node's side. Interface 200 is the other end of the cable:

```bash
docker exec k3d-k8s-lab-server-0 ip -o link | grep "^200:"
```

```text
200: vethcfa77a79@if2: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue master cni0 state UP ...
```

`master cni0` means this end plugs into the **cni0 bridge**. The bridge is a virtual network switch inside the node. Every pod on the node has a cable plugged into it. The bridge itself has the gateway address:

```text
cni0             UP             10.42.0.1/24
```

And the node's routing table:

```text
default via 192.168.107.1 dev eth0
10.42.0.0/24 dev cni0 proto kernel scope link src 10.42.0.1
192.168.107.0/24 dev eth0 proto kernel scope link src 192.168.107.2
```

Pods on the same switch find each other the way machines on a real switch do. A pod shouts "who has this IP?" and the owner answers with its hardware address, its MAC address. This exchange is called ARP. The node's neighbour table shows the MAC addresses it learned on the bridge:

```text
10.42.0.31 lladdr ca:b2:a7:54:61:ad REACHABLE
10.42.0.29 lladdr 82:be:84:17:40:84 REACHABLE
```

This lab has one node, so every pod sits on the same bridge. A cluster with more nodes needs a way to reach pods in other buildings. For this, flannel creates a VXLAN device and adds a route to each other node through it:

```text
3: flannel.1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 ...
    vxlan id 1 local 192.168.107.2 dev eth0 srcport 0 0 dstport 8472 ...
```

`flannel.1` works like an envelope service. It puts a pod packet meant for another node inside a UDP packet, addressed to port 8472 on that node's IP. The other node opens the envelope and drops the original packet onto its own bridge.

flannel writes its settings into `/run/flannel/subnet.env`:

- `FLANNEL_NETWORK=10.42.0.0/16`, the whole pod network
- `FLANNEL_SUBNET=10.42.0.1/24`, this node's share
- `FLANNEL_MTU=1450`, the packet size from point 4 above

flannel also adds a masquerade rule. Masquerading means replacing a packet's source address with the node's own address. The rule decides which traffic gets that treatment:

```text
-A FLANNEL-POSTRTG -s 10.42.0.0/24 -d 10.42.0.0/16 -m comment --comment "flanneld masq" -j RETURN
```

Traffic from pod to pod keeps its real addresses (`RETURN` means "leave it alone"). Traffic from pods to the outside world gets the node's address. Without that, the outside world would see a `10.42.x.x` address it has no route back to, and replies would get lost.

### 2.5 Ready, then endpoints, then everybody updates

A running pod still gets no traffic until the rest of the cluster knows its address. A Service keeps a list of the pods behind it, called an EndpointSlice. When the pod turns Ready, the **EndpointSlice controller** adds the pod's IP to the `hello` Service's slice:

```text
10.42.0.197 ready=true node=k3d-k8s-lab-server-0
```

Three components watch that list. Each one updates itself, without waiting for the others:

1. **kube-proxy** rewrites its iptables rules on every node. These kernel rules send traffic for the Service's address to the pod. Section 3.2 shows them.
2. **CoreDNS**, the cluster's DNS server, already answers `hello.course-life.svc.cluster.local` with the Service's ClusterIP. For a headless Service, which has no ClusterIP, it would now return the pod IP.
3. **istiod** sends the new address to every ztunnel and waypoint, Istio's proxies. It uses xDS, Envoy's protocol for configuration updates. This doesn't matter for this plain namespace. In the shop, that update decides where the mesh sends traffic.

A pod that is running but not Ready stays out of the slice, so no new traffic reaches it. That is the whole point of a readiness probe. Without it, users would hit a pod that is still loading and get errors.

---

## Part 3: Scenario A: a request without a mesh

![Scenario A](diagrams/life-3-plain-request.svg)

The client pod runs `curl http://hello`. Follow the bytes. This scenario uses only plain Kubernetes, with no Istio, so you see what the base platform does on its own. The numbers in the diagram match these steps:

1. The client pod asks CoreDNS for the address of `hello`.
2. The client pod connects to the Service's ClusterIP, `10.43.76.137`.
3. The kernel rewrites the destination to the nginx pod, `10.42.0.197`. This rewrite is called DNAT.
4. On the reply, conntrack restores the ClusterIP as the source.

The kernel does all the work. kube-proxy only wrote the rules in advance. Section 3.1 covers step 1, sections 3.2 and 3.3 cover steps 2 and 3, and section 3.4 covers step 4.

### 3.1 DNS: from a short name to a ClusterIP

Before curl sends anything, it needs an IP address for the name `hello`. The pod asks the cluster's DNS server, and the pod's DNS settings decide how the short name grows into a full one.

```bash
kubectl -n course-life exec deploy/client -- cat /etc/resolv.conf
kubectl -n course-life exec deploy/client -- nslookup hello
```

```text
search course-life.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5

Server:		10.43.0.10
** server can't find hello.cluster.local: NXDOMAIN
Name:	hello.course-life.svc.cluster.local
Address: 10.43.76.137
```

1. The kubelet wrote this `resolv.conf` when it created the pod. `10.43.0.10` is the ClusterIP of CoreDNS's Service.
2. The `search` line lists endings to try after a short name, like an area code added to a local phone number.
3. `ndots:5` says that a name with fewer than five dots is probably short. For such a name, the resolver tries the search endings first. `hello` has no dots at all.
4. The resolver tries `hello.course-life.svc.cluster.local` and finds `10.43.76.137`. It also tries other endings, such as `hello.cluster.local`, and finds nothing. BusyBox's `nslookup` prints the result for each name it tried. That is why the NXDOMAIN ("no such name") line shows up.
5. The DNS query itself goes to a Service IP. So it takes the same kube-proxy path as the HTTP request below.

`ndots:5` makes short names work, but it costs extra queries for names outside the cluster. `api.github.com` has two dots, so the resolver tries three cluster endings before the real name. A trailing dot (`api.github.com.`) marks the name as complete and skips the search.

### 3.2 The Service: a rule, not a server

DNS gave curl the address `10.43.76.137`. That address belongs to the Service, but no machine owns it. Think of it as a forwarding address. The kernel on the node rewrites it to a real pod address as the packet passes.

```bash
kubectl -n course-life get svc hello
docker exec k3d-k8s-lab-server-0 sh -c "iptables-save -t nat | grep course-life/hello"
```

```text
NAME    TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
hello   ClusterIP   10.43.76.137   <none>        80/TCP    6s

-A KUBE-SERVICES -d 10.43.76.137/32 -p tcp -m comment --comment "course-life/hello:http cluster IP" -m tcp --dport 80 -j KUBE-SVC-KJCWZC573JCB7P23
-A KUBE-SVC-KJCWZC573JCB7P23 ! -s 10.42.0.0/16 -d 10.43.76.137/32 -p tcp ... --dport 80 -j KUBE-MARK-MASQ
-A KUBE-SVC-KJCWZC573JCB7P23 -m comment --comment "course-life/hello:http -> 10.42.0.197:80" -j KUBE-SEP-4PRSQEGJPQKGEHQE
-A KUBE-SEP-4PRSQEGJPQKGEHQE -s 10.42.0.197/32 ... -j KUBE-MARK-MASQ
-A KUBE-SEP-4PRSQEGJPQKGEHQE -p tcp ... -m tcp -j DNAT --to-destination 10.42.0.197:80
```

No process listens on `10.43.76.137`. No network interface has that address. The address exists only as a match in these rules. kube-proxy wrote the rules from the Service and its EndpointSlice. The rules are grouped into chains, and one chain jumps to the next. For the first packet of each new connection, the kernel walks them in this order:

1. `KUBE-SERVICES` matches destination `10.43.76.137` port 80. It jumps to the Service's own chain.
2. `KUBE-SVC-KJCW...` first looks for traffic from *outside* the pod network (`! -s 10.42.0.0/16`). It marks that traffic for masquerading, so replies come back through this node. Then it picks an endpoint, one of the pods behind the Service. With one pod, there is one jump. With three pods, kube-proxy adds a random choice with `-m statistic --mode random --probability 0.333`, then `0.5` before the last pod. This spreads connections evenly.
3. `KUBE-SEP-4PRS...` rewrites the destination to `10.42.0.197:80`. This rewrite is called **DNAT**, destination network address translation. The other line in this chain handles hairpin traffic, where a pod reaches itself through its own Service.

### 3.3 On the wire: a plain TCP conversation

A packet capture shows exactly what travels between the two pods, and anyone with access to the node sees the same. This capture ran on the `cni0` bridge, filtered on the client's IP, while the client ran `curl http://hello`:

```text
14:01:47.689690 IP 10.42.0.198.58270 > 10.42.0.197.80: Flags [S], seq 2924985601, win 64860, options [mss 1410,...]
14:01:47.689752 IP 10.42.0.197.80 > 10.42.0.198.58270: Flags [S.], seq 2637156200, ack 2924985602, ...
14:01:47.689758 IP 10.42.0.198.58270 > 10.42.0.197.80: Flags [.], ack 1, ...
14:01:47.689791 IP 10.42.0.198.58270 > 10.42.0.197.80: Flags [P.], seq 1:70, ack 1, ...
GET / HTTP/1.1
Host: hello
User-Agent: curl/8.11.1
Accept: */*
14:01:47.689865 IP 10.42.0.197.80 > 10.42.0.198.58270: Flags [P.], seq 1:239, ack 70, ...
HTTP/1.1 200 OK
Server: nginx/1.27.5
Content-Type: text/html
Content-Length: 615
```

Line by line:

1. **SYN** (`[S]`). The client opens a TCP connection from a random port, 58270. The destination is already the pod, `10.42.0.197`, not the Service IP. The DNAT happened when the packet entered the node from the client's veth, before the capture point. `mss 1410` is the largest payload per packet. It equals the MTU of 1450 minus 40 bytes of IP and TCP headers.
2. **SYN-ACK** (`[S.]`) comes from nginx, then the client's **ACK** (`[.]`). This three-way handshake took 68 microseconds.
3. **PSH** (`[P.]`) carries 69 bytes of payload. This is the HTTP request, **in plain text**. Anyone who captures on the node reads the method, the path and every header.
4. nginx answers with `HTTP/1.1 200 OK`, also in plain text.

The kubelet's readiness probes cross the same bridge with `User-Agent: kube-probe/1.31`. They come from `10.42.0.1`, the bridge's own address, because the kubelet runs on the node.

### 3.4 conntrack: how the reply finds its way back

The kernel changed the destination address on the way in. The reply must get the matching change on the way out, or the client would receive an answer from an address it never called. conntrack is the kernel's notebook of these rewrites. It records each connection once, and it undoes the rewrite for every reply.

```bash
docker exec k3d-k8s-lab-server-0 conntrack -L -d 10.43.76.137
```

```text
tcp 6 119 TIME_WAIT src=10.42.0.198 dst=10.43.76.137 sport=34704 dport=80 src=10.42.0.197 dst=10.42.0.198 sport=80 dport=34704 [ASSURED] mark=0 use=1
```

One entry holds both directions of one connection:

1. The original direction, as the client sent it: `10.42.0.198:34704 → 10.43.76.137:80`.
2. The reply direction, as the pod sends it: `10.42.0.197:80 → 10.42.0.198:34704`.

When nginx replies, the kernel finds this entry. It rewrites the source from `10.42.0.197` back to `10.43.76.137`. The client never learns the pod's IP. As far as curl knows, the Service answered.

Only the first packet walks the iptables chains. Every later packet of the connection follows the conntrack entry, which is much faster. `TIME_WAIT` and `119` mean the connection has closed, and the entry expires in 119 seconds.

nginx's log shows who it thinks called:

```text
10.42.0.198 - - [13/Nov/2026:13:11:40 +0000] "GET / HTTP/1.1" 200 615 "-" "curl/8.11.1" "-"
10.42.0.1 - - [13/Nov/2026:13:11:40 +0000] "GET / HTTP/1.1" 200 615 "-" "kube-probe/1.31" "-"
```

nginx sees the client pod's IP, and nothing more. It has no idea which workload or service account is behind `10.42.0.198`.

### 3.5 Layer 3 and 4 security: NetworkPolicy

So far, any pod reaches any other pod. Without a mesh, the only way to limit that is NetworkPolicy, a firewall rule written as a Kubernetes object. Something on the node must turn those objects into real firewall rules. k3s uses a built-in controller, kube-router, which writes more iptables rules. Here is a policy that blocks all incoming traffic in the namespace, a "default deny":

```bash
printf 'apiVersion: networking.k8s.io/v1\nkind: NetworkPolicy\nmetadata:\n  name: deny-all\n  namespace: course-life\nspec:\n  podSelector: {}\n  policyTypes: [Ingress]\n' | kubectl apply -f -
kubectl -n course-life exec deploy/client -- curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://hello
```

```text
000
command terminated with exit code 7
```

Curl's exit code 7 means "failed to connect". The DNAT still happened. Then kube-router's firewall chain for the pod rejected the SYN, the first packet. It sent back an ICMP "port unreachable" message. So the client got an instant refusal rather than a timeout. The rules carry the policy's name:

```text
-A KUBE-NWPLCY-4TPEQJGT6QVQPPS5 ... -j NFLOG --nflog-prefix "DROP by policy course-life/deny-all" --nflog-group 100
-A KUBE-POD-FW-... -m comment --comment "rule to REJECT traffic destined for POD ..." -j REJECT --reject-with icmp-port-unreachable
```

Delete the policy, and the next curl gets `200` again. NetworkPolicy works on IPs, ports and labels. It decides *whether* two pods may talk. It never sees an identity, a method or a path.

### 3.6 What scenario A lacks

| Missing | Consequence |
|---|---|
| Identity | nginx knows an IP. IPs get reused when pods restart. |
| Encryption | The capture in 3.3 shows the request in plain text. |
| Request-level policy | Nothing checks method, path or caller identity. |
| Request-level telemetry | The kernel counts packets. Nobody counts HTTP requests, status codes or latency. |

Scenario B adds all four without changing the app.

---

## Part 4: Scenario B: a request through the ambient mesh

![Scenario B](diagrams/life-4-ambient-request.svg)

This time the request starts on your Mac: `curl localhost:8080/api/orders`. The shop runs in Istio's ambient mesh, which adds identity, encryption and HTTP checks without changing the apps. The numbers in the diagram match these steps:

1. curl on your Mac reaches the node through Docker and the serverlb container.
2. kube-proxy's rules rewrite both addresses and send the request to the gateway pod.
3. The gateway opens an HBONE tunnel, an encrypted tunnel, to the frontend pod.
4. The frontend's ztunnel sends the frontend's call through a tunnel to the waypoint.
5. The waypoint checks the policy and opens a tunnel to a backend pod.
6. The backend's ztunnel opens a tunnel to Redis.
7. The response returns through the same tunnels.

In total, the request crosses four encrypted tunnels before it reaches Redis. Sections 4.1 and 4.2 cover steps 1 and 2. Sections 4.3 to 4.8 cover steps 3 to 6, and section 4.10 covers step 7.

### 4.1 From your Mac into the node

Your Mac isn't part of the cluster, so the request first has to get into the node container. Two forwarders carry it there.

```bash
docker port k3d-k8s-lab-serverlb
docker exec k3d-k8s-lab-serverlb grep -A3 "upstream 8080_tcp" /etc/nginx/nginx.conf
```

```text
8080/tcp -> 0.0.0.0:8080
8443/tcp -> 0.0.0.0:8443
6443/tcp -> 0.0.0.0:63077

  upstream 8080_tcp {
    server k3d-k8s-lab-server-0:8080 max_fails=1 fail_timeout=10s;
  }
```

1. Docker (OrbStack here) forwards your Mac's port 8080 to port 8080 of the `k3d-k8s-lab-serverlb` container.
2. That container runs nginx in **TCP stream mode**. In this mode, nginx doesn't read the HTTP. It only copies bytes to port 8080 of the node container. k3d adds this relay so that a cluster with several servers has one stable entry point. The API server's port 6443 reaches the node the same way.

### 4.2 One DNAT and one SNAT to the gateway pod

The packet has reached the node, addressed to the node's own IP. Now the node must hand it to the gateway pod. To do that, the kernel rewrites the destination, and also the source.

The gateway's Service has type LoadBalancer. This type asks for an address that outside clients reach. In a cloud, a cloud load balancer provides that address. On k3s, a built-in component, **ServiceLB**, does it instead. It does two things:

- It gives the Service the node's own IP as its external IP.
- It runs a small `svclb-...` pod that holds a port on the node, a host port.

```bash
kubectl -n shop-ingress get svc shop-gateway-istio
kubectl -n kube-system get pods -l svccontroller.k3s.cattle.io/svcname=shop-gateway-istio -o wide
```

```text
NAME                 TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)
shop-gateway-istio   LoadBalancer   10.43.62.182   192.168.107.2   15021:32050/TCP,8080:30297/TCP

NAME                                      READY   STATUS    IP           NODE
svclb-shop-gateway-istio-e733c05f-74kdg   2/2     Running   10.42.0.86   k3d-k8s-lab-server-0
```

This creates two competing paths for a packet to `192.168.107.2:8080`:

- The svclb path. The CNI's portmap plugin wrote a DNAT rule that sends the host port to the svclb pod. The svclb pod would then forward the packet on to the Service's ClusterIP. Its environment says `DEST_IPS=10.43.62.182`.
- The kube-proxy path. kube-proxy wrote its own rule for the load balancer IP.

The kernel checks rules in order, and the first match wins. So the order of the `PREROUTING` chain decides which path fires:

```bash
docker exec k3d-k8s-lab-server-0 iptables -t nat -S PREROUTING
```

```text
-A PREROUTING -m comment --comment "kubernetes service portals" -j KUBE-SERVICES
-A PREROUTING -d 192.168.107.1/32 -j DOCKER_OUTPUT
-A PREROUTING -m addrtype --dst-type LOCAL -j CNI-HOSTPORT-DNAT
```

kube-proxy's `KUBE-SERVICES` comes first, and its rule for the load balancer IP matches. That rule rewrites the destination to a pod address. The host port chain only looks at packets for a local address, so it never sees this packet. The packet counters confirm it:

```bash
docker exec k3d-k8s-lab-server-0 sh -c 'iptables -t nat -L -v -n | grep -E "shop-gateway-istio:http loadbalancer IP|DNAT .*dpt:8080 to:"'
```

```text
   33  1980 KUBE-EXT-EIP2LX4U67RPLA5V  6    --  *      *       0.0.0.0/0            192.168.107.2        /* shop-ingress/shop-gateway-istio:http loadbalancer IP */ tcp dpt:8080
    0     0 DNAT       6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:8080 to:10.42.0.86:8080
```

33 connections took kube-proxy's path, and none took the svclb path. The NAT table counts only the first packet of each connection, so these numbers are connections, not packets. Here is kube-proxy's chain:

```text
-A KUBE-SERVICES -d 192.168.107.2/32 -p tcp ... "shop-ingress/shop-gateway-istio:http loadbalancer IP" ... --dport 8080 -j KUBE-EXT-EIP2LX4U67RPLA5V
-A KUBE-EXT-EIP2LX4U67RPLA5V -m comment --comment "masquerade traffic for shop-ingress/shop-gateway-istio:http external destinations" -j KUBE-MARK-MASQ
-A KUBE-EXT-EIP2LX4U67RPLA5V -j KUBE-SVC-EIP2LX4U67RPLA5V
-A KUBE-SVC-EIP2LX4U67RPLA5V -m comment --comment "shop-ingress/shop-gateway-istio:http -> 10.42.0.88:8080" -j KUBE-SEP-XZ3I76FPEL7X3X6S
-A KUBE-SEP-XZ3I76FPEL7X3X6S -p tcp ... -j DNAT --to-destination 10.42.0.88:8080
```

1. `KUBE-EXT-...` handles traffic from outside the cluster. It sets a mark (`KUBE-MARK-MASQ`) on the packet. The mark is a note that says "change the source on the way out". Then the chain jumps to the usual Service chain.
2. `KUBE-SVC-...` then `KUBE-SEP-...` pick the gateway pod and rewrite the destination to `10.42.0.88:8080`. This is the **DNAT**.
3. After the kernel decides where to send the packet, `KUBE-POSTROUTING` sees the mark:

```text
-A KUBE-POSTROUTING -m mark ! --mark 0x4000/0x4000 -j RETURN
-A KUBE-POSTROUTING -j MARK --set-xmark 0x4000/0x0
-A KUBE-POSTROUTING -m comment --comment "kubernetes service traffic requiring SNAT" -j MASQUERADE --random-fully
```

The rule changes the source to the node's address on the pod network, `10.42.0.1`, with a random new port. This rewrite of the source is called **SNAT**. conntrack, the kernel's notebook of rewrites, shows both rewrites in one entry:

```bash
docker exec k3d-k8s-lab-server-0 conntrack -L -p tcp -d 192.168.107.2 --dport 8080
```

```text
tcp 6 110 TIME_WAIT src=192.168.107.3 dst=192.168.107.2 sport=47994 dport=8080 src=10.42.0.88 dst=10.42.0.1 sport=8080 dport=44558 [ASSURED] mark=0 use=1
```

Read the entry in two halves:

- Going in, the packet travels from the serverlb container `192.168.107.3` to the node's `192.168.107.2:8080`.
- Coming back, the reply travels from the gateway pod `10.42.0.88:8080` to `10.42.0.1:44558`.

Both addresses changed. The gateway pod sees a plain TCP connection from the node. It never learns the serverlb's address, let alone your Mac's.

The SNAT exists to keep the reply on the right path. Without it, the gateway pod would answer `192.168.107.3` directly. The serverlb would then get a reply from an address it never talked to, and it would drop it. With the SNAT, the reply goes to `10.42.0.1`, the node. There, conntrack turns it back into `192.168.107.2:8080 → 192.168.107.3:47994`.

Hiding the client is the price of this design. It comes from `externalTrafficPolicy: Cluster`, the default. The SNAT makes sure replies come back through the node that did the DNAT, and as a side effect, it hides the client. A Service with `externalTrafficPolicy: Local` skips the SNAT and keeps the client's address. In return, only nodes with a gateway pod accept the traffic.

### 4.3 The gateway: an Envoy that speaks HBONE

The gateway is the first component that reads the request as HTTP. It decides which app should get the request, and it opens an encrypted tunnel to that app.

```bash
GW=$(kubectl -n shop-ingress get pod -l gateway.networking.k8s.io/gateway-name=shop-gateway -o name)
istioctl proxy-config routes $GW -n shop-ingress
istioctl proxy-config endpoints $GW -n shop-ingress | grep frontend
kubectl get ns shop-ingress shop -L istio.io/dataplane-mode
```

```text
NAME          VHOST NAME     DOMAINS     MATCH                  VIRTUAL SERVICE
http.8080     *:8080         *           /*                     frontend-0-istio-autogenerated-k8s-gateway.shop

ENDPOINT                                     STATUS      OUTLIER CHECK     CLUSTER
envoy://connect_originate/10.42.0.13:3000    HEALTHY     OK                outbound|3000||frontend.shop.svc.cluster.local

NAME           STATUS   AGE   DATAPLANE-MODE
shop-ingress   Active   44m
shop           Active   44m   ambient
```

The gateway pod runs Envoy, a proxy program that reads and forwards HTTP. Read the output in three steps:

1. **Route.** The gateway's Envoy reads the HTTP request. This is the first hop that looks at HTTP, also called Layer 7. It matches the route `/*`. istiod built that route from the shop's HTTPRoute `frontend`.
2. **Endpoint.** The endpoint `envoy://connect_originate/10.42.0.13:3000` means "open an HBONE tunnel to the frontend pod". Envoy picks the pod itself from istiod's list of endpoints. So kube-proxy plays no part from here on.
3. **Namespace.** `shop-ingress` isn't an ambient namespace, and it doesn't need to be. The gateway is already a full proxy with its own certificate. It starts the encrypted tunnel itself.

**HBONE** is the tunnel format of ambient mode. It is an HTTP/2 `CONNECT` request inside mutual TLS, sent to port 15008. Mutual TLS (mTLS) is encryption where both ends show a certificate, so each side knows who the other is. Think of HBONE as a sealed pipe between two checked ID cards. One TLS connection carries many TCP streams inside it, which saves a new handshake for every connection.

### 4.4 Inside the frontend pod: ztunnel's sockets

The tunnel must end somewhere that decrypts it before the app sees the bytes. In ambient mode, that job belongs to ztunnel. ztunnel is a small proxy that handles encryption and identity for every pod on its node. It runs as a DaemonSet, one pod per node.

Yet the tunnel ends *inside the frontend pod*, not inside the ztunnel pod. Two things made that possible when the frontend pod started:

1. istio-cni, a network plugin, added redirect rules in the pod's network namespace.
2. ztunnel opened listening sockets inside that same namespace.

To see the rules, enter the pod's network namespace through the app's process ID:

```bash
CID=$(docker exec k3d-k8s-lab-server-0 crictl ps --name frontend -q | head -1)
PID=$(docker exec k3d-k8s-lab-server-0 crictl inspect --output go-template --template '{{.info.pid}}' $CID)
docker exec k3d-k8s-lab-server-0 nsenter -t $PID -n iptables-save | grep -E "REDIRECT|0x539"
```

```text
-A ISTIO_PRERT -m mark --mark 0x539/0xfff -j CONNMARK --set-xmark 0x111/0xfff
-A ISTIO_OUTPUT ! -o lo -p udp -m mark ! --mark 0x539/0xfff -m udp --dport 53 -j REDIRECT --to-ports 15053
-A ISTIO_OUTPUT ! -d 127.0.0.1/32 -p tcp -m tcp --dport 53 -m mark ! --mark 0x539/0xfff -j REDIRECT --to-ports 15053
-A ISTIO_OUTPUT ! -d 127.0.0.1/32 -p tcp -m mark ! --mark 0x539/0xfff -j REDIRECT --to-ports 15001
-A ISTIO_PRERT ! -d 127.0.0.1/32 -p tcp -m tcp ! --dport 15008 -m mark ! --mark 0x539/0xfff -j REDIRECT --to-ports 15006
```

A REDIRECT rule works like a receptionist who sends every visitor to one desk, whatever room they asked for. Here, each rule sends one kind of traffic to one of ztunnel's sockets:

| Rule | Effect |
|---|---|
| `ISTIO_OUTPUT ... REDIRECT --to-ports 15001` | every TCP connection the app opens goes to ztunnel's outbound socket |
| `ISTIO_PRERT ! --dport 15008 ... REDIRECT --to-ports 15006` | plain-text arrivals go to ztunnel's inbound socket. HBONE on 15008 passes straight through |
| `... --dport 53 ... REDIRECT --to-ports 15053` | DNS goes to ztunnel's DNS proxy |
| `mark 0x539` | ztunnel marks its own packets, and every rule skips them, so ztunnel's traffic never loops back into itself |

The pod's listening TCP ports, read from `/proc/<pid>/net/tcp`:

```text
[3000, 15001, 15006, 15008, 15053]
```

Port 3000 is the app. The other four belong to ztunnel, although they sit in the app's own network namespace. ztunnel also needs to know where every pod and Service is, and which ones use a waypoint. istiod, Istio's control plane, sends it that list. ztunnel's view of it:

```text
NAMESPACE  POD NAME                    ADDRESS      NODE                  WAYPOINT  PROTOCOL
shop       backend-v1-54c86bf9b-wrp75  10.42.0.58   k3d-k8s-lab-server-0  None      HBONE
shop       frontend-d8cfc88bd-wrvvn    10.42.0.13   k3d-k8s-lab-server-0  None      HBONE
shop       redis-7bbf49c9f8-bhpxx      10.42.0.14   k3d-k8s-lab-server-0  None      HBONE
shop       waypoint-b9b76876f-dgt7j    10.42.0.81   k3d-k8s-lab-server-0  None      TCP

NAMESPACE  SERVICE NAME  SERVICE VIP     WAYPOINT  ENDPOINTS
shop       backend       10.43.239.201   waypoint  3/3
shop       frontend      10.43.196.195   None      1/1
shop       redis         10.43.100.21    None      1/1
```

Two columns matter:

- `PROTOCOL` says how to reach each pod. Ambient workloads show `HBONE`. The waypoint shows `TCP`, because it is an Envoy that ends HBONE tunnels itself.
- `WAYPOINT`, in the Services table, decides the next step. Traffic for `backend` goes to the waypoint. Traffic for `redis` doesn't.

Now the whole arrival makes sense. The gateway's tunnel lands on `10.42.0.13:15008`. Then ztunnel does three things:

1. It checks the gateway's certificate and any Layer 4 policy, a rule about who may connect.
2. It unwraps the stream.
3. It connects to the app on port 3000, from inside the pod's network namespace.

So plain text exists only inside the pod.

### 4.5 The frontend calls the backend: four tunnels, four identities

The frontend app does nothing special. It simply opens `http://backend.shop.svc.cluster.local:8000`. The redirect rules from 4.4 quietly hand the call to ztunnel:

1. The DNS query goes to port 53. The redirect rule sends it to ztunnel's DNS proxy on 15053. ztunnel answers with the Service IP `10.43.239.201`.
2. The app opens a TCP connection to `10.43.239.201:8000`. The `REDIRECT --to-ports 15001` rule catches it. So the packet never reaches kube-proxy's rules on the node.
3. ztunnel looks up `10.43.239.201` and sees that the Service uses a waypoint. It opens an HBONE tunnel to the waypoint and passes along the original destination.

ztunnel writes one log line per connection, when the connection closes. Here are the lines for this request's path:

```text
"inbound"  shop-gateway-istio-858774d7c -> frontend-d8cfc88bd-wrvvn     hbone=10.42.0.13:3000
          from "spiffe://cluster.local/ns/shop-ingress/sa/shop-gateway-istio"
          to   "spiffe://cluster.local/ns/shop/sa/frontend"
"outbound" frontend-d8cfc88bd-wrvvn     -> waypoint-b9b76876f-dgt7j     hbone=10.43.239.201:8000
          from "spiffe://cluster.local/ns/shop/sa/frontend"
          to   "spiffe://cluster.local/ns/shop/sa/waypoint"
"inbound"  waypoint-b9b76876f-dgt7j     -> backend-v1-54c86bf9b-wrp75   hbone=10.42.0.58:8000
          from "spiffe://cluster.local/ns/shop/sa/waypoint"
          to   "spiffe://cluster.local/ns/shop/sa/backend"
"inbound"  backend-v2-5fd94d9cf4-6wffw  -> redis-7bbf49c9f8-bhpxx       hbone=10.42.0.14:6379
          from "spiffe://cluster.local/ns/shop/sa/backend"
          to   "spiffe://cluster.local/ns/shop/sa/redis"
```

| Hop | From | To | Who checks |
|---|---|---|---|
| 1 | `sa/shop-gateway-istio` | `sa/frontend` | ztunnel in the frontend pod |
| 2 | `sa/frontend` | `sa/waypoint` | the waypoint (and it records `sa/frontend` as the caller) |
| 3 | `sa/waypoint` | `sa/backend` | ztunnel in the backend pod |
| 4 | `sa/backend` | `sa/redis` | ztunnel in the redis pod |

Two hops deserve a closer look:

- Hop 2's `hbone` address is the backend *Service* IP, not a pod IP. The waypoint receives traffic meant for the Service and decides which pod gets it.
- Hop 4 goes from ztunnel to ztunnel, because `redis` has no waypoint. Only Layer 4 checks apply there.

The redis line names a backend-v2 pod from an earlier run of the shop. ztunnel logs a connection only when it closes. The backend keeps its Redis connection open for as long as it runs, so the most recent closed one is old. The identities are what matter, and those stay the same.

Each identity is an X.509 certificate, the standard format for TLS certificates. Here is the gateway's own certificate, read with openssl:

```bash
istioctl proxy-config secret $GW -n shop-ingress -o json   # extract the certificate chain, then:
openssl x509 -in gw.pem -noout -subject -issuer -dates -ext subjectAltName,extendedKeyUsage
```

```text
subject=
issuer=O=cluster.local
notBefore=Nov 13 12:35:03 2026 GMT
notAfter=Nov 14 12:37:03 2026 GMT
X509v3 Extended Key Usage:
    TLS Web Server Authentication, TLS Web Client Authentication
X509v3 Subject Alternative Name: critical
    URI:spiffe://cluster.local/ns/shop-ingress/sa/shop-gateway-istio
```

1. The **subject is empty**. The identity lives only in the SAN (Subject Alternative Name) field. It has the form of a SPIFFE URI, a standard name for a workload. The URI holds three parts: the trust domain `cluster.local`, the namespace and the service account. It says nothing about IPs or pod names, because those change.
2. It works for both **server and client authentication**. Every workload is a client on one hop and a server on the next, so it needs both.
3. It lives **24 hours**. Istio renews it automatically. So a stolen certificate stops working quickly.
4. istiod signs it with the mesh's root CA (certificate authority), the key everyone in the mesh trusts. ztunnel holds one short-lived "leaf" certificate per service account on its node, plus the 10-year root:

```text
CERTIFICATE NAME                            TYPE   STATUS      NOT AFTER              NOT BEFORE
spiffe://cluster.local/ns/shop/sa/frontend  Leaf   Available   2026-11-14T12:27:38Z   2026-11-13T12:25:38Z
spiffe://cluster.local/ns/shop/sa/frontend  Root   Available   2036-11-10T12:26:51Z   2026-11-13T12:26:51Z
```

### 4.6 The waypoint: Layer 7 decisions

ztunnel sees only connections and identities. It doesn't read HTTP, so `GET /api/orders` and `DELETE /api/orders` look the same to it. Rules about methods and paths need a proxy that reads HTTP. In ambient mode, that proxy is the waypoint.

The waypoint is an Envoy that serves the `backend` Services. For each request, it does four things:

1. It ends hop 2's tunnel.
2. It reads the HTTP request.
3. It decides whether to allow it and where to send it.
4. It opens hop 3 to the chosen pod.

With access logging on, one request looks like this:

```text
[2026-11-13T14:02:22.311Z] "GET /api/orders HTTP/1.1" 200 - via_upstream - "-" 0 392 5 5 "-" "node" "3a34a7c0-49a0-9be9-9293-9409ac9baeb2" "backend.shop.svc.cluster.local:8000" "envoy://connect_origin...
```

Read the fields from left to right:

| Field | Meaning |
|---|---|
| `"GET /api/orders HTTP/1.1"` | method, path and protocol |
| `200` | status |
| `via_upstream` | the backend answered, not Envoy |
| `0 392` | 0 bytes in, 392 bytes out |
| `5 5` | 5 ms in total and 5 ms upstream |
| `"node"` | the user agent, the frontend's runtime |
| `"3a34a7c0-..."` | a request ID that every hop passes on |
| `"backend.shop.svc.cluster.local:8000"` | the authority, the host the caller asked for |
| `"envoy://connect_origin..."` | the upstream, an HBONE connection to the chosen pod |

Before routing, the waypoint checks this policy:

```yaml
spec:
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/shop/sa/frontend
    to:
    - operation:
        methods: [GET, POST]
        paths: [/api/*]
  targetRefs:
  - {kind: Service, name: backend}
  - {kind: Service, name: backend-v1}
  - {kind: Service, name: backend-v2}
```

In other words, only the frontend may call, only with `GET` or `POST`, and only on paths under `/api/`. The waypoint knows the caller's identity from hop 2's certificate. It knows the method and path because it read the HTTP. Test three requests from inside the frontend pod:

```text
GET /api/orders 200
GET /admin 403 RBAC: access denied
DELETE /api/orders 403 RBAC: access denied
```

All three requests have the same caller, the same Service and the same TCP port. Only Layer 7 tells them apart. The waypoint writes the 403 itself, so the backend never sees the refused requests.

For an allowed request, the waypoint continues in this order:

1. The HTTPRoute `backend-route` chooses between `backend-v1` and `backend-v2`.
2. The waypoint applies the route's timeouts and retries.
3. It records metrics and a trace span.
4. It picks a pod.

The response headers back at your Mac carry the proxies' marks:

```text
HTTP/1.1 200 OK
x-app-version: v1
x-served-by: backend-v1-54c86bf9b-wrp75
x-envoy-upstream-service-time: 6
server: istio-envoy
```

`server: istio-envoy` comes from the gateway, which rewrites the header. `x-envoy-upstream-service-time: 6` is the gateway's view of how long everything behind it took.

### 4.7 Layer 4 decisions: ztunnel at the backend

The waypoint is one guard. To stop callers that try to skip it, the backend pod's ztunnel checks every arrival as well. It enforces two policies of its own:

- The namespace's `PeerAuthentication`, in mode `STRICT`. STRICT means "accept only mTLS connections, never plain text".
- An AuthorizationPolicy with a `selector`. A policy that picks pods by label like this runs in ztunnel, not in the waypoint.

```text
NS     KIND                  NAME                         ACTION   SEL                MODE
shop   AuthorizationPolicy   backend-only-from-waypoint   ALLOW    map[app:backend]
shop   AuthorizationPolicy   redis-allow-backend          ALLOW    map[app:redis]
shop   PeerAuthentication    default                                                  STRICT
```

`backend-only-from-waypoint` allows `sa/waypoint` and Prometheus's service account. It names the waypoint, not the frontend, because hop 3 arrives with the waypoint's certificate. Try to skip the waypoint from a pod outside the mesh, and STRICT mode stops you first:

```bash
kubectl -n course-life exec deploy/client -- curl -s -m 5 -o /dev/null -w "%{http_code}\n" http://backend.shop.svc.cluster.local:8000/api/orders
```

```text
000
command terminated with exit code 56
```

Exit code 56 means "failure receiving data". Here is what happened:

1. The TCP connection opened. kube-proxy had rewritten its destination to a backend pod.
2. ztunnel in that pod saw plain text with no certificate.
3. ztunnel reset the connection.

Compare this with 3.5. NetworkPolicy refuses the very first packet, the SYN. The mesh accepts the TCP connection and then refuses the stream, because it carries no identity.

### 4.8 On the wire: what an eavesdropper sees

The point of the tunnels is that someone who captures packets learns nothing. To check, this capture ran on the `cni0` bridge for every packet to or from the three backend pods, while five requests ran through the shop:

```text
packets: 410
destination ports of packets sent TO a backend:
     41 15008
     93 8000
     ...    (ephemeral ports: replies to connections the backend opened)
plaintext 'GET /api' lines: 0
plaintext 'orders' lines: 0
```

1. Requests reach the backends on **port 15008**, the HBONE port, never on 8000 directly. The payload is encrypted with TLS. The strings `GET /api` and `orders` appear **zero** times in 410 packets. Compare 3.3, where the whole request was readable.
2. The 93 packets to port 8000 all come from **`169.254.7.127`**. They read `GET /readyz` and `GET /healthz`, with `User-Agent: kube-probe/1.31`. These are the kubelet's probes. The kubelet has no mesh certificate, so STRICT mode would block its probes. To keep health checks working, istio-cni rewrites probe traffic to come from this special link-local address. ztunnel lets packets from that address through in plain text.

### 4.9 Timing the whole trip

Jaeger is a tracing tool. It shows how long each hop of one request took, as a set of timed blocks called spans. Here is one `POST /api/orders`, as Jaeger recorded it:

```text
     18.5 ms  shop-gateway-istio.shop-ingress     frontend.shop.svc.cluster.local:3000/*
      7.4 ms  waypoint.shop                       backend-v1.shop.svc.cluster.local:8000/*
      5.5 ms  backend                             POST /api/orders
      0.5 ms  backend                             INCRBY
      0.3 ms  backend                             HSET LPUSH LTRIM
```

1. The gateway's span covers everything behind it, 18.5 ms.
2. The waypoint's span covers the backend plus one hop, 7.4 ms. The backend app used 5.5 ms of that. So the hop through the waypoint and two ztunnels costs about 2 ms.
3. The frontend doesn't trace itself, so its share hides in the gap, about 11 ms of the 18.5.
4. Redis answers in under a millisecond per command.

Each proxy passes on a header called `traceparent`, which carries the trace's ID. The backend's OpenTelemetry library reads it and continues the same trace. That is how the spans join into one trace.

### 4.10 The way back

The response retraces every hop in reverse. Each HBONE tunnel is a two-way stream, so the reply travels back through the same four tunnels and the same identities. After the gateway, the outer part runs in this order:

1. conntrack undoes the SNAT and the DNAT from 4.2.
2. The serverlb nginx copies the bytes out.
3. Docker forwards them to your Mac.
4. curl prints the JSON.

Nothing decides anything on the way back. Every check, from TLS handshakes to the waypoint's policy, happened when the connection or the request went in.

---

## Part 5: Security, layer by layer

A request meets several checks, and each one looks at something different. The table lists them from the API server down to the app. The "Seen in" column points to the section where you saw each check refuse something.

| Layer | Where | What it checks | Scenario A | Scenario B | Seen in |
|---|---|---|---|---|---|
| API | API server, gate 1 | who you are: certificate or token | yes | yes | 1.2: 401 |
| API | API server, gate 2 | what you may do: Node authorizer, RBAC | yes | yes | 1.2, 1.3: 403 |
| API | API server, gates 3 to 5 | whether the object is allowed: schema, webhooks | yes | yes | 1.4: two refusals |
| L2 | cni0 bridge | nothing: any pod on the bridge reaches any other | open | open | 2.4 |
| L3/L4 | kube-router, node iptables | NetworkPolicy: IPs, ports, labels | if defined | if defined | 3.5: exit 7 |
| L4 | ztunnel in each pod | mTLS identity, STRICT mode, selector policies | none | every hop | 4.7: exit 56 |
| L4 | the wire | encryption | plain text | TLS on 15008 | 3.3 against 4.8 |
| L7 | waypoint | caller identity, method, path | none | Services with a waypoint | 4.6: 403 |
| L7 | the app | its own logins and checks | yes | yes | |

Two rules of thumb follow from this table:

1. The API server protects the cluster's *configuration*. The mesh and NetworkPolicy protect its *traffic*. The two never overlap.
2. A Layer 7 rule needs a component that reads HTTP. In ambient mode, that component is the waypoint. ztunnel sees only TCP and identities.

---

## Part 6: What breaks when a component is down

The components in this document do two different jobs:

1. The control plane from Part 1 builds configuration: rules, routes and certificates.
2. The data path from Parts 3 and 4 carries traffic, using configuration that is already in place.

So when a control-plane component goes down, the cluster stops changing, but running traffic keeps flowing. Think of a road crew on strike. The roads still work, but nobody paints new lanes.

| Down | Running traffic | What stops |
|---|---|---|
| API server | keeps flowing: iptables, conntrack, ztunnel and the waypoint keep their last configuration | kubectl, new pods, scaling, new endpoints, every controller |
| kine / SQLite | keeps flowing | the API server serves no writes and soon no reads |
| Scheduler | keeps flowing | new pods stay `Pending` |
| Controller manager | keeps flowing | Deployments don't roll, dead pods don't get replaced, endpoints don't update |
| kubelet | containers keep running | probes stop, so the node turns `NotReady`. Crashed containers don't restart |
| CoreDNS | open connections keep flowing | new lookups fail, so new connections to Service names fail |
| kube-proxy | existing rules keep working | Service changes don't reach iptables |
| istiod | keeps flowing with the last xDS | no new configuration. Certificates stop renewing, so mesh traffic fails once they expire (24 hours) |
| ztunnel on a node | mesh traffic for that node's pods fails | |
| waypoint | traffic to the `backend` Services fails | |

The last two rows are different. ztunnel and the waypoint sit in the request path, so when they stop, traffic stops. They need the same care as the apps. That is why the waypoint is a Deployment you scale, and why ztunnel upgrades need a plan ([module 14](../platform-engineering/14-upgrading-istio.md)).

---

## Editing the diagrams

`docs/diagrams/make-life-of-a-request.py` draws the four diagrams above and the one-page overview at the top of module 29, using the small drawing kit in `docs/diagrams/bbg.py`. Each diagram becomes an SVG for GitHub and an Excalidraw file you may open at [excalidraw.com](https://excalidraw.com). To change a diagram, edit the script and run it again: `python3 docs/diagrams/make-life-of-a-request.py`.
