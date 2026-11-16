#!/usr/bin/env bash
# Runs on your Mac and drives the pe-lab VM over SSH.
#
#   ./proxmox/pe-lab.sh install [--with-ollama]   copies install-lab.sh to the VM and runs it there
#   ./proxmox/pe-lab.sh install --from-checkout   the same, but ships this checkout instead of cloning GitHub
#   ./proxmox/pe-lab.sh ui                        opens the lab's UIs on localhost; Ctrl-C closes them
#   ./proxmox/pe-lab.sh ssh [command]             a shell on the VM, or one command
#
# Settings come from the environment:
#   PE_LAB_HOST=ubuntu@192.168.1.231   the VM
#   PE_LAB_KEY=~/.ssh/cks_proxmox      the private key; set it empty to use your SSH config
set -euo pipefail

HOST="${PE_LAB_HOST:-ubuntu@192.168.1.231}"
KEY="${PE_LAB_KEY-$HOME/.ssh/cks_proxmox}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH=(ssh -o StrictHostKeyChecking=accept-new)
[ -z "$KEY" ] || SSH+=(-i "$KEY")
# The shop's ports plus every port that scripts/port-forward.sh opens on the VM.
PORTS="8080 8443 8081 3000 9090 9093 16686 20001 4466"

install() {
  local from_checkout=0 args=()
  for a in "$@"; do
    if [ "$a" = --from-checkout ]; then from_checkout=1; else args+=("$a"); fi
  done
  if [ "$from_checkout" = 1 ]; then
    # A Git bundle carries the current branch with its history, so the VM gets a real
    # checkout of work that is not on GitHub yet. Its origin still points at GitHub.
    local bundle; bundle="$(mktemp -d)/lab.bundle"
    local branch; branch="$(git -C "$HERE/.." rev-parse --abbrev-ref HEAD)"
    git -C "$HERE/.." bundle create "$bundle" "$branch" 2>/dev/null
    "${SSH[@]}" "$HOST" 'cat > /tmp/lab.bundle' < "$bundle"
    rm -rf "$(dirname "$bundle")"
    "${SSH[@]}" "$HOST" 'set -e
      command -v git >/dev/null || { sudo apt-get update -qq && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git >/dev/null; }
      if [ -d ~/k8s_lab_macos/.git ]; then
        git -C ~/k8s_lab_macos pull -q --ff-only /tmp/lab.bundle '"$branch"'
      else
        git clone -q -b '"$branch"' /tmp/lab.bundle ~/k8s_lab_macos
        git -C ~/k8s_lab_macos remote set-url origin https://github.com/miekuskamil/k8s_lab_macos
      fi
      rm /tmp/lab.bundle'
    "${SSH[@]}" "$HOST" k8s_lab_macos/proxmox/install-lab.sh ${args[@]+"${args[@]}"}
  else
    "${SSH[@]}" "$HOST" 'cat > ~/install-lab.sh && chmod +x ~/install-lab.sh' < "$HERE/install-lab.sh"
    "${SSH[@]}" "$HOST" ./install-lab.sh ${args[@]+"${args[@]}"}
  fi
}

ui() {
  # One SSH session forwards every port from the Mac to the same port on the VM and
  # runs port-forward.sh there, so http://localhost:3000 on the Mac reaches Grafana in the VM.
  local fwd=()
  for p in $PORTS; do
    if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "port $p is busy on this Mac (a local lab?). Stop it first: k3d cluster stop k8s-lab" >&2
      exit 1
    fi
    fwd+=(-L "$p:localhost:$p")
  done
  echo "The shop: http://localhost:8080   Grafana: http://localhost:3000   ArgoCD: http://localhost:8081"
  echo "Kiali: http://localhost:20001   Headlamp: http://localhost:4466   Jaeger: http://localhost:16686"
  "${SSH[@]}" -t -o ExitOnForwardFailure=yes "${fwd[@]}" "$HOST" k8s_lab_macos/scripts/port-forward.sh
}

case "${1:-}" in
  install) shift; install "$@" ;;
  ui) ui ;;
  ssh) shift; "${SSH[@]}" "$HOST" "$@" ;;
  *) sed -n '2,11p' "$0"; exit 1 ;;
esac
