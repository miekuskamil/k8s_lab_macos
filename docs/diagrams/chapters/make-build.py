#!/usr/bin/env python3
"""Draw the diagram in docs/build-from-scratch.md with the kit in ../bbg.py.

  build-layers   what you build, step by step, and where ArgoCD takes over

Run from anywhere: python3 docs/diagrams/chapters/make-build.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def layers():
    c = Canvas(1600, 960)
    c.title("What you are", "building")
    c.subtitle("Steps 1 to 6 run by hand, bottom up. ArgoCD applies steps 7 to 9 from GitHub.")

    def badge(x, y, t):
        c.chip(x, y, t, STEP, anchor="middle", solid=True, mono=False, size=15)

    c.frame(40, 150, 1520, 780, "Your Mac: OrbStack or Docker", "host")
    c.frame(70, 200, 1460, 700, "k3d cluster k8s-lab", "cluster")

    k3s = c.band(100, 800, 1400, 70, TEAL, "k3s 1.31 node", "app images loaded", "server", lx=120)
    badge(1440, 835, "1-2")
    mesh = c.band(100, 710, 1400, 70, BLUE, "Istio ambient data plane", "ztunnel and istio-cni on every node",
                  "tunnel", lx=120)
    badge(1440, 745, "3-4")

    c.frame(100, 250, 280, 420, "namespace istio-system", "ns")
    c.node(120, 310, 240, 100, PURPLE, "istiod", "gear", "control plane")
    badge(360, 250, "3-4")
    c.frame(410, 250, 280, 420, "namespace argocd", "ns")
    argo = c.node(430, 310, 240, 100, PURPLE, "ArgoCD", "refresh", "syncs from GitHub")
    badge(670, 250, "6")
    c.text(430, 470, "applies everything", 16, SOFT)
    c.text(430, 492, "to the right from Git", 16, SOFT)

    shop = c.frame(720, 250, 400, 420, "namespace shop", "ns", right="quotas")
    badge(1100, 250, "5")
    c.box(745, 310, 350, 90, SLATE, "the shop", "frontend, backend, redis")
    badge(745, 310, "7")
    c.box(745, 440, 350, 90, BLUE, "Istio config", "gateway, waypoint, policies")
    badge(745, 440, "8")
    obs = c.frame(1150, 250, 350, 420, "namespace observability", "ns")
    badge(1480, 250, "5")
    c.box(1175, 310, 300, 220, GREEN, "observability", "metrics, traces, logs")
    badge(1175, 310, "9")

    c.connect(argo, shop, "applies", sa="right", sb="left", fb=(360 - 250) / 420, pos="above")
    c.line([(646, 410), (646, 620), (1325, 620), (1325, 530)], LINE, AW, head=True)
    c.save(OUT, "build-layers")


if __name__ == "__main__":
    layers()
