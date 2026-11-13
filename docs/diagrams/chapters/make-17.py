#!/usr/bin/env python3
"""Module 17 diagram: one question to the assistant, through the mesh to the backend and to Ollama."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def ask():
    c = Canvas(1840, 870)
    c.title("One Question to the", "Assistant")
    c.subtitle("The assistant fetches recent orders, then asks the model. The waypoint checks both calls.")
    top, low = 290, 630
    c.node(60, top, 300, 110, SLATE, "You", "laptop", "curl")
    c.node(520, top, 320, 110, BLUE, "Ingress gateway", "shield")
    c.node(1000, top, 320, 110, SLATE, "assistant", "cube")
    c.node(520, low, 320, 110, SLATE, "backend", "cube")
    c.node(1000, low, 320, 110, PURPLE, "Waypoint", "shield")
    c.node(1480, low, 300, 110, SLATE, "Ollama", "laptop", "on your Mac")

    c.arrow([(360, top + 55), (520, top + 55)], "POST\n/api/ask", n=1, at=(440, top + 55), pos="below")
    c.arrow([(840, top + 55), (1000, top + 55)], "route\n/api/ask", n=2, at=(920, top + 55), pos="below")
    # assistant to waypoint carries two calls
    c.arrow([(1200, top + 116), (1200, low)])
    c.step(1200, top + 175, 3)
    c.text(1230, top + 182, "GET /api/orders", 18, INK, True)
    c.step(1200, top + 265, 6)
    c.text(1230, top + 260, "POST /api/chat", 18, INK, True)
    c.text(1230, top + 283, "orders + question", 18, INK, True)
    c.arrow([(1000, low + 55), (840, low + 55)], "allowed for\nsa/assistant?", n=4, at=(920, low + 55), pos="below")
    c.arrow([(1320, low + 55), (1480, low + 55)], "allowed?\nthen forward", n=7, at=(1400, low + 55), pos="below")
    c.arrow([(780, low), (780, 500), (1060, 500), (1060, top + 116)], "10 orders\n5 ms",
            n=5, at=(900, 500), pos="above")
    c.arrow([(1630, low), (1630, top + 55), (1320, top + 55)], "answer\n1 to 10 s",
            n=8, at=(1630, 480), pos="left")
    c.arrow([(1160, top), (1160, 200), (210, 200), (210, top)], "answer, tokens, seconds, trace_id",
            n=9, at=(700, 200), pos="below")
    c.note(60, 830, ["Replies 5, 8 and 9 return through the same proxies."], 17)
    c.save(OUT, "17-assistant-flow")


if __name__ == "__main__":
    ask()
