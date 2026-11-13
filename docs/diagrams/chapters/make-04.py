#!/usr/bin/env python3
"""Draw the diagrams for course module 4 (traffic routing) in ByteByteGo style (see ../bbg.py).

  04-who-decides   kube-proxy spreads by pod count; the waypoint follows HTTPRoute weights

Run from anywhere: python3 docs/diagrams/chapters/make-04.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def who_decides():
    c = Canvas(1760, 820)
    c.title("Who decides where", "a request goes")
    c.subtitle("Without a mesh, each version's share follows its pod count. With a waypoint, a weight in the HTTPRoute decides.")

    c.group(40, 190, 800, 590, "Plain Kubernetes")
    c.node(280, 230, 320, 100, SLATE, "client", "cube")
    c.node(200, 410, 480, 110, GREEN, "Service backend", "gear", "random pod")
    c.arrow([(440, 330), (440, 410)], "")
    for i, (label, col) in enumerate([("v1 pod", SOFT), ("v1 pod", SOFT), ("v2 pod", TEAL)]):
        x = 75 + i * 250
        c.outline(x, 630, 230, 96, col, label, "cube")
        c.arrow([(440, 520), (x + 115, 630)], "")

    c.group(920, 190, 800, 590, "With a waypoint")
    c.node(1160, 230, 320, 100, SLATE, "client", "cube")
    c.node(1080, 410, 480, 110, PURPLE, "Waypoint", "shield", "HTTPRoute: weights, paths, headers")
    c.arrow([(1320, 330), (1320, 410)], "")
    c.outline(960, 630, 340, 96, SOFT, "Service\nbackend-v1", "gear")
    c.outline(1340, 630, 340, 96, TEAL, "Service\nbackend-v2", "gear")
    c.arrow([(1230, 520), (1130, 630)], "90%", at=(1160, 590), pos="left")
    c.arrow([(1410, 520), (1510, 630)], "10%", at=(1480, 590), pos="right")
    c.save(OUT, "04-who-decides")


if __name__ == "__main__":
    who_decides()
