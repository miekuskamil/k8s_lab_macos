#!/usr/bin/env python3
"""Draw the diagram for course/08-incidents.md in ByteByteGo style (see ../bbg.py).

  08-investigate       from the symptom to the fix, outside in

Run from anywhere: python3 docs/diagrams/chapters/make-08.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def investigate():
    c = Canvas(1800, 790)
    c.title("How to", "investigate")
    c.subtitle("Work from symptoms to cause, and from the outside in. Each step narrows down the next one.")

    xs = [60, 500, 940, 1380]
    w, h = 360, 110
    top, low = 190, 560

    row1 = [
        (RED, "Symptom", "person", "curl -v localhost:8080/api/orders",
         ["What does the user get?"]),
        (TEAL, "Kiali", "eye", "Traffic Graph",
         ["Which edge is red", "or missing?"]),
        (ORANGE, "Grafana", "db", "Prometheus metrics",
         ["Since when, how many?", "Which code and response flag?"]),
        (TEAL, "Jaeger", "eye", "one trace",
         ["Where does one bad request", "stop or spend its time?"]),
    ]
    for i, (col, label, icon, sub, q) in enumerate(row1):
        x = xs[i]
        c.node(x, top, w, h, col, label, icon, sub, size=26)
        c.step(x, top, i + 1)
        c.note(x + 10, top + h + 40, q, 17)
        if i < 3:
            c.arrow([(x + w, top + h / 2), (xs[i + 1], top + h / 2)], "")

    row2 = [
        (3, ORANGE, "Logs", "doc", "waypoint · ztunnel · Loki",
         ["Waypoint access log,", "ztunnel, app logs in Loki"]),
        (2, PURPLE, "Config", "gear", "istioctl analyze",
         ["Kiali Istio Config,", "kubectl get the suspect resource"]),
        (1, GREEN, "Fix", "shield", "then prove it",
         ["Prove the symptom is gone"]),
    ]
    for k, (ci, col, label, icon, sub, q) in enumerate(row2):
        x = xs[ci]
        c.node(x, low, w, h, col, label, icon, sub, size=26)
        c.step(x, low, k + 5)
        c.note(x + 10, low + h + 40, q, 17)
        if k < 2:
            c.arrow([(x, low + h / 2), (xs[ci - 1] + w, low + h / 2)], "")

    c.arrow([(xs[3] + w / 2, top + h + 110), (xs[3] + w / 2, low)], "")

    c.outline(60, low, 360, h, DIM, "Outside in")
    c.save(OUT, "08-investigate")


if __name__ == "__main__":
    investigate()
