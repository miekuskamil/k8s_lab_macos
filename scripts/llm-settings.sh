#!/usr/bin/env bash
# Copies your AI settings from lab.env into the cluster, where the AI apps read them.
# ./lab.sh ai runs it, and so do ./lab.sh up, ./lab.sh start and the course checks.
#
# The shop assistant (module 5.1) and the RAG app (module 5.4) load the ConfigMap llm-settings
# and the Secret llm-api-key from their namespace when those exist. This script writes both
# into every namespace of the two apps that exists, and restarts an app that already runs so
# it picks the values up. Without lab.env, or with LLM_PROVIDER empty, it removes them, and
# the apps go back to their defaults: Ollama on your machine with qwen2.5:3b.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K=(kubectl --context "${KUBE_CONTEXT:-k3d-${CLUSTER_NAME:-k8s-lab}}")
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { (( QUIET )) || echo "$*"; }

LLM_PROVIDER="" LLM_URL="" LLM_MODEL="" LLM_API_KEY=""
EMBED_PROVIDER="" EMBED_URL="" EMBED_MODEL="" EMBED_API_KEY=""
if [[ -f "$ROOT/lab.env" ]]; then
  # shellcheck source=/dev/null
  . "$ROOT/lab.env"
fi
case "$LLM_PROVIDER" in
  ""|ollama|openai|anthropic) ;;
  *) echo "LLM_PROVIDER in lab.env must be ollama, openai or anthropic, not '$LLM_PROVIDER'" >&2; exit 1 ;;
esac

settings=() secrets=()
for v in LLM_PROVIDER LLM_URL LLM_MODEL EMBED_PROVIDER EMBED_URL EMBED_MODEL; do
  [[ -n "${!v}" ]] && settings+=(--from-literal="$v=${!v}")
done
for v in LLM_API_KEY EMBED_API_KEY; do
  [[ -n "${!v}" ]] && secrets+=(--from-literal="$v=${!v}")
done

# namespace and Deployment of each app
for app in shop/assistant course-rag/rag; do
  ns="${app%/*}" deploy="${app#*/}"
  "${K[@]}" get namespace "$ns" >/dev/null 2>&1 || continue
  changed=0
  before="$("${K[@]}" -n "$ns" get configmap llm-settings -o jsonpath='{.data}' 2>/dev/null || true)$("${K[@]}" -n "$ns" get secret llm-api-key -o jsonpath='{.data}' 2>/dev/null || true)"
  if [[ -n "$LLM_PROVIDER" ]]; then
    "${K[@]}" -n "$ns" create configmap llm-settings "${settings[@]}" --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
    if (( ${#secrets[@]} )); then
      "${K[@]}" -n "$ns" create secret generic llm-api-key "${secrets[@]}" --dry-run=client -o yaml | "${K[@]}" apply -f - >/dev/null
    else
      "${K[@]}" -n "$ns" delete secret llm-api-key --ignore-not-found >/dev/null
    fi
    say "$ns: LLM_PROVIDER=$LLM_PROVIDER${LLM_MODEL:+ LLM_MODEL=$LLM_MODEL}${LLM_URL:+ LLM_URL=$LLM_URL}"
  else
    "${K[@]}" -n "$ns" delete configmap llm-settings --ignore-not-found >/dev/null
    "${K[@]}" -n "$ns" delete secret llm-api-key --ignore-not-found >/dev/null
    say "$ns: no AI settings in lab.env, the apps use their defaults"
  fi
  after="$("${K[@]}" -n "$ns" get configmap llm-settings -o jsonpath='{.data}' 2>/dev/null || true)$("${K[@]}" -n "$ns" get secret llm-api-key -o jsonpath='{.data}' 2>/dev/null || true)"
  [[ "$before" != "$after" ]] && changed=1
  # A pod reads environment variables only when it starts.
  if (( changed )) && "${K[@]}" -n "$ns" get deploy "$deploy" >/dev/null 2>&1; then
    "${K[@]}" -n "$ns" rollout restart "deploy/$deploy" >/dev/null
    "${K[@]}" -n "$ns" rollout status "deploy/$deploy" --timeout=120s >/dev/null
    say "$ns: restarted $deploy with the new settings"
  fi
done
