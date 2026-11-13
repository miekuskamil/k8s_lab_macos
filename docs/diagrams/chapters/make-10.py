#!/usr/bin/env python3
"""Draw the diagrams for course/10-ebpf-and-cilium.md in ByteByteGo style (see ../bbg.py).

  10-cilium-node        the three Cilium parts on one node
  10-two-designs        Cilium and Istio ambient: an L4 layer per node, Envoy for L7

Run from anywhere: python3 docs/diagrams/chapters/make-10.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def cilium_node():
    c = Canvas(1700, 900)
    c.title("Cilium on", "one node")
    c.subtitle("Most packets stay in the kernel. Only flows with an L7 rule take a detour through Envoy.")

    c.group(40, 170, 1620, 680, "")
    c.text(850, 885, "one node", 19, SOFT, True, "middle")

    c.node(620, 210, 460, 100, TEAL, "cilium-agent", "server", "writes BPF maps")

    c.group(90, 430, 330, 160, "pod frontend")
    c.outline(120, 465, 270, 96, SLATE, "app", "cube")
    c.node(560, 420, 580, 140, GREEN, "eBPF in\nthe kernel", "gear", "routing · LB · policy")
    c.group(1280, 430, 330, 160, "pod backend")
    c.outline(1310, 465, 270, 96, SLATE, "app", "cube")

    c.arrow([(390, 513), (560, 490)], "", dashed=False)
    c.arrow([(1140, 490), (1310, 513)], "", dashed=False)

    c.arrow([(850, 310), (850, 420)], "Maps", at=(850, 365), pos="right", col=SOFT)

    c.node(620, 700, 460, 100, BLUE, "cilium-envoy", "shield", "only for L7 rules")
    c.arrow([(850, 566), (850, 700)], "L7 rules only", at=(850, 633), pos="right", col=SOFT)
    c.arrow([(1080, 750), (1445, 750), (1445, 590)], "", col=SOFT)
    c.save(OUT, "10-cilium-node")


def two_designs():
    c = Canvas(1760, 760)
    c.title("Two designs,", "one idea")
    c.subtitle("A cheap layer on every node for L4. An Envoy for L7, used only where needed.")

    def column(x, title, rows):
        c.group(x, 180, 760, 540, title)
        y = 215
        for i, (label, col, icon, sub) in enumerate(rows):
            c.node(x + 40, y, 680, 110, col, label, icon, sub)
            if i < len(rows) - 1:
                c.line([(x + 380, y + 110), (x + 380, y + 175)], LINE, 2.5, True, head=True)
            y += 175

    column(60, "Cilium", [
        ("pod", SLATE, "cube", None),
        ("eBPF in the kernel", GREEN, "gear", "L3/L4: routing, Service LB, policy"),
        ("cilium-envoy per node", BLUE, "shield", "L7, only when a rule needs it")])
    column(940, "Istio ambient (this lab)", [
        ("pod", SLATE, "cube", None),
        ("ztunnel per node", BLUE, "tunnel", "user space · L4: mTLS, identity, L4 policy"),
        ("waypoint per\nnamespace or service", PURPLE, "shield", "L7, only when you deploy one")])
    c.save(OUT, "10-two-designs")


if __name__ == "__main__":
    cilium_node()
    two_designs()
