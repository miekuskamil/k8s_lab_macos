#!/usr/bin/env python3
"""Draw the diagrams for course module 3.16 (the life of an outbound request) with the kit in ../bbg.py.

  3.16-outbound-overview   the whole path: pod, node container, OrbStack VM, Mac, router
  3.16-pod-and-node        inside the pod and the node: redirect, ztunnel, veth, bridge, chains
  3.16-nat-ladder          the source address after each layer, and conntrack on the way back
  3.16-controlled-egress   with a ServiceEntry, the waypoint opens the outside connection

The circled numbers match the numbered lists in module 3.16. Addresses come from one
test run of the lab.

Run from anywhere: python3 docs/diagrams/chapters/make-3.16.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def overview():
    c = Canvas(1600, 1080)
    c.title("The life of an", "outbound request")
    c.subtitle("curl https://example.com from a pod. Each layer is a private network, so each exit rewrites the source.")

    c.frame(40, 150, 1210, 890, "Your Mac", "host")
    c.frame(70, 200, 870, 810, "OrbStack Linux VM", "host", icon="box")
    c.frame(100, 250, 610, 730, "k3d node container", "node")

    c.frame(130, 300, 300, 330, "client pod", "pod")
    curl = c.box(150, 350, 260, 64, SLATE, "curl", "example.com:443")
    zt = c.box(150, 460, 260, 64, BLUE, "ztunnel socket", "DNS :15053, TCP :15001", size=18)
    peth = c.box(150, 556, 260, 56, GREEN, "eth0", "10.42.0.204")

    c.frame(470, 410, 210, 140, "CoreDNS pod", "pod")
    dns = c.box(485, 460, 180, 64, TEAL, "CoreDNS", "10.43.0.10")
    ddns = c.box(485, 590, 180, 70, TEAL, "Docker DNS", "127.0.0.11")

    cni = c.box(130, 680, 300, 60, GREEN, "cni0 bridge", "10.42.0.1")
    k = c.band(130, 775, 550, 90, GREEN, "kernel NAT", "masquerade to 192.168.107.2", "filter")
    neth = c.box(460, 890, 220, 64, GREEN, "eth0", "192.168.107.2")

    br = c.box(750, 890, 170, 64, GREEN, "Docker bridge", "192.168.107.1", size=17)
    vnat = c.box(750, 750, 170, 100, GREEN, "Docker NAT", "masquerade", size=18)
    veth = c.box(750, 610, 170, 64, GREEN, "VM eth0", "192.168.139.2", size=18)

    orb = c.box(990, 600, 230, 84, BLUE, "OrbStack app", "new connection")
    en0 = c.box(990, 450, 230, 70, GREEN, "en0", "192.168.1.132")

    rt = c.box(1300, 450, 260, 70, GREEN, "home router", "NAT")
    site = c.node(1300, 250, 260, 90, SLATE, "example.com", "globe", "172.66.147.243", size=20)

    c.connect(zt, dns, "", n=1, at=(450, 492))
    c.connect(dns, ddns, "", dashed=True, col=TEAL)
    c.connect(curl, zt, "redirect", n=2, pos="right")
    c.connect(zt, peth)
    c.connect(peth, cni, "veth pair", n=3, pos="right", at=(280, 650))
    c.connect(cni, k, "", sa="bottom", sb="top", fa=0.5, fb=150 / 550)
    c.step(280, 758, 4)
    c.connect(k, neth, "", sa="bottom", sb="top", fa=(570 - 130) / 550, fb=0.5)
    c.connect(neth, br)
    c.connect(br, vnat)
    c.step(835, 870, 5)
    c.connect(vnat, veth)
    c.connect(veth, orb, "", n=6, sa="right", sb="left", fa=0.5, fb=(642 - 600) / 84, at=(955, 642))
    c.connect(orb, en0)
    c.connect(en0, rt, "", n=7, at=(1260, 485))
    c.connect(rt, site, "public IP", pos="right")
    c.step(1010, 790, 8, col=TEAL, ink=WHITE)
    c.text(1040, 784, "replies retrace", 18, INK, True)
    c.text(1040, 808, "every step", 18, INK, True)
    c.text(1040, 834, "conntrack undoes", 17, SOFT)
    c.text(1040, 856, "each rewrite", 17, SOFT)
    c.save(OUT, "3.16-outbound-overview")


def pod_and_node():
    c = Canvas(1600, 940)
    c.title("Inside the pod", "and the node")
    c.subtitle("ztunnel opens the real connection inside the pod. The node routes it and masquerades the source.")

    c.frame(40, 150, 500, 750, "client pod netns", "pod")
    app = c.box(80, 210, 420, 72, SLATE, "curl", "to 172.66.147.243:443")
    red = c.box(80, 340, 420, 72, GREEN, "nat ISTIO_OUTPUT", "REDIRECT to :15001")
    zt = c.box(80, 470, 420, 72, BLUE, "ztunnel", "same destination, own port")
    rte = c.box(80, 600, 420, 72, GREEN, "pod route", "default via 10.42.0.1")
    eth = c.box(80, 760, 420, 72, GREEN, "eth0", "10.42.0.204")

    c.frame(600, 150, 800, 750, "k3d node container", "node")
    c.frame(620, 210, 760, 160, "", "plain", col=GREEN)
    c.text(900, 356, "kernel: iptables rules, nf_tables backend", 16, DEEP[GREEN], True)
    fwd = c.box(640, 230, 220, 90, GREEN, "FORWARD", "netpol, FLANNEL-FWD", size=18)
    kp = c.box(900, 230, 210, 90, GREEN, "KUBE-POSTROUTING", "no mark: RETURN", size=16)
    fl = c.box(1160, 230, 200, 90, GREEN, "FLANNEL-POSTRTG", "MASQUERADE", size=16)
    nrt = c.box(640, 450, 220, 80, GREEN, "node route", "default via eth0", size=18)
    cni = c.box(640, 600, 220, 72, GREEN, "cni0 bridge", "10.42.0.1", size=18)
    vth = c.box(640, 760, 220, 72, GREEN, "veth", "veth7e313e2f", size=18)
    neth = c.box(1160, 600, 200, 80, GREEN, "eth0", "192.168.107.2", size=18)
    br = c.box(1440, 600, 130, 80, SLATE, "Docker\nbridge", size=17)

    c.connect(app, red, "", n=1)
    c.connect(red, zt, "", n=2)
    c.connect(zt, rte, "", n=3)
    c.connect(rte, eth)
    c.connect(eth, vth, "", n=4)
    c.connect(vth, cni)
    c.connect(cni, nrt)
    c.connect(nrt, fwd, "", n=5)
    c.connect(fwd, kp)
    c.connect(kp, fl, "", n=6, at=(1135, 275))
    c.connect(fl, neth, "", sa="bottom", sb="top", fa=0.5, fb=0.5)
    c.connect(neth, br, "", n=7, at=(1400, 640))
    c.text(1260, 720, "src 192.168.107.2", 17, DEEP[GREEN], True, "middle")
    c.save(OUT, "3.16-pod-and-node")


def nat_ladder():
    c = Canvas(1600, 800)
    c.title("Who rewrites", "the source")
    c.subtitle("Each layer swaps the source for its own address and writes the swap down, so the reply finds its way back.")

    cols = [
        ("client pod", "ztunnel", "new connection", BLUE, "10.42.0.204", "port 52946", "conntrack", "undoes redirect"),
        ("k3d node", "masquerade", "flannel rule", GREEN, "192.168.107.2", "port 25932", "conntrack", "node table"),
        ("OrbStack VM", "masquerade", "Docker rule", GREEN, "192.168.139.2", "port 25932", "conntrack", "VM table"),
        ("Your Mac", "OrbStack app", "new socket", BLUE, "192.168.1.132", "port 56087", "two sockets", "copies bytes"),
        ("home router", "NAT", "router rule", GREEN, "public IP", "router's port", "NAT table", "router memory"),
    ]
    w, gap, x0 = 256, 50, 60
    tr, ad, mem = [], [], []
    for i, (fl, tl, ts, tc, a, asub, ml, msub) in enumerate(cols):
        x = x0 + i * (w + gap)
        c.frame(x, 150, w, 570, fl, "pod" if i == 0 else ("node" if i == 1 else ("host" if i < 4 else "plain")),
                icon=("box" if i == 2 else None))
        tr.append(c.box(x + 18, 220, w - 36, 90, tc, tl, ts, size=19))
        ad.append(c.box(x + 18, 400, w - 36, 90, SLATE, a, asub, size=19))
        mem.append(c.box(x + 18, 600, w - 36, 90, ORANGE, ml, msub, size=19))
    for i in range(5):
        c.connect(tr[i], ad[i], "", n=i + 1)
        c.connect(ad[i], mem[i], "", dashed=True, col=ORANGE)
    for i in range(4):
        mx = x0 + (i + 1) * (w + gap) - gap / 2
        c.connect(ad[i], tr[i + 1], "", sa="right", sb="left", fa=0.5, fb=0.5, mid=mx)
    for i in range(4, 0, -1):
        c.connect(mem[i], mem[i - 1], "", col=TEAL, dashed=True, off=20)
        mx = x0 + i * (w + gap) - gap / 2
    for i in range(5):
        x = x0 + (4 - i) * (w + gap)
        c.step(x + w - 18, 600, 6 + i, col=TEAL, ink=WHITE)
    c.legend(380, 770, [(LINE, "request out, steps 1 to 5"), (TEAL, "reply back, steps 6 to 10", True)])
    c.save(OUT, "3.16-nat-ladder")


def controlled():
    c = Canvas(1600, 780)
    c.title("Controlled egress:", "the waypoint calls out")
    c.subtitle("With a ServiceEntry, ztunnel tunnels the call to the waypoint, and the waypoint opens the outside connection.")

    c.frame(40, 150, 1200, 590, "k3d node container", "node")
    c.frame(70, 200, 1140, 330, "namespace course-outbound", "ns", right="ambient")
    c.frame(100, 260, 420, 240, "client pod", "pod")
    curl = c.box(120, 310, 380, 64, SLATE, "curl", "http://httpbin.org")
    zt = c.box(120, 424, 380, 60, BLUE, "ztunnel socket", "DNS and :15001")
    c.frame(700, 260, 480, 240, "waypoint pod", "pod")
    wp = c.box(720, 310, 440, 174, BLUE, "waypoint", "TLS origination\n10.42.0.205")
    k = c.band(70, 600, 1140, 100, GREEN, "kernel NAT", "masquerade 10.42.0.205 to 192.168.107.2", "filter", lx=360)

    out = c.box(1290, 600, 270, 100, SLATE, "same path out", "Docker, OrbStack,\nrouter")
    site = c.node(1290, 250, 270, 100, SLATE, "httpbin.org", "globe", "real address :443", size=20)

    c.connect(curl, zt, "to 240.240.0.2:80", n=1, pos="right")
    c.connect(zt, wp, "HBONE :15008", n=2, sa="right", sb="left", fa=0.5, fb=(454 - 310) / 174, pos="above", at=(610, 454))
    c.connect(wp, k, "TLS to :443", n=3, sa="bottom", sb="top", fa=0.5, fb=(940 - 70) / 1140, pos="right", at=(940, 565))
    c.connect(k, out)
    c.connect(out, site, "", n=4, sa="top", sb="bottom")
    c.save(OUT, "3.16-controlled-egress")


if __name__ == "__main__":
    overview()
    pod_and_node()
    nat_ladder()
    controlled()
