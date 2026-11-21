#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/3-istio/09-sidecar-mode.md with the kit in ../bbg.py.

  07-two-modes         ambient and sidecar namespaces side by side, one istiod
  07-injection         how a one-container Deployment ends up with three containers
  07-two-proxies       a request from client to httpbin passes two Envoys

Run from anywhere: python3 docs/diagrams/chapters/make-3.9.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def two_modes():
    c = Canvas(1600, 900)
    c.title("Two data planes,", "one istiod")
    c.subtitle("Each namespace picks ambient or sidecars with a label. The same istiod configures both.")

    c.frame(40, 150, 1520, 720, "Cluster", "cluster")
    c.frame(560, 180, 480, 150, "namespace istio-system", "ns")
    ist = c.node(590, 225, 420, 86, PURPLE, "istiod", "gear", "one control plane, one CA")

    c.frame(70, 380, 1460, 460, "Node", "node")
    amb = c.frame(100, 430, 560, 270, "namespace shop", "ns")
    c.chip(640, 445, "dataplane-mode: ambient", BLUE, anchor="end", size=15)
    c.frame(130, 490, 240, 180, "frontend pod", "pod")
    fe = c.box(155, 545, 190, 90, SLATE, "app", "1 container")
    c.frame(400, 490, 240, 180, "waypoint pod", "pod")
    c.box(425, 545, 190, 90, BLUE, "Envoy", "L7 for backend")
    zt = c.band(100, 730, 560, 80, BLUE, "ztunnel", "", "tunnel", size=19)
    c.text(640, 776, "one per node", 17, SOFT, False, "end")
    c.connect(fe, zt, "", sa="bottom", sb="top", fb=(250 - 100) / 560)

    sc = c.frame(700, 430, 800, 380, "namespace course-sidecar", "ns")
    c.chip(1480, 445, "istio-injection: enabled", BLUE, anchor="end", size=15)
    c.frame(730, 490, 340, 290, "client pod", "pod")
    c.box(760, 545, 280, 80, SLATE, "curl")
    p1 = c.box(760, 665, 280, 86, BLUE, "istio-proxy", "Envoy")
    c.frame(1130, 490, 340, 290, "httpbin pod", "pod")
    c.box(1160, 545, 280, 80, SLATE, "httpbin")
    p2 = c.box(1160, 665, 280, 86, BLUE, "istio-proxy", "Envoy")
    c.connect(p1, p2, "mTLS", pos="above")

    c.connect(ist, amb, "xDS, certificates", sa="bottom", sb="top", fa=0.2, fb=(674 - 100) / 560, dashed=True,
              col=PURPLE, pos="left", at=(674, 380))
    c.connect(ist, sc, "xDS, certificates", sa="bottom", sb="top", fa=0.8, fb=(926 - 700) / 800, dashed=True,
              col=PURPLE, pos="right", at=(926, 380))
    c.save(OUT, "3.9-two-modes")


def injection():
    c = Canvas(1600, 980)
    c.title("How a pod gets its", "sidecar")
    c.subtitle("A mutating admission webhook in istiod edits each new pod before the API server stores it.")

    you = c.node(40, 200, 260, 110, SLATE, "You", "person", "Deployment,\n1 container")
    c.frame(370, 150, 1190, 220, "Control plane", "group")
    api = c.node(410, 210, 340, 120, PURPLE, "API server", "server", "stores the pod")
    inj = c.node(1180, 210, 340, 120, PURPLE, "istiod injector", "gear", "mutating webhook")
    c.connect(you, api, "create", n=1, sa="right", sb="left", fa=0.5, fb=(255 - 210) / 120, at=(335, 255), pos="above")
    c.connect(api, inj, "AdmissionReview", n=2, sa="right", sb="left", fa=0.3, fb=0.3, at=(965, 246))
    c.connect(inj, api, "patch: add 2 containers", n=3, sa="left", sb="right", fa=0.72, fb=0.72, at=(965, 296),
              pos="below", col=PURPLE)

    c.frame(370, 420, 1190, 530, "Node", "node")
    kub = c.node(410, 470, 340, 110, TEAL, "kubelet", "server", "runs the pod")
    c.connect(api, kub, "pod spec", sa="bottom", sb="top", dashed=True, pos="right")
    pod = c.frame(410, 650, 1110, 260, "pod: 3 containers", "pod")
    init = c.box(440, 730, 320, 140, GREEN, "istio-init", "NET_ADMIN, NET_RAW\nsets iptables, exits")
    app = c.box(810, 730, 300, 140, SLATE, "app")
    prx = c.box(1160, 730, 330, 140, BLUE, "istio-proxy", "Envoy")
    c.connect(kub, init, "first", n=4, sa="bottom", sb="top", fa=0.5, fb=0.5, pos="right", at=(580, 615))
    c.connect(kub, app, "", sa="right", sb="top", fa=0.35)
    c.connect(kub, prx, "then app and proxy", n=5, sa="right", sb="top", fa=0.75, at=(1150, 552), pos="below")
    c.save(OUT, "3.9-injection")


def two_proxies():
    c = Canvas(1600, 860)
    c.title("Two proxies on", "every request")
    c.subtitle("iptables rules inside each pod hand the app's connections to Envoy. The app never notices.")

    c.frame(40, 150, 720, 680, "client pod", "pod", right="its own netns")
    curl = c.box(80, 210, 220, 90, SLATE, "curl", "the app")
    p1 = c.frame(400, 200, 320, 380, "istio-proxy", "plain", col=BLUE, icon="shield", right=":15001")
    for i, t in enumerate(["Routing", "Retries", "Faults", "Starts mTLS"]):
        c.box(425, 255 + i * 76, 270, 58, BLUE, t, size=18)
    b1 = c.band(80, 650, 640, 120, GREEN, "iptables", "OUTPUT: to :15001", "filter", lx=150, ly=684)

    c.frame(840, 150, 720, 680, "httpbin pod", "pod", right="its own netns")
    p2 = c.frame(880, 200, 320, 380, "istio-proxy", "plain", col=BLUE, icon="shield", right=":15006")
    for i, t in enumerate(["Ends mTLS", "Checks policy", "Adds XFCC"]):
        c.box(905, 255 + i * 76, 270, 58, BLUE, t, size=18)
    app = c.box(1300, 210, 220, 90, SLATE, "httpbin", "the app")
    c.band(880, 650, 640, 120, GREEN, "iptables", "PREROUTING: to :15006", "filter", lx=1170, ly=684)

    c.line([(130, 300), (130, 740), (560, 740), (560, 580)], SLATE, AW, head=True)
    c.chip(450, 740, "redirect", GREEN, anchor="middle", mono=False)
    c.line([(720, 250), (800, 250), (800, 740), (1040, 740), (1040, 580)], GREEN, 3, head=True)
    c.chip(800, 470, "mTLS", GREEN, anchor="middle", solid=True, mono=False)
    c.chip(960, 740, "redirect", GREEN, anchor="middle", mono=False)
    c.connect(p2, app, "localhost", sa="right", sb="left", fa=(255 - 200) / 380, pos="above")
    c.note(80, 806, "Envoy runs as uid 1337, so its own traffic skips the rules.", 17)
    c.save(OUT, "3.9-two-proxies")


if __name__ == "__main__":
    two_modes()
    injection()
    two_proxies()
