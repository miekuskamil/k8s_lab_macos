#!/usr/bin/env python3
"""Draw the diagrams for module 27 (RAG on Kubernetes) with the kit in ../bbg.py.

  27-ingest-and-ask     the two flows: ingest once per change, ask once per question
  27-prompt             what the chat model actually receives

The chunk count is left out on purpose: it changes whenever the course files change.

Run from anywhere: python3 docs/diagrams/chapters/make-27.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


ING = TEAL


def ingest_and_ask():
    c = Canvas(1600, 880)
    c.title("Ingest once,", "ask many times")
    c.subtitle("Both phases use the same service, models and vectors. Teal steps ingest, amber steps ask.")

    c.frame(40, 150, 320, 690, "Your Mac", "host")
    c.frame(60, 200, 280, 420, "Ollama", "plain", icon="sparkle")
    emb = c.node(80, 250, 240, 120, PINK, "embedding", "sparkle", "text to 768\nnumbers")
    chat = c.node(80, 460, 240, 120, PINK, "chat model", "sparkle", "qwen2.5:3b")
    you = c.node(60, 690, 280, 110, SLATE, "You", "terminal", "curl /ask")

    c.frame(420, 150, 1140, 690, "Cluster", "cluster")
    c.frame(450, 190, 1080, 620, "namespace course-rag", "ns")
    cm = c.node(800, 230, 340, 90, SLATE, "ConfigMap", "doc", "course *.md files")
    rag = c.frame(800, 390, 340, 250, "rag service pod", "pod")
    c.box(825, 440, 290, 170, SLATE, "/ingest, /ask", "splits files at\nheadings into chunks")
    qd = c.frame(800, 700, 340, 90, "Qdrant pod", "pod")
    c.chip(1000, 760, "vectors + text, PVC", ORANGE, anchor="middle", mono=False, size=15)

    c.connect(cm, rag, "")
    c.step(970, 355, 1, col=ING, ink=WHITE)
    c.text(996, 361, "read the files", 17, INK, True, halo=True)
    c.connect(rag, emb, "", sa="left", sb="right", fa=0.15, fb=0.5, mid=600, both=True)
    c.step(420, 310, 2, col=ING, ink=WHITE)
    c.step(480, 310, 1)
    c.text(450, 285, "embed", 17, INK, True, "middle", halo=True)
    c.connect(rag, chat, "chunks + question", sa="left", sb="right", fa=(520 - 390) / 250, n=3, pos="above",
              at=(560, 520))
    c.connect(rag, qd, "", both=True)
    c.step(940, 670, 3, col=ING, ink=WHITE)
    c.step(1000, 670, 2)
    c.text(1030, 676, "store / 4 nearest", 17, INK, True, halo=True)
    c.connect(you, rag, "", sa="right", sb="left", fa=0.5, fb=0.9, via=[(700, 745), (700, 615)], both=True)
    c.step(520, 745, 4)
    c.text(546, 735, "question in,", 16, INK, True, halo=True)
    c.text(546, 757, "answer + sources out", 16, INK, True, halo=True)

    c.step(1210, 280, 1, col=ING, ink=WHITE)
    c.text(1238, 286, "ingest, once per change", 17, SOFT)
    c.step(1210, 325, 1)
    c.text(1238, 331, "ask, per question", 17, SOFT)
    c.save(OUT, "27-ingest-and-ask")


def prompt():
    c = Canvas(1600, 860)
    c.title("What the chat model", "receives")
    c.subtitle("The service builds one text with two messages and sends it to Ollama's /api/chat.")

    c.frame(40, 300, 240, 200, "rag service pod", "pod")
    svc = c.box(65, 355, 190, 110, SLATE, "builds", "the request")

    req = c.frame(330, 150, 760, 680, "POST /api/chat", "plain", icon="doc")
    c.frame(360, 210, 700, 170, "system message: the rules", "plain", col=PINK, icon="list")
    for i, t in enumerate(["use only the\nnumbered context", "cite [1], [2]", "say you\ndon't know"]):
        c.box(385 + i * 225, 265, 205, 90, PINK, t, size=17)
    c.frame(360, 410, 700, 390, "user message", "plain", col=BLUE, icon="person")
    for i in range(4):
        c.box(385 + i * 168, 465, 150, 110, BLUE, f"[{i + 1}]", "file, heading,\ntext", size=22)
    c.note(385, 615, "every extra chunk adds its tokens to every question", 16)
    c.box(385, 650, 650, 120, SLATE, "the question", size=20)
    c.connect(svc, req, "", sa="right", sb="left", fb=(410 - 150) / 680)

    c.frame(1150, 250, 410, 480, "Your Mac: Ollama", "host")
    model = c.node(1180, 320, 350, 120, PINK, "qwen2.5:3b", "sparkle", "temperature 0")
    ans = c.node(1180, 560, 350, 120, GREEN, "answer", "doc", "with [n] citations")
    c.connect(req, model, "", sa="right", sb="left", fa=(380 - 150) / 680)
    c.connect(model, ans, "writes", pos="right")
    c.save(OUT, "27-prompt")


if __name__ == "__main__":
    ingest_and_ask()
    prompt()
