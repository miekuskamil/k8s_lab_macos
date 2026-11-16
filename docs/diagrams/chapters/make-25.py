#!/usr/bin/env python3
"""Draw the diagram for module 25 (OpenTelemetry and Tempo) with the kit in ../bbg.py.

  25-collector-pipeline     one span from the orders app through the Collector to the back ends

Run from anywhere: python3 docs/diagrams/chapters/make-25.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def pipeline():
    c = Canvas(1600, 920)
    c.title("The Collector", "pipeline")
    c.subtitle("One span goes in. Four processors change it, exporters send it on, a connector makes metrics.")

    c.frame(40, 150, 1110, 730, "namespace course-otel", "ns")
    app = c.frame(70, 230, 250, 130, "orders pod", "pod")
    c.box(90, 280, 210, 60, SLATE, "app + OTel SDK", size=17)

    col = c.frame(370, 200, 750, 650, "otel-collector pod", "pod")
    rcv = c.box(400, 260, 280, 80, TEAL, "receiver", "otlp :4318")
    c.frame(400, 380, 280, 440, "", "group", right="processors, in order")
    procs = []
    for i, p in enumerate(["memory_limiter", "k8s_attributes", "transform", "batch"]):
        procs.append(c.box(420, 430 + i * 96, 240, 70, PURPLE, p, size=17))
        if i:
            c.connect(procs[i - 1], procs[i])
    c.step(400, 380, 2)
    c.connect(rcv, procs[0], "", sa="bottom", sb="top")
    ex_t = c.box(800, 260, 290, 80, BLUE, "exporter", "otlp_grpc/tempo")
    ex_j = c.box(800, 380, 290, 80, BLUE, "exporter", "otlp_grpc/jaeger")
    conn = c.box(800, 540, 290, 80, TEAL, "connector", "span_metrics")
    ex_p = c.box(800, 700, 290, 80, BLUE, "exporter", "prometheus :8889")
    bus = 740
    c.line([(660, 753), (bus, 753), (bus, 300)], LINE, AW)
    for b in (ex_t, ex_j, conn):
        c.line([(bus, b.cy), (b.x, b.cy)], LINE, AW, head=True)
    c.connect(conn, ex_p, "metrics", n=4, pos="right", at=(945, 660))
    c.connect(app, rcv, "OTLP", n=1, sa="right", sb="left", fa=(300 - 230) / 130, pos="above", at=(345, 300))

    c.frame(1190, 150, 370, 730, "back ends", "group")
    tempo = c.node(1220, 260, 310, 80, ORANGE, "Tempo", "db", "course-otel")
    jae = c.node(1220, 380, 310, 80, ORANGE, "Jaeger", "db", "observability")
    prom = c.node(1220, 700, 310, 80, ORANGE, "Prometheus", "db", "scrapes :8889")
    c.connect(ex_t, tempo, "spans", n=3, pos="above", at=(1155, 300))
    c.connect(ex_j, jae, "spans", pos="above")
    c.connect(prom, ex_p, "scrape", dashed=True, pos="above")
    c.save(OUT, "25-collector-pipeline")


if __name__ == "__main__":
    pipeline()
