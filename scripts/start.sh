#!/usr/bin/env bash
# Resume the lab after a reboot, after the Mac slept, or after Docker restarted.
#
#   ./scripts/start.sh
#
# Why this exists: when Docker restarts the k3d containers by itself, k3d does not get to
# re-add the "NodeHosts" key to the CoreDNS ConfigMap. CoreDNS then cannot mount its
# config, cluster DNS stops, ztunnel cannot reach istiod, and the whole mesh goes down.
# "k3d cluster stop" followed by "k3d cluster start" lets k3d repair the ConfigMap.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-k8s-lab}"
K=(kubectl --context "k3d-${CLUSTER_NAME}")
QUIET=0
[[ "${1:-}" == "--quiet" ]] && QUIET=1
say() { (( QUIET )) || echo "$*"; }

if command -v orb >/dev/null 2>&1 && ! orb status >/dev/null 2>&1; then
  say "Starting OrbStack"
  orb start
fi
docker info >/dev/null 2>&1 || { echo "Docker does not answer. Start OrbStack or Docker first." >&2; exit 1; }

coredns_ok() {
  "${K[@]}" -n kube-system get configmap coredns -o jsonpath='{.data.NodeHosts}' 2>/dev/null | grep -q .
}

running="$(docker ps --filter "name=k3d-${CLUSTER_NAME}-server-0" --format '{{.Names}}')"
if [[ -n "$running" ]] && coredns_ok; then
  say "Cluster ${CLUSTER_NAME} is running and CoreDNS is healthy."
else
  say "Restarting cluster ${CLUSTER_NAME} through k3d so it can repair CoreDNS"
  k3d cluster stop "$CLUSTER_NAME" >/dev/null 2>&1 || true
  k3d cluster start "$CLUSTER_NAME" >/dev/null
fi

# OrbStack switches the current context to "orbstack" when it restarts. Point kubectl back
# at the lab so plain "kubectl" commands in the course reach the right cluster.
kubectl config use-context "k3d-${CLUSTER_NAME}" >/dev/null
say "kubectl context is k3d-${CLUSTER_NAME}"

"${K[@]}" wait --for=condition=Ready node --all --timeout=120s >/dev/null
"${K[@]}" -n kube-system rollout status deploy/coredns --timeout=120s >/dev/null

say "Waiting for every pod to become Ready (up to 5 minutes)"
for _ in $(seq 1 60); do
  not_ready="$("${K[@]}" get pods -A --no-headers 2>/dev/null | awk '{split($3,a,"/"); if ($4!="Completed" && (a[1]!=a[2] || $4!="Running")) n++} END {print n+0}')"
  [[ "$not_ready" == "0" ]] && break
  sleep 5
done
if [[ "$not_ready" != "0" ]]; then
  echo "Still not ready:" >&2
  "${K[@]}" get pods -A --no-headers | awk '{split($3,a,"/"); if ($4!="Completed" && (a[1]!=a[2] || $4!="Running")) print "  "$1"/"$2" "$3" "$4}' >&2
  exit 1
fi
say "All pods are Ready. The shop is at http://localhost:8080. Run ./scripts/port-forward.sh for the other UIs."
