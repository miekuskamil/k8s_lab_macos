#!/usr/bin/env python3
"""Draw the diagrams for course module 2 (identity and mTLS) in ByteByteGo style (see ../bbg.py).

  02-certificate-issue   ztunnel asks istiod for a certificate, istiod checks with the API server
  02-hbone-tunnel        plain HTTP inside each node, mTLS on :15008 between the ztunnels

Run from anywhere: python3 docs/diagrams/chapters/make-02.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def certificate():
    c = Canvas(1720, 900)
    c.title("How a pod gets", "its identity")
    c.subtitle("ztunnel asks istiod for a certificate on the pod's behalf. istiod checks the claim with the API server first.")

    c.group(40, 190, 440, 520, "Node")
    c.outline(80, 230, 360, 110, SLATE, "frontend pod\nSA frontend", "cube")
    c.node(80, 470, 360, 160, BLUE, "ztunnel", "tunnel", "on the node")
    c.arrow([(260, 340), (260, 470)], "Pod starts", n=1, at=(260, 405))

    c.node(760, 470, 340, 160, PURPLE, "istiod", "lock", "certificate authority")
    c.node(1340, 470, 340, 160, PURPLE, "Kubernetes API", "server", "TokenReview")
    c.arrow([(440, 510), (760, 510)], "CSR for\nsa/frontend", n=2, at=(620, 510), pos="above")
    c.arrow([(1100, 510), (1340, 510)], "Is the\ntoken real?", n=3, at=(1220, 510), pos="above")
    c.arrow([(1340, 590), (1100, 590)], "Yes", n=4, at=(1220, 590), pos="below", col=GREEN)
    c.arrow([(760, 590), (440, 590)], "Certificate,\nvalid 24 h", n=5, at=(620, 590), pos="below", col=GREEN)

    c.outline(40, 760, 1640, 90, GREEN, "spiffe://cluster.local/ns/shop/sa/frontend", "lock")
    c.save(OUT, "02-certificate-issue")


def hbone():
    c = Canvas(1720, 760)
    c.title("HBONE: one", "mTLS tunnel")
    c.subtitle("The apps speak plain HTTP. ztunnel encrypts it before it leaves the node and decrypts it on the other side.")

    c.group(40, 190, 480, 520, "Node A")
    c.node(80, 230, 400, 120, SLATE, "frontend pod", "cube", "plain HTTP to backend:8000")
    c.node(80, 540, 400, 120, BLUE, "ztunnel", "tunnel", "client cert: sa/frontend")
    c.arrow([(280, 350), (280, 540)], "Plaintext,\nnever leaves\nthe node", at=(290, 445), pos="right", col=SOFT)

    c.group(1200, 190, 480, 520, "Node B")
    c.node(1240, 230, 400, 120, SLATE, "backend pod", "cube", "plain HTTP on :8000")
    c.node(1240, 540, 400, 120, BLUE, "ztunnel", "tunnel", "server cert: sa/backend")
    c.arrow([(1440, 540), (1440, 350)], "Plaintext", at=(1450, 445), pos="right", col=SOFT)

    c.line([(480, 600), (1240, 600)], GREEN, 6, False, head=True)
    c.icon("lock", 838, 540, GREEN)
    c.text(860, 640, "mTLS on :15008", 20, INK, True, "middle")
    c.text(860, 668, "HTTP/2 CONNECT backend-ip:8000", 18, SOFT, True, "middle")
    c.save(OUT, "02-hbone-tunnel")


if __name__ == "__main__":
    certificate()
    hbone()
