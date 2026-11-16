#!/usr/bin/env python3
"""Draw the diagrams for course module 4 (traffic routing) with the kit in ../bbg.py.

  04-who-decides   kube-proxy spreads by pod count; the waypoint follows HTTPRoute weights

Run from anywhere: python3 docs/diagrams/chapters/make-04.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def who_decides():
    c = Canvas(1600, 860)
    c.title("Who decides where", "a request goes")
    c.subtitle("Without a mesh, each version's share follows its pod count. With a waypoint, a weight in the HTTPRoute decides.")

    # plain Kubernetes: the kernel picks a pod at random
    c.frame(40, 150, 740, 670, "Plain Kubernetes", "node")
    cl = c.box(280, 210, 260, 76, SLATE, "client")
    svc = c.band(80, 370, 660, 100, GREEN, "Service backend", "iptables picks a random pod", "gear")
    c.connect(cl, svc)
    for i, v in enumerate(["v1", "v1", "v2"]):
        x = 80 + i * 230
        p = c.frame(x, 600, 200, 170, "pod", "pod")
        c.box(x + 25, 650, 150, 80, SLATE if v == "v1" else TEAL, "backend", v)
        c.connect(svc, p, "33%", sa="bottom", sb="top", fa=(x + 100 - 80) / 660, pos="right")

    # with a waypoint: a weight in the HTTPRoute
    c.frame(820, 150, 740, 670, "With a waypoint", "node")
    cl2 = c.box(1060, 210, 260, 76, SLATE, "client")
    wp = c.node(860, 350, 660, 140, BLUE, "Waypoint", "shield", "HTTPRoute: 90 to v1, 10 to v2")
    c.connect(cl2, wp)
    s1 = c.frame(860, 580, 440, 210, "Service backend-v1", "ns")
    for i in range(2):
        c.box(885 + i * 205, 640, 185, 110, SLATE, "pod", "v1")
    s2 = c.frame(1330, 580, 190, 210, "backend-v2", "ns")
    c.box(1352, 640, 146, 110, TEAL, "pod", "v2")
    c.connect(wp, s1, "90%", sa="bottom", sb="top", fa=(1080 - 860) / 660, fb=0.5, pos="right")
    c.connect(wp, s2, "10%", sa="bottom", sb="top", fa=(1425 - 860) / 660, fb=0.5, pos="right")
    c.save(OUT, "04-who-decides")


if __name__ == "__main__":
    who_decides()
