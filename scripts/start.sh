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

not_ready_pods() {
  "${K[@]}" get pods -A --no-headers 2>/dev/null \
    | awk '{split($3,a,"/"); if ($4!="Completed" && (a[1]!=a[2] || $4!="Running")) print $1"/"$2}'
}

wait_for_pods() {
  local tries="$1"
  for _ in $(seq 1 "$tries"); do
    [[ -z "$(not_ready_pods)" ]] && return 0
    sleep 5
  done
  return 1
}

say "Waiting for every pod to become Ready (up to 3 minutes)"
if ! wait_for_pods 36; then
  # After a node restart, pods whose sandboxes came back before istio-cni was running
  # can end up with incomplete traffic redirection: ztunnel then captures the kubelet's
  # health probes and the pod never becomes Ready. A new pod gets set up correctly,
  # so recreate the stuck mesh pods once, after the CNI agent and ztunnel are Ready.
  "${K[@]}" -n istio-system rollout status ds/istio-cni-node --timeout=120s >/dev/null
  "${K[@]}" -n istio-system rollout status ds/ztunnel --timeout=120s >/dev/null
  mesh_namespaces="$("${K[@]}" get ns -l istio.io/dataplane-mode=ambient -o jsonpath='{.items[*].metadata.name}')"
  for pod in $(not_ready_pods); do
    ns="${pod%%/*}"
    if [[ " $mesh_namespaces " == *" $ns "* ]]; then
      say "Recreating ${pod}, which did not become Ready after the restart"
      "${K[@]}" -n "$ns" delete pod "${pod#*/}" --wait=false >/dev/null
    fi
  done
  say "Waiting again (up to 3 minutes)"
  wait_for_pods 36 || true
fi

if [[ -n "$(not_ready_pods)" ]]; then
  echo "Still not ready:" >&2
  not_ready_pods | sed 's/^/  /' >&2
  exit 1
fi
say "All pods are Ready. The shop is at http://localhost:8080. Run ./scripts/port-forward.sh for the other UIs."
