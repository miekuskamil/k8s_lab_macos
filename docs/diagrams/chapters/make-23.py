#!/usr/bin/env python3
"""Draw the diagram for module 23 (Prometheus and alerting) in ByteByteGo style (see ../bbg.py).

  23-scrape-to-page     from a /metrics page to a person, in four steps

Run from anywhere: python3 docs/diagrams/chapters/make-23.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def scrape_to_page():
    c = Canvas(1560, 720)
    c.title("From scrape", "to page")
    c.subtitle("An alert travels from a pod to a person in four steps.")

    c.node(60, 200, 340, 110, SLATE, "Pods + proxies", "cube", "/metrics")
    c.node(600, 200, 380, 110, ORANGE, "Prometheus", "db", "rules every 30 s")
    c.step(980, 200, 2)
    c.node(1160, 200, 340, 110, PINK, "Alertmanager", "gear", "group · silence · route")
    c.arrow([(400, 255), (600, 255)], "Scrape\nevery 15 s", n=1, at=(500, 255), pos="below")
    c.arrow([(980, 255), (1160, 255)], "Firing\nalerts", n=3, at=(1070, 255), pos="below")

    c.node(1160, 520, 340, 110, SLATE, "Receiver", "person", "Slack · PagerDuty · log")
    c.arrow([(1330, 310), (1330, 520)], "Webhook", n=4, at=(1330, 415))

    c.node(600, 520, 380, 110, TEAL, "Grafana", "eye", "dashboards, module 24")
    c.arrow([(790, 520), (790, 310)], "Query", at=(790, 415), col=SOFT)

    c.note(60, 690, ["Step 2: Prometheus stores series and evaluates rules."], 17)
    c.save(OUT, "23-scrape-to-page")


if __name__ == "__main__":
    scrape_to_page()
