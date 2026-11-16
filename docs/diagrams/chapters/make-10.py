#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/10-ebpf-and-cilium.md with the kit in ../bbg.py.

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
    c = Canvas(1600, 900)
    c.title("Cilium on", "one node")
    c.subtitle("Most packets stay in the kernel. Only flows with an L7 rule take a detour through Envoy.")

    c.frame(40, 150, 1520, 710, "Node", "node")
    c.text(1530, 210, "user space", 17, SOFT, True, "end")
    fp = c.frame(80, 220, 300, 190, "frontend pod", "pod")
    c.box(105, 275, 250, 100, SLATE, "app")
    env = c.node(540, 250, 340, 130, BLUE, "cilium-envoy", "shield", "only for L7 rules")
    bp = c.frame(960, 220, 300, 190, "backend pod", "pod")
    c.box(985, 275, 250, 100, SLATE, "app")
    agent = c.node(1300, 250, 230, 130, TEAL, "cilium-agent", None, "writes maps")

    c.frame(70, 520, 1470, 310, "Kernel", "plain", col=GREEN, icon="chip")
    h1 = c.box(80 + 10, 590, 290, 110, GREEN, "eBPF program", "on the pod's veth")
    h2 = c.box(965, 590, 290, 110, GREEN, "eBPF program", "on the pod's veth")
    maps = c.node(1300, 590, 230, 110, ORANGE, "BPF maps", "db")
    c.note(110, 790, "Routing, Service load balancing and L3/L4 policy run here, on the packet where it sits.", 17)

    c.connect(fp, h1, "", sa="bottom", sb="top", fa=0.5, fb=(230 - 90) / 290)
    c.connect(h1, h2, "L3/L4: stays in the kernel", sa="right", sb="left", fa=0.75, fb=0.75, pos="above",
              at=(672, 672), col=GREEN)
    c.connect(h1, env, "", sa="right", sb="bottom", fa=0.25, fb=0.35, dashed=True, col=BLUE)
    c.connect(env, h2, "L7 rule", sa="bottom", sb="left", fa=0.65, fb=0.25, dashed=True, col=BLUE, pos="right",
              at=(761, 470))
    c.connect(h2, bp, "", sa="top", sb="bottom")
    c.connect(agent, maps, "writes", dashed=True, col=TEAL, pos="right")
    c.connect(maps, h2, "read", sa="left", sb="right", dashed=True, col=ORANGE, pos="above")
    c.save(OUT, "10-cilium-node")


def two_designs():
    c = Canvas(1600, 880)
    c.title("Two designs,", "one idea")
    c.subtitle("A cheap layer on every node for L4. An Envoy for L7, used only where needed.")

    def node(x, title, l4_in_kernel):
        c.frame(x, 150, 740, 690, title, "node")
        c.text(x + 720, 210, "user space", 17, SOFT, True, "end")
        p = c.frame(x + 40, 230, 260, 160, "pod", "pod")
        c.box(x + 65, 280, 210, 80, SLATE, "app")
        if l4_in_kernel:
            l7 = c.node(x + 360, 250, 340, 130, BLUE, "cilium-envoy", "shield", "one per node,\nL7 rules only")
            c.rect(x + 40, 440, 660, 100, DIM, "none", 14, 1.4, True)
            c.text(x + 370, 497, "no L4 proxy in user space", 18, SOFT, False, "middle")
            k = c.frame(x + 30, 590, 680, 220, "Kernel", "plain", col=GREEN, icon="chip")
            l4 = c.box(x + 60, 650, 620, 120, GREEN, "eBPF programs", "L3/L4: routing, Service LB, policy")
            c.connect(p, l4, "", sa="bottom", sb="top", fa=0.5, fb=(170 - 60) / 620)
            c.connect(l4, l7, "L7 rule only", sa="top", sb="bottom", fa=(530 - 60) / 620, fb=0.5, dashed=True,
                      col=BLUE, pos="right", at=(x + 530, 500))
        else:
            l7 = c.node(x + 360, 250, 340, 130, BLUE, "waypoint", "shield", "per namespace\nor service")
            l4 = c.band(x + 40, 440, 660, 100, BLUE, "ztunnel", "L4: mTLS, identity, policy", "tunnel", lx=x + 230)
            c.frame(x + 30, 590, 680, 220, "Kernel", "plain", col=GREEN, icon="chip")
            c.box(x + 60, 650, 620, 120, GREEN, "any CNI", "plain routing")
            c.connect(p, l4, "", sa="bottom", sb="top", fa=0.5, fb=(130) / 660)
            c.connect(l4, l7, "L7 only", sa="top", sb="bottom", fa=(530 - 40) / 660, fb=0.5, dashed=True,
                      col=BLUE, pos="right")

    node(40, "Cilium", True)
    node(820, "Istio ambient (this lab)", False)
    c.save(OUT, "10-two-designs")


if __name__ == "__main__":
    cilium_node()
    two_designs()
