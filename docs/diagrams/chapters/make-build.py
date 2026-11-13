#!/usr/bin/env python3
"""Draw the diagram in docs/build-from-scratch.md in ByteByteGo style (see ../bbg.py).

  build-layers   what you build, step by step, and where ArgoCD takes over

Run from anywhere: python3 docs/diagrams/chapters/make-build.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def badge(c, x, y, t):
    """A yellow pill with step numbers, centred on (x, y)."""
    w = 30 + len(t) * 12
    c.rect(x - w / 2, y - 17, w, 34, STEP, STEP, rx=17, sw=1)
    c.text(x, y + 7, t, 19, BG, True, "middle")


def layers():
    c = Canvas(1640, 1050)
    c.title("What you are", "building")
    c.subtitle("Steps 1 to 6 run by hand; ArgoCD applies steps 7 to 9.")

    c.group(40, 180, 1560, 840, "Your machine: OrbStack or Docker")
    c.group(80, 240, 1480, 750, "k3d cluster k8s-lab")

    c.group(120, 300, 620, 660, "You run commands")
    left = [("1-2", TEAL, "Kubernetes 1.31", "server", "k3s and app images"),
            ("3-4", BLUE, "Istio ambient", "tunnel", "istiod, istio-cni, ztunnel"),
            ("5", SLATE, "Namespaces", "doc", "quotas, lab credentials"),
            ("6", PURPLE, "ArgoCD", "gear", "syncs from GitHub")]
    for i, (n, col, label, icon, sub) in enumerate(left):
        y = 330 + i * 155
        c.node(170, y, 540, 105, col, label, icon, sub)
        badge(c, 170, y, n)
        if i < len(left) - 1:
            c.line([(440, y + 105), (440, y + 155)], LINE, 2.5, True, head=True)

    c.group(880, 300, 640, 660, "ArgoCD applies from GitHub")
    right = [("7", SLATE, "The shop", "cube", "frontend, backend, redis"),
             ("8", BLUE, "Istio config", "shield", "gateway, waypoint, routes, policies"),
             ("9", GREEN, "Observability", "eye", "metrics, traces, logs")]
    for i, (n, col, label, icon, sub) in enumerate(right):
        y = 360 + i * 200
        c.node(930, y, 560, 110, col, label, icon, sub)
        badge(c, 930, y, n)
        if i < len(right) - 1:
            c.line([(1210, y + 110), (1210, y + 200)], LINE, 2.5, True, head=True)

    c.arrow([(710, 850), (880, 850)], "sync", at=(795, 850), pos="above")
    c.save(OUT, "build-layers")


if __name__ == "__main__":
    layers()
