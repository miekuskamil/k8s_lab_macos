#!/usr/bin/env python3
"""Draw the diagram for module 25 (OpenTelemetry and Tempo) in ByteByteGo style (see ../bbg.py).

  25-collector-pipeline     one span from the orders app through the Collector to the back ends

Run from anywhere: python3 docs/diagrams/chapters/make-25.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def pipeline():
    c = Canvas(1940, 990)
    c.title("The Collector", "pipeline")
    c.subtitle("One span goes in. Four processors change it, exporters send it on, a connector makes metrics.")

    c.node(40, 230, 280, 110, SLATE, "orders app", "cube", "OpenTelemetry SDK", size=22)

    c.group(440, 180, 1120, 770, "OpenTelemetry Collector")
    c.outline(510, 237, 300, 96, GREEN, "receiver\notlp")
    c.arrow([(320, 285), (510, 285)], "OTLP\n:4318", n=1, at=(380, 285), pos="below")

    c.group(490, 410, 340, 470)
    c.text(660, 912, "Processors, in order", 19, SOFT, True, "middle")
    procs = ["memory_limiter", "k8s_attributes", "transform", "batch"]
    for i, p in enumerate(procs):
        y = 440 + i * 110
        c.outline(510, y, 300, 80, PURPLE, p)
        if i < len(procs) - 1:
            c.line([(660, y + 80), (660, y + 110)], LINE, 2.5, head=True)
    c.step(830, 410, 2)
    c.line([(660, 333), (660, 440)], LINE, 2.5, True, head=True)

    # batch fans out over a bus line to the two exporters and the connector
    c.line([(810, 810), (890, 810), (890, 285)], LINE, 2.5, True)
    c.outline(940, 237, 300, 96, BLUE, "exporter\notlp_grpc/tempo")
    c.outline(940, 417, 300, 96, BLUE, "exporter\notlp_grpc/jaeger")
    c.outline(940, 597, 260, 96, TEAL, "connector\nspan_metrics")
    c.outline(1260, 597, 270, 96, BLUE, "exporter\nprometheus :8889")
    for y in (285, 465, 645):
        c.line([(890, y), (940, y)], LINE, 2.5, True, head=True)
    c.line([(1200, 645), (1260, 645)], LINE, 2.5, True, head=True)
    c.step(1230, 597, 4)

    c.node(1660, 230, 240, 110, ORANGE, "Tempo", "db")
    c.node(1660, 410, 240, 110, ORANGE, "Jaeger", "db")
    c.node(1660, 590, 240, 110, ORANGE, "Prometheus", "db", size=22)
    c.arrow([(1240, 285), (1660, 285)], "Spans", n=3, at=(1450, 285), pos="above")
    c.arrow([(1240, 465), (1660, 465)], "Spans", at=(1450, 450), pos="above", col=SOFT)
    c.arrow([(1660, 645), (1530, 645)], "Scrape", at=(1610, 690), pos="above", col=SOFT)
    c.save(OUT, "25-collector-pipeline")


if __name__ == "__main__":
    pipeline()
