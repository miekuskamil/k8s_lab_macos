#!/usr/bin/env python3
"""Draw the diagrams for module 22 (GitOps with ArgoCD) with the kit in ../bbg.py.

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
    c = Canvas(1600, 860)
    c.title("The reconcile", "loop")
    c.subtitle("Git holds the setting you want. ArgoCD keeps checking the cluster against it.")

    you = c.node(40, 200, 270, 110, SLATE, "You", "person", "git push")
    c.frame(40, 400, 270, 230, "GitHub", "plain", icon="git")
    git = c.node(65, 460, 220, 130, ORANGE, "Git repo", "git", "desired state")
    c.connect(you, git, "commit", n=1, pos="right")

    c.frame(360, 150, 1200, 680, "Cluster", "cluster")
    c.frame(400, 190, 730, 300, "namespace argocd", "ns")
    rs = c.frame(430, 250, 300, 200, "repo-server", "pod")
    c.box(455, 305, 250, 110, PURPLE, "render", "Kustomize, Helm")
    ac = c.frame(800, 250, 300, 200, "application-controller", "pod")
    c.box(825, 305, 250, 110, PURPLE, "compare", "desired vs live")
    c.frame(1170, 190, 360, 300, "control plane", "group")
    api = c.node(1200, 300, 300, 110, PURPLE, "API server", "server")

    c.connect(git, rs, "every 3 min\nor webhook", n=2, sa="right", sb="left", fa=0.5, fb=0.5,
              via=[(380, 525), (380, 350)], pos="left", at=(380, 440))
    c.connect(rs, ac, "manifests", pos="above")
    c.step(800, 250, 3)
    c.connect(ac, api, "sync: apply", n=4, sa="right", sb="left", fa=0.4, fb=(330 - 300) / 110, pos="above",
              at=(1150, 330))
    c.connect(api, ac, "watch live", sa="left", sb="right", fa=(385 - 300) / 110, fb=0.675, dashed=True, pos="below",
              at=(1150, 385))

    live = c.frame(400, 560, 1130, 230, "namespace podinfo-dev: live state", "ns")
    for i, (t, col) in enumerate([("Deployment", SLATE), ("ReplicaSet", SLATE), ("Pods", SLATE), ("Service", GREEN)]):
        c.box(440 + i * 270, 640, 240, 100, col, t)
    c.connect(api, live, "", sa="bottom", sb="top", fa=0.5, fb=(1350 - 400) / 1130)
    c.save(OUT, "22-reconcile-loop")


def sync_operation():
    c = Canvas(1600, 820)
    c.title("One sync operation", "at a time")
    c.subtitle("A sync keeps its Git revision until it ends. Retries reuse the old commit, and the fix waits.")

    c.frame(40, 150, 1520, 180, "Git: main branch", "plain", icon="git")
    c.line([(140, 250), (1460, 250)], DIM, 3)
    for x, name, col, sub in ((200, "A", SLATE, "works"), (420, "B", RED, "broken"), (1000, "C", GREEN, "the revert")):
        c.ellipse(x, 250, 26, 26, col, pastel(col), 2.4)
        c.text(x, 258, name, 22, deep(col), True, "middle")
        c.text(x, 300, sub, 17, SOFT, False, "middle")

    c.frame(40, 370, 1090, 410, "namespace argocd", "ns")
    app = c.frame(80, 430, 640, 310, "Application podinfo-dev", "plain", col=PURPLE, icon="doc")
    op = c.box(110, 490, 420, 200, PURPLE, "status.operationState", "revision: B, fixed\nphase: Running\nretryCount: 3")
    c.icon("refresh", 590, 560, PURPLE, s=1.3)
    c.text(620, 650, "retries B,", 16, DEEP[PURPLE], True, "middle")
    c.text(620, 671, "longer pauses", 16, DEEP[PURPLE], True, "middle")
    wait = c.frame(790, 430, 300, 130, "next sync: C", "plain", fill=WHITE)
    c.rect(790, 430, 300, 130, DIM, "none", 14, 1.6, True)
    c.text(810, 520, "waits", 18, SOFT, True)

    c.frame(1170, 370, 390, 410, "namespace podinfo-dev", "ns")
    live = c.box(1200, 560, 330, 120, RED, "live objects", "apply of B fails")

    c.connect(Box(394, 224, 52, 52), op, "start with B", n=1, sa="bottom", sb="top", fb=(420 - 110) / 420,
              pos="right", at=(420, 345))
    c.connect(app, live, "apply B", n=2, sa="right", sb="left", fa=(640 - 430) / 310, fb=(640 - 560) / 120, col=RED,
              pos="above", at=(1150, 640))
    c.connect(Box(974, 224, 52, 52), wait, "", sa="bottom", sb="top", fb=(1000 - 790) / 300, dashed=True, col=GREEN)
    c.step(1090, 430, 3)
    c.note(790, 600, ["starts once B's retries", "run out or you terminate"], 16)
    c.save(OUT, "22-sync-operation")


if __name__ == "__main__":
    reconcile_loop()
    sync_operation()
