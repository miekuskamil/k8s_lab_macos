#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/3-istio/20-installing-istio.md with the kit in ../bbg.py.

  3.20-profiles       which components each install profile turns on
  3.20-install-flow   profile + IstioOperator + --set, rendered from the same charts Helm uses

Run from anywhere: python3 docs/diagrams/chapters/make-3.20.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def profiles():
    c = Canvas(1600, 820)
    c.title("Install profiles:", "what each turns on")
    c.subtitle("Measured with istioctl 1.24.2 manifest generate --set profile=<name>.")

    comps = [("istiod", PURPLE), ("ingress gateway", BLUE), ("egress gateway", BLUE), ("istio-cni", TEAL),
             ("ztunnel", BLUE)]
    rows = [("minimal", [1, 0, 0, 0, 0]), ("default", [1, 1, 0, 0, 0]),
            ("demo", [1, 1, 1, 0, 0]), ("ambient", [1, 0, 0, 1, 1])]
    for j, (name, on) in enumerate(rows):
        x = 40 + j * 385
        c.frame(x, 150, 365, 600, f"profile {name}", "cluster")
        for i, ((comp, col), flag) in enumerate(zip(comps, on)):
            y = 210 + i * 104
            if flag:
                c.box(x + 25, y, 315, 84, col, comp, size=19)
            else:
                c.rect(x + 25, y, 315, 84, DIM, "none", 10, 1.4, True)
                c.text(x + 182, y + 49, comp, 18, DIM, False, "middle")
    c.note(40, 790, "demo also lowers resource requests and turns on access logs.", 18)
    c.save(OUT, "3.20-profiles")


def install_flow():
    c = Canvas(1600, 900)
    c.title("Two installers,", "one set of charts")
    c.subtitle("istioctl merges its inputs and renders the same Helm charts that helm install uses.")

    c.frame(40, 150, 720, 710, "Your Mac", "host")
    ins = [c.box(70, 210, 280, 80, SLATE, "profile", "minimal, ambient, ..."),
           c.box(70, 320, 280, 80, SLATE, "IstioOperator file", "-f 32-istio-operator"),
           c.box(70, 430, 280, 80, SLATE, "--set flags", "later input wins")]
    ictl = c.node(430, 290, 300, 150, PURPLE, "istioctl", "terminal", "merge, then\nrender")
    for i, b in enumerate(ins):
        c.connect(b, ictl, "", sa="right", sb="left", fb=(0.25, 0.5, 0.75)[i], mid=390)
    charts = c.node(430, 560, 300, 130, ORANGE, "Istio charts", "layers", "base, istiod, cni,\nztunnel, gateways")
    c.connect(ictl, charts, "render", n=1, pos="right")
    helm = c.node(70, 700, 280, 120, BLUE, "helm install", "terminal", "values files,\nmodule 3.19")
    c.connect(helm, charts, "same charts", sa="right", sb="bottom", fa=0.5, fb=0.5, pos="above", at=(470, 760))

    c.frame(820, 150, 740, 710, "Cluster", "cluster")
    c.frame(860, 200, 660, 180, "namespace istio-system", "ns")
    c.node(890, 250, 300, 100, PURPLE, "istiod", "gear")
    c.node(1210, 250, 280, 100, BLUE, "gateways", "shield", "if the profile\nhas them")
    c.frame(860, 430, 660, 390, "Node", "node")
    c.band(890, 490, 600, 120, TEAL, "istio-cni", "DaemonSet, ambient", "server")
    c.band(890, 650, 600, 120, BLUE, "ztunnel", "DaemonSet, ambient", "tunnel")
    c.connect(ictl, Box(820, 150, 740, 710), "apply, wait,\nprune", n=2, sa="right", sb="left", fa=0.4,
              fb=(350 - 150) / 710, pos="above", at=(780, 350))
    c.note(70, 845, "istioctl manifest generate stops after step 1.", 16)
    c.save(OUT, "3.20-install-flow")


if __name__ == "__main__":
    profiles()
    install_flow()
