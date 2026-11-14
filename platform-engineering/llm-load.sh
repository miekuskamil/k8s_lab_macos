#!/usr/bin/env bash
# Module 18: one long generation keeps a model server busy, while 10 short
# questions arrive half a second apart. Prints how long each short one took.
# Runs inside the course client, so the traffic goes through the mesh.
#   ./platform-engineering/llm-load.sh            target the Qwen servers directly
#   ./platform-engineering/llm-load.sh llm        target the "llm" Service instead
set -euo pipefail
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
SERVICE="${1:-llm-qwen}"
"${K[@]}" -n shop exec -i deploy/course-client -- sh -s "$SERVICE" <<'INNER' | awk '
  /^LONG/ {long = $2; next}
  {t = $2; if (t > 2) slow++; line = line sprintf("%.1f ", t)}
  END {printf "short questions (seconds): %s\nlong generation: %.0f s\nshort questions stuck behind it (over 2 s): %d of 10\n", line, long, slow}'
U="http://$1.ai.svc.cluster.local:8080/v1/chat/completions"
( curl -s -o /dev/null -m 120 -w 'LONG %{time_total}\n' "$U" -H 'Content-Type: application/json' \
    -d '{"messages":[{"role":"user","content":"Write a long story about a cat."}],"max_tokens":2000,"ignore_eos":true}' ) &
sleep 3
for i in 1 2 3 4 5 6 7 8 9 10; do
  ( curl -s -o /dev/null -m 120 -w 'short %{time_total}\n' "$U" -H 'Content-Type: application/json' \
      -d '{"messages":[{"role":"user","content":"Say hi."}],"max_tokens":3}' ) &
  sleep 0.5
done
wait
INNER
