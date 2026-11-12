#!/usr/bin/env bash
# Module 19: ask a kagent agent a question over A2A, from inside the mesh, and print
# the tools it called and its answer.
#   ./course/agent-ask.sh "How many pods run in the shop namespace?"
#   AGENT=istio-agent ./course/agent-ask.sh "Is mTLS strict in the shop namespace?"
set -euo pipefail
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
AGENT="${AGENT:-k8s-agent}"
QUESTION="${1:?usage: $0 \"your question\"}"
BODY=$(python3 -c 'import json,sys,uuid; print(json.dumps({"jsonrpc":"2.0","id":"1","method":"message/send","params":{"message":{"role":"user","messageId":str(uuid.uuid4()),"parts":[{"kind":"text","text":sys.argv[1]}]}}}))' "$QUESTION")
PRINT=$(cat <<'PY'
import json, sys
raw = sys.stdin.read()
if not raw.strip():
    sys.exit("no answer (timed out or refused)")
r = json.loads(raw).get("result", {})
for h in r.get("history", []):
    for p in h.get("parts", []):
        d = p.get("data", {}) if p.get("kind") == "data" else {}
        if "args" in d:
            print("tool call:  ", d.get("name"), json.dumps(d["args"]))
        elif "response" in d:
            print("tool result:", json.dumps(d["response"])[:160])
usage = r.get("metadata", {}).get("adk_usage_metadata", {})
print("state:", r.get("status", {}).get("state"), "| tokens in", usage.get("promptTokenCount"), "out", usage.get("candidatesTokenCount"))
for a in r.get("artifacts", []):
    for p in a.get("parts", []):
        print("answer:", p.get("text", ""))
PY
)
"${K[@]}" -n shop exec deploy/course-client -- curl -s -m 300 -X POST \
  "http://kagent-controller.kagent:8083/api/a2a/kagent/${AGENT}/" -H 'Content-Type: application/json' -d "$BODY" | python3 -c "$PRINT"
