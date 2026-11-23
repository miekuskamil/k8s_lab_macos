#!/usr/bin/env python3
"""Draw the diagram for module 6.3 (chaos engineering with Chaos Mesh) with the kit in ../bbg.py.

  6.3-how-a-fault-lands   from a NetworkChaos resource to delayed packets in a pod, and the SLO that notices

Run from anywhere: python3 docs/diagrams/chapters/make-6.3.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def fault():
    c = Canvas(1600, 1000)
    c.title("How a fault", "lands in a pod")
    c.subtitle("You write the experiment. The daemon on the node changes the pod's network from the inside, and the SLO shows the cost.")

    c.frame(40, 150, 330, 310, "your terminal", "host")
    yaml = c.box(70, 245, 270, 90, PINK, "NetworkChaos", "delay 300 ms")
    abort = c.box(70, 360, 270, 70, SLATE, "kubectl delete", "abort, fault gone")

    c.frame(420, 150, 1140, 770, "node k3d-k8s-lab-server-0", "node")
    c.frame(450, 200, 480, 160, "namespace chaos-mesh", "ns")
    ctrl = c.box(480, 250, 420, 80, PURPLE, "controller-manager", "watches experiments")
    daemon = c.box(980, 250, 540, 80, PINK, "chaos-daemon", "privileged, one per node")

    c.frame(450, 420, 1080, 310, "namespace course-sre", "ns")
    lg = c.box(480, 520, 200, 80, SLATE, "loadgen")
    co = c.box(760, 520, 220, 80, SLATE, "checkout", "1 s timeout")
    pp = c.frame(1060, 470, 440, 230, "payments pod", "pod")
    pay = c.box(1090, 520, 380, 70, SLATE, "podinfo")
    tc = c.box(1090, 610, 380, 60, GREEN, "tc netem in its netns", "+300 ms on egress")

    prom = c.box(450, 800, 440, 80, ORANGE, "Prometheus", "latency SLI over 5m")
    page = c.box(1030, 800, 500, 80, RED, "page", "CheckoutLatencyBudgetBurn")

    c.connect(yaml, ctrl, "", n=1, sa="right", sb="left", fa=0.5, fb=0.5, mid=395, at=(395, 290))
    c.connect(ctrl, daemon, "", n=2)
    c.connect(daemon, pp, "enters its netns", n=3, sa="bottom", sb="top", fa=(1280 - 980) / 540, fb=(1280 - 1060) / 440, pos="right", at=(1280, 390))
    c.connect(lg, co, "", pos="above")
    c.connect(co, pay, "", n=4, sa="right", sb="left", fa=0.5, fb=0.5, at=(1020, 555))
    c.connect(co, prom, "slower orders", n=5, sa="bottom", sb="top", fa=40 / 220, fb=350 / 440, pos="right", at=(800, 750))
    c.connect(prom, page, "burn > 14.4", pos="above")
    c.save(OUT, "6.3-how-a-fault-lands")


if __name__ == "__main__":
    fault()
