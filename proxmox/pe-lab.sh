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
#   PE_LAB_PORT_OFFSET=0               added to every port on the Mac side of "ui"
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
  # PE_LAB_PORT_OFFSET=10000 moves the Mac side to 18080, 13000 and so on, next to a running local lab.
  local off="${PE_LAB_PORT_OFFSET:-0}" fwd=()
  for p in $PORTS; do
    if lsof -nP -iTCP:"$((p + off))" -sTCP:LISTEN >/dev/null 2>&1; then
      echo "port $((p + off)) is busy on this Mac (a local lab?). Stop it with 'k3d cluster stop k8s-lab' or set PE_LAB_PORT_OFFSET=10000" >&2
      exit 1
    fi
    fwd+=(-L "$((p + off)):localhost:$p")
  done
  echo "The shop: http://localhost:$((8080 + off))   Grafana: http://localhost:$((3000 + off))   ArgoCD: http://localhost:$((8081 + off))"
  echo "Kiali: http://localhost:$((20001 + off))   Headlamp: http://localhost:$((4466 + off))   Jaeger: http://localhost:$((16686 + off))"
  # A dropped connection leaves the VM's kubectl port-forwards behind, so clear them first.
  "${SSH[@]}" -t -o ExitOnForwardFailure=yes "${fwd[@]}" "$HOST" \
    'pkill -f "kubectl --context k3d-k8s-lab -n [a-z-]* port-forward svc/" ; k8s_lab_macos/scripts/port-forward.sh'
}

case "${1:-}" in
  install) shift; install "$@" ;;
  ui) ui ;;
  ssh) shift; "${SSH[@]}" "$HOST" "$@" ;;
  *) sed -n '2,12p' "$0"; exit 1 ;;
esac
