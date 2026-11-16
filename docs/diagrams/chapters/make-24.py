#!/usr/bin/env python3
"""Draw the diagram for module 24 (Grafana as code) with the kit in ../bbg.py.

  24-dashboard-provisioning     a dashboard file in Git reaches Grafana in four steps

Run from anywhere: python3 docs/diagrams/chapters/make-24.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def provisioning():
    c = Canvas(1600, 820)
    c.title("How a dashboard gets", "into Grafana")
    c.subtitle("A ConfigMap with one label reaches Grafana through a sidecar container and a shared folder.")

    c.frame(40, 200, 280, 260, "GitHub", "plain", icon="git")
    git = c.node(65, 270, 230, 120, ORANGE, "Git", "git", "dashboard JSON")

    c.frame(360, 150, 1200, 640, "Cluster", "cluster")
    c.frame(400, 190, 420, 180, "namespace argocd", "ns")
    argo = c.node(430, 240, 360, 100, PURPLE, "ArgoCD", "refresh", "or kubectl apply")
    c.connect(git, argo, "sync", sa="right", sb="left", fa=(290 - 270) / 120, fb=0.5, pos="above", at=(375, 290))

    c.frame(400, 440, 1130, 320, "namespace observability", "ns")
    cm = c.node(430, 520, 330, 130, SLATE, "ConfigMap", "doc", "dashboard JSON")
    c.chip(595, 690, 'grafana_dashboard: "1"', SLATE, anchor="middle", size=14)
    pod = c.frame(860, 480, 640, 250, "Grafana pod", "pod")
    side = c.box(890, 530, 250, 90, TEAL, "sidecar", "watches ConfigMaps")
    graf = c.box(1220, 530, 250, 90, TEAL, "grafana", "loads the folder")
    vol = c.band(890, 650, 580, 56, ORANGE, "/tmp/dashboards", "", None, size=18, lx=1050)

    c.connect(argo, cm, "apply", n=1, sa="bottom", sb="top", fa=0.5, fb=(610 - 430) / 330, pos="right", at=(610, 405))
    c.connect(cm, side, "watch label", n=2, sa="right", sb="left", fa=(575 - 520) / 130, pos="above", at=(825, 575))
    c.connect(side, vol, "write", n=3, sa="bottom", sb="top", fa=0.5, fb=(1015 - 890) / 580, pos="right", at=(1015, 635))
    c.connect(vol, graf, "read", n=4, sa="top", sb="bottom", fa=(1345 - 890) / 580, fb=0.5, pos="right", at=(1345, 635))
    c.save(OUT, "24-dashboard-provisioning")


if __name__ == "__main__":
    provisioning()
