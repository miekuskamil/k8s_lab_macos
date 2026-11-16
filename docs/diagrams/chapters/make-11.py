#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/11-edge-tls.md with the kit in ../bbg.py.

  11-two-tls           one request, two TLS sessions, two certificate authorities
  11-trust-chain       the lab root CA signs shop-tls, curl trusts the root
  11-cert-manager      Certificate and ClusterIssuer in, Secret out, Gateway reads it

Run from anywhere: python3 docs/diagrams/chapters/make-11.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def two_tls():
    c = Canvas(1600, 860)
    c.title("Two kinds of", "TLS")
    c.subtitle("One request passes two separate TLS sessions. Each uses a different certificate authority.")

    c.frame(40, 220, 260, 280, "Your Mac", "host")
    br = c.node(65, 300, 210, 110, SLATE, "curl", "laptop", "or a browser")

    c.frame(340, 150, 1220, 680, "Cluster", "cluster")
    c.frame(380, 190, 620, 380, "namespace shop-ingress", "ns")
    gw = c.frame(410, 240, 560, 300, "ingress gateway pod", "plain", col=BLUE, icon="shield")
    steps = [("terminate TLS", 440, 300), ("read HTTP", 710, 300), ("pick a route", 440, 420), ("open mTLS", 710, 420)]
    bx = []
    for i, (t, x, y) in enumerate(steps):
        bx.append(c.box(x, y, 230, 84, BLUE, t, size=18))
        c.step(x, y, i + 1)
    c.connect(bx[0], bx[1])
    c.connect(bx[1], bx[2], "", sa="bottom", sb="top", fa=0.5, fb=0.5, mid=402)
    c.connect(bx[2], bx[3])

    c.frame(1080, 190, 440, 380, "namespace shop", "ns")
    fe = c.frame(1110, 300, 380, 170, "frontend pod", "pod")
    c.box(1135, 350, 330, 90, SLATE, "app", "never sees the edge cert")

    # the two sessions
    c.line([(275, 342), (440, 342)], PINK, 4, head=True)
    c.chip(357, 384, ":8443", PINK, anchor="middle")
    c.text(357, 322, "edge TLS", 18, DEEP[PINK], True, "middle", halo=True)
    c.line([(940, 462), (1135, 462)], GREEN, 4, head=True)
    c.chip(1040, 425, "HBONE mTLS", GREEN, anchor="middle", mono=False)

    # who signs each certificate
    cm = c.node(410, 650, 560, 120, RED, "Lab CA", "lock", "via cert-manager, Secret shop-tls")
    ist = c.node(1110, 650, 380, 120, PURPLE, "istiod", "lock", "mesh CA, SPIFFE IDs")
    c.connect(cm, gw, "edge certificate", dashed=True, col=RED, pos="right", off=-150)
    c.connect(ist, fe, "mesh certificates", dashed=True, col=PURPLE, pos="right")
    c.save(OUT, "11-two-tls")


def trust_chain():
    c = Canvas(1500, 820)
    c.title("How curl decides to", "trust")
    c.subtitle("curl trusts the lab root CA, which signed the gateway's certificate. Then it runs three checks.")

    c.frame(40, 150, 620, 640, "Your Mac", "host")
    curl = c.node(80, 200, 270, 110, SLATE, "curl", "laptop", "--cacert")
    chk = c.frame(80, 350, 540, 240, "Three checks", "plain")
    for i, (t, sub) in enumerate([("signature", "a trusted CA signed it"), ("name", "shop.local in the SAN"),
                                  ("dates", "now is inside the window")]):
        y = 410 + i * 58
        c.step(118, y, i + 1)
        c.text(148, y + 7, t, 19, INK, True)
        c.text(268, y + 7, sub, 17, SOFT)
        c.mark(586, y, r=12)
    store = c.frame(80, 630, 540, 130, "trust store: /tmp/lab-ca.crt", "plain", col=RED, icon="lock")
    c.box(110, 684, 480, 56, RED, "Lab root CA", size=18)
    c.connect(curl, chk)

    c.frame(720, 150, 740, 640, "Cluster", "cluster")
    c.frame(760, 200, 660, 360, "ingress gateway pod", "pod")
    cert = c.frame(800, 260, 580, 260, "certificate shop-tls", "plain", col=PINK, icon="doc")
    for i, (k, v) in enumerate([("SAN", "shop.local"), ("issuer", "lab-ca"), ("valid", "90 days"),
                                ("key", "stays in the Secret")]):
        c.text(830, 340 + i * 44, k, 17, SOFT, True)
        c.text(930, 340 + i * 44, v, 18, INK, False, mono=(k != "key"))
    root = c.node(800, 630, 580, 120, RED, "Lab root CA", "lock", "self-signed, created by cert-manager")
    c.connect(root, cert, "signs", col=RED, pos="right")
    c.connect(cert, chk, "sends it in\nthe handshake", sa="left", sb="right", fa=(470 - 260) / 260, fb=0.5, pos="above",
              at=(690, 470))
    c.save(OUT, "11-trust-chain")


def cert_manager():
    c = Canvas(1600, 840)
    c.title("How cert-manager", "works")
    c.subtitle("You describe the certificate you want. A controller makes it and keeps it fresh.")

    c.frame(40, 150, 1520, 660, "Cluster", "cluster")
    c.frame(560, 190, 480, 200, "namespace cert-manager", "ns")
    ctl = c.node(590, 245, 420, 115, PURPLE, "cert-manager", "gear", "controller")
    c.frame(1120, 190, 400, 200, "cluster-scoped", "group")
    iss = c.node(1150, 245, 340, 115, RED, "ClusterIssuer", "lock", "lab-ca: who signs")

    c.frame(80, 450, 1440, 320, "namespace shop-ingress", "ns")
    crt = c.node(120, 540, 360, 130, SLATE, "Certificate", "doc", "shop-tls: names,\nlifetime")
    sec = c.node(620, 540, 360, 130, ORANGE, "Secret shop-tls", "key", "tls.crt + tls.key")
    gw = c.node(1120, 540, 360, 130, BLUE, "Gateway listener", "shield", "certificateRefs")

    c.connect(crt, ctl, "watches", n=1, sa="top", sb="left", pos="right", at=(300, 400))
    c.connect(iss, ctl, "who signs", sa="left", sb="right", pos="above", dashed=True, col=RED)
    c.connect(ctl, sec, "creates, renews", n=2, sa="bottom", sb="top", fa=(800 - 590) / 420, fb=(800 - 620) / 360,
              pos="right", at=(800, 405))
    c.connect(sec, gw, "reads", n=3, pos="above")
    c.save(OUT, "11-cert-manager")


if __name__ == "__main__":
    two_tls()
    trust_chain()
    cert_manager()
