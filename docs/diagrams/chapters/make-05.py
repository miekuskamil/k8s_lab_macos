#!/usr/bin/env python3
"""Draw the diagrams for course module 5 (resilience) in ByteByteGo style (see ../bbg.py).

  05-timeout-and-breaker   a 1 s route timeout, then the circuit breaker turning away request 11

The pool numbers come from manifests/scenarios/c-circuit-breaker.yaml: maxConnections 5
and http1MaxPendingRequests 5, so 5 requests run, 5 wait and request 11 gets 503 UO.

Run from anywhere: python3 docs/diagrams/chapters/make-05.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def timeout_and_breaker():
    c = Canvas(1700, 960)
    c.title("Two ways to", "fail fast")
    c.subtitle("Top: the waypoint stops waiting after 1 second. Bottom: a full pool turns request 11 away at once.")

    # timeout
    c.group(40, 180, 1620, 290, "Timeout: 1 second budget")
    c.node(80, 230, 320, 130, SLATE, "caller", "laptop", "frontend")
    c.node(690, 230, 320, 130, PURPLE, "Waypoint", "shield", "timeout 1 s")
    c.node(1300, 230, 320, 130, SLATE, "backend", "server", "works for 3 s")
    c.arrow([(400, 270), (690, 270)], "GET /api/slow?ms=3000", n=1, at=(545, 270), pos="above")
    c.arrow([(1010, 270), (1300, 270)], "Forward", n=2, at=(1155, 270), pos="above")
    c.arrow([(690, 325), (400, 325)], "After 1 s:\n504", n=3, at=(545, 325), pos="below", col=RED)
    c.note(1300, 400, ["Still working.", "Its answer is thrown away."], 17)

    # circuit breaker
    c.group(40, 540, 1620, 380, "Circuit breaker: pool of 5 connections + 5 queued")
    c.node(80, 620, 320, 130, SLATE, "caller", "laptop", "request 11")
    c.group(560, 600, 640, 290, "Waypoint pool, full")
    c.outline(590, 630, 270, 110, ORANGE, "5 waiting", "db")
    c.outline(900, 630, 270, 110, GREEN, "5 running", "server")
    c.arrow([(860, 685), (900, 685)], "")
    c.outline(590, 770, 580, 90, RED, "503 UO: upstream overflow", "shield")
    c.node(1380, 620, 260, 130, SLATE, "backend", "server", "busy with 5")
    c.arrow([(1170, 685), (1380, 685)], "5 connections", at=(1290, 685), pos="below", col=SOFT)
    c.arrow([(400, 670), (590, 670)], "Request 11", n=4, at=(480, 670), pos="above")
    c.arrow([(590, 815), (240, 815), (240, 750)], "503 at once", n=5, at=(415, 815), pos="below", col=RED)
    c.note(1380, 800, ["Never sees", "request 11."], 17)
    c.save(OUT, "05-timeout-and-breaker")


if __name__ == "__main__":
    timeout_and_breaker()
