#!/usr/bin/env python3
"""Module 21 diagram: the CNI chain when the istio-cni plugin file is missing."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def cni_chain():
    c = Canvas(1720, 760)
    c.title("One Missing File", "Stops the Chain")
    c.subtitle("containerd runs the CNI plugins in order. When istio-cni is missing, the cleanup stops halfway.")
    y = 240
    c.node(60, y, 400, 110, GREEN, "flannel", "globe", "+ host-local IPAM")
    c.node(720, y, 320, 110, TEAL, "containerd", "server", "runs the chain")
    c.node(1300, y, 360, 110, RED, "istio-cni", "lock", "not in plugin directory")
    c.arrow([(720, y + 30), (460, y + 30)], "ADD: an IP", n=1, at=(590, y + 30), pos="above")
    c.arrow([(460, y + 80), (720, y + 80)], "10.42.0.x,\nlease file written", n=2, at=(590, y + 80), pos="below")
    c.arrow([(1040, y + 30), (1300, y + 30)], "ADD: ambient\nredirection fails", n=3, at=(1170, y + 30), pos="above", col=RED)
    c.arrow([(1040, y + 80), (1300, y + 80)], "DEL cleanup:\nfails again", n=4, at=(1170, y + 80), pos="below", col=RED)
    c.node(60, 570, 400, 110, ORANGE, "Lease file", "db", "stays behind")
    c.arrow([(160, y + 116), (160, 570)], "writes", at=(160, 460), pos="right", col=SOFT)
    c.arrow([(880, y + 116), (880, 625), (460, 625)], "Chain stops: flannel's\nDEL never runs",
            at=(670, 625), pos="above", col=RED)
    c.save(OUT, "21-cni-chain")


if __name__ == "__main__":
    cni_chain()
