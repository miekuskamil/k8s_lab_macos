#!/usr/bin/env python3
"""Draw the life-of-a-request diagrams in ByteByteGo style (see bbg.py).

  life-of-a-request       the big picture, used at the top of module 29
  life-1-control-plane    one write through the API server, then the watchers
  life-2-pod-startup      from a Deployment to a ready pod with endpoints
  life-3-plain-request    scenario A: client pod to nginx, no mesh
  life-4-ambient-request  scenario B: your Mac to Redis through the ambient mesh

The circled numbers match the numbered steps in docs/life-of-a-request.md and in
module 29. Addresses come from one test run of the lab.

Run from anywhere: python3 docs/diagrams/make-life-of-a-request.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def control_plane():
    c = Canvas(1700, 1010)
    c.title("One write,", "many watchers")
    c.subtitle("kubectl apply sends one HTTPS request. Three gates decide, storage keeps it, watchers react.")

    c.node(60, 205, 290, 100, SLATE, "kubectl", "laptop", "apply -f app.yaml")
    c.outline(60, 455, 290, 110, RED, "Refused\n401 · 403 · 422")

    c.group(410, 170, 540, 520, "API server")
    gates = [(205, RED, "Authentication", "lock", "Who are you?"),
             (365, RED, "Authorization", "shield", "May you do this?"),
             (525, PINK, "Admission", "gear", "Change it? Allow it?")]
    for i, (y, col, label, icon, sub) in enumerate(gates):
        c.node(450, y, 460, 110, col, label, icon, sub)
        c.step(450, y, i + 2)
        c.line([(450, y + 70), (350, 510)], RED, 2.5, True, head=True)
    for y in (315, 475):
        c.line([(680, y), (680, y + 50)], LINE, 2.5, head=True)

    c.arrow([(350, 255), (450, 255)], "", n=1, at=(400, 255))
    c.text(400, 300, "HTTPS", 17, SOFT, True, "middle")

    c.node(450, 790, 460, 110, ORANGE, "kine + SQLite", "db", "etcd in bigger clusters")
    c.arrow([(680, 635), (680, 790)], "Store it", n=5, at=(680, 735))

    c.group(1090, 170, 560, 790, "Watchers")
    watchers = [("Deployment controller", PURPLE, "gear"), ("ReplicaSet controller", PURPLE, "gear"),
                ("Scheduler", GREEN, "gear"), ("kubelet", TEAL, "server"),
                ("EndpointSlice controller", PURPLE, "gear"), ("kube-proxy · CoreDNS · istiod", BLUE, "globe")]
    for i, (label, col, icon) in enumerate(watchers):
        c.outline(1120, 200 + i * 124, 500, 96, col, label, icon)
    c.arrow([(910, 845), (1090, 845)], "Watch", n=6, at=(1000, 845), pos="above")

    c.note(60, 990, ["Each watcher writes its result back through steps 1 to 5."], 17)
    c.save(OUT, "life-1-control-plane")


def pod_startup():
    c = Canvas(1700, 1130)
    c.title("From a Deployment to a", "Ready Pod")
    c.subtitle("Each arrow is one component reacting to a change it watched. The whole chain took about two seconds.")

    top = 190
    c.node(60, top, 320, 100, SLATE, "Deployment", "doc", "hello, replicas: 1")
    c.node(560, top, 320, 100, SLATE, "ReplicaSet", "doc", "hello-76fb6c6b6f")
    c.node(1060, top, 320, 100, SLATE, "Pod", "cube", "no node yet")
    c.arrow([(380, top + 50), (560, top + 50)], "Deployment\ncontroller", n=1, at=(470, top + 50), pos="below")
    c.arrow([(880, top + 50), (1060, top + 50)], "ReplicaSet\ncontroller", n=2, at=(970, top + 50), pos="below")

    c.node(1060, 400, 320, 100, GREEN, "Scheduler", "gear", "filter · score · bind")
    c.arrow([(1220, top + 100), (1220, 400)], "Pick a node", n=3, at=(1220, 345))

    c.node(1060, 590, 320, 100, TEAL, "kubelet", "server", "on the chosen node")
    c.arrow([(1220, 500), (1220, 590)], "watch: a pod for me", at=(1222, 560), col=SOFT)

    c.group(60, 560, 860, 330, "Pod sandbox on the node")
    c.outline(95, 600, 380, 100, ORANGE, "Sandbox\npause container", "cube")
    c.outline(505, 600, 380, 100, TEAL, "flannel\nIP 10.42.0.197", "globe")
    c.outline(95, 750, 380, 100, BLUE, "istio-cni\nambient only", "lock")
    c.outline(505, 750, 380, 100, GREEN, "Containers\nstart · probe", "cube")
    c.step(505, 600, 5)
    c.step(505, 750, 6)
    c.arrow([(1060, 640), (920, 640)], "containerd\n(CRI)", n=4, at=(990, 640), pos="below")

    c.node(60, 990, 400, 100, PURPLE, "EndpointSlice", "gear", "10.42.0.197 ready")
    c.arrow([(260, 890), (260, 990)], "Ready", n=7, at=(260, 940))

    c.group(560, 965, 1080, 150, "Watchers update")
    for i, (label, col, icon) in enumerate([("kube-proxy", TEAL, "server"), ("CoreDNS", TEAL, "dns"), ("istiod", BLUE, "gear")]):
        c.outline(590 + i * 345, 1000, 315, 90, col, label, icon)
    c.arrow([(460, 1040), (560, 1040)], "")
    c.save(OUT, "life-2-pod-startup")


def plain_request():
    c = Canvas(1700, 990)
    c.title("Scenario A:", "No Mesh")
    c.subtitle("curl http://hello from a client pod. The node's kernel does all the work, with rules kube-proxy wrote.")

    c.group(40, 160, 1620, 640, "Node k3d-k8s-lab-server-0")
    c.node(90, 220, 360, 110, SLATE, "client pod", "cube", "10.42.0.198")
    c.node(90, 600, 360, 110, TEAL, "CoreDNS", "dns", "10.43.0.10")
    c.arrow([(170, 330), (170, 600)], "Where is\nhello?", n=1, at=(170, 465))
    c.arrow([(370, 600), (370, 330)], "10.43.76.137", at=(370, 470), pos="right", col=SOFT)

    c.node(650, 220, 420, 110, GREEN, "Kernel: iptables", "gear", "rules from kube-proxy")
    c.arrow([(450, 275), (650, 275)], "Connect to\n10.43.76.137", n=2, at=(550, 275), pos="above")

    c.node(1250, 220, 360, 110, SLATE, "hello pod", "cube", "nginx · 10.42.0.197")
    c.arrow([(1070, 275), (1250, 275)], "DNAT to\n10.42.0.197", n=3, at=(1160, 275), pos="above")

    c.node(650, 520, 420, 110, ORANGE, "conntrack", "db", "the kernel's notebook")
    c.arrow([(860, 330), (860, 520)], "writes down\nthe rewrite", at=(940, 430), pos="right", col=SOFT)
    c.arrow([(1430, 330), (1430, 575), (1070, 575)], "Reply", n=4, at=(1430, 455))
    c.arrow([(650, 575), (450, 300)], "source restored:\n10.43.76.137", at=(560, 520), pos="left", col=SOFT)

    c.text(60, 860, "What nobody checked", 21, INK, True)
    for i, t in enumerate(["No identity", "No encryption", "No policy", "No request metrics"]):
        c.outline(60 + i * 405, 880, 375, 76, RED, t)
    c.save(OUT, "life-3-plain-request")


def ambient_request():
    c = Canvas(1800, 1180)
    c.title("Scenario B:", "Through the Mesh")
    c.subtitle("curl localhost:8080/api/orders on your Mac. Every hop inside the cluster is an mTLS tunnel with two checked identities.")

    c.node(60, 170, 300, 100, SLATE, "Your Mac", "laptop", "curl :8080")
    c.node(560, 170, 320, 100, SLATE, "k3d serverlb", "server", "nginx, TCP only")
    c.node(1080, 170, 360, 100, GREEN, "Node kernel", "gear", "DNAT + SNAT")
    c.arrow([(360, 220), (560, 220)], "Docker\nport 8080", n=1, at=(460, 220), pos="below")
    c.arrow([(880, 220), (1080, 220)], "to node :8080", at=(980, 205), pos="above", col=SOFT)

    c.node(1080, 380, 360, 110, BLUE, "Gateway", "shield", "Envoy · shop-ingress")
    c.arrow([(1260, 270), (1260, 380)], "kube-proxy:\nto 10.42.0.88", n=2, at=(1260, 325))

    c.group(60, 360, 900, 170, "frontend pod")
    c.outline(85, 400, 260, 96, BLUE, "ztunnel\n:15001 out", "tunnel")
    c.outline(370, 400, 260, 96, SLATE, "frontend\napp :3000", "cube")
    c.outline(655, 400, 280, 96, BLUE, "ztunnel\n:15008 in", "tunnel")
    c.arrow([(1080, 435), (935, 435)], "HBONE", n=3, at=(1008, 435), pos="above")
    c.line([(655, 448), (630, 448)], LINE, 2.5, head=True)
    c.line([(370, 448), (345, 448)], LINE, 2.5, head=True)

    c.node(60, 640, 380, 110, PURPLE, "Waypoint", "shield", "L7 policy · routing")
    c.arrow([(215, 496), (215, 640)], "HBONE to\nthe waypoint", n=4, at=(215, 568))

    c.group(560, 620, 860, 170, "backend-v1 pod")
    c.outline(585, 660, 260, 96, BLUE, "ztunnel\n:15008 in", "tunnel")
    c.outline(870, 660, 260, 96, SLATE, "backend\napp :8000", "cube")
    c.outline(1155, 660, 240, 96, BLUE, "ztunnel\n:15001 out", "tunnel")
    c.arrow([(440, 708), (585, 708)], "Allowed", n=5, at=(512, 708), pos="above")
    c.line([(845, 708), (870, 708)], LINE, 2.5, head=True)
    c.line([(1130, 708), (1155, 708)], LINE, 2.5, head=True)

    c.node(1500, 650, 260, 110, SLATE, "Redis", "db", "10.42.0.14")
    c.arrow([(1395, 708), (1500, 708)], "", n=6, at=(1448, 708))
    c.text(1448, 760, "HBONE", 17, SOFT, True, "middle")

    c.node(60, 880, 380, 100, PURPLE, "istiod", "gear", "config + certificates")
    c.arrow([(250, 880), (250, 750)], "xDS", at=(290, 815), pos="right", col=SOFT)

    c.group(540, 870, 1220, 250, "Identities checked on the way")
    rows = ["shop-gateway-istio  →  frontend", "frontend  →  waypoint", "waypoint  →  backend", "backend  →  redis"]
    for i, t in enumerate(rows):
        c.step(590, 920 + i * 48, ["3", "4", "5", "6"][i])
        c.text(625, 927 + i * 48, t, 19, INK, True)
    c.outline(1250, 915, 480, 150, GREEN, "Back through\nthe same tunnels", "tunnel")
    c.step(1250, 915, 7)
    c.save(OUT, "life-4-ambient-request")


def overview():
    c = Canvas(1800, 1060)
    c.title("The Life of a", "Request")
    c.subtitle("Part 1 builds the pod. Scenario A and B send a request to it: once without a mesh, once through it.")

    def column(x, title, rows, col_title):
        c.group(x, 170, 540, 850, title)
        y = 215
        for i, (label, col, icon, sub) in enumerate(rows):
            c.node(x + 40, y, 460, 100, col, label, icon, sub, size=22)
            c.step(x + 40, y, i + 1)
            if i < len(rows) - 1:
                c.line([(x + 270, y + 100), (x + 270, y + 158)], LINE, 2.5, True, head=True)
            y += 158

    column(40, "1 · A pod comes to life", [
        ("kubectl", SLATE, "laptop", "sends the Deployment"),
        ("API server", RED, "lock", "who? allowed? valid?"),
        ("kine + SQLite", ORANGE, "db", "stores the object"),
        ("Controllers", PURPLE, "gear", "ReplicaSet, then Pod"),
        ("Scheduler + kubelet", TEAL, "server", "node, sandbox, IP, start")], SLATE)
    column(630, "A · No mesh", [
        ("client pod", SLATE, "cube", "curl http://hello"),
        ("CoreDNS", TEAL, "dns", "name to ClusterIP"),
        ("Kernel iptables", GREEN, "gear", "DNAT to the pod"),
        ("hello pod", SLATE, "cube", "plain TCP, no identity"),
        ("conntrack", ORANGE, "db", "restores the reply")], SLATE)
    column(1220, "B · Ambient mesh", [
        ("Your Mac", SLATE, "laptop", "curl :8080"),
        ("Gateway", BLUE, "shield", "Envoy, opens HBONE"),
        ("ztunnel", BLUE, "tunnel", "mTLS in every pod"),
        ("Waypoint", PURPLE, "shield", "L7 policy, routing"),
        ("backend → Redis", SLATE, "db", "identity at every hop")], SLATE)
    c.save(OUT, "life-of-a-request")


if __name__ == "__main__":
    overview()
    control_plane()
    pod_startup()
    plain_request()
    ambient_request()
