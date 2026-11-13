#!/usr/bin/env python3
"""Draw the diagrams for course module 3 (authorization) in ByteByteGo style (see ../bbg.py).

  03-two-guards   the waypoint checks HTTP, the backend's ztunnel checks connections

Run from anywhere: python3 docs/diagrams/chapters/make-03.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def guards():
    c = Canvas(1780, 800)
    c.title("Two guards in front of", "the backend")
    c.subtitle("The waypoint checks each HTTP request. The backend's ztunnel checks each connection, even one that skips the waypoint.")

    c.node(60, 400, 340, 110, SLATE, "frontend", "cube", "sa/frontend")
    c.node(60, 650, 340, 110, SLATE, "course-client", "cube", "sa/course-client")

    c.outline(540, 210, 400, 96, RED, "backend-allow-frontend", "shield")
    c.node(540, 400, 400, 110, PURPLE, "Waypoint", "shield", "L7: who, method, path")
    c.line([(740, 306), (740, 400)], RED, 2.5, True)

    c.outline(1080, 210, 400, 96, RED, "backend-only-from-\nwaypoint", "shield")
    c.node(1080, 400, 400, 110, BLUE, "ztunnel", "tunnel", "L4 check")
    c.line([(1280, 306), (1280, 400)], RED, 2.5, True)

    c.node(1580, 400, 160, 110, SLATE, "backend", None, "pods")

    c.arrow([(400, 455), (540, 455)], "backend:8000", at=(470, 455), pos="above")
    c.arrow([(400, 680), (500, 680), (500, 490), (540, 490)], "backend:8000", at=(500, 590), pos="left", col=SOFT)
    c.arrow([(940, 455), (1080, 455)], "sa/waypoint", at=(1010, 455), pos="above")
    c.arrow([(1480, 455), (1580, 455)], "")
    c.arrow([(400, 730), (1280, 730), (1280, 510)], "pod IP:8000, skips the waypoint", at=(840, 730), pos="below", col=PINK)
    c.save(OUT, "03-two-guards")


if __name__ == "__main__":
    guards()
