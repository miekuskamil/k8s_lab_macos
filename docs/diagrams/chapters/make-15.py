#!/usr/bin/env python3
"""Module 15 diagram: outlier detection takes the faulty pod out of load balancing."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def outlier():
    c = Canvas(1300, 760)
    c.title("Outlier Detection:", "Eject the Bad Pod")
    c.subtitle("The waypoint watches each pod's answers and stops sending to the one that keeps failing.")
    c.node(60, 380, 340, 110, PURPLE, "Waypoint", "shield", "load balances")
    c.node(780, 200, 440, 110, SLATE, "backend-v1 pod 1", "cube", "healthy")
    c.node(780, 380, 440, 110, SLATE, "backend-v1 pod 2", "cube", "healthy")
    c.node(780, 580, 440, 110, RED, "backend-v1-faulty", "cube", "503 on every request")
    c.arrow([(230, 380), (230, 255), (780, 255)], dashed=False)
    c.arrow([(400, 435), (780, 435)], dashed=False)
    c.arrow([(230, 496), (230, 635), (780, 635)], "3 errors in a row:\nout for 30 s",
            at=(520, 635), pos="above", col=RED)
    c.save(OUT, "15-outlier-detection")


if __name__ == "__main__":
    outlier()
