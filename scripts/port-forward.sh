#!/usr/bin/env bash
# Open local ports for ArgoCD, Grafana, Prometheus and Jaeger. Press Ctrl-C to stop all of them.
set -euo pipefail

pids=()
cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT INT TERM

forward() {
  local namespace="$1" target="$2" mapping="$3" label="$4"
  kubectl -n "$namespace" port-forward "$target" "$mapping" >/dev/null &
  pids+=("$!")
  printf '%-11s http://localhost:%s\n' "$label" "${mapping%%:*}"
}

forward argocd svc/argocd-server 8081:80 ArgoCD
forward observability svc/kube-prometheus-stack-grafana 3000:80 Grafana
forward observability svc/kube-prometheus-stack-prometheus 9090:9090 Prometheus
forward observability svc/jaeger-query 16686:16686 Jaeger
forward istio-system svc/kiali 20001:20001 Kiali

printf '\nPort-forwards are running. Press Ctrl-C to stop.\n'
wait
