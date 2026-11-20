#!/usr/bin/env bash
# Adds what the application modules need on top of the practice cluster. Run it on your Mac after
# ./lab.sh practice up, and again after every ./lab.sh practice reset.
#   control plane  helm, kubectl-convert, podman, and a local registry at registry.practice:5000
#   worker         the registry's name, and containerd set to pull from it over plain HTTP
#   cluster        metrics-server, so that "kubectl top" works
# On kind, the default, the node image already carries helm, kubectl-convert and podman, and the
# registry runs as the container practice-registry, so only metrics-server is left to add.
# Safe to run again. Works on kind, on OrbStack and, with PRACTICE_PLATFORM=vms, on your own VMs.
# Usage: ./platform-engineering/practice/app-extras/extras.sh            everything
#        ./platform-engineering/practice/app-extras/extras.sh metrics    only metrics-server (the tasks call this)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../cluster/platform.sh"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-0.9.1}"

say() { printf '\n=== %s\n' "$*"; }

metrics() {
  # kubeadm signs the kubelets' serving certificates with no IP in them, so metrics-server
  # skips that check here, the same as on most practice clusters.
  node_sh "$CP" "kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1 || {
    curl -fsSL https://github.com/kubernetes-sigs/metrics-server/releases/download/v${METRICS_SERVER_VERSION}/components.yaml \
      | sed 's|- --metric-resolution=15s|- --metric-resolution=15s\n        - --kubelet-insecure-tls|' | kubectl apply -f - >/dev/null; }
    kubectl -n kube-system rollout status deploy metrics-server --timeout=180s >/dev/null
    for i in \$(seq 1 60); do kubectl top nodes >/dev/null 2>&1 && break; sleep 3; done
    kubectl top nodes"
}

if [ "${1:-}" = metrics ]; then metrics; exit 0; fi

if [ "$PRACTICE_PLATFORM" = orbstack ]; then
  for m in "$CP" "$W1"; do orb start "$m" >/dev/null 2>&1 || true; done
fi
node_sh "$CP" "test -f /etc/kubernetes/admin.conf" || { echo "no cluster on $CP: run ./lab.sh practice up first"; exit 1; }

if [ "$PRACTICE_PLATFORM" = kind ]; then
  say "1/2 tools in the node image, and the registry container"
  node_sh "$CP" "echo \"helm \$(helm version --short), \$(podman --version), kubectl-convert \$(test -x /usr/local/bin/kubectl-convert && echo present)\"
    curl -fsS http://$PRACTICE_REGISTRY/v2/_catalog" \
    || { echo "the registry container practice-registry does not answer: run ./lab.sh practice up"; exit 1; }
  say "2/2 metrics-server $METRICS_SERVER_VERSION"
  metrics
  say "ready"
  echo "Work on $CP as in the security modules: $(node_shell_hint "$CP")"
  exit 0
fi

CP_IP="$(node_sh "$CP" "kubectl get node $CP -o jsonpath='{.status.addresses[?(@.type==\"InternalIP\")].address}'")"

say "1/3 $CP: helm, kubectl-convert, podman, registry"
node_script "$CP" cp "$CP_IP" < "$HERE/extras-node.sh"

say "2/3 $W1: pulls from $PRACTICE_REGISTRY"
node_script "$W1" w1 "$CP_IP" < "$HERE/extras-node.sh"

say "3/3 metrics-server $METRICS_SERVER_VERSION"
metrics

say "ready"
echo "Work on $CP as in the security modules: $(node_shell_hint "$CP"), then sudo -i"
