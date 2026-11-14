#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/07-sidecar-mode.md in ByteByteGo style (see ../bbg.py).

  07-two-modes         ambient and sidecar namespaces side by side, one istiod
  07-injection         how a one-container Deployment ends up with three containers
  07-two-proxies       a request from client to httpbin passes two Envoys

Run from anywhere: python3 docs/diagrams/chapters/make-07.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def two_modes():
    c = Canvas(1700, 860)
    c.title("Two data planes,", "one istiod")
    c.subtitle("Each namespace picks ambient or sidecars with a label. The same istiod configures both.")

    c.node(650, 170, 400, 100, PURPLE, "istiod", "gear", "one control plane, one CA")

    c.group(40, 400, 360, 320, "")
    c.text(220, 750, "namespace shop: ambient", 19, SOFT, True, "middle")
    c.outline(70, 440, 300, 96, BLUE, "waypoint", "shield")
    c.outline(70, 590, 300, 96, SLATE, "frontend\n1 container", "cube")

    c.node(560, 440, 300, 96, BLUE, "ztunnel", "tunnel")

    c.group(1000, 400, 660, 320, "")
    c.text(1330, 750, "namespace course-sidecar: sidecars", 19, SOFT, True, "middle")
    c.group(1030, 450, 290, 250, "")
    c.text(1175, 690, "pod client", 17, SOFT, True, "middle")
    c.outline(1050, 470, 250, 86, BLUE, "istio-proxy", "shield")
    c.outline(1050, 585, 250, 86, SLATE, "curl", "cube")
    c.line([(1175, 556), (1175, 585)], LINE, 2.5)
    c.group(1350, 450, 290, 250, "")
    c.text(1495, 690, "pod httpbin", 17, SOFT, True, "middle")
    c.outline(1370, 470, 250, 86, BLUE, "istio-proxy", "shield")
    c.outline(1370, 585, 250, 86, SLATE, "httpbin", "cube")
    c.line([(1495, 556), (1495, 585)], LINE, 2.5)

    # config from istiod
    c.arrow([(670, 270), (300, 440)], "xDS", at=(470, 345), pos="left", col=SOFT)
    c.arrow([(740, 270), (710, 440)], "xDS config,\ncertificates", at=(725, 355), pos="right", col=SOFT)
    c.arrow([(980, 270), (1150, 470)], "xDS", at=(1035, 335), pos="left", col=SOFT)
    c.arrow([(1040, 250), (1480, 470)], "xDS", at=(1280, 360), pos="right", col=SOFT)

    # traffic
    c.arrow([(1300, 512), (1370, 512)], "", dashed=False)
    c.text(1335, 500, "mTLS", 17, INK, True, "middle")
    c.arrow([(1050, 512), (860, 512)], "mTLS\n(HBONE)", at=(940, 512), pos="below", dashed=False)

    c.note(40, 825, ["Ambient: no proxy in the app pod. Sidecar: an Envoy in every pod."], 17)
    c.save(OUT, "07-two-modes")


def injection():
    c = Canvas(1640, 920)
    c.title("How a pod gets its", "sidecar")
    c.subtitle("A mutating admission webhook in istiod edits each new pod before the API server stores it.")

    c.node(60, 190, 280, 110, SLATE, "You", "person", "Deployment, 1 container")
    c.node(560, 190, 360, 110, PURPLE, "Kubernetes API", "server", "API server")
    c.node(1180, 190, 400, 110, PURPLE, "istiod injector", "gear", "mutating webhook")

    c.arrow([(340, 245), (560, 245)], "Create\nDeployment", n=1, at=(450, 245), pos="below")
    c.arrow([(920, 220), (1180, 220)], "AdmissionReview,\neach new pod", n=2, at=(1050, 220), pos="above")
    c.arrow([(1180, 275), (920, 275)], "Patch: add istio-init\nand istio-proxy", n=3, at=(1050, 275), pos="below")

    c.node(560, 470, 360, 100, TEAL, "kubelet", "server", "runs the pod")
    c.arrow([(740, 300), (740, 470)], "Run pod,\n3 containers", at=(740, 395), pos="right", col=SOFT)

    c.group(60, 690, 1520, 160, "")
    c.text(820, 885, "Pod: 3 containers", 19, SOFT, True, "middle")
    c.outline(100, 725, 420, 96, GREEN, "istio-init\nNET_ADMIN, NET_RAW", "gear")
    c.outline(600, 725, 380, 96, SLATE, "app", "cube")
    c.outline(1060, 725, 480, 96, BLUE, "istio-proxy", "shield")

    c.arrow([(600, 570), (310, 725)], "Set iptables\nrules, exit", n=4, at=(455, 648), pos="above")
    c.arrow([(790, 570), (790, 725)], "", dashed=True)
    c.arrow([(880, 570), (1300, 725)], "Start app and\nistio-proxy", n=5, at=(1090, 648), pos="above")
    c.save(OUT, "07-injection")


def two_proxies():
    c = Canvas(1800, 760)
    c.title("Two proxies on", "every request")
    c.subtitle("iptables rules inside each pod hand the app's connections to Envoy. The app never notices.")

    c.group(40, 180, 800, 520, "pod client")
    c.node(80, 230, 260, 110, SLATE, "curl", "cube", "the app")
    c.node(500, 230, 300, 110, BLUE, "istio-proxy", "shield", "outbound :15001")
    c.arrow([(340, 285), (500, 285)], "iptables\nport 15001", at=(420, 285), pos="below")
    for i, t in enumerate(["Routing", "Retries", "Faults", "Starts mTLS"]):
        c.outline(500, 390 + i * 74, 300, 58, BLUE, t, size=18)

    c.group(960, 180, 800, 520, "pod httpbin")
    c.node(1000, 230, 300, 110, BLUE, "istio-proxy", "shield", "inbound :15006")
    c.node(1460, 230, 260, 110, SLATE, "httpbin", "cube", "the app")
    c.arrow([(1300, 285), (1460, 285)], "localhost", at=(1380, 285), pos="below")
    for i, t in enumerate(["Ends mTLS", "Checks policy", "Adds XFCC header"]):
        c.outline(1000, 390 + i * 74, 300, 58, BLUE, t, size=18)

    c.arrow([(800, 285), (1000, 285)], "mTLS", at=(900, 285), pos="above", dashed=False)
    c.save(OUT, "07-two-proxies")


if __name__ == "__main__":
    two_modes()
    injection()
    two_proxies()
