#!/usr/bin/env python3
"""Module 18 diagram: ztunnel balances connections, so short questions wait behind a long story."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def l4_balance():
    c = Canvas(1600, 740)
    c.title("Why LLM load balancing", "is hard")
    c.subtitle("ztunnel spreads connections without looking at what each one carries.")

    c.frame(40, 150, 1520, 560, "Node", "node")
    cl = c.frame(80, 260, 320, 290, "client pod", "pod")
    c.box(105, 315, 270, 70, RED, "1 long story", "25 s")
    c.box(105, 400, 270, 120, SLATE, "6 short\nquestions", "30 ms each")
    zt = c.node(520, 340, 300, 130, BLUE, "ztunnel", "tunnel", "L4: one pick per\nconnection")
    c.connect(cl, zt, "", sa="right", sb="left", fb=0.5)

    a = c.frame(960, 200, 560, 260, "Replica A: llama.cpp", "pod", right="--parallel 1")
    c.box(990, 255, 500, 70, RED, "busy: long story", "25 s")
    c.text(990, 370, "queue", 16, SOFT, True)
    for i in range(3):
        c.box(1060 + i * 145, 345, 130, 80, ORANGE, "short", "waits")
    b = c.frame(960, 500, 560, 150, "Replica B: llama.cpp", "pod", right="--parallel 1")
    c.box(990, 555, 500, 70, GREEN, "idle", "after its 3 short ones")
    c.connect(zt, a, "story + 3 short", sa="right", sb="left", fa=0.3, fb=(379 - 200) / 260, pos="above", at=(890, 379))
    c.connect(zt, b, "3 short", sa="right", sb="left", fa=0.7, fb=0.46, pos="above",
              at=(890, 569))
    c.save(OUT, "18-l4-balancing")


if __name__ == "__main__":
    l4_balance()
