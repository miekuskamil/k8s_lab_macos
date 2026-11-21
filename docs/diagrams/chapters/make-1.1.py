#!/usr/bin/env python3
"""Draw the diagrams for course module 1.1 (setup) with the kit in ../bbg.py.

  00-observability-tools   the five tools, the question each one answers, and the data they read

Run from anywhere: python3 docs/diagrams/chapters/make-1.1.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def tools():
    c = Canvas(1600, 860)
    c.title("Five tools,", "five questions")
    c.subtitle("Pick the tool by the question you have. Each one reads data the mesh produces inside the cluster.")

    c.frame(40, 150, 300, 670, "Your Mac", "host")
    browser = c.node(70, 360, 240, 110, SLATE, "Browser", "globe")
    cli = c.node(70, 670, 240, 110, SLATE, "istioctl", "terminal", "which config now?")

    c.frame(380, 150, 1180, 670, "Cluster", "cluster")
    kiali = c.node(430, 200, 300, 110, TEAL, "Kiali", "eye", "what talks to what?")
    graf = c.node(430, 360, 300, 110, TEAL, "Grafana", "chart", "how bad, since when?")
    jaeg = c.node(430, 520, 300, 110, ORANGE, "Jaeger", "search", "where did time go?")
    prom = c.node(830, 200, 290, 110, ORANGE, "Prometheus", "db", "metrics")
    loki = c.node(830, 400, 290, 110, ORANGE, "Loki", "db", "what did pods print?")

    mesh = c.frame(1200, 190, 320, 440, "Mesh", "ns")
    for i, (lab, col) in enumerate([("frontend", SLATE), ("backend", SLATE), ("ztunnel", BLUE), ("waypoint", BLUE)]):
        c.box(1230, 240 + i * 92, 260, 66, col, lab)
    ist = c.node(1200, 670, 320, 110, PURPLE, "istiod", "gear", "pushes config")

    c.connect(mesh, prom, "metrics", sa="left", sb="right", fa=(255 - 190) / 440, pos="above", col=ORANGE)
    c.connect(mesh, loki, "logs", sa="left", sb="right", fa=(455 - 190) / 440, pos="above", col=ORANGE)
    c.connect(mesh, jaeg, "traces", sa="left", sb="right", fa=(590 - 190) / 440, fb=70 / 110, pos="above", col=ORANGE,
              at=(1000, 590))
    c.connect(prom, kiali, "reads", sa="left", sb="right", pos="above", dashed=True)
    c.connect(prom, graf, "", sa="left", sb="right", fa=0.8, fb=0.25, mid=780, dashed=True)
    c.connect(loki, graf, "", sa="left", sb="right", fa=0.3, fb=0.75, dashed=True)
    c.connect(jaeg, graf, "", sa="top", sb="bottom", fa=0.3, fb=0.3, dashed=True)
    c.connect(ist, mesh, "config", sa="top", sb="bottom", dashed=True, col=PURPLE)
    for t in (kiali, graf, jaeg):
        c.connect(browser, t, sa="right", sb="left", fa=0.5 + (t.cy - graf.cy) / 400, mid=375)
    c.connect(cli, ist, "asks istiod and the proxies", sa="right", sb="left", pos="above", at=(760, 725))
    c.save(OUT, "1.1-observability-tools")


if __name__ == "__main__":
    tools()
