#!/usr/bin/env bash
# Open local ports for ArgoCD, Grafana, Prometheus, Jaeger, Kiali and Headlamp. Press Ctrl-C to stop all of them.
set -euo pipefail

pids=()
# A run whose terminal went away without Ctrl-C leaves its forwards behind, holding the
# ports. Each run writes its process ids here, and the next run stops those first.
PIDFILE="${TMPDIR:-/tmp}/k8s-lab-port-forward.pids"
if [[ -f "$PIDFILE" ]]; then
  for pid in $(cat "$PIDFILE"); do
    # Only processes of an earlier run, never an unrelated one that got the same id.
    ps -p "$pid" -o args= 2>/dev/null | grep -q port-forward && kill "$pid" 2>/dev/null
  done
  sleep 1
fi
echo "$$" > "$PIDFILE"
cleanup() {
  for pid in "${pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -f "$PIDFILE"
}
trap cleanup EXIT INT TERM

# Always target the lab cluster. OrbStack switches the current context to "orbstack"
# when it restarts, and a bare "kubectl port-forward" would then look in the wrong cluster.
CONTEXT="k3d-${CLUSTER_NAME:-k8s-lab}"
# The toolbox sets PF_ADDRESS=0.0.0.0, so the ports it publishes reach these forwards from
# your browser. On the host they listen on localhost only.
ADDRESS="${PF_ADDRESS:-localhost}"

forward() {
  local namespace="$1" target="$2" mapping="$3" label="$4"
  kubectl --context "$CONTEXT" -n "$namespace" port-forward --address "$ADDRESS" "$target" "$mapping" >/dev/null &
  pids+=("$!")
  echo "$!" >> "$PIDFILE"
  printf '%-11s http://localhost:%s\n' "$label" "${mapping%%:*}"
}

forward argocd svc/argocd-server 8081:80 ArgoCD
forward observability svc/kube-prometheus-stack-grafana 3000:80 Grafana
forward observability svc/kube-prometheus-stack-prometheus 9090:9090 Prometheus
forward observability svc/kube-prometheus-stack-alertmanager 9093:9093 Alertmanager
forward observability svc/jaeger-query 16686:16686 Jaeger
forward istio-system svc/kiali 20001:20001 Kiali
forward headlamp svc/headlamp 4466:80 Headlamp

printf '\nPort-forwards are running. Press Ctrl-C to stop.\n'
wait
