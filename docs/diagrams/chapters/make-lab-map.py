#!/usr/bin/env python3
"""Draw the map of the whole lab for the root README with the kit in ../bbg.py.

  lab-map   your machine, the toolbox, the k3d lab, the practice cluster, Ollama and the VM

Run from anywhere: python3 docs/diagrams/chapters/make-lab-map.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def lab_map():
    c = Canvas(1760, 1000)
    c.title("How the lab", "fits together")
    c.subtitle("Two clusters in one Docker engine on your machine, and a VM only for module 4.7.")

    c.frame(40, 150, 1680, 820, "Your machine", "host")
    term = c.node(70, 250, 250, 110, SLATE, "Terminal", "terminal", "./lab.sh")
    web = c.node(70, 480, 250, 110, SLATE, "Browser", "globe", "localhost ports")
    llm = c.node(70, 730, 250, 110, SLATE, "Ollama", "sparkle", "track 5")

    c.frame(540, 200, 860, 740, "Docker engine", "plain", icon="box")
    tb = c.node(570, 250, 800, 110, TEAL, "toolbox", "terminal", "kubectl, helm, k3d, kind, istioctl")

    lab = c.frame(570, 410, 390, 500, "k3d lab k8s-lab", "node")
    c.box(595, 460, 340, 80, SLATE, "the shop", "frontend, backend, Redis", size=18)
    c.box(595, 555, 340, 80, BLUE, "Istio ambient", "gateway, ztunnel, waypoint", size=18)
    c.box(595, 650, 340, 80, PURPLE, "ArgoCD", "syncs from GitHub", size=18)
    c.box(595, 745, 340, 80, ORANGE, "Grafana, Prometheus", "Jaeger, Loki, Kiali", size=18)
    c.note(765, 875, ["tracks 2, 3 and 5"], size=16, anchor="middle")

    pc = c.frame(980, 410, 390, 500, "practice cluster", "node")
    c.box(1005, 460, 340, 80, PURPLE, "practice-control-plane", "kubeadm control plane", size=17)
    c.box(1005, 555, 340, 80, TEAL, "practice-worker", "gVisor, Falco", size=18)
    c.box(1005, 650, 340, 80, ORANGE, "practice-registry", "registry.practice:5000", size=18)
    c.note(1175, 875, ["tracks 1 and 4, exams 1 to 6"], size=16, anchor="middle")

    c.frame(1430, 200, 260, 740, "VM cks-lima", "node")
    c.box(1450, 250, 220, 120, GREEN, "its own kernel", "Cilium, AppArmor", size=18)
    c.note(1560, 875, ["module 4.7 only"], size=16, anchor="middle")

    c.connect(term, tb, "./lab.sh shell", sa="right", sb="left", fa=0.5, fb=0.5, pos="above")
    c.connect(tb, lab, "kubectl", sa="bottom", sb="top", fa=0.24, fb=0.5, pos="right")
    c.connect(tb, pc, "kind", sa="bottom", sb="top", fa=0.75, fb=0.5, pos="right")
    c.connect(web, lab, "8080 and the UIs", sa="right", sb="left", fa=0.5, fb=(535 - 410) / 500,
              pos="above")
    c.connect(lab, llm, "host.docker.internal", sa="left", sb="right", fa=(785 - 410) / 500, fb=0.5,
              pos="above", dashed=True)
    c.save(OUT, "lab-map")


if __name__ == "__main__":
    lab_map()
