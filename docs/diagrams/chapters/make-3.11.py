#!/usr/bin/env python3
"""Draw the diagram for platform-engineering/3-istio/11-egress.md with the kit in ../bbg.py.

  12-egress-flow       a call to httpbin.org through ztunnel and the waypoint

The circled numbers match the numbered steps in the chapter.

Run from anywhere: python3 docs/diagrams/chapters/make-3.11.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def egress_flow():
    c = Canvas(1600, 900)
    c.title("A call to the internet,", "through the mesh")
    c.subtitle("A ServiceEntry gives httpbin.org a fixed virtual IP. ztunnel answers DNS, then hands the call to the waypoint.")

    c.frame(40, 150, 1150, 720, "Cluster", "cluster")
    c.frame(470, 180, 440, 140, "namespace istio-system", "ns")
    ist = c.node(500, 222, 380, 80, PURPLE, "istiod", "gear", "reads the ServiceEntry")

    c.frame(70, 370, 1090, 470, "Node", "node")
    c.frame(100, 420, 1030, 240, "namespace shop", "ns")
    cc = c.frame(130, 470, 470, 160, "course-client pod", "pod")
    c.box(155, 520, 420, 76, SLATE, "app", "curl http://httpbin.org")
    wp = c.frame(790, 470, 310, 160, "waypoint pod", "pod")
    c.box(815, 520, 260, 76, BLUE, "Envoy", "policy, metrics")
    zt = c.band(100, 720, 1030, 90, BLUE, "ztunnel", "DNS proxy and HBONE", "tunnel", lx=640)

    c.connect(ist, zt, "virtual IP\n240.240.0.1", n=1, sa="bottom", sb="top", fa=(690 - 500) / 380,
              fb=(690 - 100) / 1030, at=(690, 360), pos="right", col=PURPLE, dashed=True)
    c.step(140, 765, 2)
    c.text(166, 771, "answers DNS", 17, INK, True, halo=True)
    c.line([(230, 630), (230, 720)], SLATE, AW, head=True)
    c.text(215, 690, "httpbin.org?", 17, INK, True, "end", halo=True)
    c.step(230, 664, 3)
    c.line([(360, 720), (360, 630)], SLATE, AW, dashed=True, head=True)
    c.text(375, 682, "240.240.0.1", 16, SOFT, True, halo=True, mono=True)
    c.line([(540, 630), (540, 720)], SLATE, AW, head=True)
    c.step(540, 664, 4)
    c.text(564, 670, "HTTP :80", 17, INK, True, halo=True)
    c.line([(945, 720), (945, 630)], BLUE, AW, head=True)
    c.step(945, 675, 5)
    c.text(969, 681, "HBONE", 17, INK, True, halo=True)

    c.frame(1240, 420, 320, 240, "Internet", "plain", icon="globe")
    web = c.box(1270, 520, 260, 76, SLATE, "httpbin.org", ":443")
    c.connect(wp, web, "TLS :443", n=6, sa="right", sb="left", fa=(558 - 470) / 160, pos="above", at=(1185, 558))
    c.note(1240, 700, ["The waypoint opens TLS", "itself: TLS origination."], 17)
    c.save(OUT, "3.11-egress-flow")


if __name__ == "__main__":
    egress_flow()
