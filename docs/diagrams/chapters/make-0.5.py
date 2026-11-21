#!/usr/bin/env python3
"""Draw the diagrams for course module 0.5 (networking in depth) with the kit in ../bbg.py.

  0.5-bridge   two containers on one bridge network: eth0, veth pairs, the bridge
  0.5-dns      Docker's embedded DNS: NAT rules and a dockerd socket inside the container
  0.5-nat      masquerade on the way out, DNAT on the way in, conntrack, the userland proxy

The circled numbers match the numbered lists in module 0.5. Addresses come from one test
run on a Mac with OrbStack.

Run from anywhere: python3 docs/diagrams/chapters/make-0.5.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def bridge():
    c = Canvas(1600, 1060)
    c.title("One bridge,", "a veth pair per container")
    c.subtitle("Each eth0 is one end of a virtual cable. The other end plugs into the bridge on the host.")

    c.frame(40, 150, 1520, 870, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(100, 210, 520, 300, "course-a netns", "pod")
    wget = c.box(140, 270, 440, 80, SLATE, "wget course-b", "route: own subnet via eth0", size=19)
    ea = c.box(140, 400, 440, 80, GREEN, "eth0", "192.168.148.2")
    c.frame(980, 210, 520, 300, "course-b netns", "pod")
    ngx = c.box(1020, 270, 440, 80, SLATE, "nginx", "port 80")
    eb = c.box(1020, 400, 440, 80, GREEN, "eth0", "192.168.148.3")

    c.frame(100, 620, 1400, 360, "host network namespace", "plain", col=GREEN)
    va = c.box(140, 690, 440, 80, GREEN, "vetha4762cb", "host end of the cable", size=19)
    vb = c.box(1020, 690, 440, 80, GREEN, "veth of course-b", "host end of the cable", size=19)
    br = c.box(140, 850, 1320, 90, GREEN, "bridge br-6f252504c5d0", "gateway 192.168.148.1, learns MACs", size=20)

    c.connect(wget, ea, "", n=1)
    c.connect(ea, va, "veth pair", n=2, pos="right", at=(360, 550))
    c.connect(va, br, "", n=3, sa="bottom", sb="top", fa=0.5, fb=(360 - 140) / 1320)
    c.connect(br, vb, "", sa="top", sb="bottom", fa=(1240 - 140) / 1320, fb=0.5)
    c.connect(vb, eb, "veth pair", n=4, pos="right", at=(1240, 550))
    c.connect(eb, ngx)
    c.save(OUT, "0.5-bridge")


def dns():
    c = Canvas(1600, 980)
    c.title("Docker's DNS server", "inside each container")
    c.subtitle("127.0.0.11 never leaves the container: NAT rules there send it to a dockerd socket.")

    c.frame(40, 150, 1520, 790, "Docker host", "host", icon="box")
    c.frame(80, 210, 900, 690, "course-a netns", "pod")
    prog = c.box(120, 270, 380, 80, SLATE, "nslookup course-b", "to 127.0.0.11:53", size=19)
    out = c.box(120, 430, 380, 90, GREEN, "DOCKER_OUTPUT", "DNAT to :48364", size=19)
    sock = c.box(560, 430, 380, 90, PURPLE, "dockerd socket", "127.0.0.11:48364", size=19)
    post = c.box(120, 620, 380, 90, GREEN, "DOCKER_POSTROUTING", "SNAT back to :53", size=18)
    ans = c.box(120, 780, 380, 80, SLATE, "answer", "from 127.0.0.11:53")

    d = c.box(1080, 430, 420, 90, PURPLE, "dockerd", "container records", size=20)
    up = c.box(1080, 640, 420, 90, TEAL, "host's DNS servers", "for other names", size=19)

    c.connect(prog, out, "", n=1)
    c.connect(out, sock, "", n=2)
    c.connect(sock, d, "same process", pos="above")
    c.connect(d, up, "example.com", n=3, pos="right")
    c.connect(sock, post, "", sa="bottom", sb="right", fa=0.5, fb=0.5)
    c.connect(post, ans, "", n=4)
    c.save(OUT, "0.5-dns")


def two_networks():
    c = Canvas(1600, 900)
    c.title("Two networks:", "dropped, then connected")
    c.subtitle("Docker drops packets for a container that arrive through another bridge. A second eth gives a legal path.")

    c.frame(40, 150, 1520, 710, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(80, 210, 560, 250, "course-a", "pod")
    e0 = c.box(110, 290, 230, 80, GREEN, "eth0", "course-net")
    e1 = c.box(380, 290, 230, 80, GREEN, "eth1", "after connect")
    c.frame(960, 210, 560, 250, "course-c", "pod")
    ec = c.box(1100, 290, 280, 80, GREEN, "eth0", "course-net2")

    b1 = c.box(110, 560, 230, 80, GREEN, "bridge", "course-net")
    b2 = c.box(900, 560, 560, 80, GREEN, "bridge", "course-net2")
    rt = c.box(110, 720, 560, 90, RED, "raw PREROUTING", "drop if not from course-c's bridge", size=18)

    c.connect(e0, b1, "", n=1, at=(225, 470))
    c.connect(b1, rt, "", sa="bottom", sb="top", fa=0.5, fb=(225 - 110) / 560)
    c.mark(700, 765, ok=False)
    c.text(730, 772, "Linux: dropped", 18, DEEP[RED], True)
    c.connect(e1, b2, "", n=2, sa="bottom", sb="left", fa=0.5, fb=0.5)
    c.connect(b2, ec, "", sa="top", sb="bottom", fa=(1240 - 900) / 560, fb=0.5)
    c.mark(760, 600, ok=True)
    c.save(OUT, "0.5-two-networks")


def nat():
    c = Canvas(1600, 990)
    c.title("Out with masquerade,", "in with DNAT")
    c.subtitle("The kernel rewrites addresses at the edge of the host, and conntrack remembers each rewrite.")

    c.frame(40, 150, 1520, 800, "Docker host", "host", icon="box", right="on a Mac: OrbStack's Linux VM")
    c.frame(80, 210, 340, 170, "course-a", "pod")
    ca = c.box(110, 270, 280, 80, SLATE, "wget example.com", "192.168.148.2", size=18)
    c.frame(80, 430, 340, 170, "course-web", "pod")
    cw = c.box(110, 490, 280, 80, SLATE, "nginx :80", "192.168.148.4", size=19)
    br = c.box(480, 260, 200, 330, GREEN, "bridge", "course-net")

    k = c.frame(740, 210, 520, 700, "host kernel", "plain", col=GREEN)
    rt = c.box(780, 270, 440, 70, GREEN, "route via eth0", "default gateway", size=18)
    masq = c.box(780, 380, 440, 80, RED, "POSTROUTING", "MASQUERADE to eth0's address", size=18)
    ct = c.box(780, 520, 440, 80, ORANGE, "conntrack", "original and rewritten", size=19)
    dnat = c.box(780, 660, 440, 80, RED, "PREROUTING DOCKER", "DNAT :8886 to course-web:80", size=18)
    fwd = c.box(780, 790, 440, 80, RED, "FORWARD DOCKER", "ACCEPT course-web:80", size=18)

    eth = c.box(1320, 380, 200, 330, GREEN, "eth0", "host address")
    net = c.node(1320, 220, 200, 100, SLATE, "internet", "globe", size=19)
    prox = c.box(110, 790, 280, 90, BLUE, "userland proxy", "localhost:8886", size=18)

    c.connect(ca, br, "", n=1, sa="right", sb="left", fa=0.5, fb=(310 - 260) / 330)
    c.connect(br, rt, "", sa="right", sb="left", fa=(305 - 260) / 330, fb=0.5)
    c.connect(rt, masq)
    c.connect(masq, eth, "", n=2, sa="right", sb="left", fa=0.5, fb=(420 - 380) / 330)
    c.connect(eth, net)
    c.connect(masq, ct, "", n=3, col=ORANGE, dashed=True)
    c.connect(eth, dnat, "", n=4, sa="left", sb="right", fa=(700 - 380) / 330, fb=0.5)
    c.connect(dnat, fwd, "", n=5)
    c.arrow([(780, 830), (640, 830), (640, 590)])
    c.connect(br, cw, "", sa="left", sb="right", fa=(530 - 260) / 330, fb=0.5)
    c.arrow([(390, 835), (520, 835), (520, 590)], n=6, at=(520, 700))
    c.save(OUT, "0.5-nat")


bridge()
dns()
two_networks()
nat()
