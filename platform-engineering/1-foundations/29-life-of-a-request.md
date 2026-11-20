# Module 29: the life of a request

> New to a term here, like admission webhook, conntrack or HBONE? The [glossary](../glossary.md) explains every term in this course.

**Before this module:** module 0. Parts 1 and 2 need no Istio. Part 3 builds on modules 1 and 2 (ambient mode, ztunnel, mTLS identity) and refers to module 3's policies.

**You need:** the lab running (`./scripts/start.sh` starts or repairs it) and `istioctl`. `./scripts/port-forward.sh` running in a spare terminal lets you follow part 3 in Jaeger.

You type `curl localhost:8080/api/orders` and get JSON back about 20 milliseconds later, and a lot happens in those 20 milliseconds. Before the request even starts, a pod had to come to life, and then the request crosses the network, the mesh and the apps.

This module follows all of it on your lab, with a command for every hop, in three parts:

1. Part 1 brings a pod to life, from `kubectl apply` to a pod that answers.
2. Part 2 sends a request in plain Kubernetes, with no mesh.
3. Part 3 sends a request through the shop's ambient mesh.

Compare parts 2 and 3, and you see exactly what a mesh adds.

Time: about 75 minutes. Adds almost nothing: one small nginx and a client.

![The life of a request](../../docs/diagrams/life-of-a-request.svg)

[Module 45](../3-advanced/45-life-of-an-outbound-request.md) follows the opposite direction, a call from a pod out to the internet, through every NAT step on the way.

For the long read, [docs/life-of-a-request.md](../../docs/life-of-a-request.md) walks the same path in more depth, with four detailed diagrams, packet captures, the Layer 2 and 3 plumbing, and the real output of every command, while this module is the hands-on version.

The diagram also exists in [Excalidraw format](../../docs/diagrams/life-of-a-request.excalidraw), which you open at [excalidraw.com](https://excalidraw.com) to zoom, move and annotate, and `docs/diagrams/make-life-of-a-request.py` generates both files.

**Your values will differ.** The IPs and pod names in this module come from one test run, and Kubernetes gives pods and Services new addresses whenever it creates them, so yours change with every rebuild, restart or rollout. The commands look values up instead of hard-coding them, so they work on any run. To line up your numbers with the ones quoted here, run `./platform-engineering/my-values.sh` after step 1, which prints each address under the same name the text uses.

## Part 1: a pod comes to life

You run `kubectl apply`, and about a second later a pod answers requests, after work in two stages.

First, the API server accepts and stores the request:

1. kubectl sends the request to the API server over HTTPS.
2. Authentication: the API server checks who you are.
3. Authorization: the API server checks what you may do, first with the Node authorizer and then with RBAC.
4. Admission: webhooks and built-in plugins may change the object or refuse it.
5. Storage: kine writes the object to SQLite. Other clusters use etcd here.
6. Watch: every interested component hears about the change.

A refusal at step 2, 3 or 4 goes straight back to kubectl as 401, 403, or 400/422.

Second, the cluster turns the stored Deployment into a running pod:

1. The Deployment controller creates a ReplicaSet.
2. The ReplicaSet controller creates a Pod.
3. The scheduler picks a node.
4. The kubelet asks containerd for a sandbox.
5. The CNI plugins give the pod an IP address. flannel does this everywhere, and istio-cni adds its rules in ambient namespaces.
6. The containers start, and the readiness probe passes.
7. The EndpointSlice controller adds the pod's IP to its Service. Then kube-proxy, CoreDNS and istiod update.

The long read draws each stage as its own diagram, with these step numbers.

### Concept: one object, many independent workers

![One object, many workers: each component watches the API server and writes its result back](../../docs/diagrams/chapters/29-many-workers.svg)

Nobody gives orders in Kubernetes, because each component looks after one kind of object, like an office where nobody talks and everybody reads and writes the same notice board.

Every component **watches** the API server for the objects it cares about, through an open connection that streams every change to those objects, and repeats three steps again and again:

1. It compares what exists with what should exist.
2. It acts to close the gap.
3. It writes the result back to the API server.

This cycle is the **reconcile loop**, so the Deployment controller never talks to the scheduler: it writes a ReplicaSet, and the next worker notices.

This design is why Kubernetes heals itself. Delete a pod, and the ReplicaSet controller sees one pod too few and creates another, without anyone asking.

### Concept: inside the API server

The API server is the cluster's front door, and to keep bad or unauthorised changes out, every request passes the same gates, in this order, before it stores anything:

| Gate | Question | In this lab |
|---|---|---|
| Authentication | Who are you? | client certificates signed by the cluster's client CA. Service accounts use signed tokens. `--anonymous-auth=false` |
| Authorization | May you do this? | `--authorization-mode=Node,RBAC`: the Node authorizer for kubelets, then RBAC |
| Mutating admission | Should the object change? | built-in plugins, then webhooks: Istio's sidecar injector, Kyverno (module 26) |
| Validation | Is the object well-formed? | the API schema, built-in rules |
| Validating admission | Is it allowed? | `NodeRestriction`, ValidatingAdmissionPolicy, webhooks such as Istio's config validation |
| Storage | Write it, give it a `resourceVersion` | `--etcd-servers=unix://kine.sock`: k3s' kine translates etcd calls to SQLite |

A few words in the table need a definition:

- Admission is the stage that may change or refuse an object after the caller is known and allowed.
- A webhook is a call from the API server to another program, such as Istio, that adds its own checks.
- kine is a small translator in k3s that lets the API server store data in a SQLite file instead of etcd, the usual Kubernetes database.

A refusal at any gate goes straight back to the client, so the API server stores nothing and no controller ever hears of it.

### 1. See what kubectl sends, and who you are

```console
$ kubectl apply -f platform-engineering/manifests/29-plain-app.yaml -v=6 2>&1 | grep -oE 'verb="[A-Z]+" url="[^"]*" status="[^"]*"' | grep -v openapi | head -6
verb="GET" url="https://0.0.0.0:63077/api/v1/namespaces/course-life" status="404 Not Found"
verb="POST" url="https://0.0.0.0:63077/api/v1/namespaces?fieldManager=kubectl-client-side-apply&fieldValidation=Strict" status="201 Created"
verb="GET" url="https://0.0.0.0:63077/apis/apps/v1/namespaces/course-life/deployments/hello" status="404 Not Found"
verb="GET" url="https://0.0.0.0:63077/api/v1/namespaces/course-life" status="200 OK"
verb="POST" url="https://0.0.0.0:63077/apis/apps/v1/namespaces/course-life/deployments?fieldManager=kubectl-client-side-apply&fieldValidation=Strict" status="201 Created"
verb="GET" url="https://0.0.0.0:63077/api/v1/namespaces/course-life/services/hello" status="404 Not Found"

$ kubectl auth whoami
ATTRIBUTE   VALUE
Username    system:admin
Groups      [system:masters system:authenticated]

$ kubectl auth can-i create deployments -n course-life
yes

$ kubectl auth can-i create deployments -n course-life --as=system:serviceaccount:shop:frontend
no
```

**What you should see.** The output answers three questions.

**What does kubectl send?** REST calls such as `verb="POST" url=".../apis/apps/v1/namespaces/course-life/deployments..."`, so `kubectl apply` is an ordinary HTTP client. The URL works like a postal address, naming the API group (`apps`), the version (`v1`), the namespace and the kind of resource.

**Who are you?** `whoami` says `system:admin`, in the groups `system:masters` and `system:authenticated`.

**What may you do?** You get `yes`, while the frontend's service account gets `no`, because the shop's apps need no access to the Kubernetes API. Members of `system:masters` skip RBAC, the role-based permission check, entirely, which is why that group belongs only in emergency "break-glass" credentials.

### 2. Watch the controllers hand the work along

```console
$ kubectl -n course-life get events --sort-by=.firstTimestamp \
  -o custom-columns=WHO:.source.component,KIND:.involvedObject.kind,REASON:.reason,MESSAGE:.message | grep -v client
WHO                     KIND         REASON              MESSAGE
<none>                  Pod          Scheduled           Successfully assigned course-life/hello-76fb6c6b6f-dqlh9 to k3d-k8s-lab-server-0
replicaset-controller   ReplicaSet   SuccessfulCreate    Created pod: hello-76fb6c6b6f-dqlh9
deployment-controller   Deployment   ScalingReplicaSet   Scaled up replica set hello-76fb6c6b6f to 1
kubelet                 Pod          Pulled              Container image "curlimages/curl:8.11.1" already present on machine
kubelet                 Pod          Created             Created container curl
kubelet                 Pod          Started             Started container curl
kubelet                 Pod          Pulled              Container image "nginx:1.27-alpine" already present on machine
kubelet                 Pod          Created             Created container web
kubelet                 Pod          Started             Started container web

$ P=$(kubectl -n course-life get pod -l app=hello -o jsonpath='{.items[0].metadata.name}')
$ kubectl -n course-life get pod $P -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ReplicaSet/hello-76fb6c6b6f

$ kubectl -n course-life get pod $P -o jsonpath='{range .status.conditions[*]}{.type}={.lastTransitionTime}{"\n"}{end}'
PodReadyToStartContainers=2026-11-14T22:54:00Z
Initialized=2026-11-14T22:53:59Z
Ready=2026-11-14T22:54:00Z
ContainersReady=2026-11-14T22:54:00Z
PodScheduled=2026-11-14T22:53:59Z
```

**What you should see.** Each controller does one small job and hands over to the next by writing an object, and in the test run all of it took under two seconds:

| Who | Event |
|---|---|
| deployment-controller | `ScalingReplicaSet`: Scaled up replica set hello-76fb6c6b6f to 1 |
| replicaset-controller | `SuccessfulCreate`: Created pod hello-76fb6c6b6f-dqlh9 |
| default-scheduler | `Scheduled`: assigned to k3d-k8s-lab-server-0 |
| kubelet | `Pulled` (already present on machine), `Created`, `Started` |

The scheduler's row shows `<none>` in the WHO column, because the scheduler writes its name into the event's `reportingComponent` field rather than `source.component`.

Each object records who created it: the pod's owner is `ReplicaSet/hello-76fb6c6b6f`, and that ReplicaSet's owner is `Deployment/hello`. A background cleaner, the garbage collector, follows these owner references, so `kubectl delete deployment` removes everything below the Deployment too.

The pod's conditions run from `PodScheduled` to `Ready` in about a second, because the node already had the image.

### 3. See what a controller sees

Controllers don't ask the API server "anything new?" every second, because they open a watch and wait for changes, and you open the same kind of watch here.

```console
$ kubectl get --raw "/api/v1/namespaces/course-life/pods?watch=1&timeoutSeconds=3&labelSelector=app%3Dhello"
{"type":"ADDED","object":{"kind":"Pod","apiVersion":"v1","metadata":{"name":"hello-76fb6c6b6f-dqlh9","generateName":"hello-76fb6c6b6f-","namespace":"course-life","uid":"105ada5b-5707-4b5f-86ba-6a4ae90615e5","resourceVersion":"148280","creationTimestamp":"2026-11-14T22:53:59Z",
...
```

**What you should see.** One JSON line, starting with `{"type":"ADDED","object":{"kind":"Pod"...`, with a `resourceVersion`, 148280 in this run, which is a counter that grows with every write in the cluster.

Controllers hold a watch like this open all the time, so when something changes, `MODIFIED` or `DELETED` lines arrive. If the connection drops, the watcher reconnects with its last `resourceVersion`, and the API server sends only what it missed, like a bookmark in a news feed.

### 4. Make the scheduler say no

The scheduler's job is to find a node with room for each new pod, so to see how it decides, you give it two pods that fit nowhere: one asks for far too much memory, and one asks for a node label that doesn't exist.

```console
$ kubectl -n course-life run greedy --image=nginx:1.27-alpine \
  --overrides='{"spec":{"containers":[{"name":"greedy","image":"nginx:1.27-alpine","resources":{"requests":{"memory":"64Gi"}}}]}}'
pod/greedy created

$ kubectl -n course-life run picky --image=nginx:1.27-alpine --overrides='{"spec":{"nodeSelector":{"disktype":"ssd"}}}'
pod/picky created

$ sleep 5; kubectl -n course-life get events --field-selector reason=FailedScheduling -o jsonpath='{range .items[*]}{.message}{"\n"}{end}'
0/1 nodes are available: 1 Insufficient memory. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.
0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.

$ kubectl describe node k3d-k8s-lab-server-0 | grep -A6 "Allocated resources"
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests      Limits
  --------           --------      ------
  cpu                1560m (10%)   15350m (102%)
  memory             3284Mi (27%)  10506Mi (87%)
  ephemeral-storage  0 (0%)        0 (0%)

$ kubectl -n course-life delete pod greedy picky
pod "greedy" deleted
pod "picky" deleted
```

**What you should see.** Two refusals:

- `0/1 nodes are available: 1 Insufficient memory. preemption: 0/1 nodes are available: 1 No preemption victims found for incoming pod.`
- `didn't match Pod's node affinity/selector`

Each message reports how many nodes the scheduler examined and why each one failed, because the scheduler works in phases:

1. **Filter.** The scheduler removes nodes where the pod doesn't fit. A node fails if it lacks free requested CPU or memory, has the wrong labels, has a taint (a "keep out" mark) or has a needed port in use.
2. **Score.** The scheduler ranks the remaining nodes. It prefers to spread replicas, to use nodes that already have the image, and to balance load.
3. **Bind.** The scheduler writes the winning node into `spec.nodeName`.

If no node survives the filter, the scheduler tries **preemption**, which means evicting lower-priority pods to make room, but here it found nothing to evict, so both pods stay `Pending`.

Now look at the node's allocations. A pod states two amounts: its *request* is what it reserves, and its *limit* is the most it may use. In the test run memory requests added up to 30% and limits to **106%**, and since the scheduler counts only requests, the limits promise more memory than the node has, which engineers call overcommitting. If every pod used its full limit at once, the node would run out, and the kernel's OOM ("out of memory") killer would pick processes to kill.

### 5. Make admission say no

Admission is the API server's last check before storage, so here you send two broken objects and watch two different checkers refuse them.

```console
$ kubectl -n course-life create deployment bad --image=nginx:1.27-alpine --replicas=-1 --dry-run=client -o yaml | kubectl apply -f -
The Deployment "bad" is invalid: spec.replicas: Invalid value: -1: must be greater than or equal to 0

$ printf 'apiVersion: security.istio.io/v1\nkind: AuthorizationPolicy\nmetadata:\n  name: broken\n  namespace: course-life\nspec:\n  rules:\n  - when:\n    - key: request.colour\n      values: ["blue"]\n' | kubectl apply -f -
Error from server: error when creating "STDIN": admission webhook "validation.istio.io" denied the request: configuration is invalid: 2 errors occurred:
	* invalid policy broken.course-life: invalid `value` for `key` request.colour: unknown attribute: request.colour
	* invalid policy broken.course-life: invalid `notValue` for `key` request.colour: unknown attribute: request.colour
```

**What you should see.** Two refusals, from two checkers:

1. `spec.replicas: Invalid value: -1: must be greater than or equal to 0` comes from the API server's own validation, because a Deployment with fewer than zero replicas makes no sense.
2. `invalid policy broken.course-life: ... unknown attribute: request.colour` comes from Istio's validating webhook, because the API server asked istiod to check the policy, and istiod found an attribute it doesn't know.

Neither object exists afterwards. Every write in the cluster passes through admission, which is why tools like Istio and Kyverno plug in there.

### 6. The kubelet's side: sandbox, network, probes

Once the scheduler has picked a node, the kubelet, the agent on that node, must turn the Pod object into a running container with a network address. Think of the pod as a new room in a building that needs walls, a network cable and a tenant, with the building directory listing it. On the node, in order:

1. The kubelet asks the container runtime, containerd, to create a **sandbox** for the pod, a tiny `pause` container whose only job is to hold the pod's network namespace, the pod's private copy of the network stack and so the room's walls.
2. containerd runs the network plugins, called the Container Network Interface (**CNI**) chain. The first one, flannel, picks a free IP address from this node's range, gives it to the pod, and connects the pod to the node's `cni0` bridge, a virtual switch, with a veth pair, a virtual cable with one end in the pod and the other on the node.
3. If the namespace uses ambient mode, a second plugin, istio-cni, adds iptables rules inside the pod, which Part 3 explains.
4. The kubelet pulls the image, starts the container and runs the readiness probe, a regular "are you ready?" check.
5. When the probe passes, the pod turns Ready, and the **EndpointSlice controller** adds the pod's IP to the list of addresses behind the Service, which is the building directory.

Three components read that list, each for its own reason:

- kube-proxy, which runs on every node, writes iptables rules so traffic for the Service IP reaches the pod, as Part 2 walks through.
- CoreDNS, the cluster's DNS server, answers name lookups for the Service.
- istiod, Istio's control plane, tells ztunnel and the waypoints, Istio's proxies, about the new address.

```console
$ docker exec k3d-k8s-lab-server-0 crictl pods --namespace course-life
POD ID              CREATED             STATE               NAME                      NAMESPACE           ATTEMPT             RUNTIME
02bfa6f80973d       56 seconds ago      Ready               client-7695f5987b-q9gk6   course-life         0                   (default)
68644c8d13d7b       56 seconds ago      Ready               hello-76fb6c6b6f-dqlh9    course-life         0                   (default)

$ docker exec k3d-k8s-lab-server-0 ip route
default via 192.168.107.1 dev eth0
10.42.0.0/24 dev cni0 proto kernel scope link src 10.42.0.1
192.168.107.0/24 dev eth0 proto kernel scope link src 192.168.107.2

$ kubectl -n course-life get endpointslice -l kubernetes.io/service-name=hello -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]} ready={.conditions.ready}{"\n"}{end}'
10.42.0.176 ready=true
```

**What you should see.** Each command shows one part of the list above:

1. `crictl pods` lists the pod's sandbox.
2. `ip route` shows the node's routes, where `10.42.0.0/24 dev cni0` covers the pods on this node through the bridge and a default route sends everything else out of `eth0`. With more nodes, flannel adds a route per node through its VXLAN interface, a tunnel that carries pod traffic between nodes.
3. The EndpointSlice lists `10.42.0.176 ready=true`. Your IP differs.

## Part 2: scenario A, a request without a mesh

The client pod sends `curl http://hello`, and a few milliseconds later nginx answers, after four things happen in between:

1. The client asks DNS for the address of `hello`.
2. The client opens a TCP connection to that address.
3. The node's kernel changes the destination to a real nginx pod.
4. On the way back, the kernel changes the address back again.

No proxy and no extra software takes part, because everything happens in the Linux kernel of the node, using rules that Kubernetes wrote earlier.

### Concept: a Service is a forwarding address

A Service gives your pods one stable address, the **ClusterIP**, because pod IPs change every time a pod restarts.

No machine owns the ClusterIP, though: no process listens on it, and no network card has it. It works like a forwarding address at the post office, where mail never arrives at that address, because the post office reads it and sends the letter on to where the person really lives.

Two pieces of the node do that forwarding:

- kube-proxy: writes the forwarding rules
- the kernel: follows them, packet by packet

**kube-proxy** is a small program on every node that watches the API server for Services and their pods, and for each Service it writes iptables rules that say "a connection to this ClusterIP goes to one of these pod IPs". **iptables** is the kernel's built-in packet filter, a list of rules the kernel checks for every packet, and when the kernel follows such a rule, it rewrites the packet's destination address, a step engineers call **DNAT** (destination network address translation).

The reply then needs care, because it comes back from the pod's real IP while the client sent its request to the ClusterIP, so a reply that showed the pod's IP would look like a stranger to the client. The kernel therefore keeps **conntrack**, its notebook of connections, where it writes down every rewrite it made, so it knows how to undo the change on the reply. kube-proxy writes the forwarding rules once, and the kernel applies them and remembers them for every connection.

### 7. Follow one request

```console
$ kubectl -n course-life exec deploy/client -- cat /etc/resolv.conf
search course-life.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5

$ kubectl -n course-life exec deploy/client -- curl -sv -o /dev/null http://hello 2>&1 | grep -E "Trying|Connected|< HTTP"
*   Trying 10.43.36.121:80...
* Connected to hello (10.43.36.121) port 80
< HTTP/1.1 200 OK

$ SVCIP=$(kubectl -n course-life get svc hello -o jsonpath='{.spec.clusterIP}')
$ docker exec k3d-k8s-lab-server-0 sh -c "iptables-save -t nat | grep course-life/hello"
-A KUBE-SEP-YAZKFCYBLKU7OJFH -s 10.42.0.176/32 -m comment --comment "course-life/hello:http" -j KUBE-MARK-MASQ
-A KUBE-SEP-YAZKFCYBLKU7OJFH -p tcp -m comment --comment "course-life/hello:http" -m tcp -j DNAT --to-destination 10.42.0.176:80
-A KUBE-SERVICES -d 10.43.36.121/32 -p tcp -m comment --comment "course-life/hello:http cluster IP" -m tcp --dport 80 -j KUBE-SVC-KJCWZC573JCB7P23
-A KUBE-SVC-KJCWZC573JCB7P23 ! -s 10.42.0.0/16 -d 10.43.36.121/32 -p tcp -m comment --comment "course-life/hello:http cluster IP" -m tcp --dport 80 -j KUBE-MARK-MASQ
-A KUBE-SVC-KJCWZC573JCB7P23 -m comment --comment "course-life/hello:http -> 10.42.0.176:80" -j KUBE-SEP-YAZKFCYBLKU7OJFH

$ docker exec k3d-k8s-lab-server-0 conntrack -L -d $SVCIP 2>/dev/null
tcp      6 119 TIME_WAIT src=10.42.0.177 dst=10.43.36.121 sport=56598 dport=80 src=10.42.0.176 dst=10.42.0.177 sport=80 dport=56598 [ASSURED] mark=0 use=1
```

**What you should see.** The output follows the four steps from the top of this part, with values from the test run that differ from yours.

**Step 1: DNS finds the ClusterIP.**

The client knows only the name `hello`, and `resolv.conf` tells it where to ask for an address and how:

- `nameserver 10.43.0.10`: the address of CoreDNS, the cluster's DNS server
- `search course-life.svc.cluster.local svc.cluster.local cluster.local`: endings to try after a short name
- `ndots:5`: a name with fewer than five dots counts as short

`hello` has no dots, so the client tries the first ending and asks for `hello.course-life.svc.cluster.local`, and CoreDNS answers with the Service's ClusterIP, which is why a short name works inside the same namespace.

**Step 2: the client connects.**

curl prints `Trying 10.43.36.121:80... Connected to hello`, so as far as curl knows, it talks to `10.43.36.121`. The packet leaves the client pod through its network cable, the veth pair, and enters the node.

**Step 3: the kernel rewrites the destination.**

The kernel checks the packet against kube-proxy's rules in the `nat` table, where the `grep` shows five rules, and the three that move the packet work as a chain, each handing the packet to the next:

1. `KUBE-SERVICES` matches the destination `10.43.36.121` port 80 and jumps to the Service's own chain, `KUBE-SVC-KJCW...`.
2. `KUBE-SVC-KJCW...` picks one pod. With one pod, the choice is easy. With three, kube-proxy adds random odds, so each pod gets about a third of the connections.
3. `KUBE-SEP-YAZK...` rewrites the destination: `DNAT --to-destination 10.42.0.176:80`.

The packet now carries the nginx pod's real address, so the kernel sends it through the node's bridge, `cni0`, to the nginx pod, and nginx sees an ordinary TCP connection from the client pod's IP.

**Step 4: conntrack undoes the rewrite on the way back.**

conntrack shows one line with two halves:

- going out: `src=10.42.0.177 dst=10.43.36.121 dport=80` (what the client sent)
- coming back: `src=10.42.0.176 dst=10.42.0.177 sport=80` (what nginx sends)

When nginx replies from `10.42.0.176`, the kernel finds this entry and changes the source back to `10.43.36.121`, so to the client the Service answered, and it never learns the pod's real IP.

Only the first packet of a connection walks through the iptables chain, because every later packet follows the conntrack entry, which is faster.

### What scenario A doesn't give you

The request worked, but look at what nobody checked:

| Missing | What it means |
|---|---|
| Identity | nginx knows the caller's IP, nothing more. Pod IPs change, so an IP says little about who called. |
| Encryption | The request crosses the node in plain text. Anyone who captures packets on the node reads it. |
| Policy | Any pod in the cluster may connect, unless a NetworkPolicy says otherwise. |
| Request metrics | The kernel counts packets. Nobody counts HTTP requests, status codes or response times. |

Part 3 sends a request through the shop's mesh, which adds all four without any change to the apps.

## Part 3: scenario B, a request through the ambient mesh

This time the request starts on your Mac and goes through the shop, `curl localhost:8080/api/orders`, in seven steps:

1. curl on your Mac reaches the node through Docker and the serverlb container.
2. kube-proxy's rules rewrite both addresses and send the request to the gateway pod.
3. The gateway opens an HBONE tunnel, an encrypted tunnel, to the frontend pod.
4. The frontend's ztunnel sends the frontend's call through a tunnel to the waypoint.
5. The waypoint checks the policy and opens a tunnel to a backend pod.
6. The backend's ztunnel opens a tunnel to Redis.
7. The response returns through the same tunnels.

Exercise 8 below covers steps 1 and 2 of this list, exercises 9 to 12 cover steps 3 to 6, and exercise 14 covers step 7.

### Concept: the same Kubernetes plumbing, plus identity at every hop

Scenario A had no identity and no encryption, and the mesh adds both without replacing the Kubernetes plumbing, so the kernel still rewrites addresses, as in Part 2.

The connection between pods changes, because each one now runs inside an **HBONE** tunnel, ambient mode's tunnel format: an HTTP CONNECT request over mutual TLS, sent to port 15008. Mutual TLS (mTLS) is encryption where both ends show a certificate, so think of a sealed pipe with an ID check at each end.

Each end's certificate names its service account in a standard form, a SPIFFE ID, so with identities known, every hop checks policy before it passes the request on.

### 8. From your Mac to the gateway pod

Your Mac sits outside the cluster, so the request first has to reach the gateway pod inside it, through two forwarders and two kernel rewrites, before any Istio component takes part.

```console
$ docker port k3d-k8s-lab-serverlb
6443/tcp -> 0.0.0.0:63077
8080/tcp -> 0.0.0.0:8080
8080/tcp -> [::]:8080
8443/tcp -> 0.0.0.0:8443
8443/tcp -> [::]:8443

$ docker exec k3d-k8s-lab-serverlb grep -A3 "upstream 8080_tcp" /etc/nginx/nginx.conf
  upstream 8080_tcp {
    server k3d-k8s-lab-server-0:8080 max_fails=1 fail_timeout=10s;
  }

$ kubectl -n shop-ingress get svc shop-gateway-istio
NAME                 TYPE           CLUSTER-IP     EXTERNAL-IP     PORT(S)                          AGE
shop-gateway-istio   LoadBalancer   10.43.62.182   192.168.107.2   15021:32050/TCP,8080:30297/TCP   34h

$ docker exec k3d-k8s-lab-server-0 iptables -t nat -S PREROUTING
-P PREROUTING ACCEPT
-A PREROUTING -m comment --comment "kubernetes service portals" -j KUBE-SERVICES
-A PREROUTING -d 192.168.107.1/32 -j DOCKER_OUTPUT
-A PREROUTING -m addrtype --dst-type LOCAL -j CNI-HOSTPORT-DNAT

$ curl -s -o /dev/null localhost:8080/
$ docker exec k3d-k8s-lab-server-0 sh -c 'iptables -t nat -L -v -n | grep -E "shop-gateway-istio:http loadbalancer IP|DNAT .*dpt:8080 to:"'
    0     0 DNAT       6    --  *      *       0.0.0.0/0            0.0.0.0/0            tcp dpt:8080 to:10.42.0.103:8080
    1    60 KUBE-EXT-EIP2LX4U67RPLA5V  6    --  *      *       0.0.0.0/0            192.168.107.2        /* shop-ingress/shop-gateway-istio:http loadbalancer IP */ tcp dpt:8080

$ docker exec k3d-k8s-lab-server-0 conntrack -L -p tcp -d 192.168.107.2 --dport 8080 2>/dev/null | head -1
tcp      6 119 TIME_WAIT src=192.168.107.3 dst=192.168.107.2 sport=40124 dport=8080 src=10.42.0.172 dst=10.42.0.1 sport=8080 dport=36112 [ASSURED] mark=0 use=1

$ kubectl -n shop-ingress get pod -l gateway.networking.k8s.io/gateway-name=shop-gateway -o wide
NAME                                  READY   STATUS    RESTARTS   AGE    IP            NODE                   NOMINATED NODE   READINESS GATES
shop-gateway-istio-858774d7cd-5k8bl   1/1     Running   0          113s   10.42.0.172   k3d-k8s-lab-server-0   <none>           <none>
```

**What you should see.** The output follows four hops.

**Hop 1: Docker forwards the port.** Docker maps your Mac's `0.0.0.0:8080` to port 8080 of the `k3d-k8s-lab-serverlb` container.

**Hop 2: nginx relays the bytes.** That container runs **nginx in TCP stream mode**, where nginx doesn't read the HTTP but only copies bytes, as `upstream 8080_tcp { server k3d-k8s-lab-server-0:8080; }` shows, opening a new connection to the node from its own address, `192.168.107.3` in the test run.

**Hop 3: the kernel rewrites the destination.** The gateway's Service has type LoadBalancer, which on k3s gives the Service the node's own IP as its external IP, `192.168.107.2`.

Two sets of rules want this packet:

- ServiceLB: k3s's built-in load balancer runs a `svclb-...` pod with a host port, and the CNI wrote a host port DNAT for it.
- kube-proxy: it wrote its own rule for the load balancer IP.

The kernel checks rules in order and the first match wins, and `PREROUTING` jumps to kube-proxy's `KUBE-SERVICES` **first**, so kube-proxy wins, with its rules working as a chain:

1. The rule `-d 192.168.107.2/32 ... --dport 8080` jumps to `KUBE-EXT-EIP2...`.
2. `KUBE-EXT-EIP2...` marks the packet for masquerade, a note that says "change the source on the way out".
3. `KUBE-SVC-EIP2...` then `KUBE-SEP-...` rewrite the destination to the gateway pod, `10.42.0.172:8080`. This is the DNAT.

The packet counters prove it: in this run the load balancer IP rule had matched 1 connection since the gateway pod last restarted, and the host port DNAT none, while an earlier run counted 33.

**Hop 4: the kernel rewrites the source.** On the way out to the pod, `KUBE-POSTROUTING` sees the mark and applies `MASQUERADE --random-fully`, which changes the source to `10.42.0.1`, the node's address on the pod network, with a new port. Engineers call this rewrite of the source SNAT.

conntrack, the kernel's notebook of rewrites, shows both changes in one line:

- going in: `src=192.168.107.3 dst=192.168.107.2 dport=8080`
- coming back: `src=10.42.0.172 dst=10.42.0.1`

So the gateway pod sees a plain TCP connection from the node. The SNAT makes the reply return through this node, so conntrack undoes both rewrites, at the cost that the gateway never learns your Mac's address, because a Service with `externalTrafficPolicy: Cluster`, the default, always hides the client this way.

### 9. The gateway opens a tunnel to the frontend

The gateway is the shop's front door, an Envoy proxy that reads HTTP, decides which app gets the request, and opens an encrypted tunnel to that app.

```console
$ GW=$(kubectl -n shop-ingress get pod -l gateway.networking.k8s.io/gateway-name=shop-gateway -o name)
$ istioctl proxy-config routes $GW -n shop-ingress | head -3
NAME          VHOST NAME     DOMAINS     MATCH                  VIRTUAL SERVICE
http.8080     *:8080         *           /*                     frontend-0-istio-autogenerated-k8s-gateway.shop
              backend        *           /healthz/ready*

$ istioctl proxy-config endpoints $GW -n shop-ingress | grep frontend
envoy://connect_originate/10.42.0.42:3000               HEALTHY     OK                outbound|3000||frontend.shop.svc.cluster.local

$ kubectl get ns shop-ingress shop -L istio.io/dataplane-mode
NAME           STATUS   AGE   DATAPLANE-MODE
shop-ingress   Active   34h
shop           Active   34h   ambient
```

**What you should see.** Three answers:

1. **Where does the request go?** Route `http.8080` matches `/*` and sends it to `frontend.shop`, a route istiod built from the shop's HTTPRoute.
2. **How does it get there?** The endpoint is `envoy://connect_originate/10.42.0.42:3000`, which means the gateway's Envoy **itself** opens the HBONE tunnel to the frontend pod, with its own certificate.
3. **Does the gateway need ambient mode?** No. The gateway's namespace `shop-ingress` runs outside ambient mode and doesn't need it, because the gateway is already an Envoy that speaks HBONE.

### 10. Inside the frontend pod: ztunnel's sockets

Something must decrypt the tunnel before the app sees the bytes, and in ambient mode that job belongs to ztunnel, a small proxy, one per node, that handles encryption and identity for every pod on its node. Surprisingly, the tunnel ends inside the frontend pod rather than inside ztunnel's own pod, and this step shows how.

```console
$ CID=$(docker exec k3d-k8s-lab-server-0 crictl ps --name frontend -q | head -1)
$ PID=$(docker exec k3d-k8s-lab-server-0 crictl inspect --output go-template --template '{{.info.pid}}' $CID)
$ docker exec k3d-k8s-lab-server-0 nsenter -t $PID -n iptables-save | grep -E "REDIRECT|15008"
-A ISTIO_OUTPUT ! -o lo -p udp -m mark ! --mark 0x539/0xfff -m udp --dport 53 -j REDIRECT --to-ports 15053
-A ISTIO_OUTPUT ! -d 127.0.0.1/32 -p tcp -m tcp --dport 53 -m mark ! --mark 0x539/0xfff -j REDIRECT --to-ports 15053
-A ISTIO_OUTPUT ! -d 127.0.0.1/32 -p tcp -m mark ! --mark 0x539/0xfff -j REDIRECT --to-ports 15001
-A ISTIO_PRERT ! -d 127.0.0.1/32 -p tcp -m tcp ! --dport 15008 -m mark ! --mark 0x539/0xfff -j REDIRECT --to-ports 15006

$ docker exec k3d-k8s-lab-server-0 sh -c "cat /proc/$PID/net/tcp /proc/$PID/net/tcp6" \
  | python3 -c 'import sys; print(sorted({int(l.split()[1].split(":")[1],16) for l in sys.stdin if len(l.split())>3 and l.split()[3]=="0A"}))'
[3000, 15001, 15006, 15008, 15053]
```

**What you should see.** The third command enters the frontend pod's network namespace through its process ID, where istio-cni wrote REDIRECT rules when the pod started. A REDIRECT rule works like a receptionist who sends every visitor to one desk, whatever room they asked for:

| Rule | Meaning |
|---|---|
| `REDIRECT --to-ports 15001` for outgoing TCP | every connection the app opens goes to ztunnel's outbound socket |
| `REDIRECT --to-ports 15006` for incoming TCP, except to 15008 | plain-text arrivals go to ztunnel's inbound socket |
| `REDIRECT --to-ports 15053` for DNS on port 53 | ztunnel answers DNS (the lab enables DNS capture) |
| packets marked `0x539` pass untouched | ztunnel's own traffic, so it doesn't loop |

The last command lists the listening ports, `[3000, 15001, 15006, 15008, 15053]`, where port 3000 is the app and the other four are **ztunnel's sockets, inside the pod's own network namespace**, which ztunnel created here although it runs as a pod of its own.

Now the arrival makes sense, because the gateway's tunnel ends at `10.42.0.42:15008`, inside the frontend pod, and ztunnel then works through four steps:

1. It checks the gateway's identity.
2. It checks any L4 policy, a rule about who may connect.
3. It decrypts the stream.
4. It hands the bytes to the app on `:3000`.

So plain text never leaves the pod.

### 11. The frontend calls the backend: four identities

The frontend app knows nothing about the mesh and opens `http://backend.shop.svc.cluster.local:8000` like any app, so the redirect rules from step 10 hand the call to ztunnel:

1. The app's DNS query goes to ztunnel's DNS port, 15053.
2. The app's TCP connection goes to ztunnel's outbound socket, 15001.
3. ztunnel knows from istiod that the backend Service uses a waypoint, so it tunnels to the waypoint instead of to a backend pod.

Each hop has its own tunnel with two identities, the caller's and the receiver's, and ztunnel's log records them.

```console
$ kubectl -n istio-system logs ds/ztunnel --since=60m | grep 'connection complete' \
  | grep -E 'src.workload="(shop-gateway|frontend|waypoint|backend)' \
  | grep -oE '(src\.identity|dst\.identity|dst\.hbone_addr)=[^ ]+' | paste - - - | sort -u | head -8
src.identity="spiffe://cluster.local/ns/shop-ingress/sa/shop-gateway-istio"	dst.hbone_addr=10.42.0.37:4317	dst.identity="spiffe://cluster.local/ns/observability/sa/jaeger"
src.identity="spiffe://cluster.local/ns/shop-ingress/sa/shop-gateway-istio"	dst.hbone_addr=10.42.0.42:3000	dst.identity="spiffe://cluster.local/ns/shop/sa/frontend"
src.identity="spiffe://cluster.local/ns/shop/sa/backend"	dst.hbone_addr=10.42.0.37:4318	dst.identity="spiffe://cluster.local/ns/observability/sa/jaeger"
src.identity="spiffe://cluster.local/ns/shop/sa/backend"	dst.hbone_addr=10.42.0.46:6379	dst.identity="spiffe://cluster.local/ns/shop/sa/redis"
src.identity="spiffe://cluster.local/ns/shop/sa/frontend"	dst.hbone_addr=10.43.239.201:8000	dst.identity="spiffe://cluster.local/ns/shop/sa/waypoint"
src.identity="spiffe://cluster.local/ns/shop/sa/waypoint"	dst.hbone_addr=10.42.0.150:8000	dst.identity="spiffe://cluster.local/ns/shop/sa/backend"
src.identity="spiffe://cluster.local/ns/shop/sa/waypoint"	dst.hbone_addr=10.42.0.152:8000	dst.identity="spiffe://cluster.local/ns/shop/sa/backend"
src.identity="spiffe://cluster.local/ns/shop/sa/waypoint"	dst.hbone_addr=10.42.0.155:8000	dst.identity="spiffe://cluster.local/ns/shop/sa/backend"

$ istioctl ztunnel-config certificates | grep -E "ns/shop/sa/(frontend|backend)" | head -4
spiffe://cluster.local/ns/shop/sa/backend                                               Leaf     Available     true           cdd0650411d48f45b45f756066cd3e7f     2026-11-15T16:02:52Z     2026-11-14T16:00:52Z
spiffe://cluster.local/ns/shop/sa/backend                                               Root     Available     true           b1d9074685f90f0b29a27c6e0edc1a1a     2036-11-10T12:26:51Z     2026-11-13T12:26:51Z
spiffe://cluster.local/ns/shop/sa/frontend                                              Leaf     Available     true           2a7a3d079d91bf699aadb658ee9a5316     2026-11-15T16:02:51Z     2026-11-14T16:00:51Z
spiffe://cluster.local/ns/shop/sa/frontend                                              Root     Available     true           b1d9074685f90f0b29a27c6e0edc1a1a     2036-11-10T12:26:51Z     2026-11-13T12:26:51Z
```

ztunnel logs a connection only when it **closes**, and the shop reuses its connections, so they stay open for a long time. Give the command a wide time window, or wait a few minutes after sending requests. Tunnels to services from earlier modules, such as `sa/assistant` from module 17, may show up too.

**What you should see.** Four hops, each with a caller and a receiver, from the test run:

| Hop | From | To | Notes |
|---|---|---|---|
| 1 | `ns/shop-ingress/sa/shop-gateway-istio` | `ns/shop/sa/frontend` | step 9's tunnel |
| 2 | `ns/shop/sa/frontend` | `ns/shop/sa/waypoint` | addressed to `10.43.239.201:8000`, the backend **Service's** IP: the waypoint takes the Service's traffic |
| 3 | `ns/shop/sa/waypoint` | `ns/shop/sa/backend` | the waypoint picked a backend-v1 pod |
| 4 | `ns/shop/sa/backend` | `ns/shop/sa/redis` | ztunnel to ztunnel: Redis has no waypoint, so only L4 |

Every certificate carries a SPIFFE identity, a standard name made of namespace and service account, and the second command lists the certificates. In the test run each workload's leaf certificate was valid for 24 hours, signed by a root certificate valid for 10 years, and ztunnel renews the short-lived ones on its own, so a stolen certificate stops working quickly.

### 12. The waypoint decides, at Layer 7

ztunnel sees connections and identities but not HTTP, so a rule like "only `GET` on `/api/`" needs a proxy that reads each request, which in ambient mode is the waypoint, an Envoy that serves the backend Services.

```console
$ kubectl apply -f platform-engineering/manifests/06-waypoint-access-logs.yaml
telemetry.telemetry.istio.io/waypoint-access-logs created

$ curl -s -o /dev/null localhost:8080/api/orders
$ kubectl -n shop logs deploy/waypoint --tail=1
[2026-11-14T22:55:06.925Z] "GET /api/orders HTTP/1.1" 200 - via_upstream - "-" 0 395 15 14 "-" "node" "4a405e31-bc25-901e-a9aa-6ca228e6c85d" "backend.shop.svc.cluster.local:8000" "envoy://connect_originate/10.42.0.157:8000" inbound-vip|8000|http|backend-v1.shop.svc.cluster.local envoy://internal_client_address/ 10.43.239.201:8000 10.42.0.42:43502 - shop.backend-route.0

$ kubectl -n shop get authorizationpolicy backend-allow-frontend -o yaml | grep -A12 "^spec"
spec:
  action: ALLOW
  rules:
  - from:
    - source:
        principals:
        - cluster.local/ns/shop/sa/frontend
    to:
    - operation:
        methods:
        - GET
        - POST
        paths:
```

**What you should see.** One access log line that names the pod the waypoint chose, `envoy://connect_originate/10.42.0.157:8000`, and the Service `backend-v1`.

Behind that one line, the waypoint did everything an L7 proxy does, in this order:

1. It read the HTTP request.
2. It checked the policy `backend-allow-frontend`, which allows only the identity `cluster.local/ns/shop/sa/frontend`, only `GET` and `POST`, and only paths under `/api/`.
3. It matched the HTTPRoute, which chooses the version of the backend.
4. It applied timeouts and retries.
5. It recorded metrics and a trace span.
6. It opened a new HBONE tunnel to the chosen pod.

A refused request ends at step 2 with `403 RBAC: access denied`, which the waypoint writes itself, so the backend never sees the request.

### 13. Measure the whole trip

Each proxy records how long its part of the request took, as a timed block called a span, and Jaeger, the lab's tracing tool, joins the spans of one request into a trace that shows where the time goes.

```console
$ curl -s -o /dev/null -X POST localhost:8080/api/orders -H 'content-type: application/json' -d '{"item":"life","quantity":1}'
```

Find the trace in Jaeger (http://localhost:16686) by choosing service `backend` and operation `POST /api/orders`.

**What you should see.** From the test run:

| Span | Time |
|---|---|
| gateway: `frontend.shop.svc.cluster.local:3000/*`, the whole request as the gateway saw it | 18.5 ms |
| waypoint: `backend-v1.shop.svc.cluster.local:8000/*` | 7.4 ms |
| backend: `POST /api/orders` | 5.5 ms |
| backend: Redis `INCRBY`, then `HSET LPUSH LTRIM` | 0.5 ms and 0.3 ms |

Read the spans from the outside in:

1. The gateway's span covers the whole request, 18.5 ms.
2. The waypoint's span covers the backend plus one hop, 7.4 ms, while the backend itself used 5.5 ms, so the waypoint and the two ztunnels around it add about 2 ms.
3. The frontend (Node.js) doesn't trace itself, so its share hides in the gap, about 11 ms of the 18.5.

Your numbers vary with load, and the first request after a quiet spell runs slower.

### 14. The way back

The response retraces every hop, because each HBONE tunnel is a two-way stream, so replies travel back through the same tunnels and the same identities. On the outer part, the steps run in this order:

1. conntrack undoes the SNAT and the DNAT from step 8.
2. nginx and Docker pass the bytes back.
3. curl prints the JSON.

No component makes a new decision on the way back, because every check happened when the connection or request went in.

## Security checkpoints, end to end

The request met several checks, each looking at something different:

| Where | Checks | Scenario A | Scenario B |
|---|---|---|---|
| API server | authentication, RBAC, admission | yes | yes |
| Kernel, at the pod | NetworkPolicy | if defined | if defined |
| ztunnel, at each pod | mTLS identity, L4 AuthorizationPolicy | no | every hop |
| Waypoint | L7 AuthorizationPolicy on method, path, identity | no | for Services with a waypoint |
| Application | its own logins and checks | yes | yes |

## Investigate

1. You delete the `hello` pod. List, in order, the components that act before a new pod serves traffic again, and what each does.
2. In scenario A, nginx logs the client pod's IP as the source. In scenario B, what does the backend app see as the source of a request, and how does the backend learn which service really called?
3. The frontend's connection to the backend goes to the Service IP `10.43.239.201`, yet kube-proxy has iptables rules for that IP too. Why doesn't kube-proxy's DNAT send it straight to a backend pod?
4. Your API server is down for five minutes. Which of today's paths keep working, and which stop?

<details>
<summary>Answers</summary>

1. Seven components act, in this order:
   1. The ReplicaSet controller sees one pod too few and creates a new Pod object.
   2. The scheduler binds the Pod to a node.
   3. The kubelet asks containerd for a sandbox.
   4. The CNI chain gives the sandbox a network. In an ambient namespace, istio-cni and ztunnel also set up the redirect rules.
   5. The container starts, and the readiness probe passes.
   6. The EndpointSlice controller adds the new IP to the Service.
   7. kube-proxy rewrites its iptables rules, and istiod sends the new endpoint to ztunnel and the waypoints.

   Only then does traffic reach the new pod.
2. The backend receives its connection from ztunnel inside its own pod, which delivered the bytes from the waypoint's tunnel, so a plain socket shows no useful client identity. The identity lives in the mTLS layer instead: ztunnel and the waypoint know the caller is `sa/waypoint`, and the waypoint knew the original caller was `sa/frontend`, so policies use that identity. An app that needs the caller's identity relies on the mesh's AuthorizationPolicy to let in only the right callers, while in sidecar mode (module 7) the sidecar also passes the identity to the app in the `X-Forwarded-Client-Cert` header.
3. The redirect inside the frontend pod catches the connection first, because istio-cni's `REDIRECT --to-ports 15001` rule runs in the pod's own network namespace, before the packet ever reaches the node's kube-proxy rules. ztunnel then opens its own tunnel to the waypoint, while kube-proxy's rules still serve every pod outside the mesh.
4. Running traffic keeps flowing, because the iptables rules, conntrack, and the last configuration of ztunnel and the waypoint all live on the node and in the proxies. Change stops instead: no new pods start, nothing scales, endpoints don't update, no new configuration arrives, and `kubectl` fails. If a pod crashes during the outage, the kubelet restarts its container locally, while a pod that needs a new node waits for the API server.

</details>

## Clean up

```console
$ ./platform-engineering/reset.sh
Removing course rules from the shop namespace
Applying the baseline Istio config from manifests/istio
Turning off the backend experiment settings
Asking ArgoCD to sync istio-config from Git
Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules.
```

This deletes the `course-life` namespace, and with it the nginx app and the client.
