#!/usr/bin/env python3
"""Draw the diagrams for course module 0.7 (debugging) with the kit in ../bbg.py.

  0.7-ladder            where each rung of the ladder reads its answer
  0.7-debug-container   a debug container in the namespaces of a container with no shell

The circled numbers match the numbered lists in module 0.7.

Run from anywhere: python3 docs/diagrams/chapters/make-0.7.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def ladder():
    c = Canvas(1600, 960)
    c.title("The debugging ladder:", "cheap questions first")
    c.subtitle("Each command reads a different record. Go inside the container only at the last rung.")

    c.frame(40, 150, 1520, 770, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(80, 210, 340, 670, "toolbox", "pod")
    cmds = []
    labels = [("docker ps -a", "state, exit, health"), ("docker logs", "stdout and stderr"),
              ("docker events", "start, die, kill"), ("docker inspect", "configuration"),
              ("exec or debug", "inside the namespaces")]
    y = 270
    for t, sub in labels:
        cmds.append(c.box(110, y, 280, 90, SLATE, t, sub, size=19))
        y += 120

    c.frame(520, 210, 600, 550, "dockerd", "plain", col=PURPLE)
    st = c.box(560, 270, 520, 90, PURPLE, "container state", "status, exit code, health log", size=19)
    lg = c.box(560, 390, 520, 90, ORANGE, "log file", "one per container", size=19)
    ev = c.box(560, 510, 520, 90, PURPLE, "event stream", "last few minutes", size=19)
    cf = c.box(560, 630, 520, 90, PURPLE, "container config", "command, env, mounts", size=19)

    c.frame(1180, 210, 340, 670, "course-hits", "pod")
    app = c.box(1210, 750, 280, 90, SLATE, "/hits", "PID 1, no shell")
    for i, tgt in enumerate([st, lg, ev, cf]):
        c.connect(cmds[i], tgt, "", n=i + 1, sa="right", sb="left", fa=0.5, fb=0.5, mid=470)
    c.connect(cmds[4], app, "", n=5, sa="right", sb="left", fa=0.5, fb=0.5)
    c.connect(app, lg, "", sa="top", sb="right", fa=0.5, fb=0.5, col=ORANGE, dashed=True)
    c.save(OUT, "0.7-ladder")


def debug():
    c = Canvas(1600, 900)
    c.title("A debug container", "borrows the namespaces")
    c.subtitle("--network container: and --pid container: put a toolbox next to an app that has no shell.")

    c.frame(40, 150, 1520, 710, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(80, 210, 1440, 610, "course-hits network and process namespaces", "plain", col=GREEN)
    c.frame(120, 270, 560, 320, "course-hits", "pod")
    fs = c.box(160, 380, 480, 80, ORANGE, "its files", "image + writable layer")
    app = c.box(160, 490, 480, 80, SLATE, "/hits", "PID 1, user 65532")
    c.frame(860, 270, 620, 320, "debug container", "pod")
    c.box(900, 320, 540, 60, BLUE, "course/nettools:1.0", "own tools", size=18)
    rt = c.box(900, 400, 540, 60, ORANGE, "ls /proc/1/root", "needs SYS_PTRACE", size=18)
    ps = c.box(900, 490, 250, 80, SLATE, "ps", "sees /hits", size=18)
    ss = c.box(1190, 490, 250, 80, GREEN, "ss -ltnp", "port 8123", size=18)
    sock = c.box(120, 680, 1360, 90, GREEN, "listening socket :8123", "one network namespace, shared by both", size=19)

    c.step(140, 530, 1)
    c.step(880, 300, 2)
    c.connect(ps, app, "")
    c.connect(ss, sock, "", n=3, sa="bottom", sb="top", fa=0.5, fb=(1315 - 120) / 1360)
    c.connect(app, sock, "", sa="bottom", sb="top", fa=0.5, fb=(400 - 120) / 1360, col=GREEN, dashed=True)
    c.connect(rt, fs, "", n=4)
    c.save(OUT, "0.7-debug-container")


ladder()
debug()
