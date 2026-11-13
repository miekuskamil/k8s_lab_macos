#!/usr/bin/env python3
"""Draw the diagrams for module 28 (continuous profiling) in ByteByteGo style (see ../bbg.py).

  28-profile-path       how profiles get from podinfo to a flame graph, in four steps
  28-flame-tree         the call tree from the module's test run, with total percentages

Run from anywhere: python3 docs/diagrams/chapters/make-28.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def profile_path():
    c = Canvas(1240, 690)
    c.title("How profiles get to", "Pyroscope")
    c.subtitle("Alloy pulls, Pyroscope stores, Grafana draws the flame graphs.")

    c.node(60, 200, 400, 110, SLATE, "podinfo", "cube", "Go · /debug/pprof")
    c.step(60, 200, 1)
    c.node(760, 200, 420, 110, TEAL, "Alloy", "eye", "finds pods by annotation")
    c.arrow([(460, 255), (760, 255)], "Pull every 15 s", n=2, at=(610, 255), pos="below")

    c.node(760, 500, 420, 110, ORANGE, "Pyroscope", "db", "stores profiles")
    c.arrow([(970, 310), (970, 500)], "Push", n=3, at=(970, 405))

    c.node(60, 500, 400, 110, GREEN, "Grafana", "eye", "flame graphs")
    c.arrow([(760, 555), (460, 555)], "Read", n=4, at=(610, 555), pos="below")
    c.save(OUT, "28-profile-path")


def flame_tree():
    c = Canvas(1380, 900)
    c.title("Reading a", "flame graph")
    c.subtitle("This module's real result. Each bar is a function. Its width is its total share of samples.")

    full = 1260
    rows = [("total", "100%", 100, SLATE, ""),
            ("main.beginStressTest.func1", "99.9%", 99.9, PURPLE, "podinfo's own code"),
            ("runtime.selectnbrecv", "91.6%", 91.6, BLUE, "non-blocking channel read"),
            ("runtime.chanrecv", "63.3%", 63.3, BLUE, "called by selectnbrecv"),
            ("runtime.empty", "25.2%", 25.2, BLUE, "called by chanrecv")]
    y = 190
    for i, (name, pct, share, col, sub) in enumerate(rows):
        w = full * share / 100
        c.node(60, y, w, 90, col, name, None, f"{pct}" + (f"  ·  {sub}" if sub and w > 520 else ""), size=22)
        if sub and w <= 520:
            c.text(60 + w + 20, y + 52, sub, 17, SOFT, True)
        if i < len(rows) - 1:
            c.line([(120, y + 96), (120, y + 132)], LINE, 2.5, True, head=True)
        y += 135
    c.text(60, y + 20, "Each function sits under its caller. A child is never wider than its parent.", 17, SOFT)
    c.save(OUT, "28-flame-tree")


if __name__ == "__main__":
    profile_path()
    flame_tree()
