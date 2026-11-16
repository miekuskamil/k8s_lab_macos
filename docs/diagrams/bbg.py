"""A small drawing kit for the course diagrams, in a light ByteByteGo style.

The diagrams sit on a white page (GitHub and the PDF), so the kit draws on white with
soft pastel fills, one strong accent colour per kind of thing, thin strokes and rounded
corners. A diagram shows structure first (cluster, node, namespace, pod, container,
kernel) with nested frames, then draws the flow on top with numbered step circles that
match the numbered steps in the text.

One description writes two files: <name>.svg for GitHub and <name>.excalidraw to open
and edit at https://excalidraw.com. Everything is built from five primitives (rect,
ellipse, line, poly, text), so both outputs draw the same picture.

Colours mean kinds of things, the same in every diagram:
  SLATE apps and clients     BLUE proxies (Envoy, ztunnel, waypoint, gateways)
  PURPLE control plane       GREEN kernel and networking
  ORANGE storage             RED security decisions (PINK for admission and crypto)
  TEAL node agents and DNS

The building blocks return a Box, and connect() draws an arrow between two boxes that
starts and ends exactly on their edges, running straight or with right-angle elbows.
"""
import json
from html import escape
from pathlib import Path

# ---- page and ink ---------------------------------------------------------------------
BG = "#ffffff"
INK = "#0f172a"          # titles and box labels
SOFT = "#475569"         # sub-lines and arrow labels
DIM = "#94a3b8"          # frames and quiet notes
LINE = "#475569"         # default arrow colour
FAINT = "#cbd5e1"        # frame strokes
STEP = "#f59e0b"         # step circles
STEP_INK = "#1f2937"
WHITE = "#ffffff"

# ---- accents (one per kind of thing) ---------------------------------------------------
BLUE = "#2563eb"
GREEN = "#059669"
PURPLE = "#7c3aed"
PINK = "#db2777"
ORANGE = "#ea580c"
RED = "#dc2626"
TEAL = "#0891b2"
SLATE = "#475569"

PASTEL = {BLUE: "#eaf1ff", GREEN: "#e7f7f0", PURPLE: "#f2edff", PINK: "#fdecf4",
          ORANGE: "#fff2e8", RED: "#fdeeee", TEAL: "#e6f6fa", SLATE: "#f1f4f8"}
DEEP = {BLUE: "#1e40af", GREEN: "#047857", PURPLE: "#5b21b6", PINK: "#9d174d",
        ORANGE: "#9a3412", RED: "#991b1b", TEAL: "#155e75", SLATE: "#334155"}

FONT = "Inter, -apple-system, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "'SF Mono', Menlo, Consolas, monospace"

SW = 1.8                 # stroke width for boxes
AW = 2.2                 # stroke width for arrows


def pastel(col):
    return PASTEL.get(col, "#f8fafc")


def deep(col):
    return DEEP.get(col, INK)


def text_width(t, size, bold=False):
    """A rough width for Inter / Helvetica, good enough for layout."""
    w = 0.0
    for ch in t:
        if ch in "il.,:;'|!·":
            w += 0.28
        elif ch in "fjrt()[]{}/ -":
            w += 0.36
        elif ch in "mwMW@%":
            w += 0.86
        elif ch.isupper() or ch.isdigit():
            w += 0.64
        else:
            w += 0.55
    return w * size * (1.03 if bold else 1.0)


class Box:
    """A rectangle with edge anchors. f is a fraction along the edge (0 to 1)."""

    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h

    @property
    def cx(self):
        return self.x + self.w / 2

    @property
    def cy(self):
        return self.y + self.h / 2

    @property
    def r(self):
        return self.x + self.w

    @property
    def b(self):
        return self.y + self.h

    def top(self, f=0.5):
        return (self.x + self.w * f, self.y)

    def bottom(self, f=0.5):
        return (self.x + self.w * f, self.y + self.h)

    def left(self, f=0.5):
        return (self.x, self.y + self.h * f)

    def right(self, f=0.5):
        return (self.x + self.w, self.y + self.h * f)

    def at(self, side, f=0.5):
        return {"top": self.top, "bottom": self.bottom, "left": self.left, "right": self.right}[side](f)


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.items = []

    # ---- primitives ----------------------------------------------------------------
    def rect(self, x, y, w, h, stroke, fill="none", rx=12, sw=SW, dashed=False):
        self.items.append(("rect", x, y, w, h, stroke, fill, rx, sw, dashed))
        return Box(x, y, w, h)

    def ellipse(self, cx, cy, rx, ry, stroke, fill="none", sw=SW):
        self.items.append(("ellipse", cx, cy, rx, ry, stroke, fill, sw))

    def line(self, pts, stroke=LINE, sw=AW, dashed=False, head=False, tail=False):
        self.items.append(("line", [tuple(p) for p in pts], stroke, sw, dashed, head, tail))

    def poly(self, pts, stroke, fill, sw=SW):
        self.items.append(("poly", pts, stroke, fill, sw))

    def text(self, x, y, t, size=18, color=INK, bold=False, anchor="start", halo=False, mono=False):
        self.items.append(("text", x, y, t, size, color, bold, anchor, halo, mono))

    # ---- icons: drawn in a 44 x 44 box, top-left at (x, y), scaled by s ------------
    def icon(self, kind, x, y, col=INK, s=1.0, bg=WHITE):
        def P(a, b):
            return (x + a * s, y + b * s)

        def L(pts, w=2.4, dashed=False):
            self.line([P(a, b) for a, b in pts], col, w * s, dashed)

        def R(a, b, w, h, fill="none", rx=4, sw=2.4):
            self.rect(x + a * s, y + b * s, w * s, h * s, col, fill, rx * s, sw * s)

        def E(a, b, rx, ry, fill="none", sw=2.4, stroke=None):
            self.ellipse(x + a * s, y + b * s, rx * s, ry * s, stroke or col, fill, sw * s)

        def G(pts, fill="none", sw=2.4):
            self.poly([P(a, b) for a, b in pts], col, fill, sw * s)

        if kind == "person":
            E(22, 13, 8, 8)
            self.line([P(7, 40), P(7, 34), P(12, 27), P(32, 27), P(37, 34), P(37, 40)], col, 2.4 * s)
        elif kind == "doc":
            G([(10, 3), (27, 3), (36, 12), (36, 41), (10, 41)])
            L([(27, 3), (27, 12), (36, 12)])
            for yy, x2 in ((21, 30), (28, 30), (35, 24)):
                L([(16, yy), (x2, yy)], 2.2)
        elif kind == "server":
            for i in range(3):
                R(4, 4 + i * 13, 36, 10, rx=3, sw=2.2)
                E(11, 9 + i * 13, 1.6, 1.6, col, 1)
                L([(22, 9 + i * 13), (33, 9 + i * 13)], 2)
        elif kind == "db":
            E(22, 10, 15, 6)
            L([(7, 10), (7, 34)])
            L([(37, 10), (37, 34)])
            self.line([P(7, 34), P(10, 38), P(22, 40), P(34, 38), P(37, 34)], col, 2.4 * s)
            self.line([P(7, 22), P(10, 26), P(22, 28), P(34, 26), P(37, 22)], col, 2.2 * s)
        elif kind == "lock":
            R(9, 19, 26, 21, rx=4)
            self.line([P(14, 19), P(14, 13), P(17, 7), P(22, 5), P(27, 7), P(30, 13), P(30, 19)], col, 2.4 * s)
            E(22, 29, 2.6, 2.6, col, 1)
        elif kind == "shield":
            G([(22, 3), (38, 9), (36, 27), (22, 41), (8, 27), (6, 9)])
            L([(15, 22), (20, 28), (30, 16)], 2.6)
        elif kind == "cube":
            G([(22, 4), (39, 13), (39, 32), (22, 41), (5, 32), (5, 13)])
            L([(5, 13), (22, 22), (39, 13)])
            L([(22, 22), (22, 41)])
        elif kind == "laptop":
            R(8, 8, 28, 20, rx=3)
            self.line([P(3, 36), P(41, 36)], col, 3 * s)
        elif kind == "gear":
            for a, b in [((22, 3), (22, 10)), ((22, 34), (22, 41)), ((3, 22), (10, 22)), ((34, 22), (41, 22)),
                         ((8.5, 8.5), (13.5, 13.5)), ((30.5, 30.5), (35.5, 35.5)), ((35.5, 8.5), (30.5, 13.5)),
                         ((8.5, 35.5), (13.5, 30.5))]:
                L([a, b], 3.6)
            E(22, 22, 12, 12, bg)
            E(22, 22, 4.5, 4.5)
        elif kind == "globe":
            E(22, 22, 18, 18)
            E(22, 22, 8, 18, sw=2)
            L([(4, 22), (40, 22)], 2)
        elif kind == "eye":
            self.line([P(3, 22), P(12, 13), P(22, 10), P(32, 13), P(41, 22), P(32, 31), P(22, 34), P(12, 31), P(3, 22)],
                      col, 2.4 * s)
            E(22, 22, 6, 6, col, 1)
        elif kind == "tunnel":
            E(11, 22, 6, 14)
            L([(11, 8), (33, 8)])
            L([(11, 36), (33, 36)])
            E(33, 22, 6, 14, col, 1)
        elif kind == "dns":
            E(22, 22, 18, 18)
            self.text(x + 22 * s, y + 30 * s, "?", 22 * s, col, True, "middle")
        elif kind == "key":
            E(13, 22, 8, 8)
            L([(21, 22), (40, 22)])
            L([(33, 22), (33, 29)])
            L([(39, 22), (39, 28)])
        elif kind == "chart":
            L([(5, 5), (5, 39), (40, 39)])
            self.line([P(10, 31), P(18, 22), P(25, 27), P(37, 11)], col, 2.6 * s)
        elif kind == "bell":
            self.line([P(9, 32), P(12, 27), P(12, 17), P(16, 9), P(22, 7), P(28, 9), P(32, 17), P(32, 27), P(35, 32), P(9, 32)],
                      col, 2.4 * s)
            L([(19, 37), (25, 37)])
        elif kind == "git":
            E(12, 10, 4.5, 4.5)
            E(12, 34, 4.5, 4.5)
            E(32, 18, 4.5, 4.5)
            L([(12, 14.5), (12, 29.5)])
            self.line([P(32, 22.5), P(32, 26), P(16, 31)], col, 2.4 * s)
        elif kind == "terminal":
            R(3, 6, 38, 32, rx=5)
            L([(10, 16), (16, 22), (10, 28)])
            L([(20, 29), (30, 29)])
        elif kind == "chip":
            R(10, 10, 24, 24, rx=4)
            R(17, 17, 10, 10, rx=2, sw=2)
            for v in (16, 22, 28):
                L([(v, 4), (v, 10)], 2)
                L([(v, 34), (v, 40)], 2)
                L([(4, v), (10, v)], 2)
                L([(34, v), (40, v)], 2)
        elif kind == "cloud":
            self.line([P(12, 34), P(5, 30), P(5, 23), P(10, 18), P(15, 18), P(19, 11), P(27, 9), P(33, 13), P(35, 19),
                       P(40, 22), P(40, 30), P(34, 34), P(12, 34)], col, 2.4 * s)
        elif kind == "filter":
            G([(4, 7), (40, 7), (26, 23), (26, 37), (18, 41), (18, 23)])
        elif kind == "search":
            E(19, 19, 12, 12)
            L([(28, 28), (40, 40)], 3.2)
        elif kind == "clock":
            E(22, 22, 18, 18)
            self.line([P(22, 11), P(22, 22), P(30, 27)], col, 2.6 * s)
        elif kind == "check":
            E(22, 22, 18, 18)
            L([(14, 22), (20, 28), (31, 16)], 2.8)
        elif kind == "cross":
            E(22, 22, 18, 18)
            L([(15, 15), (29, 29)], 2.8)
            L([(29, 15), (15, 29)], 2.8)
        elif kind == "sparkle":
            G([(22, 3), (26, 18), (41, 22), (26, 26), (22, 41), (18, 26), (3, 22), (18, 18)])
        elif kind == "layers":
            G([(22, 5), (40, 14), (22, 23), (4, 14)])
            self.line([P(4, 22), P(22, 31), P(40, 22)], col, 2.4 * s)
            self.line([P(4, 30), P(22, 39), P(40, 30)], col, 2.4 * s)
        elif kind == "box":
            R(5, 9, 34, 28, rx=4)
            L([(5, 17), (39, 17)])
        elif kind == "bolt":
            G([(25, 3), (8, 25), (20, 25), (17, 41), (36, 17), (24, 17)])
        elif kind == "flame":
            self.line([P(22, 41), P(11, 36), P(7, 26), P(12, 15), P(16, 21), P(20, 4), P(31, 15), P(37, 27), P(33, 36),
                       P(22, 41)], col, 2.4 * s)
        elif kind == "list":
            for yy in (11, 22, 33):
                E(8, yy, 2, 2, col, 1)
                L([(15, yy), (39, yy)])
        elif kind == "refresh":
            self.line([P(36, 14), P(30, 7), P(22, 5), P(12, 8), P(6, 16), P(5, 24)], col, 2.6 * s)
            G([(36, 5), (37, 15), (27, 14)], col, 1)
            self.line([P(8, 30), P(14, 37), P(22, 39), P(32, 36), P(38, 28), P(39, 20)], col, 2.6 * s)
            G([(8, 39), (7, 29), (17, 30)], col, 1)
        elif kind == "plug":
            R(10, 15, 24, 15, rx=5)
            L([(16, 5), (16, 15)])
            L([(28, 5), (28, 15)])
            L([(22, 30), (22, 41)])

    # ---- frames: the structure the flow runs on ------------------------------------
    FRAME = {
        "cluster": dict(stroke=FAINT, fill="#fbfcfe", rx=22, dashed=False, sw=1.6, col=SOFT, icon="globe"),
        "node": dict(stroke="#d3dae4", fill="#f5f7fa", rx=18, dashed=False, sw=1.6, col=SOFT, icon="server"),
        "ns": dict(stroke=DIM, fill="none", rx=16, dashed=True, sw=1.6, col=SOFT, icon=None),
        "pod": dict(stroke="#9aa8ba", fill=WHITE, rx=14, dashed=False, sw=1.6, col=SLATE, icon="cube"),
        "group": dict(stroke=DIM, fill="none", rx=16, dashed=True, sw=1.6, col=SOFT, icon=None),
        "host": dict(stroke=FAINT, fill="#fbfcfe", rx=22, dashed=False, sw=1.6, col=SOFT, icon="laptop"),
        "plain": dict(stroke=FAINT, fill=WHITE, rx=16, dashed=False, sw=1.6, col=SOFT, icon=None),
    }

    def frame(self, x, y, w, h, label="", kind="group", col=None, fill=None, icon=None, size=18, right=""):
        """A container: cluster, node, ns (namespace), pod, group, host or plain.
        A coloured frame (col=...) uses that accent's pastel. The label sits inside, top-left."""
        st = dict(self.FRAME[kind])
        if col:
            st.update(stroke=col, fill=pastel(col) if fill is None else fill, col=deep(col))
        elif fill is not None:
            st["fill"] = fill
        self.rect(x, y, w, h, st["stroke"], st["fill"], st["rx"], st["sw"], st["dashed"])
        ic = st["icon"] if icon is None else icon
        tx = x + 18
        if label:
            if ic:
                self.icon(ic, x + 16, y + 13, st["col"], s=0.5)
                tx = x + 46
            self.text(tx, y + 30, label, size, st["col"], True)
        if right:
            self.text(x + w - 18, y + 30, right, size - 1, st["col"], False, "end")
        return Box(x, y, w, h)

    def band(self, x, y, w, h, col, label, sub="", icon=None, size=20):
        """A wide strip, for a kernel, a network or a shared layer under the boxes."""
        self.rect(x, y, w, h, col, pastel(col), 14, SW)
        tx = x + 20
        if icon:
            self.icon(icon, x + 18, y + h / 2 - 15, col, s=0.68)
            tx = x + 60
        if sub:
            self.text(tx, y + h / 2 - 3, label, size, deep(col), True)
            self.text(tx, y + h / 2 + 21, sub, size - 3, SOFT)
        else:
            self.text(tx, y + h / 2 + size * 0.36, label, size, deep(col), True)
        return Box(x, y, w, h)

    # ---- titles ---------------------------------------------------------------------
    def title(self, text, highlight=""):
        self.rect(40, 34, 6, 40, PURPLE, PURPLE, rx=3, sw=0)
        self.text(62, 66, text, 34, INK, True)
        if highlight:
            x = 62 + text_width(text + " ", 34, True)
            self.text(x, 66, highlight, 34, PURPLE, True)

    def subtitle(self, text):
        self.text(62, 104, text, 20, SOFT)

    # ---- boxes ----------------------------------------------------------------------
    def node(self, x, y, w, h, col, label, icon=None, sub=None, size=22):
        """A pastel box with an accent edge: an icon tile on the left, one to three words,
        an optional small sub-line."""
        self.rect(x, y, w, h, col, pastel(col), 14, SW)
        tx = x + 20
        if icon:
            t = 44 if h >= 76 else 36
            self.rect(x + 16, y + h / 2 - t / 2, t, t, col, col, 10, 0)
            self.icon(icon, x + 16 + t * 0.18, y + h / 2 - t * 0.32, WHITE, s=t * 0.64 / 44, bg=col)
            tx = x + 16 + t + 14
        self._label(tx, y, h, label, sub, size, INK)
        return Box(x, y, w, h)

    def outline(self, x, y, w, h, col, label, icon=None, size=19, sub=None, fill=WHITE):
        """A white box with a coloured edge, for smaller parts (containers, rules)."""
        self.rect(x, y, w, h, col, fill, 12, SW)
        tx = x + 16
        if icon:
            self.icon(icon, x + 14, y + h / 2 - 15, col, s=0.68)
            tx = x + 56
        self._label(tx, y, h, label, sub, size, INK)
        return Box(x, y, w, h)

    def _label(self, tx, y, h, label, sub, size, col, anchor="start"):
        lines = label.split("\n") if label else []
        subs = sub.split("\n") if sub else []
        lh, sh = size * 1.22, 17 * 1.3
        total = len(lines) * lh + len(subs) * sh
        top = y + h / 2 - total / 2 + size * 0.8
        for i, t in enumerate(lines):
            self.text(tx, top + i * lh, t, size, col, True, anchor)
        for i, t in enumerate(subs):
            self.text(tx, top + len(lines) * lh + i * sh - 1, t, 17, SOFT, False, anchor)

    def box(self, x, y, w, h, col, label, sub=None, size=19, solid=False):
        """A centred label in a small box: a container, a chain, a rule."""
        self.rect(x, y, w, h, col, col if solid else pastel(col), 10, SW)
        lines = label.split("\n")
        subs = sub.split("\n") if sub else []
        lh, sh = size * 1.22, 17 * 1.3
        total = len(lines) * lh + len(subs) * sh
        top = y + h / 2 - total / 2 + size * 0.8
        for i, t in enumerate(lines):
            self.text(x + w / 2, top + i * lh, t, size, WHITE if solid else INK, True, "middle")
        for i, t in enumerate(subs):
            self.text(x + w / 2, top + len(lines) * lh + i * sh - 1, t, 17, WHITE if solid else SOFT, False, "middle")
        return Box(x, y, w, h)

    def chip(self, x, y, label, col=SLATE, size=16, anchor="start", solid=False, mono=True):
        """A small pill: a port, a label, a header. (x, y) is its left (or centre) middle."""
        w = (len(label) * size * 0.61 if mono else text_width(label, size, True)) + 22
        h = size + 12
        left = x - w / 2 if anchor == "middle" else (x - w if anchor == "end" else x)
        self.rect(left, y - h / 2, w, h, col, col if solid else WHITE, h / 2, 1.4)
        self.text(left + w / 2, y + size * 0.36, label, size, WHITE if solid else deep(col), True, "middle", mono=mono)
        return Box(left, y - h / 2, w, h)

    def port(self, p, label, col=SLATE, side="right", size=16):
        """A small square on a box edge at point p, with its port label beside it."""
        x, y = p
        self.rect(x - 6, y - 6, 12, 12, col, WHITE, 3, 1.8)
        off = {"right": (12, 0, "start"), "left": (-12, 0, "end"),
               "above": (0, -22, "middle"), "below": (0, 22, "middle")}[side]
        return self.chip(x + off[0], y + off[1], label, col, size, off[2])

    def diamond(self, cx, cy, w, h, col, label, size=18):
        """A decision."""
        self.poly([(cx, cy - h / 2), (cx + w / 2, cy), (cx, cy + h / 2), (cx - w / 2, cy)], col, pastel(col), SW)
        lines = label.split("\n")
        lh = size * 1.2
        top = cy - len(lines) * lh / 2 + size * 0.8
        for i, t in enumerate(lines):
            self.text(cx, top + i * lh, t, size, INK, True, "middle")
        return Box(cx - w / 2, cy - h / 2, w, h)

    def mark(self, cx, cy, ok=True, r=14):
        """A green tick or a red cross in a circle, where a check passes or fails."""
        col = GREEN if ok else RED
        self.ellipse(cx, cy, r, r, col, col, 0)
        if ok:
            self.line([(cx - r * 0.42, cy), (cx - r * 0.1, cy + r * 0.34), (cx + r * 0.45, cy - r * 0.32)], WHITE, 2.6)
        else:
            self.line([(cx - r * 0.36, cy - r * 0.36), (cx + r * 0.36, cy + r * 0.36)], WHITE, 2.6)
            self.line([(cx + r * 0.36, cy - r * 0.36), (cx - r * 0.36, cy + r * 0.36)], WHITE, 2.6)

    def group(self, x, y, w, h, label="", col=DIM):
        """A dashed group around related parts. The label sits inside, top-left."""
        self.rect(x, y, w, h, col, "none", 16, 1.6, True)
        if label:
            self.text(x + 18, y + 30, label, 18, SOFT if col == DIM else deep(col), True)
        return Box(x, y, w, h)

    # ---- flow ------------------------------------------------------------------------
    def step(self, cx, cy, n, r=16):
        self.ellipse(cx, cy, r + 3, r + 3, WHITE, WHITE, 0)
        self.ellipse(cx, cy, r, r, STEP, STEP, 0)
        self.text(cx, cy + 6.5, str(n), 18, STEP_INK, True, "middle")

    def _flow_label(self, cx, cy, label, pos, r, colr, size=18):
        lines = label.split("\n")
        gap = size * 1.25
        if pos == "right":
            for i, t in enumerate(lines):
                self.text(cx + r + 10, cy + 6 + (i - (len(lines) - 1) / 2) * gap, t, size, colr, True, halo=True)
        elif pos == "left":
            for i, t in enumerate(lines):
                self.text(cx - r - 10, cy + 6 + (i - (len(lines) - 1) / 2) * gap, t, size, colr, True, "end", halo=True)
        elif pos == "above":
            for i, t in enumerate(lines):
                self.text(cx, cy - r - 10 - (len(lines) - 1 - i) * gap, t, size, colr, True, "middle", halo=True)
        else:
            for i, t in enumerate(lines):
                self.text(cx, cy + r + 22 + i * gap, t, size, colr, True, "middle", halo=True)

    def arrow(self, pts, label="", n=None, at=None, dashed=False, col=LINE, pos=None, both=False, sw=AW):
        """A line through pts with an arrowhead. n puts a step circle at `at` (default: the
        middle of the longest segment). The label goes right, left, above or below it."""
        self.line(pts, col, sw, dashed, head=True, tail=both)
        if at is None:
            best, at = -1, None
            for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
                d = abs(x1 - x0) + abs(y1 - y0)
                if d > best:
                    best, at = d, ((x0 + x1) / 2, (y0 + y1) / 2)
                    vertical = abs(x1 - x0) < abs(y1 - y0)
        else:
            vertical = False
            for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
                if min(x0, x1) - 1 <= at[0] <= max(x0, x1) + 1 and min(y0, y1) - 1 <= at[1] <= max(y0, y1) + 1:
                    vertical = abs(x1 - x0) < abs(y1 - y0)
                    break
        cx, cy = at
        r = 16 if n is not None else 0
        if n is not None:
            self.step(cx, cy, n)
        if label:
            if pos is None:
                pos = "right" if vertical else "above"
            colr = INK if n is not None else (deep(col) if col in DEEP and col != LINE else SOFT)
            self._flow_label(cx, cy, label, pos, r, colr)
        return at

    def connect(self, a, b, label="", n=None, sa=None, sb=None, fa=0.5, fb=0.5, via=None, at=None,
                pos=None, col=LINE, dashed=False, both=False, sw=AW, off=0, mid=None):
        """An arrow from box a to box b that starts and ends on their edges.
        Without sides: a straight line where the boxes overlap (off shifts it), else an
        elbow. sa/sb pick the sides ('top', 'bottom', 'left', 'right'), fa/fb the place
        along them. via adds bend points. mid sets the x (or y) of a Z-shaped jog."""
        if sa is None and sb is None and via is None:
            lo, hi = max(a.x, b.x), min(a.r, b.r)
            if hi - lo > 20:
                x = (lo + hi) / 2 + off
                if b.y >= a.b:
                    pts = [(x, a.b), (x, b.y)]
                else:
                    pts = [(x, a.y), (x, b.b)]
                return self.arrow(pts, label, n, at, dashed, col, pos, both, sw)
            lo, hi = max(a.y, b.y), min(a.b, b.b)
            if hi - lo > 20:
                y = (lo + hi) / 2 + off
                if b.x >= a.r:
                    pts = [(a.r, y), (b.x, y)]
                else:
                    pts = [(a.x, y), (b.r, y)]
                return self.arrow(pts, label, n, at, dashed, col, pos, both, sw)
            sa = "right" if b.cx > a.cx else "left"
            sb = "top" if b.cy > a.cy else "bottom"
        if sa is None:
            sa = "bottom" if b.y >= a.b else ("top" if b.b <= a.y else ("right" if b.cx > a.cx else "left"))
        if sb is None:
            sb = {"bottom": "top", "top": "bottom", "right": "left", "left": "right"}[sa]
        p0, p1 = a.at(sa, fa), b.at(sb, fb)
        if via is not None:
            pts = [p0] + list(via) + [p1]
        else:
            ha, hb = sa in ("left", "right"), sb in ("left", "right")
            if ha and hb:
                if abs(p0[1] - p1[1]) < 0.5:
                    pts = [p0, p1]
                else:
                    mx = mid if mid is not None else (p0[0] + p1[0]) / 2
                    if sa == sb:
                        mx = mid if mid is not None else (max(p0[0], p1[0]) + 40 if sa == "right" else min(p0[0], p1[0]) - 40)
                    pts = [p0, (mx, p0[1]), (mx, p1[1]), p1]
            elif not ha and not hb:
                if abs(p0[0] - p1[0]) < 0.5:
                    pts = [p0, p1]
                else:
                    my = mid if mid is not None else (p0[1] + p1[1]) / 2
                    if sa == sb:
                        my = mid if mid is not None else (max(p0[1], p1[1]) + 40 if sa == "bottom" else min(p0[1], p1[1]) - 40)
                    pts = [p0, (p0[0], my), (p1[0], my), p1]
            elif ha:
                pts = [p0, (p1[0], p0[1]), p1]
            else:
                pts = [p0, (p0[0], p1[1]), p1]
        return self.arrow(pts, label, n, at, dashed, col, pos, both, sw)

    def note(self, x, y, lines, size=18, col=SOFT, anchor="start"):
        if isinstance(lines, str):
            lines = [lines]
        for i, t in enumerate(lines):
            self.text(x, y + i * (size + 8), t, size, col, False, anchor)

    def legend(self, x, y, entries, size=16):
        """A row of small swatches: [(colour, label, dashed), ...]."""
        for e in entries:
            col, label = e[0], e[1]
            dashed = len(e) > 2 and e[2]
            self.line([(x, y), (x + 34, y)], col, AW, dashed, head=True)
            self.text(x + 44, y + 5.5, label, size, SOFT)
            x += 44 + text_width(label, size) + 36

    # ---- output -------------------------------------------------------------------
    @staticmethod
    def _head(p_from, p_to, size=10):
        (x0, y0), (x1, y1) = p_from, p_to
        dx, dy = x1 - x0, y1 - y0
        d = max((dx * dx + dy * dy) ** 0.5, 1e-6)
        ux, uy = dx / d, dy / d
        bx, by = x1 - ux * size, y1 - uy * size
        w = size * 0.5
        return [(x1, y1), (bx - uy * w, by + ux * w), (bx + uy * w, by - ux * w)], (bx + ux * 2, by + uy * 2)

    def svg(self):
        o = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
             f'viewBox="0 0 {self.w} {self.h}" font-family="{FONT}">',
             f'<rect width="{self.w}" height="{self.h}" fill="{BG}"/>']
        for it in self.items:
            k = it[0]
            if k == "rect":
                _, x, y, w, h, s, f, rx, sw, d = it
                dash = ' stroke-dasharray="7 6"' if d else ""
                stroke = f'stroke="{s}" stroke-width="{sw}"' if sw else 'stroke="none"'
                o.append(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx:.1f}" fill="{f}" '
                         f'{stroke}{dash}/>')
            elif k == "ellipse":
                _, cx, cy, rx, ry, s, f, sw = it
                stroke = f'stroke="{s}" stroke-width="{sw:.2f}"' if sw else 'stroke="none"'
                o.append(f'<ellipse cx="{cx:.1f}" cy="{cy:.1f}" rx="{rx:.1f}" ry="{ry:.1f}" fill="{f}" {stroke}/>')
            elif k == "line":
                _, pts, s, sw, d, head, tail = it
                pts = list(pts)
                heads = []
                hs = 8 + sw * 1.6
                if head and len(pts) > 1:
                    tri, back = self._head(pts[-2], pts[-1], hs)
                    heads.append(tri)
                    pts[-1] = back
                if tail and len(pts) > 1:
                    tri, back = self._head(pts[1], pts[0], hs)
                    heads.append(tri)
                    pts[0] = back
                dash = ' stroke-dasharray="7 6"' if d else ""
                p = " ".join(f"{a:.1f},{b:.1f}" for a, b in pts)
                o.append(f'<polyline points="{p}" fill="none" stroke="{s}" stroke-width="{sw:.2f}" '
                         f'stroke-linecap="round" stroke-linejoin="round"{dash}/>')
                for tri in heads:
                    q = " ".join(f"{a:.1f},{b:.1f}" for a, b in tri)
                    o.append(f'<polygon points="{q}" fill="{s}" stroke="{s}" stroke-width="1" stroke-linejoin="round"/>')
            elif k == "poly":
                _, pts, s, f, sw = it
                p = " ".join(f"{a:.1f},{b:.1f}" for a, b in pts)
                o.append(f'<polygon points="{p}" fill="{f}" stroke="{s}" stroke-width="{sw:.2f}" stroke-linejoin="round"/>')
            elif k == "text":
                _, x, y, t, size, c, b, anchor, halo, mono = it
                wgt = ' font-weight="700"' if b else ""
                ff = f' font-family="{MONO}"' if mono else ""
                hl = (' stroke="#ffffff" stroke-width="6" stroke-linejoin="round" paint-order="stroke"' if halo else "")
                o.append(f'<text x="{x:.1f}" y="{y:.1f}" font-size="{size:.1f}" fill="{c}"{wgt}{ff}{hl} '
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

        for it in self.items:
            k = it[0]
            if k == "rect":
                _, x, y, w, h, s, f, rx, sw, d = it
                if colour(s) == "transparent" and colour(f) == "transparent":
                    continue
                e = base("rectangle", x, y, w, h, s if (sw and colour(s) != "transparent") else f, f, sw or 1, d)
                if rx:
                    e["roundness"] = {"type": 3}
                els.append(e)
            elif k == "ellipse":
                _, cx, cy, rx, ry, s, f, sw = it
                els.append(base("ellipse", cx - rx, cy - ry, 2 * rx, 2 * ry, s if sw else f, f, sw or 1))
            elif k in ("line", "poly"):
                pts = list(it[1])
                x0, y0 = pts[0]
                closed = k == "poly"
                if closed:
                    pts = pts + [pts[0]]
                xs = [p[0] - x0 for p in pts]
                ys = [p[1] - y0 for p in pts]
                if k == "line":
                    _, _, s, sw, d, head, tail = it
                    e = base("arrow" if (head or tail) else "line", x0, y0, max(xs) - min(xs), max(ys) - min(ys),
                             s, "transparent", sw, d)
                    e.update({"startArrowhead": "triangle" if tail else None,
                              "endArrowhead": "triangle" if head else None})
                else:
                    _, _, s, f, sw = it
                    e = base("line", x0, y0, max(xs) - min(xs), max(ys) - min(ys), s, f, sw)
                    e.update({"startArrowhead": None, "endArrowhead": None})
                e.update({"points": [[a, b] for a, b in zip(xs, ys)], "lastCommittedPoint": None,
                          "startBinding": None, "endBinding": None})
                els.append(e)
            elif k == "text":
                _, x, y, t, size, c, b, anchor, halo, mono = it
                w = text_width(t, size, b)
                left = x - w / 2 if anchor == "middle" else (x - w if anchor == "end" else x)
                e = base("text", left, y - size, w, size * 1.25, c, "transparent", 1)
                e.update({"text": t, "originalText": t, "fontSize": size, "fontFamily": 3 if mono else 2,
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
