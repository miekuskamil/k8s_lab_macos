#!/usr/bin/env python3
"""Draw the diagram for course/12-egress.md in ByteByteGo style (see ../bbg.py).

  12-egress-flow       a call to httpbin.org through ztunnel and the waypoint

The circled numbers match the numbered steps in the chapter.

Run from anywhere: python3 docs/diagrams/chapters/make-12.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def egress_flow():
    c = Canvas(2060, 880)
    c.title("A call to the internet,", "through the mesh")
    c.subtitle("A ServiceEntry gives httpbin.org a fixed virtual IP. ztunnel answers DNS, then hands the call to the waypoint.")

    top, h = 400, 220
    c.node(630, 170, 300, 100, PURPLE, "istiod", "gear", "ServiceEntry")
    c.arrow([(780, 270), (780, top)], "Virtual IP from\n240.240.0.0/16", n=1, at=(780, 335))

    c.node(50, top, 280, h, SLATE, "course-client", "cube", "the pod")
    c.node(630, top, 300, h, BLUE, "ztunnel", "tunnel", "DNS proxy")
    c.step(930, top, 2)

    c.arrow([(330, top + 40), (630, top + 40)], "Where is httpbin.org?", n=3, at=(480, top + 40), pos="above")
    c.arrow([(630, top + 110), (330, top + 110)], "240.240.0.1", at=(480, top + 110), pos="above", col=SOFT)
    c.arrow([(330, top + 180), (630, top + 180)], "Plain HTTP to\n240.240.0.1:80", n=4, at=(480, top + 180), pos="below")

    c.node(1170, top, 330, h, PURPLE, "Waypoint", "shield", "policy · metrics · traces")
    c.arrow([(930, top + 110), (1170, top + 110)], "HBONE mTLS as\nsa/course-client", n=5, at=(1050, top + 110), pos="above")
    c.note(1170, 330, ["Checks the AuthorizationPolicy,", "records metrics and traces"], 17)

    c.node(1730, top, 280, h, SLATE, "httpbin.org", "globe", "the internet")
    c.arrow([(1500, top + 110), (1730, top + 110)], "TLS to :443", n=6, at=(1615, top + 110), pos="above")
    c.text(1615, top + 160, "TLS origination", 17, SOFT, True, "middle")

    c.arrow([(1870, top + h + 6), (1870, 790), (190, 790), (190, top + h + 6)], "Response", n=7,
            at=(1030, 790), pos="above", col=SOFT)
    c.save(OUT, "12-egress-flow")


if __name__ == "__main__":
    egress_flow()
