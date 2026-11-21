#!/usr/bin/env python3
"""Draw the diagrams for course module 0.1 (containers and images) with the kit in ../bbg.py.

  0.1-container-anatomy   one docker run: CLI, socket, dockerd, containerd, runc, kernel
  0.1-image-layers        read-only image layers and one writable layer per container

The circled numbers match the numbered lists in module 0.1.

Run from anywhere: python3 docs/diagrams/chapters/make-0.1.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def anatomy():
    c = Canvas(1600, 900)
    c.title("A container is", "a fenced-in process")
    c.subtitle("dockerd, containerd and runc set the fence up; the kernel enforces it.")

    c.frame(40, 150, 1520, 710, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(80, 210, 300, 240, "toolbox container", "pod")
    cli = c.box(105, 290, 250, 80, SLATE, "docker CLI", "docker run nginx")
    dockerd = c.box(470, 290, 240, 80, PURPLE, "dockerd", "Docker API")
    ctrd = c.box(470, 430, 240, 80, PURPLE, "containerd", "lifecycles")
    runc = c.box(470, 570, 240, 80, PURPLE, "runc", "starts, then exits")

    c.frame(820, 210, 700, 450, "container course-web", "pod")
    nginx = c.box(860, 270, 320, 80, SLATE, "nginx", "PID 1 inside")
    c.box(860, 400, 320, 80, ORANGE, "image files", "root filesystem")
    c.chip(1220, 300, "own hostname", TEAL)
    c.chip(1220, 350, "own eth0", GREEN)
    c.chip(1220, 400, "own process list", SLATE)
    c.chip(1220, 450, "own mounts", ORANGE)
    c.chip(860, 590, "cgroup: 64 MiB, half a CPU", RED)

    k = c.band(80, 710, 1440, 110, GREEN, "Linux kernel", "one kernel for every container", icon="chip")
    c.chip(1000, 765, "namespaces", GREEN)
    c.chip(1160, 765, "cgroups", GREEN)
    c.chip(1300, 765, "overlayfs", GREEN)

    c.connect(cli, dockerd, "socket", n=1, at=(412, 330), pos="below")
    c.connect(dockerd, ctrd, "", n=2)
    c.connect(ctrd, runc, "", n=3)
    c.connect(runc, k, "", sa="bottom", sb="top", fa=0.5, fb=(590 - 80) / 1440)
    c.connect(runc, nginx, "", n=4, sa="right", sb="left", fa=0.5, fb=0.5, mid=770, at=(770, 450))
    c.save(OUT, "0.1-container-anatomy")


def layers():
    c = Canvas(1600, 860)
    c.title("An image is a stack", "of read-only layers")
    c.subtitle("Every container shares the image's layers and writes only to its own thin top layer.")

    c.frame(40, 150, 1520, 670, "Docker host", "host", icon="box")
    c.frame(80, 210, 880, 570, "image nginx:1.28.0-alpine", "plain", col=ORANGE)
    base = c.box(120, 660, 800, 80, ORANGE, "Alpine base layer", "about 10 MB")
    inst = c.box(120, 550, 800, 80, ORANGE, "install nginx", "about 40 MB")
    scr = c.box(120, 440, 800, 80, ORANGE, "start scripts", "a few KB")
    cfg = c.box(120, 270, 800, 120, SLATE, "settings", "command, port 80, env")
    c.step(100, 700, 1)
    c.step(100, 590, 2)
    c.step(100, 330, 3)

    w1 = c.box(1040, 270, 230, 90, BLUE, "writable layer", "course-web")
    w2 = c.box(1300, 270, 230, 90, BLUE, "writable layer", "second container")
    ct1 = c.box(1040, 420, 230, 80, SLATE, "course-web", "nginx")
    ct2 = c.box(1300, 420, 230, 80, SLATE, "container 2", "nginx")
    c.connect(w1, ct1)
    c.connect(w2, ct2)
    c.connect(ct1, scr, "", col=DIM, dashed=True)
    c.arrow([(1415, 500), (1415, 590), (920, 590)], col=DIM, dashed=True)
    c.step(1155, 230, 4)
    c.text(1285, 660, "both read the", 18, SOFT, True, "middle")
    c.text(1285, 686, "same layers", 18, SOFT, True, "middle")
    c.save(OUT, "0.1-image-layers")


anatomy()
layers()
