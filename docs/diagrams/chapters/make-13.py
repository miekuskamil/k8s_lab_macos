#!/usr/bin/env python3
"""Draw the diagram for platform-engineering/13-jwt.md with the kit in ../bbg.py.

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
    c = Canvas(1600, 800)
    c.title("Two resources,", "two jobs")
    c.subtitle("Is the token real? Is this caller allowed? A request reaches the frontend only if both checks pass.")

    c.frame(40, 200, 270, 560, "Your Mac", "host")
    curl = c.node(65, 300, 220, 120, SLATE, "curl", "laptop", "Bearer token")

    c.frame(350, 150, 1210, 620, "Cluster", "cluster")
    c.frame(380, 190, 760, 360, "namespace shop-ingress", "ns")
    c.frame(410, 240, 700, 280, "ingress gateway pod", "plain", col=BLUE, icon="shield")
    ra = c.node(440, 310, 275, 140, RED, "Request\nAuthentication", "lock", "token valid?")
    ap = c.node(825, 310, 265, 140, PINK, "Authorization\nPolicy", "shield", "caller allowed?")
    c.step(ra.x, ra.y, 1)
    c.step(ap.x, ap.y, 2)

    c.frame(1180, 190, 350, 360, "namespace shop", "ns")
    fe = c.frame(1210, 300, 290, 150, "frontend pod", "pod")
    c.box(1235, 350, 240, 74, SLATE, "app")
    c.step(fe.x, fe.y, 3)

    c.connect(curl, ra, "", sa="right", sb="left", fa=0.5, fb=0.29)
    c.connect(ra, ap, "good token\nor none", sa="right", sb="left", fa=0.5, fb=0.5, pos="above", at=(770, 380))
    c.connect(ap, fe, "allowed", sa="right", sb="left", fa=0.5, fb=(380 - 300) / 150, pos="below", at=(1150, 380))

    c.connect(ra, curl, "401: bad token", sa="bottom", sb="bottom", fa=0.5, fb=0.25, via=[(577, 620), (120, 620)],
              col=RED, pos="above", at=(400, 620))
    c.connect(ap, curl, "403: no rule matches", sa="bottom", sb="bottom", fa=0.5, fb=0.7, via=[(957, 690), (219, 690)],
              col=RED, pos="above", at=(600, 690))
    c.save(OUT, "13-two-checks")


if __name__ == "__main__":
    two_checks()
