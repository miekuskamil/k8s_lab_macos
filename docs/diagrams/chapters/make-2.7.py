#!/usr/bin/env python3
"""Draw the diagram for module 2.7 (Kyverno, policy as code) with the kit in ../bbg.py.

  2.7-where-kyverno-sits     one apply through the two Kyverno webhooks, plus the background parts

Solid arrows follow the request. Dashed arrows are the parts that work outside of requests,
as the module text says.

Run from anywhere: python3 docs/diagrams/chapters/make-2.7.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def where_kyverno_sits():
    c = Canvas(1600, 900)
    c.title("Where Kyverno", "sits")
    c.subtitle("The API server calls Kyverno twice for every object it receives. Two more controllers work outside requests.")

    you = c.node(40, 230, 270, 110, SLATE, "You or ArgoCD", "person", "kubectl apply")

    c.frame(350, 150, 470, 710, "control plane", "group")
    c.frame(380, 200, 410, 520, "API server", "plain", col=PURPLE, icon="server")
    auth = c.box(410, 255, 350, 70, PURPLE, "authenticate, authorize", size=18)
    mut = c.box(410, 365, 350, 80, PINK, "mutating admission", "calls webhooks")
    sch = c.box(410, 485, 350, 70, PURPLE, "schema check", size=18)
    val = c.box(410, 595, 350, 80, PINK, "validating admission", "calls webhooks")
    for a, b in ((auth, mut), (mut, sch), (sch, val)):
        c.connect(a, b)
    etcd = c.node(410, 760, 350, 80, ORANGE, "etcd / kine", "db", "stored object")
    c.connect(val, etcd, "store", n=4, sa="bottom", sb="top", pos="right", at=(585, 720))
    c.connect(you, auth, "", n=1, sa="right", sb="left", fa=0.5, fb=(285 - 255) / 70, at=(345, 285))

    c.frame(880, 150, 680, 710, "namespace kyverno", "ns")
    adm = c.frame(910, 200, 620, 520, "admission controller pod", "pod")
    mw = c.box(1100, 360, 400, 90, PINK, "mutating webhook", "adds defaults")
    vw = c.box(1100, 590, 400, 90, PINK, "validating webhook", "allows or denies")
    c.connect(mut, mw, "object", n=2, sa="right", sb="left", fa=0.3, fb=0.3, pos="above", at=(930, 389))
    c.connect(mw, mut, "patch", sa="left", sb="right", fa=0.75, fb=0.75, pos="below", col=PINK, at=(930, 427))
    c.connect(val, vw, "object", n=3, sa="right", sb="left", fa=0.3, fb=0.3, pos="above", at=(930, 619))
    c.connect(vw, val, "allow / deny", sa="left", sb="right", fa=0.75, fb=0.75, pos="below", col=PINK, at=(930, 657))

    bg = c.box(910, 760, 300, 80, TEAL, "background", "scans, generates")
    rp = c.box(1230, 760, 300, 80, TEAL, "reports", "writes PolicyReports")
    c.connect(bg, Box(380, 200, 410, 520), "", sa="left", sb="right", fa=0.5, fb=0.95, dashed=True, col=TEAL,
              via=[(850, 800), (850, 694)])
    c.save(OUT, "2.7-where-kyverno-sits")


if __name__ == "__main__":
    where_kyverno_sits()
