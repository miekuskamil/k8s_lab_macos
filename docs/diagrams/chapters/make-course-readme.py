#!/usr/bin/env python3
"""Draw the course map for the course section of README.md with the kit in ../bbg.py.

  readme-course-routes   module 1.1, then the Istio, operations and platform tracks

Run from anywhere: python3 docs/diagrams/chapters/make-course-readme.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def routes():
    c = Canvas(1600, 900)
    c.title("Routes through", "the course")
    c.subtitle("Every route starts at module 1.1. Each line is a route, each stop a module.")

    start = c.node(40, 400, 230, 100, SLATE, "Start here", "doc", "Istio in one picture")
    x0, y0 = 340, 450
    c.line([(270, y0), (x0 - 26, y0)], LINE, 3)

    def stop(x, y, n, col, r=24):
        c.ellipse(x, y, r, r, col, WHITE, 3)
        c.text(x, y + 6.5, str(n), 18 if len(str(n)) < 3 else 15, deep(col), True, "middle")

    def lane(y, col, stops, label, sub, xs=420, gap=62, dashed=False):
        c.line([(x0 + 40, y), (xs + (len(stops) - 1) * gap, y)], col, 5, dashed)
        for i, n in enumerate(stops):
            stop(xs + i * gap, y, n, col)
        end = xs + (len(stops) - 1) * gap + 50
        c.text(end, y - 2, label, 19, deep(col), True)
        c.text(end, y + 22, sub, 16, SOFT)
        return xs + (len(stops) - 1) * gap

    c.line([(x0 + 30, y0), (x0 + 40, y0)], SLATE, 5)
    c.line([(x0 + 40, 200), (x0 + 40, 780)], SLATE, 5)
    stop(x0, y0, 0, SLATE, 30)
    ist = [1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14, 15, 16, 30, 31, 45]
    lane(200, BLUE, ist, "Istio", "", gap=56)
    # module 3.20 branches off after 14, the AI route after the core
    x14 = 420 + ist.index(14) * 56
    c.line([(x14, 200), (x14, 290), (x14 + 60, 290)], BLUE, 4, True)
    stop(x14 + 84, 290, 32, BLUE)
    c.text(x14 + 120, 296, "throwaway cluster", 16, SOFT)
    x8 = 420 + ist.index(8) * 56
    c.line([(x8, 200), (x8, 360), (x8 + 40, 360)], PINK, 5)
    for i, n in enumerate([17, 18, 19]):
        stop(x8 + 64 + i * 62, 360, n, PINK)
    c.text(x8 + 64 + 2 * 62 + 50, 358, "AI on Kubernetes", 19, DEEP[PINK], True)
    c.text(x8 + 64 + 2 * 62 + 50, 382, "needs modules 3.3 to 3.6 and 3.11", 16, SOFT)

    lane(560, GREEN, [20, 21], "Kubernetes operations", "only module 1.1 needed")
    lane(670, ORANGE, [22, 23, 24, 25, 26, 28], "Platform tools", "GitOps, alerts, dashboards, OTel, policy, profiling")
    lane(780, PINK, [27], "AI without Istio", "RAG, needs Ollama")

    ref = c.frame(1180, 420, 380, 120, "Reference, read any time", "plain")
    stop(1220, 490, 9, SLATE)
    c.text(1256, 496, "commands", 17, SOFT)
    stop(1390, 490, 10, SLATE)
    c.text(1426, 496, "eBPF, Cilium", 17, SOFT)
    c.text(420, 150, "29 ties the core together after 7, and 45 follows it outward", 16, SOFT)
    c.save(OUT, "readme-course-routes")


if __name__ == "__main__":
    routes()
