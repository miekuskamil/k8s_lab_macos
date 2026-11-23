#!/usr/bin/env python3
"""Draw the diagram for module 6.1 (SLIs, SLOs and error budgets) with the kit in ../bbg.py.

  6.1-slo-pipeline   from a request counter to a page, through Sloth's rules

Run from anywhere: python3 docs/diagrams/chapters/make-6.1.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def slo_pipeline():
    c = Canvas(1600, 980)
    c.title("From a counter", "to a page")
    c.subtitle("Sloth writes the rules once. Prometheus turns checkout's counters into burn rates every 30 s.")

    # Your machine: the spec and Sloth
    c.frame(40, 150, 420, 330, "your terminal", "host")
    spec = c.box(80, 210, 340, 80, ORANGE, "SLO spec", "60 lines of YAML")
    sloth = c.box(80, 360, 340, 80, PURPLE, "Sloth", "docker run")
    c.connect(spec, sloth, "generate", n=1, pos="right")

    # The app namespace
    c.frame(40, 530, 420, 410, "namespace course-sre", "ns")
    lg = c.box(80, 590, 160, 80, SLATE, "loadgen", "8 per second")
    co = c.box(80, 720, 340, 90, SLATE, "checkout", "/metrics")
    pay = c.box(260, 590, 160, 80, SLATE, "payments", "podinfo")
    c.connect(lg, co, "", fa=0.5, fb=80 / 340, sa="bottom", sb="top")
    c.connect(co, pay, "", sa="top", sb="bottom", fa=260 / 340, fb=0.5)
    rule = c.box(80, 840, 340, 70, RED, "PrometheusRule", "checkout")

    # Prometheus
    c.frame(540, 150, 1020, 790, "namespace observability", "ns")
    c.frame(580, 210, 580, 700, "Prometheus pod", "plain", col=ORANGE, icon="db")
    scr = c.box(620, 270, 500, 80, ORANGE, "scrape", "http_request_duration_seconds")
    sli = c.box(620, 410, 500, 90, ORANGE, "SLI recording rules", "error ratio over 8 windows")
    meta = c.box(620, 560, 500, 90, ORANGE, "budget rules", "burn rate, budget left")
    alerts = c.box(620, 710, 500, 140, RED, "burn-rate alerts", "page: 5m and 1h above 14.4x\nticket: 2h and 1d above 3x")
    am = c.node(1250, 720, 280, 120, RED, "Alertmanager", "bell", "routes the page")
    graf = c.node(1250, 405, 280, 100, TEAL, "Grafana", "chart", "module 6.2")

    c.connect(sloth, rule, "kubectl apply", n=2, sa="left", sb="left", via=[(20, 400), (20, 875)], pos="right", at=(20, 505))
    c.connect(co, scr, "", n=3, sa="right", sb="left", fa=0.5, fb=0.5, mid=500, at=(500, 540))
    c.connect(rule, alerts, "loaded", sa="right", sb="left", fa=0.5, fb=0.85, mid=520, pos="above", at=(470, 875))
    c.connect(scr, sli, "every 30 s", n=4, pos="right")
    c.connect(sli, meta, "")
    c.connect(meta, alerts, "")
    c.connect(alerts, am, "firing", n=5, sa="right", sb="left", pos="above", at=(1205, 780))
    c.connect(sli, graf, "reads", sa="right", sb="left", dashed=True, pos="above")
    c.save(OUT, "6.1-slo-pipeline")


if __name__ == "__main__":
    slo_pipeline()
