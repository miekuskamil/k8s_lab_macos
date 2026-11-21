#!/usr/bin/env python3
"""Module 2.8 diagram: the node states for cordon, drain, uncordon and delete."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def node_states():
    c = Canvas(1600, 860)
    c.title("Cordon, drain,", "delete")
    c.subtitle("Take a node out of service in steps. Uncordon brings it back, delete removes it for good.")

    c.frame(40, 150, 1520, 680, "Cluster", "cluster")
    a = c.frame(80, 200, 640, 590, "Node agent-0: leaving", "node")
    c.chip(690, 215, "SchedulingDisabled", ORANGE, anchor="end", size=15)
    c.step(470, 215, 1)
    c.text(100, 280, "app pods", 17, SOFT, True)
    olds = []
    for i, lab in enumerate(["frontend", "backend", "redis"]):
        olds.append(c.box(110 + i * 200, 300, 180, 80, SLATE, lab, "evicted"))
    c.text(100, 470, "DaemonSet pods stay", 17, SOFT, True)
    c.box(110, 490, 280, 80, BLUE, "ztunnel")
    c.box(410, 490, 280, 80, TEAL, "istio-cni")
    gone = c.outline(110, 640, 580, 110, RED, "remove machine,\nthen delete the Node", "cross")
    c.step(110, 640, 3)

    b = c.frame(880, 200, 640, 590, "Node server-0", "node")
    c.text(900, 280, "replacements", 17, SOFT, True)
    for i, lab in enumerate(["frontend", "backend", "redis"]):
        c.box(910 + i * 200, 300, 180, 80, GREEN, lab, "new pod")
    c.box(910, 490, 280, 80, BLUE, "ztunnel")
    c.box(1210, 490, 280, 80, TEAL, "istio-cni")
    c.line([(720, 340), (880, 340)], LINE, AW, head=True)
    c.step(800, 340, 2)
    c.text(800, 300, "drain", 17, INK, True, "middle", halo=True)
    c.text(800, 386, "PDB: one", 15, SOFT, True, "middle", halo=True)
    c.text(800, 406, "at a time", 15, SOFT, True, "middle", halo=True)
    c.note(910, 680, ["Or kubectl uncordon:", "the node takes new pods again."], 17)
    c.save(OUT, "2.8-cordon-drain-delete")


if __name__ == "__main__":
    node_states()
