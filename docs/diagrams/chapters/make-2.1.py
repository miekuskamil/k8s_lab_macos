#!/usr/bin/env python3
"""Draw the diagram for module 2.1 (Prometheus and alerting) with the kit in ../bbg.py.

  2.1-scrape-to-page     from a /metrics page to a person, in four steps

Run from anywhere: python3 docs/diagrams/chapters/make-2.1.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def scrape_to_page():
    c = Canvas(1600, 840)
    c.title("From scrape", "to page")
    c.subtitle("Prometheus reads and judges the numbers. Alertmanager decides who hears about it, and how often.")

    shop = c.frame(40, 150, 360, 650, "namespace shop", "ns")
    for i, (t, col) in enumerate([("frontend", SLATE), ("backend", SLATE), ("waypoint", BLUE), ("ztunnel", BLUE)]):
        c.box(70, 210 + i * 140, 300, 100, col, t, "/metrics")

    c.frame(460, 150, 1100, 650, "namespace observability", "ns")
    prom = c.frame(500, 210, 420, 400, "Prometheus pod", "plain", col=ORANGE, icon="db")
    scr = c.box(530, 270, 360, 80, ORANGE, "scrape", "every 15 s")
    tsdb = c.box(530, 380, 360, 80, ORANGE, "store", "time series")
    rules = c.box(530, 490, 360, 90, RED, "rules", "evaluated every 30 s")
    c.connect(scr, tsdb)
    c.connect(tsdb, rules, "", n=2, at=(710, 475))
    am = c.node(1040, 300, 470, 130, RED, "Alertmanager", "bell", "group, hold back, route")
    rcv = c.node(1040, 560, 470, 120, SLATE, "receiver", "doc", "a log here, Slack in production")
    graf = c.node(500, 680, 420, 90, TEAL, "Grafana", "chart", "dashboards (module 2.2)")

    c.connect(shop, scr, "", n=1, sa="right", sb="left", fa=(310 - 150) / 650, pos="above", at=(430, 310))
    c.connect(rules, am, "firing alerts", n=3, sa="right", sb="left", fa=0.5, fb=0.8, pos="above", at=(985, 535))
    c.connect(am, rcv, "webhook", n=4, pos="right")
    c.connect(prom, graf, "reads", sa="bottom", sb="top", dashed=True, pos="right")
    c.save(OUT, "2.1-scrape-to-page")


if __name__ == "__main__":
    scrape_to_page()
