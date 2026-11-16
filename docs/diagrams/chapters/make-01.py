#!/usr/bin/env python3
"""Draw the diagrams for course module 1 (what a mesh adds) with the kit in ../bbg.py.

  01-sidecar-vs-ambient    a proxy in every pod against a shared ztunnel per node and an optional waypoint
  01-ztunnel-choice        the three ways ztunnel sends the frontend's connection

Run from anywhere: python3 docs/diagrams/chapters/make-01.py
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
    c.save(OUT, "01-sidecar-vs-ambient")


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
    c.save(OUT, "01-ztunnel-choice")


if __name__ == "__main__":
    modes()
    choice()
