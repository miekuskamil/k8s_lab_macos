#!/usr/bin/env python3
"""Draw the diagram for module 24 (Grafana as code) in ByteByteGo style (see ../bbg.py).

  24-dashboard-provisioning     a dashboard file in Git reaches Grafana in four steps

Run from anywhere: python3 docs/diagrams/chapters/make-24.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def provisioning():
    c = Canvas(1560, 700)
    c.title("How a dashboard gets into", "Grafana")
    c.subtitle("A dashboard file in Git reaches Grafana in four steps, like any other manifest.")

    c.node(300, 190, 380, 110, ORANGE, "Git", "doc", "ConfigMap + dashboard JSON")
    c.node(1060, 190, 420, 110, SLATE, "ConfigMap", "doc", "grafana_dashboard=1")
    c.arrow([(680, 245), (1060, 245)], "ArgoCD or kubectl", n=1, at=(870, 245), pos="below")

    c.group(40, 440, 1480, 200, "Grafana pod")
    c.node(80, 480, 380, 110, GREEN, "Grafana", "eye", "marked provisioned")
    c.node(580, 480, 380, 110, ORANGE, "/tmp/dashboards", "doc", "dashboard JSON", size=22)
    c.node(1080, 480, 400, 110, TEAL, "Sidecar", "gear", "second container")
    c.arrow([(1270, 300), (1270, 480)], "Watch every\nnamespace", n=2, at=(1270, 370))
    c.arrow([(1080, 535), (960, 535)], "Write", n=3, at=(1020, 535), pos="above")
    c.arrow([(580, 535), (460, 535)], "Load", n=4, at=(520, 535), pos="above")
    c.save(OUT, "24-dashboard-provisioning")


if __name__ == "__main__":
    provisioning()
