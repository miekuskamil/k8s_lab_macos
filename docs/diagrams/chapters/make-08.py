#!/usr/bin/env python3
"""Draw the diagram for platform-engineering/08-incidents.md with the kit in ../bbg.py.

  08-investigate       from the symptom to the fix, outside in

Run from anywhere: python3 docs/diagrams/chapters/make-08.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def investigate():
    c = Canvas(1600, 900)
    c.title("How to", "investigate")
    c.subtitle("Work from symptoms to cause, and from the outside in. Each ring narrows down the next one.")

    rings = [
        (RED, "Symptom", "curl -v: what does the user get?"),
        (TEAL, "Kiali", "which edge is red or missing?"),
        (ORANGE, "Grafana", "since when, which code and flag?"),
        (TEAL, "Jaeger", "where does one request stop?"),
        (ORANGE, "Logs", "waypoint, ztunnel, app in Loki"),
    ]
    x0, y0, w0, h0 = 40, 150, 1140, 720
    for i, (col, label, q) in enumerate(rings):
        x, y, w, h = x0 + i * 46, y0 + i * 74, w0 - i * 92, h0 - i * 74 - i * 46
        c.rect(x, y, w, h, col, pastel(col) if i == 0 else WHITE, 18, SW)
        c.step(x + 34, y + 37, i + 1)
        c.text(x + 62, y + 44, label, 21, deep(col), True)
        c.text(x + 62 + text_width(label, 21, True) + 16, y + 44, q, 18, SOFT)
    core = c.node(x0 + 5 * 46, y0 + 5 * 74 + 4, w0 - 5 * 92, 128, PURPLE, "Config", "gear",
                  "istioctl analyze, kubectl get")
    c.step(core.x, core.y, 6)

    fix = c.node(1260, 518, 300, 140, GREEN, "Fix", "check", "then prove the\nsymptom is gone")
    c.step(fix.x, fix.y, 7)
    c.connect(core, fix, "", sa="right", sb="left")
    c.connect(fix, Box(40, 150, 1140, 74), "re-run curl", sa="top", sb="right", dashed=True, col=GREEN, pos="right",
              at=(1410, 300))
    c.save(OUT, "08-investigate")


if __name__ == "__main__":
    investigate()
