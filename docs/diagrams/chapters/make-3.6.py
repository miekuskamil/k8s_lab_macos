#!/usr/bin/env python3
"""Draw the diagrams for course module 3.6 (observability) with the kit in ../bbg.py.

  06-signals   who produces metrics, traces and logs, where each lives, and where you look

Run from anywhere: python3 docs/diagrams/chapters/make-3.6.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def signals():
    c = Canvas(1600, 920)
    c.title("Three signals,", "four tools")
    c.subtitle("Left to right: the parts that produce data, the stores that keep it, and the two tools you look at.")

    node = c.frame(40, 150, 560, 730, "Node: who produces the data", "node")
    src = [("gateway pod", BLUE, "Envoy: L7 metrics, spans"),
           ("waypoint pod", BLUE, "Envoy: L7 metrics, spans"),
           ("backend pod", SLATE, "OTel SDK: metrics, spans")]
    for i, (label, col, sub) in enumerate(src):
        c.box(80, 210 + i * 120, 480, 96, col, label, sub)
    c.band(80, 580, 480, 110, BLUE, "ztunnel", "L4 metrics: bytes, connections", "tunnel")
    c.box(80, 730, 480, 110, SLATE, "every container", "stdout logs")

    c.frame(660, 150, 440, 730, "namespace observability", "ns")
    prom = c.node(700, 210, 360, 110, ORANGE, "Prometheus", "db", "metrics")
    jae = c.node(700, 400, 360, 110, ORANGE, "Jaeger", "db", "traces")
    alloy = c.box(700, 590, 360, 70, TEAL, "Alloy", "reads logs via the API")
    loki = c.node(700, 740, 360, 110, ORANGE, "Loki", "db", "logs")
    c.connect(alloy, loki)

    c.connect(node, prom, "metrics", sa="right", sb="left", fa=(265 - 150) / 730, pos="above", col=ORANGE)
    c.connect(node, jae, "spans", sa="right", sb="left", fa=(455 - 150) / 730, pos="above", col=ORANGE)
    c.connect(node, alloy, "logs", sa="right", sb="left", fa=(625 - 150) / 730, pos="above", col=ORANGE)

    kiali = c.node(1160, 210, 380, 110, TEAL, "Kiali", "eye", "mesh map")
    graf = c.node(1160, 420, 380, 220, TEAL, "Grafana", "chart", "graphs over time,\ntraces and logs")
    c.connect(prom, kiali, "reads", pos="above", dashed=True)
    c.connect(prom, graf, "", sa="right", sb="left", fa=0.85, fb=0.09, mid=1120, dashed=True)
    c.connect(jae, graf, "", sa="right", sb="left", fa=0.7, fb=(477 - 420) / 220, dashed=True)
    c.connect(loki, graf, "", sa="right", sb="bottom", dashed=True)
    c.save(OUT, "3.6-signals")


if __name__ == "__main__":
    signals()
