#!/usr/bin/env python3
"""Module 19 diagrams: the agent loop of model and tools, and whose permissions a tool call uses."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from bbg import *  # noqa: E402,F403

OUT = Path(__file__).resolve().parent


def loop():
    c = Canvas(1600, 880)
    c.title("Model, tools,", "loop")
    c.subtitle("The model never touches the cluster. It asks for a tool, the agent runs it and hands back the result.")

    c.frame(40, 150, 300, 700, "Your Mac", "host")
    you = c.node(70, 200, 240, 100, SLATE, "You", "person")
    model = c.node(70, 480, 240, 120, PINK, "Model", "sparkle", "Ollama")

    c.frame(400, 150, 1160, 700, "Cluster", "cluster")
    c.frame(430, 380, 680, 440, "namespace kagent", "ns")
    agent = c.frame(690, 440, 380, 200, "k8s-agent pod", "pod", right="sa/k8s-agent")
    c.box(715, 495, 330, 110, SLATE, "agent program", "runs the loop")
    tools = c.frame(690, 700, 320, 100, "kagent-tools pod", "pod")
    c.frame(1150, 640, 380, 180, "control plane", "group")
    api = c.node(1180, 700, 320, 100, PURPLE, "Kubernetes API", "server")

    c.connect(you, agent, "how many deployments in shop?", n=1, sa="right", sb="top", fa=0.5, fb=0.5,
              pos="above", at=(560, 250))
    y1, y2 = 515, 570
    c.line([(690, y1), (310, y1)], LINE, AW, head=True)
    c.step(600, y1, 2)
    c.text(600, y1 - 26, "question + 18 tools", 17, INK, True, "middle", halo=True)
    c.step(410, y1, 6)
    c.text(410, y1 - 26, "result", 17, INK, True, "middle", halo=True)
    c.line([(310, y2), (690, y2)], PINK, AW, head=True)
    c.step(500, y2, 3)
    c.text(500, y2 + 40, "tool call:", 17, DEEP[PINK], True, "middle", halo=True)
    c.text(500, y2 + 62, "k8s_get_resources", 16, DEEP[PINK], True, "middle", halo=True, mono=True)
    c.connect(agent, tools, "MCP tools/call", n=4, pos="right", at=(850, 670))
    c.connect(tools, api, "kubectl get", n=5, pos="above", at=(1095, 750))
    c.save(OUT, "19-agent-loop")


def permissions():
    c = Canvas(1600, 780)
    c.title("Whose permissions does", "a tool use?")
    c.subtitle("The API server checks whoever sends the request. Here that is the tool server, not you or the agent.")

    c.frame(40, 220, 280, 240, "Your Mac", "host")
    you = c.node(65, 290, 230, 110, SLATE, "You", "person", "may only read pods")

    c.frame(360, 150, 1200, 600, "Cluster", "cluster")
    c.frame(390, 190, 720, 520, "namespace kagent", "ns")
    ag = c.frame(420, 270, 300, 150, "k8s-agent pod", "pod")
    c.chip(570, 380, "sa/k8s-agent", SLATE, anchor="middle")
    tl = c.frame(790, 270, 290, 150, "kagent-tools pod", "pod")
    c.chip(935, 330, "sa/kagent-tools", SLATE, anchor="middle")
    c.box(830, 360, 210, 44, ORANGE, "its own token", size=16)
    mesh = c.outline(560, 490, 380, 90, BLUE, "mesh policy", "shield", sub="who may connect")
    rb = c.outline(790, 600, 290, 90, RED, "cluster-admin", "key", sub="bound to kagent-tools")

    c.frame(1150, 190, 380, 520, "control plane", "group")
    api = c.node(1180, 290, 320, 110, PURPLE, "API server", "server")
    rbac = c.node(1180, 500, 320, 120, RED, "RBAC check", "shield", "sees sa/kagent-tools")

    c.connect(you, ag, "A2A request", sa="right", sb="left", fb=(345 - 270) / 150, pos="above")
    c.connect(ag, tl, "MCP: POST /mcp", sa="right", sb="left", pos="above")
    c.connect(mesh, Box(750, 345, 1, 1), "", sa="top", sb="bottom", fa=0.5, dashed=True, col=BLUE)
    c.connect(tl, api, "kubectl", sa="right", sb="left", fa=(345 - 270) / 150, fb=(345 - 290) / 110, pos="above")
    c.connect(api, rbac, "", pos="right")
    c.connect(rb, rbac, "allows all", sa="right", sb="left", fa=0.5, fb=0.85, dashed=True, col=RED, pos="below",
              at=(1130, 645))
    c.save(OUT, "19-tool-permissions")


if __name__ == "__main__":
    loop()
    permissions()
