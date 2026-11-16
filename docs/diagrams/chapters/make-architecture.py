#!/usr/bin/env python3
"""Draw the diagrams in docs/architecture.md with the kit in ../bbg.py.

  chapters/architecture-request-path   how one request travels, hops 1 to 9
  ../traffic-flow                      trust zones and which hops are encrypted
  ../gitops-flow                       how a git push reaches the cluster

Arrow styles: thick blue = mTLS tunnel, solid = plaintext, dashed = control and telemetry.

Run from anywhere: python3 docs/diagrams/chapters/make-architecture.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent
DIAGRAMS = OUT.parent


def _lab(c, zones=False):
    """The lab's layout: your Mac, the k3d load balancer and one k3s node with its namespaces.
    Returns the boxes the flows attach to."""
    b = {}
    c.frame(40, 150, 270, 280, "Your Mac", "host")
    b["browser"] = c.node(60, 220, 230, 110, SLATE, "Browser", "globe", "localhost:8080")

    c.frame(350, 150, 1210, 880, "OrbStack: k3d cluster k8s-lab", "cluster")
    b["lb"] = c.node(380, 220, 240, 110, SLATE, "load balancer", "server", "k3d, :8080")
    c.frame(660, 190, 880, 810, "k3s node container", "node")

    c.frame(690, 240, 230, 180, "namespace argocd", "ns")
    b["argo"] = c.box(710, 300, 190, 90, PURPLE, "ArgoCD", ":8081")
    c.frame(940, 240, 260, 180, "namespace istio-system", "ns")
    b["istiod"] = c.box(960, 300, 220, 90, PURPLE, "istiod", "xDS :15012")
    obs = c.frame(1220, 240, 290, 180, "namespace observability", "ns", col=GREEN if zones else None,
                  fill="none" if zones else None)
    b["obs"] = c.box(1240, 300, 250, 90, GREEN, "Prometheus", "Grafana, Jaeger")

    c.frame(690, 470, 230, 260, "shop-ingress", "ns", right="no mesh" if zones else "")
    b["gw"] = c.box(710, 540, 190, 110, BLUE, "gateway", "Envoy :8080")
    c.frame(940, 470, 570, 260, "namespace shop", "ns", col=GREEN if zones else None, fill="none" if zones else None,
            right="ambient")
    for k, x, t, sub, col in (("fe", 955, "frontend", ":3000", SLATE), ("wp", 1095, "waypoint", "Envoy", BLUE),
                              ("be", 1235, "backend", "v1 x2, v2", SLATE), ("rd", 1375, "redis", ":6379", ORANGE)):
        b[k] = c.box(x, 540, 125, 110, col, t, sub, size=18)
    b["zt"] = c.band(690, 780, 820, 190, BLUE, "ztunnel", "one per node, HBONE :15008, socket in each pod", "tunnel",
                     lx=700, ly=930)
    return b


def _hbone(c, x0, x1, y, top=650):
    """A hop that drops from a pod into ztunnel and rises into the next pod."""
    c.line([(x0, top), (x0, y), (x1, y), (x1, top)], BLUE, 4.5, head=True)


def request_path():
    c = Canvas(1600, 1070)
    c.title("How a request", "travels")
    c.subtitle("From the browser to Redis. Blue hops run inside an mTLS tunnel, gray ones are plain or control traffic.")
    b = _lab(c)
    c.connect(b["browser"], b["lb"], "", n=1, sa="right", sb="left", at=(320, 275))
    c.connect(b["lb"], b["gw"], "TCP", sa="bottom", sb="left", fa=0.5, fb=0.5, pos="right", at=(500, 470))
    _hbone(c, 805, 1000, 820)
    c.step(900, 820, 2)
    c.text(900, 800, "HBONE", 16, DEEP[BLUE], True, "middle", halo=True)
    c.line([(1050, 650), (1050, 845), (1140, 845), (1140, 650)], BLUE, 4.5, head=True)
    c.step(1050, 700, 3)
    c.step(1095, 845, 4)
    _hbone(c, 1180, 1275, 870)
    c.step(1228, 870, 5)
    _hbone(c, 1315, 1435, 895)
    c.step(1375, 895, 6)
    c.connect(b["istiod"], Box(940, 470, 570, 1), "xDS, certificates", sa="bottom", sb="top", dashed=True,
              col=PURPLE, pos="right")
    c.legend(380, 1010, [(BLUE, "mTLS tunnel"), (LINE, "plain"), (PURPLE, "control", True)])
    c.save(OUT, "architecture-request-path")


def trust_zones():
    c = Canvas(1600, 1070)
    c.title("Traffic flow and", "trust zones")
    c.subtitle("Green namespaces are in the mesh. On blue hops the receiver checks the identity written beside it.")
    b = _lab(c, zones=True)
    c.connect(b["browser"], b["lb"], "HTTP", sa="right", sb="left", pos="above")
    c.connect(b["lb"], b["gw"], "nothing checked", sa="bottom", sb="left", fa=0.5, fb=0.5, pos="left", at=(500, 470))
    _hbone(c, 805, 1000, 820)
    c.text(900, 805, "gateway SA", 15, DEEP[BLUE], True, "middle", halo=True)
    _hbone(c, 1040, 1135, 845)
    c.text(1088, 865, "shop/frontend", 15, DEEP[BLUE], True, "middle", halo=True)
    _hbone(c, 1180, 1275, 870)
    c.text(1228, 890, "shop/waypoint", 15, DEEP[BLUE], True, "middle", halo=True)
    _hbone(c, 1315, 1435, 895)
    c.text(1375, 915, "shop/backend", 15, DEEP[BLUE], True, "middle", halo=True)
    c.line([(1365, 420), (1365, 470)], BLUE, 4.5, head=True)
    c.text(1380, 452, "scrape: Prometheus SA", 15, DEEP[BLUE], True, halo=True)
    c.legend(380, 1010, [(BLUE, "mTLS: identity checked"), (LINE, "plain")])
    c.save(DIAGRAMS, "traffic-flow")


def gitops():
    c = Canvas(1600, 1000)
    c.title("From git push to", "live cluster")
    c.subtitle("ArgoCD polls GitHub, creates the child Applications and applies them.")

    you = c.node(40, 190, 260, 100, SLATE, "You", "person", "edit manifests")
    c.frame(40, 380, 260, 200, "GitHub", "plain", icon="git")
    gh = c.node(60, 440, 220, 110, ORANGE, "repo", "git", "main")
    c.connect(you, gh, "git push", n=1, pos="right", at=(170, 335))

    c.frame(350, 150, 1210, 820, "k3d cluster k8s-lab", "cluster")
    c.frame(390, 190, 560, 750, "namespace argocd", "ns")
    root = c.node(420, 240, 500, 100, PURPLE, "Application root", "refresh", "manifests/argocd/apps")
    c.connect(gh, root, "poll", n=2, sa="right", sb="left", fa=0.5, fb=0.5, via=[(330, 495), (330, 290)],
              pos="left", at=(330, 400))
    kids = [("shop-base", "namespaces, RBAC, quotas", "shop"),
            ("shop-apps", "frontend, backend, redis", "shop"),
            ("istio-config", "gateway, waypoint, routes", "shop"),
            ("kube-prometheus-stack", "Helm chart", "obs"),
            ("observability-config", "Jaeger, monitors, dashboards", "obs"),
            ("loki, alloy, kiali", "three Helm charts", "obs")]
    rows = []
    for i, (name, sub, _) in enumerate(kids):
        y = 420 + i * 84
        col = PINK if name == "istio-config" else PURPLE
        rows.append(c.box(450, y, 470, 70, col, name, sub, size=18))
    c.chip(905, 420 + 2 * 84 + 6, "no selfHeal", PINK, anchor="end", size=13, mono=False)
    c.frame(420, 380, 520, 540, "child Applications", "group")
    c.connect(root, Box(420, 380, 520, 540), "creates", n=3, sa="bottom", sb="top", fa=0.5, fb=0.5, pos="right",
              at=(670, 360))

    shop = c.frame(1010, 300, 520, 300, "namespaces shop, shop-ingress", "ns")
    for i, t in enumerate(["frontend", "backend", "waypoint", "gateway"]):
        c.box(1040 + (i % 2) * 240, 360 + (i // 2) * 110, 220, 90, SLATE if i < 2 else BLUE, t, size=18)
    obs = c.frame(1010, 660, 520, 260, "namespace observability", "ns")
    for i, t in enumerate(["Prometheus", "Grafana", "Loki", "Kiali"]):
        c.box(1040 + (i % 2) * 240, 720 + (i // 2) * 95, 220, 75, GREEN, t, size=18)
    c.connect(Box(940, 315, 1, 270), shop, "apply", n=4, sa="right", sb="left", fa=0.5, fb=0.5, pos="above",
              at=(975, 450))
    c.connect(Box(940, 655, 1, 270), obs, "", sa="right", sb="left", fa=0.5, fb=0.5)
    c.connect(shop, root, "drift report", n=5, sa="top", sb="right", fa=0.3, fb=0.5, dashed=True, col=DIM,
              pos="right", at=(1166, 250))
    c.save(DIAGRAMS, "gitops-flow")


if __name__ == "__main__":
    request_path()
    trust_zones()
    gitops()
