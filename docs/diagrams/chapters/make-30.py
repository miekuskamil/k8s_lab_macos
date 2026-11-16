#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/30-sidecar-in-depth.md with the kit in ../bbg.py.

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
    c = Canvas(1600, 860)
    c.title("How iptables hands traffic", "to Envoy")
    c.subtitle("istio-init writes these NAT rules into the pod's own network namespace, then exits.")

    c.frame(40, 150, 1520, 680, "pod: one network namespace", "pod")
    app = c.box(80, 220, 240, 110, SLATE, "app", "uid 100, :8080")
    env = c.box(560, 210, 560, 130, BLUE, "Envoy", "uid 1337")
    c.chip(658, 380, ":15001 out", BLUE, anchor="end", size=15)
    c.chip(942, 380, ":15006 in", BLUE, anchor="start", size=15)
    eth = c.box(1300, 220, 220, 110, TEAL, "eth0", "the network")

    c.frame(70, 450, 1460, 340, "", "plain", col=GREEN, right="kernel: iptables nat table")
    y, h, w = 540, 90, 210
    out_ = c.box(90, y, w, h, GREEN, "OUTPUT", size=17)
    iout = c.box(330, y, w, h, GREEN, "ISTIO_OUTPUT", size=17)
    ired = c.box(570, y, w, h, GREEN, "ISTIO_REDIRECT", size=17)
    iinr = c.box(820, y, w, h, GREEN, "ISTIO_IN_REDIRECT", size=17)
    iin = c.box(1060, y, w, h, GREEN, "ISTIO_INBOUND", size=17)
    pre = c.box(1300, y, w, h, GREEN, "PREROUTING", size=17)

    c.connect(app, out_, "", sa="bottom", sb="top", fa=0.5, fb=(200 - 90) / 210)
    c.connect(out_, iout, "", n=1, at=(315, 585))
    c.connect(iout, ired, "", n=2, at=(555, 585))
    c.text(435, 670, "uid is not 1337", 16, SOFT, True, "middle")
    c.connect(ired, env, "", n=3, sa="top", sb="bottom", fa=0.5, fb=(675 - 560) / 560, at=(675, 410))
    c.connect(env, eth, "own connection,", n=4, sa="right", sb="left", fa=0.3, fb=(249 - 220) / 110, pos="above",
              at=(1210, 249))
    c.text(1210, 300, "uid 1337: RETURN", 16, SOFT, True, "middle", halo=True)
    c.connect(eth, pre, "", sa="bottom", sb="top", fa=(1405 - 1300) / 220, fb=0.5)
    c.connect(pre, iin, "", n=5, at=(1285, 585))
    c.connect(iin, iinr, "", n=6, at=(1045, 585))
    c.text(1165, 670, "skips 15008, 15090,", 16, SOFT, True, "middle")
    c.text(1165, 692, "15021, 15020", 16, SOFT, True, "middle")
    c.connect(iinr, env, "", n=7, sa="top", sb="bottom", fa=0.5, fb=(925 - 560) / 560, at=(925, 410))
    c.connect(env, app, "from 127.0.0.6", n=8, sa="left", sb="right", fa=0.5, fb=0.5, pos="above", at=(440, 275))
    c.note(90, 760, "Outbound: steps 1 to 4. Inbound: steps 5 to 8.", 17)
    c.save(OUT, "30-traffic-capture")


def sidecar_scope():
    c = Canvas(1600, 900)
    c.title("A Sidecar resource", "trims the config")
    c.subtitle("Measured on the client proxy in course-proxy, in the test run.")

    c.frame(600, 150, 400, 130, "namespace istio-system", "ns")
    ist = c.node(625, 190, 350, 70, PURPLE, "istiod", "gear", "knows every Service")
    nss = ["course-proxy", "istio-system", "shop", "observability", "argocd", "kagent"]

    def panel(x, title, keep, stats):
        c.frame(x, 330, 720, 540, title, "plain")
        p = c.box(x + 30, 390, 300, 80, BLUE, "client proxy", "course-proxy")
        c.text(x + 370, 420, "config it holds for:", 17, SOFT, True)
        for i, ns in enumerate(nss):
            on = ns in keep
            bx = x + 370 + (i % 2) * 165
            by = 440 + (i // 2) * 62
            if on:
                c.box(bx, by, 150, 50, BLUE, ns, size=15)
            else:
                c.rect(bx, by, 150, 50, DIM, "none", 10, 1.4, True)
                c.text(bx + 75, by + 31, ns, 15, DIM, True, "middle")
        for i, (k, v) in enumerate(stats):
            c.text(x + 30, 680 + i * 56, k, 19, SOFT, True)
            c.text(x + 330, 680 + i * 56, v, 26, INK, True, "end")
        return p

    p1 = panel(40, "no Sidecar resource", nss, [("clusters", "62"), ("listeners", "75"), ("Envoy heap", "11.8 MB")])
    p2 = panel(840, "Sidecar: ./* and istio-system/*", ["course-proxy", "istio-system"],
               [("clusters", "16"), ("listeners", "26"), ("Envoy heap", "7.1 MB")])
    c.connect(ist, p1, "every Service", sa="left", sb="top", fa=0.5, fb=0.85, pos="above", at=(400, 225), dashed=True,
              col=PURPLE)
    c.connect(ist, p2, "only the listed hosts", sa="right", sb="top", fa=0.5, fb=0.95, pos="above", at=(1200, 225),
              dashed=True, col=PURPLE)
    c.save(OUT, "30-sidecar-scope")


if __name__ == "__main__":
    traffic_capture()
    sidecar_scope()
