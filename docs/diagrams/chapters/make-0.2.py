#!/usr/bin/env python3
"""Draw the diagrams for course module 0.2 (building images) with the kit in ../bbg.py.

  0.2-build-cache    the build context, BuildKit's cache and the first changed step
  0.2-multi-stage    the build stage compiles, the final stage gets only the binary

The circled numbers match the numbered lists in module 0.2.

Run from anywhere: python3 docs/diagrams/chapters/make-0.2.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def cache():
    c = Canvas(1600, 1000)
    c.title("The build cache", "stops at the first change")
    c.subtitle("Steps above the change come from the cache. The changed step and every step below it run.")

    c.frame(40, 150, 1520, 810, "Docker host", "host", icon="box")
    c.frame(80, 210, 360, 300, "toolbox", "pod")
    ctx = c.box(110, 280, 300, 90, ORANGE, "build context", "work/app folder")
    ign = c.box(110, 400, 300, 80, RED, ".dockerignore", "keeps files out")

    c.frame(520, 210, 1000, 710, "BuildKit", "plain", col=PURPLE)
    rows = [
        ("FROM golang", "base image", True),
        ("WORKDIR /src", "", True),
        ("COPY go.mod", "same checksum", True),
        ("RUN go mod download", "", True),
        ("COPY *.go", "main.go changed", False),
        ("RUN go build", "layer below changed", False),
        ("COPY --from=build", "final stage", False),
    ]
    boxes = []
    y = 270
    for label, sub, cached in rows:
        b = c.box(560, y, 470, 78, SLATE if cached else ORANGE, label, sub or None, size=19)
        c.chip(1060, y + 39, "CACHED" if cached else "runs", GREEN if cached else ORANGE, solid=not cached)
        boxes.append(b)
        y += 92
    store = c.node(1250, 300, 230, 150, GREEN, "cache", "db", "layers by key", size=20)
    for a, b in zip(boxes, boxes[1:]):
        c.connect(a, b)
    c.connect(ctx, boxes[0], "", n=1, sa="right", sb="left", fa=0.5, fb=0.5, mid=490, at=(490, 320))
    c.line([(1170, 300), (1170, 588)], GREEN, 2.0, dashed=True)
    c.arrow([(1170, 375), (1250, 375)], col=GREEN, dashed=True, n=2, at=(1205, 375))
    c.step(540, 677, 3)
    c.step(540, 769, 4)
    c.save(OUT, "0.2-build-cache")


def multistage():
    c = Canvas(1600, 860)
    c.title("A multi-stage build", "ships only what runs")
    c.subtitle("The build stage holds the compiler and the source. The final image holds one binary.")

    c.frame(40, 150, 1520, 670, "BuildKit", "plain", col=PURPLE)
    c.frame(80, 210, 640, 570, "stage build: golang image, 430 MB", "plain", col=ORANGE)
    go = c.box(120, 280, 560, 80, SLATE, "Go toolchain", "compiler, standard library")
    src = c.box(120, 400, 560, 80, SLATE, "source code", "go.mod, main.go")
    comp = c.box(120, 520, 560, 80, GREEN, "go build", "CGO_ENABLED=0")
    binr = c.box(120, 660, 560, 80, ORANGE, "/out/hits", "static binary, 8 MB")

    c.frame(880, 210, 640, 570, "final stage: scratch, 8 MB", "plain", col=BLUE)
    hits = c.box(920, 280, 560, 80, ORANGE, "/hits", "the only file")
    user = c.box(920, 400, 560, 80, RED, "USER 65532", "not root")
    hc = c.box(920, 520, 560, 80, TEAL, "HEALTHCHECK", "/hits healthcheck")
    img = c.box(920, 660, 560, 80, BLUE, "image hits:1.0.0", "what you tag and push")

    c.connect(go, src, "", n=1)
    c.connect(src, comp)
    c.connect(comp, binr, "", n=2)
    c.connect(binr, hits, "", n=3, sa="right", sb="left", fa=0.5, fb=0.5, mid=800, at=(800, 500))
    c.connect(hits, user)
    c.connect(user, hc)
    c.connect(hc, img, "", n=4)
    c.save(OUT, "0.2-multi-stage")


cache()
multistage()
