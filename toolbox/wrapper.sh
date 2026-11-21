#!/usr/bin/env bash
# Installed as both k3d and kind in the toolbox. Runs the real tool from /usr/local/lib/lab,
# then fixes the toolbox kubeconfig (kube-sync.sh) after a command that creates or starts a
# cluster. Before k3d deletes a cluster, the toolbox leaves that cluster's network, so k3d
# can remove the network as it does on the host.
tool="$(basename "$0")"
real="/usr/local/lib/lab/$tool"

if [[ "$tool" == k3d && "${1:-}" == cluster && "${2:-}" =~ ^(delete|rm)$ ]]; then
  names=()
  for a in "${@:3}"; do
    case "$a" in
      -a|--all) mapfile -t names < <("$real" cluster list -o json 2>/dev/null | jq -r '.[].name') ;;
      -*) ;;
      *) names+=("$a") ;;
    esac
  done
  [[ ${#names[@]} -eq 0 ]] && names=(k3s-default)
  for n in "${names[@]}"; do
    docker network disconnect -f "k3d-$n" "$(hostname)" >/dev/null 2>&1 || true
  done
fi

"$real" "$@"
status=$?

case "$tool ${1:-} ${2:-}" in
  "k3d cluster create"|"k3d cluster start"|"k3d cluster edit"|"kind create cluster")
    /usr/local/lib/lab/kube-sync.sh ;;
esac
exit "$status"
