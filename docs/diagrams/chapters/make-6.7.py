#!/usr/bin/env python3
"""Draw the centralized logging diagram for module 6.7 with the kit in ../bbg.py."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def centralized_logs():
    c = Canvas(1600, 1600)
    c.title("From container", "to searchable logs")
    c.subtitle("Fluent Bit reads the node's container logs, adds Kubernetes labels and sends them to Loki.")

    c.frame(40, 150, 300, 1290, "your terminal", "host")
    query = c.box(70, 1190, 240, 90, SLATE, "LogQL query", "namespace + app")
    result = c.box(70, 1330, 240, 70, GREEN, "error lines", "from Loki")

    c.frame(390, 150, 1170, 1290, "OrbStack cluster", "cluster")
    c.frame(430, 220, 1090, 1180, "node k3d-k8s-lab-server-0", "node")
    c.frame(470, 290, 1010, 245, "namespace course-sre", "ns")
    c.frame(690, 350, 570, 145, "pod checkout", "pod")
    app = c.box(720, 405, 510, 60, SLATE, "checkout", "JSON to stdout")
    logs = c.band(470, 570, 1010, 75, GREEN, "node log files", "/var/log/containers", icon="log")
    c.frame(470, 700, 470, 330, "namespace course-logging", "ns")
    c.frame(520, 775, 370, 150, "Fluent Bit pod", "pod")
    fb = c.box(550, 830, 310, 60, TEAL, "tail + enrich", "Kubernetes labels")
    c.frame(990, 700, 490, 630, "namespace observability", "ns")
    c.frame(1040, 775, 390, 150, "Loki pod", "pod")
    loki = c.box(1070, 830, 330, 60, ORANGE, "Loki", "shared store")

    c.connect(app, logs, "", n=1, sa="bottom", sb="top", fa=0.5, fb=0.5, pos="right")
    c.connect(logs, fb, "tails", n=2, sa="bottom", sb="top", fa=0.35, fb=0.5,
              via=[(824, 675), (705, 675)], at=(765, 675), pos="right")
    c.connect(fb, loki, "pushes labeled lines", n=3, sa="right", sb="left", fa=0.5, fb=0.5, at=(925, 860), pos="above")
    c.connect(query, loki, "queries", n=4, sa="right", sb="bottom", fa=0.5, fb=0.5,
              via=[(365, 1235), (1235, 1235), (1235, 1000)], at=(810, 1235), pos="above")
    c.connect(loki, result, "returns matches", sa="bottom", sb="right", fa=0.5, fb=0.5,
              via=[(1235, 1355), (360, 1355), (360, 1365)], at=(700, 1355), pos="below")
    c.save(OUT, "6.7-centralized-logs")


if __name__ == "__main__":
    centralized_logs()
