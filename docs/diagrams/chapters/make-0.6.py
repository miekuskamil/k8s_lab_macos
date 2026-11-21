#!/usr/bin/env python3
"""Draw the diagrams for course module 0.6 (security) with the kit in ../bbg.py.

  0.6-security-layers   the checks between a container's system call and the kernel
  0.6-supply-chain      scan, sign, store the signature, verify before running

The circled numbers match the numbered lists in module 0.6.

Run from anywhere: python3 docs/diagrams/chapters/make-0.6.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def layers():
    c = Canvas(1600, 1000)
    c.title("The checks between", "a container and the kernel")
    c.subtitle("Each layer stops a different attack. --cap-drop ALL makes chown fail at the capability check.")

    c.frame(40, 150, 1520, 810, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(80, 210, 560, 180, "container", "pod")
    app = c.box(120, 260, 480, 90, SLATE, "app as root", "chown nobody /tmp")

    k = c.frame(700, 210, 820, 710, "kernel", "plain", col=GREEN)
    sc = c.box(740, 270, 740, 80, RED, "seccomp filter", "default profile allows chown", size=19)
    cap = c.box(740, 390, 740, 80, RED, "capabilities", "CAP_CHOWN missing", size=19)
    lsm = c.box(740, 510, 740, 80, RED, "AppArmor or SELinux", "Linux hosts only", size=19)
    nnp = c.box(740, 630, 740, 80, RED, "no-new-privileges", "setuid bits ignored", size=19)
    cg = c.box(740, 750, 740, 80, PURPLE, "cgroup limits", "memory, CPU, processes", size=19)
    err = c.box(120, 510, 480, 80, RED, "Operation not permitted", "", size=19)

    c.connect(app, sc, "", n=1, sa="right", sb="left", fa=0.5, fb=0.5, mid=670, at=(670, 307))
    c.connect(sc, cap, "", n=2)
    c.connect(cap, err, "", n=3, sa="left", sb="top", fa=0.5, fb=0.5)
    c.mark(1440, 430, ok=False)
    c.connect(cap, lsm, "", dashed=True, col=DIM)
    c.connect(lsm, nnp, "", dashed=True, col=DIM)
    c.connect(nnp, cg, "", dashed=True, col=DIM)
    c.step(720, 790, 4)
    c.save(OUT, "0.6-security-layers")


def supply():
    c = Canvas(1600, 820)
    c.title("Scan, sign,", "verify before running")
    c.subtitle("The scanner reads what is inside; the signature proves who built these exact bytes.")

    c.frame(40, 150, 1520, 640, "toolbox and Docker host", "host", icon="box")
    img = c.box(80, 260, 280, 90, SLATE, "image hits:1.0.1", "digest sha256:34e2...", size=18)
    tv = c.box(460, 230, 300, 150, PINK, "trivy", "packages, Go libraries", size=20)
    db = c.box(460, 470, 300, 90, ORANGE, "vulnerability DB", "about 1.7 GB", size=18)
    rep = c.box(860, 260, 300, 90, RED, "report", "severity per CVE", size=19)
    key = c.box(80, 640, 280, 90, PINK, "cosign.key", "private key", size=19)
    reg = c.frame(860, 430, 640, 320, "registry localhost:5555", "plain", col=ORANGE)
    man = c.box(900, 490, 260, 80, ORANGE, "image manifest", "by digest", size=18)
    sig = c.box(1200, 490, 260, 80, PINK, "signature", "attached to digest", size=18)
    ver = c.box(1200, 620, 260, 80, GREEN, "cosign verify", "with cosign.pub", size=18)

    c.connect(img, tv, "", n=1)
    c.connect(db, tv, "")
    c.connect(tv, rep, "", n=2)
    c.arrow([(360, 685), (1030, 685), (1030, 570)], n=3, at=(600, 685))
    c.connect(man, sig)
    c.connect(sig, ver, "", n=4)
    c.save(OUT, "0.6-supply-chain")


layers()
supply()
