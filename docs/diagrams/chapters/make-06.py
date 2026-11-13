#!/usr/bin/env python3
"""Draw the diagrams for course module 6 (observability) in ByteByteGo style (see ../bbg.py).

  06-signals   who produces metrics, traces and logs, where each lives, and where you look

Run from anywhere: python3 docs/diagrams/chapters/make-06.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def signals():
    c = Canvas(1760, 940)
    c.title("Three signals,", "four tools")
    c.subtitle("Left to right: the parts that produce data, the stores that keep it, and the two tools you look at.")

    c.group(40, 190, 520, 710, "Who produces the data")
    src = [("gateway Envoy", BLUE, "shield", "L7 metrics · spans"),
           ("waypoint Envoy", BLUE, "shield", "L7 metrics · spans"),
           ("ztunnel", BLUE, "tunnel", "L4 metrics"),
           ("backend app", SLATE, "cube", "OpenTelemetry SDK: metrics · spans"),
           ("every container", SLATE, "doc", "stdout logs")]
    for i, (label, col, icon, sub) in enumerate(src):
        c.node(70, 220 + i * 134, 460, 104, col, label, icon, sub, size=22)

    c.group(720, 190, 440, 710, "Where it lives")
    c.node(760, 240, 360, 120, ORANGE, "Prometheus", "db", "metrics")
    c.node(760, 480, 360, 120, ORANGE, "Jaeger", "db", "traces")
    c.node(760, 760, 360, 120, ORANGE, "Loki", "db", "logs")
    c.arrow([(560, 300), (760, 300)], "metrics", at=(660, 300), pos="above")
    c.arrow([(560, 540), (760, 540)], "spans", at=(660, 540), pos="above")
    c.arrow([(530, 810), (760, 810)], "Alloy reads\nvia the API", at=(645, 810), pos="above")

    c.group(1320, 190, 400, 710, "Where you look")
    c.node(1360, 360, 320, 120, TEAL, "Kiali", "eye", "mesh map")
    c.node(1360, 620, 320, 120, TEAL, "Grafana", "eye", "graphs over time")
    c.arrow([(1120, 260), (1705, 260), (1705, 680), (1680, 680)], "")
    c.arrow([(1120, 320), (1190, 320), (1190, 400), (1360, 400)], "")
    c.arrow([(1120, 510), (1190, 510), (1190, 450), (1360, 450)], "")
    c.arrow([(1120, 570), (1260, 570), (1260, 660), (1360, 660)], "")
    c.arrow([(1120, 820), (1260, 820), (1260, 710), (1360, 710)], "")
    c.save(OUT, "06-signals")


if __name__ == "__main__":
    signals()
