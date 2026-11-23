#!/usr/bin/env python3
"""Draw the diagram for module 6.5 (backup and disaster recovery) with the kit in ../bbg.py.

  6.5-backup-and-restore   what Velero copies, from where, into which bucket

Run from anywhere: python3 docs/diagrams/chapters/make-6.5.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def backup():
    c = Canvas(1600, 960)
    c.title("Two kinds of state,", "one backup")
    c.subtitle("Velero puts the namespace's objects and the database's files in one bucket. A restore reads both back.")

    c.frame(40, 150, 330, 280, "your terminal", "host")
    cmd = c.box(70, 300, 270, 90, SLATE, "velero backup", "through kubectl exec")

    c.frame(420, 150, 1140, 770, "node k3d-k8s-lab-server-0", "node")
    c.frame(450, 250, 420, 480, "namespace velero", "ns")
    srv = c.box(480, 300, 360, 90, PURPLE, "velero server", "objects and hooks")
    agent = c.box(480, 615, 360, 90, TEAL, "node-agent", "Kopia, one per node")

    c.frame(910, 250, 350, 480, "", "ns", right="namespace course-dr")
    cr = c.box(940, 300, 290, 70, PURPLE, "Cluster orders-db", "CloudNativePG")
    c.frame(930, 400, 310, 220, "pod orders-db-1", "pod")
    pg = c.box(950, 450, 270, 70, SLATE, "postgres", "CHECKPOINT hook")
    vol = c.box(950, 535, 270, 70, ORANGE, "volume pgdata", "PVC, 1 GiB")

    c.frame(1290, 250, 240, 480, "", "ns", right="course-backup")
    s3 = c.box(1310, 300, 200, 405, ORANGE, "SeaweedFS", "bucket velero\nS3 API")

    disk = c.band(450, 790, 1080, 80, ORANGE, "node disk", "/var/lib/rancher/k3s/storage holds pgdata", icon="db")

    c.connect(cmd, srv, "", n=1, sa="right", sb="left", fa=0.5, fb=0.5, mid=395, at=(395, 345))
    c.connect(srv, pg, "hook", n=2, sa="right", sb="left", fa=0.8, fb=0.5, pos="above", at=(885, 372))
    c.connect(srv, s3, "", n=3, sa="top", sb="top", fa=320 / 360, fb=0.25, via=[(800, 222), (1360, 222)], at=(1100, 222))
    c.text(1135, 212, "objects as JSON", 18, INK, True, halo=True)
    c.connect(agent, disk, "reads files", n=4, sa="bottom", sb="top", fa=0.5, fb=210 / 1080, pos="right", at=(660, 748))
    c.connect(agent, s3, "uploads chunks", n=5, sa="right", sb="left", fa=0.5, fb=(660 - 300) / 405, pos="above", at=(1010, 660))
    c.save(OUT, "6.5-backup-and-restore")


if __name__ == "__main__":
    backup()
