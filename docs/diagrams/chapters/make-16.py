#!/usr/bin/env python3
"""Module 16 diagrams: Gateway API next to the Istio API, and a VirtualService canary split."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def two_apis():
    c = Canvas(1800, 900)
    c.title("Same Jobs,", "Different Shapes")
    c.subtitle("Both APIs build an ingress proxy and route to backend versions. The pieces fit together differently.")
    xs, W, H = [100, 680, 1260], 440, 110
    c.group(60, 200, 1680, 190, "Gateway API (modules 4, 11)")
    y = 240
    c.node(xs[0], y, W, H, BLUE, "Gateway", "doc", "creates the proxy")
    c.node(xs[1], y, W, H, PURPLE, "HTTPRoute", "doc", "parentRefs: the Gateway")
    c.node(xs[2], y, W, H, SLATE, "Services", "cube", "backend-v1, backend-v2")
    c.arrow([(xs[0] + W, y + 55), (xs[1], y + 55)])
    c.arrow([(xs[1] + W, y + 55), (xs[2], y + 55)])

    c.group(60, 480, 1680, 380, "Istio API (this module)")
    y = 520
    c.node(xs[0], y, W, H, PURPLE, "VirtualService", "doc", "gateways: the Gateway")
    c.node(xs[1], y, W, H, BLUE, "Gateway", "doc", "networking.istio.io")
    c.node(xs[2], y, W, H, BLUE, "Deployment", "server", "istio/gateway Helm chart")
    c.node(xs[0], y + 190, W, H, PURPLE, "DestinationRule", "doc", "subsets v1, v2")
    c.arrow([(xs[0] + W, y + 55), (xs[1], y + 55)])
    c.arrow([(xs[1] + W, y + 55), (xs[2], y + 55)], "configures", at=(xs[1] + W + 70, y + 55), pos="above")
    c.text(xs[1] + W + 70, y + 92, "selector:", 17, SOFT, True, "middle")
    c.text(xs[1] + W + 70, y + 114, "istio=ingress", 17, SOFT, True, "middle")
    c.arrow([(xs[0] + W / 2, y + H + 6), (xs[0] + W / 2, y + 190)])
    c.save(OUT, "16-two-apis")


def canary():
    c = Canvas(1640, 640)
    c.title("A VirtualService", "Canary")
    c.subtitle("The waypoint of the backend Service runs the rules for host backend and splits the traffic by subset.")
    c.node(60, 330, 320, 110, SLATE, "frontend", "cube", "calls backend:8000")
    c.node(540, 245, 400, 280, PURPLE, "Waypoint", "shield", "VirtualService rules", size=26)
    c.text(618, 429, "for host backend", 16, "#ffffffcc")
    c.node(1120, 230, 460, 110, BLUE, "Envoy cluster v1", "server", "pods with version=v1")
    c.node(1120, 430, 460, 110, BLUE, "Envoy cluster v2", "server", "pods with version=v2")
    c.arrow([(380, 385), (540, 385)])
    c.arrow([(940, 285), (1120, 285)], "90%: subset v1", at=(1030, 285), pos="above")
    c.arrow([(940, 485), (1120, 485)], "10%: subset v2", at=(1030, 485), pos="below")
    c.save(OUT, "16-virtualservice-canary")


if __name__ == "__main__":
    two_apis()
    canary()
