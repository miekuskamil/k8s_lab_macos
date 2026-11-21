#!/usr/bin/env python3
"""Draw the diagram in platform-engineering/3-istio/15-life-of-a-request.md with the kit in ../bbg.py.

  29-many-workers   one Deployment, many workers that each watch the API server and write back

Run from anywhere: python3 docs/diagrams/chapters/make-3.15.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def many_workers():
    c = Canvas(1600, 1000)
    c.title("One object,", "many workers")
    c.subtitle("Each worker watches the API server for its kind of object, acts, and writes the result back.")

    c.frame(40, 200, 280, 170, "Your Mac", "host")
    kc = c.node(60, 250, 240, 100, SLATE, "kubectl", "terminal", "apply a Deployment")
    kine = c.node(40, 820, 280, 110, ORANGE, "kine + SQLite", "db", "stores every object")

    api = c.node(380, 200, 260, 730, PURPLE, "API server", "server", "the notice\nboard")
    c.connect(kc, api, "POST", sa="right", sb="left", fb=(300 - 200) / 730, pos="above")
    c.connect(api, kine, "store", sa="left", sb="right", fa=(875 - 200) / 730, pos="above")

    c.frame(880, 150, 680, 620, "control plane: k3s server", "group")
    c.frame(880, 800, 680, 170, "Node", "node")
    workers = [(1, "Deployment controller", PURPLE, "gear", "Deployment", "ReplicaSet", 200),
               (2, "ReplicaSet controller", PURPLE, "gear", "ReplicaSet", "Pod, no node", 340),
               (3, "Scheduler", GREEN, "filter", "Pod, no node", "Pod bound", 480),
               (7, "EndpointSlice controller", PURPLE, "gear", "Pod Ready", "EndpointSlice", 620),
               ("4-6", "kubelet", TEAL, "server", "Pod on my node", "status: Ready", 840)]
    for n, label, col, icon, heard, wrote, y in workers:
        w = c.node(920, y, 600, 100, col, label, icon)
        if isinstance(n, int):
            c.step(w.x, w.y, n)
        else:
            c.chip(w.x + 6, w.b, "4 to 6", STEP, anchor="middle", solid=True, mono=False, size=15)
        c.line([(640, y + 32), (920, y + 32)], DIM, AW, dashed=True, head=True)
        c.text(780, y + 22, f"watch: {heard}", 16, SOFT, True, "middle", halo=True)
        c.line([(920, y + 68), (640, y + 68)], LINE, AW, head=True)
        c.text(780, y + 96, f"write: {wrote}", 16, INK, True, "middle", halo=True)
    c.save(OUT, "3.15-many-workers")


if __name__ == "__main__":
    many_workers()
