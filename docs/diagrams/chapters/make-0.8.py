#!/usr/bin/env python3
"""Draw the diagrams for course module 0.8 (the capstone) with the kit in ../bbg.py.

  0.8-capstone   proxy and api on front, api and redis on the internal back network
  0.8-pipeline   build, scan, push, sign, pin the digest, verify, compose up

The circled numbers match the numbered lists in module 0.8.

Run from anywhere: python3 docs/diagrams/chapters/make-0.8.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def capstone():
    c = Canvas(1600, 960)
    c.title("Two networks,", "one way in")
    c.subtitle("Only the proxy publishes a port. Redis sits on an internal network with no route out.")

    c.frame(40, 150, 1520, 770, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    cl = c.box(80, 230, 240, 80, SLATE, "client", "port 8889")
    front = c.frame(380, 210, 700, 300, "network front", "plain", col=GREEN)
    back = c.frame(760, 560, 760, 320, "network back, internal", "plain", col=RED)
    px = c.box(420, 290, 280, 90, BLUE, "proxy", "user 101, :8080")
    api = c.box(800, 290, 240, 90, SLATE, "api", "user 65532, :8000")
    rd = c.box(1200, 640, 280, 90, SLATE, "redis", "user 999, :6379")
    vol = c.box(1200, 780, 280, 70, ORANGE, "volume data", "")
    api2 = c.box(800, 640, 240, 90, SLATE, "api's eth1", "on back", size=18)
    out = c.box(1240, 290, 240, 90, SLATE, "internet", "no route from back", size=18)

    c.connect(cl, px, "", n=1, sa="right", sb="left", fa=0.5, fb=0.5, mid=350)
    c.connect(px, api, "", n=2)
    c.connect(api, api2, "", dashed=True, col=DIM)
    c.connect(api2, rd, "", n=3)
    c.connect(rd, vol, "", n=4)
    c.connect(rd, out, "", sa="top", sb="bottom", col=RED, dashed=True)
    c.mark(1360, 480, ok=False)
    c.chip(420, 440, "read-only, no capabilities", RED)
    c.save(OUT, "0.8-capstone")


def pipeline():
    c = Canvas(1600, 640)
    c.title("From build to run:", "pin what you checked")
    c.subtitle("The deploy names each image by the digest that passed the scan and carries a signature.")

    c.frame(40, 150, 1520, 450, "toolbox and Docker host", "host", icon="box")
    b = c.box(80, 250, 230, 90, SLATE, "docker build", "api and proxy", size=18)
    s = c.box(380, 250, 230, 90, PINK, "trivy gate", "CRITICAL: exit 1", size=18)
    p = c.box(680, 250, 230, 90, ORANGE, "push + sign", "registry, cosign", size=18)
    e = c.box(980, 250, 230, 90, SLATE, ".env", "image@sha256:...", size=18)
    v = c.box(1280, 250, 240, 90, GREEN, "verify", "cosign.pub", size=18)
    up = c.box(1340, 440, 180, 90, BLUE, "compose up", "--wait", size=18)
    st = c.box(1040, 440, 200, 90, RED, "stop", "not signed", size=18)

    c.connect(b, s, "", n=1)
    c.connect(s, p, "", n=2)
    c.connect(p, e, "", n=3)
    c.connect(e, v, "")
    c.connect(v, up, "", n=4, sa="bottom", sb="top", fa=(1430 - 1280) / 240, fb=0.5)
    c.connect(v, st, "", sa="bottom", sb="right", fa=0.1, fb=0.5, col=RED, dashed=True)
    c.save(OUT, "0.8-pipeline")


capstone()
pipeline()
