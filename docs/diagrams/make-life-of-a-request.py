#!/usr/bin/env python3
"""Draw the life-of-a-request diagrams with the kit in bbg.py.

  life-of-a-request       the big picture, used at the top of module 3.15
  life-1-control-plane    one write through the API server, then the watchers
  life-2-pod-startup      from a Deployment to a ready pod with endpoints
  life-3-plain-request    scenario A: client pod to nginx, no mesh
  life-4-ambient-request  scenario B: your Mac to Redis through the ambient mesh

The circled numbers match the numbered steps in docs/life-of-a-request.md and in
module 3.15. Addresses come from one test run of the lab.

Run from anywhere: python3 docs/diagrams/make-life-of-a-request.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def control_plane():
    c = Canvas(1600, 960)
    c.title("One write,", "many watchers")
    c.subtitle("kubectl apply sends one HTTPS request. Three gates decide, storage keeps it, watchers react.")

    c.frame(40, 150, 270, 260, "Your Mac", "host")
    kc = c.node(60, 210, 230, 110, SLATE, "kubectl", "terminal", "apply -f app.yaml")
    c.frame(350, 150, 760, 790, "control plane: k3s server", "group")
    c.frame(380, 200, 700, 560, "API server", "plain", col=PURPLE, icon="server")
    g1 = c.box(520, 260, 400, 100, RED, "authentication", "who are you?")
    g2 = c.box(520, 400, 400, 100, RED, "authorization", "Node authorizer, RBAC")
    g3 = c.box(520, 540, 400, 120, PINK, "admission", "mutating, schema,\nvalidating webhooks")
    for i, g in enumerate((g1, g2, g3)):
        c.step(g.x, g.y, i + 2)
    c.connect(g1, g2)
    c.connect(g2, g3)
    kine = c.node(520, 810, 400, 100, ORANGE, "kine + SQLite", "db", "etcd in bigger clusters")
    c.connect(g3, kine, "store", n=5, pos="right", at=(720, 785))
    c.connect(kc, g1, "HTTPS", n=1, sa="right", sb="left", fa=0.4, fb=0.3, pos="above", at=(340, 254))
    # refusals go straight back
    for g in (g1, g2, g3):
        c.line([(g.x, g.cy + 22), (440, g.cy + 22)], RED, 1.8, True)
    c.line([(440, 622), (440, 320), (290, 320)], RED, 1.8, True, head=True)
    c.text(455, 720, "refused:", 16, DEEP[RED], True)
    c.text(455, 742, "401, 403, 400/422", 16, DEEP[RED], True)

    c.frame(1150, 150, 410, 790, "watchers", "group")
    ws = [("Deployment controller", PURPLE, "gear"), ("ReplicaSet controller", PURPLE, "gear"),
          ("Scheduler", GREEN, "filter"), ("kubelet", TEAL, "server"),
          ("EndpointSlice controller", PURPLE, "gear"), ("kube-proxy, CoreDNS, istiod", BLUE, "globe")]
    for i, (t, col, ic) in enumerate(ws):
        c.node(1180, 200 + i * 120, 350, 96, col, t, ic, size=19)
    c.connect(Box(380, 200, 700, 560), Box(1150, 150, 410, 790), "watch", n=6, sa="right", sb="left", fa=0.5,
              fb=(480 - 150) / 790, pos="above")
    c.note(1180, 925, "Each writes its result back through steps 1 to 5.", 15)
    c.save(OUT, "life-1-control-plane")


def pod_startup():
    c = Canvas(1600, 1000)
    c.title("From a Deployment to a", "ready pod")
    c.subtitle("Each arrow is one component reacting to a change it watched. The whole chain took about two seconds.")

    c.frame(40, 150, 720, 500, "control plane", "group")
    api = c.node(70, 210, 230, 400, PURPLE, "API server", "server")
    ctl = [(1, "Deployment ctrl", "creates ReplicaSet", PURPLE, "gear"),
           (2, "ReplicaSet ctrl", "creates Pod, no node", PURPLE, "gear"),
           (3, "Scheduler", "binds Pod to a node", GREEN, "filter"),
           (7, "EndpointSlice ctrl", "adds the pod's IP", PURPLE, "gear")]
    for i, (n, t, sub, col, ic) in enumerate(ctl):
        y = 210 + i * 105
        b = c.node(400, y, 330, 85, col, t, ic, sub, size=19)
        c.step(b.x, b.y, n)
        c.line([(400, y + 42), (300, y + 42)], LINE, AW, head=True)

    c.frame(820, 150, 740, 810, "Node", "node")
    kub = c.node(850, 210, 300, 100, TEAL, "kubelet", "server", "a pod for me")
    ctd = c.node(1220, 210, 310, 100, TEAL, "containerd", "box", "CRI")
    c.connect(kub, ctd, "sandbox", n=4, pos="above")
    pod = c.frame(850, 370, 680, 300, "pod sandbox", "pod", right="its own netns")
    c.box(875, 425, 200, 90, ORANGE, "pause", "holds namespaces")
    c.box(1100, 425, 405, 90, GREEN, "eth0", "10.42.0.197/24")
    ctr = c.box(875, 545, 630, 95, SLATE, "nginx container", "readiness probe GET /")
    c.step(ctr.x, ctr.y, 6)
    cni = c.band(850, 710, 680, 90, GREEN, "CNI plugins", "flannel gives the IP, istio-cni adds rules", "plug")
    c.line([(1300, 710), (1300, 515)], GREEN, AW, head=True)
    c.step(1300, 690, 5)
    c.connect(ctd, cni, "", sa="right", sb="right", fa=0.8, fb=0.5, mid=1545)
    c.frame(850, 820, 680, 130, "watchers update", "plain")
    for i, t in enumerate(["kube-proxy", "CoreDNS", "istiod"]):
        c.box(870 + i * 220, 862, 200, 70, BLUE if t == "istiod" else TEAL, t, size=18)
    c.line([(300, 610), (300, 897), (850, 897)], DIM, AW, dashed=True, head=True)
    c.step(560, 897, 7)
    c.line([(185, 610), (185, 700), (835, 700), (835, 260), (850, 260)], DIM, AW, dashed=True, head=True)
    c.text(520, 690, "watch: a pod bound to this node", 16, SOFT, True, "middle", halo=True)
    c.save(OUT, "life-2-pod-startup")


def plain_request():
    c = Canvas(1600, 960)
    c.title("Scenario A:", "no mesh")
    c.subtitle("curl http://hello from a client pod. The node's kernel does the work, with rules kube-proxy wrote.")

    c.frame(40, 150, 1520, 760, "", "node", right="Node k3d-k8s-lab-server-0")
    cl = c.frame(80, 230, 360, 160, "client pod", "pod")
    c.box(100, 280, 320, 80, SLATE, "curl http://hello", "10.42.0.198")
    dns = c.frame(620, 230, 360, 160, "CoreDNS pod", "pod", right="kube-system")
    c.box(640, 280, 320, 80, TEAL, "DNS", "10.43.0.10")
    hp = c.frame(1150, 230, 370, 160, "hello pod", "pod")
    c.box(1170, 280, 330, 80, SLATE, "nginx", "10.42.0.197:80")
    c.connect(cl, dns, "hello?", n=1, sa="right", sb="left", fa=0.35, fb=0.35, pos="above")
    c.connect(dns, cl, "10.43.76.137", sa="left", sb="right", fa=0.75, fb=0.75, pos="below", dashed=True)

    c.frame(70, 470, 1460, 410, "", "plain", col=GREEN)
    c.text(95, 860, "kernel: rules kube-proxy wrote", 17, DEEP[GREEN], True)
    s1 = c.box(100, 540, 300, 90, GREEN, "KUBE-SERVICES", "10.43.76.137:80?", size=17)
    s2 = c.box(460, 540, 300, 90, GREEN, "KUBE-SVC-...", "pick an endpoint", size=17)
    s3 = c.box(820, 540, 300, 90, GREEN, "KUBE-SEP-...", "DNAT to 10.42.0.197", size=17)
    ct = c.box(460, 720, 660, 110, ORANGE, "conntrack", "10.42.0.198 to 10.43.76.137 = 10.42.0.197", size=19)
    c.connect(cl, s1, "", n=2, sa="bottom", sb="top", fa=(200 - 80) / 360, fb=(200 - 100) / 300, at=(200, 430))
    c.connect(s1, s2)
    c.connect(s2, s3)
    c.connect(s3, hp, "", n=3, sa="right", sb="bottom", fa=0.5, fb=(1300 - 1150) / 370, at=(1300, 430))
    c.connect(s3, ct, "writes", sa="bottom", sb="top", fa=0.5, fb=(970 - 460) / 660, dashed=True, pos="right")
    c.line([(1420, 390), (1420, 775), (1120, 775)], SLATE, AW, dashed=True, head=True)
    c.line([(460, 775), (430, 775), (430, 390)], SLATE, AW, dashed=True, head=True)
    c.step(1420, 600, 4)
    c.text(1445, 606, "reply", 17, INK, True, halo=True)
    c.note(100, 945, "Nobody checked an identity, encrypted the bytes, applied a policy or counted the request.", 17)
    c.save(OUT, "life-3-plain-request")


def ambient_request():
    c = Canvas(1600, 1060)
    c.title("Scenario B:", "through the mesh")
    c.subtitle("curl localhost:8080/api/orders on your Mac. Every hop inside the cluster is an mTLS tunnel.")

    c.frame(40, 150, 260, 220, "Your Mac", "host")
    curl = c.box(65, 215, 210, 100, SLATE, "curl", ":8080")
    c.frame(340, 150, 1220, 880, "OrbStack", "host", icon="box")
    lb = c.node(380, 200, 300, 110, SLATE, "k3d serverlb", "server", "nginx, TCP only")
    c.connect(curl, lb, "Docker :8080", n=1, sa="right", sb="left", fa=0.4, fb=0.4, pos="above", at=(340, 240))

    c.frame(370, 350, 1160, 650, "", "node", right="node container k3d-k8s-lab-server-0")
    k = c.band(400, 400, 1100, 80, GREEN, "kernel", "kube-proxy: DNAT to the gateway pod, SNAT", "filter", lx=700)
    c.connect(lb, k, "", sa="bottom", sb="top", fa=0.5, fb=(530 - 400) / 1100)
    c.frame(400, 520, 230, 250, "shop-ingress", "ns")
    gw = c.box(415, 580, 200, 150, BLUE, "gateway", "Envoy, opens\nHBONE")
    c.line([(590, 480), (590, 580)], LINE, AW, head=True)
    c.step(590, 530, 2)

    c.frame(660, 520, 840, 250, "namespace shop", "ns", right="ambient")
    fe = c.frame(680, 580, 250, 160, "frontend pod", "pod")
    c.box(700, 625, 210, 50, SLATE, "app :3000", size=16)
    c.chip(805, 705, "ztunnel :15001 :15008", BLUE, anchor="middle", size=12)
    wp = c.box(960, 580, 170, 160, BLUE, "waypoint", "L7 policy,\nrouting")
    be = c.frame(1160, 580, 170, 160, "backend", "pod")
    c.box(1175, 625, 140, 60, SLATE, "app :8000", size=16)
    rd = c.box(1350, 580, 130, 160, ORANGE, "redis", ":6379")
    c.band(400, 810, 1100, 170, BLUE, "ztunnel", "one per node, sockets in each pod", "tunnel", lx=410, ly=935)

    def hop(xa, xb, y, n):
        c.line([(xa, 740), (xa, y), (xb, y), (xb, 740)], BLUE, 4, head=True)
        c.step((xa + xb) / 2, y, n)

    hop(560, 740, 840, 3)
    hop(870, 1000, 840, 4)
    hop(1090, 1220, 870, 5)
    hop(1290, 1400, 900, 6)
    c.text(1480, 955, "7  the response returns through the same tunnels", 15, SOFT, True, "end")
    c.save(OUT, "life-4-ambient-request")


def overview():
    c = Canvas(1600, 1100)
    c.title("The life of a", "request")
    c.subtitle("Part 1 builds the pod. Scenarios A and B send a request to it: once without a mesh, once through it.")

    c.frame(40, 150, 260, 900, "Your Mac", "host")
    kc = c.box(65, 220, 210, 90, SLATE, "kubectl", "apply")
    cu = c.box(65, 840, 210, 90, SLATE, "curl", "localhost:8080")

    c.frame(340, 150, 1220, 900, "Cluster", "cluster")
    c.frame(370, 190, 1160, 210, "control plane", "group")
    api = c.box(400, 250, 260, 110, PURPLE, "API server", "who? allowed? valid?")
    c.box(700, 250, 230, 110, ORANGE, "kine + SQLite", "stores it")
    c.box(970, 250, 250, 110, PURPLE, "controllers", "ReplicaSet, Pod")
    c.box(1260, 250, 240, 110, GREEN, "scheduler", "picks the node")

    c.frame(370, 440, 1160, 580, "Node", "node")
    kub = c.box(400, 500, 260, 100, TEAL, "kubelet", "sandbox, IP, start")
    c.frame(700, 480, 800, 150, "namespace course-life", "ns")
    cl = c.box(720, 530, 180, 80, SLATE, "client pod")
    dns = c.box(930, 530, 180, 80, TEAL, "CoreDNS")
    hello = c.box(1140, 530, 180, 80, SLATE, "hello pod")
    c.frame(400, 660, 1100, 170, "namespaces shop-ingress and shop", "ns")
    gw = c.box(420, 715, 190, 90, BLUE, "gateway")
    fe = c.box(640, 715, 190, 90, SLATE, "frontend")
    wp = c.box(860, 715, 190, 90, BLUE, "waypoint")
    be = c.box(1080, 715, 190, 90, SLATE, "backend")
    rd = c.box(1300, 715, 180, 90, ORANGE, "redis")
    c.band(400, 860, 540, 130, GREEN, "kernel", "iptables, conntrack", "filter")
    c.band(960, 860, 540, 130, BLUE, "ztunnel", "mTLS between pods", "tunnel")

    P1, PA, PB = PURPLE, SLATE, BLUE
    c.connect(kc, api, "", sa="right", sb="left", fa=0.5, fb=(265 - 250) / 110, col=P1)
    c.connect(api, kub, "", col=P1, dashed=True)
    c.connect(cl, dns, "", col=PA)
    c.line([(810, 610), (810, 650), (1230, 650), (1230, 610)], PA, AW, head=True)
    c.line([(275, 885), (420, 885)], PB, 3.5, head=False)
    c.line([(420, 885), (515, 885), (515, 805)], PB, 3.5, head=True)
    c.chip(1230, 650, "via iptables DNAT", SLATE, anchor="middle", size=13, mono=False)
    for xa, xb in ((610, 640), (830, 860), (1050, 1080), (1270, 1300)):
        c.line([(xa, 760), (xb, 760)], PB, 3.5, head=True)
    c.legend(440, 1035, [(P1, "Part 1: a pod comes to life"), (PA, "A: no mesh"), (PB, "B: ambient mesh")])
    c.save(OUT, "life-of-a-request")


if __name__ == "__main__":
    overview()
    control_plane()
    pod_startup()
    plain_request()
    ambient_request()
