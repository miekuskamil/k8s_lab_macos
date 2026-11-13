#!/usr/bin/env python3
"""Module 14 diagrams: the upgrade order, and the lab after step 5 of the canary upgrade."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def pill(c, cx, cy, t):
    w = text_width(t, 19, True) + 22
    c.rect(cx - w / 2, cy - 17, w, 34, STEP, STEP, rx=17, sw=1)
    c.text(cx, cy + 7, t, 19, BG, True, "middle")


def upgrade_order():
    c = Canvas(1800, 680)
    c.title("Upgrade Istio in", "Nine Steps")
    c.subtitle("Types first, then a canary istiod, then the node agents, then the proxies one group at a time.")
    W, H = 360, 110
    xs = [60, 500, 940, 1380]
    top, low = 220, 500
    row1 = [(SLATE, "CRDs", "doc", "in place, first"),
            (PURPLE, "New istiod", "gear", "canary, rev 1-25-5"),
            (TEAL, "istio-cni", "server", "in place"),
            (BLUE, "ztunnel", "tunnel", "in place")]
    for i, (col, label, icon, sub) in enumerate(row1):
        c.node(xs[i], top, W, H, col, label, icon, sub)
        c.step(xs[i], top, i + 1)
        if i < 3:
            c.arrow([(xs[i] + W, top + H / 2), (xs[i + 1], top + H / 2)])
    row2 = [(xs[3], BLUE, "Proxies move\nby label", "shield", "waypoint · gateway · sidecars", "5-7"),
            (xs[2], PURPLE, "Default tag", "gear", "+ validator to new istiod", "8"),
            (xs[1], RED, "Remove old\nistiod", "gear", None, "9")]
    for x, col, label, icon, sub, n in row2:
        c.node(x, low, W, 120, col, label, icon, sub)
        pill(c, x, low, n)
    c.arrow([(xs[3] + W / 2, top + H + 6), (xs[3] + W / 2, low)])
    c.arrow([(xs[3], low + 60), (xs[2] + W, low + 60)])
    c.arrow([(xs[2], low + 60), (xs[1] + W, low + 60)])
    c.save(OUT, "14-upgrade-order")


def after_step5():
    c = Canvas(1600, 800)
    c.title("Two istiods,", "One Mesh")
    c.subtitle("After step 5: some proxies already follow the new istiod, the rest still follow the old one.")
    px = [(220, "shop-gateway\nno label yet"), (340, "Sidecars in course-sidecar\nistio-injection: enabled"),
          (530, "ztunnel\nHelm revision=1-25-5"), (650, "Waypoint\nistio.io/rev=1-25-5")]
    for y, label in px:
        c.outline(60, y, 500, 96, BLUE, label, "shield")
    c.group(1000, 190, 540, 580, "istio-system, after step 5")
    c.node(1040, 220, 460, 216, PURPLE, "istiod", "gear", "revision default, 1.24.2", size=28)
    c.node(1040, 530, 460, 216, PURPLE, "istiod-1-25-5", "gear", "revision 1-25-5", size=28)
    for y, _ in px:
        c.arrow([(560, y + 48), (1040, y + 48)], "xDS", at=(800, y + 48), pos="above")
    c.save(OUT, "14-two-revisions")


if __name__ == "__main__":
    upgrade_order()
    after_step5()
