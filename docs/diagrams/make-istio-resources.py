#!/usr/bin/env python3
"""Draw "Istio in one picture": the lab's request path with every Istio resource
pinned to the proxy that enforces it.

Writes two files from one description, so they always match:
  istio-resources.excalidraw   open and edit at https://excalidraw.com
  istio-resources.svg          shown on GitHub and in the course

Run from anywhere: python3 docs/diagrams/make-istio-resources.py
"""
import json
from html import escape
from pathlib import Path

OUT = Path(__file__).resolve().parent
W, H = 1640, 1080

# Colours: (stroke, fill)
GREY = ("#57606a", "#f6f8fa")      # components and pods
PROXY = ("#0969da", "#ddf4ff")     # Envoy and ztunnel proxies
CTRL = ("#8250df", "#fbefff")      # control plane
TRAFFIC = ("#0969da", "#dbeafe")   # traffic resources
SECURITY = ("#cf222e", "#ffebe9")  # security resources
OBS = ("#1a7f37", "#dafbe1")       # observability resources
EXT = ("#9a6700", "#fff8c5")       # outside the cluster
INK = "#24292f"

boxes = []   # (id, x, y, w, h, colours, title, lines, dashed)
arrows = []  # (points, colour, label, dashed, label_xy)
texts = []   # (x, y, text, size, colour, bold)
CHAR = 7.3   # rough width of one 14 px character


def wrap(line, width):
    out, cur = [], ""
    for word in line.split():
        if cur and (len(cur) + 1 + len(word)) * CHAR > width:
            out.append(cur)
            cur = word
        else:
            cur = f"{cur} {word}".strip()
    return out + ([cur] if cur else [])


def box(i, x, y, w, col, title, lines=(), dashed=False, h=None):
    wrapped = [part for line in lines for part in wrap(line, w - 24)]
    height = h or (36 + 19 * len(wrapped) + (8 if wrapped else 0))
    boxes.append((i, x, y, w, height, col, title, wrapped, dashed))
    return y + height


def arrow(points, col=INK, label="", dashed=False, at=None):
    arrows.append((points, col, label, dashed, at))


def text(x, y, t, size=16, col=INK, bold=False):
    texts.append((x, y, t, size, col, bold))


def notes(x, y, w, header, items):
    text(x, y, header, 15, "#57606a", True)
    y += 12
    for col, title, line in items:
        y = box(title, x, y, w, col, title, [line]) + 10
    return y


# ---- title ------------------------------------------------------------------
text(30, 42, "Istio in one picture: which resource acts where", 28, INK, True)
text(30, 74, "The lab's request path. Grey: your pods. Blue: proxies. Coloured notes: the resources you write, grouped by the proxy that enforces them.", 15, "#57606a")

# ---- cluster frame ----------------------------------------------------------
box("cluster", 190, 100, 1240, ("#8c959f", "#ffffff"), "", dashed=True, h=960)
text(205, 126, "Kubernetes cluster", 15, "#57606a", True)

# ---- control plane ---------------------------------------------------------
box("istiod", 520, 120, 520, CTRL, "istiod (control plane)",
    ["turns your resources into proxy config and sends it over xDS; signs every workload's mTLS certificate (SPIFFE ID)"])
box("telemetry", 1070, 120, 340, OBS, "Telemetry",
    ["where proxies send traces (Jaeger), access logs and metrics settings"])

# ---- request path ----------------------------------------------------------
box("client", 20, 320, 150, EXT, "Browser or curl", ["outside the cluster, sends HTTP or HTTPS"])
box("ingress", 220, 310, 210, PROXY, "Ingress gateway", ["Envoy in shop-ingress; traffic entering the cluster (north-south)"])
box("frontend", 500, 330, 160, GREY, "frontend pod", ["no sidecar (ambient)"])
box("waypoint", 730, 300, 240, PROXY, "Waypoint", ["Envoy in front of the backend; reads HTTP (L7); traffic between services (east-west)"])
box("v1", 1040, 290, 160, GREY, "backend v1", ["2 pods, version: v1"])
box("v2", 1040, 400, 160, GREY, "backend v2", ["1 pod, version: v2"])
box("redis", 1260, 340, 150, GREY, "redis pod", ["only the backend"])
box("ztunnel", 470, 500, 940, PROXY, "ztunnel (one per node)",
    ["every hop between mesh pods passes through it: mTLS tunnel (HBONE, port 15008), L4 checks, never reads HTTP"])
box("external", 1460, 270, 150, EXT, "httpbin.org", ["outside the cluster"])

arrow([(170, 365), (220, 365)], INK)
arrow([(430, 365), (500, 365)], INK)
arrow([(660, 365), (730, 365)], INK)
arrow([(970, 330), (1040, 322)], INK, "90%", at=(990, 312))
arrow([(970, 400), (1040, 432)], INK, "10%", at=(990, 440))
arrow([(1200, 322), (1260, 365)], INK)
arrow([(950, 300), (950, 255), (1535, 255), (1535, 270)], EXT[0], "egress (module 12)", dashed=True, at=(1180, 248))
arrow([(600, 197), (330, 310)], CTRL[0], dashed=True)
arrow([(850, 197), (850, 300)], CTRL[0], dashed=True)
arrow([(1010, 197), (1010, 230), (1300, 230), (1300, 500)], CTRL[0], dashed=True)
text(440, 240, "xDS config and certificates", 14, CTRL[0])

# ---- resource notes, by enforcement point ----------------------------------
notes(210, 600, 270, "At the ingress gateway", [
    (TRAFFIC, "Gateway", "opens ports 8080 and 8443 and holds the TLS certificate (module 11)"),
    (TRAFFIC, "HTTPRoute", "path / goes to the frontend; the Istio API uses Gateway + VirtualService instead"),
    (SECURITY, "RequestAuthentication", "checks end-user tokens, JWT (module 13)"),
    (SECURITY, "AuthorizationPolicy", "a valid token is required for /api/* (module 13)"),
])
notes(510, 600, 300, "At the waypoint", [
    (TRAFFIC, "HTTPRoute or VirtualService", "WHERE a request goes: 90% v1 and 10% v2, by path or header; timeouts, retries, faults (modules 4, 5)"),
    (TRAFFIC, "DestinationRule", "HOW to talk to it: connection pool, eject failing pods, subsets, TLS (modules 5, 12)"),
    (SECURITY, "AuthorizationPolicy (L7)", "only sa/frontend may call GET or POST /api/* (module 3)"),
])
notes(840, 600, 290, "At ztunnel", [
    (SECURITY, "PeerAuthentication", "STRICT: accept mTLS only, no plain text (module 2)"),
    (SECURITY, "AuthorizationPolicy (L4)", "only the waypoint may open connections to the backend (module 3)"),
])
notes(1160, 600, 250, "For traffic leaving the mesh", [
    (TRAFFIC, "ServiceEntry", "puts httpbin.org in the mesh's registry, so routes, rules and metrics apply (module 12)"),
])

# ---- legend -----------------------------------------------------------------
lx, ly = 1460, 420
text(lx, ly, "Legend", 15, INK, True)
for n, (col, label) in enumerate([(PROXY, "proxy"), (GREY, "your pod"), (TRAFFIC, "traffic resource"),
                                  (SECURITY, "security resource"), (OBS, "observability"), (CTRL, "control plane"), (EXT, "outside")]):
    box(f"leg{n}", lx, ly + 16 + n * 36, 26, col, "", [], h=26)
    text(lx + 36, ly + 35 + n * 36, label, 14)

# ---- SVG ------------------------------------------------------------------
FONT = "Segoe UI, Helvetica, Arial, sans-serif"


def svg():
    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" font-family="{FONT}">',
         '<defs>']
    cols = {c for _, c, _, _, _ in arrows}
    for c in cols:
        cid = c.strip("#")
        o.append(f'<marker id="a{cid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
    o.append('</defs>')
    o.append(f'<rect width="{W}" height="{H}" fill="#ffffff"/>')
    for i, x, y, w, h, (stroke, fill), title, lines, dashed in boxes:
        dash = ' stroke-dasharray="8 6"' if dashed else ""
        o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill}" stroke="{stroke}" stroke-width="2"{dash}/>')
        if title:
            o.append(f'<text x="{x + 12}" y="{y + 24}" font-size="16" font-weight="700" fill="{INK}">{escape(title)}</text>')
        for n, line in enumerate(lines):
            o.append(f'<text x="{x + 12}" y="{y + 46 + n * 19}" font-size="14" fill="#57606a">{escape(line)}</text>')
    for pts, col, label, dashed, at in arrows:
        d = " ".join(f"{px},{py}" for px, py in pts)
        dash = ' stroke-dasharray="6 5"' if dashed else ""
        o.append(f'<polyline points="{d}" fill="none" stroke="{col}" stroke-width="2"{dash} marker-end="url(#a{col.strip("#")})"/>')
        if label:
            lx, ly = at or ((pts[0][0] + pts[1][0]) / 2 + 4, (pts[0][1] + pts[1][1]) / 2 - 8)
            o.append(f'<text x="{lx}" y="{ly}" font-size="13" fill="{col}">{escape(label)}</text>')
    for x, y, t, size, col, bold in texts:
        weight = ' font-weight="700"' if bold else ""
        o.append(f'<text x="{x}" y="{y}" font-size="{size}"{weight} fill="{col}">{escape(t)}</text>')
    o.append('</svg>')
    return "\n".join(o) + "\n"


# ---- Excalidraw ------------------------------------------------------------
def excalidraw():
    els, seed = [], [1]

    def base(kind, x, y, w, h, stroke, fill="transparent", dashed=False):
        seed[0] += 1
        return {"id": f"x{seed[0]}", "type": kind, "x": x, "y": y, "width": w, "height": h, "angle": 0,
                "strokeColor": stroke, "backgroundColor": fill, "fillStyle": "solid", "strokeWidth": 2,
                "strokeStyle": "dashed" if dashed else "solid", "roughness": 1, "opacity": 100, "groupIds": [],
                "frameId": None, "roundness": None, "seed": 1000 + seed[0], "version": 1, "versionNonce": 2000 + seed[0],
                "isDeleted": False, "boundElements": None, "updated": 1, "link": None, "locked": False}

    def txt(x, y, t, size, col):
        e = base("text", x, y, max(10, int(len(t) * size * 0.55)), int(size * 1.25), col)
        e.update({"strokeWidth": 1, "text": t, "fontSize": size, "fontFamily": 1, "textAlign": "left",
                  "verticalAlign": "top", "baseline": size, "containerId": None, "originalText": t,
                  "lineHeight": 1.25, "autoResize": True})
        return e

    for i, x, y, w, h, (stroke, fill), title, lines, dashed in boxes:
        r = base("rectangle", x, y, w, h, stroke, fill, dashed)
        r["roundness"] = {"type": 3}
        els.append(r)
        if title:
            els.append(txt(x + 12, y + 8, title, 16, INK))
        for n, line in enumerate(lines):
            els.append(txt(x + 12, y + 32 + n * 19, line, 14, "#57606a"))
    for pts, col, label, dashed, at in arrows:
        x0, y0 = pts[0]
        a = base("arrow", x0, y0, max(abs(p[0] - x0) for p in pts), max(abs(p[1] - y0) for p in pts), col, dashed=dashed)
        a.update({"points": [[px - x0, py - y0] for px, py in pts], "lastCommittedPoint": None,
                  "startBinding": None, "endBinding": None, "startArrowhead": None, "endArrowhead": "arrow"})
        els.append(a)
        if label:
            lx, ly = at or ((pts[0][0] + pts[1][0]) / 2 + 4, (pts[0][1] + pts[1][1]) / 2 - 8)
            els.append(txt(lx, ly - 14, label, 13, col))
    for x, y, t, size, col, bold in texts:
        els.append(txt(x, y - size, t, size, col))
    return {"type": "excalidraw", "version": 2, "source": "k8s_lab_macos course", "elements": els,
            "appState": {"gridSize": None, "viewBackgroundColor": "#ffffff"}, "files": {}}


(OUT / "istio-resources.svg").write_text(svg())
(OUT / "istio-resources.excalidraw").write_text(json.dumps(excalidraw(), indent=1) + "\n")
print("wrote istio-resources.svg and istio-resources.excalidraw")
