#!/usr/bin/env python3
"""Draw the diagram for course/13-jwt.md in ByteByteGo style (see ../bbg.py).

  13-two-checks        RequestAuthentication, then AuthorizationPolicy

The circled numbers match the numbered steps in the chapter.

Run from anywhere: python3 docs/diagrams/chapters/make-13.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def two_checks():
    c = Canvas(1990, 700)
    c.title("Two resources,", "two jobs")
    c.subtitle("Is the token real? Is this caller allowed? A request reaches the frontend only if both checks pass.")

    y, h = 200, 140
    c.node(50, y + 20, 240, 100, SLATE, "Request", "doc")
    c.node(440, y, 400, h, RED, "Request\nAuthentication", "lock", "is the token valid?")
    c.node(1080, y, 400, h, PINK, "Authorization\nPolicy", "shield", "is this caller allowed?")
    c.node(1700, y + 20, 250, 100, SLATE, "frontend", "cube")
    c.step(440, y, 1)
    c.step(1080, y, 2)
    c.step(1700, y + 20, 3)

    c.arrow([(290, y + 70), (440, y + 70)], "")
    c.arrow([(840, y + 70), (1080, y + 70)], "Good token,\nor no token", at=(960, y + 70), pos="above")
    c.arrow([(1480, y + 70), (1700, y + 70)], "A rule\nmatches", at=(1590, y + 70), pos="above")

    c.outline(490, 540, 300, 90, RED, "401\nUnauthorized")
    c.outline(1130, 540, 300, 90, RED, "403\nForbidden")
    c.arrow([(640, y + h + 6), (640, 540)], "Bad token", at=(640, 445), pos="right", col=SOFT)
    c.arrow([(1280, y + h + 6), (1280, 540)], "No rule matches", at=(1280, 445), pos="right", col=SOFT)
    c.save(OUT, "13-two-checks")


if __name__ == "__main__":
    two_checks()
