#!/usr/bin/env python3
"""Module 17 diagram: one question to the assistant, through the mesh to the backend and to Ollama."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def ask():
    c = Canvas(1600, 900)
    c.title("One question to the", "assistant")
    c.subtitle("The assistant fetches recent orders, then asks the model. The waypoint checks both calls.")

    c.frame(40, 150, 300, 710, "Your Mac", "host")
    you = c.node(70, 220, 240, 110, SLATE, "curl", "terminal", "POST /api/ask")
    oll = c.node(70, 690, 240, 110, PINK, "Ollama", "sparkle", "qwen2.5:3b")

    c.frame(400, 150, 1160, 710, "Cluster", "cluster")
    c.frame(430, 190, 340, 190, "namespace shop-ingress", "ns")
    gw = c.node(460, 230, 280, 110, BLUE, "gateway", "shield", "routes /api/ask")
    c.frame(430, 420, 1100, 410, "namespace shop", "ns")
    asst = c.frame(460, 470, 260, 160, "assistant pod", "pod")
    c.box(485, 520, 210, 80, SLATE, "app", "builds the prompt")
    wp = c.frame(880, 470, 300, 240, "waypoint pod", "plain", col=BLUE, icon="shield")
    c.box(905, 525, 250, 150, BLUE, "Envoy", "checks both calls\nfor sa/assistant")
    be = c.frame(1330, 470, 180, 160, "backend pod", "pod")
    c.box(1350, 520, 140, 80, SLATE, "app")

    c.connect(you, gw, "", n=1, sa="right", sb="left", at=(370, 285))
    c.connect(gw, asst, "", n=2, sa="bottom", sb="top", fa=0.5, fb=(600 - 460) / 260, at=(600, 400))
    c.connect(asst, wp, "", n=3, sa="right", sb="left", fa=(510 - 470) / 160, fb=(510 - 470) / 240, at=(800, 510))
    c.connect(wp, be, "GET orders", sa="right", sb="left", fa=(510 - 470) / 240, fb=(510 - 470) / 160,
              pos="above", at=(1255, 510))
    c.text(1255, 548, "about 5 ms", 16, SOFT, False, "middle")
    c.connect(asst, wp, "", n=4, sa="right", sb="left", fa=(590 - 470) / 160, fb=(590 - 470) / 240, at=(800, 590))
    c.line([(1030, 710), (1030, 740), (310, 740)], LINE, AW, head=True)
    c.text(660, 730, "POST /api/chat: orders + question", 17, INK, True, "middle", halo=True)
    c.line([(310, 780), (590, 780), (590, 630)], PINK, AW, dashed=True, head=True)
    c.step(450, 780, 5)
    c.text(476, 810, "answer, 1 to 10 s", 17, DEEP[PINK], True, halo=True)
    c.line([(460, 560), (190, 560), (190, 330)], SLATE, AW, dashed=True, head=True)
    c.step(190, 445, 6)
    c.text(214, 440, "answer, tokens,", 16, SOFT, True, halo=True)
    c.text(214, 462, "seconds, trace_id", 16, SOFT, True, halo=True)
    c.save(OUT, "17-assistant-flow")


if __name__ == "__main__":
    ask()
