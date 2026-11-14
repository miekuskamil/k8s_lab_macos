#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/30-sidecar-in-depth.md in ByteByteGo style (see ../bbg.py).

  30-traffic-capture   the iptables chains istio-init writes, outbound to 15001 and inbound to 15006
  30-sidecar-scope     a Sidecar resource shrinks what one proxy hears from istiod

Run from anywhere: python3 docs/diagrams/chapters/make-30.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def traffic_capture():
    c = Canvas(1700, 1000)
    c.title("How iptables hands traffic", "to Envoy")
    c.subtitle("istio-init writes these NAT rules into the pod's own network namespace, then exits.")

    c.group(40, 170, 1620, 760, "")
    c.text(850, 965, "one pod, one network namespace", 19, SOFT, True, "middle")

    # outbound row
    c.text(80, 225, "Outbound: the app calls httpbin:8000", 20, SOFT, True)
    c.node(80, 250, 230, 100, SLATE, "app", "cube", "uid 100")
    c.outline(400, 255, 250, 90, GREEN, "OUTPUT\nISTIO_OUTPUT")
    c.outline(740, 255, 250, 90, GREEN, "ISTIO_REDIRECT")
    c.node(1080, 250, 260, 100, BLUE, "Envoy", "shield", "port 15001")
    c.node(1420, 250, 210, 100, TEAL, "network", "globe")
    c.arrow([(310, 300), (400, 300)], "", n=1, at=(355, 300))
    c.arrow([(650, 300), (740, 300)], "", n=2, at=(695, 300))
    c.arrow([(990, 300), (1080, 300)], "", n=3, at=(1035, 300))
    c.arrow([(1340, 300), (1420, 300)], "", n=4, at=(1380, 300))
    c.text(1380, 390, "uid 1337: RETURN", 18, INK, True, "middle")
    c.text(1380, 414, "no loop", 16, SOFT, False, "middle")

    # inbound row
    c.text(80, 545, "Inbound: a caller reaches the pod", 20, SOFT, True)
    c.node(80, 570, 230, 100, TEAL, "network", "globe")
    c.outline(400, 575, 250, 90, GREEN, "PREROUTING\nISTIO_INBOUND")
    c.outline(740, 575, 250, 90, GREEN, "ISTIO_IN_REDIRECT")
    c.node(1080, 570, 260, 100, BLUE, "Envoy", "shield", "port 15006")
    c.node(1420, 570, 210, 100, SLATE, "app", "cube", ":8080")
    c.arrow([(310, 620), (400, 620)], "", n=5, at=(355, 620))
    c.arrow([(650, 620), (740, 620)], "", n=6, at=(695, 620))
    c.arrow([(990, 620), (1080, 620)], "", n=7, at=(1035, 620))
    c.arrow([(1340, 620), (1420, 620)], "", n=8, at=(1380, 620))
    c.text(1380, 710, "from 127.0.0.6", 18, INK, True, "middle")

    c.outline(400, 770, 420, 110, RED, "Skipped: 15008, 15090,\n15021, 15020, localhost")
    c.line([(525, 770), (525, 665)], LINE, 2.5, dashed=True)
    c.save(OUT, "30-traffic-capture")


def sidecar_scope():
    c = Canvas(1700, 860)
    c.title("A Sidecar resource", "trims the config")
    c.subtitle("Measured on the client proxy in course-proxy, in the test run.")

    c.node(650, 160, 400, 100, PURPLE, "istiod", "gear", "knows every Service")

    c.group(60, 380, 680, 400, "")
    c.text(400, 820, "no Sidecar resource", 19, SOFT, True, "middle")
    c.node(120, 420, 300, 100, BLUE, "client proxy", "shield")
    for i, (t, v) in enumerate([("clusters", "62"), ("listeners", "75"), ("Envoy heap", "11.8 MB")]):
        c.outline(120, 560 + i * 70, 300, 56, BLUE, t, size=18)
        c.text(470, 596 + i * 70, v, 26, INK, True)

    c.group(960, 380, 680, 400, "")
    c.text(1300, 820, "Sidecar: ./* and istio-system/*", 19, SOFT, True, "middle")
    c.node(1020, 420, 300, 100, BLUE, "client proxy", "shield")
    for i, (t, v) in enumerate([("clusters", "16"), ("listeners", "26"), ("Envoy heap", "7.1 MB")]):
        c.outline(1020, 560 + i * 70, 300, 56, BLUE, t, size=18)
        c.text(1370, 596 + i * 70, v, 26, INK, True)

    c.arrow([(700, 260), (300, 420)], "every Service\nin the cluster", at=(470, 330), pos="left", col=SOFT)
    c.arrow([(1000, 260), (1170, 420)], "own namespace,\nistio-system", at=(1100, 330), pos="right", col=SOFT)
    c.save(OUT, "30-sidecar-scope")


if __name__ == "__main__":
    traffic_capture()
    sidecar_scope()
