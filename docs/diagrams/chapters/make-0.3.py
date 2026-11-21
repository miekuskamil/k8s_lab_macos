#!/usr/bin/env python3
"""Draw the diagrams for course module 0.3 (Docker Compose) with the kit in ../bbg.py.

  0.3-compose-project   three services on the project network, DNS, one port, a volume
  0.3-start-order       depends_on with service_healthy: each waits for the one below

The circled numbers match the numbered lists in module 0.3.

Run from anywhere: python3 docs/diagrams/chapters/make-0.3.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def project():
    c = Canvas(1600, 960)
    c.title("A Compose project", "on its own network")
    c.subtitle("Services find each other by name through Docker's DNS. Only the proxy publishes a port.")

    c.frame(40, 150, 1520, 770, "Docker host", "host", icon="box")
    client = c.box(80, 230, 220, 80, SLATE, "curl", "port 8884")
    pub = c.box(80, 420, 220, 80, GREEN, "published port", "8884 to 80", size=18)

    c.frame(360, 210, 1160, 500, "network course-compose_default", "plain", col=GREEN)
    c.frame(400, 270, 300, 200, "proxy", "pod")
    nginx = c.box(430, 330, 240, 90, BLUE, "nginx", "port 80")
    c.frame(780, 270, 300, 200, "api", "pod")
    api = c.box(810, 330, 240, 90, SLATE, "hits", "port 8000")
    c.frame(1160, 270, 320, 200, "redis", "pod")
    red = c.box(1190, 330, 260, 90, SLATE, "redis-server", "port 6379")

    dns = c.box(430, 570, 620, 90, TEAL, "Docker DNS 127.0.0.11", "api, redis, proxy", size=19)
    vol = c.box(1190, 760, 260, 90, ORANGE, "volume data", "course-compose_data", size=18)

    c.connect(client, pub, "", n=1)
    c.connect(pub, nginx, "", sa="right", sb="left", fa=0.5, fb=0.5, mid=380)
    c.connect(nginx, dns, "", n=2, sa="bottom", sb="top", fa=0.5, fb=(550 - 430) / 620)
    c.connect(nginx, api, "")
    c.connect(api, dns, "", sa="bottom", sb="top", fa=0.5, fb=(930 - 430) / 620, col=TEAL, dashed=True)
    c.connect(api, red, "", n=3)
    c.connect(red, vol, "", n=4, sa="bottom", sb="top")
    c.save(OUT, "0.3-compose-project")


def order():
    c = Canvas(1600, 880)
    c.title("Start order", "waits for healthy")
    c.subtitle("depends_on with condition: service_healthy holds each service until the one it needs answers.")

    c.frame(40, 150, 1520, 690, "docker compose up", "plain", col=PURPLE)
    net = c.box(80, 230, 300, 90, GREEN, "network, volume", "created first", size=19)
    r = c.box(460, 230, 300, 90, SLATE, "redis starts", "")
    rh = c.diamond(610, 450, 280, 130, TEAL, "redis-cli ping\nPONG?")
    a = c.box(840, 230, 300, 90, SLATE, "api starts", "")
    ah = c.diamond(990, 620, 280, 130, TEAL, "/healthz\nok?")
    p = c.box(1220, 230, 300, 90, BLUE, "proxy starts", "last")
    ok = c.box(1220, 700, 300, 90, GREEN, "first request", "finds it all ready", size=19)

    c.connect(net, r, "", n=1)
    c.connect(r, rh, "", n=2)
    c.connect(rh, a, "healthy", sa="right", sb="bottom", fa=0.5, fb=0.2, pos="above")
    c.connect(a, ah, "", n=3, sa="bottom", sb="top", fa=0.5, fb=0.5, at=(990, 470))
    c.connect(ah, p, "healthy", sa="right", sb="bottom", fa=0.5, fb=0.2, pos="above")
    c.connect(p, ok, "", n=4)
    c.text(610, 545, "else retry in 2 s", 17, SOFT, True, "middle")
    c.text(990, 715, "else retry in 5 s", 17, SOFT, True, "middle")
    c.save(OUT, "0.3-start-order")


project()
order()
