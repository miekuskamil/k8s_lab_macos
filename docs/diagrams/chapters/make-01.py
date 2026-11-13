#!/usr/bin/env python3
"""Draw the diagrams for course module 1 (what a mesh adds) in ByteByteGo style (see ../bbg.py).

  01-sidecar-vs-ambient    a proxy in every pod against shared ztunnels and an optional waypoint
  01-ztunnel-choice        the three ways ztunnel sends the frontend's connection

Run from anywhere: python3 docs/diagrams/chapters/make-01.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def modes():
    c = Canvas(1860, 800)
    c.title("Two ways to put a", "proxy in the path")
    c.subtitle("Sidecar mode puts Envoy in every pod. Ambient mode shares a ztunnel per node and adds a waypoint for L7.")

    c.group(40, 190, 1780, 230, "Sidecar mode: a proxy in every pod")
    c.group(80, 240, 700, 150, "pod frontend")
    c.outline(110, 265, 300, 100, SOFT, "app", "cube")
    c.outline(450, 265, 300, 100, BLUE, "Envoy", "shield")
    c.arrow([(410, 315), (450, 315)], "")
    c.group(1080, 240, 700, 150, "pod backend")
    c.outline(1110, 265, 300, 100, BLUE, "Envoy", "shield")
    c.outline(1450, 265, 300, 100, SOFT, "app", "cube")
    c.arrow([(1410, 315), (1450, 315)], "")
    c.arrow([(750, 315), (1110, 315)], "mTLS,\nHTTP aware", at=(930, 315), pos="above")

    c.group(40, 500, 1780, 260, "Ambient mode: shared proxies")
    c.node(70, 560, 300, 120, SLATE, "frontend", "cube", "pod, app only")
    c.node(450, 560, 300, 120, BLUE, "ztunnel", "tunnel", "one per node, L4")
    c.node(830, 560, 330, 120, PURPLE, "Waypoint", "shield", "Envoy, L7")
    c.node(1240, 560, 260, 120, BLUE, "ztunnel", "tunnel", "L4")
    c.node(1560, 560, 240, 120, SLATE, "backend", "cube", "app only")
    c.arrow([(370, 620), (450, 620)], "")
    c.arrow([(750, 620), (830, 620)], "HBONE\nmTLS", at=(790, 620), pos="below")
    c.arrow([(1160, 620), (1240, 620)], "HBONE\nmTLS", at=(1200, 620), pos="below")
    c.arrow([(1500, 620), (1560, 620)], "")
    c.note(830, 720, ["Only if you need L7."], 17)
    c.save(OUT, "01-sidecar-vs-ambient")


def choice():
    c = Canvas(1240, 1090)
    c.title("Where ztunnel", "sends it")
    c.subtitle("frontend dials backend:8000. ztunnel checks the table from istiod and picks one of three paths.")

    c.node(60, 180, 400, 110, SLATE, "frontend", "cube", "opens backend:8000")
    c.node(60, 380, 400, 110, BLUE, "ztunnel :15001", "tunnel", "inside the pod")
    c.arrow([(260, 290), (260, 380)], "Caught in the pod", n=1, at=(260, 335))

    c.outline(60, 580, 400, 100, TEAL, "Destination\nin the mesh?", "dns")
    c.arrow([(260, 490), (260, 580)], "Look up", n=2, at=(260, 535))
    c.node(760, 575, 400, 110, SLATE, "Plain TCP", "globe", "as without a mesh")
    c.arrow([(460, 630), (760, 630)], "No", at=(610, 630), pos="above")

    c.outline(60, 780, 400, 100, TEAL, "Service has\nuse-waypoint?", "dns")
    c.arrow([(260, 680), (260, 780)], "Yes", at=(270, 730), pos="right", col=SOFT)
    c.node(760, 775, 400, 110, PURPLE, "Waypoint", "shield", "HBONE, L7 rules")
    c.arrow([(460, 830), (760, 830)], "Yes, backend", at=(610, 830), pos="above")
    c.node(760, 940, 400, 110, BLUE, "Destination pod", "tunnel", "HBONE to :15008")
    c.arrow([(260, 880), (260, 995), (760, 995)], "No, redis", at=(610, 995), pos="above")
    c.save(OUT, "01-ztunnel-choice")


if __name__ == "__main__":
    modes()
    choice()
