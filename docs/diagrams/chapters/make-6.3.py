#!/usr/bin/env python3
"""Draw the diagrams for module 6.3 (autoscaling) with the kit in ../bbg.py.

  6.3-hpa-loop     checkout metrics flow through Prometheus and the adapter to the HPA
  6.3-keda-queue   KEDA watches a Redis list and scales its worker Deployment

Run from anywhere: python3 docs/diagrams/chapters/make-6.3.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def hpa_loop():
    c = Canvas(1600, 1600)
    c.title("Scale from", "measured demand")
    c.subtitle("Prometheus supplies checkout's request rate. The HPA compares it with a target and changes the replica count.")

    c.frame(40, 145, 1520, 810, "OrbStack cluster", "cluster")
    c.frame(80, 225, 350, 660, "control plane", "group")
    controller = c.box(110, 345, 290, 90, PURPLE, "HPA controller", "compares value with target")
    metrics = c.box(110, 560, 290, 80, PURPLE, "metrics-server", "CPU and memory")

    c.frame(460, 245, 1070, 640, "node k3d-k8s-lab-server-0", "node")
    c.frame(490, 315, 400, 500, "namespace course-sre", "ns")
    load = c.frame(520, 390, 150, 100, "loadgen pod", "pod")
    c.box(535, 430, 120, 42, SLATE, "curl")
    checkout = c.frame(700, 390, 160, 100, "checkout pod", "pod")
    c.box(715, 430, 130, 42, SLATE, "checkout")
    cpu = c.frame(520, 555, 150, 100, "cpu-demo pod", "pod")
    c.box(535, 595, 120, 42, SLATE, "CPU loop")

    c.frame(950, 315, 250, 220, "namespace observability", "ns")
    prom = c.box(980, 395, 190, 80, ORANGE, "Prometheus", "scrapes every 15 s")
    c.frame(1260, 315, 240, 220, "namespace course-autoscale", "ns", size=15)
    adapter = c.box(1290, 395, 180, 80, PURPLE, "adapter", "custom metrics API")

    c.connect(load, checkout, "orders", sa="right", sb="left", fa=0.5, fb=0.5, at=(685, 450), pos="above")
    c.connect(checkout, prom, "scrape", n=1, sa="right", sb="left", fa=0.5, fb=0.5, at=(920, 440), pos="above")
    c.connect(prom, adapter, "rate", n=2, sa="right", sb="left", fa=0.5, fb=0.5, at=(1230, 435), pos="above")
    c.connect(adapter, controller, "per-pod rate", n=3, sa="top", sb="top",
              via=[(1380, 200), (255, 200)], at=(815, 200), pos="above")
    c.connect(metrics, controller, "CPU", n=3, sa="top", sb="bottom", at=(255, 500), pos="right", col=TEAL)
    c.connect(controller, checkout, "scale", n=4, sa="right", sb="left",
              via=[(445, 390), (445, 440)], at=(445, 415), pos="below")
    c.connect(controller, cpu, "CPU", n=4, sa="right", sb="left",
              via=[(445, 390), (445, 710), (500, 710), (500, 605)], at=(445, 710), pos="below", col=TEAL)
    c.save(OUT, "6.3-hpa-loop")


def keda_queue():
    c = Canvas(1600, 1600)
    c.title("Wake workers", "from a queue")
    c.subtitle("KEDA watches Redis even when no worker pod runs, then scales the Deployment with the waiting work.")

    c.frame(40, 145, 1520, 710, "OrbStack cluster", "cluster")
    c.frame(100, 220, 1450, 590, "node k3d-k8s-lab-server-0", "node")
    c.frame(140, 300, 800, 450, "namespace course-sre", "ns")
    producer = c.frame(175, 390, 200, 105, "producer pod", "pod")
    c.box(195, 435, 160, 45, SLATE, "loadgen")
    redis = c.frame(470, 370, 220, 145, "queue pod", "pod")
    c.box(490, 425, 180, 60, ORANGE, "Redis", "list: orders")
    worker = c.frame(470, 565, 220, 125, "worker pods", "group")
    c.box(490, 610, 180, 58, SLATE, "worker", "0 to 5 replicas")
    scaled = c.box(740, 335, 165, 70, PURPLE, "ScaledObject", "list length: 10", size=17)

    c.frame(1080, 300, 390, 390, "namespace keda", "ns")
    operator = c.box(1110, 385, 330, 100, PURPLE, "KEDA operator", "polls Redis every 5 s")
    hpa = c.box(1110, 535, 330, 80, PURPLE, "generated HPA", "scales the Deployment")

    c.connect(producer, redis, "push orders", n=1, sa="right", sb="left", fa=0.5, fb=0.5, at=(425, 445), pos="above")
    c.connect(operator, redis, "length", n=2, sa="left", sb="right", fa=0.55, fb=0.75,
              at=(890, 440), pos="above")
    c.connect(operator, scaled, "watches", sa="left", sb="right", fa=0.8, fb=0.5, at=(1060, 490), pos="below",
              dashed=True, col=PURPLE)
    c.connect(operator, hpa, "desired replicas", n=3, sa="bottom", sb="top", at=(1275, 510), pos="right")
    c.connect(hpa, worker, "start or stop pods", n=3, sa="left", sb="right", fa=0.8, fb=0.55,
              at=(850, 634), pos="below")
    c.connect(worker, redis, "pop order", n=4, sa="top", sb="bottom", at=(580, 540), pos="right", col=TEAL)
    c.save(OUT, "6.3-keda-queue")


if __name__ == "__main__":
    hpa_loop()
    keda_queue()
