#!/usr/bin/env python3
"""Draw the diagrams for module 28 (continuous profiling) with the kit in ../bbg.py.

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
    c = Canvas(1600, 760)
    c.title("How profiles get to", "Pyroscope")
    c.subtitle("Alloy pulls, Pyroscope stores, Grafana draws the flame graphs.")

    c.frame(40, 150, 1080, 580, "namespace course-profiling", "ns")
    pod = c.frame(80, 220, 380, 220, "podinfo pod", "pod")
    app = c.box(105, 275, 330, 90, SLATE, "Go app", "serves /debug/pprof")
    c.chip(270, 405, "profiles.grafana.com/cpu.scrape", SLATE, anchor="middle", size=13)
    c.step(app.x, app.y, 1)
    alloy = c.node(700, 260, 380, 130, TEAL, "Alloy", "eye", "finds pods by\nannotation")
    pyro = c.node(700, 540, 380, 130, ORANGE, "Pyroscope", "db", "stores profiles")
    c.connect(app, alloy, "pull every 15 s", n=2, sa="right", sb="left", fb=(320 - 260) / 130, pos="below",
              at=(570, 320))
    c.connect(alloy, pyro, "push", n=3, pos="right")

    c.frame(1170, 150, 390, 580, "namespace observability", "ns")
    graf = c.node(1200, 540, 330, 130, TEAL, "Grafana", "flame", "flame graphs")
    c.connect(pyro, graf, "read", n=4, pos="above")
    c.save(OUT, "28-profile-path")


def flame_tree():
    c = Canvas(1600, 860)
    c.title("Reading a", "flame graph")
    c.subtitle("This module's real result. Each bar is a function, its width is its total share of samples.")

    full, x0 = 1380, 80
    rows = [("total", 100, SLATE, ""),
            ("main.beginStressTest.func1", 99.9, PURPLE, "podinfo's own code"),
            ("runtime.selectnbrecv", 91.6, BLUE, "non-blocking channel read"),
            ("runtime.chanrecv", 63.3, BLUE, ""),
            ("runtime.empty", 25.2, BLUE, "")]
    y = 200
    for i, (name, share, col, note) in enumerate(rows):
        w = full * share / 100
        c.rect(x0, y, w, 86, col, pastel(col), 8, SW)
        c.text(x0 + 20, y + 38, name, 20, INK, True, mono=True)
        c.text(x0 + 20, y + 66, f"total {share:g}%" + (f", {note}" if note else ""), 17, SOFT)
        y += 98
    # the scale under the bars
    c.line([(x0, y + 30), (x0 + full, y + 30)], DIM, 2)
    for p in (0, 25, 50, 75, 100):
        x = x0 + full * p / 100
        c.line([(x, y + 22), (x, y + 38)], DIM, 2)
        c.text(x, y + 62, f"{p}%", 16, SOFT, False, "middle")
    c.text(x0, y + 110, "Root at the top. Each function sits under its caller, and a child is never wider than its parent.",
           17, SOFT)
    c.save(OUT, "28-flame-tree")


if __name__ == "__main__":
    profile_path()
    flame_tree()
