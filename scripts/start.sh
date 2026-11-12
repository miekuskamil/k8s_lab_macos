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

# After a node restart, containerd recreates every pod's network sandbox. A mesh pod
# whose sandbox came back after the node booted but before istio-cni and ztunnel were
# Ready gets broken traffic redirection. Its health probes may still pass, so it looks
# Ready while every mesh connection into it fails (troubleshooting problem 15).
# Kubernetes records when each sandbox was set up, so find those pods and recreate them.
# This lab has one node, so one istio-cni pod and one ztunnel pod mark the window.
say "Waiting for istio-cni and ztunnel"
"${K[@]}" -n istio-system rollout status ds/istio-cni-node --timeout=180s >/dev/null
"${K[@]}" -n istio-system rollout status ds/ztunnel --timeout=180s >/dev/null
cond_time() { "${K[@]}" -n istio-system get pods -l "$1" -o jsonpath="{.items[0].status.conditions[?(@.type==\"$2\")].lastTransitionTime}"; }
window_start="$(cond_time k8s-app=istio-cni-node PodReadyToStartContainers)"
# Something may have replaced the istio-cni pod after the boot, like provision.sh after
# a k3s upgrade (course module 21). Then its sandbox time comes too late, so the window
# starts when the node container started, if that's earlier.
node_boot="$(docker inspect -f '{{.State.StartedAt}}' "k3d-${CLUSTER_NAME}-server-0" 2>/dev/null | cut -c1-19)"
[[ -n "$node_boot" && "${node_boot}Z" < "$window_start" ]] && window_start="${node_boot}Z"
window_end="$(cond_time k8s-app=istio-cni-node Ready)"
ztunnel_ready="$(cond_time app=ztunnel Ready)"
[[ "$ztunnel_ready" > "$window_end" ]] && window_end="$ztunnel_ready"
mesh_namespaces="$("${K[@]}" get ns -l istio.io/dataplane-mode=ambient -o jsonpath='{.items[*].metadata.name}')"
for ns in $mesh_namespaces; do
  while read -r pod sandbox; do
    [[ -z "$sandbox" ]] && continue
    if [[ ! "$sandbox" < "$window_start" && ! "$sandbox" > "$window_end" ]]; then
      say "Recreating ${ns}/${pod}: its network came up before the mesh was ready"
      "${K[@]}" -n "$ns" delete pod "$pod" --wait=false >/dev/null
    fi
  done < <("${K[@]}" -n "$ns" get pods -o jsonpath='{range .items[*]}{.metadata.name} {.status.conditions[?(@.type=="PodReadyToStartContainers")].lastTransitionTime}{"\n"}{end}')
done

say "Waiting for every pod to become Ready (up to 3 minutes)"
if ! wait_for_pods 36; then
  # Second safety net: recreate any mesh pod that is still not Ready, once.
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
