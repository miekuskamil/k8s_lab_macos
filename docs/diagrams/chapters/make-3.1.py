#!/usr/bin/env python3
"""Draw the diagrams for course module 3.1 (what a mesh adds) with the kit in ../bbg.py.

  3.1-sidecar-vs-ambient   a proxy in every pod against a shared ztunnel per node and an optional waypoint
  3.1-ztunnel-choice       the three ways ztunnel sends the frontend's connection
  3.1-observability-tools  the five tools, the question each one answers, and the data they read

Run from anywhere: python3 docs/diagrams/chapters/make-3.1.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def modes():
    c = Canvas(1600, 1010)
    c.title("Two ways to put a", "proxy in the path")
    c.subtitle("Sidecar mode puts Envoy in every pod. Ambient mode shares one ztunnel per node and adds a waypoint for L7.")

    # sidecar mode: two containers per pod
    c.frame(40, 150, 1520, 300, "Sidecar mode: a proxy in every pod", "node")
    c.frame(80, 210, 600, 200, "frontend pod", "pod")
    a1 = c.box(110, 270, 230, 100, SLATE, "app")
    e1 = c.box(420, 270, 230, 100, BLUE, "Envoy", "L4 + L7")
    c.frame(920, 210, 600, 200, "backend pod", "pod")
    e2 = c.box(950, 270, 230, 100, BLUE, "Envoy", "L4 + L7")
    a2 = c.box(1260, 270, 230, 100, SLATE, "app")
    c.connect(a1, e1)
    c.connect(e1, e2, "mTLS, HTTP aware", pos="above")
    c.connect(e2, a2)

    # ambient mode: app-only pods above a shared ztunnel
    c.frame(40, 490, 1520, 480, "Ambient mode: shared proxies", "node")
    f = c.frame(80, 550, 330, 170, "frontend pod", "pod")
    c.box(110, 606, 270, 80, SLATE, "app only")
    w = c.frame(635, 550, 330, 170, "waypoint pod", "pod")
    c.box(665, 606, 270, 80, BLUE, "Envoy", "L7, only if needed")
    b = c.frame(1190, 550, 330, 170, "backend pod", "pod")
    c.box(1220, 606, 270, 80, SLATE, "app only")
    zt = c.band(80, 790, 1440, 150, BLUE, "ztunnel", "one per node, L4 and mTLS", "tunnel", lx=860, ly=838)

    y = 900
    c.line([(245, 720), (245, y), (760, y), (760, 720)], SLATE, AW, head=True)
    c.line([(840, 720), (840, y), (1355, y), (1355, 720)], SLATE, AW, head=True)
    c.chip(500, y, "HBONE", BLUE, anchor="middle")
    c.chip(1100, y, "HBONE", BLUE, anchor="middle")
    c.save(OUT, "3.1-sidecar-vs-ambient")


def choice():
    c = Canvas(1500, 1000)
    c.title("Where ztunnel", "sends it")
    c.subtitle("frontend dials backend:8000. ztunnel checks the table from istiod and picks one of three paths.")

    c.frame(40, 150, 440, 470, "frontend pod", "pod", right="network namespace")
    app = c.box(80, 210, 360, 100, SLATE, "app", "dials backend:8000")
    sock = c.node(80, 450, 360, 120, BLUE, "ztunnel", "tunnel", "socket :15001\ninside the pod")
    c.connect(app, sock, "caught", n=1)
    ist = c.node(80, 820, 360, 120, PURPLE, "istiod", "gear", "sends the table")
    c.connect(ist, sock, "address table", dashed=True, col=PURPLE)

    d1 = c.diamond(760, 510, 250, 150, TEAL, "In the\nmesh?")
    c.connect(sock, d1, "look up", n=2, sa="right", sb="left", at=(560, 510))
    plain = c.node(1080, 200, 380, 120, SLATE, "Plain TCP", "globe", "as without a mesh")
    c.connect(d1, plain, "no", sa="top", sb="left", pos="right", at=(760, 330))

    d2 = c.diamond(760, 790, 250, 150, TEAL, "use-\nwaypoint?")
    c.connect(d1, d2, "yes", sa="bottom", sb="top", pos="right")
    wp = c.node(1080, 450, 380, 120, BLUE, "Waypoint", "shield", "HBONE, L7 rules")
    c.connect(d2, wp, "yes: backend", sa="right", sb="bottom", pos="right", at=(1270, 660))
    dst = c.node(1080, 820, 380, 120, BLUE, "Destination pod", "tunnel", "HBONE to :15008")
    c.connect(d2, dst, "no: redis", sa="bottom", sb="left", at=(900, 880), pos="above")
    c.save(OUT, "3.1-ztunnel-choice")


def tools():
    c = Canvas(1600, 860)
    c.title("Five tools,", "five questions")
    c.subtitle("Pick the tool by the question you have. Each one reads data the mesh produces inside the cluster.")

    c.frame(40, 150, 300, 670, "Your Mac", "host")
    browser = c.node(70, 360, 240, 110, SLATE, "Browser", "globe")
    cli = c.node(70, 670, 240, 110, SLATE, "istioctl", "terminal", "which config now?")

    c.frame(380, 150, 1180, 670, "Cluster", "cluster")
    kiali = c.node(430, 200, 300, 110, TEAL, "Kiali", "eye", "what talks to what?")
    graf = c.node(430, 360, 300, 110, TEAL, "Grafana", "chart", "how bad, since when?")
    jaeg = c.node(430, 520, 300, 110, ORANGE, "Jaeger", "search", "where did time go?")
    prom = c.node(830, 200, 290, 110, ORANGE, "Prometheus", "db", "metrics")
    loki = c.node(830, 400, 290, 110, ORANGE, "Loki", "db", "what did pods print?")

    mesh = c.frame(1200, 190, 320, 440, "Mesh", "ns")
    for i, (lab, col) in enumerate([("frontend", SLATE), ("backend", SLATE), ("ztunnel", BLUE), ("waypoint", BLUE)]):
        c.box(1230, 240 + i * 92, 260, 66, col, lab)
    ist = c.node(1200, 670, 320, 110, PURPLE, "istiod", "gear", "pushes config")

    c.connect(mesh, prom, "metrics", sa="left", sb="right", fa=(255 - 190) / 440, pos="above", col=ORANGE)
    c.connect(mesh, loki, "logs", sa="left", sb="right", fa=(455 - 190) / 440, pos="above", col=ORANGE)
    c.connect(mesh, jaeg, "traces", sa="left", sb="right", fa=(590 - 190) / 440, fb=70 / 110, pos="above", col=ORANGE,
              at=(1000, 590))
    c.connect(prom, kiali, "reads", sa="left", sb="right", pos="above", dashed=True)
    c.connect(prom, graf, "", sa="left", sb="right", fa=0.8, fb=0.25, mid=780, dashed=True)
    c.connect(loki, graf, "", sa="left", sb="right", fa=0.3, fb=0.75, dashed=True)
    c.connect(jaeg, graf, "", sa="top", sb="bottom", fa=0.3, fb=0.3, dashed=True)
    c.connect(ist, mesh, "config", sa="top", sb="bottom", dashed=True, col=PURPLE)
    for t in (kiali, graf, jaeg):
        c.connect(browser, t, sa="right", sb="left", fa=0.5 + (t.cy - graf.cy) / 400, mid=375)
    c.connect(cli, ist, "asks istiod and the proxies", sa="right", sb="left", pos="above", at=(760, 725))
    c.save(OUT, "3.1-observability-tools")


if __name__ == "__main__":
    modes()
    choice()
    tools()
