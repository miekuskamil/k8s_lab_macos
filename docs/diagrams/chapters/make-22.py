#!/usr/bin/env python3
"""Draw the diagrams for module 22 (GitOps with ArgoCD) in ByteByteGo style (see ../bbg.py).

  22-reconcile-loop     the four steps of the reconcile loop
  22-sync-operation     a failing sync operation blocks the revert

Run from anywhere: python3 docs/diagrams/chapters/make-22.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def reconcile_loop():
    c = Canvas(1520, 690)
    c.title("The reconcile", "loop")
    c.subtitle("Git holds the setting you want. ArgoCD keeps checking the cluster against it.")

    c.node(60, 200, 300, 110, SLATE, "You", "person", "git push")
    c.node(560, 200, 330, 110, ORANGE, "Git", "doc", "desired state")
    c.node(1100, 200, 360, 110, PURPLE, "repo-server", "gear", "Kustomize · Helm")
    c.arrow([(360, 255), (560, 255)], "Push a\ncommit", n=1, at=(460, 255), pos="below")
    c.arrow([(890, 255), (1100, 255)], "every 3 min\nor webhook", n=2, at=(995, 255), pos="below")

    c.node(1100, 500, 360, 120, PURPLE, "application-\ncontroller", "gear", "desired vs live", size=22)
    c.step(1460, 500, 3)
    c.arrow([(1280, 310), (1280, 500)], "Rendered\nmanifests", at=(1280, 405), col=SOFT)

    c.node(560, 500, 330, 120, SLATE, "Cluster", "server", "live state")
    c.arrow([(1100, 535), (890, 535)], "Sync:\nkubectl apply", n=4, at=(995, 535), pos="above")
    c.arrow([(890, 590), (1100, 590)], "Watch", at=(995, 590), pos="below", col=SOFT)
    c.save(OUT, "22-reconcile-loop")


def sync_operation():
    c = Canvas(1560, 720)
    c.title("One sync operation", "at a time")
    c.subtitle("A sync keeps its Git revision until it ends. Retries reuse the old commit, and the fix waits.")

    c.node(60, 250, 300, 110, RED, "Commit B", "doc", "broken")
    c.node(560, 250, 340, 110, PURPLE, "Operation", "gear", "sync B")
    c.node(1100, 250, 380, 110, RED, "Retry sync B", "gear", "longer pause each time")
    c.arrow([(360, 305), (560, 305)], "Start", n=1, at=(460, 305), pos="below")
    c.arrow([(900, 305), (1100, 305)], "Fails", n=2, at=(1000, 305), pos="below")
    c.line([(1230, 250), (1230, 200), (1350, 200), (1350, 250)], LINE, 2.5, True, head=True)
    c.text(1290, 188, "Fails again", 18, SOFT, True, "middle")

    c.node(60, 540, 300, 110, GREEN, "Commit C", "doc", "the revert")
    c.node(1100, 540, 380, 110, PURPLE, "Operation", "gear", "sync C")
    c.arrow([(360, 595), (1100, 595)], "Waits", at=(730, 595), pos="above", col=SOFT)
    c.arrow([(1290, 360), (1290, 540)], "retries used up\nor terminated", n=3, at=(1290, 450))
    c.save(OUT, "22-sync-operation")


if __name__ == "__main__":
    reconcile_loop()
    sync_operation()
