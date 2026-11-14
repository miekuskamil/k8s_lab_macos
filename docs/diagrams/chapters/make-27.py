#!/usr/bin/env python3
"""Draw the diagrams for module 27 (RAG on Kubernetes) in ByteByteGo style (see ../bbg.py).

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


def ingest_and_ask():
    c = Canvas(1840, 760)
    c.title("Ingest once,", "ask many times")
    c.subtitle("Ingest runs when the documents change. Ask runs for every question.")

    c.group(30, 180, 1780, 200, "Ingest, once per change")
    ingest = [(SLATE, "Course files", "doc", "*.md, ConfigMap"),
              (PURPLE, "Split", "gear", "at headings, chunks"),
              (TEAL, "Embedding", "gear", "text to 768 numbers"),
              (ORANGE, "Qdrant", "db", "vector + text")]
    xs = [70, 520, 970, 1420]
    for x, (col, label, icon, sub) in zip(xs, ingest):
        c.node(x, 225, 350, 110, col, label, icon, sub, size=22)
    for i in range(3):
        x0 = xs[i] + 350
        c.arrow([(x0, 280), (xs[i + 1], 280)], "", n=i + 1, at=((x0 + xs[i + 1]) / 2, 280))

    c.group(30, 520, 1780, 200, "Ask, per question")
    ask = [(SLATE, "Question", "person", None),
           (TEAL, "Embed", "gear", "the question too"),
           (ORANGE, "Qdrant", "db", "4 nearest chunks"),
           (PURPLE, "Chat model", "gear", "only these chunks"),
           (GREEN, "Answer", "doc", "+ sources")]
    xs2 = [70, 430, 790, 1150, 1510]
    for x, (col, label, icon, sub) in zip(xs2, ask):
        c.node(x, 565, 280, 110, col, label, icon, sub, size=22)
    for i in range(4):
        x0 = xs2[i] + 280
        c.arrow([(x0, 620), (xs2[i + 1], 620)], "", n=i + 1, at=((x0 + xs2[i + 1]) / 2, 620))

    c.line([(1595, 335), (1595, 450), (1040, 450), (1040, 565)], SOFT, 2.5, True, head=True)
    c.text(1320, 438, "Same vectors", 18, SOFT, True, "middle")
    c.save(OUT, "27-ingest-and-ask")


def prompt():
    c = Canvas(1760, 800)
    c.title("What the chat model", "receives")
    c.subtitle("The service builds one text with two messages and sends it to Ollama's /api/chat.")

    c.group(60, 190, 760, 150, "System message: the rules")
    for i, t in enumerate(["Use only the\nnumbered context", "Cite [1], [2]", "Say you don't\nknow"]):
        c.outline(85 + i * 245, 222, 225, 90, PINK, t)

    c.group(60, 430, 760, 320, "User message")
    for i in range(4):
        c.outline(85 + i * 182, 462, 162, 90, BLUE, f"[{i + 1}]\nchunk")
    c.note(85, 590, ["Each chunk: file, heading and text"], 17)
    c.outline(85, 630, 710, 90, SLATE, "Question")

    c.node(1000, 410, 340, 120, PURPLE, "qwen2.5:3b", "gear", "temperature 0")
    c.arrow([(820, 265), (1170, 265), (1170, 410)], "Rules", at=(995, 265), pos="above")
    c.arrow([(820, 590), (1170, 590), (1170, 530)], "Context +\nquestion", at=(995, 590), pos="below")

    c.node(1440, 410, 280, 120, GREEN, "Answer", "doc", "with [n] citations")
    c.arrow([(1340, 470), (1440, 470)], "")
    c.save(OUT, "27-prompt")


if __name__ == "__main__":
    ingest_and_ask()
    prompt()
