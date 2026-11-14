#!/usr/bin/env python3
"""Draw the diagrams for the CKS track (certs/cks) in ByteByteGo style (see ../bbg.py).

  cks-practice-cluster   the two OrbStack machines, the Lima VM, and what runs on each
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
    c = Canvas(1800, 1000)
    c.title("The CKS", "practice clusters")
    c.subtitle("Two OrbStack machines on one kernel, and a Lima VM with its own.")

    c.node(60, 360, 280, 110, SLATE, "Your Mac", "laptop", "orb, limactl")

    c.group(440, 190, 620, 480, "cks-cp, control plane")
    c.node(480, 230, 540, 100, PURPLE, "Static pods", "server", "API server, etcd")
    c.outline(480, 370, 260, 80, GREEN, "Calico", "globe")
    c.outline(760, 370, 260, 80, BLUE, "Ingress", "globe")
    c.outline(480, 490, 260, 80, RED, "Image policy", "shield")
    c.outline(760, 490, 260, 80, TEAL, "Scanners", "eye")
    c.note(480, 610, ["etcdctl, trivy, kube-bench,", "kubesec, bom"])

    c.group(1160, 190, 580, 480, "cks-w1, worker")
    c.node(1200, 230, 500, 100, SLATE, "Your pods", "cube", "the task workloads")
    c.outline(1200, 370, 240, 80, GREEN, "Calico", "globe")
    c.outline(1460, 370, 240, 80, TEAL, "runc", "gear")
    c.outline(1200, 490, 240, 80, RED, "Falco", "eye")
    c.outline(1460, 490, 240, 80, PINK, "gVisor", "lock")

    c.arrow([(340, 415), (440, 415)], "shell", dashed=False, pos="above", at=(390, 415))
    c.arrow([(1060, 280), (1160, 280)], "kubelet", dashed=True, pos="above", at=(1110, 280))
    c.rect(440, 690, 1300, 30, DIM, "#2a2b33", rx=8, sw=1.5)
    c.text(1090, 712, "one shared OrbStack kernel: no AppArmor, no WireGuard", 17, SOFT, False, "middle")

    c.group(440, 770, 1300, 190, "cks-lima, one-node cluster in a Lima VM")
    c.outline(480, 830, 280, 80, PURPLE, "Control plane", "server")
    c.outline(800, 830, 280, 80, GREEN, "Cilium", "globe")
    c.outline(1120, 830, 280, 80, RED, "AppArmor", "shield")
    c.outline(1440, 830, 260, 80, PINK, "WireGuard", "lock")
    c.arrow([(200, 470), (200, 870), (440, 870)], "limactl shell", dashed=False, pos="above", at=(320, 870))
    c.save(OUT, "cks-practice-cluster")


def supply_chain():
    c = Canvas(1800, 620)
    c.title("Supply chain", "checks")
    c.subtitle("Each check catches a different mistake, at a different place.")

    xs = [60, 400, 740, 1080, 1420]
    labels = [("Dockerfile", "doc", "small base"), ("Build", "gear", "CI pipeline"),
              ("Registry", "db", "signed image"), ("API server", "server", "admission"),
              ("Node", "cube", "runs pod")]
    cols = [SLATE, SLATE, ORANGE, PURPLE, SLATE]
    for (lab, ic, sub), x, col in zip(labels, xs, cols):
        c.node(x, 220, 300, 110, col, lab, ic, sub)
    for i in range(4):
        c.arrow([(xs[i] + 300, 275), (xs[i + 1], 275)], dashed=False)

    checks = [("kubesec", "static analysis"), ("trivy, bom", "CVEs and SBOM"),
              ("cosign", "signature"), ("ImagePolicy", "allowed registries")]
    for (lab, sub), x in zip(checks, [60, 400, 740, 1080]):
        c.outline(x, 430, 300, 90, RED, lab, "shield")
        c.text(x + 150, 560, sub, 17, SOFT, False, "middle")
        c.line([(x + 150, 430), (x + 150, 330)], RED, 2.5, dashed=True)
    c.outline(1420, 430, 300, 90, RED, "Falco", "eye")
    c.text(1570, 560, "behaviour at runtime", 17, SOFT, False, "middle")
    c.line([(1570, 430), (1570, 330)], RED, 2.5, dashed=True)
    c.save(OUT, "cks-supply-chain")


def runtime_layers():
    c = Canvas(1800, 680)
    c.title("One system call,", "three guards")
    c.subtitle("seccomp and AppArmor block. Falco only watches and reports.")

    c.node(60, 200, 300, 110, SLATE, "Container", "cube", "calls open()")
    c.node(500, 200, 300, 110, RED, "seccomp", "shield", "which calls?")
    c.node(940, 200, 300, 110, PINK, "AppArmor", "shield", "which files?")
    c.node(1380, 200, 340, 110, GREEN, "Kernel", "server", "does the work")
    c.arrow([(360, 255), (500, 255)], n=1, at=(430, 255), dashed=False)
    c.arrow([(800, 255), (940, 255)], n=2, at=(870, 255), dashed=False)
    c.arrow([(1240, 255), (1380, 255)], n=3, at=(1310, 255), dashed=False)

    c.node(1380, 460, 340, 110, RED, "Falco", "eye", "eBPF probe")
    c.arrow([(1550, 310), (1550, 460)], "copy of event", n=4, at=(1550, 385), dashed=True)
    c.node(940, 460, 300, 110, SLATE, "Alert", "doc", "journal")
    c.arrow([(1380, 515), (1240, 515)], n=5, at=(1310, 515), dashed=False)
    c.save(OUT, "cks-runtime-layers")


def netpol_enforce():
    c = Canvas(1800, 700)
    c.title("NetworkPolicy", "in the CNI")
    c.subtitle("The API server only stores the policy. An agent on every node enforces it.")

    c.node(60, 180, 260, 110, SLATE, "You", "person", "kubectl apply")
    c.node(480, 180, 300, 110, PURPLE, "API server", "server", "stores policy")
    c.node(900, 180, 320, 110, TEAL, "CNI agent", "gear", "Calico or Cilium")
    c.arrow([(320, 235), (480, 235)], "apply", n=1, at=(400, 235), dashed=False, pos="above")
    c.arrow([(780, 235), (900, 235)], "watch", n=2, at=(840, 235), dashed=False, pos="above")

    c.group(30, 420, 1740, 220, "every node")
    c.node(60, 470, 260, 110, SLATE, "Pod A", "cube", "client")
    c.node(480, 470, 300, 110, GREEN, "Service DNAT", "globe", "kube-proxy")
    c.node(900, 470, 320, 110, GREEN, "Packet filter", "shield", "iptables or eBPF")
    c.node(1380, 470, 340, 110, SLATE, "Pod B", "cube", "server")
    c.arrow([(1060, 290), (1060, 470)], "write rules", n=3, at=(1060, 370), dashed=False)
    c.arrow([(320, 525), (480, 525)], "send", n=4, at=(400, 525), dashed=False, pos="above")
    c.arrow([(780, 525), (900, 525)], "real IP", n=5, at=(840, 525), dashed=False, pos="above")
    c.arrow([(1220, 525), (1380, 525)], "allow or drop", n=6, at=(1300, 525), dashed=False, pos="above")
    c.save(OUT, "cks-netpol-enforce")


def kubelet_ports():
    c = Canvas(1800, 780)
    c.title("The kubelet's", "two doors")
    c.subtitle("Port 10250 checks every caller. Port 10255 checks nobody.")

    c.node(60, 200, 260, 110, SLATE, "Caller", "person", "any pod or host")
    c.node(460, 200, 300, 110, RED, "Authenticate", "shield", "no anonymous")
    c.node(880, 200, 300, 110, RED, "Authorize", "shield", "mode Webhook")
    c.node(1320, 200, 380, 110, TEAL, "Pod data", "cube", "logs, exec, specs")
    c.arrow([(320, 255), (460, 255)], "HTTPS 10250", n=1, at=(390, 255), dashed=False, pos="above")
    c.arrow([(760, 255), (880, 255)], "who?", n=2, at=(820, 255), dashed=False, pos="above")
    c.arrow([(1180, 255), (1320, 255)], "allowed", n=4, at=(1250, 255), dashed=False, pos="above")

    c.node(880, 430, 300, 100, PURPLE, "API server", "server", "RBAC decides")
    c.arrow([(1030, 310), (1030, 430)], "ask", n=3, at=(1030, 370), dashed=True)

    c.outline(460, 610, 300, 90, RED, "Port 10255", "lock")
    c.arrow([(190, 310), (190, 655), (460, 655)], "plain HTTP", dashed=True, pos="above", at=(330, 655))
    c.arrow([(760, 655), (1510, 655), (1510, 310)], "pod specs, no checks", dashed=True, pos="above", at=(1130, 655))
    c.save(OUT, "cks-kubelet-ports")


def api_chain():
    c = Canvas(1800, 720)
    c.title("One API request,", "six steps")
    c.subtitle("Each gate either passes the request on or ends it with an error.")

    c.node(60, 180, 240, 110, SLATE, "Client", "person", "kubectl")
    c.node(420, 180, 300, 110, RED, "Authenticate", "shield", "who are you?")
    c.node(840, 180, 300, 110, RED, "Authorize", "shield", "may you?")
    c.node(1260, 180, 340, 110, PINK, "Mutating", "gear", "may change it")
    c.arrow([(300, 235), (420, 235)], n=1, at=(360, 235), dashed=False)
    c.arrow([(720, 235), (840, 235)], n=2, at=(780, 235), dashed=False)
    c.arrow([(1140, 235), (1260, 235)], n=3, at=(1200, 235), dashed=False)
    c.text(570, 340, "401 if unknown", 18, SOFT, True, "middle")
    c.text(990, 340, "403 if denied", 18, SOFT, True, "middle")

    c.node(1260, 470, 340, 110, PURPLE, "Schema check", "doc", "valid object?")
    c.node(840, 470, 300, 110, PINK, "Validating", "shield", "accept it?")
    c.node(420, 470, 300, 110, ORANGE, "etcd", "db", "stored")
    c.arrow([(1430, 290), (1430, 470)], n=4, at=(1430, 380), dashed=False)
    c.arrow([(1260, 525), (1140, 525)], n=5, at=(1200, 525), dashed=False)
    c.arrow([(840, 525), (720, 525)], "write", n=6, at=(780, 525), dashed=False, pos="below")
    c.save(OUT, "cks-api-chain")


def static_pod_loop():
    c = Canvas(1800, 720)
    c.title("Static pods,", "the repair loop")
    c.subtitle("The kubelet runs what the folder says. No API server is involved.")

    c.node(60, 180, 240, 110, SLATE, "You", "person", "on the node")
    c.node(420, 180, 320, 110, ORANGE, "Manifest", "doc", "manifests folder")
    c.node(860, 180, 300, 110, TEAL, "kubelet", "gear", "watches folder")
    c.node(1280, 180, 320, 110, TEAL, "containerd", "cube", "CRI runtime")
    c.arrow([(300, 235), (420, 235)], "edit", n=1, at=(360, 235), dashed=False, pos="above")
    c.arrow([(740, 235), (860, 235)], "reads", n=2, at=(800, 235), dashed=False, pos="above")
    c.arrow([(1160, 235), (1280, 235)], "start", n=3, at=(1220, 235), dashed=False, pos="above")

    c.node(1280, 470, 320, 110, PURPLE, "API server", "server", "the container")
    c.node(860, 470, 300, 110, ORANGE, "Pod logs", "doc", "/var/log/pods")
    c.arrow([(1440, 290), (1440, 470)], "runs", n=4, at=(1440, 380), dashed=False)
    c.arrow([(1280, 525), (1160, 525)], "writes", n=5, at=(1220, 525), dashed=False, pos="below")
    c.arrow([(860, 525), (180, 525), (180, 290)], "crictl logs", n=6, at=(520, 525), dashed=True, pos="below")
    c.save(OUT, "cks-static-pod-loop")


def node_limits():
    c = Canvas(1800, 640)
    c.title("A kubelet's", "two limits")
    c.subtitle("The Node authorizer limits reads. NodeRestriction limits writes.")

    c.node(60, 200, 320, 110, TEAL, "kubelet", "gear", "system:node:cks-w1")
    c.node(520, 200, 320, 110, RED, "Node authorizer", "shield", "which objects?")
    c.node(980, 200, 320, 110, RED, "NodeRestriction", "shield", "which changes?")
    c.node(1440, 200, 300, 110, ORANGE, "etcd", "db", "own Node, own pods")
    c.arrow([(380, 255), (520, 255)], "request", n=1, at=(450, 255), dashed=False, pos="above")
    c.arrow([(840, 255), (980, 255)], "allowed", n=2, at=(910, 255), dashed=False, pos="above")
    c.arrow([(1300, 255), (1440, 255)], "allowed", n=3, at=(1370, 255), dashed=False, pos="above")

    c.outline(520, 440, 320, 90, RED, "Other node", "lock")
    c.outline(980, 440, 320, 90, RED, "Protected label", "lock")
    c.arrow([(680, 310), (680, 440)], "403", dashed=True)
    c.arrow([(1140, 310), (1140, 440)], "403", dashed=True)
    c.save(OUT, "cks-node-limits")


def encryption_rest():
    c = Canvas(1800, 700)
    c.title("Secrets", "at rest")
    c.subtitle("The API server encrypts the value before etcd ever sees it.")

    c.node(60, 180, 260, 110, SLATE, "Client", "person", "create secret")
    c.node(440, 180, 300, 110, PURPLE, "API server", "server", "kube-apiserver")
    c.node(860, 180, 300, 110, RED, "Encrypt", "lock", "first provider")
    c.node(1280, 180, 440, 110, ORANGE, "etcd", "db", "k8s:enc:aescbc:v1:key1:")
    c.arrow([(320, 235), (440, 235)], "plain", n=1, at=(380, 235), dashed=False, pos="above")
    c.arrow([(740, 235), (860, 235)], "hand over", n=2, at=(800, 235), dashed=False, pos="above")
    c.arrow([(1160, 235), (1280, 235)], "ciphertext", n=3, at=(1220, 235), dashed=False, pos="above")

    c.group(440, 450, 720, 180, "EncryptionConfiguration")
    c.outline(480, 500, 300, 90, RED, "aescbc key1", "lock")
    c.outline(820, 500, 300, 90, DIM, "identity", "doc")
    c.arrow([(590, 290), (590, 450)], "read at start", dashed=True)
    c.outline(1280, 500, 440, 90, PINK, "KMS plugin", "lock")
    c.note(1290, 620, ["the key stays outside the cluster"])
    c.save(OUT, "cks-encryption-rest")


def sandbox_kernel():
    c = Canvas(1800, 820)
    c.title("One syscall,", "two runtimes")
    c.subtitle("A runc container talks to the host kernel. gVisor answers most calls itself.")

    c.group(140, 180, 600, 330, "runc")
    c.group(1060, 180, 600, 330, "runsc (gVisor)")
    c.node(200, 220, 480, 110, SLATE, "Container", "cube", "app process")
    c.node(1120, 220, 480, 110, SLATE, "Container", "cube", "app process")
    c.node(1120, 380, 480, 110, PINK, "Sentry", "shield", "user-space kernel")

    c.outline(60, 560, 1680, 70, RED, "Syscall filters: seccomp, AppArmor", "shield")
    c.node(60, 670, 1680, 110, GREEN, "Host kernel", "server", "shared by every pod")
    c.arrow([(440, 330), (440, 560)], "every syscall", dashed=False)
    c.arrow([(440, 630), (440, 670)], dashed=False)
    c.arrow([(1360, 330), (1360, 380)], "syscalls", dashed=False)
    c.arrow([(1360, 490), (1360, 560)], "few syscalls", dashed=False)
    c.arrow([(1360, 630), (1360, 670)], dashed=False)
    c.save(OUT, "cks-sandbox-kernel")


def image_policy():
    c = Canvas(1800, 720)
    c.title("Image policy", "verdicts")
    c.subtitle("The API server asks a back end about the images of every new pod.")

    c.node(60, 190, 260, 110, SLATE, "Client", "person", "create pod")
    c.node(470, 190, 320, 110, PURPLE, "API server", "server", "admission")
    c.node(1000, 190, 360, 110, RED, "Policy back end", "shield", "localhost:8443")
    c.arrow([(320, 245), (470, 245)], "pod", n=1, at=(395, 245), dashed=False, pos="above")
    c.arrow([(790, 220), (1000, 220)], "ImageReview", n=2, at=(895, 220), dashed=False, pos="above")
    c.arrow([(1000, 275), (790, 275)], "verdict", n=3, at=(895, 275), dashed=False, pos="below")

    c.outline(470, 480, 320, 90, ORANGE, "No answer", "eye")
    c.arrow([(630, 300), (630, 480)], "back end down", n=4, at=(630, 390), dashed=True)
    c.outline(1000, 440, 360, 80, GREEN, "Fail closed", "lock")
    c.outline(1000, 580, 360, 80, RED, "Fail open", "lock")
    c.arrow([(790, 525), (900, 525), (900, 480), (1000, 480)], dashed=False)
    c.arrow([(790, 525), (900, 525), (900, 620), (1000, 620)], dashed=False)
    c.text(1390, 487, "defaultAllow: false, pod refused", 18, SOFT, True)
    c.text(1390, 627, "defaultAllow: true, pod admitted", 18, SOFT, True)
    c.save(OUT, "cks-image-policy")


def audit_pipeline():
    c = Canvas(1800, 700)
    c.title("The audit", "pipeline")
    c.subtitle("Each request makes events. The policy picks a level. A backend keeps them.")

    c.node(60, 290, 260, 110, SLATE, "Request", "person", "kubectl get")
    c.group(420, 170, 480, 460, "API server")
    c.outline(450, 210, 420, 80, PURPLE, "RequestReceived", "doc")
    c.outline(450, 320, 420, 80, PURPLE, "ResponseStarted", "doc")
    c.outline(450, 430, 420, 80, PURPLE, "ResponseComplete", "doc")
    c.note(470, 560, ["Panic, only on a crash", "Started, only for watches"])
    c.arrow([(320, 345), (420, 345)], n=1, at=(370, 345), dashed=False)

    c.node(1000, 290, 320, 110, RED, "Audit policy", "doc", "first match wins")
    c.arrow([(900, 345), (1000, 345)], n=2, at=(950, 345), dashed=False)
    c.outline(1480, 220, 280, 90, ORANGE, "Log file", "doc")
    c.outline(1480, 400, 280, 90, ORANGE, "Webhook", "globe")
    c.arrow([(1320, 345), (1420, 345), (1420, 265), (1480, 265)], "level", n=3, at=(1370, 345), dashed=False, pos="above")
    c.arrow([(1420, 345), (1420, 445), (1480, 445)], dashed=False)
    c.note(1010, 450, ["level None: dropped"])
    c.save(OUT, "cks-audit-pipeline")


def falco_path():
    c = Canvas(1800, 740)
    c.title("From syscall", "to alert")
    c.subtitle("Falco reads a copy of each event. It never blocks the call.")

    c.node(60, 210, 240, 110, SLATE, "Container", "cube", "runs bash")
    c.group(440, 170, 820, 190, "kernel space")
    c.node(480, 210, 340, 110, GREEN, "Kernel", "server", "execve()")
    c.node(880, 210, 340, 110, GREEN, "eBPF probe", "eye", "modern_ebpf")
    c.arrow([(300, 265), (480, 265)], "syscall", n=1, at=(370, 265), dashed=False, pos="above")
    c.arrow([(820, 265), (880, 265)], n=2, at=(850, 265), dashed=False)

    c.group(440, 440, 820, 190, "user space")
    c.node(880, 480, 340, 110, RED, "Rule engine", "shield", "lists, macros, rules")
    c.node(480, 480, 340, 110, TEAL, "Outputs", "doc", "journal, HTTP")
    c.arrow([(1050, 320), (1050, 480)], "copy of event", n=3, at=(1050, 400), dashed=True)
    c.arrow([(880, 535), (820, 535)], n=4, at=(850, 535), dashed=False)
    c.node(1380, 480, 340, 110, SLATE, "You", "person", "read alert")
    c.arrow([(650, 590), (650, 690), (1550, 690), (1550, 590)], "alert line", n=5, at=(1100, 690), dashed=False, pos="above")
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
