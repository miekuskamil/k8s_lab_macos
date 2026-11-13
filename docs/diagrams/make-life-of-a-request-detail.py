#!/usr/bin/env python3
"""Draw the four detail diagrams for docs/life-of-a-request.md.

  life-1-control-plane     one write through the API server's gates, then the watchers
  life-2-pod-startup       from a Deployment object to a ready pod with endpoints
  life-3-plain-request     scenario A: client pod to nginx through a Service, no mesh
  life-4-ambient-request   scenario B: curl on the Mac to Redis through the ambient mesh

Each one becomes an .svg (shown on GitHub) and an .excalidraw file (open and edit at
https://excalidraw.com), both from the same description. The numbers come from the
module 29 test run.

Run from anywhere: python3 docs/diagrams/make-life-of-a-request-detail.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from drawlib import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent
W = 1560
WATCH = CTRL[0]
DENY = SEC[0]
TUNNEL = PROXY[0]
PACKET = NET[0]


def height(c, w, lines):
    n = sum(len(c.wrap(line, w - 24)) for line in lines)
    return 36 + 19 * n + (8 if n else 0)


def heading(c, title, sub):
    c.text(40, 52, title, 26, INK, True)
    c.text(40, 82, sub, 15, MUTED)


def frame(c, x, y, w, h, title, col=FRAME, dashed=True):
    """A background box; insert it first so it sits behind everything."""
    c.boxes.insert(0, (x, y, w, h, col, title, [], dashed))


def row(c, y, specs):
    """Boxes side by side at the same top. specs: (x, w, colour, title, lines).
    Returns a list of (x, y, w, bottom) and the row's lowest bottom."""
    out = []
    for x, w, col, title, lines in specs:
        out.append((x, y, w, c.box(x, y, w, col, title, lines)))
    return out, max(b for *_, b in out)


def right_arrow(c, a, b, label="", col=INK, dy=30, dashed=False):
    c.arrow([(a[0] + a[2], a[1] + dy), (b[0], b[1] + dy)], col, label, dashed,
            at=(a[0] + a[2] + 4, a[1] + dy - 8) if label else None)


def left_arrow(c, a, b, label="", col=INK, dy=30, dashed=False):
    c.arrow([(a[0], a[1] + dy), (b[0] + b[2], b[1] + dy)], col, label, dashed,
            at=(b[0] + b[2] + 4, b[1] + dy - 8) if label else None)


def down_arrow(c, a, b, label="", col=INK, x=None, dashed=False):
    x = x if x is not None else a[0] + a[2] / 2
    c.arrow([(x, a[3]), (x, b[1])], col, label, dashed, at=(x + 8, (a[3] + b[1]) / 2 + 5) if label else None)


# ---------------------------------------------------------------------------
# 1. The control plane
# ---------------------------------------------------------------------------
def control_plane():
    c = Canvas(W, 100)
    heading(c, "1. The control plane: one write, many watchers",
            "kubectl apply sends one HTTP request. Six gates decide its fate; then every interested component hears about it through a watch.")

    kubectl = (40, 200, 250)
    kb = c.box(40, 200, 250, EXT, "kubectl apply", [
        "an HTTP client", "POST /apis/apps/v1/", "namespaces/course-life/", "deployments",
        "client certificate: system:admin, group system:masters"])

    gates = [
        (SEC, "1. Authentication: who are you?", [
            "TLS client certificate signed by the cluster's client CA, or a signed service account token",
            "--anonymous-auth=false: no identity, no entry",
            "result: user system:admin, groups system:masters, system:authenticated"]),
        (SEC, "2. Authorization: may you do this?", [
            "--authorization-mode=Node,RBAC, asked in order; the first yes wins",
            "Node: a kubelet only touches its own node's pods and secrets",
            "RBAC: Roles and ClusterRoles through bindings; system:masters skips RBAC"]),
        (SEC, "3. Mutating admission: should it change?", [
            "built-in plugins fill defaults: service account, default tolerations",
            "webhooks: Kyverno add-defaults (module 26), Istio's sidecar injector"]),
        (SEC, "4. Schema validation: is it well formed?", [
            "the OpenAPI schema and built-in rules",
            "replicas: -1 gives 422: must be greater than or equal to 0"]),
        (SEC, "5. Validating admission: is it allowed?", [
            "NodeRestriction, ValidatingAdmissionPolicy (CEL)",
            "webhooks: Istio config validation, Kyverno Enforce policies",
            "an AuthorizationPolicy using request.colour: denied"]),
        (STORE, "6. Storage: write it", [
            "--etcd-servers=unix://kine.sock",
            "the object gets a resourceVersion (16403 in the test run)",
            "the reply goes back to kubectl: 201 Created"]),
    ]
    gx, gw, y = 350, 430, 200
    boxes = []
    for col, title, lines in gates:
        b = c.box(gx, y, gw, col, title, lines)
        boxes.append((gx, y, gw, b))
        y = b + 30
    for a, b in zip(boxes, boxes[1:]):
        down_arrow(c, a, b)
    c.arrow([(kubectl[0] + kubectl[2], 240), (gx, 240)], INK, "HTTPS", at=(296, 232))
    c.arrow([(gx, boxes[-1][1] + 60), (kubectl[0] + 115, boxes[-1][1] + 60), (kubectl[0] + 115, kb)],
            INK, "201 Created", dashed=True, at=(160, boxes[-1][1] + 52))

    # refusals
    rx, rw = 820, 250
    ry = boxes[1][1]
    rb = c.box(rx, ry, rw, SEC, "Refused: straight back", [
        "401 Unauthorized (gate 1)", "403 Forbidden (gate 2)",
        "400 or 422, or a webhook's message (gates 3 to 5)",
        "nothing stored, no watcher ever hears of it"])
    for g in boxes[:5]:
        yy = g[1] + 26
        c.arrow([(gx + gw, yy), (rx, min(max(yy, ry + 20), rb - 20))], DENY, dashed=True)

    # watch cache
    wy = boxes[5][1]
    wc = (rx, wy, rw)
    wb = c.box(rx, wy, rw, CTRL, "Watch cache", [
        "every watcher holds one long HTTP stream: ?watch=1",
        "events: ADDED, MODIFIED, DELETED",
        "a resourceVersion lets a watcher resume after a reconnect"])
    right_arrow(c, (gx, wy, gw), (rx, wy), "", WATCH)

    # storage
    fbottom = max(boxes[5][3], wb) + 30
    sy = fbottom + 70
    sb = c.box(gx, sy, gw, STORE, "kine + SQLite", [
        "k3s' default datastore: kine speaks the etcd API, stores rows in SQLite (state.db)",
        "each row carries a revision; kine polls for new rows and turns them into watch events",
        "etcd in other clusters: the same API, replicated with Raft"])
    down_arrow(c, boxes[5], (gx, sy, gw, sb), "etcd API over a unix socket", STORE[0])

    frame(c, 320, 160, 780, fbottom - 160, "API server (inside the k3s server process)")

    # watchers
    xw, ww = 1150, 370
    watchers = [
        ("Deployment controller", [
            "watches Deployments and ReplicaSets",
            "hashes the pod template into pod-template-hash",
            "writes a ReplicaSet; a rolling update scales two of them in steps"]),
        ("ReplicaSet controller", [
            "counts the pods that match its selector",
            "too few: creates Pods with an ownerReference",
            "too many: deletes, unscheduled and unready first"]),
        ("Scheduler", [
            "watches Pods with an empty spec.nodeName",
            "filter, score, then bind writes the node",
            "nothing fits: tries preemption, else the pod stays Pending"]),
        ("kubelet (one per node)", [
            "watches Pods bound to its own node",
            "runs them through CRI and CNI, reports status",
            "the Node authorizer keeps it to its own pods"]),
        ("EndpointSlice controller", [
            "watches Services and Pods",
            "lists the ready pod IPs behind each Service"]),
        ("kube-proxy, CoreDNS, istiod", [
            "kube-proxy: Services and EndpointSlices become iptables rules",
            "CoreDNS: names become ClusterIPs",
            "istiod: everything becomes xDS for ztunnel, waypoints, gateways"]),
    ]
    y = 160
    bus = 1120
    for title, lines in watchers:
        b = c.box(xw, y, ww, CTRL, title, lines)
        c.arrow([(rx + rw, wy + 40), (bus, wy + 40), (bus, y + 26), (xw, y + 26)], WATCH, dashed=True)
        y = b + 18
    c.text(rx + rw + 4, wy + 32, "watch", 13, WATCH, True)

    note_y = max(y, sb) + 30
    nb = c.box(40, note_y, W - 80, FRAME, "Nobody gives orders", [
        "Each watcher writes its result back through gates 1 to 6, like kubectl, with its own identity and RBAC role. "
        "The next watcher notices the new object. Two writers racing on one object: the second gets 409 Conflict, "
        "because its resourceVersion is stale, re-reads and tries again (optimistic concurrency)."])
    c.h = nb + 40
    c.save(OUT, "life-1-control-plane")


# ---------------------------------------------------------------------------
# 2. Pod start-up
# ---------------------------------------------------------------------------
def pod_startup():
    c = Canvas(W, 100)
    heading(c, "2. From an object to a ready pod",
            "Each arrow is one component reacting to a change it watched. In the test run, all of it took about two seconds.")
    xs = [40, 340, 640, 940, 1240]
    w = 270

    r1, b1 = row(c, 150, [
        (xs[0], w, GREY, "Deployment hello", ["replicas: 1", "template: nginx:1.27-alpine", "stored, resourceVersion set"]),
        (xs[1], w, GREY, "ReplicaSet hello-76fb6c6b6f", ["pod-template-hash=76fb6c6b6f", "ownerReference: Deployment/hello"]),
        (xs[2], w, GREY, "Pod hello-76fb6c6b6f-sj879", ["spec.nodeName empty", "phase Pending", "ownerReference: ReplicaSet"]),
        (xs[3], w, CTRL, "Scheduler", ["filter: requests fit? selector? taints? ports?",
                                       "score: spread, image present, balance",
                                       "bind: nodeName k3d-k8s-lab-server-0"]),
        (xs[4], w, CTRL, "kubelet", ["sees a new pod on its node", "syncPod: sandbox, volumes, containers, probes"]),
    ])
    labels = ["deployment-controller", "replicaset-controller", "watch", "bind"]
    for a, b, l in zip(r1, r1[1:], labels):
        c.arrow([(a[0] + a[2], a[1] + 30), (b[0], b[1] + 30)], WATCH)
        c.text(a[0] + a[2] - 60, a[1] - 10, l, 13, WATCH, True)

    y2 = b1 + 70
    r2, b2 = row(c, y2, [
        (xs[4], w, GREY, "containerd: RunPodSandbox", ["kubelet calls it over CRI (a gRPC socket)",
                                                       "a pause container holds the pod's network namespace"]),
        (xs[3], w, NET, "CNI: flannel", ["a veth pair: eth0 in the pod, the other end on cni0",
                                         "host-local IPAM: 10.42.0.197 from 10.42.0.0/24"]),
        (xs[2], w, PROXY, "istio-cni (ambient only)", ["iptables in the pod's namespace: 15001, 15006, 15053",
                                                        "ztunnel opens its sockets inside the pod"]),
        (xs[1], w, GREY, "Containers", ["image already present", "create, start",
                                        "cgroup limits: memory 64Mi"]),
        (xs[0], w, GREY, "Ready", ["readinessProbe GET / every 2 s passes",
                                   "condition Ready=True, about 1 s after PodScheduled"]),
    ])
    down_arrow(c, r1[4], r2[0], "CRI", INK)
    for a, b in zip(r2, r2[1:]):
        left_arrow(c, a, b)
    c.text(xs[2] + 4, y2 - 10, "skipped outside ambient namespaces", 12, MUTED)

    y3 = b2 + 70
    es = (xs[0], y3, w)
    eb = c.box(*es, CTRL, "EndpointSlice controller", ["adds 10.42.0.197 ready=true to Service hello"])
    down_arrow(c, r2[4], (xs[0], y3, w, eb), "status Ready", WATCH)
    cx, cw, cy = 470, 700, y3
    bus = 400
    b3 = eb
    for col, title, lines in [
            (NET, "kube-proxy (on every node)", ["writes a new KUBE-SEP chain: DNAT to 10.42.0.197:80"]),
            (GREY, "CoreDNS", ["hello.course-life.svc.cluster.local answers ClusterIP 10.43.76.137"]),
            (CTRL, "istiod", ["pushes the workload to every ztunnel and waypoint; matters only for mesh traffic"])]:
        b3 = c.box(cx, cy, cw, col, title, lines)
        c.arrow([(xs[0] + w, y3 + 30), (bus, y3 + 30), (bus, cy + 28), (cx, cy + 28)], WATCH, dashed=True)
        cy = b3 + 14
    c.text(xs[0] + w + 6, y3 + 22, "watch", 13, WATCH, True)

    y4 = b3 + 50
    r4, b4 = row(c, y4, [
        (40, 470, SEC, "When the scheduler says no", [
            "64Gi request: 0/1 nodes are available: 1 Insufficient memory",
            "nodeSelector disktype=ssd: didn't match Pod's node affinity/selector",
            "preemption: no victims found, so the pod stays Pending"]),
        (545, 470, STORE, "Requests against limits", [
            "the scheduler counts requests only: 30% of the node's memory",
            "limits add up to 106%: the node is overcommitted",
            "if every pod used its limit at once, the OOM killer picks victims"]),
        (1050, 470, GREY, "Self-healing", [
            "delete the pod: the ReplicaSet controller sees 0 of 1",
            "it creates a new Pod, and the chain from the third box runs again",
            "owner references let the garbage collector delete children"]),
    ])
    c.h = b4 + 40
    c.save(OUT, "life-2-pod-startup")


# ---------------------------------------------------------------------------
# 3. Scenario A: plain Kubernetes
# ---------------------------------------------------------------------------
def plain_request():
    c = Canvas(W, 100)
    heading(c, "3. Scenario A: a request without a mesh",
            "client pod to nginx through a ClusterIP Service. The kernel does all the work; kube-proxy only wrote the rules.")

    client = (80, 190, 330)
    cb = c.box(*client, GREY, "client pod: 10.42.0.198", [
        "curlimages/curl", "resolv.conf: nameserver 10.43.0.10",
        "search course-life.svc.cluster.local ...", "ndots:5", "curl http://hello"])
    dns_y = cb + 70
    db = c.box(80, dns_y, 330, GREY, "CoreDNS", [
        "hello has fewer than 5 dots: try hello.course-life.svc.cluster.local first",
        "answer: ClusterIP 10.43.76.137"])
    c.arrow([(160, cb), (160, dns_y)], INK, "1  DNS query to 10.43.0.10:53", at=(168, (cb + dns_y) / 2 + 4))
    c.arrow([(330, dns_y), (330, cb)], INK, "", dashed=True)

    nx, nw = 490, 520
    nb = c.box(nx, 190, nw, NET, "Node kernel: the nat table kube-proxy wrote", [
        "KUBE-SERVICES: -d 10.43.76.137/32 --dport 80",
        "-> KUBE-SVC-KJCW...: pick one endpoint (random, by probability)",
        "-> KUBE-SEP-4PRS...: DNAT --to-destination 10.42.0.197:80",
        "nothing listens on 10.43.76.137: it exists only as this rule"])
    c.arrow([(client[0] + client[2], 230), (nx, 230)], PACKET, "2  SYN", at=(420, 222))

    ct_y = nb + 60
    ctb = c.box(nx, ct_y, nw, NET, "conntrack", [
        "out:  src=10.42.0.198  dst=10.43.76.137  dport=80",
        "back: src=10.42.0.197  dst=10.42.0.198  sport=80",
        "rewrites every reply's source back to 10.43.76.137"])
    c.arrow([(nx + 120, nb), (nx + 120, ct_y)], PACKET, "3  remember the rewrite", at=(nx + 128, (nb + ct_y) / 2 + 4))

    bx, bw = 1090, 400
    bb = c.box(bx, 190, bw, NET, "cni0 bridge", [
        "route 10.42.0.0/24 dev cni0: pods on this node",
        "a veth pair into every pod",
        "pods on other nodes: flannel's VXLAN interface"])
    c.arrow([(nx + nw, 230), (bx, 230)], PACKET, "4  DNAT", at=(nx + nw + 10, 222))
    hy = bb + 60
    hb = c.box(bx, hy, bw, GREY, "hello pod: nginx, 10.42.0.197:80", [
        "accepts a plain TCP connection",
        "sees source 10.42.0.198, an IP and nothing more",
        "200 OK"])
    c.arrow([(bx + 120, bb), (bx + 120, hy)], PACKET, "5  deliver through the veth", at=(bx + 128, (bb + hy) / 2 + 4))
    c.arrow([(bx, hy + 70), (nx + nw, ct_y + 50)], PACKET, "6  reply", dashed=True, at=(nx + nw + 10, ct_y + 40))
    c.arrow([(nx, ct_y + 70), (client[0] + client[2], cb - 30)], PACKET, "7  source restored", dashed=True,
            at=(client[0] + client[2] + 20, cb + 30))

    frame(c, 40, 140, W - 80, max(db, ctb, hb) + 40 - 140, "Node k3d-k8s-lab-server-0 (a Docker container on your Mac)")

    my = max(db, ctb, hb) + 80
    mb = c.box(40, my, W - 80, SEC, "What scenario A lacks", [
        "No identity: nginx knows an IP, and IPs change with every pod.",
        "No encryption: anyone who captures packets on the node reads the request.",
        "No policy: any pod in the cluster connects, unless a NetworkPolicy says otherwise.",
        "No per-request metrics or traces: the kernel counts packets, not HTTP requests."])
    c.h = mb + 40
    c.save(OUT, "life-3-plain-request")


# ---------------------------------------------------------------------------
# 4. Scenario B: the ambient mesh
# ---------------------------------------------------------------------------
def ambient_request():
    c = Canvas(W, 100)
    heading(c, "4. Scenario B: curl to Redis through the ambient mesh",
            "One DNAT and one SNAT bring the request to the gateway; then four HBONE tunnels, each with two verified identities.")

    # row 1: outside the cluster
    r1, b1 = row(c, 150, [
        (40, 440, EXT, "Your Mac", ["curl localhost:8080/api/orders"]),
        (560, 440, EXT, "Docker port mapping", ["0.0.0.0:8080 to port 8080 of k3d-k8s-lab-serverlb"]),
        (1080, 440, EXT, "k3d-k8s-lab-serverlb", ["nginx in TCP stream mode",
                                                  "upstream 8080_tcp: server k3d-k8s-lab-server-0:8080"]),
    ])
    right_arrow(c, r1[0], r1[1], "", PACKET)
    right_arrow(c, r1[1], r1[2], "", PACKET)

    # row 2: one DNAT and one SNAT on the node
    y2 = b1 + 70
    r2, b2 = row(c, y2, [
        (1080, 440, NET, "PREROUTING: KUBE-SERVICES runs first", ["-d 192.168.107.2 --dport 8080: kube-proxy's load balancer IP rule",
                                                                 "KUBE-EXT-EIP2... marks the packet for masquerade"]),
        (560, 440, NET, "DNAT: kube-proxy", ["KUBE-SVC-EIP2... -> KUBE-SEP-XZ3I...",
                                             "destination becomes the gateway pod 10.42.0.88:8080"]),
        (40, 440, NET, "SNAT: KUBE-POSTROUTING", ["MASQUERADE --random-fully",
                                                  "source becomes 10.42.0.1 with a new port",
                                                  "the gateway sees the node, not the serverlb"]),
    ])
    down_arrow(c, r1[2], r2[0], "", PACKET)
    left_arrow(c, r2[0], r2[1], "", PACKET)
    left_arrow(c, r2[1], r2[2], "", PACKET)
    c.text(560, y2 - 14, "conntrack remembers both rewrites; svclb's host port rule comes later and never matches", 13, PACKET, True)

    # row 3: gateway, then the frontend pod
    y3 = b2 + 90
    gw = (40, y3, 400)
    gb = c.box(*gw, PROXY, "Gateway pod: Envoy", [
        "ns shop-ingress, not in ambient mode",
        "route http.8080: /* to frontend.shop:3000",
        "endpoint envoy://connect_originate/10.42.0.13:3000",
        "opens the HBONE tunnel itself, with its own certificate",
        "span: 18.5 ms, the whole request"])
    down_arrow(c, r2[2], (40, y3, 400, gb), "plain TCP", PACKET, x=240)

    fx = 520
    inner_y = y3 + 46
    f_in = (fx + 20, inner_y, 300)
    f_app = (fx + 345, inner_y, 300)
    f_out = (fx + 670, inner_y, 310)
    fi = c.box(*f_in, PROXY, "ztunnel :15008 (inbound)", [
        "terminates mTLS, checks the caller's identity",
        "L4 AuthorizationPolicy", "hands plain bytes to :3000"])
    fa = c.box(*f_app, GREY, "frontend app :3000", [
        "Node.js, no tracing of its own",
        "about 11 ms of the 18.5",
        "calls http://backend.shop.svc.cluster.local:8000"])
    fo = c.box(*f_out, PROXY, "ztunnel :15001 (outbound)", [
        "istio-cni's REDIRECT caught the connect",
        "DNS through :15053",
        "istiod says: the backend Service has a waypoint"])
    fbot = max(fi, fa, fo)
    frame(c, fx, y3, 1000, fbot + 18 - y3, "frontend pod 10.42.0.13 (sockets inside its own network namespace)", GREY)
    c.arrow([(440, y3 + 90), (f_in[0], inner_y + 40)], TUNNEL, "", at=None)
    c.text(446, y3 + 80, "HBONE 1", 13, TUNNEL, True)
    right_arrow(c, f_in + (fi,), f_app, "", INK, dy=40)
    right_arrow(c, f_app + (fa,), f_out, "", INK, dy=40)

    # row 4: waypoint on the right, the backend pod on the left
    y4 = max(gb, fbot + 18) + 90
    wp = (1100, y4, 420)
    wb = c.box(*wp, PROXY, "Waypoint pod: Envoy, sa/waypoint", [
        "reads the HTTP request: GET /api/orders",
        "AuthorizationPolicy backend-allow-frontend: sa/frontend only, GET and POST, /api/*",
        "HTTPRoute picks backend-v1; timeouts and retries",
        "metrics and a span: 7.4 ms",
        "refused: 403 RBAC: access denied, from here"])
    c.arrow([(f_out[0] + 150, fo), (f_out[0] + 150, y4)], TUNNEL,
            "", at=None)
    c.text(f_out[0] + 142 - 250, (fo + y4) / 2 - 6, "HBONE 2", 13, TUNNEL, True)
    c.text(f_out[0] + 142 - 250, (fo + y4) / 2 + 12, "to the Service IP 10.43.239.201:8000", 13, TUNNEL)

    bx = 40
    b_out = (bx + 20, y4 + 46, 300)
    b_app = (bx + 345, y4 + 46, 300)
    b_in = (bx + 670, y4 + 46, 290)
    bo = c.box(*b_out, PROXY, "ztunnel :15001 (outbound)", [
        "redis has no waypoint", "so ztunnel tunnels straight to its ztunnel", "Layer 4 only"])
    ba = c.box(*b_app, GREY, "backend app :8000", [
        "span POST /api/orders: 5.5 ms", "writes the order to Redis"])
    bi = c.box(*b_in, PROXY, "ztunnel :15008 (inbound)", [
        "checks sa/waypoint", "hands bytes to :8000"])
    bbot = max(bo, ba, bi)
    frame(c, bx, y4, 1000, bbot + 18 - y4, "backend-v1 pod", GREY)
    c.arrow([(wp[0], y4 + 90), (b_in[0] + b_in[2], y4 + 86)], TUNNEL, "", at=None)
    c.text(wp[0] - 76, y4 + 112, "HBONE 3", 13, TUNNEL, True)
    left_arrow(c, b_in + (bi,), b_app, "", INK, dy=40)
    left_arrow(c, b_app + (ba,), b_out, "", INK, dy=40)

    # row 5: redis and istiod
    y5 = max(wb, bbot + 18) + 90
    rb = c.box(40, y5, 400, GREY, "redis pod", [
        "its ztunnel :15008 checks sa/backend",
        "INCRBY 0.5 ms, then HSET LPUSH LTRIM 0.3 ms"])
    c.arrow([(b_out[0] + 120, bo), (b_out[0] + 120, y5)], TUNNEL, "HBONE 4", at=(b_out[0] + 128, (bo + y5) / 2 + 4))

    ib = c.box(1100, y5, 420, CTRL, "istiod", [
        "sends routes, policies and endpoints over xDS to every ztunnel, waypoint and gateway",
        "signs SPIFFE certificates: 24 h leaves, a 10 year root; ztunnel renews them on its own"])
    c.arrow([(1310, y5), (1310, wb)], WATCH, "xDS", dashed=True, at=(1318, (wb + y5) / 2 + 4))

    ty = max(rb, ib) + 40
    tb = c.box(480, y5, 580, SEC, "The four identities", [
        "1  ns/shop-ingress/sa/shop-gateway-istio  ->  ns/shop/sa/frontend",
        "2  ns/shop/sa/frontend  ->  ns/shop/sa/waypoint",
        "3  ns/shop/sa/waypoint  ->  ns/shop/sa/backend",
        "4  ns/shop/sa/backend  ->  ns/shop/sa/redis"])
    ty = max(ty, tb + 40)
    back = c.box(40, ty, W - 80, FRAME, "The way back", [
        "Each HBONE tunnel is a two-way stream: the response returns through the same tunnels and identities. "
        "Then conntrack undoes the SNAT and the DNAT, nginx and Docker pass the bytes on, and curl prints the JSON. "
        "Nothing decides anything on the way back: every check happened on the way in."])
    c.h = back + 40
    c.save(OUT, "life-4-ambient-request")


if __name__ == "__main__":
    control_plane()
    pod_startup()
    plain_request()
    ambient_request()
