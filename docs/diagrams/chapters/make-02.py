#!/usr/bin/env python3
"""Draw the diagrams for course module 2 (identity and mTLS) with the kit in ../bbg.py.

  02-certificate-issue   ztunnel asks istiod for a certificate, istiod checks with the API server
  02-hbone-tunnel        plain HTTP inside each node, one mTLS tunnel on :15008 between the ztunnels

Run from anywhere: python3 docs/diagrams/chapters/make-02.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def certificate():
    c = Canvas(1600, 800)
    c.title("How a pod gets", "its identity")
    c.subtitle("ztunnel asks istiod for a certificate on the pod's behalf. istiod checks the claim with the API server first.")

    c.frame(40, 140, 1520, 620, "Cluster", "cluster")
    c.frame(70, 190, 680, 540, "Node", "node")
    pod = c.frame(100, 240, 330, 170, "frontend pod", "pod")
    c.box(124, 296, 282, 52, SLATE, "app container")
    c.chip(265, 378, "sa: frontend", SLATE, anchor="middle")
    c.note(470, 290, ["ztunnel serves every pod", "on its node and keeps", "one certificate for each", "service account."], 18)

    zt = c.frame(100, 500, 620, 200, "ztunnel", "plain", col=BLUE, icon="tunnel", right="one per node")
    c.rect(130, 556, 560, 116, GREEN, WHITE, 12, SW)
    c.icon("lock", 148, 600, GREEN, s=0.62)
    c.text(186, 594, "Certificate for the pod", 18, DEEP[GREEN], True)
    c.text(186, 624, "spiffe://cluster.local/ns/shop/sa/frontend", 16, DEEP[GREEN], True, mono=True)
    c.text(186, 652, "valid 24 h, then renewed", 17, SOFT)

    c.frame(830, 190, 700, 540, "Control plane", "group")
    ist = c.node(880, 540, 270, 130, PURPLE, "istiod", "lock", "certificate\nauthority")
    api = c.node(1240, 540, 270, 130, PURPLE, "API server", "server", "TokenReview")
    c.note(880, 290, ["istiod also checks that the pod", "runs on the asking ztunnel's", "node, so one node never gets", "another node's identities."], 18)

    c.connect(pod, zt, "pod starts", n=1, sa="bottom", sb="top", fa=0.5, fb=165 / 620, pos="right")
    c.connect(zt, ist, "CSR + SA token", n=2, sa="right", sb="left", fa=(579 - 500) / 200, fb=0.3, at=(800, 579))
    c.connect(ist, api, "token real?", n=3, sa="right", sb="left", fa=0.3, fb=0.3, at=(1195, 579))
    c.connect(api, ist, "yes", n=4, sa="left", sb="right", fa=0.7, fb=0.7, at=(1195, 631), pos="below", col=GREEN)
    c.connect(ist, zt, "certificate", n=5, sa="left", sb="right", fa=0.7, fb=(631 - 500) / 200, at=(800, 631), pos="below", col=GREEN)
    c.save(OUT, "02-certificate-issue")


def hbone():
    c = Canvas(1600, 780)
    c.title("HBONE: one", "mTLS tunnel")
    c.subtitle("The apps speak plain HTTP. ztunnel encrypts it before it leaves the node and decrypts it on the other side.")

    c.frame(40, 140, 470, 600, "Node A", "node")
    c.frame(1090, 140, 470, 600, "Node B", "node")

    fp = c.frame(80, 200, 390, 130, "frontend pod", "pod")
    c.box(104, 250, 342, 52, SLATE, "app", "calls backend:8000")
    za = c.node(80, 520, 390, 140, BLUE, "ztunnel", "tunnel", "client cert\nsa/frontend")

    bp = c.frame(1130, 200, 390, 130, "backend pod", "pod")
    c.box(1154, 250, 342, 52, SLATE, "app", "listens on :8000")
    zb = c.node(1130, 520, 390, 140, BLUE, "ztunnel", "tunnel", "server cert\nsa/backend")

    c.connect(fp, za, "plain HTTP,\nstays on node", sa="bottom", sb="top", col=SLATE, at=(275, 440))
    c.connect(zb, bp, "plain HTTP\nto :8000", sa="top", sb="bottom", col=SLATE, at=(1325, 440))

    # the tunnel: one mTLS connection that carries many HTTP/2 streams
    c.rect(470, 532, 660, 116, GREEN, PASTEL[GREEN], 58, 2.4)
    c.icon("lock", 778, 452, GREEN, s=0.9)
    c.text(800, 440, "one mTLS connection", 19, DEEP[GREEN], True, "middle")
    for i, y in enumerate((562, 590, 618)):
        c.line([(530, y), (1110, y)], GREEN, 2, dashed=(i == 2), head=True)
    c.chip(1130, 690, "port 15008", GREEN, anchor="middle")
    c.rect(1124, 584, 12, 12, GREEN, WHITE, 3, 1.8)
    c.step(560, 500, 1)
    c.text(584, 506, "open mTLS to :15008", 18, INK, True, halo=True)
    c.step(560, 700, 2)
    c.text(584, 706, "one HTTP/2 stream per connection", 18, INK, True, halo=True)
    c.step(1040, 500, 3)
    c.text(1016, 506, "same identities reuse it", 18, INK, True, "end", halo=True)
    c.save(OUT, "02-hbone-tunnel")


if __name__ == "__main__":
    certificate()
    hbone()
