#!/usr/bin/env python3
"""Draw the diagrams for platform-engineering/31-debugging-envoy.md in ByteByteGo style (see ../bbg.py).

  31-envoy-chain   listener, route, cluster, endpoint, and the Istio resource behind each
  31-flag-where    which proxy writes which response flag

Run from anywhere: python3 docs/diagrams/chapters/make-31.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def envoy_chain():
    c = Canvas(1700, 820)
    c.title("Four lookups inside", "every Envoy")
    c.subtitle("The client sidecar's path for GET httpbin:8000/headers, and where each piece comes from.")

    c.node(40, 230, 220, 100, SLATE, "curl", "cube", "httpbin:8000")
    xs = [340, 680, 1020, 1360]
    names = [("listener", "0.0.0.0_8000"), ("route", "8000"),
             ("cluster", "outbound|8000||httpbin"), ("endpoint", "10.42.0.3:8080")]
    for i, (x, (n, sub)) in enumerate(zip(xs, names)):
        c.node(x, 230, 300, 100, BLUE, n, None, sub, size=26)
    c.arrow([(260, 280), (340, 280)], "", dashed=False)
    c.arrow([(640, 280), (680, 280)], "", n=1, at=(660, 280), dashed=False)
    c.arrow([(980, 280), (1020, 280)], "", n=2, at=(1000, 280), dashed=False)
    c.arrow([(1320, 280), (1360, 280)], "", n=3, at=(1340, 280), dashed=False)

    asks = ["which port?", "which host, path?", "which pool, policy?", "which pod IP?"]
    for x, t in zip(xs, asks):
        c.text(x + 150, 380, t, 19, SOFT, True, "middle")

    srcs = [("Service port", SLATE), ("VirtualService\nHTTPRoute", PURPLE),
            ("DestinationRule\nsubsets, pools", PURPLE), ("EndpointSlice\nready pods", SLATE)]
    for x, (t, col) in zip(xs, srcs):
        c.outline(x, 520, 300, 100, col, t)
        c.arrow([(x + 150, 520), (x + 150, 400)], "", col=SOFT)

    cmds = ["listener --port", "route --name", "cluster --fqdn", "endpoint --cluster"]
    for x, t in zip(xs, cmds):
        c.text(x + 150, 680, t, 18, INK, True, "middle")
    c.note(340, 740, ["istioctl proxy-config ... on the line above each box"], 17)
    c.save(OUT, "31-envoy-chain")


def flag_where():
    c = Canvas(1700, 760)
    c.title("Which proxy writes", "the flag")
    c.subtitle("Read the log of the proxy that hit the problem. The other side often shows a plain 503.")

    c.group(40, 180, 760, 520, "pod client")
    c.node(80, 230, 200, 100, SLATE, "curl", "cube")
    c.node(420, 230, 340, 100, BLUE, "client sidecar", "shield", "outbound")
    c.arrow([(280, 280), (420, 280)], "", dashed=False)
    for i, (f, t) in enumerate([("NR", "no route matched"), ("UH", "no healthy endpoint"),
                                ("UO", "pool overflow"), ("URX", "retries ran out"), ("UT", "route timeout")]):
        c.outline(420, 370 + i * 62, 340, 50, RED, f"{f}  {t}", size=17)

    c.group(900, 180, 760, 520, "pod httpbin")
    c.node(940, 230, 340, 100, BLUE, "server sidecar", "shield", "inbound :15006")
    c.node(1420, 230, 200, 100, SLATE, "httpbin", "cube", ":8080")
    c.arrow([(1280, 280), (1420, 280)], "", dashed=False)
    for i, (f, t) in enumerate([("UF", "app port refused"), ("403", "RBAC denied")]):
        c.outline(940, 370 + i * 62, 340, 50, RED, f"{f}  {t}", size=17)

    c.arrow([(760, 280), (940, 280)], "mTLS", at=(850, 280), pos="above", dashed=False)
    c.save(OUT, "31-flag-where")


if __name__ == "__main__":
    envoy_chain()
    flag_where()
