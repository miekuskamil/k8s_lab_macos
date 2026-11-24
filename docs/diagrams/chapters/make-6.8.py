#!/usr/bin/env python3
"""Draw the game-day incident flow for module 6.8 with the kit in ../bbg.py."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def game_day():
    c = Canvas(1600, 1600)
    c.title("Triage the", "checkout outage")
    c.subtitle("Use the SLO to confirm impact, inspect the fault, remove it and prove that orders recover.")

    c.frame(40, 150, 330, 1290, "your terminal", "host")
    observe = c.box(70, 280, 270, 90, SLATE, "SLO + logs", "504, payments timeout")
    inspect = c.box(70, 540, 270, 90, SLATE, "kubectl get", "find NetworkChaos")
    abort = c.box(70, 800, 270, 90, PINK, "kubectl delete", "remove the fault")
    verify = c.box(70, 1060, 270, 90, GREEN, "20 orders", "all answer 200")

    c.frame(420, 150, 1140, 1290, "OrbStack cluster", "cluster")
    c.frame(465, 230, 1050, 480, "namespace course-sre", "ns")
    lg = c.box(510, 350, 220, 90, SLATE, "loadgen", "orders")
    checkout = c.frame(790, 320, 260, 170, "pod checkout", "pod")
    co = c.box(815, 380, 210, 80, SLATE, "checkout", "1 s timeout")
    payments = c.frame(1120, 320, 260, 170, "pod payments", "pod")
    pay = c.box(1145, 380, 210, 80, SLATE, "podinfo", "dependency")
    chaos = c.box(1120, 555, 260, 90, PINK, "NetworkChaos", "delay 2 s")

    c.frame(465, 790, 1050, 430, "namespace observability", "ns")
    prom = c.box(520, 900, 270, 90, ORANGE, "Prometheus", "availability SLI")
    page = c.box(900, 900, 240, 90, RED, "page", "budget burn")
    log = c.box(520, 1060, 270, 90, SLATE, "checkout log", "payments timeout")
    recovery = c.box(900, 1060, 300, 90, GREEN, "orders recover", "200 responses")

    c.connect(lg, co, "request", n=1, sa="right", sb="left", at=(760, 395), pos="above")
    c.connect(co, pay, "times out", sa="right", sb="left", fa=0.5, fb=0.5, at=(1085, 420), pos="above", col=RED)
    c.connect(chaos, pay, "injects delay", n=2, sa="top", sb="bottom", fa=0.5, fb=0.5, at=(1250, 520), pos="right")
    c.connect(co, prom, "504s", sa="bottom", sb="top", fa=0.5, fb=0.5,
              via=[(920, 700), (655, 700)], at=(790, 700), pos="above")
    c.connect(prom, page, "burns budget", sa="right", sb="left", at=(845, 945), pos="above", col=RED)
    c.connect(co, log, "writes timeout", sa="bottom", sb="top", fa=0.5, fb=0.5,
              via=[(920, 740), (655, 740)], at=(790, 740), pos="above")
    c.connect(abort, chaos, "deletes", n=3, sa="right", sb="left", fa=0.5, fb=0.5,
              via=[(390, 845), (1080, 845), (1080, 600)], at=(740, 845), pos="above", col=PINK)
    c.connect(pay, recovery, "healthy again", sa="bottom", sb="top", fa=0.5, fb=0.5,
              via=[(1250, 720), (1050, 720), (1050, 1025)], at=(1150, 720), pos="above", col=GREEN)
    c.connect(verify, recovery, "checks", n=4, sa="right", sb="left", at=(835, 1105), pos="above", col=GREEN)
    c.save(OUT, "6.8-sre-game-day")


if __name__ == "__main__":
    game_day()
