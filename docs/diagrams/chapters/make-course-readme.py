#!/usr/bin/env python3
"""Draw the course map for platform-engineering/README.md in ByteByteGo style (see ../bbg.py).

  readme-course-routes   module 0, then the Istio, operations and platform tracks

Run from anywhere: python3 docs/diagrams/chapters/make-course-readme.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def routes():
    c = Canvas(1780, 940)
    c.title("Routes through", "the Course")
    c.subtitle("Every track starts after module 0. The Istio track runs from the core modules to AI.")

    c.node(60, 190, 320, 110, SLATE, "Start here", "doc", "Istio in one picture")
    c.node(60, 420, 320, 110, TEAL, "0 Setup", "laptop", "cluster and tools")
    c.arrow([(220, 300), (220, 420)], "")

    c.node(520, 190, 340, 110, BLUE, "Istio core", "shield", "modules 1 to 8")
    c.node(980, 190, 360, 110, BLUE, "Istio advanced", "shield", "modules 11 to 16")
    c.node(1460, 190, 280, 110, PURPLE, "AI", "cube", "modules 17 to 19")
    c.arrow([(860, 245), (980, 245)], "")
    c.arrow([(1340, 245), (1460, 245)], "")
    c.note(980, 335, ["edge TLS, egress, JWT,", "upgrades, resilience,", "Istio API"], 17)
    c.note(1460, 335, ["LLMs, model serving,", "agents"], 17)

    c.outline(520, 420, 340, 100, DIM, "Reference\n9 and 10", "doc")
    c.arrow([(690, 300), (690, 420)], "read any time", at=(700, 360), pos="right", col=SOFT)
    c.note(520, 555, ["9 command reference,", "10 eBPF and Cilium"], 17)

    c.node(520, 620, 340, 110, GREEN, "k3s operations", "server", "modules 20 and 21")
    c.node(520, 780, 340, 110, ORANGE, "Platform tools", "gear", "modules 22 to 28")
    c.note(900, 815, ["ArgoCD, Prometheus, Grafana,", "OpenTelemetry, Kyverno, Pyroscope"], 17)

    for y in (245, 675, 835):
        c.arrow([(380, 475), (450, 475), (450, y), (520, y)], "")
    c.save(OUT, "readme-course-routes")


if __name__ == "__main__":
    routes()
