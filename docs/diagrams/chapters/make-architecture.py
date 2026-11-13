#!/usr/bin/env python3
"""Draw the diagrams in docs/architecture.md in ByteByteGo style (see ../bbg.py).

  chapters/architecture-request-path   how one request travels, hops 1 to 9
  ../traffic-flow                      trust zones and which hops are encrypted
  ../gitops-flow                       how a git push reaches the cluster

Arrow styles: thick blue = mTLS tunnel, solid = plaintext, dashed = control and telemetry.

Run from anywhere: python3 docs/diagrams/chapters/make-architecture.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent
DIAGRAMS = OUT.parent


def shorten(pts, d=12):
    (x0, y0), (x1, y1) = pts[-2], pts[-1]
    length = max(1, ((x1 - x0) ** 2 + (y1 - y0) ** 2) ** 0.5)
    return pts[:-1] + [(x1 - (x1 - x0) * d / length, y1 - (y1 - y0) * d / length)]


def tunnel(c, pts, label="", n=None, at=None, pos="right"):
    """mTLS hop: thick blue line."""
    c.line(shorten(pts), BLUE, 7)
    c.arrow(pts, label, n=n, at=at, dashed=False, col=BLUE, pos=pos)


def plain(c, pts, label="", n=None, at=None, pos="right"):
    c.arrow(pts, label, n=n, at=at, dashed=False, col=LINE, pos=pos)


def control(c, pts, label="", at=None, pos="right"):
    c.arrow(pts, label, at=at, col=DIM, pos=pos)


def legend(c, x, y):
    c.text(x, y, "Arrows", 19, INK, True)
    c.line([(x, y + 34), (x + 60, y + 34)], BLUE, 7)
    c.text(x + 80, y + 40, "mTLS tunnel (HBONE)", 17, SOFT)
    c.line([(x, y + 74), (x + 60, y + 74)], LINE, 2.5)
    c.text(x + 80, y + 80, "plaintext", 17, SOFT)
    c.line([(x, y + 114), (x + 60, y + 114)], DIM, 2.5, True)
    c.text(x + 80, y + 120, "control, telemetry", 17, SOFT)


def request_path():
    c = Canvas(2000, 1560)
    c.title("How a request", "travels")
    c.subtitle("From the browser to Redis in nine hops.")

    c.node(60, 190, 320, 100, SLATE, "Browser", "laptop", "localhost:8080")
    c.node(60, 400, 320, 110, SLATE, "k3d load\nbalancer", "server", ":8080 to :8080")
    plain(c, [(220, 290), (220, 400)], "HTTP", n=1, at=(220, 345))

    c.group(440, 370, 360, 170, "shop-ingress")
    c.node(470, 400, 300, 110, BLUE, "shop-gateway", "shield", "Envoy, outside mesh", size=23)
    plain(c, [(380, 455), (470, 455)], "", n=2, at=(425, 455))
    c.text(425, 560, "TCP :8080", 17, SOFT, True, "middle")

    c.group(880, 160, 270, 880, "istio-system")
    c.node(895, 190, 240, 100, PURPLE, "istiod", "gear", "xDS :15012")
    c.node(905, 350, 220, 660, BLUE, "ztunnel", "tunnel", "HBONE :15008")
    tunnel(c, [(770, 455), (905, 455)], "HBONE", n=3, at=(838, 455), pos="above")

    c.group(1310, 330, 650, 720, "shop · ambient")
    apps = [(360, "frontend", ":3000"), (540, "waypoint", "Envoy · HBONE :15008"),
            (720, "backend-v1", "2 pods · :8000"), (900, "backend-v2", "1 pod · :8000")]
    for y, label, sub in apps:
        col, icon = (BLUE, "shield") if label == "waypoint" else (SLATE, "cube")
        c.node(1340, y, 300, 100, col, label, icon, sub, size=23)
    mid = 1232
    plain(c, [(1125, 390), (1340, 390)], "deliver", n=4, at=(mid, 390), pos="above")
    plain(c, [(1340, 440), (1125, 440)], "HTTP :8000\ncaptured", n=5, at=(mid, 440), pos="below")
    tunnel(c, [(1125, 570), (1340, 570)], "HBONE", n=6, at=(mid, 570), pos="above")
    tunnel(c, [(1340, 620), (1125, 620)], "HBONE, 90/10", n=7, at=(mid, 620), pos="below")
    plain(c, [(1125, 770), (1340, 770)], "deliver", n=8, at=(mid, 770), pos="above")
    plain(c, [(1125, 950), (1340, 950)], "deliver", n=8, at=(mid, 950), pos="above")

    c.node(1740, 800, 200, 100, ORANGE, "redis", "db", ":6379")
    tunnel(c, [(1640, 770), (1740, 828)], "", n=9, at=(1690, 799))
    tunnel(c, [(1640, 950), (1740, 872)], "", n=9, at=(1690, 911))
    c.text(1840, 935, "L4 mTLS", 17, SOFT, True, "middle")

    control(c, [(895, 240), (720, 240), (720, 400)], "xDS", at=(810, 240), pos="above")
    control(c, [(1015, 290), (1015, 350)], "certs, config", at=(1015, 322))
    control(c, [(1135, 240), (1765, 240), (1765, 590), (1640, 590)], "xDS", at=(1400, 240), pos="above")

    c.group(1310, 1190, 650, 330, "observability · ambient")
    c.outline(1340, 1225, 280, 100, GREEN, "Prometheus\n:9090", "eye")
    c.outline(1660, 1225, 270, 100, GREEN, "Jaeger\n:16686", "eye")
    c.outline(1340, 1400, 280, 90, ORANGE, "Alertmanager\n:9093")
    c.outline(1660, 1400, 270, 90, GREEN, "Grafana\n:3000", "eye")
    control(c, [(1480, 1325), (1480, 1400)], "alerts", at=(1480, 1362))
    control(c, [(1660, 1445), (1620, 1445), (1620, 1325)], "")
    c.text(1612, 1385, "PromQL", 16, SOFT, True, "end")
    control(c, [(1795, 1400), (1795, 1325)], "trace lookup", at=(1795, 1362))
    control(c, [(1420, 1225), (1420, 1050)], "scrape\nwaypoint, backend-v1", at=(1420, 1120), pos="left")
    control(c, [(1880, 1050), (1880, 1225)], "OTLP traces", at=(1880, 1120), pos="left")

    c.group(60, 1250, 380, 170, "argocd")
    c.node(90, 1280, 320, 110, PURPLE, "ArgoCD", "gear", ":8081")
    c.node(620, 1280, 320, 110, SLATE, "GitHub", "globe", "k8s_lab_macos, main")
    plain(c, [(410, 1335), (620, 1335)], "git poll, sync", at=(515, 1335), pos="above")

    legend(c, 60, 680)
    c.save(OUT, "architecture-request-path")


def trust_zones():
    c = Canvas(2100, 1310)
    c.title("Traffic flow and", "trust zones")
    c.subtitle("On blue hops the receiver checks the identity on the label.")

    c.group(30, 180, 330, 1100, "macOS host")
    c.node(60, 340, 270, 100, SLATE, "Browser", "laptop", "localhost:8080")
    legend(c, 60, 560)
    c.note(60, 760, ["Pod to ztunnel never", "leaves the pod."], 17)

    c.group(400, 180, 1670, 1100, "OrbStack · k3d cluster k8s-lab")
    c.node(430, 340, 280, 110, SLATE, "k3d load\nbalancer", "server", ":8080")
    plain(c, [(330, 390), (430, 390)], "HTTP", at=(380, 380), pos="above")

    c.group(750, 240, 1290, 1010, "k3s node container")
    c.group(790, 300, 290, 170, "shop-ingress · outside mesh")
    c.node(810, 340, 250, 100, BLUE, "shop-gateway", "shield", "Envoy :8080")
    plain(c, [(710, 390), (810, 390)], "TCP", at=(760, 380), pos="above")
    c.text(935, 500, "nothing checked", 16, SOFT, True, "middle")

    c.group(1210, 300, 790, 400, "shop · ambient", col=GREEN)
    c.node(1240, 340, 260, 100, SLATE, "frontend", "cube", ":3000")
    c.node(1710, 340, 260, 100, BLUE, "waypoint", "shield", "Envoy")
    c.node(1710, 560, 260, 110, SLATE, "backend", "cube", "v1 x2 · v2 x1")
    c.node(1240, 560, 260, 110, ORANGE, "redis", "db", ":6379")
    tunnel(c, [(1060, 390), (1240, 390)])
    c.text(1145, 470, "gateway SA", 16, INK, True, "middle")
    tunnel(c, [(1500, 390), (1710, 390)], "shop/frontend", at=(1605, 390), pos="above")
    tunnel(c, [(1840, 440), (1840, 560)], "shop/\nwaypoint", at=(1840, 500), pos="left")
    tunnel(c, [(1710, 615), (1500, 615)], "shop/backend", at=(1605, 615), pos="above")
    c.text(1605, 655, "L4 only", 16, SOFT, True, "middle")

    y2 = 870
    c.group(790, y2, 480, 330, "istio-system")
    c.node(815, y2 + 50, 210, 100, PURPLE, "istiod", "gear", "xDS :15012", size=22)
    c.node(1045, y2 + 50, 205, 100, BLUE, "ztunnel", "tunnel", "one per node", size=22)
    control(c, [(920, y2 + 150), (920, y2 + 210), (1147, y2 + 210), (1147, y2 + 150)], "xDS, certs",
            at=(1033, y2 + 210), pos="below")

    c.group(1340, y2, 660, 330, "observability · ambient", col=GREEN)
    c.outline(1370, y2 + 40, 270, 90, GREEN, "Prometheus\n:9090", "eye")
    c.outline(1700, y2 + 40, 270, 90, GREEN, "Jaeger\n:16686", "eye")
    c.outline(1540, y2 + 210, 270, 90, GREEN, "Grafana\n:3000", "eye")
    control(c, [(1610, y2 + 210), (1560, y2 + 130)], "PromQL", at=(1585, y2 + 170), pos="left")
    control(c, [(1740, y2 + 210), (1790, y2 + 130)], "traces", at=(1765, y2 + 170))
    tunnel(c, [(1430, y2 + 40), (1430, 700)], "scrape\nPrometheus SA",
           at=(1430, 775), pos="right")
    control(c, [(1930, 670), (1930, y2 + 40)], "OTLP\ntraces", at=(1930, 775), pos="left")
    c.save(DIAGRAMS, "traffic-flow")


def gitops():
    c = Canvas(1900, 1300)
    c.title("From git push to", "live cluster")
    c.subtitle("ArgoCD polls GitHub, creates the child Applications and applies them.")

    c.node(60, 190, 240, 100, SLATE, "You", "person", "edit manifests")
    c.node(420, 190, 360, 100, SLATE, "GitHub", "globe", "k8s_lab_macos, main")
    plain(c, [(300, 240), (420, 240)], "git push", n=1, at=(360, 240), pos="below")

    c.group(40, 380, 1820, 885, "k3d cluster k8s-lab")
    c.group(410, 610, 380, 170, "argocd")
    c.node(430, 640, 340, 110, PURPLE, "Application\nroot", "gear", "manifests/argocd/apps", size=22)
    plain(c, [(700, 640), (700, 290)], "poll repo", n=2, at=(700, 465))

    c.group(890, 420, 560, 720, "Child Applications")
    kids = [("shop-base", "namespaces, RBAC, quotas", PURPLE),
            ("shop-apps", "frontend, backend, redis", PURPLE),
            ("istio-config", "gateway, waypoint, routes", PINK),
            ("kube-prometheus-stack", "Helm chart", PURPLE),
            ("observability-config", "Jaeger, monitors, dashboard", PURPLE),
            ("loki · alloy · kiali", "three more Helm charts", PURPLE)]
    for i, (name, sub, col) in enumerate(kids):
        y = 450 + i * 113
        c.rect(920, y, 500, 92, col, "#2a2b33", rx=12, sw=2.5)
        c.text(944, y + 38, name, 20, INK, True)
        c.text(944, y + 68, sub, 17, SOFT)
    c.text(1405, 450 + 2 * 113 + 38, "no selfHeal", 16, PINK, True, "end")
    plain(c, [(770, 695), (890, 695)], "create\nchild apps", n=3, at=(830, 695), pos="below")

    c.node(1550, 640, 270, 110, GREEN, "Live\ncluster state", "cube", size=22)
    tunnel(c, [(1450, 695), (1550, 695)], "apply", n=4, at=(1500, 695), pos="below")
    c.arrow([(1685, 750), (1685, 1180), (600, 1180), (600, 750)], "drift report", n=5, at=(1150, 1180),
            col=DIM, pos="below")

    c.note(80, 450, ["istio-config does", "not self-heal."], 17)
    c.save(DIAGRAMS, "gitops-flow")


if __name__ == "__main__":
    request_path()
    trust_zones()
    gitops()
