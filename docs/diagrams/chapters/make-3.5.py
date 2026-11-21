#!/usr/bin/env python3
"""Draw the diagrams for course module 3.5 (resilience) with the kit in ../bbg.py.

  05-timeout-and-breaker   a 1 s route timeout, then the circuit breaker turning away request 11

The pool numbers come from manifests/scenarios/c-circuit-breaker.yaml: maxConnections 5
and http1MaxPendingRequests 5, so 5 requests run, 5 wait and request 11 gets 503 UO.

Run from anywhere: python3 docs/diagrams/chapters/make-3.5.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def timeout_and_breaker():
    c = Canvas(1600, 1000)
    c.title("Two ways to", "fail fast")
    c.subtitle("Top: the waypoint stops waiting after 1 second. Bottom: a full pool turns request 11 away at once.")

    # timeout
    c.frame(40, 150, 1520, 380, "Timeout: a 1 second budget", "group")
    c.frame(80, 210, 300, 150, "frontend pod", "pod")
    fe = c.box(105, 260, 250, 74, SLATE, "caller")
    c.frame(620, 200, 360, 170, "waypoint pod", "pod")
    wp = c.box(645, 250, 310, 92, BLUE, "Envoy", "route timeout 1 s")
    c.frame(1220, 210, 300, 150, "backend pod", "pod")
    be = c.box(1245, 260, 250, 74, SLATE, "app", "works for 3 s")
    c.connect(fe, wp, "GET /api/slow", n=1, sa="right", sb="left", fa=0.25, fb=(278.5 - 250) / 92, at=(500, 278.5))
    c.connect(wp, be, "forward", n=2, sa="right", sb="left", fa=(278.5 - 250) / 92, fb=0.25, at=(1100, 278.5))
    c.connect(wp, fe, "504 after 1 s", n=3, sa="left", sb="right", fa=(315.5 - 250) / 92, fb=0.75, at=(500, 315.5),
              pos="below", col=RED)
    # a time line under the waypoint and the backend
    y = 460
    c.line([(700, y), (1500, y)], DIM, 2, head=True)
    for t, x in (("0 s", 700), ("1 s", 900), ("2 s", 1100), ("3 s", 1300)):
        c.line([(x, y - 8), (x, y + 8)], DIM, 2)
        c.text(x, y + 32, t, 16, SOFT, False, "middle")
    c.ellipse(900, y, 9, 9, RED, RED, 0)
    c.text(900, y - 18, "504 sent", 17, DEEP[RED], True, "middle")
    c.ellipse(1300, y, 9, 9, SLATE, WHITE, 2)
    c.text(1300, y - 18, "answer thrown away", 17, SOFT, True, "middle")

    # circuit breaker
    c.frame(40, 570, 1520, 400, "Circuit breaker: 5 connections + 5 queued", "group")
    c.frame(80, 680, 300, 150, "frontend pod", "pod")
    fe2 = c.box(105, 730, 250, 74, SLATE, "caller", "request 11")
    pool = c.frame(540, 630, 640, 300, "waypoint pod: connection pool", "pod")
    c.text(575, 715, "running", 17, SOFT, True)
    c.text(575, 815, "queued", 17, SOFT, True)
    for i in range(5):
        c.rect(680 + i * 96, 685, 76, 50, GREEN, PASTEL[GREEN], 8, SW)
        c.rect(680 + i * 96, 785, 76, 50, ORANGE, PASTEL[ORANGE], 8, SW)
    c.text(860, 900, "full: 5 running, 5 waiting", 17, SOFT, False, "middle")
    c.frame(1260, 640, 260, 150, "backend pod", "pod")
    c.box(1285, 690, 210, 74, SLATE, "app", "busy with 5")
    c.line([(1180, 710), (1260, 710)], LINE, AW, head=True)
    c.connect(fe2, pool, "request 11", n=4, sa="right", sb="left", fa=0.3, fb=(752 - 630) / 300, at=(460, 752))
    c.connect(pool, fe2, "503 UO at once", n=5, sa="left", sb="right", fa=(796 - 630) / 300, fb=0.85, at=(460, 796),
              pos="below", col=RED)
    c.save(OUT, "3.5-timeout-and-breaker")


if __name__ == "__main__":
    timeout_and_breaker()
