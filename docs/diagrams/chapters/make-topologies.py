#!/usr/bin/env python3
"""Draw the three supported topologies for the guide with the kit in ../bbg.py.

  topology-mac       macOS, OrbStack, Docker with four containers, and the Lima VM for module 4.7
  topology-linux     a Linux machine with Docker and the same four containers
  topology-proxmox   the lab host VM with Docker, two practice VMs for module 4.7, and your laptop's browser

Run from anywhere: python3 docs/diagrams/chapters/make-topologies.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def containers(c, x, y, w):
    """The four Docker containers in one row, each with its command and memory."""
    gap = 30
    bw = (w - 3 * gap) / 4
    parts = [(SLATE, "toolbox", "./lab.sh shell", "about 0.1 GB"),
             (BLUE, "k3d lab", "./lab.sh up", "about 5 GB"),
             (GREEN, "kind practice", "./lab.sh practice up", "about 1.3 GB"),
             (ORANGE, "Ollama", "./lab.sh ollama", "2.5 GB, optional")]
    boxes = []
    for i, (col, name, cmd, mem) in enumerate(parts):
        bx = x + i * (bw + gap)
        boxes.append(c.box(bx, y, bw, 110, col, name, mem))
        c.text(bx + bw / 2, y + 140, cmd, 15, SOFT, anchor="middle", mono=True)
    return boxes


def mac():
    c = Canvas(1600, 620)
    c.title("On a Mac:", "one Docker engine")
    c.subtitle("OrbStack runs Docker, Docker runs every part of the course, and Lima adds one VM for module 4.7.")
    c.frame(40, 150, 1520, 430, "macOS", "host")
    c.frame(80, 210, 1080, 330, "OrbStack", "plain", col=PURPLE)
    c.frame(120, 270, 1000, 230, "Docker", "group")
    containers(c, 150, 330, 940)
    lima = c.frame(1200, 210, 320, 330, "Lima", "plain", col=PURPLE)
    c.box(1230, 330, 260, 110, RED, "cks-lima VM", "3 GiB, module 4.7")
    c.text(1360, 470, "lima.sh create", 15, SOFT, anchor="middle", mono=True)
    c.save(OUT, "topology-mac")


def linux():
    c = Canvas(1600, 560)
    c.title("On Linux:", "Docker and nothing else")
    c.subtitle("The same four containers as on a Mac, straight on Docker Engine. Give the machine 12 GB or more.")
    c.frame(40, 150, 1520, 370, "Ubuntu 24.04", "host")
    c.frame(80, 210, 1440, 270, "Docker Engine", "group")
    containers(c, 120, 260, 1360)
    c.save(OUT, "topology-linux")


def proxmox():
    c = Canvas(1600, 900)
    c.title("On Proxmox:", "one Docker VM")
    c.subtitle("One VM holds the whole lab. Two small VMs exist only for the kernel tasks, and the toolbox reaches them over SSH.")
    c.frame(40, 150, 1180, 700, "Proxmox host", "host")
    vm = c.frame(80, 210, 1100, 380, "VM pe-lab: lab host", "plain", col=PURPLE, right="8 GB, 4 cores, 80 GB")
    c.frame(110, 270, 1040, 250, "Docker", "group")
    boxes = containers(c, 140, 320, 980)
    cp = c.box(80, 680, 400, 110, RED, "VM cks-cp", "3 GB, 2 cores")
    w1 = c.box(560, 680, 400, 110, RED, "VM cks-w1", "2.5 GB, 2 cores")
    c.text(520, 830, "PRACTICE_PLATFORM=vms, module 4.7 only", 15, SOFT, anchor="middle", mono=True)
    c.connect(boxes[0], cp, "ssh", sa="bottom", sb="top", fa=0.1, fb=0.2, pos="right", mid=640)
    c.connect(boxes[0], w1, "", sa="bottom", sb="top", fa=0.92, fb=0.2, mid=640)
    laptop = c.node(1280, 380, 260, 120, SLATE, "Your laptop", "globe", "browser")
    c.connect(laptop, vm, "ssh -L", sa="left", sb="right", fa=0.5, fb=(440 - 210) / 380, pos="above")
    c.save(OUT, "topology-proxmox")


if __name__ == "__main__":
    mac()
    linux()
    proxmox()
