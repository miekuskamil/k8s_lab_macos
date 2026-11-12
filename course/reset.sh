#!/usr/bin/env bash
# Put the lab back to its Git baseline after a course exercise.
#   ./course/reset.sh         restore routing, policies and experiment settings
#   ./course/reset.sh --all   also remove the course namespaces and the course client
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")

echo "Removing course rules from the shop namespace"
"${K[@]}" -n shop delete virtualservice,destinationrule --all --ignore-not-found >/dev/null
"${K[@]}" -n shop delete telemetry waypoint-access-logs --ignore-not-found >/dev/null
"${K[@]}" -n shop delete authorizationpolicy backend-allow-course-client --ignore-not-found >/dev/null
"${K[@]}" -n course-sidecar delete virtualservice,destinationrule,peerauthentication --all --ignore-not-found >/dev/null 2>&1 || true

echo "Applying the baseline Istio config from manifests/istio"
"${K[@]}" apply -f "$ROOT/manifests/istio/" >/dev/null

echo "Turning off the backend experiment settings"
"${K[@]}" -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=0 EXTRA_LATENCY_MS=0 >/dev/null
"${K[@]}" -n shop rollout status deploy/backend-v1 --timeout=120s >/dev/null
"${K[@]}" -n shop rollout status deploy/backend-v2 --timeout=120s >/dev/null
"${K[@]}" -n shop wait --for=condition=Programmed gateway/waypoint --timeout=120s >/dev/null

if [[ "${1:-}" == "--all" ]]; then
  echo "Removing the course namespaces and the course client"
  "${K[@]}" delete namespace course-sidecar course-outside --ignore-not-found >/dev/null
  "${K[@]}" -n shop delete deployment/course-client serviceaccount/course-client --ignore-not-found >/dev/null
fi
echo "Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules."
