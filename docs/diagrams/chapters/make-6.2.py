#!/usr/bin/env python3
"""Draw the diagram for module 6.2 (Grafana in depth) with the kit in ../bbg.py.

  6.2-dashboards-from-git   a dashboard from a git push to Grafana, and an alert rule from the API to a webhook

Run from anywhere: python3 docs/diagrams/chapters/make-6.2.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def from_git():
    c = Canvas(1600, 1140)
    c.title("Dashboards from Git,", "alerts from the API")
    c.subtitle("Orange steps carry a dashboard from a push to the screen. Teal steps carry an alert rule to a person.")

    c.frame(40, 150, 360, 950, "your terminal", "host")
    repo = c.box(70, 220, 300, 90, ORANGE, "git push", "slo, red, use .json")
    curl = c.box(70, 825, 300, 90, TEAL, "curl", "provisioning API")

    c.frame(450, 150, 1120, 970, "cluster", "cluster")
    c.frame(480, 200, 420, 300, "namespace course-sre", "ns")
    gitea = c.box(510, 250, 360, 80, SLATE, "Gitea", "sre-dashboards.git")
    cms = c.box(510, 390, 360, 80, ORANGE, "3 ConfigMaps", "grafana_dashboard=1")
    c.frame(980, 200, 560, 140, "namespace argocd", "ns")
    argo = c.box(1010, 250, 500, 70, PURPLE, "ArgoCD", "Application sre-dashboards")

    c.frame(480, 560, 1060, 410, "", "ns", right="namespace observability")
    c.frame(510, 610, 670, 330, "Grafana pod", "pod")
    side = c.box(540, 660, 270, 80, TEAL, "sidecar", "watches ConfigMaps")
    graf = c.box(870, 660, 270, 80, TEAL, "grafana", "provisioned, read-only")
    rule = c.box(870, 830, 270, 80, RED, "alert rule", "every 30 s")
    loki = c.box(1240, 830, 270, 80, ORANGE, "Loki", "checkout's logs")
    c.frame(1210, 990, 330, 110, "", "ns", right="namespace course-sre")
    recv = c.box(1240, 1035, 210, 55, SLATE, "alert-receiver")

    # A dashboard, from a push to Grafana
    c.connect(repo, gitea, "", n=1, sa="right", sb="left", fa=0.5, fb=0.5, mid=430, at=(430, 280))
    c.connect(argo, gitea, "fetch", n=2, sa="left", sb="right", fa=0.5, fb=0.5, pos="above", at=(940, 285))
    c.connect(argo, cms, "apply", n=3, sa="bottom", sb="right", fa=0.3, fb=0.5, pos="right", at=(1160, 430))
    c.connect(cms, side, "", n=4, sa="bottom", sb="top", fa=0.5, fb=150 / 270, at=(690, 520))
    c.connect(side, graf, "", n=5, at=(840, 700))

    # An alert rule, from the API to a person
    c.connect(curl, rule, "", sa="right", sb="left", col=TEAL)
    c.step(450, 870, 1, col=TEAL, ink=WHITE)
    c.text(450, 838, "POST", 18, deep(TEAL), True, "middle", halo=True)
    c.connect(graf, rule, "evaluates", sa="bottom", sb="top", pos="right")
    c.connect(rule, loki, "", sa="right", sb="left", col=TEAL)
    c.text(1190, 838, "query", 18, deep(TEAL), True, "middle", halo=True)
    c.step(1190, 870, 2, col=TEAL, ink=WHITE)
    c.connect(rule, recv, "", sa="bottom", sb="left", fa=0.5, fb=0.5, col=TEAL)
    c.step(1005, 1000, 3, col=TEAL, ink=WHITE)
    c.text(1030, 1006, "firing, webhook", 18, deep(TEAL), True, halo=True)
    c.save(OUT, "6.2-dashboards-from-git")


if __name__ == "__main__":
    from_git()
