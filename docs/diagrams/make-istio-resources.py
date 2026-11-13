#!/usr/bin/env python3
"""Draw "Istio in one picture" in ByteByteGo style (see bbg.py): the lab's request
path, with every Istio resource placed under the proxy that enforces it.

The circled numbers match "Follow one request" in course/start-here.md.

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


def resource(c, x, y, w, col, name, lines, module):
    h = 46 + 22 * len(lines)
    c.rect(x, y, w, h, col, "#2a2b33", rx=12, sw=2.5)
    c.rect(x, y + 12, 6, h - 24, col, col, rx=3, sw=1)
    c.text(x + 22, y + 32, name, 20, INK, True)
    c.text(x + w - 14, y + 31, module, 15, DIM, True, "end")
    for i, t in enumerate(lines):
        c.text(x + 22, y + 58 + i * 22, t, 16, SOFT)
    return y + h + 16


def column(c, x, y, w, title, items):
    top = y
    y += 30
    for col, name, lines, module in items:
        y = resource(c, x + 20, y, w - 40, col, name, lines, module)
    c.group(x, top, w, y - top + 14, title)


def picture():
    c = Canvas(1960, 1280)
    c.title("Istio in", "one picture")
    c.subtitle("Each resource you write acts at one proxy.")

    # control plane on top
    c.node(560, 175, 470, 110, PURPLE, "istiod", "gear", "config and certificates")
    c.node(60, 175, 300, 110, SLATE, "Browser", "laptop", "or curl, outside")
    c.node(1500, 175, 400, 110, SLATE, "httpbin.org", "globe", "outside the cluster")

    # request path
    y = 420
    c.node(60, y, 300, 120, BLUE, "Ingress\ngateway", "shield", "Envoy · north-south")
    c.node(450, y, 260, 120, SLATE, "frontend", "cube", "your pod")
    c.node(800, y, 300, 120, BLUE, "Waypoint", "shield", "Envoy · reads HTTP")
    c.group(1190, y - 20, 470, 160, "backend")
    c.node(1210, y, 205, 120, SLATE, "v1", "cube", "2 pods")
    c.node(1435, y, 205, 120, SLATE, "v2", "cube", "1 pod")
    c.node(1740, y, 185, 120, SLATE, "redis", None, "only the backend")
    c.step(60, y, 2)
    c.step(800, y, 5)

    c.arrow([(210, 285), (210, 420)], "HTTP", n=1, at=(210, 352), dashed=False)
    c.arrow([(1070, 420), (1070, 335), (1700, 335), (1700, 285)], "egress", n=7, at=(1400, 335), pos="above",
            col=SOFT)
    c.arrow([(1660, 480), (1740, 480)], "")

    # xDS from istiod to every proxy
    c.line([(600, 285), (600, 330), (330, 330), (330, 420)], PURPLE, 2.5, True, head=True)
    c.line([(900, 285), (900, 420)], PURPLE, 2.5, True, head=True)
    c.line([(775, 285), (775, 640)], PURPLE, 2.5, True, head=True)
    c.text(765, 400, "xDS", 17, "#b794f6", True, "end")

    # ztunnel: every hop between pods
    zy = 640
    c.node(60, zy, 1840, 100, BLUE, "ztunnel", "tunnel",
           "one per node · HBONE :15008 · L4 only")
    hops = [(300, zy, "down", 3, "HBONE"), (520, zy, "up", None, ""),
            (640, zy, "down", 4, "to backend"), (870, zy, "up", None, ""),
            (1040, zy, "down", 6, "HBONE"), (1310, zy, "up", None, "90%"), (1540, zy, "up", None, "10%")]
    for x, _, way, n, label in hops:
        if way == "down":
            c.arrow([(x, 540), (x, zy)], label, n=n, at=(x, 590), pos="right", dashed=False)
        else:
            c.arrow([(x, zy), (x, 540)], label, at=(x, 590), pos="right", dashed=False)

    # resources, grouped by the proxy that enforces them
    ry = 800
    column(c, 40, ry, 450, "2 · At the ingress gateway", [
        (TRAFFIC, "Gateway", ["ports 8080, 8443, TLS"], "M11"),
        (TRAFFIC, "HTTPRoute", ["path / to frontend"], ""),
        (SECURITY, "RequestAuthentication", ["checks user JWT"], "M13"),
        (SECURITY, "AuthorizationPolicy", ["token for /api/*"], "M13")])
    column(c, 510, ry, 470, "5 · At the waypoint", [
        (SECURITY, "AuthorizationPolicy L7", ["WHETHER: only sa/frontend"], "M3"),
        (TRAFFIC, "HTTPRoute / VirtualService", ["WHERE: 90/10 split"], "M4 M5"),
        (TRAFFIC, "DestinationRule", ["HOW: pool, ejection, TLS"], "M5 M12")])
    column(c, 1000, ry, 440, "3 · 6 · At ztunnel", [
        (SECURITY, "PeerAuthentication", ["STRICT: mTLS only"], "M2"),
        (SECURITY, "AuthorizationPolicy L4", ["only the waypoint"], "M3")])
    column(c, 1460, ry, 460, "7 · Leaving the mesh", [
        (TRAFFIC, "ServiceEntry", ["names httpbin.org"], "M12")])
    column(c, 1460, ry + 180, 460, "Every proxy", [
        (OBSERVE, "Telemetry", ["traces, logs, metrics"], "M6")])

    # legend
    lx, ly = 1010, 1090
    c.text(lx, ly, "Colours", 19, INK, True)
    items = [(SLATE, "your pod"), (BLUE, "proxy"), (PURPLE, "control plane"),
             (TRAFFIC, "traffic resource"), (SECURITY, "security resource"), (OBSERVE, "observability")]
    for i, (col, label) in enumerate(items):
        x = lx + (i % 2) * 210
        yy = ly + 32 + (i // 2) * 38
        c.rect(x, yy - 16, 22, 22, col, col, rx=5, sw=1)
        c.text(x + 32, yy + 1, label, 16, SOFT)
    c.text(lx, ly + 150, "M11 = course module 11", 16, DIM, True)
    c.save(OUT, "istio-resources")


if __name__ == "__main__":
    picture()
