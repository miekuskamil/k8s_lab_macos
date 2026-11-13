#!/usr/bin/env python3
"""Draw the diagrams for course/11-edge-tls.md in ByteByteGo style (see ../bbg.py).

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
    c = Canvas(1700, 560)
    c.title("Two kinds of", "TLS")
    c.subtitle("One request passes two separate TLS sessions. Each uses a different certificate authority.")

    c.node(60, 200, 330, 110, SLATE, "Browser\nor curl", "laptop")
    c.node(680, 200, 360, 110, BLUE, "Ingress gateway", "shield", "Envoy in shop-ingress")
    c.node(1320, 200, 320, 110, SLATE, "frontend pod", "cube")

    c.arrow([(390, 255), (680, 255)], "HTTPS on :8443", at=(535, 255), pos="above", dashed=False)
    c.arrow([(1040, 255), (1320, 255)], "HBONE mTLS", at=(1180, 255), pos="above", dashed=False)

    c.outline(395, 400, 280, 100, RED, "Lab CA\nvia cert-manager", "lock")
    c.outline(1040, 400, 280, 100, PURPLE, "Certificates\nfrom istiod", "lock")
    c.line([(535, 400), (535, 265)], DIM, 2, True)
    c.line([(1180, 400), (1180, 265)], DIM, 2, True)
    c.save(OUT, "11-two-tls")


def trust_chain():
    c = Canvas(1300, 720)
    c.title("How curl decides to", "trust")
    c.subtitle("curl trusts the lab root CA, which signed the gateway's certificate.")

    c.node(60, 370, 300, 110, SLATE, "curl", "laptop", "--cacert")
    c.node(740, 180, 500, 110, RED, "Lab root CA", "lock", "self-signed · /tmp/lab-ca.crt")
    c.node(740, 540, 500, 110, PINK, "shop-tls", "doc", "shop.local · 90 days")

    c.arrow([(990, 290), (990, 540)], "Signs", at=(990, 415), pos="right", dashed=False)
    c.arrow([(360, 400), (740, 240)], "Trusts", at=(550, 320), pos="above")
    c.arrow([(360, 450), (740, 590)], "Checks", at=(550, 520), pos="below")
    c.save(OUT, "11-trust-chain")


def cert_manager():
    c = Canvas(1560, 760)
    c.title("How cert-manager", "works")
    c.subtitle("You describe the certificate you want. A controller makes it and keeps it fresh.")

    c.node(60, 190, 420, 110, SLATE, "Certificate", "doc", "shop-tls · names, lifetime")
    c.node(60, 420, 420, 110, RED, "ClusterIssuer", "lock", "lab-ca · who signs")
    c.node(600, 305, 340, 110, PURPLE, "cert-manager", "gear", "controller")
    c.node(1140, 305, 360, 110, ORANGE, "Secret shop-tls", "db", "tls.crt + tls.key")
    c.node(1140, 590, 360, 110, BLUE, "Gateway listener", "shield", "certificateRefs: shop-tls")

    c.arrow([(480, 245), (540, 245), (540, 340), (600, 340)], "")
    c.arrow([(480, 475), (540, 475), (540, 380), (600, 380)], "")
    c.arrow([(940, 360), (1140, 360)], "Creates, renews\nbefore expiry", at=(1040, 360), pos="above")
    c.arrow([(1320, 590), (1320, 415)], "Reads", at=(1320, 505), pos="right")
    c.save(OUT, "11-cert-manager")


if __name__ == "__main__":
    two_tls()
    trust_chain()
    cert_manager()
