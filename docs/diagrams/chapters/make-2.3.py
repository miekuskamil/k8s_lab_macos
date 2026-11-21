#!/usr/bin/env python3
"""Draw the diagram for module 2.3 (logs with Loki) with the kit in ../bbg.py.

  2.3-log-path   a pod prints a line, Alloy tails it, Loki indexes the labels and stores the text, Grafana queries it

Run from anywhere: python3 docs/diagrams/chapters/make-2.3.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def log_path():
    c = Canvas(1600, 820)
    c.title("From a printed line", "to a query")
    c.subtitle("Loki indexes a few labels per stream and keeps the text as it came, so LogQL filters the text when you ask.")

    c.frame(40, 150, 1520, 630, "Cluster", "cluster")
    c.frame(80, 210, 400, 520, "namespace course-logs", "ns")
    pod = c.frame(120, 270, 320, 200, "pod orders", "pod")
    app = c.box(150, 330, 260, 100, SLATE, "orders", "prints JSON to stdout")
    files = c.box(120, 560, 320, 110, GREEN, "node log file", "one per container")

    c.frame(540, 210, 980, 520, "namespace observability", "ns")
    alloy = c.node(580, 550, 320, 130, TEAL, "Alloy", "eye", "tails every pod")
    loki = c.frame(980, 260, 500, 290, "Loki", "plain", col=ORANGE, icon="db")
    idx = c.box(1010, 320, 440, 90, ORANGE, "index", "namespace, app, pod")
    chunks = c.box(1010, 430, 440, 90, ORANGE, "chunks", "the text, compressed")
    graf = c.node(1100, 600, 380, 100, TEAL, "Grafana", "chart", "LogQL in Explore")

    c.connect(app, files, "stdout", n=1, sa="bottom", sb="top", pos="right")
    c.connect(files, alloy, "reads", n=2, sa="right", sb="left", fa=0.5, fb=0.5, pos="above")
    c.connect(alloy, loki, "push with labels", n=3, sa="top", sb="left", fa=0.5, fb=0.3, via=[(740, 347)], pos="above", at=(860, 347))
    c.connect(graf, chunks, "query", n=4, sa="top", sb="bottom", fa=0.5, fb=0.65, pos="right")
    c.save(OUT, "2.3-log-path")


if __name__ == "__main__":
    log_path()
