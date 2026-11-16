#!/usr/bin/env python3
"""Draw "Istio in one picture" with the kit in bbg.py: the lab's request
path, with every Istio resource placed under the proxy that enforces it.

The circled numbers match "Follow one request" in platform-engineering/start-here.md.

Writes istio-resources.svg (shown on GitHub and in the course) and
istio-resources.excalidraw (open and edit at https://excalidraw.com).

Run from anywhere: python3 docs/diagrams/make-istio-resources.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent

TRAFFIC, SECURITY, OBSERVE = TEAL, RED, GREEN


def card(c, x, y, w, col, name, line, module):
    c.rect(x, y, w, 64, col, WHITE, 10, 1.6)
    c.rect(x, y + 10, 5, 44, col, col, 2, 0)
    c.text(x + 18, y + 27, name, 17, INK, True)
    c.text(x + 18, y + 51, line, 15, SOFT)
    if module:
        c.text(x + w - 12, y + 27, module, 13, DIM, True, "end")
    return y + 74


def column(c, x, y, w, title, items):
    c.text(x, y, title, 17, SOFT, True)
    y += 14
    for col, name, line, module in items:
        y = card(c, x, y, w, col, name, line, module)
    return y


def picture():
    c = Canvas(1600, 1300)
    c.title("Istio in", "one picture")
    c.subtitle("Each resource you write acts at one proxy. istiod turns them into proxy config.")

    c.frame(40, 150, 260, 170, "Your Mac", "host")
    br = c.box(65, 205, 210, 90, SLATE, "Browser", "or curl")
    c.frame(1300, 150, 260, 170, "Internet", "plain", icon="globe")
    web = c.box(1325, 205, 210, 90, SLATE, "httpbin.org")

    c.frame(40, 360, 1520, 910, "Cluster", "cluster")
    c.frame(960, 390, 300, 120, "namespace istio-system", "ns")
    ist = c.box(980, 440, 260, 56, PURPLE, "istiod", size=18)

    c.frame(70, 540, 1460, 400, "Node", "node")
    c.frame(95, 590, 250, 200, "shop-ingress", "ns")
    gw = c.box(115, 650, 210, 110, BLUE, "ingress\ngateway", "Envoy")
    c.frame(370, 590, 1135, 200, "namespace shop", "ns", right="your pods and the waypoint")
    fe = c.box(390, 650, 190, 110, SLATE, "frontend", "your pod")
    wp = c.box(620, 650, 230, 110, BLUE, "waypoint", "Envoy, reads HTTP")
    v1 = c.box(890, 650, 180, 110, SLATE, "backend v1", "2 pods")
    v2 = c.box(1090, 650, 180, 110, SLATE, "backend v2", "1 pod")
    rd = c.box(1310, 650, 175, 110, ORANGE, "redis", "only the backend")
    zt = c.band(95, 820, 1410, 100, BLUE, "ztunnel", "per node, HBONE :15008", "tunnel", lx=1220, ly=870)

    def hop(xa, xb, y, n=None, label=""):
        c.line([(xa, 760), (xa, y), (xb, y), (xb, 760)], BLUE, 4, head=True)
        if n:
            c.step((xa + xb) / 2, y, n)

    hop(270, 440, 845, 3)
    hop(530, 680, 845, 4)
    hop(800, 960, 845, 6)
    hop(800, 1180, 870)
    c.connect(br, gw, "HTTP :8080", n=1, sa="bottom", sb="top", fa=0.5, fb=(170 - 115) / 210, pos="right",
              at=(170, 470))
    c.step(gw.x, gw.y, 2)
    c.step(wp.x, wp.y, 5)
    c.connect(wp, web, "egress", n=7, sa="top", sb="left", fa=0.7, fb=0.5, pos="above", at=(1000, 250))
    c.connect(ist, Box(70, 540, 1460, 400), "xDS, certificates", sa="bottom", sb="top", fb=(1110 - 70) / 1460, dashed=True, col=PURPLE,
              pos="right")

    y = 990
    column(c, 70, y, 300, "2  at the ingress gateway", [
        (TRAFFIC, "Gateway", "ports 8080, 8443, TLS", "M11"),
        (TRAFFIC, "HTTPRoute", "path / to frontend", ""),
        (SECURITY, "RequestAuthentication", "checks the user's JWT", "M13")])
    column(c, 400, y, 340, "5  at the waypoint", [
        (SECURITY, "AuthorizationPolicy L7", "whether: only sa/frontend", "M3"),
        (TRAFFIC, "HTTPRoute, VirtualService", "where: 90/10 split", "M4"),
        (TRAFFIC, "DestinationRule", "how: pool, ejection, TLS", "M5")])
    column(c, 770, y, 330, "3, 4, 6  at ztunnel", [
        (SECURITY, "PeerAuthentication", "STRICT: mTLS only", "M2"),
        (SECURITY, "AuthorizationPolicy L4", "only the waypoint", "M3")])
    column(c, 1130, y, 400, "7  leaving the mesh, and every proxy", [
        (TRAFFIC, "ServiceEntry", "names httpbin.org", "M12"),
        (OBSERVE, "Telemetry", "traces, logs, metrics", "M6")])
    c.legend(770, 1220, [(BLUE, "mTLS hop through ztunnel"), (PURPLE, "config", True)])
    c.save(OUT, "istio-resources")


if __name__ == "__main__":
    picture()
