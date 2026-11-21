#!/usr/bin/env python3
"""Module 2.9 diagram: the CNI chain when the istio-cni plugin file is missing."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def cni_chain():
    c = Canvas(1600, 900)
    c.title("One missing file", "stops the chain")
    c.subtitle("containerd runs the CNI plugins in order. When istio-cni is missing, the cleanup stops halfway.")

    c.frame(40, 150, 1520, 720, "Node", "node")
    ctd = c.node(620, 200, 360, 110, TEAL, "containerd", "server", "runs the chain")

    c.frame(80, 400, 1440, 170, "", "plain", right="CNI plugin directory, run in order")
    fl = c.node(130, 450, 400, 90, GREEN, "flannel", "globe", "+ host-local IPAM")
    c.rect(1070, 450, 400, 90, RED, PASTEL[RED], 14, SW, dashed=True)
    ic = c.box(1070, 450, 400, 90, RED, "istio-cni", "file missing")

    c.connect(ctd, fl, "", n=1, sa="left", sb="top", fa=0.3, fb=0.4, at=(450, 233))
    c.text(450, 205, "ADD: IP + lease", 17, INK, True, "middle", halo=True)
    c.connect(ctd, fl, "", sa="left", sb="top", fa=0.75, fb=0.75, dashed=True, col=DIM)
    c.step(530, 282, 4)
    c.text(530, 330, "DEL never runs", 17, SOFT, True, "middle", halo=True)
    c.connect(ctd, ic, "", n=2, sa="right", sb="top", fa=0.3, fb=0.6, col=RED, at=(1150, 233))
    c.text(1150, 205, "ADD fails", 17, DEEP[RED], True, "middle", halo=True)
    c.connect(ctd, ic, "", n=3, sa="right", sb="top", fa=0.75, fb=0.25, col=RED, at=(1070, 282))
    c.text(1070, 330, "DEL fails too", 17, DEEP[RED], True, "middle", halo=True)
    c.mark(1310, 425, ok=False, r=12)
    c.mark(1170, 425, ok=False, r=12)

    pod = c.frame(620, 640, 360, 190, "pod sandbox", "pod")
    c.box(645, 695, 310, 100, SLATE, "IP 10.42.0.x", "never starts")
    leases = c.frame(130, 640, 400, 190, "host-local leases", "plain", col=ORANGE, icon="db")
    for i, (t, hot) in enumerate([("10.42.0.31", False), ("10.42.0.32: stays", True)]):
        c.box(155, 690 + i * 64, 350, 50, ORANGE if hot else SLATE, t, size=17)
    c.connect(fl, leases, "writes", pos="right")
    c.connect(fl, pod, "gives IP", sa="right", sb="top", fa=0.75, fb=0.3, pos="right", at=(728, 600))
    c.note(1070, 700, ["Every failed try keeps", "one of 254 addresses."], 17)
    c.save(OUT, "2.9-cni-chain")


if __name__ == "__main__":
    cni_chain()
