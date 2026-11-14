#!/usr/bin/env bash
# Break the lab on purpose for module 8. The script does not say what it changed.
#   ./platform-engineering/incident.sh 1|2|3|4   start an incident
#   ./platform-engineering/incident.sh stop      repair everything (same as ./platform-engineering/reset.sh)
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")

case "${1:-}" in
  1) "${K[@]}" apply -f "$DIR/manifests/incidents/1.yaml" >/dev/null ;;
  2) "${K[@]}" apply -f "$DIR/manifests/incidents/2.yaml" >/dev/null ;;
  3) "${K[@]}" apply -f "$DIR/manifests/incidents/3.yaml" >/dev/null
     "${K[@]}" -n shop set env deploy/backend-v2 EXTRA_LATENCY_MS=700 >/dev/null
     "${K[@]}" -n shop rollout status deploy/backend-v2 --timeout=120s >/dev/null ;;
  4) "${K[@]}" -n shop delete gateway waypoint --ignore-not-found >/dev/null ;;
  stop) exec "$DIR/reset.sh" ;;
  *) echo "Usage: $0 1|2|3|4|stop" >&2; exit 2 ;;
esac
echo "Incident ${1} is active. Users are complaining. Open http://localhost:8080 and investigate."
echo "Repair the lab with: ./platform-engineering/incident.sh stop"
