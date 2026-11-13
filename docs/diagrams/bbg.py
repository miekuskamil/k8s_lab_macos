"""A small drawing kit for step diagrams in the style of the ByteByteGo newsletter.

Dark background, big boxes with an icon and two or three words, short verb labels on
the arrows, circled step numbers that match the numbered steps in the text, dashed
groups around related parts. One description writes two files: <name>.svg for GitHub
and <name>.excalidraw to open and edit at https://excalidraw.com.

Everything is built from five primitives (rect, ellipse, line, poly, text), so both
outputs draw the same picture.
"""
import json
from html import escape
from pathlib import Path

BG = "#1e1f24"
INK = "#f5f5f7"
SOFT = "#c9cbd3"
DIM = "#8b8f9c"
LINE = "#d0d3dc"
STEP = "#fbbf24"          # step circles

BLUE = "#1677ff"
GREEN = "#0ea47a"
PURPLE = "#7c3aed"
PINK = "#db2777"
ORANGE = "#ea7a17"
RED = "#e5484d"
TEAL = "#0e9fb3"
SLATE = "#475069"

FONT = "Inter, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"


def text_width(t, size, bold=False):
    if size >= 30:
        return len(t) * size * (0.53 if bold else 0.5)
    return len(t) * size * (0.58 if bold else 0.54)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.items = []

    # ---- primitives ----------------------------------------------------------------
    def rect(self, x, y, w, h, stroke, fill="none", rx=14, sw=2.5, dashed=False):
        self.items.append(("rect", x, y, w, h, stroke, fill, rx, sw, dashed))

    def ellipse(self, cx, cy, rx, ry, stroke, fill="none", sw=2.5):
        self.items.append(("ellipse", cx, cy, rx, ry, stroke, fill, sw))

    def line(self, pts, stroke=LINE, sw=2.5, dashed=False, head=False):
        self.items.append(("line", pts, stroke, sw, dashed, head))

    def poly(self, pts, stroke, fill):
        self.items.append(("poly", pts, stroke, fill))

    def text(self, x, y, t, size=18, color=INK, bold=False, anchor="start"):
        self.items.append(("text", x, y, t, size, color, bold, anchor))

    # ---- icons, about 44 x 44, top-left at (x, y) ----------------------------------
    def icon(self, kind, x, y, col=INK):
        if kind == "person":
            self.ellipse(x + 22, y + 12, 10, 10, col, col)
            self.rect(x + 6, y + 25, 32, 19, col, col, rx=10)
        elif kind == "doc":
            self.poly([(x + 8, y + 2), (x + 28, y + 2), (x + 38, y + 12), (x + 38, y + 42), (x + 8, y + 42)], col, "none")
            self.line([(x + 15, y + 20), (x + 31, y + 20)], col, 2.5)
            self.line([(x + 15, y + 28), (x + 31, y + 28)], col, 2.5)
            self.line([(x + 15, y + 36), (x + 26, y + 36)], col, 2.5)
        elif kind == "server":
            for i in range(3):
                self.rect(x + 3, y + 2 + i * 14, 38, 11, col, "none", rx=3, sw=2.2)
                self.ellipse(x + 10, y + 7.5 + i * 14, 2, 2, col, col, sw=1)
        elif kind == "db":
            self.rect(x + 6, y + 8, 32, 30, col, "none", rx=2, sw=2.2)
            self.ellipse(x + 22, y + 8, 16, 6, col, BG, sw=2.2)
            self.line([(x + 6, y + 23), (x + 38, y + 23)], col, 2.2)
        elif kind == "lock":
            self.rect(x + 8, y + 20, 28, 22, col, col, rx=4)
            self.rect(x + 13, y + 4, 18, 24, col, "none", rx=9, sw=3)
            self.ellipse(x + 22, y + 31, 3, 3, BG, BG, sw=1)
        elif kind == "shield":
            self.poly([(x + 22, y + 2), (x + 40, y + 9), (x + 37, y + 30), (x + 22, y + 43), (x + 7, y + 30), (x + 4, y + 9)], col, "none")
            self.line([(x + 14, y + 22), (x + 20, y + 29), (x + 31, y + 16)], col, 3)
        elif kind == "cube":
            self.poly([(x + 22, y + 2), (x + 40, y + 12), (x + 22, y + 22), (x + 4, y + 12)], col, "none")
            self.poly([(x + 4, y + 12), (x + 22, y + 22), (x + 22, y + 43), (x + 4, y + 33)], col, "none")
            self.poly([(x + 40, y + 12), (x + 22, y + 22), (x + 22, y + 43), (x + 40, y + 33)], col, "none")
        elif kind == "laptop":
            self.rect(x + 7, y + 6, 30, 22, col, "none", rx=3)
            self.rect(x + 1, y + 32, 42, 6, col, col, rx=3)
        elif kind == "gear":
            self.ellipse(x + 22, y + 22, 16, 16, col, "none", sw=3)
            self.ellipse(x + 22, y + 22, 6, 6, col, col, sw=1)
            for a, b in [((22, 1), (22, 8)), ((22, 36), (22, 43)), ((1, 22), (8, 22)), ((36, 22), (43, 22))]:
                self.line([(x + a[0], y + a[1]), (x + b[0], y + b[1])], col, 4)
        elif kind == "globe":
            self.ellipse(x + 22, y + 22, 19, 19, col, "none")
            self.ellipse(x + 22, y + 22, 8, 19, col, "none", sw=2)
            self.line([(x + 3, y + 22), (x + 41, y + 22)], col, 2)
        elif kind == "eye":
            self.ellipse(x + 22, y + 22, 20, 11, col, "none")
            self.ellipse(x + 22, y + 22, 6, 6, col, col, sw=1)
        elif kind == "tunnel":
            self.ellipse(x + 10, y + 22, 7, 16, col, "none")
            self.line([(x + 10, y + 6), (x + 36, y + 6)], col)
            self.line([(x + 10, y + 38), (x + 36, y + 38)], col)
            self.ellipse(x + 36, y + 22, 7, 16, col, col, sw=1)
        elif kind == "dns":
            self.ellipse(x + 22, y + 22, 19, 19, col, "none")
            self.text(x + 22, y + 29, "?", 22, col, True, "middle")

    # ---- building blocks ----------------------------------------------------------
    def title(self, text, highlight=""):
        self.rect(28, 30, 8, 46, GREEN, GREEN, rx=2, sw=1)
        self.text(52, 68, text, 38, INK, True)
        if highlight:
            x = 52 + text_width(text + " ", 38, True)
            w = text_width(highlight, 38, True) + 28
            self.rect(x, 26, w, 54, PURPLE, PURPLE, rx=10, sw=1)
            self.text(x + 14, 68, highlight, 38, INK, True)

    def subtitle(self, text):
        self.text(52, 108, text, 19, SOFT)

    def node(self, x, y, w, h, col, label, icon=None, sub=None, size=24):
        """A filled box: icon on the left, one or two words, optional small line."""
        self.rect(x, y + 6, w, h, col, col, rx=16, sw=1)              # shadow edge
        self.rect(x, y, w, h, col, col, rx=16, sw=1)
        self.rect(x, y + h - 2, w, 8, "#00000033", "#00000033", rx=4, sw=0)
        tx = x + 22
        if icon:
            self.icon(icon, x + 18, y + h / 2 - 22, INK)
            tx = x + 78
        lines = label.split("\n")
        n = len(lines) + (1 if sub else 0)
        top = y + h / 2 - (n * (size + 6)) / 2 + size - 2
        for i, line in enumerate(lines):
            self.text(tx, top + i * (size + 6), line, size, INK, True)
        if sub:
            self.text(tx, top + len(lines) * (size + 6) - 2, sub, 16, "#ffffffcc")

    def outline(self, x, y, w, h, col, label, icon=None, size=19):
        """A dark box with a coloured border, for smaller parts."""
        self.rect(x, y, w, h, col, "#2a2b33", rx=12, sw=2.5)
        tx = x + 16
        if icon:
            self.icon(icon, x + 12, y + h / 2 - 22, col)
            tx = x + 66
        lines = label.split("\n")
        top = y + h / 2 - (len(lines) * (size + 5)) / 2 + size - 3
        for i, line in enumerate(lines):
            self.text(tx, top + i * (size + 5), line, size, INK, True)

    def group(self, x, y, w, h, label="", col=DIM):
        self.rect(x, y, w, h, col, "#00000000", rx=18, sw=2.5, dashed=True)
        if label:
            self.text(x + w / 2, y - 12, label, 19, SOFT, True, "middle")

    def step(self, cx, cy, n):
        self.ellipse(cx, cy, 17, 17, STEP, STEP, sw=1)
        self.text(cx, cy + 7, str(n), 19, "#1e1f24", True, "middle")

    def arrow(self, pts, label="", n=None, at=None, dashed=True, col=LINE, pos="right"):
        """A line with an arrowhead. n puts a circled step number at `at` (default: the
        middle of the first segment). The label goes right, left, above or below it.
        A label may hold two lines, split with a newline."""
        self.line(pts, col, 2.5, dashed, head=True)
        (x0, y0), (x1, y1) = pts[0], pts[1]
        cx, cy = at or ((x0 + x1) / 2, (y0 + y1) / 2)
        r = 17 if n is not None else 0
        if n is not None:
            self.step(cx, cy, n)
        if not label:
            return
        lines = label.split("\n")
        size, gap = 18, 23
        colr = INK if n is not None else SOFT
        if pos == "right":
            for i, t in enumerate(lines):
                self.text(cx + r + 10, cy + 6 + (i - (len(lines) - 1) / 2) * gap, t, size, colr, True)
        elif pos == "left":
            for i, t in enumerate(lines):
                self.text(cx - r - 10, cy + 6 + (i - (len(lines) - 1) / 2) * gap, t, size, colr, True, "end")
        elif pos == "above":
            for i, t in enumerate(lines):
                self.text(cx, cy - r - 12 - (len(lines) - 1 - i) * gap, t, size, colr, True, "middle")
        else:
            for i, t in enumerate(lines):
                self.text(cx, cy + r + 26 + i * gap, t, size, colr, True, "middle")

    def note(self, x, y, lines, size=16, col=SOFT):
        for i, t in enumerate(lines):
            self.text(x, y + i * (size + 7), t, size, col)

    # ---- output -------------------------------------------------------------------
    def svg(self):
        o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
             f'viewBox="0 0 {self.w} {self.h}" font-family="{FONT}">',
             f'<rect width="{self.w}" height="{self.h}" fill="{BG}"/>',
             '<defs><marker id="h" markerWidth="12" markerHeight="10" refX="10" refY="5" orient="auto" '
             f'markerUnits="userSpaceOnUse"><path d="M0,0 L12,5 L0,10 z" fill="{LINE}"/></marker></defs>']
        for it in self.items:
            k = it[0]
            if k == "rect":
                _, x, y, w, h, s, f, rx, sw, d = it
                dash = ' stroke-dasharray="9 7"' if d else ""
                o.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}" fill="{f}" '
                         f'stroke="{s}" stroke-width="{sw}"{dash}/>')
            elif k == "ellipse":
                _, cx, cy, rx, ry, s, f, sw = it
                o.append(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx}" ry="{ry}" fill="{f}" stroke="{s}" stroke-width="{sw}"/>')
            elif k == "line":
                _, pts, s, sw, d, head = it
                dash = ' stroke-dasharray="9 7"' if d else ""
                mk = ' marker-end="url(#h)"' if head else ""
                p = " ".join(f"{a:.1f},{b:.1f}" for a, b in pts)
                o.append(f'<polyline points="{p}" fill="none" stroke="{s}" stroke-width="{sw}" '
                         f'stroke-linecap="round" stroke-linejoin="round"{dash}{mk}/>')
            elif k == "poly":
                _, pts, s, f = it
                p = " ".join(f"{a:.1f},{b:.1f}" for a, b in pts)
                o.append(f'<polygon points="{p}" fill="{f}" stroke="{s}" stroke-width="2.5" stroke-linejoin="round"/>')
            elif k == "text":
                _, x, y, t, size, c, b, anchor = it
                wgt = ' font-weight="700"' if b else ""
                o.append(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size}" fill="{c}"{wgt} '
                         f'text-anchor="{anchor}">{escape(t)}</text>')
        o.append("</svg>")
        return "\n".join(o) + "\n"

    def excalidraw(self):
        els, n = [], [0]

        def colour(c):
            if c in ("none",) or (c.startswith("#") and len(c) == 9):
                return "transparent"
            return c

        def base(kind, x, y, w, h, stroke, fill="transparent", sw=2, dashed=False):
            n[0] += 1
            return {"id": f"e{n[0]}", "type": kind, "x": x, "y": y, "width": w, "height": h, "angle": 0,
                    "strokeColor": colour(stroke), "backgroundColor": colour(fill), "fillStyle": "solid",
                    "strokeWidth": max(1, round(sw)), "strokeStyle": "dashed" if dashed else "solid",
                    "roughness": 0, "opacity": 100, "groupIds": [], "frameId": None, "roundness": None,
                    "seed": 100 + n[0], "version": 1, "versionNonce": 200 + n[0], "isDeleted": False,
                    "boundElements": None, "updated": 1, "link": None, "locked": False}

        els.append(base("rectangle", 0, 0, self.w, self.h, BG, BG, 1))
        for it in self.items:
            k = it[0]
            if k == "rect":
                _, x, y, w, h, s, f, rx, sw, d = it
                if colour(s) == "transparent" and colour(f) == "transparent":
                    continue
                e = base("rectangle", x, y, w, h, s if colour(s) != "transparent" else f, f, sw, d)
                if rx:
                    e["roundness"] = {"type": 3}
                els.append(e)
            elif k == "ellipse":
                _, cx, cy, rx, ry, s, f, sw = it
                els.append(base("ellipse", cx - rx, cy - ry, 2 * rx, 2 * ry, s, f, sw))
            elif k in ("line", "poly"):
                pts = it[1]
                x0, y0 = pts[0]
                closed = k == "poly"
                if closed:
                    pts = list(pts) + [pts[0]]
                xs = [p[0] - x0 for p in pts]
                ys = [p[1] - y0 for p in pts]
                if k == "line":
                    _, _, s, sw, d, head = it
                    e = base("arrow" if head else "line", x0, y0, max(xs) - min(xs), max(ys) - min(ys), s, "transparent", sw, d)
                    e.update({"startArrowhead": None, "endArrowhead": "arrow" if head else None})
                else:
                    _, _, s, f = it
                    e = base("line", x0, y0, max(xs) - min(xs), max(ys) - min(ys), s, f, 2)
                    e.update({"startArrowhead": None, "endArrowhead": None})
                e.update({"points": [[a, b] for a, b in zip(xs, ys)], "lastCommittedPoint": None,
                          "startBinding": None, "endBinding": None})
                els.append(e)
            elif k == "text":
                _, x, y, t, size, c, b, anchor = it
                w = text_width(t, size, b)
                left = x - w / 2 if anchor == "middle" else (x - w if anchor == "end" else x)
                e = base("text", left, y - size, w, size * 1.25, c, "transparent", 1)
                e.update({"text": t, "originalText": t, "fontSize": size, "fontFamily": 2,
                          "textAlign": {"start": "left", "middle": "center", "end": "right"}[anchor],
                          "verticalAlign": "top", "baseline": size, "containerId": None,
                          "lineHeight": 1.25, "autoResize": True})
                els.append(e)
        return {"type": "excalidraw", "version": 2, "source": "k8s_lab_macos course", "elements": els,
                "appState": {"gridSize": None, "viewBackgroundColor": BG}, "files": {}}

    def save(self, folder, name):
        folder = Path(folder)
        (folder / f"{name}.svg").write_text(self.svg())
        (folder / f"{name}.excalidraw").write_text(json.dumps(self.excalidraw(), indent=1) + "\n")
        print(f"wrote {name}.svg and {name}.excalidraw")
