#!/usr/bin/env python3
"""Module 20 diagram: the node states for cordon, drain, uncordon and delete."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def node_states():
    c = Canvas(1880, 740)
    c.title("Cordon, Drain,", "Delete")
    c.subtitle("Take a node out of service in steps. Uncordon brings it back, delete removes it for good.")
    y = 240
    c.node(60, y, 360, 120, GREEN, "Ready", "server", "pods schedule here")
    c.node(620, y, 440, 120, ORANGE, "SchedulingDisabled", "lock", "no new pods")
    c.node(1260, y, 360, 120, SLATE, "Empty", "server", "except DaemonSets")
    c.node(1260, 560, 360, 110, RED, "Gone", "server")
    c.arrow([(420, y + 60), (620, y + 60)], "kubectl\ncordon", n=1, at=(520, y + 60), pos="below")
    c.arrow([(1060, y + 60), (1260, y + 60)], "kubectl\ndrain", n=2, at=(1160, y + 60), pos="below")
    c.arrow([(1530, y + 126), (1530, 560)], "remove machine,\ndelete node", n=3, at=(1530, 470), pos="right")
    c.arrow([(1330, y + 126), (1330, 470), (240, 470), (240, y + 126)], "kubectl uncordon",
            at=(780, 470), pos="above", col=SOFT)
    c.save(OUT, "20-cordon-drain-delete")


if __name__ == "__main__":
    node_states()
