#!/usr/bin/env python3
"""Draw "The life of a request": from kubectl apply to a response.

Three bands on one canvas:
  1. top:          a pod comes to life (control plane, steps 1 to 13)
  2. middle left:  scenario A, plain Kubernetes, client pod to Service
  3. right:        scenario B, the shop through Istio ambient, curl to response

Writes life-of-a-request.svg (shown on GitHub) and life-of-a-request.excalidraw
(open and edit at https://excalidraw.com) from the same description.

Run from anywhere: python3 docs/diagrams/make-life-of-a-request.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from drawlib import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent
W, H = 2600, 2560
c = Canvas(W, H)
BLANK = ("#8c959f", "#ffffff")


def height(w, lines):
    """Height box() will give a box of width w holding these lines."""
    n = sum(len(c.wrap(line, w - 24)) for line in lines)
    return 36 + 19 * n + (8 if n else 0)


def group(x, y, w, col, title, lines, inner, h=None, across=False):
    """A box holding its own lines, then smaller boxes inside it: stacked, or side by side
    when across=True. Returns bottom y."""
    top = y + (height(w, lines) if lines else 36)
    if across:
        iw = (w - 24 - 10 * (len(inner) - 1)) / len(inner)
        ih = max(height(iw, l) for _, _, l in inner)
        total = top + ih + 12
    else:
        iw = w - 24
        total = top + sum(height(iw, l) + 10 for _, _, l in inner) + 4
    bottom = c.box(x, y, w, col, title, lines, h=h or (total - y))
    yy, xx = top, x + 12
    for icol, ititle, ilines in inner:
        if across:
            c.box(xx, top, iw, icol, ititle, ilines, h=(h or (total - y)) - (top - y) - 12)
            xx += iw + 10
        else:
            yy = c.box(x + 12, yy, iw, icol, ititle, ilines) + 10
    return bottom


def down(x, y1, y2, col=INK, label="", dashed=False):
    c.arrow([(x, y1), (x, y2)], col, label, dashed, at=(x + 10, (y1 + y2) / 2 + 5) if label else None)


# ---- title ------------------------------------------------------------------
c.text(40, 54, "The life of a request: from kubectl apply to a response", 34, INK, True)
c.text(40, 88, "Everything measured on this lab: k3s v1.31.5 in k3d on OrbStack, Istio 1.24.2 ambient. "
       "Purple: control plane. Orange: storage. Green: kernel networking. Blue: proxies. "
       "Red: security decisions. Yellow: outside the cluster.", 16, MUTED)

# ============================================================================
# Band 1: a pod comes to life
# ============================================================================
B1 = 112
band1 = len(c.boxes)
c.box(40, B1, 2520, BLANK, "", h=10)  # placeholder, resized at the end of the band
c.text(60, B1 + 32, "1. A pod comes to life: kubectl apply -f deployment.yaml", 22, CTRL[0], True)

R1 = B1 + 110  # top of the API server frame
# step 1: kubectl
k_x, k_w = 60, 370
# API server frame with steps 2 to 5
api_x, api_w = 470, 1400
sw, sg = 320, 20
api = [
    ("2. Authentication", [
        "Client cert signed by client-ca → user system:admin, groups system:masters and system:authenticated.",
        "--anonymous-auth=false.",
        "Service accounts use signed JWT tokens."]),
    ("3. Authorization", [
        "--authorization-mode=Node,RBAC.",
        "Node authorizer for kubelets, then RBAC Roles and ClusterRoles. system:masters skips RBAC.",
        "Example: kubectl auth can-i create deployments",
        "--as=system:serviceaccount:shop:frontend",
        "→ no"]),
    ("4. Mutating admission", [
        "Built-in plugins plus webhooks (Istio sidecar injector, Kyverno mutate) change the object."]),
    ("5. Validation", [
        "Schema validation, then validating admission: NodeRestriction, ValidatingAdmissionPolicy (CEL), "
        "webhooks (Kyverno, Istio validation).",
        "Refusal → error back to kubectl."]),
]
sh = max(height(sw, l) for _, l in api)
api_h = 40 + sh + 20
c.box(api_x, R1, api_w, CTRL, "API server: every request passes these checks in order", h=api_h)
sx = [api_x + 20 + i * (sw + sg) for i in range(4)]
for x, (t, l) in zip(sx, api):
    c.box(x, R1 + 40, sw, SEC, t, l, h=sh)
for i in range(3):
    c.arrow([(sx[i] + sw, R1 + 40 + sh / 2), (sx[i + 1], R1 + 40 + sh / 2)], INK)

k_h = height(k_w, ["Reads kubeconfig.", "Sends REST POST /apis/apps/v1/namespaces/default/deployments "
                   "(protobuf/JSON) over TLS with a client certificate."])
c.box(k_x, R1 + 40, k_w, EXT, "1. kubectl apply", [
    "Reads kubeconfig.",
    "Sends REST POST /apis/apps/v1/namespaces/default/deployments (protobuf/JSON) over TLS "
    "with a client certificate."])
c.arrow([(k_x + k_w, R1 + 40 + k_h / 2), (sx[0], R1 + 40 + k_h / 2)], INK)
# refusal path from step 5 back to kubectl, above the frame
c.arrow([(sx[3] + sw / 2, R1 + 40), (sx[3] + sw / 2, R1 - 22), (k_x + k_w / 2, R1 - 22), (k_x + k_w / 2, R1 + 40)],
        SEC[0], "refused by step 2, 3, 4 or 5: error back to kubectl", dashed=True, at=(k_x + k_w / 2 + 14, R1 - 30))

# step 6: storage below the API server
st_y = R1 + api_h + 60
st_x, st_w = api_x + 20, api_w - 40
st_bottom = c.box(st_x, st_y, st_w, STORE, "6. Storage", [
    "--etcd-servers=unix://kine.sock: kine translates etcd calls to SQLite "
    "/var/lib/rancher/k3s/server/db/state.db (74 MB) in k3s.",
    "Real clusters use etcd (Raft, 3 or 5 nodes). Every object gets a resourceVersion."])
down(sx[3] + sw / 2, R1 + 40 + sh, st_y, STORE[0], "store")

# step 7: controller manager, right of the API server
cm_x, cm_w = api_x + api_w + 40, 2540 - (api_x + api_w + 40)
cm_bottom = c.box(cm_x, R1 + 40, cm_w, CTRL, "7. Controller manager", [
    "Watch: informers cache objects.",
    "Deployment controller creates a ReplicaSet (ownerReference); the ReplicaSet controller creates Pods.",
    "Reconcile loop: compare desired vs actual, act, repeat."])
st_mid = (st_y + st_bottom) / 2
c.arrow([(st_x + st_w, st_mid), (cm_x + 140, st_mid), (cm_x + 140, cm_bottom)], CTRL[0], "watch",
        at=(st_x + st_w + 16, st_mid - 8))

# row 2: steps 8 to 13, left to right
R2 = st_bottom + 70
row2 = [
    (370, CTRL, "8. Scheduler", [
        "Watches Pods with no nodeName.",
        "Filter (resources, taints, affinity, ports) → Score (spread, image locality, balance) "
        "→ Bind (writes spec.nodeName).",
        "Failure: 0/1 nodes are available: Insufficient memory = filter phase."], None),
    (290, CTRL, "9. kubelet", [
        "On k3d-k8s-lab-server-0.",
        "Sees its pod via watch, admits it, calls containerd over CRI."], None),
    (290, GREY, "10. containerd", [
        "Creates the pause sandbox (network namespace), pulls the image, starts containers."], None),
    (400, NET, "11. CNI chain", [
        "flannel: pod IP from 10.42.0.0/24 on the cni0 bridge + veth.",
        "istio-cni (if the namespace is in ambient): iptables inside the pod netns, "
        "tells ztunnel to open sockets inside the pod."], None),
    (280, GREY, "12. Probes", [
        "startup → readiness.",
        "Ready pod → the EndpointSlice controller adds its IP."], None),
    (720, GREY, "13. Consumers of EndpointSlices", [], [
        (NET, "kube-proxy", ["Writes iptables KUBE-SVC / KUBE-SEP rules."]),
        (CTRL, "istiod", ["Pushes the endpoint over xDS: to ztunnel (WDS), to waypoints and gateways (EDS)."]),
        (GREY, "CoreDNS", ["Answers names."])]),
]
gap = (2480 - sum(r[0] for r in row2)) / (len(row2) - 1)
r2h = 0
for w, col, t, l, inner in row2:
    if inner:
        iw = (w - 24 - 10 * (len(inner) - 1)) / len(inner)
        r2h = max(r2h, 36 + max(height(iw, il) for _, _, il in inner) + 12)
    else:
        r2h = max(r2h, height(w, l))
x = 60
r2x = []
for w, col, t, l, inner in row2:
    r2x.append(x)
    if inner:
        group(x, R2, w, col, t, l, inner, h=r2h, across=True)
    else:
        c.box(x, R2, w, col, t, l, h=r2h)
    x += w + gap
for i in range(len(row2) - 1):
    a = r2x[i] + row2[i][0]
    c.arrow([(a, R2 + r2h / 2), (r2x[i + 1], R2 + r2h / 2)], INK)
# 7 -> 8: new Pods go to the scheduler
gy = R2 - 32
c.arrow([(cm_x + cm_w - 120, cm_bottom), (cm_x + cm_w - 120, gy), (r2x[0] + 200, gy), (r2x[0] + 200, R2)],
        CTRL[0], "new Pods (no nodeName yet) → scheduler; Bind → kubelet on that node",
        at=(r2x[0] + 214, gy - 8))

B1_end = R2 + r2h + 24
b = c.boxes[band1]
c.boxes[band1] = (b[0], b[1], b[2], B1_end - B1, b[4], b[5], b[6], b[7])

# ============================================================================
# Band 2: scenario A, plain Kubernetes
# ============================================================================
B2 = B1_end + 30
A_x, A_w = 40, 700
c.box(A_x, B2, A_w, BLANK, "", h=10)
band2 = len(c.boxes) - 1
c.text(A_x + 20, B2 + 32, "A. Plain Kubernetes (no mesh)", 22, NET[0], True)
c.text(A_x + 20, B2 + 56, "A client pod calls a Service.", 15, MUTED)

hx, hw, hgap = A_x + 40, A_w - 80, 52
y = B2 + 80
hops_a = [
    (GREY, "1. Client pod (namespace outside the mesh)", [
        "Asks DNS: /etc/resolv.conf → CoreDNS 10.43.0.10 → A record for the Service ClusterIP."], "connect()"),
    (GREY, "2. connect(ClusterIP:port)", [
        "Leaves the pod through its veth into the node netns."], "veth"),
    (NET, "3. Node iptables", [
        "KUBE-SERVICES matches the ClusterIP",
        "→ KUBE-SVC-xxx picks an endpoint (random, probability)",
        "→ KUBE-SEP-xxx DNATs to pod IP:port.",
        "conntrack records the translation."], "DNAT done"),
    (NET, "4. cni0 bridge → veth of the target pod", [
        "Same node here. Across nodes, flannel VXLAN would wrap the packet."], "veth"),
    (GREY, "5. Target pod", [
        "Receives plain TCP, source = client pod IP."], None),
]
for i, (col, t, l, lab) in enumerate(hops_a):
    yb = c.box(hx, y, hw, col, t, l)
    if lab:
        down(hx + 60, yb, yb + hgap, INK, lab)
        y = yb + hgap
    else:
        y = yb
# security note glued to the target pod
y = c.box(hx + 40, y + 10, hw - 40, SEC, "No identity, no encryption", [
    "Any pod may connect unless a NetworkPolicy says otherwise."])
down(hx + 60, y, y + hgap, INK, "reply")
y = c.box(hx, y + hgap, hw, GREY, "6. Return", [
    "The reply goes back; conntrack reverses the DNAT, so the client sees the ClusterIP as the source."],
    dashed=True)
A_end = y + 30

# ============================================================================
# Band 3: scenario B, the shop through Istio ambient
# ============================================================================
Bx = A_x + A_w + 30
Bw = 2560 - Bx
c.box(Bx, B2, Bw, BLANK, "", h=10)
band3 = len(c.boxes) - 1
c.text(Bx + 20, B2 + 32, "B. The shop through Istio ambient", 22, PROXY[0], True)
c.text(Bx + 20, B2 + 56, "curl on the Mac → gateway → frontend → waypoint → backend → Redis, and back.", 15, MUTED)

cw, cg = 540, 40
cx = [Bx + 20 + i * (cw + cg) for i in range(3)]
top = B2 + 80
gap = 52


def column(x, y, hops):
    """Stack hops down a column with labelled arrows; return (bottom y, list of (top, bottom))."""
    spans = []
    for i, (kind, col, t, l, inner, lab) in enumerate(hops):
        if kind == "box":
            yb = c.box(x, y, cw, col, t, l)
        else:
            yb = group(x, y, cw, col, t, l, inner)
        spans.append((y, yb))
        if lab is not None and i < len(hops) - 1:
            down(x + 60, yb, yb + gap, INK, lab)
        y = yb + gap
    return y - gap, spans


col1 = [
    ("box", EXT, "1. Mac", ["curl localhost:8080"], None, "TCP"),
    ("box", EXT, "2. OrbStack / Docker port mapping", [
        "host 0.0.0.0:8080 → container k3d-k8s-lab-serverlb:8080"], None, "TCP"),
    ("box", EXT, "3. k3d serverlb (nginx, TCP stream mode)", [
        "upstream 8080_tcp { server k3d-k8s-lab-server-0:8080 }"], None, "to node :8080"),
    ("box", NET, "4. Node 192.168.107.2:8080, PREROUTING", [
        "KUBE-SERVICES runs before the svclb host port rule:",
        "kube-proxy's load balancer IP rule matches first"], None, "KUBE-EXT"),
    ("box", NET, "5. kube-proxy DNAT", [
        "KUBE-EXT-EIP2... marks for masquerade → KUBE-SVC-EIP2... → KUBE-SEP-...",
        "DNAT → gateway pod 10.42.0.88:8080"], None, "SNAT"),
    ("box", NET, "6. KUBE-POSTROUTING", [
        "MASQUERADE --random-fully: the source becomes 10.42.0.1.",
        "The svclb pod's host port DNAT never matches."], None, None),
]
col2 = [
    ("box", PROXY, "7. Gateway pod (Envoy)", [
        "Namespace shop-ingress, NOT in ambient mode.",
        "HTTPRoute match /* → frontend.shop:3000.",
        "Endpoint envoy://connect_originate/10.42.0.13:3000: Envoy itself opens HBONE "
        "(HTTP CONNECT over mTLS) to port 15008 of the frontend pod.",
        "Identity spiffe://cluster.local/ns/shop-ingress/sa/shop-gateway-istio"], None, "HBONE → :15008"),
    ("group", GREY, "8. Frontend pod netns", ["App listens on 3000."], [
        (PROXY, "ztunnel sockets live INSIDE the pod", [
            "15008 HBONE inbound, 15006 plaintext inbound, 15001 outbound, 15053 DNS."]),
        (SEC, "ztunnel inbound: L4 AuthorizationPolicy", [
            "Checks the policy, terminates mTLS, delivers to the app on :3000."])], "app makes a call"),
    ("box", NET, "9. Frontend app calls the backend", [
        "http://backend.shop.svc.cluster.local:8000",
        "DNS: iptables redirects it to 15053 (ztunnel DNS proxy).",
        "TCP: iptables REDIRECT --to-ports 15001.",
        "ztunnel's own traffic (mark 0x539) is exempt."], None, ":15001"),
    ("box", PROXY, "10. ztunnel outbound", [
        "The backend Service has istio.io/use-waypoint: waypoint",
        "→ HBONE mTLS to the waypoint pod :15008",
        "as spiffe://cluster.local/ns/shop/sa/frontend"], None, None),
]
col3 = [
    ("group", PROXY, "11. Waypoint (Envoy, L7)", [], [
        (SEC, "AuthorizationPolicy backend-allow-frontend", [
            "L7 check: only sa/frontend, GET/POST paths."]),
        (PROXY, "Route and record", [
            "HTTPRoute picks backend-v1 (weights), retries and timeouts.",
            "Writes metrics istio_requests_total and a trace span."])], "HBONE → :15008"),
    ("group", GREY, "12. Backend pod", [], [
        (SEC, "ztunnel inbound: backend-only-from-waypoint", ["L4 policy."]),
        (GREY, "App :8000", ["Calls Redis."])], "to Redis"),
    ("group", PROXY, "13. Backend → Redis", [
        "Redis has no waypoint, so ztunnel to ztunnel only (L4, mTLS)."], [
        (SEC, "redis-allow-backend", ["L4 policy."])], None),
]
b1, sp1 = column(cx[0], top, col1)
b2, sp2 = column(cx[1], top, col2)
b3, sp3 = column(cx[2], top, col3)

# column to column: from the right edge of the last hop, up the gutter, into the next column's first hop
for (sx_, spans_a), (nx, spans_b), lab in (((cx[0], sp1), (cx[1], sp2), "to gateway"),
                                            ((cx[1], sp2), (cx[2], sp3), "HBONE → waypoint :15008")):
    ya = (spans_a[-1][0] + spans_a[-1][1]) / 2
    yb = spans_b[0][0] + 30
    gx = sx_ + cw + cg / 2
    c.arrow([(sx_ + cw, ya), (gx, ya), (gx, yb), (nx, yb)], INK)

# return path and timing, under columns 1 and 3
ret_x = cx[2]
ret_bottom = c.box(ret_x, b3 + 40, cw, GREY, "14. Return path", [
    "Same connections in reverse: HBONE streams are bidirectional.",
    "conntrack undoes kube-proxy's SNAT and DNAT.",
    "nginx and Docker forward the bytes back to curl."], dashed=True)
tim_bottom = c.box(ret_x, ret_bottom + 30, cw, BLANK, "Measured trace (Jaeger) of one request", [
    "One POST /api/orders: gateway 18.5 ms in total, waypoint 7.4 ms, backend 5.5 ms, Redis 0.5 and 0.3 ms.",
    "The untraced Node.js frontend takes most of the gap; each mesh hop costs about a millisecond."])
down(cx[2] + 60, b3, b3 + 40, INK, "response")

# legend and security checkpoints under column 1
lg_y = b1 + 40
leg = [(CTRL, "control plane"), (STORE, "storage"), (NET, "kernel networking"), (PROXY, "proxies"),
       (SEC, "security decisions"), (EXT, "outside the cluster"), (GREY, "pods and apps")]
leg_h = 44 + 30 * ((len(leg) + 1) // 2) + 6
c.box(cx[0], lg_y, cw, BLANK, "Legend", h=leg_h)
for n, (col, label) in enumerate(leg):
    lx = cx[0] + 16 + (n % 2) * 260
    ly = lg_y + 40 + (n // 2) * 30
    c.box(lx, ly, 22, col, "", h=20)
    c.text(lx + 32, ly + 15, label, 14, INK)

sec_y = lg_y + leg_h + 24
sec_bottom = c.box(cx[0], sec_y, cw, SEC, "Security checkpoints, in order", [
    "1. RBAC + admission (control plane, steps 2 to 5)",
    "2. NetworkPolicy (kernel, plain path A)",
    "3. mTLS identity at every ztunnel hop",
    "4. L4 AuthorizationPolicy at ztunnel",
    "5. L7 AuthorizationPolicy at the waypoint"])

B_end = max(b2, tim_bottom, sec_bottom, A_end - 30) + 30
for i, end in ((band2, B_end), (band3, B_end)):
    b = c.boxes[i]
    c.boxes[i] = (b[0], b[1], b[2], end - b[1], b[4], b[5], b[6], b[7])

c.h = int(B_end + 40)

# warn about text that may not fit its box (rough widths: 14 px body, 16 px bold titles)
for x, y, w, h, col, title, lines, dashed in c.boxes:
    if title and len(title) * 9.4 > w - 20:
        print(f"title may overflow: {title!r}")
    for line in lines:
        if len(line) * 7.3 > w - 24:
            print(f"line may overflow: {line!r}")
    if x + w > c.w - 20 or y + h > c.h - 20:
        print(f"box near the canvas edge: {title!r}")
c.save(OUT, "life-of-a-request")
print(f"canvas {c.w} x {c.h}")
