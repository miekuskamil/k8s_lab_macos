#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/3-istio/18-debugging-envoy.md with the kit in ../bbg.py.

  3.18-envoy-chain   listener, route, cluster, endpoint, and the Istio resource behind each
  3.18-flag-where    which proxy writes which response flag

Run from anywhere: python3 docs/diagrams/chapters/make-3.18.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def envoy_chain():
    c = Canvas(1600, 900)
    c.title("Four lookups inside", "every Envoy")
    c.subtitle("The client sidecar's path for GET httpbin:8000/headers, and where istiod gets each piece from.")

    c.frame(40, 150, 1110, 420, "client pod", "pod")
    curl = c.box(70, 310, 180, 100, SLATE, "curl", "httpbin:8000")
    env = c.frame(290, 200, 840, 340, "istio-proxy: Envoy", "plain", col=BLUE, icon="shield")
    looks = [("listener", "which port?", "0.0.0.0_8000"), ("route", "which host, path?", "8000"),
             ("cluster", "which pool?", "outbound|8000||"), ("endpoint", "which pod?", "10.42.0.3:8080")]
    boxes = []
    for i, (name, q, ex) in enumerate(looks):
        x = 320 + i * 200
        b = c.box(x, 270, 180, 130, BLUE, name, q, size=21)
        c.step(x, 270, i + 1)
        c.text(x + 90, 440, ex, 14, DEEP[BLUE], True, "middle", mono=True)
        boxes.append(b)
        if i:
            c.connect(boxes[i - 1], b)
    c.text(710, 500, "istioctl proxy-config listener | route | cluster | endpoint", 15, SOFT, False, "middle", mono=True)
    c.connect(curl, boxes[0], "", sa="right", sb="left", fa=(340 - 310) / 100, fb=(340 - 270) / 130)

    c.frame(1210, 270, 350, 170, "httpbin pod", "pod")
    hb = c.box(1240, 320, 290, 90, SLATE, "app", "10.42.0.3:8080")
    c.connect(boxes[3], hb, "", sa="right", sb="left", fa=(355 - 270) / 130, fb=(355 - 320) / 90)

    c.frame(290, 620, 840, 240, "istiod builds each one from", "plain", col=PURPLE, icon="gear")
    srcs = [("Service", "one per port", SLATE), ("VirtualService", "or HTTPRoute", PURPLE),
            ("DestinationRule", "subsets, pools", PURPLE), ("EndpointSlice", "ready pod IPs", SLATE)]
    for i, (t, sub, col) in enumerate(srcs):
        x = 320 + i * 200
        s = c.box(x, 690, 180, 120, col, t, sub, size=17)
        c.connect(s, Box(x, 540, 180, 1), "", sa="top", sb="bottom", dashed=True, col=PURPLE)
    c.text(1150, 590, "xDS", 16, DEEP[PURPLE], True)
    c.save(OUT, "3.18-envoy-chain")


def flag_where():
    c = Canvas(1600, 800)
    c.title("Which proxy writes", "the flag")
    c.subtitle("Read the log of the proxy that hit the problem. The other side often shows a plain 503.")

    c.frame(40, 150, 700, 610, "client pod", "pod")
    curl = c.box(70, 210, 180, 100, SLATE, "curl")
    cs = c.box(330, 200, 380, 120, BLUE, "client sidecar", "outbound")
    c.connect(curl, cs, "")
    c.text(330, 375, "flags it writes", 17, SOFT, True)
    for i, (f, t) in enumerate([("NR", "no route matched"), ("UH", "no healthy endpoint"),
                                ("UO", "pool overflow"), ("URX", "retries ran out"), ("UT", "route timeout")]):
        y = 395 + i * 68
        c.rect(330, y, 380, 54, RED, PASTEL[RED], 10, SW)
        c.text(352, y + 34, f, 18, DEEP[RED], True, mono=True)
        c.text(430, y + 34, t, 17, INK)

    c.frame(860, 150, 700, 610, "httpbin pod", "pod")
    ss = c.box(890, 200, 380, 120, BLUE, "server sidecar", "inbound :15006")
    app = c.box(1350, 210, 180, 100, SLATE, "httpbin", ":8080")
    c.connect(ss, app, "")
    c.text(890, 375, "flags it writes", 17, SOFT, True)
    for i, (f, t) in enumerate([("UF", "app port refused"), ("403", "RBAC denied")]):
        y = 395 + i * 68
        c.rect(890, y, 380, 54, RED, PASTEL[RED], 10, SW)
        c.text(912, y + 34, f, 18, DEEP[RED], True, mono=True)
        c.text(990, y + 34, t, 17, INK)
    c.connect(cs, ss, "mTLS", pos="above")
    c.save(OUT, "3.18-flag-where")


if __name__ == "__main__":
    envoy_chain()
    flag_where()
