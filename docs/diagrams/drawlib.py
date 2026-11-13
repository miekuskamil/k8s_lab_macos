"""Tiny drawing helper: describe boxes, arrows and text once, write SVG and Excalidraw.

Used by make-life-of-a-request.py. Each diagram builds a Canvas, calls box(), arrow()
and text(), then save() writes <name>.svg (shown on GitHub) and <name>.excalidraw
(open and edit at https://excalidraw.com). Both files come from the same description,
so they always match.
"""
import json
from html import escape
from pathlib import Path

INK = "#24292f"
MUTED = "#57606a"

# Colours: (stroke, fill)
GREY = ("#57606a", "#f6f8fa")      # pods, apps, plain components
PROXY = ("#0969da", "#ddf4ff")     # Envoy and ztunnel
CTRL = ("#8250df", "#fbefff")      # control plane
SEC = ("#cf222e", "#ffebe9")       # security decisions
NET = ("#1a7f37", "#dafbe1")       # kernel networking: iptables, bridges, routes
EXT = ("#9a6700", "#fff8c5")       # outside the cluster
STORE = ("#bc4c00", "#fff1e5")     # storage
FRAME = ("#8c959f", "#ffffff")


class Canvas:
    CHAR = 7.3  # rough width of one 14 px character

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.boxes, self.arrows, self.texts = [], [], []

    def wrap(self, line, width):
        out, cur = [], ""
        for word in line.split():
            if cur and (len(cur) + 1 + len(word)) * self.CHAR > width:
                out.append(cur)
                cur = word
            else:
                cur = f"{cur} {word}".strip()
        return out + ([cur] if cur else [])

    def box(self, x, y, w, col, title, lines=(), dashed=False, h=None):
        """Draw a box; return its bottom y."""
        wrapped = [part for line in lines for part in self.wrap(line, w - 24)]
        height = h or (36 + 19 * len(wrapped) + (8 if wrapped else 0))
        self.boxes.append((x, y, w, height, col, title, wrapped, dashed))
        return y + height

    def arrow(self, points, col=INK, label="", dashed=False, at=None):
        self.arrows.append((points, col, label, dashed, at))

    def text(self, x, y, t, size=16, col=INK, bold=False):
        self.texts.append((x, y, t, size, col, bold))

    # ---- SVG -----------------------------------------------------------------
    def svg(self):
        o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
             f'viewBox="0 0 {self.w} {self.h}" font-family="-apple-system, Segoe UI, Helvetica, Arial, sans-serif">',
             f'<rect width="{self.w}" height="{self.h}" fill="#ffffff"/>', "<defs>"]
        for col in sorted({a[1] for a in self.arrows}):
            o.append(f'<marker id="a{col.strip("#")}" markerWidth="10" markerHeight="8" refX="9" refY="4" '
                     f'orient="auto"><path d="M0,0 L10,4 L0,8 z" fill="{col}"/></marker>')
        o.append("</defs>")
        for x, y, w, h, (stroke, fill), title, lines, dashed in self.boxes:
            dash = ' stroke-dasharray="7 5"' if dashed else ""
            o.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{fill}" stroke="{stroke}" stroke-width="2"{dash}/>')
            if title:
                o.append(f'<text x="{x + 12}" y="{y + 24}" font-size="16" font-weight="700" fill="{INK}">{escape(title)}</text>')
            for n, line in enumerate(lines):
                o.append(f'<text x="{x + 12}" y="{y + 46 + n * 19}" font-size="14" fill="{MUTED}">{escape(line)}</text>')
        for pts, col, label, dashed, at in self.arrows:
            d = " ".join(f"{px},{py}" for px, py in pts)
            dash = ' stroke-dasharray="6 5"' if dashed else ""
            o.append(f'<polyline points="{d}" fill="none" stroke="{col}" stroke-width="2"{dash} marker-end="url(#a{col.strip("#")})"/>')
            if label:
                lx, ly = at or ((pts[0][0] + pts[1][0]) / 2 + 6, (pts[0][1] + pts[1][1]) / 2 - 6)
                o.append(f'<text x="{lx}" y="{ly}" font-size="13" font-weight="600" fill="{col}">{escape(label)}</text>')
        for x, y, t, size, col, bold in self.texts:
            weight = ' font-weight="700"' if bold else ""
            o.append(f'<text x="{x}" y="{y}" font-size="{size}"{weight} fill="{col}">{escape(t)}</text>')
        o.append("</svg>")
        return "\n".join(o) + "\n"

    # ---- Excalidraw ------------------------------------------------------------
    def excalidraw(self):
        els, seed = [], [1]

        def base(kind, x, y, w, h, stroke, fill="transparent", dashed=False):
            seed[0] += 1
            return {"id": f"x{seed[0]}", "type": kind, "x": x, "y": y, "width": w, "height": h, "angle": 0,
                    "strokeColor": stroke, "backgroundColor": fill, "fillStyle": "solid", "strokeWidth": 2,
                    "strokeStyle": "dashed" if dashed else "solid", "roughness": 1, "opacity": 100,
                    "groupIds": [], "frameId": None, "roundness": None, "seed": 1000 + seed[0], "version": 1,
                    "versionNonce": 2000 + seed[0], "isDeleted": False, "boundElements": None, "updated": 1,
                    "link": None, "locked": False}

        def txt(x, y, t, size, col):
            e = base("text", x, y, max(10, int(len(t) * size * 0.55)), int(size * 1.25), col)
            e.update({"strokeWidth": 1, "text": t, "fontSize": size, "fontFamily": 1, "textAlign": "left",
                      "verticalAlign": "top", "baseline": size, "containerId": None, "originalText": t,
                      "lineHeight": 1.25, "autoResize": True})
            return e

        for x, y, w, h, (stroke, fill), title, lines, dashed in self.boxes:
            r = base("rectangle", x, y, w, h, stroke, fill, dashed)
            r["roundness"] = {"type": 3}
            els.append(r)
            if title:
                els.append(txt(x + 12, y + 8, title, 16, INK))
            for n, line in enumerate(lines):
                els.append(txt(x + 12, y + 32 + n * 19, line, 14, MUTED))
        for pts, col, label, dashed, at in self.arrows:
            x0, y0 = pts[0]
            a = base("arrow", x0, y0, max(abs(p[0] - x0) for p in pts), max(abs(p[1] - y0) for p in pts),
                     col, dashed=dashed)
            a.update({"points": [[px - x0, py - y0] for px, py in pts], "lastCommittedPoint": None,
                      "startBinding": None, "endBinding": None, "startArrowhead": None, "endArrowhead": "arrow"})
            els.append(a)
            if label:
                lx, ly = at or ((pts[0][0] + pts[1][0]) / 2 + 6, (pts[0][1] + pts[1][1]) / 2 - 6)
                els.append(txt(lx, ly - 14, label, 13, col))
        for x, y, t, size, col, bold in self.texts:
            els.append(txt(x, y - size, t, size, col))
        return {"type": "excalidraw", "version": 2, "source": "k8s_lab_macos course", "elements": els,
                "appState": {"gridSize": None, "viewBackgroundColor": "#ffffff"}, "files": {}}

    def save(self, folder, name):
        folder = Path(folder)
        (folder / f"{name}.svg").write_text(self.svg())
        (folder / f"{name}.excalidraw").write_text(json.dumps(self.excalidraw(), indent=1) + "\n")
        print(f"wrote {name}.svg and {name}.excalidraw")
