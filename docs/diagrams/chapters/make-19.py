#!/usr/bin/env python3
"""Module 19 diagrams: the agent loop of model and tools, and whose permissions a tool call uses."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def loop():
    c = Canvas(1820, 860)
    c.title("Model, Tools,", "Loop")
    c.subtitle("The model never touches the cluster. It asks for a tool, the agent runs it and hands back the result.")
    top, low = 280, 640
    c.node(60, top, 280, 110, SLATE, "You", "person")
    c.node(560, top, 320, 110, SLATE, "k8s-agent", "cube", "pod")
    c.node(1400, top, 360, 110, SLATE, "Model", "laptop", "Ollama on your Mac")
    c.node(560, low, 320, 110, SLATE, "Tool server", "gear", "MCP")
    c.node(1400, low, 360, 110, PURPLE, "Kubernetes API", "server")

    c.arrow([(340, top + 30), (560, top + 30)], "How many deployments\nrun in shop?", n=1, at=(450, top + 30), pos="above")
    c.arrow([(560, top + 80), (340, top + 80)], "answer", n=10, at=(450, top + 80), pos="below")

    c.arrow([(880, top + 30), (1400, top + 30)], "question\n+ 18 tools", n=2, at=(1010, top + 30), pos="above")
    c.step(1270, top + 30, 8)
    c.text(1270, top - 22, "here is the result,", 18, INK, True, "middle")
    c.text(1270, top + 1, "now answer", 18, INK, True, "middle")
    c.arrow([(1400, top + 80), (880, top + 80)], "There are\n6 deployments", n=9, at=(1010, top + 80), pos="below")
    c.step(1270, top + 80, 3)
    c.text(1270, top + 123, "call k8s_get_resources", 18, INK, True, "middle")
    c.text(1270, top + 146, "namespace=shop", 18, INK, True, "middle")
    c.text(1270, top + 169, "type=deployment", 18, INK, True, "middle")

    c.arrow([(660, top + 116), (660, low)], "MCP\ntools/call", n=4, at=(660, 520), pos="left")
    c.arrow([(780, low), (780, top + 116)], "tool\nresult", n=7, at=(780, 520), pos="right")

    c.arrow([(880, low + 30), (1400, low + 30)], "kubectl get deployment -n shop", n=5, at=(1140, low + 30), pos="above")
    c.arrow([(1400, low + 80), (880, low + 80)], "table", n=6, at=(1140, low + 80), pos="below")
    c.save(OUT, "19-agent-loop")


def permissions():
    c = Canvas(1800, 640)
    c.title("Whose Permissions Does", "a Tool Use?")
    c.subtitle("The API server checks whoever sends the request. Here that is the tool server, not you or the agent.")
    xs, W, y = [60, 520, 980, 1440], 300, 240
    c.node(xs[0], y, W, 110, SLATE, "You", "person", "or any client")
    c.node(xs[1], y, W, 110, SLATE, "k8s-agent", "cube", "sa/k8s-agent")
    c.node(xs[2], y, W, 110, SLATE, "kagent-tools", "gear", "sa/kagent-tools")
    c.node(xs[3], y, W, 110, PURPLE, "Kubernetes API", "server", "RBAC")
    c.arrow([(xs[0] + W, y + 55), (xs[1], y + 55)], "A2A request", n=1, at=(xs[0] + W + 80, y + 55), pos="below")
    c.arrow([(xs[1] + W, y + 55), (xs[2], y + 55)], "MCP:\nPOST /mcp", n=2, at=(xs[1] + W + 80, y + 55), pos="below")
    c.arrow([(xs[2] + W, y + 55), (xs[3], y + 55)], "kubectl with\nits own token", n=3, at=(xs[2] + W + 80, y + 55), pos="below")
    c.outline(xs[3], 470, W, 110, RED, "RBAC checks\nsa/kagent-tools", "shield")
    c.arrow([(xs[3] + W / 2, y + 116), (xs[3] + W / 2, 470)])
    c.save(OUT, "19-tool-permissions")


if __name__ == "__main__":
    loop()
    permissions()
