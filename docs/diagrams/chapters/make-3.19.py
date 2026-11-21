#!/usr/bin/env python3
"""Module 3.19 diagrams: the upgrade order, and the lab after step 5 of the canary upgrade."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def _layout(c):
    """The pieces an upgrade touches, where they live. Returns the boxes by name."""
    b = {}
    c.frame(40, 150, 1520, 720, "Cluster", "cluster")
    c.frame(80, 200, 340, 160, "cluster-scoped", "group")
    b["crds"] = c.node(110, 250, 280, 80, SLATE, "CRDs", "doc", "istio-base chart")
    c.frame(460, 200, 1060, 160, "namespace istio-system", "ns")
    b["old"] = c.node(490, 250, 300, 80, PURPLE, "istiod", "gear", "default, 1.24.2")
    b["new"] = c.node(830, 250, 320, 80, PURPLE, "istiod-1-25-5", "gear", "canary")
    b["tag"] = c.node(1190, 250, 300, 80, PINK, "default tag", "plug", "and the validator")

    c.frame(80, 410, 1440, 430, "Node", "node")
    b["cni"] = c.node(110, 470, 300, 90, TEAL, "istio-cni", "server", "node agent")
    c.frame(450, 460, 330, 200, "namespace shop", "ns")
    b["wp"] = c.node(480, 520, 270, 100, BLUE, "waypoint", "shield")
    c.frame(810, 460, 330, 200, "namespace shop-ingress", "ns")
    b["gw"] = c.node(840, 520, 270, 100, BLUE, "gateway", "shield")
    c.frame(1170, 460, 320, 200, "namespace course-sidecar", "ns")
    b["sc"] = c.node(1200, 520, 260, 100, BLUE, "sidecars", "shield")
    b["zt"] = c.band(110, 710, 1380, 100, BLUE, "ztunnel", "node proxy for every ambient pod", "tunnel", lx=520)
    return b


def upgrade_order():
    c = Canvas(1600, 900)
    c.title("Upgrade Istio in", "nine steps")
    c.subtitle("Types first, then a canary istiod, then the node agents, then the proxies one group at a time.")
    b = _layout(c)
    for n, k in enumerate(["crds", "new", "cni", "zt", "wp", "gw", "sc", "tag", "old"], 1):
        c.step(b[k].x, b[k].y, n)
    c.mark(b["old"].r - 4, b["old"].y + 4, ok=False, r=12)
    c.note(110, 615, ["istio-cni and ztunnel may", "lag istiod by one version,", "never run ahead of it."], 16)
    c.save(OUT, "3.19-upgrade-order")


def after_step5():
    c = Canvas(1600, 900)
    c.title("Two istiods,", "one mesh")
    c.subtitle("After step 5: ztunnel and the waypoint follow the new istiod, the gateway and the sidecars the old one.")
    c.frame(40, 150, 1520, 720, "Cluster", "cluster")
    c.frame(80, 200, 1440, 160, "namespace istio-system", "ns")
    old = c.node(160, 250, 540, 80, PURPLE, "istiod", "gear", "revision default, 1.24.2")
    new = c.node(960, 250, 420, 80, PURPLE, "istiod-1-25-5", "gear", "revision 1-25-5")

    c.frame(80, 410, 1440, 430, "Node", "node")
    c.frame(110, 460, 330, 220, "namespace shop-ingress", "ns")
    gw = c.node(140, 520, 270, 100, BLUE, "gateway", "shield")
    c.chip(275, 650, "no label yet", SLATE, anchor="middle", size=14)
    c.frame(470, 460, 330, 220, "namespace course-sidecar", "ns")
    sc = c.node(500, 520, 270, 100, BLUE, "sidecars", "shield")
    c.chip(635, 650, "istio-injection", SLATE, anchor="middle", size=14)
    c.frame(950, 460, 330, 220, "namespace shop", "ns")
    wp = c.node(980, 520, 270, 100, BLUE, "waypoint", "shield")
    c.chip(1115, 650, "istio.io/rev=1-25-5", PURPLE, anchor="middle", size=14)
    zt = c.band(110, 720, 1380, 90, BLUE, "ztunnel", "node proxy for every ambient pod", "tunnel", lx=520)
    c.chip(1340, 772, "Helm revision=1-25-5", PURPLE, anchor="middle", size=14)

    c.connect(old, gw, "xDS", sa="bottom", sb="top", fa=(275 - 160) / 540, fb=0.5, dashed=True, col=SLATE, pos="right")
    c.connect(old, sc, "xDS", sa="bottom", sb="top", fa=(635 - 160) / 540, fb=0.5, dashed=True, col=SLATE, pos="right")
    c.connect(new, wp, "xDS", sa="bottom", sb="top", fa=(1115 - 960) / 420, fb=0.5, col=PURPLE, pos="right")
    c.connect(new, zt, "xDS", sa="bottom", sb="top", fa=(1340 - 960) / 420, fb=(1340 - 110) / 1380, col=PURPLE,
              pos="right", at=(1340, 430))
    c.save(OUT, "3.19-two-revisions")


if __name__ == "__main__":
    upgrade_order()
    after_step5()
