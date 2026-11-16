#!/usr/bin/env python3
"""Module 16 diagrams: Gateway API next to the Istio API, and a VirtualService canary split."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def two_apis():
    c = Canvas(1600, 920)
    c.title("Same jobs,", "different shapes")
    c.subtitle("Both APIs build an ingress proxy and route to backend versions. The pieces fit together differently.")

    # Gateway API
    c.frame(40, 150, 740, 740, "Gateway API (modules 4, 11)", "group")
    gw = c.node(70, 210, 280, 100, BLUE, "Gateway", "doc", "creates the proxy")
    rt = c.node(470, 210, 280, 100, PURPLE, "HTTPRoute", "doc", "parentRefs")
    pod = c.frame(70, 420, 280, 120, "gateway pod", "pod")
    c.text(90, 510, "Istio creates it", 17, SOFT)
    c.connect(gw, pod, "creates", pos="right")
    c.connect(rt, gw, "attaches to", pos="above")
    c.frame(450, 640, 300, 210, "namespace shop", "ns")
    s1 = c.box(470, 690, 125, 130, SLATE, "Service", "backend\n-v1")
    s2 = c.box(610, 690, 125, 130, TEAL, "Service", "backend\n-v2")
    c.connect(rt, s1, "", sa="bottom", sb="top", fa=(532.5 - 470) / 280)
    c.connect(rt, s2, "", sa="bottom", sb="top", fa=(672.5 - 470) / 280)
    c.text(545, 480, "backendRefs", 17, SOFT, True, halo=True)

    # Istio API
    c.frame(820, 150, 740, 740, "Istio API (this module)", "group")
    helm = c.node(850, 210, 300, 100, SLATE, "Helm chart", "terminal", "istio/gateway")
    igw = c.node(1250, 210, 280, 100, BLUE, "Gateway", "doc", "selector:\nistio=ingress")
    pod2 = c.frame(850, 400, 300, 120, "gateway pod", "pod")
    c.text(870, 490, "you install it", 17, SOFT)
    c.connect(helm, pod2, "installs", pos="right")
    c.connect(igw, pod2, "configures", sa="left", sb="right", fa=0.8, fb=0.5, via=[(1200, 290), (1200, 460)],
              pos="above", at=(1175, 460))
    vs = c.node(1250, 400, 280, 100, PURPLE, "VirtualService", "doc", "gateways: [...]")
    c.connect(vs, igw, "names it", sa="top", sb="bottom", fa=0.6, fb=0.6, pos="right")
    svc = c.frame(850, 640, 300, 210, "Service backend", "ns")
    c.rect(870, 690, 125, 130, SLATE, "none", 10, 1.6, True)
    c.box(882, 715, 100, 70, SLATE, "pods", "v1")
    c.rect(1007, 690, 125, 130, TEAL, "none", 10, 1.6, True)
    c.box(1019, 715, 100, 70, TEAL, "pods", "v2")
    c.text(932, 845, "subset v1", 15, SOFT, True, "middle")
    c.text(1069, 845, "subset v2", 15, SOFT, True, "middle")
    dr = c.node(1250, 700, 280, 100, PURPLE, "DestinationRule", "doc", "subsets by label")
    c.connect(vs, svc, "routes to subsets", sa="left", sb="right", fa=0.8, fb=0.15, via=[(1225, 480), (1225, 671)],
              pos="right", at=(1225, 580))
    c.connect(dr, svc, "defines", sa="left", sb="right", fa=0.5, fb=(750 - 640) / 210, pos="above")
    c.save(OUT, "16-two-apis")


def canary():
    c = Canvas(1600, 820)
    c.title("A VirtualService", "canary")
    c.subtitle("The waypoint of the backend Service runs the rules for host backend and splits the traffic by subset.")

    c.frame(560, 150, 480, 130, "namespace istio-system", "ns")
    ist = c.node(590, 190, 420, 70, PURPLE, "istiod", "gear", "VirtualService + DestinationRule")

    c.frame(40, 320, 1520, 470, "namespace shop", "ns")
    fe = c.frame(80, 470, 280, 150, "frontend pod", "pod")
    c.box(100, 520, 240, 76, SLATE, "app", "calls backend:8000")
    wp = c.frame(470, 380, 440, 360, "waypoint pod", "plain", col=BLUE, icon="shield")
    c.box(500, 440, 380, 90, BLUE, "route for host", "backend.shop.svc")
    c.box(500, 570, 180, 130, SLATE, "90%", "subset v1", size=26)
    c.box(700, 570, 180, 130, TEAL, "10%", "subset v2", size=26)
    c.connect(ist, wp, "Envoy config", dashed=True, col=PURPLE, pos="right", off=-100)
    c.connect(fe, wp, "", sa="right", sb="left", fa=0.5, fb=(558 - 380) / 360)

    svc = c.frame(1010, 380, 510, 360, "Service backend: app=backend", "plain")
    v1 = c.frame(1040, 430, 450, 150, "subset v1: version=v1", "group")
    for i in range(2):
        c.box(1060 + i * 215, 485, 195, 70, SLATE, "pod", "v1")
    v2 = c.frame(1040, 600, 450, 120, "subset v2: version=v2", "group")
    c.box(1060, 650, 195, 56, TEAL, "pod v2", size=18)
    c.connect(wp, v1, "", sa="right", sb="left", fa=(520 - 380) / 360, fb=0.6)
    c.connect(wp, v2, "", sa="right", sb="left", fa=(670 - 380) / 360, fb=0.58)
    c.save(OUT, "16-virtualservice-canary")


if __name__ == "__main__":
    two_apis()
    canary()
