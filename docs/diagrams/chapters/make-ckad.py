#!/usr/bin/env python3
"""Draw the diagrams for the application modules (platform-engineering/practice-cluster.md and modules 33 to 37) with the kit in ../bbg.py.

  ckad-practice-cluster   the practice cluster with the application extras (practice-cluster.md)
  ckad-image-flow         Dockerfile to registry to node, the four steps of tasks 1 and 2 (01)
  ckad-pod-patterns       init container, native sidecar and app in one pod (01)
  ckad-rolling-update     a Deployment moving pods from one ReplicaSet to the next (02)
  ckad-blue-green-canary  one Service selector, two release patterns (02)
  ckad-probes             the kubelet's three probes and what each failure does (03)
  ckad-rbac               a pod's ServiceAccount, a RoleBinding and a Role in another namespace (04)
  ckad-requests-limits    LimitRange, ResourceQuota and the container's requests and limits (04)
  ckad-ingress-path       one request from outside through ingress-nginx and a Service to a pod (05)
  ckad-netpol-selectors   which peers a NetworkPolicy's from-list lets in (05)

Run from anywhere: python3 docs/diagrams/chapters/make-ckad.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def practice_cluster():
    c = Canvas(1600, 900)
    c.title("The application", "extras")
    c.subtitle("The practice cluster with helm, podman, a registry and metrics-server.")

    c.frame(40, 150, 1520, 720, "Your Mac", "host")
    you = c.node(70, 220, 200, 110, SLATE, "terminal", "terminal", "./lab.sh practice")

    c.frame(350, 200, 1180, 640, "Docker engine", "plain", icon="box")
    cp = c.frame(380, 250, 560, 420, "practice-control-plane", "node")
    c.box(405, 300, 510, 80, PURPLE, "static pods", "API server, etcd, scheduler")
    tools = c.frame(405, 410, 510, 230, "in the node image", "group")
    c.box(430, 455, 220, 70, SLATE, "helm 4.3.1", size=17)
    c.box(670, 455, 220, 70, SLATE, "podman", "build, push", size=17)
    c.box(430, 545, 220, 70, SLATE, "kubectl-convert", size=16)
    reg = c.node(380, 700, 440, 100, ORANGE, "registry.practice:5000", "db", "container practice-registry", size=20)

    w1 = c.frame(980, 250, 520, 560, "practice-worker", "node")
    pods = c.box(1005, 300, 470, 90, SLATE, "your task pods", "every namespace practice=task")
    ms = c.box(1005, 420, 225, 80, TEAL, "metrics-server", size=16)
    ing = c.box(1250, 420, 225, 80, BLUE, "ingress-nginx", "NodePort 30080", size=16)
    ctd = c.node(1005, 700, 470, 100, TEAL, "containerd", "box", "pulls over plain HTTP")

    c.connect(you, cp, "shell", sa="right", sb="left", fa=0.5, fb=(275 - 250) / 420, pos="above")
    c.connect(ctd, reg, "pull image", sa="left", sb="right", fa=0.5, fb=0.5, pos="above")
    c.connect(ctd, pods, "start", sa="top", sb="bottom", fa=0.5, fb=0.5, pos="right", at=(1240, 600))
    c.save(OUT, "ckad-practice-cluster")


def image_flow():
    c = Canvas(1600, 760)
    c.title("From Dockerfile", "to a running pod")
    c.subtitle("The image travels by name: registry host, repository, tag.")

    cp = c.frame(40, 150, 700, 560, "practice-control-plane", "node")
    df = c.node(70, 220, 300, 110, SLATE, "Dockerfile", "doc", "and greet.sh")
    pm = c.node(420, 220, 290, 110, SLATE, "podman", "terminal", "build, then push")
    store = c.frame(70, 400, 640, 140, "podman's local store", "plain", icon="layers")
    for i, t in enumerate(["busybox layer", "COPY layer", "RUN layer"]):
        c.box(95 + i * 205, 445, 185, 70, ORANGE, t, size=16)
    reg = c.node(70, 580, 640, 100, ORANGE, "registry.practice:5000", "db", "greeter:v1, greeter:v2")

    w1 = c.frame(800, 150, 760, 560, "practice-worker", "node")
    kub = c.node(830, 220, 300, 110, TEAL, "kubelet", "server", "a pod needs the image")
    ctd = c.node(1200, 220, 330, 110, TEAL, "containerd", "box", "pulls the layers")
    pod = c.frame(830, 400, 330, 190, "pod greeter", "pod")
    ctr = c.box(855, 450, 280, 90, SLATE, "greeter", "hello from greeter")

    c.connect(df, pm, "reads", sa="right", sb="left", pos="above")
    c.connect(pm, store, "build", n=1, sa="bottom", sb="top", fa=0.5, fb=(565 - 70) / 640, pos="right")
    c.connect(store, reg, "push", n=2, sa="bottom", sb="top", fa=0.5, fb=0.5, pos="right")
    c.connect(kub, ctd, "", n=3, pos="above")
    c.connect(ctd, reg, "pull", n=4, sa="bottom", sb="right", fa=0.6, fb=0.7, pos="above",
              via=[(1398, 650)])
    c.connect(ctd, ctr, "start", sa="bottom", sb="right", fa=0.15, fb=0.5, pos="right")
    c.save(OUT, "ckad-image-flow")


def pod_patterns():
    c = Canvas(1600, 820)
    c.title("Several containers,", "one pod")
    c.subtitle("They share the pod's network and its volumes. The init list starts first, in order.")

    c.frame(40, 150, 1520, 640, "", "node", right="Node practice-worker")
    pod = c.frame(80, 190, 1440, 560, "pod pipeline", "pod")
    init = c.frame(110, 240, 720, 240, "initContainers, in order", "group")
    fetch = c.outline(140, 290, 280, 150, SLATE, "fetch", "box", sub="runs, exits 0", size=20)
    side = c.outline(520, 290, 280, 150, BLUE, "exporter", "box", sub="restartPolicy: Always", size=20)
    main = c.frame(890, 240, 600, 240, "containers", "group")
    tr = c.outline(980, 290, 420, 150, SLATE, "transform", "box", sub="the app, writes output.txt", size=20)
    c.step(fetch.x, fetch.y, 1)
    c.step(side.x, side.y, 2)
    c.step(tr.x, tr.y, 3)
    vol = c.band(110, 540, 1380, 70, ORANGE, "emptyDir volume work, mounted at /work in all three", size=18)
    net = c.band(110, 640, 1380, 70, GREEN, "the pod's network: one IP, localhost shared", size=18)
    c.connect(fetch, side, "then", pos="above")
    c.connect(side, tr, "then", pos="above")
    for b in (fetch, side, tr):
        c.line([(b.cx, b.b), (b.cx, vol.y)], ORANGE, 1.8, dashed=True)
    c.connect(tr, side, "GET :8080", sa="bottom", sb="bottom", fa=0.8, fb=0.8, pos="below", mid=505, col=BLUE)
    c.save(OUT, "ckad-pod-patterns")


def rolling_update():
    c = Canvas(1600, 820)
    c.title("A rolling update,", "one pod at a time")
    c.subtitle("maxSurge 1, maxUnavailable 0: a new pod first, then an old one goes.")

    c.frame(40, 150, 1520, 640, "namespace rollout", "ns")
    dep = c.node(560, 200, 480, 100, PURPLE, "Deployment web", "gear", "replicas: 3, nginx:1.28")
    old = c.frame(80, 360, 640, 260, "ReplicaSet web-64fc (revision 1)", "plain", col=SLATE, fill=WHITE)
    new = c.frame(880, 360, 640, 260, "ReplicaSet web-66bc (revision 2)", "plain", col=PURPLE, fill=WHITE)
    for i in range(3):
        c.box(110 + i * 200, 420, 180, 80, SLATE, "pod", "1.27", size=18)
    c.box(110 + 2 * 200, 520, 180, 70, RED, "stopping", size=16)
    for i in range(2):
        c.box(910 + i * 200, 420, 180, 80, PURPLE, "pod", "1.28, ready", size=18)
    c.box(1310, 420, 180, 80, PURPLE, "pod", "starting", size=18)
    c.connect(dep, old, "scale down to 0", n=2, sa="bottom", sb="top", fa=0.2, fb=0.5, pos="left")
    c.connect(dep, new, "scale up to 3", n=1, sa="bottom", sb="top", fa=0.8, fb=0.5, pos="right")
    svc = c.node(560, 670, 480, 90, BLUE, "Service web", "plug", "every ready pod of both")
    c.connect(svc, old, "", sa="left", sb="bottom", fa=0.5, fb=0.5, dashed=True, col=BLUE)
    c.connect(svc, new, "", sa="right", sb="bottom", fa=0.5, fb=0.5, dashed=True, col=BLUE)
    c.save(OUT, "ckad-rolling-update")


def blue_green_canary():
    c = Canvas(1600, 860)
    c.title("One selector,", "two release patterns")
    c.subtitle("A Service sends requests to every ready pod whose labels match its selector.")

    bg = c.frame(40, 150, 740, 680, "blue-green: namespace bluegreen", "ns")
    s1 = c.node(160, 210, 500, 100, BLUE, "Service shop", "plug", "version: blue, then green")
    blue = c.frame(70, 400, 320, 300, "shop-blue", "plain", col=SLATE, fill=WHITE)
    green = c.frame(430, 400, 320, 300, "shop-green", "plain", col=GREEN, fill=WHITE)
    for i in range(3):
        c.box(95, 450 + i * 78, 270, 62, SLATE, "version=blue", size=16)
        c.box(455, 450 + i * 78, 270, 62, GREEN, "version=green", size=16)
    c.connect(s1, blue, "before", n=1, sa="bottom", sb="top", fa=0.2, fb=0.5, pos="left", dashed=True)
    c.connect(s1, green, "after the switch", n=2, sa="bottom", sb="top", fa=0.8, fb=0.5, pos="right")

    ca = c.frame(820, 150, 740, 680, "canary: namespace canary", "ns")
    s2 = c.node(940, 210, 500, 100, BLUE, "Service front", "plug", "app: front")
    v1 = c.frame(850, 400, 400, 400, "front-v1: 4 pods", "plain", col=SLATE, fill=WHITE)
    v2 = c.frame(1290, 400, 240, 400, "front-v2: 1 pod", "plain", col=ORANGE, fill=WHITE)
    for i in range(4):
        c.box(875, 450 + i * 82, 350, 64, SLATE, "app=front, v1", size=16)
    c.box(1310, 450, 200, 64, ORANGE, "app=front, v2", size=16)
    c.connect(s2, v1, "4 in 5", sa="bottom", sb="top", fa=0.3, fb=0.5, pos="left")
    c.connect(s2, v2, "1 in 5", sa="bottom", sb="top", fa=0.85, fb=0.5, pos="right")
    c.save(OUT, "ckad-blue-green-canary")


def probes():
    c = Canvas(1600, 860)
    c.title("Three probes,", "three reactions")
    c.subtitle("The kubelet asks; a Service and the kubelet itself act on the answers.")

    c.frame(40, 150, 1060, 680, "", "node", right="Node practice-worker")
    kub = c.node(80, 200, 300, 110, TEAL, "kubelet", "server", "runs every probe")
    pod = c.frame(470, 200, 590, 320, "pod api", "pod")
    ctr = c.box(500, 260, 530, 100, SLATE, "container", "httpd on :8080")
    st = c.box(500, 400, 160, 80, PINK, "startup", "/live", size=17)
    lv = c.box(685, 400, 160, 80, RED, "liveness", "TCP 8080", size=17)
    rd = c.box(870, 400, 160, 80, BLUE, "readiness", "/ready", size=17)
    c.step(st.x, st.y, 1)
    c.step(rd.x, rd.y, 2)
    c.step(lv.x, lv.y, 3)
    c.connect(kub, ctr, "asks", sa="right", sb="left", fa=0.5, fb=0.5, pos="above")

    restart = c.box(700, 620, 300, 100, RED, "restart container", "RESTARTS + 1", size=18)
    c.connect(lv, restart, "fails 3 times", sa="bottom", sb="top", fa=0.5, fb=(765 - 700) / 300, pos="right")
    wait = c.box(400, 620, 260, 100, PINK, "wait, then kill", "after 30 x 2s", size=18)
    c.connect(st, wait, "keeps failing", sa="bottom", sb="top", fa=0.5, fb=(580 - 400) / 260, pos="left")

    c.frame(1140, 150, 420, 680, "control plane", "group")
    eps = c.node(1170, 380, 360, 110, BLUE, "EndpointSlice", "list", "ready pods only")
    svc = c.node(1170, 600, 360, 110, BLUE, "Service api", "plug", "routes to them")
    c.connect(rd, eps, "in or out", sa="right", sb="left", fa=0.5, fb=(440 - 380) / 110, pos="above")
    c.connect(eps, svc, "", pos="right")
    c.save(OUT, "ckad-probes")


def rbac():
    c = Canvas(1600, 800)
    c.title("Who may do what:", "RBAC for a pod")
    c.subtitle("The pod's token names its ServiceAccount. A RoleBinding in the target namespace grants the Role.")

    obs = c.frame(40, 150, 560, 610, "namespace observer", "ns")
    pod = c.frame(70, 210, 500, 220, "pod watcher", "pod")
    app = c.box(95, 260, 450, 70, SLATE, "wget with the token", size=18)
    tok = c.box(95, 345, 450, 60, ORANGE, "token: observer:watcher", size=16)
    sa = c.node(70, 560, 500, 110, TEAL, "ServiceAccount watcher", "person", "the pod's identity")
    c.connect(sa, tok, "mounted into", sa="top", sb="bottom", pos="right")

    api = c.frame(650, 150, 300, 610, "API server", "plain", col=PURPLE, icon="server")
    an = c.box(680, 260, 240, 80, RED, "authenticate", "who?", size=18)
    az = c.box(680, 420, 240, 80, RED, "authorize", "may it?", size=18)
    c.connect(an, az, "", n=2)
    c.connect(app, an, "list pods", n=1, sa="right", sb="left", fa=0.5, fb=(295 - 260) / 80, pos="above",
              at=(612, 295))

    sf = c.frame(1000, 150, 560, 610, "namespace shop-front", "ns")
    rb = c.node(1030, 210, 500, 110, PINK, "RoleBinding", "lock", "subject: observer:watcher")
    role = c.node(1030, 400, 500, 110, PINK, "Role pod-reader", "list", "get, list on pods")
    pods = c.box(1030, 600, 500, 100, SLATE, "pods cart-...", "what the token may list", size=18)
    c.connect(rb, role, "grants", pos="right")
    c.connect(az, rb, "finds", n=3, sa="right", sb="left", fa=0.3, fb=0.5, pos="above", mid=965)
    c.connect(role, pods, "covers", pos="right", dashed=True)
    c.save(OUT, "ckad-rbac")


def requests_limits():
    c = Canvas(1600, 820)
    c.title("Requests, limits", "and the namespace's rules")
    c.subtitle("Admission fills in defaults, then checks the totals. The scheduler and the kernel use the numbers.")

    c.frame(40, 150, 300, 200, "Your terminal", "host")
    you = c.box(65, 215, 250, 90, SLATE, "kubectl apply", "pod, no resources", size=17)
    api = c.frame(380, 150, 760, 380, "API server admission, namespace limits", "plain", col=PURPLE, icon="server")
    lr = c.box(410, 230, 330, 110, PINK, "LimitRange", "fills in defaults,\nrefuses above max", size=18)
    rq = c.box(780, 230, 330, 110, PINK, "ResourceQuota", "adds to the totals,\nrefuses past hard", size=18)
    c.connect(lr, rq, "", n=2)
    c.connect(you, lr, "", n=1, sa="right", sb="left", fa=0.5, fb=(260 - 230) / 110, at=(360, 260))
    ref = c.box(780, 400, 330, 90, RED, "403 exceeded quota", size=17)
    c.connect(rq, ref, "over", sa="bottom", sb="top", pos="right")
    sch = c.node(1190, 230, 370, 110, PURPLE, "scheduler", "gear", "fits requests to nodes")
    c.connect(rq, sch, "stored", n=3, pos="above")
    c.frame(380, 580, 1180, 200, "", "node", right="Node practice-worker")
    ctr = c.box(420, 640, 420, 100, SLATE, "container", "requests 100m, limit 200m", size=18)
    ker = c.band(900, 630, 620, 120, GREEN, "kernel cgroups", "CPU above limit waits, memory above limit is killed",
                 size=18)
    c.connect(sch, ctr, "binds pod", n=4, sa="bottom", sb="top", fa=0.5, fb=0.5, pos="right",
              via=[(1375, 560), (630, 560)])
    c.connect(ctr, ker, "", n=5)
    c.save(OUT, "ckad-requests-limits")


def ingress_path():
    c = Canvas(1600, 820)
    c.title("One request", "through Ingress")
    c.subtitle("The Host header and the path pick a Service. The Service picks a ready pod.")

    c.frame(40, 150, 300, 220, "practice-control-plane, or a browser", "host")
    cl = c.box(65, 220, 250, 100, SLATE, "curl", "Host: shop.ckad.local", size=18)
    c.frame(380, 150, 1180, 640, "", "node", right="Node practice-worker")
    np = c.box(420, 220, 240, 100, GREEN, "NodePort 30080", "kube-proxy", size=18)
    ctl = c.frame(720, 190, 380, 280, "pod ingress-nginx-controller", "pod")
    ng = c.box(745, 240, 330, 100, BLUE, "nginx", "rules from Ingress", size=18)
    rule = c.box(745, 360, 330, 80, PINK, "Ingress shop", "/ to web, /api to api", size=16)
    c.connect(rule, ng, "", sa="top", sb="bottom", dashed=True, col=PINK)
    eps = c.box(1160, 220, 360, 100, BLUE, "EndpointSlice api", "ready pod IPs", size=18)
    pod = c.frame(1160, 520, 360, 220, "pod api", "pod")
    ctr = c.box(1185, 580, 310, 100, SLATE, "httpd :8080", "/api/orders", size=18)
    c.connect(cl, np, "", n=1, sa="right", sb="left", fa=0.5, fb=0.5, at=(360, 270))
    c.connect(np, ng, "", n=2, pos="above")
    c.connect(ng, eps, "looks up", n=3, pos="above")
    c.connect(eps, ctr, "to pod IP", n=4, sa="bottom", sb="top", pos="right")
    c.save(OUT, "ckad-ingress-path")


def netpol_selectors():
    c = Canvas(1600, 860)
    c.title("NetworkPolicy:", "who gets in")
    c.subtitle("One from-entry with both selectors means AND. Two entries mean OR.")

    m = c.frame(40, 150, 700, 340, "namespace np-monitoring, team=monitoring", "ns")
    pr = c.box(70, 230, 300, 90, SLATE, "app=prometheus", size=18)
    gr = c.box(410, 230, 300, 90, SLATE, "app=grafana", size=18)
    d = c.frame(40, 530, 700, 300, "namespace np-dev, team=dev", "ns")
    pd = c.box(70, 610, 300, 90, SLATE, "app=prometheus", size=18)

    t = c.frame(860, 150, 700, 680, "namespace np-metrics", "ns")
    pol = c.box(890, 220, 640, 150, RED, "allow-prometheus", "from: namespaceSelector team=monitoring\n      AND podSelector app=prometheus",
                size=18)
    ex = c.frame(990, 470, 440, 260, "pod exporter", "pod")
    srv = c.box(1015, 530, 390, 100, SLATE, "httpd :9100", size=18)
    c.connect(pr, srv, "allowed", sa="bottom", sb="left", fa=0.5, fb=0.25, pos="above",
              via=[(220, 400), (960, 400), (960, 555)])
    c.line([(710, 275), (800, 275)], RED, AW, dashed=True)
    c.mark(800, 275, ok=False)
    c.text(800, 320, "wrong pod", 16, DEEP[RED], True, "middle", halo=True)
    c.line([(370, 655), (800, 655)], RED, AW, dashed=True)
    c.mark(800, 655, ok=False)
    c.text(800, 700, "wrong namespace", 16, DEEP[RED], True, "middle", halo=True)
    c.save(OUT, "ckad-netpol-selectors")


if __name__ == "__main__":
    for f in (practice_cluster, image_flow, pod_patterns, rolling_update, blue_green_canary, probes,
              rbac, requests_limits, ingress_path, netpol_selectors):
        f()
