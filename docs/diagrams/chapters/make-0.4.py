#!/usr/bin/env python3
"""Draw the diagram for course module 0.4 (storage) with the kit in ../bbg.py.

  0.4-mount-types   a volume, a bind mount and tmpfs, and where each one lives

The circled numbers match the numbered list in module 0.4.

Run from anywhere: python3 docs/diagrams/chapters/make-0.4.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def mounts():
    c = Canvas(1600, 900)
    c.title("Three places a folder", "can come from")
    c.subtitle("A mount replaces one folder of the container with storage outside the image's layers.")

    c.frame(40, 150, 1520, 710, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(80, 210, 1440, 220, "container course-site", "pod")
    data = c.box(110, 290, 320, 90, SLATE, "/data", "volume mount")
    html = c.box(480, 290, 380, 90, SLATE, "/usr/share/nginx/html", "bind mount", size=18)
    scr = c.box(910, 290, 280, 90, SLATE, "/scratch", "tmpfs mount")
    c.box(1240, 290, 250, 90, ORANGE, "everything else", "image + writable layer", size=18)
    c.step(1365, 260, 4)

    c.frame(80, 500, 820, 320, "Docker host's disk", "plain", col=ORANGE)
    vol = c.box(110, 580, 320, 90, ORANGE, "volumes folder", "/var/lib/docker/volumes", size=18)
    repo = c.box(480, 580, 380, 90, ORANGE, "repo folder", "same path as your machine", size=18)
    mac = c.box(480, 710, 380, 80, GREEN, "Mac file share", "virtiofs, Mac only", size=18)
    ram = c.box(910, 580, 280, 90, PURPLE, "memory", "gone at stop")

    c.connect(data, vol, "", n=1)
    c.connect(html, repo, "", n=2)
    c.connect(scr, ram, "", n=3)
    c.connect(repo, mac, "", col=GREEN, dashed=True)
    c.save(OUT, "0.4-mount-types")


mounts()
