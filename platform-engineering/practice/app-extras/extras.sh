#!/usr/bin/env bash
# Adds what the CKAD track needs on top of the CKS practice cluster. Run it on your Mac after
# ./certs/cks/cluster/create.sh, and again after every ./certs/cks/cluster/reset.sh.
#   cks-cp  helm, kubectl-convert, podman, and a local registry at registry.ckad:5000
#   cks-w1  the registry's name, and containerd set to pull from it over plain HTTP
#   cluster metrics-server, so that "kubectl top" works
# Safe to run again. Works on OrbStack and, with CKS_PLATFORM=vms, on your own VMs.
# Usage: ./certs/ckad/cluster/extras.sh            everything
#        ./certs/ckad/cluster/extras.sh metrics    only metrics-server (the tasks call this)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../../cks/cluster/platform.sh"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-0.9.1}"

say() { printf '\n=== %s\n' "$*"; }

metrics() {
  # kubeadm signs the kubelets' serving certificates with no IP in them, so metrics-server
  # skips that check here, the same as on most practice clusters.
  node_sh "$CKS_CP" "kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1 || {
    curl -fsSL https://github.com/kubernetes-sigs/metrics-server/releases/download/v${METRICS_SERVER_VERSION}/components.yaml \
      | sed 's|- --metric-resolution=15s|- --metric-resolution=15s\n        - --kubelet-insecure-tls|' | kubectl apply -f - >/dev/null; }
    kubectl -n kube-system rollout status deploy metrics-server --timeout=180s >/dev/null
    for i in \$(seq 1 60); do kubectl top nodes >/dev/null 2>&1 && break; sleep 3; done
    kubectl top nodes"
}

if [ "${1:-}" = metrics ]; then metrics; exit 0; fi

if [ "$CKS_PLATFORM" = orbstack ]; then
  for m in "$CKS_CP" "$CKS_W1"; do orb start "$m" >/dev/null 2>&1 || true; done
fi
node_sh "$CKS_CP" "test -f /etc/kubernetes/admin.conf" || { echo "no cluster on $CKS_CP: run ./certs/cks/cluster/create.sh first"; exit 1; }
CP_IP="$(node_sh "$CKS_CP" "kubectl get node $CKS_CP -o jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}'")"

say "1/3 $CKS_CP: helm, kubectl-convert, podman, registry"
node_script "$CKS_CP" cp "$CP_IP" < "$HERE/extras-node.sh"

say "2/3 $CKS_W1: pulls from registry.ckad:5000"
node_script "$CKS_W1" w1 "$CP_IP" < "$HERE/extras-node.sh"

say "3/3 metrics-server $METRICS_SERVER_VERSION"
metrics

say "ready"
echo "Work on $CKS_CP as in the CKS track: $(node_shell_hint "$CKS_CP"), then sudo -i"
