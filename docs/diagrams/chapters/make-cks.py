#!/usr/bin/env python3
"""Draw the diagrams for the security modules (platform-engineering/practice-cluster.md and modules 38 to 44) with the kit in ../bbg.py.

  cks-practice-cluster   the two kind nodes, the Lima VM, and what runs on each
  cks-supply-chain       where each supply chain check sits, from Dockerfile to node
  cks-runtime-layers     what seccomp, AppArmor and Falco do with one system call
  cks-netpol-enforce     how a NetworkPolicy becomes packet filter rules on every node (01)
  cks-kubelet-ports      the kubelet's checked port 10250 and its unchecked port 10255 (01)
  cks-api-chain          one API request through authentication, authorization and admission (02)
  cks-static-pod-loop    how the kubelet runs a static pod, and where crictl reads its logs (02)
  cks-node-limits        the Node authorizer and NodeRestriction around one kubelet (03)
  cks-encryption-rest    a Secret encrypted by the API server before etcd stores it (04)
  cks-sandbox-kernel     who answers a container's syscalls with runc and with gVisor (04)
  cks-image-policy       the ImagePolicyWebhook call, and what defaultAllow does when it fails (05)
  cks-audit-pipeline     audit stages, the policy's level, and the backends (06)
  cks-falco-path         one syscall from a container to a Falco alert (06)

Run from anywhere: python3 docs/diagrams/chapters/make-cks.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def practice_cluster():
    c = Canvas(1600, 1000)
    c.title("The practice cluster", "and the Lima VM")
    c.subtitle("Two kind nodes are containers on Docker's shared kernel. The Lima VM brings its own.")

    c.frame(40, 150, 1520, 820, "Your Mac", "host")
    you = c.node(70, 210, 220, 110, SLATE, "terminal", "terminal", "./lab.sh practice")

    dock = c.frame(330, 200, 1200, 430, "Docker engine", "plain", icon="box")
    cp = c.frame(360, 250, 560, 300, "practice-control-plane", "node")
    c.box(385, 300, 510, 80, PURPLE, "static pods", "API server, etcd, scheduler")
    c.box(385, 395, 160, 70, GREEN, "Calico", size=17)
    c.box(560, 395, 160, 70, RED, "image policy", size=16)
    c.box(735, 395, 160, 70, TEAL, "scanners", size=17)
    c.text(385, 520, "etcdctl, trivy, kube-bench, kubesec, bom", 15, SOFT)
    c.step(cp.x, cp.y, 1)
    w1 = c.frame(950, 250, 550, 300, "practice-worker", "node")
    c.box(975, 300, 500, 80, SLATE, "your pods", "the task workloads")
    for i, (t, col) in enumerate([("Calico", GREEN), ("runc", TEAL), ("gVisor", PINK), ("Falco", RED)]):
        c.box(975 + i * 127, 395, 115, 70, col, t, size=16)
    c.step(w1.x, w1.y, 2)
    c.band(360, 565, 1140, 50, GREEN, "one shared kernel: no AppArmor, no WireGuard", size=16, lx=360, ly=590)

    lima = c.frame(330, 670, 1200, 270, "Lima VM", "plain", icon="box")
    c.frame(360, 715, 1140, 150, "cks-lima: one-node cluster", "node")
    for i, (t, col) in enumerate([("control plane", PURPLE), ("Cilium", GREEN), ("AppArmor", RED), ("WireGuard", PINK)]):
        c.box(385 + i * 280, 765, 255, 75, col, t, size=18)
    c.band(360, 880, 1140, 45, GREEN, "its own Linux kernel", size=16, lx=360, ly=902)

    c.connect(you, dock, "", sa="right", sb="left", fa=0.5, fb=(265 - 200) / 430, pos="above")
    c.connect(you, lima, "limactl shell", sa="bottom", sb="left", fa=0.5, fb=0.5, pos="right", at=(180, 700))
    c.save(OUT, "cks-practice-cluster")


def supply_chain():
    c = Canvas(1600, 760)
    c.title("Supply chain", "checks")
    c.subtitle("Each check catches a different mistake, at a different place.")

    places = [("your repo", SLATE, "Dockerfile,\nmanifest", "kubesec", "scores settings"),
              ("CI build", SLATE, "image", "trivy, bom", "CVEs, SBOM"),
              ("registry", ORANGE, "pushed image", "cosign", "signature"),
              ("API server", PURPLE, "pod spec", "admission", "trusted registries"),
              ("node", TEAL, "running pod", "Falco", "behaviour")]
    arts = []
    for i, (place, col, art, chk, sub) in enumerate(places):
        x = 40 + i * 308
        f = c.frame(x, 160, 288, 540, place, "plain", col=col, fill=pastel(col))
        a = c.box(x + 24, 240, 240, 110, col, art, size=18)
        k = c.node(x + 24, 470, 240, 120, RED, chk, "shield", sub, size=19)
        c.line([(x + 144, 470), (x + 144, 350)], RED, 1.8, True)
        c.step(f.x, f.y, i + 1)
        arts.append(a)
    for a, b in zip(arts, arts[1:]):
        c.connect(a, b)
    c.save(OUT, "cks-supply-chain")


def runtime_layers():
    c = Canvas(1600, 780)
    c.title("One system call,", "three guards")
    c.subtitle("seccomp and AppArmor block. Falco only watches and reports.")

    c.frame(40, 150, 1520, 600, "", "node", right="Node")
    c.text(70, 200, "user space", 17, SOFT, True)
    ctr = c.frame(80, 220, 330, 150, "pod", "pod")
    proc = c.box(105, 270, 280, 80, SLATE, "process", "calls open()")
    c.step(proc.x, proc.y, 1)
    fal = c.frame(1060, 220, 460, 150, "Falco", "plain", col=RED, icon="eye")
    rules = c.box(1085, 270, 200, 80, RED, "rules", size=18)
    out = c.box(1300, 270, 195, 80, SLATE, "alert", "journal", size=18)
    c.connect(rules, out, "")
    c.step(out.x + out.w, out.y, 5)

    c.frame(70, 450, 1460, 280, "kernel", "plain", col=GREEN, icon="chip")
    sc = c.box(100, 540, 300, 110, RED, "seccomp", "which syscall?")
    aa = c.box(480, 540, 300, 110, PINK, "AppArmor", "which file, capability?")
    wk = c.box(860, 540, 300, 110, GREEN, "syscall", "does the work")
    pr = c.box(1220, 540, 280, 110, GREEN, "eBPF probe", "copies the event")
    c.connect(proc, sc, "", sa="bottom", sb="top", fa=0.5, fb=(245 - 100) / 300)
    c.connect(sc, aa, "", n=2)
    c.connect(aa, wk, "", n=3)
    c.connect(wk, pr, "", n=4, dashed=True)
    c.connect(pr, rules, "", sa="top", sb="bottom", fa=(1240 - 1220) / 280 if False else 0.2, fb=(1276 - 1085) / 200)
    for b in (sc, aa):
        c.mark(b.cx, b.b + 40, ok=False, r=12)
        c.text(b.cx + 20, b.b + 46, "blocked: EPERM", 16, DEEP[RED], True)
    c.save(OUT, "cks-runtime-layers")


def netpol_enforce():
    c = Canvas(1600, 920)
    c.title("NetworkPolicy", "in the CNI")
    c.subtitle("The API server only stores the policy. An agent on every node turns it into packet filter rules.")

    c.frame(40, 150, 260, 200, "Your Mac", "host")
    you = c.box(65, 210, 210, 100, SLATE, "kubectl apply", "NetworkPolicy", size=18)
    c.frame(340, 150, 1220, 200, "control plane", "group")
    api = c.node(700, 200, 300, 110, PURPLE, "API server", "server", "stores it in etcd")
    c.connect(you, api, "", n=1, sa="right", sb="left", fa=0.5, fb=(260 - 200) / 110, at=(500, 260))

    c.frame(340, 390, 1220, 500, "", "node", right="every node")
    pa = c.frame(380, 450, 260, 120, "pod A", "pod")
    c.box(400, 495, 220, 55, SLATE, "client", size=17)
    agent = c.frame(700, 450, 300, 120, "CNI agent pod", "pod")
    c.box(720, 495, 260, 55, TEAL, "Felix or cilium-agent", size=16)
    pb = c.frame(1260, 450, 260, 120, "pod B", "pod")
    c.box(1280, 495, 220, 55, SLATE, "server", size=17)
    c.frame(370, 620, 1160, 240, "kernel", "plain", col=GREEN, icon="chip")
    dnat = c.box(400, 690, 320, 110, GREEN, "Service DNAT", "kube-proxy rule")
    filt = c.box(820, 690, 320, 110, GREEN, "packet filter", "iptables or eBPF")

    c.connect(api, agent, "watch", n=2, sa="bottom", sb="top", fa=0.5, fb=0.5, pos="right")
    c.connect(agent, filt, "write rules", n=3, sa="bottom", sb="top", fa=0.5, fb=(850 - 820) / 320, pos="right",
              at=(850, 595))
    c.connect(pa, dnat, "send", n=4, sa="bottom", sb="top", fa=0.5, fb=(510 - 400) / 320, pos="right")
    c.connect(dnat, filt, "real pod IP", n=5, pos="above")
    c.connect(filt, pb, "allow or drop", n=6, sa="right", sb="bottom", fa=0.5, fb=0.5, pos="above", at=(1250, 745))
    c.save(OUT, "cks-netpol-enforce")


def kubelet_ports():
    c = Canvas(1600, 720)
    c.title("The kubelet's", "two doors")
    c.subtitle("Port 10250 checks every caller. Port 10255 checks nobody.")

    caller = c.node(40, 330, 260, 110, SLATE, "caller", "person", "any pod or host")
    c.frame(360, 150, 790, 530, "", "node", right="Node")
    kub = c.frame(420, 200, 690, 440, "kubelet", "plain", col=TEAL, icon="server")
    an = c.box(520, 290, 280, 90, RED, "authenticate", "cert or token")
    az = c.box(520, 440, 280, 90, RED, "authorize", "mode Webhook")
    data = c.box(860, 230, 220, 160, TEAL, "pod data", "logs, exec,\npod specs")
    c.port((420, 335), "10250 HTTPS", SLATE, side="above", size=14)
    c.rect(414, 244, 12, 12, RED, WHITE, 3, 1.8)
    c.chip(300, 222, "10255 HTTP", RED, anchor="middle", size=14)
    c.frame(1190, 380, 370, 210, "control plane", "group")
    api = c.node(1220, 440, 310, 110, PURPLE, "API server", "server", "RBAC decides")

    c.connect(caller, an, "", n=1, sa="right", sb="left", fa=(335 - 330) / 110, fb=0.5, at=(360, 335))
    c.connect(an, az, "", n=2, pos="right")
    c.connect(az, api, "may it?", n=3, sa="right", sb="left", fa=0.7, fb=(503 - 440) / 110, pos="below",
              at=(1000, 503))
    c.line([(800, 465), (960, 465), (960, 390)], LINE, AW, head=True)
    c.step(960, 425, 4)
    c.line([(170, 330), (170, 250), (860, 250)], RED, AW, dashed=True, head=True)
    c.text(650, 238, "no checks at all", 16, DEEP[RED], True, "middle", halo=True)
    c.save(OUT, "cks-kubelet-ports")


def api_chain():
    c = Canvas(1600, 1000)
    c.title("One API request,", "six steps")
    c.subtitle("Each gate either passes the request on or ends it with an error.")

    c.frame(40, 150, 270, 220, "Your Mac", "host")
    kc = c.box(65, 220, 220, 100, SLATE, "kubectl", "create, apply")
    c.frame(360, 150, 760, 820, "control plane", "group")
    c.frame(390, 200, 700, 630, "API server", "plain", col=PURPLE, icon="server")
    gates = [("authentication", "who are you?", RED), ("authorization", "may you?", RED),
             ("mutating admission", "may change it", PINK), ("schema validation", "well formed?", PURPLE),
             ("validating admission", "accept it?", PINK)]
    bs = []
    for i, (t, sub, col) in enumerate(gates):
        b = c.box(560, 255 + i * 112, 380, 82, col, t, sub, size=18)
        c.step(b.x, b.y, i + 1)
        if bs:
            c.connect(bs[-1], b)
        bs.append(b)
    etcd = c.node(560, 870, 380, 80, ORANGE, "etcd", "db", "stored")
    c.connect(bs[-1], etcd, "write", n=6, pos="right", at=(750, 850))
    c.connect(kc, bs[0], "", sa="right", sb="left", fa=0.5, fb=0.4, via=[(470, 270), (470, 288)])
    c.line([(560, 312), (420, 312), (420, 330), (285, 330)], RED, 1.8, True, head=True)
    c.text(430, 360, "401", 16, DEEP[RED], True)
    c.line([(560, 424), (440, 424), (440, 310)], RED, 1.8, True)
    c.text(450, 450, "403", 16, DEEP[RED], True)

    c.frame(1170, 340, 390, 480, "webhook servers", "group")
    mw = c.box(1200, 479, 330, 82, PINK, "mutating webhook", "patch")
    vw = c.box(1200, 703, 330, 82, PINK, "validating webhook", "allow or deny")
    c.connect(bs[2], mw, "", both=True)
    c.connect(bs[4], vw, "", both=True)
    c.save(OUT, "cks-api-chain")


def static_pod_loop():
    c = Canvas(1600, 720)
    c.title("Static pods,", "the repair loop")
    c.subtitle("The kubelet runs what the folder says. No API server takes part.")

    c.frame(40, 150, 1520, 530, "", "node", right="Node practice-control-plane")
    you = c.node(80, 220, 260, 110, SLATE, "You", "terminal", "ssh on the node")
    fold = c.frame(430, 200, 420, 160, "/etc/kubernetes/manifests", "plain", col=ORANGE, icon="doc")
    yaml = c.box(455, 255, 370, 80, ORANGE, "kube-apiserver.yaml", size=18)
    kub = c.node(960, 220, 260, 110, TEAL, "kubelet", "server", "watches the folder")
    ctd = c.node(1270, 220, 250, 110, TEAL, "containerd", "box", "CRI")
    pod = c.frame(1170, 470, 350, 170, "static pod", "pod")
    ctr = c.box(1195, 520, 300, 90, PURPLE, "kube-apiserver", "new flags")
    logs = c.frame(430, 470, 420, 170, "/var/log/pods/", "plain", col=ORANGE, icon="doc")
    lg = c.box(455, 525, 370, 80, ORANGE, "container output", size=18)
    crictl = c.node(80, 500, 260, 110, SLATE, "crictl", "terminal", "logs, ps")

    c.connect(you, yaml, "edit", n=1, sa="right", sb="left", fa=0.5, fb=(275 - 255) / 80, pos="above")
    c.connect(fold, kub, "notices", n=2, sa="right", sb="left", fa=(275 - 200) / 160, pos="above")
    c.connect(kub, ctd, "", n=3, at=(1245, 275))
    c.connect(ctd, ctr, "runs", n=4, sa="bottom", sb="top", fa=0.5, fb=(1395 - 1195) / 300, pos="right")
    c.connect(ctr, lg, "writes", n=5, sa="left", sb="right", pos="above")
    c.connect(lg, crictl, "reads", n=6, sa="left", sb="right", fa=0.5, fb=0.4, pos="above", at=(385, 565))
    c.connect(crictl, you, "", dashed=True, col=DIM)
    c.save(OUT, "cks-static-pod-loop")


def node_limits():
    c = Canvas(1600, 760)
    c.title("A kubelet's", "two limits")
    c.subtitle("The Node authorizer limits what a kubelet reads. NodeRestriction limits what it writes.")

    c.frame(40, 150, 320, 300, "Node practice-worker", "node")
    kub = c.node(70, 220, 260, 110, TEAL, "kubelet", "server", "node certificate")
    c.chip(200, 380, "system:node:practice-worker", TEAL, anchor="middle", size=14)

    c.frame(420, 150, 1140, 580, "control plane", "group")
    c.frame(450, 200, 820, 490, "API server", "plain", col=PURPLE, icon="server")
    na = c.box(490, 260, 340, 120, RED, "Node authorizer", "only its own node's\nobjects")
    nr = c.box(890, 260, 340, 120, RED, "NodeRestriction", "only its own Node and\npods, no protected labels")
    c.step(na.x, na.y, 2)
    c.step(nr.x, nr.y, 3)
    etcd = c.node(1310, 260, 220, 120, ORANGE, "etcd", "db")
    c.connect(kub, na, "request", n=1, sa="right", sb="left", fa=0.5, fb=(275 - 260) / 120, pos="above", at=(395, 275))
    c.connect(na, nr, "allowed")
    c.connect(nr, etcd, "allowed", pos="above")
    r1 = c.box(490, 520, 340, 90, RED, "other node's Secret", "403", size=18)
    r2 = c.box(890, 520, 340, 90, RED, "protected label", "403", size=18)
    c.connect(na, r1, "", dashed=True, col=RED)
    c.connect(nr, r2, "", dashed=True, col=RED)
    c.mark(660, 460, ok=False, r=12)
    c.mark(1060, 460, ok=False, r=12)
    c.save(OUT, "cks-node-limits")


def encryption_rest():
    c = Canvas(1600, 860)
    c.title("Secrets", "at rest")
    c.subtitle("The API server encrypts the value before etcd ever sees it.")

    c.frame(40, 150, 270, 220, "Your Mac", "host")
    cl = c.box(65, 220, 220, 100, SLATE, "kubectl", "create secret")
    c.frame(360, 150, 1200, 680, "control plane", "group")
    api = c.frame(390, 200, 600, 590, "API server", "plain", col=PURPLE, icon="server")
    cfg = c.frame(420, 380, 540, 380, "EncryptionConfiguration", "plain", col=RED, icon="doc")
    p1 = c.box(450, 440, 480, 90, RED, "1. aescbc, key1", "writes use the first")
    p2 = c.box(450, 550, 480, 80, SLATE, "2. identity", "reads old plain values")
    kms = c.box(450, 650, 480, 80, PINK, "or KMS plugin", "key outside the cluster")
    c.text(420, 300, "loaded at start with", 16, SOFT)
    c.text(420, 322, "--encryption-provider-config", 15, SOFT, mono=True)
    etcd = c.frame(1050, 380, 480, 250, "etcd", "plain", col=ORANGE, icon="db")
    c.box(1075, 440, 430, 150, ORANGE, "k8s:enc:aescbc:v1:key1:", "then ciphertext", size=17)
    c.connect(cl, api, "plain text over TLS", n=1, sa="right", sb="left", fa=0.5, fb=(270 - 200) / 590,
              pos="above", at=(335, 270))
    c.step(p1.x, p1.y, 2)
    c.connect(p1, etcd, "ciphertext", n=3, sa="right", sb="left", fb=(485 - 380) / 250, pos="above", at=(1000, 485))
    c.save(OUT, "cks-encryption-rest")


def sandbox_kernel():
    c = Canvas(1600, 900)
    c.title("One syscall,", "two runtimes")
    c.subtitle("A runc container talks to the host kernel. gVisor answers most calls itself.")

    c.frame(40, 150, 1520, 720, "", "node", right="Node practice-worker")
    a = c.frame(100, 200, 560, 380, "pod with runc", "pod")
    ca = c.box(130, 260, 500, 100, SLATE, "app process")
    b = c.frame(900, 200, 600, 380, "pod with runsc (gVisor)", "pod")
    cb = c.box(930, 260, 540, 100, SLATE, "app process")
    sen = c.box(930, 420, 540, 120, PINK, "Sentry", "kernel in user space, written in Go")
    filt = c.band(70, 630, 1460, 70, RED, "syscall filters: seccomp, AppArmor", "", "shield", lx=560, ly=665)
    ker = c.band(70, 730, 1460, 110, GREEN, "host kernel", "shared by every pod on the node", "chip", lx=560)
    c.line([(380, 360), (380, 730)], LINE, 4, head=True)
    c.text(400, 470, "every syscall", 18, INK, True, halo=True)
    c.connect(cb, sen, "syscalls", pos="right")
    c.line([(1200, 540), (1200, 730)], LINE, 2, head=True)
    c.text(1220, 600, "a few syscalls", 18, INK, True, halo=True)
    c.save(OUT, "cks-sandbox-kernel")


def image_policy():
    c = Canvas(1600, 860)
    c.title("Image policy", "verdicts")
    c.subtitle("The API server asks a back end about the images of every new pod.")

    c.frame(40, 150, 270, 220, "Your Mac", "host")
    cl = c.box(65, 220, 220, 100, SLATE, "kubectl", "create pod")
    c.frame(360, 150, 1200, 680, "", "node", right="Node practice-control-plane")
    api = c.frame(400, 200, 470, 300, "API server", "plain", col=PURPLE, icon="server")
    plug = c.box(430, 260, 410, 200, PINK, "ImagePolicyWebhook", "admission plugin\ncaches allowTTL, denyTTL")
    be = c.node(1100, 260, 420, 200, RED, "policy back end", "shield", "localhost:8443")
    c.connect(cl, api, "pod", n=1, sa="right", sb="left", fa=0.5, fb=(270 - 200) / 300, pos="above", at=(335, 270))
    c.connect(plug, be, "ImageReview", n=2, sa="right", sb="left", fa=0.3, fb=0.3, pos="above", at=(970, 320))
    c.connect(be, plug, "allowed or denied", n=3, sa="left", sb="right", fa=0.7, fb=0.7, pos="below", at=(970, 400))
    d = c.diamond(635, 640, 300, 150, ORANGE, "back end\ndown?")
    c.connect(plug, d, "", n=4, sa="bottom", sb="top", at=(635, 530))
    fc = c.box(1000, 560, 520, 70, GREEN, "defaultAllow: false", "fail closed: pod refused", size=18)
    fo = c.box(1000, 660, 520, 70, RED, "defaultAllow: true", "fail open: pod admitted", size=18)
    c.connect(d, fc, "", sa="right", sb="left", fa=0.5, fb=0.5, mid=900)
    c.connect(d, fo, "", sa="right", sb="left", fa=0.5, fb=0.5, mid=900)
    c.save(OUT, "cks-image-policy")


def audit_pipeline():
    c = Canvas(1600, 820)
    c.title("The audit", "pipeline")
    c.subtitle("Each request makes events. The policy picks a level. A backend keeps them.")

    c.frame(40, 220, 260, 200, "Your Mac", "host")
    cl = c.box(65, 280, 210, 100, SLATE, "kubectl get", "a request")
    c.frame(340, 150, 1220, 600, "", "node", right="control plane")
    api = c.frame(380, 200, 1140, 520, "API server", "plain", col=PURPLE, icon="server")
    c.text(410, 290, "stages of one request", 17, SOFT, True)
    st = []
    for i, (t, sub) in enumerate([("RequestReceived", ""), ("ResponseStarted", "only for watches"),
                                  ("ResponseComplete", ""), ("Panic", "only on a crash")]):
        st.append(c.box(410, 310 + i * 100, 320, 80, PURPLE, t, sub or None, size=18))
    c.step(410, 310, 1)
    pol = c.frame(800, 300, 320, 360, "audit policy", "plain", col=RED, icon="list")
    for i, t in enumerate(["rule 1: level None", "rule 2: Metadata", "rule 3: RequestResponse"]):
        c.box(820, 360 + i * 90, 280, 70, RED, t, size=16)
    c.text(820, 645, "first match wins", 16, DEEP[RED], True)
    c.step(pol.x, pol.y, 2)
    lf = c.node(1180, 330, 310, 100, ORANGE, "log file", "doc", "--audit-log-path")
    wh = c.node(1180, 500, 310, 100, ORANGE, "webhook", "globe", "outside service")
    c.connect(cl, st[0], "", sa="right", sb="left", fa=0.5, fb=0.5, via=[(340, 330), (340, 350)])
    c.connect(Box(730, 310, 1, 380), pol, "events", sa="right", sb="left", pos="above")
    c.connect(pol, lf, "level", n=3, sa="right", sb="left", fa=(380 - 300) / 360, pos="above", at=(1150, 380))
    c.connect(pol, wh, "", sa="right", sb="left", fa=(550 - 300) / 360)
    c.save(OUT, "cks-audit-pipeline")


def falco_path():
    c = Canvas(1600, 790)
    c.title("From syscall", "to alert")
    c.subtitle("Falco reads a copy of each event. It never blocks the call.")

    c.frame(40, 150, 1520, 610, "", "node", right="Node practice-worker")
    c.text(70, 200, "user space", 17, SOFT, True)
    pod = c.frame(80, 220, 330, 160, "pod", "pod")
    sh = c.box(105, 275, 280, 80, SLATE, "bash", "a shell starts")
    fal = c.frame(560, 220, 640, 200, "Falco", "plain", col=RED, icon="eye")
    ctx = c.box(590, 280, 180, 110, RED, "context", "process tree,\npod")
    eng = c.box(800, 280, 180, 110, RED, "rule engine", "lists, macros,\nrules")
    outb = c.box(1010, 280, 170, 110, TEAL, "outputs", "stdout, file,\nHTTP")
    c.connect(ctx, eng)
    c.connect(eng, outb, "", n=4, at=(995, 335))
    you = c.node(1270, 270, 260, 110, SLATE, "You", "terminal", "read the alert")
    c.connect(outb, you, "", n=5, sa="right", sb="left", fb=0.5, at=(1225, 335))

    c.frame(70, 480, 1460, 250, "kernel", "plain", col=GREEN, icon="chip")
    sys_ = c.box(100, 560, 300, 110, GREEN, "execve()", "the syscall")
    drv = c.box(520, 560, 300, 110, GREEN, "driver", "modern eBPF probe")
    buf = c.box(940, 560, 300, 110, ORANGE, "ring buffer", "copies of events")
    c.connect(sh, sys_, "", n=1, sa="bottom", sb="top", fa=0.5, fb=(245 - 100) / 300)
    c.connect(sys_, drv, "", n=2)
    c.connect(drv, buf, "copy", pos="above")
    c.connect(buf, ctx, "", n=3, sa="top", sb="bottom", fa=(680 - 940) / 300 if False else 0.1, fb=0.5,
              via=[(970, 520), (680, 520)])
    c.save(OUT, "cks-falco-path")


if __name__ == "__main__":
    practice_cluster()
    supply_chain()
    runtime_layers()
    netpol_enforce()
    kubelet_ports()
    api_chain()
    static_pod_loop()
    node_limits()
    encryption_rest()
    sandbox_kernel()
    image_policy()
    audit_pipeline()
    falco_path()
