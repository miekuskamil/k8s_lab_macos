#!/usr/bin/env python3
"""Draw the diagrams for module 6.6 (capacity and cost) with the kit in ../bbg.py.

  6.6-right-sizing       Kubernetes schedules pods from their resource requests
  6.6-cost-allocation    OpenCost combines cluster metrics and configured rates

Run from anywhere: python3 docs/diagrams/chapters/make-6.6.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def right_sizing():
    c = Canvas(1600, 1600)
    c.title("Reserve what", "the pod needs")
    c.subtitle("The scheduler places pods from their requests. A right-sized request leaves more room for other work.")

    c.frame(40, 150, 1520, 1290, "OrbStack cluster", "cluster")
    c.frame(90, 230, 370, 1080, "control plane", "group")
    scheduler = c.box(125, 360, 300, 100, PURPLE, "scheduler", "checks requests")

    c.frame(500, 230, 1000, 1080, "node k3d-k8s-lab-server-0", "node")
    c.frame(540, 310, 910, 910, "namespace course-capacity", "ns")

    c.frame(590, 405, 380, 330, "Deployment overprovisioned", "group", size=16)
    over_a = c.frame(620, 480, 145, 190, "pod", "pod")
    c.box(635, 540, 115, 64, SLATE, "idle", "250m / 256Mi", size=15)
    over_b = c.frame(795, 480, 145, 190, "pod", "pod")
    c.box(810, 540, 115, 64, SLATE, "idle", "250m / 256Mi", size=15)

    c.frame(590, 820, 800, 300, "Deployment right-sized", "group", size=16)
    right_a = c.frame(630, 895, 145, 175, "pod", "pod")
    c.box(645, 950, 115, 64, SLATE, "idle", "100m / 128Mi", size=15)
    right_b = c.frame(820, 895, 145, 175, "pod", "pod")
    c.box(835, 950, 115, 64, SLATE, "idle", "100m / 128Mi", size=15)

    c.text(1060, 510, "same work", 18, INK, True, halo=True)
    c.text(1060, 570, "half the requests", 18, GREEN, True, halo=True)
    c.text(1060, 630, "same replica count", 16, SOFT)
    c.text(1060, 955, "more schedulable room", 18, GREEN, True, halo=True)

    c.connect(scheduler, over_a, "places", n=1, sa="right", sb="left",
              via=[(480, 410), (480, 570)], at=(480, 490), pos="above")
    c.connect(scheduler, right_a, "places", n=2, sa="right", sb="left",
              via=[(480, 410), (480, 980)], at=(480, 700), pos="above", col=TEAL)
    c.save(OUT, "6.6-right-sizing")


def cost_allocation():
    c = Canvas(1600, 1600)
    c.title("Turn resource", "use into cost")
    c.subtitle("OpenCost queries Prometheus, applies its price model and returns an allocation for each namespace.")

    c.frame(40, 150, 1520, 1270, "OrbStack cluster", "cluster")
    c.frame(80, 235, 930, 1100, "node k3d-k8s-lab-server-0", "node")
    c.frame(120, 310, 520, 890, "namespace course-capacity", "ns")

    workloads = c.frame(140, 380, 500, 330, "demo workloads", "group")
    over = c.frame(150, 410, 210, 220, "overprovisioned", "group")
    c.box(170, 475, 170, 90, SLATE, "two pods", "500m / 512Mi")
    right = c.frame(390, 410, 210, 220, "right-sized", "group")
    c.box(410, 475, 170, 90, SLATE, "two pods", "200m / 256Mi")
    opencost = c.box(185, 810, 410, 115, PURPLE, "OpenCost", "price model + allocation API")

    c.frame(700, 310, 280, 400, "namespace observability", "ns")
    prom = c.box(735, 425, 210, 100, ORANGE, "Prometheus", "requests and usage")

    c.frame(1110, 300, 380, 580, "your terminal", "host")
    api = c.box(1150, 435, 300, 100, SLATE, "kubectl get --raw", "allocation?window=1h")
    result = c.box(1150, 625, 300, 110, GREEN, "namespace cost", "estimate in USD")

    c.connect(workloads, prom, "scrapes metrics", n=1, sa="right", sb="left", fa=0.5, fb=0.5,
              via=[(670, 545), (670, 475)], at=(670, 510), pos="above")
    c.connect(opencost, prom, "queries", n=2, sa="right", sb="left", fa=0.5, fb=0.8,
              at=(665, 860), pos="above", col=PURPLE)
    c.connect(opencost, api, "serves", n=3, sa="right", sb="left",
              via=[(1035, 865), (1035, 485)], at=(1035, 670), pos="right")
    c.connect(api, result, "returns", n=4, sa="bottom", sb="top", at=(1300, 580), pos="right")
    c.save(OUT, "6.6-cost-allocation")


if __name__ == "__main__":
    right_sizing()
    cost_allocation()
