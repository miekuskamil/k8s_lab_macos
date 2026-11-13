#!/usr/bin/env python3
"""Draw the diagrams for course module 0 (setup) in ByteByteGo style (see ../bbg.py).

  00-observability-tools   the five tools, the question each one answers, and what they read

Run from anywhere: python3 docs/diagrams/chapters/make-00.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def tools():
    c = Canvas(1560, 900)
    c.title("Five tools,", "five questions")
    c.subtitle("Pick the tool by the question you have. Kiali and Grafana read the same Prometheus data.")

    c.node(60, 445, 260, 110, SLATE, "You", "person")
    rows = [("Kiali", TEAL, "eye", "What talks to what? Encrypted? Config valid?"),
            ("Grafana", TEAL, "eye", "How much, how fast, how many errors, over time?"),
            ("Jaeger", ORANGE, "db", "Where did one request spend its time?"),
            ("Loki, in Grafana", ORANGE, "db", "What did the pods print while it happened?"),
            ("istioctl", SLATE, "laptop", "What config does this proxy hold now?")]
    for i, (label, col, icon, sub) in enumerate(rows):
        y = 180 + i * 140
        c.node(460, y, 560, 110, col, label, icon, sub, size=22)
        c.arrow([(320, 500), (460, y + 55)], "")

    c.node(1240, 220, 280, 110, ORANGE, "Prometheus", "db", "metrics")
    c.arrow([(1020, 235), (1240, 260)], "reads", at=(1130, 225), pos="above", col=SOFT)
    c.arrow([(1020, 365), (1240, 300)], "reads", at=(1130, 360), pos="below", col=SOFT)
    c.arrow([(1020, 405), (1090, 405), (1090, 555), (1020, 555)], "")
    c.arrow([(1020, 405), (1090, 405), (1090, 695), (1020, 695)], "")
    c.text(1110, 570, "Grafana reads", 17, SOFT, True)
    c.text(1110, 594, "traces and logs", 17, SOFT, True)
    c.save(OUT, "00-observability-tools")


if __name__ == "__main__":
    tools()
