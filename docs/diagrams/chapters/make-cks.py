#!/usr/bin/env python3
"""Draw the diagrams for the CKS track (certs/cks) in ByteByteGo style (see ../bbg.py).

  cks-practice-cluster   the two OrbStack machines and what runs on each
  cks-supply-chain       where each supply chain check sits, from Dockerfile to node
  cks-runtime-layers     what seccomp, AppArmor and Falco do with one system call

Run from anywhere: python3 docs/diagrams/chapters/make-cks.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def practice_cluster():
    c = Canvas(1800, 760)
    c.title("The CKS", "practice cluster")
    c.subtitle("Two OrbStack machines, one kernel, built by kubeadm.")

    c.node(60, 360, 280, 110, SLATE, "Your Mac", "laptop", "orb -m cks-cp")

    c.group(440, 190, 620, 480, "cks-cp, control plane")
    c.node(480, 230, 540, 100, PURPLE, "Static pods", "server", "API server, etcd")
    c.outline(480, 370, 260, 80, GREEN, "Calico", "globe")
    c.outline(760, 370, 260, 80, BLUE, "Ingress", "globe")
    c.outline(480, 490, 260, 80, RED, "Image policy", "shield")
    c.outline(760, 490, 260, 80, TEAL, "Scanners", "eye")
    c.note(480, 610, ["etcdctl, trivy, kube-bench,", "kubesec, bom"])

    c.group(1160, 190, 580, 480, "cks-w1, worker")
    c.node(1200, 230, 500, 100, SLATE, "Your pods", "cube", "the task workloads")
    c.outline(1200, 370, 240, 80, GREEN, "Calico", "globe")
    c.outline(1460, 370, 240, 80, TEAL, "runc", "gear")
    c.outline(1200, 490, 240, 80, RED, "Falco", "eye")
    c.outline(1460, 490, 240, 80, PINK, "gVisor", "lock")

    c.arrow([(340, 415), (440, 415)], "shell", dashed=False, pos="above", at=(390, 415))
    c.arrow([(1060, 280), (1160, 280)], "kubelet", dashed=True, pos="above", at=(1110, 280))
    c.rect(440, 690, 1300, 30, DIM, "#2a2b33", rx=8, sw=1.5)
    c.text(1090, 712, "one shared OrbStack kernel: no AppArmor, no WireGuard", 17, SOFT, False, "middle")
    c.save(OUT, "cks-practice-cluster")


def supply_chain():
    c = Canvas(1800, 620)
    c.title("Supply chain", "checks")
    c.subtitle("Each check catches a different mistake, at a different place.")

    xs = [60, 400, 740, 1080, 1420]
    labels = [("Dockerfile", "doc", "small base"), ("Build", "gear", "CI pipeline"),
              ("Registry", "db", "signed image"), ("API server", "server", "admission"),
              ("Node", "cube", "runs pod")]
    cols = [SLATE, SLATE, ORANGE, PURPLE, SLATE]
    for (lab, ic, sub), x, col in zip(labels, xs, cols):
        c.node(x, 220, 300, 110, col, lab, ic, sub)
    for i in range(4):
        c.arrow([(xs[i] + 300, 275), (xs[i + 1], 275)], dashed=False)

    checks = [("kubesec", "static analysis"), ("trivy, bom", "CVEs and SBOM"),
              ("cosign", "signature"), ("ImagePolicy", "allowed registries")]
    for (lab, sub), x in zip(checks, [60, 400, 740, 1080]):
        c.outline(x, 430, 300, 90, RED, lab, "shield")
        c.text(x + 150, 560, sub, 17, SOFT, False, "middle")
        c.line([(x + 150, 430), (x + 150, 330)], RED, 2.5, dashed=True)
    c.outline(1420, 430, 300, 90, RED, "Falco", "eye")
    c.text(1570, 560, "behaviour at runtime", 17, SOFT, False, "middle")
    c.line([(1570, 430), (1570, 330)], RED, 2.5, dashed=True)
    c.save(OUT, "cks-supply-chain")


def runtime_layers():
    c = Canvas(1800, 680)
    c.title("One system call,", "three guards")
    c.subtitle("seccomp and AppArmor block. Falco only watches and reports.")

    c.node(60, 200, 300, 110, SLATE, "Container", "cube", "calls open()")
    c.node(500, 200, 300, 110, RED, "seccomp", "shield", "which calls?")
    c.node(940, 200, 300, 110, PINK, "AppArmor", "shield", "which files?")
    c.node(1380, 200, 340, 110, GREEN, "Kernel", "server", "does the work")
    c.arrow([(360, 255), (500, 255)], n=1, at=(430, 255), dashed=False)
    c.arrow([(800, 255), (940, 255)], n=2, at=(870, 255), dashed=False)
    c.arrow([(1240, 255), (1380, 255)], n=3, at=(1310, 255), dashed=False)

    c.node(1380, 460, 340, 110, RED, "Falco", "eye", "eBPF probe")
    c.arrow([(1550, 310), (1550, 460)], "copy of event", n=4, at=(1550, 385), dashed=True)
    c.node(940, 460, 300, 110, SLATE, "Alert", "doc", "journal")
    c.arrow([(1380, 515), (1240, 515)], n=5, at=(1310, 515), dashed=False)
    c.save(OUT, "cks-runtime-layers")


if __name__ == "__main__":
    practice_cluster()
    supply_chain()
    runtime_layers()
