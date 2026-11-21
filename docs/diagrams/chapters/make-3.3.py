#!/usr/bin/env python3
"""Draw the diagrams for course module 3.3 (authorization) with the kit in ../bbg.py.

  03-two-guards   the waypoint checks HTTP, the backend's ztunnel checks connections

Run from anywhere: python3 docs/diagrams/chapters/make-3.3.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def guards():
    c = Canvas(1600, 840)
    c.title("Two guards in front of", "the backend")
    c.subtitle("The waypoint checks each HTTP request. The backend's ztunnel checks each connection, even one that skips the waypoint.")

    c.frame(40, 150, 1520, 470, "namespace shop", "ns")
    c.frame(80, 300, 300, 150, "frontend pod", "pod")
    fe = c.box(105, 350, 250, 70, SLATE, "app", "sa/frontend")

    c.frame(560, 210, 380, 370, "waypoint pod", "pod")
    env = c.box(590, 262, 320, 90, BLUE, "Envoy", "L7: who, method, path")
    c.outline(590, 400, 320, 140, RED, "L7 policy", "shield", sub="backend-allow-\nfrontend")

    c.frame(1090, 210, 440, 370, "backend pod", "pod", right="netns")
    zt = c.box(1120, 262, 180, 90, BLUE, "ztunnel", "L4 check")
    app = c.box(1330, 262, 170, 90, SLATE, "app", ":8000")
    c.outline(1120, 400, 380, 140, RED, "L4 policy", "shield", sub="backend-only-\nfrom-waypoint")
    c.line([(750, 352), (750, 400)], RED, 1.6, True)
    c.line([(1210, 352), (1210, 400)], RED, 1.6, True)

    c.connect(fe, env, "GET /api/orders", sa="right", sb="left", fa=0.5, fb=(385 - 262) / 90, pos="above", at=(455, 385))
    c.mark(560, 385)
    c.connect(env, zt, "sa/waypoint", sa="right", sb="left", fa=0.33, fb=0.33, pos="above", at=(995, 292))
    c.mark(1090, 292)
    c.connect(zt, app)

    c.frame(40, 660, 520, 150, "namespace course", "ns")
    cc = c.frame(80, 710, 440, 74, "course-client pod", "pod")
    c.connect(cc, zt, "", sa="right", sb="left", fb=0.8, via=[(1015, 747), (1015, 334)], col=PINK, dashed=True)
    c.text(640, 737, "pod IP:8000, skips the waypoint", 18, DEEP[PINK], True, halo=True)
    c.mark(1015, 640, ok=False)
    c.text(1039, 646, "denied by the L4 policy", 18, DEEP[RED], True, halo=True)
    c.save(OUT, "3.3-two-guards")


if __name__ == "__main__":
    guards()
