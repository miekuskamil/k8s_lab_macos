#!/usr/bin/env python3
"""Draw the course map for the guide with the kit in ../bbg.py.

  readme-course-routes   the six tracks, each from the quick start, its modules from easy to hard

Run from anywhere: python3 docs/diagrams/chapters/make-course-readme.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def routes():
    c = Canvas(1600, 1040)
    c.title("Six tracks,", "one lab")
    c.subtitle("Every track starts from the quick start and needs no other track. Each stop is a module, easy on the left.")

    start = c.node(40, 515, 230, 110, SLATE, "Quick start", "terminal", "lab.sh shell, up")
    trunk = 330

    def stop(x, y, n, col, r=23):
        c.ellipse(x, y, r, r, col, WHITE, 3)
        c.text(x, y + 6, str(n), 17 if len(str(n)) < 2 else 15, deep(col), True, "middle")

    gap = 54
    xs = 400

    def lane(y, col, n, label, sub, exams=None):
        last = xs + (n - 1) * gap
        c.line([(trunk, y), (last, y)], col, 5)
        for i in range(n):
            stop(xs + i * gap, y, i + 1, col)
        if exams:
            ex = last + 60
            c.line([(last + 23, y), (ex, y)], col, 4, True)
            c.rect(ex, y - 22, 130, 44, col, WHITE, rx=22, sw=3)
            c.text(ex + 65, y + 6, exams, 15, deep(col), True, "middle")
        c.text(xs - 23, y - 42, label, 19, deep(col), True)
        c.text(xs - 23 + 11 * len(label) + 20, y - 42, sub, 16, SOFT)

    c.line([(270, 570), (trunk, 570)], SLATE, 5)
    c.line([(trunk, 210), (trunk, 935)], SLATE, 5)
    lane(210, TEAL, 8, "0 Docker and Compose", "Docker only, containers to a hardened capstone")
    lane(355, SLATE, 6, "1 Applications", "practice cluster, build to debug", "exams 1-3")
    lane(500, ORANGE, 9, "2 Observability and platform", "lab, metrics to k3s upgrades")
    lane(645, BLUE, 21, "3 Istio service mesh", "lab, what a mesh adds to installing it")
    lane(790, RED, 7, "4 Cluster security", "practice cluster, network to kernel", "exams 4-6")
    lane(935, PINK, 4, "5 AI on Kubernetes", "lab, a model call to RAG")
    c.save(OUT, "readme-course-routes")


if __name__ == "__main__":
    routes()
