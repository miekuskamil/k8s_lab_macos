#!/usr/bin/env python3
"""Draw the diagram for module 26 (Kyverno, policy as code) in ByteByteGo style (see ../bbg.py).

  26-where-kyverno-sits     one apply through the two Kyverno webhooks, plus the background parts

Solid arrows follow the request. Dashed arrows are the parts that work outside of requests,
as the module text says.

Run from anywhere: python3 docs/diagrams/chapters/make-26.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def where_kyverno_sits():
    c = Canvas(1800, 820)
    c.title("Where Kyverno", "sits")
    c.subtitle("Every object passes two Kyverno webhooks before the API server stores it.")

    c.node(60, 200, 340, 110, SLATE, "kubectl apply", "laptop", "or ArgoCD sync", size=22)
    c.node(540, 200, 380, 110, PURPLE, "API server", "server")
    c.node(1180, 200, 340, 110, ORANGE, "Stored", "db")
    c.arrow([(400, 255), (540, 255)], "Send", n=1, at=(470, 255), pos="below", dashed=False)
    c.arrow([(920, 255), (1180, 255)], "Store", n=4, at=(1050, 255), pos="below", dashed=False)

    c.group(320, 440, 1250, 330, "Kyverno")
    c.node(360, 480, 360, 110, PINK, "Mutate", "gear", "add defaults")
    c.node(780, 480, 360, 110, RED, "Validate", "shield", "allow or deny")
    c.arrow([(600, 310), (600, 480)], "Mutating\nwebhook", n=2, at=(600, 365), pos="left", dashed=False)
    c.line([(670, 480), (670, 310)], LINE, 2.5, head=True)
    c.arrow([(880, 310), (880, 480)], "Validating\nwebhook", n=3, at=(880, 365), dashed=False)
    c.line([(820, 480), (820, 310)], LINE, 2.5, head=True)

    c.outline(1200, 470, 340, 96, PURPLE, "Background\ncontroller", "gear")
    c.outline(1200, 640, 340, 96, PURPLE, "Reports\ncontroller", "doc")
    c.arrow([(1350, 470), (1350, 310)], "Scan what runs,\ngenerate objects", at=(1350, 390), col=SOFT)
    c.arrow([(1540, 688), (1620, 688), (1620, 255), (1520, 255)], "PolicyReports", at=(1620, 470), pos="right", col=SOFT)
    c.save(OUT, "26-where-kyverno-sits")


if __name__ == "__main__":
    where_kyverno_sits()
