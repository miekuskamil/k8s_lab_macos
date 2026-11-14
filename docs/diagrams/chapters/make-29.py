#!/usr/bin/env python3
"""Draw the diagram in platform-engineering/29-life-of-a-request.md in ByteByteGo style (see ../bbg.py).

  29-many-workers   one Deployment, many workers that each watch the API server and write back

Run from anywhere: python3 docs/diagrams/chapters/make-29.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def many_workers():
    c = Canvas(1760, 1120)
    c.title("One object,", "many workers")
    c.subtitle("Each worker watches the API server, acts, and writes back.")

    c.node(60, 250, 300, 110, SLATE, "kubectl", "laptop", "apply a Deployment")
    c.node(500, 200, 420, 690, RED, "API server", "lock", "authn · authz · admission")
    c.arrow([(360, 305), (500, 305)], "POST", n=1, at=(430, 305), pos="below", dashed=False)

    c.node(500, 980, 420, 100, ORANGE, "kine + SQLite", "db", "stores every object")
    c.arrow([(710, 890), (710, 980)], "Store", n=2, at=(710, 935), dashed=False)

    c.group(1180, 170, 560, 900, "Watchers")
    workers = [(3, "Deployment\ncontroller", PURPLE, "gear", "Deployment ADDED", "create ReplicaSet"),
               (4, "ReplicaSet\ncontroller", PURPLE, "gear", "ReplicaSet ADDED", "create Pod, no node"),
               (5, "Scheduler", GREEN, "gear", "Pod without a node", "bind Pod to a node"),
               (6, "kubelet", TEAL, "server", "Pod on my node", "status: Ready")]
    for i, (n, label, col, icon, heard, wrote) in enumerate(workers):
        y = 210 + i * 210
        sub = "sandbox, containers, probes" if label == "kubelet" else None
        c.node(1220, y, 480, 120, col, label, icon, sub)
        c.step(1220, y, n)
        c.arrow([(920, y + 30), (1220, y + 30)], heard, at=(1070, y + 30), pos="above", col=SOFT)
        c.arrow([(1220, y + 90), (920, y + 90)], wrote, at=(1070, y + 90), pos="below", dashed=False)

    c.line([(60, 470), (100, 470)], SOFT, 2.5, True)
    c.text(115, 476, "watch", 17, SOFT)
    c.line([(60, 510), (100, 510)], LINE, 2.5)
    c.text(115, 516, "write back", 17, SOFT)
    c.save(OUT, "29-many-workers")


if __name__ == "__main__":
    many_workers()
