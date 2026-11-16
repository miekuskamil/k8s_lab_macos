#!/usr/bin/env python3
"""Module 15 diagram: outlier detection takes the faulty pod out of load balancing."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def outlier():
    c = Canvas(1600, 860)
    c.title("Outlier detection:", "eject the bad pod")
    c.subtitle("The waypoint keeps a score per pod in its own memory and stops sending to the pod that keeps failing.")

    c.frame(40, 150, 1520, 680, "namespace shop", "ns")
    fe = c.frame(80, 400, 240, 130, "frontend pod", "pod")
    c.box(100, 450, 200, 60, SLATE, "app")

    wp = c.frame(400, 200, 520, 580, "waypoint pod", "plain", col=BLUE, icon="shield")
    c.box(430, 250, 460, 80, BLUE, "Envoy", "load balances backend-v1")
    c.text(430, 380, "score per pod, in memory", 17, SOFT, True)
    c.step(880, 374, 1)
    rows = [("pod 1", "0 errors", True), ("pod 2", "0 errors", True), ("faulty pod", "3 in a row", False)]
    ys = [450, 560, 670]
    for (name, score, ok), y in zip(rows, ys):
        c.rect(430, y - 38, 460, 76, GREEN if ok else RED, PASTEL[GREEN] if ok else PASTEL[RED], 10, SW)
        c.text(452, y + 6, name, 18, INK, True)
        c.text(610, y + 6, score, 17, SOFT)
        c.mark(860, y, ok=ok, r=12)
    c.text(610, 704, "ejected for 30 s", 16, DEEP[RED], True)
    c.step(430, 632, 3)
    c.connect(fe, wp, "", sa="right", sb="left", fb=(465 - 200) / 580)

    p1 = c.frame(1100, 400, 420, 100, "backend-v1 pod 1", "pod", right="healthy")
    p2 = c.frame(1100, 510, 420, 100, "backend-v1 pod 2", "pod", right="healthy")
    p3 = c.frame(1100, 620, 420, 100, "backend-v1-faulty", "plain", col=RED, icon="cube", right="503 always")
    c.line([(920, 450), (1100, 450)], LINE, AW, head=True)
    c.line([(920, 560), (1100, 560)], LINE, AW, head=True)
    c.line([(1100, 655), (920, 655)], RED, AW, head=True)
    c.step(1010, 655, 2)
    c.text(1010, 634, "503, 503, 503", 16, DEEP[RED], True, "middle", halo=True)
    c.line([(920, 695), (1100, 695)], DIM, AW, dashed=True, head=True)
    c.step(1010, 695, 4)
    c.text(1010, 735, "try again after 30 s", 16, SOFT, True, "middle", halo=True)

    c.frame(1100, 220, 420, 110, "EndpointSlice backend-v1", "plain", icon="list")
    c.text(1120, 300, "still lists all 3 pods", 17, SOFT)
    c.save(OUT, "15-outlier-detection")


if __name__ == "__main__":
    outlier()
