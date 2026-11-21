#!/usr/bin/env bash
# Gives the toolbox a working kubectl context for every k3d and kind cluster on this Docker host.
#
# Why this is needed: k3d and kind write kubeconfigs that point at 0.0.0.0 or 127.0.0.1 and a
# port published on the host. Inside the toolbox, 127.0.0.1 is the toolbox itself, so those
# addresses lead nowhere. Instead, the toolbox joins each cluster's Docker network and talks to
# the API server by its container name, which the API server's certificate already lists:
#   k3d cluster NAME   network k3d-NAME   server https://k3d-NAME-serverlb:6443
#   kind cluster NAME  network kind       server https://NAME-control-plane:6443
# The host's own ~/.kube/config stays as it is; the toolbox keeps its kubeconfig in its home
# volume. The k3d and kind wrappers run this after every create or start, and so does lab.sh.
set -uo pipefail

LIB=/usr/local/lib/lab
self="$(hostname)"
config="${KUBECONFIG:-$HOME/.kube/config}"
mkdir -p "$(dirname "$config")"
exec 9>"$(dirname "$config")/.kube-sync.lock"
flock 9

join() { docker network connect "$1" "$self" >/dev/null 2>&1 || true; }

for name in $("$LIB/k3d" cluster list -o json 2>/dev/null | jq -r '.[].name'); do
  # A stopped cluster has no kubeconfig to read; the k3d wrapper syncs again after it starts.
  [[ -n "$(docker ps -q --filter "name=^k3d-${name}-server-0$")" ]] || continue
  join "k3d-$name"
  "$LIB/k3d" kubeconfig merge "$name" --kubeconfig-merge-default --kubeconfig-switch-context=false >/dev/null 2>&1 || continue
  server="k3d-${name}-serverlb"
  docker container inspect "$server" >/dev/null 2>&1 || server="k3d-${name}-server-0"
  kubectl config set-cluster "k3d-$name" --server="https://${server}:6443" >/dev/null
done

for name in $("$LIB/kind" get clusters 2>/dev/null); do
  join kind
  tmp="$(mktemp)"
  "$LIB/kind" get kubeconfig --internal --name "$name" > "$tmp" 2>/dev/null || { rm -f "$tmp"; continue; }
  # The practice scripts print KUBECONFIG=~/.kube/practice-kind.yaml; keep that file right too.
  if [[ "$name" == "${PRACTICE_KIND_NAME:-practice}" ]]; then
    install -m 600 "$tmp" "${PRACTICE_KUBECONFIG:-$HOME/.kube/practice-kind.yaml}"
  fi
  kubectl config delete-context "kind-$name" >/dev/null 2>&1
  kubectl config delete-cluster "kind-$name" >/dev/null 2>&1
  kubectl config delete-user "kind-$name" >/dev/null 2>&1
  [[ -s "$config" ]] || : > "$config"
  KUBECONFIG="$config:$tmp" kubectl config view --flatten > "$tmp.merged" && install -m 600 "$tmp.merged" "$config"
  rm -f "$tmp" "$tmp.merged"
done
exit 0
