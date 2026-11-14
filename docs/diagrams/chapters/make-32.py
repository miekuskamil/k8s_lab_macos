#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/32-installing-istio.md in ByteByteGo style (see ../bbg.py).

  32-profiles       which components each install profile turns on
  32-install-flow   profile + IstioOperator + --set, rendered from the same charts Helm uses

Run from anywhere: python3 docs/diagrams/chapters/make-32.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def profiles():
    c = Canvas(1700, 820)
    c.title("Install profiles:", "what each turns on")
    c.subtitle("Measured with istioctl 1.24.2 manifest generate --set profile=<name>.")

    cols = [("istiod", PURPLE), ("ingress gateway", BLUE), ("egress gateway", BLUE),
            ("istio-cni", TEAL), ("ztunnel", TEAL)]
    rows = [("minimal", [1, 0, 0, 0, 0]), ("default", [1, 1, 0, 0, 0]),
            ("demo", [1, 1, 1, 0, 0]), ("ambient", [1, 0, 0, 1, 1])]
    x0, y0, cw, rh = 300, 170, 270, 120
    for i, (name, col) in enumerate(cols):
        c.node(x0 + i * cw + 10, y0, cw - 20, 80, col, name, None, size=21)
    for j, (name, on) in enumerate(rows):
        y = y0 + 120 + j * rh
        c.outline(40, y, 230, 90, SLATE, name, size=24)
        for i, flag in enumerate(on):
            cx = x0 + i * cw + cw / 2
            if flag:
                c.ellipse(cx, y + 45, 26, 26, GREEN, GREEN)
                c.line([(cx - 12, y + 46), (cx - 3, y + 56), (cx + 13, y + 35)], INK, 4)
            else:
                c.ellipse(cx, y + 45, 26, 26, DIM, "none", sw=2)
    c.note(300, 790, ["demo also lowers resources and turns on access logs."], 18)
    c.save(OUT, "32-profiles")


def install_flow():
    c = Canvas(1700, 820)
    c.title("Two installers,", "one set of charts")
    c.subtitle("istioctl merges its inputs and renders the same Helm charts that helm install uses.")

    c.outline(40, 180, 330, 90, SLATE, "profile\nminimal, ambient")
    c.outline(40, 310, 330, 90, SLATE, "IstioOperator file\n-f 32-istio-operator")
    c.outline(40, 440, 330, 90, SLATE, "--set flags\nmeshConfig...")
    c.node(500, 290, 320, 130, PURPLE, "istioctl", "gear", "merge, render")
    for y in (225, 355, 485):
        c.arrow([(370, y), (500, 355)], "", col=SOFT)
    c.node(950, 290, 320, 130, ORANGE, "Istio charts", "doc", "base, istiod, cni")
    c.arrow([(820, 355), (950, 355)], "", n=1, at=(885, 355), dashed=False)
    c.node(1380, 290, 280, 130, GREEN, "cluster", "server", "applied, pruned")
    c.arrow([(1270, 355), (1380, 355)], "", n=2, at=(1325, 355), dashed=False)

    c.outline(950, 560, 320, 90, SLATE, "helm values files")
    c.node(500, 560, 320, 90, BLUE, "helm install", "cube")
    c.arrow([(820, 605), (950, 605)], "", dashed=False)
    c.arrow([(1110, 560), (1110, 420)], "same charts", at=(1110, 490), pos="right", col=SOFT)
    c.arrow([(1270, 605), (1520, 420)], "", col=SOFT)
    c.text(660, 700, "module 14: Helm and revisions", 18, SOFT, True, "middle")
    c.text(1325, 262, "manifest generate", 17, SOFT, True, "middle")
    c.text(1325, 284, "stops before 2", 17, SOFT, True, "middle")
    c.save(OUT, "32-install-flow")


if __name__ == "__main__":
    profiles()
    install_flow()
