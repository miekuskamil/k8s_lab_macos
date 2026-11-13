#!/usr/bin/env python3
"""Module 18 diagram: ztunnel balances connections, so short questions wait behind a long story."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def l4_balance():
    c = Canvas(1460, 700)
    c.title("Why LLM Load Balancing", "Is Hard")
    c.subtitle("ztunnel spreads connections without looking at what each one carries.")
    c.node(60, 370, 300, 110, SLATE, "client", "laptop")
    c.group(840, 200, 560, 450, "ztunnel: balances connections", BLUE)
    c.node(890, 240, 460, 120, RED, "Replica A", "server", "busy: long story")
    c.node(890, 490, 460, 120, GREEN, "Replica B", "server", "idle")
    c.arrow([(360, 400), (560, 400), (560, 300), (890, 300)], "half the short\nquestions",
            at=(720, 300), pos="above")
    c.arrow([(360, 450), (560, 450), (560, 550), (890, 550)])
    c.save(OUT, "18-l4-balancing")


if __name__ == "__main__":
    l4_balance()
