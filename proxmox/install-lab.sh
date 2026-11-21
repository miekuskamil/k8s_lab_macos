#!/usr/bin/env bash
# Installs the Platform Engineering lab on a fresh Ubuntu 24.04 machine, for example
# the pe-lab VM on Proxmox. Run it on that machine as a normal user with sudo rights:
#
#   ./install-lab.sh                 Docker, the tools, the repository, then provision.sh
#   ./install-lab.sh --with-ollama   the same, plus Ollama and its models for track 5
#   ./install-lab.sh --no-provision  install everything but leave the cluster alone
#
# Safe to run again: every step checks what is already there and skips it.
# The steps follow README.md, section "Linux". Settings come from the environment:
#   LAB_DIR=~/k8s_lab_macos   where the repository lives (ignored when the script runs from a checkout)
#   LAB_REPO_URL=https://github.com/miekuskamil/k8s_lab_macos
#   LAB_APT_MIRROR=https://gb.archive.ubuntu.com/ubuntu   the apt mirror to use; set it where
#                             plain-HTTP apt downloads hang, as on the author's Proxmox network
set -euo pipefail

KUBECTL_VERSION=1.31.5
HELM_VERSION=4.3.1
K3D_VERSION=5.9.0
ISTIO_VERSION=1.32.0   # the client; the control plane stays at 1.24.2 (module 3.18 needs a client this new)
OLLAMA_VERSION=0.40.13
OLLAMA_MODELS="qwen2.5:3b nomic-embed-text"
LAB_REPO_URL="${LAB_REPO_URL:-https://github.com/miekuskamil/k8s_lab_macos}"
LAB_DIR="${LAB_DIR:-$HOME/k8s_lab_macos}"

with_ollama=0
provision=1
for arg in "$@"; do
  case "$arg" in
    --with-ollama) with_ollama=1 ;;
    --no-provision) provision=0 ;;
    *) sed -n '2,15p' "$0"; exit 1 ;;
  esac
done

say() { printf '\n=== %s\n' "$*"; }
ok() { printf '  ok  %s\n' "$*"; }
die() { printf 'fail  %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -ne 0 ] || die "run this as your normal user, not as root: the script calls sudo where it needs to"
. /etc/os-release
[ "$ID" = ubuntu ] || die "this script expects Ubuntu, found $PRETTY_NAME"
[ "$VERSION_ID" = 24.04 ] || printf 'warn  tested on Ubuntu 24.04, this is %s\n' "$VERSION_ID"
sudo -n true 2>/dev/null || sudo -v || die "your user needs sudo rights"
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in amd64|arm64) ;; *) die "no lab tools for architecture $ARCH" ;; esac
start=$(date +%s)
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# fetch <url> <file>: downloads into the temporary directory
fetch() { curl -fsSL --retry 3 -o "$TMP/$2" "$1"; }
# check <file> <sha256>: stops the script when the download does not match its published checksum
check() { echo "$2  $TMP/$1" | sha256sum -c --quiet - || die "checksum mismatch for $1"; }

packages() {
  say "Ubuntu packages: Docker Engine, git, curl, python3"
  # On a fresh cloud image, cloud-init's first-boot upgrade holds the apt lock for a while.
  if command -v cloud-init >/dev/null; then cloud-init status --wait >/dev/null 2>&1 || true; fi
  local sources=/etc/apt/sources.list.d/ubuntu.sources
  if [ -n "${LAB_APT_MIRROR:-}" ] && [ -f "$sources" ] && grep -qE '^URIs: http://' "$sources"; then
    sudo sed -i -E "s#^URIs: http://[a-z.]*ubuntu\.com/ubuntu(-ports)?/?\$#URIs: $LAB_APT_MIRROR#" "$sources"
    ok "apt uses $LAB_APT_MIRROR"
  fi
  local need=()
  for p in docker.io git curl python3 ca-certificates; do
    dpkg -s "$p" >/dev/null 2>&1 || need+=("$p")
  done
  [ "$with_ollama" = 0 ] || dpkg -s zstd >/dev/null 2>&1 || need+=(zstd)
  if [ "${#need[@]}" -gt 0 ]; then
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need[@]}" >/dev/null
  fi
  sudo systemctl enable --now docker >/dev/null 2>&1
  ok "docker $(docker --version | awk '{print $3}' | tr -d ,)"
  if ! id -nG "$USER" | grep -qw docker; then
    sudo usermod -aG docker "$USER"
    ok "added $USER to the docker group"
  fi
}

kubectl_tool() {
  if kubectl version --client 2>/dev/null | grep -q "v$KUBECTL_VERSION"; then ok "kubectl $KUBECTL_VERSION already installed"; return; fi
  local base="https://dl.k8s.io/release/v$KUBECTL_VERSION/bin/linux/$ARCH/kubectl"
  fetch "$base" kubectl
  check kubectl "$(curl -fsSL "$base.sha256")"
  sudo install "$TMP/kubectl" /usr/local/bin/kubectl
  ok "kubectl $KUBECTL_VERSION"
}

helm_tool() {
  if helm version --short 2>/dev/null | grep -q "v$HELM_VERSION"; then ok "helm $HELM_VERSION already installed"; return; fi
  local file="helm-v$HELM_VERSION-linux-$ARCH.tar.gz"
  fetch "https://get.helm.sh/$file" "$file"
  check "$file" "$(curl -fsSL "https://get.helm.sh/$file.sha256sum" | awk '{print $1}')"
  tar -xzf "$TMP/$file" -C "$TMP"
  sudo install "$TMP/linux-$ARCH/helm" /usr/local/bin/helm
  ok "helm $HELM_VERSION"
}

k3d_tool() {
  if k3d version 2>/dev/null | grep -q "v$K3D_VERSION"; then ok "k3d $K3D_VERSION already installed"; return; fi
  local base="https://github.com/k3d-io/k3d/releases/download/v$K3D_VERSION"
  fetch "$base/k3d-linux-$ARCH" k3d
  fetch "$base/checksums.txt" k3d-sums
  check k3d "$(awk -v f="k3d-linux-$ARCH" '$2 ~ f"$" {print $1}' "$TMP/k3d-sums")"
  sudo install "$TMP/k3d" /usr/local/bin/k3d
  ok "k3d $K3D_VERSION"
}

istioctl_tool() {
  if istioctl version --remote=false 2>/dev/null | grep -q "$ISTIO_VERSION"; then ok "istioctl $ISTIO_VERSION already installed"; return; fi
  local file="istioctl-$ISTIO_VERSION-linux-$ARCH.tar.gz"
  local base="https://github.com/istio/istio/releases/download/$ISTIO_VERSION/$file"
  fetch "$base" "$file"
  check "$file" "$(curl -fsSL "$base.sha256" | awk '{print $1}')"
  tar -xzf "$TMP/$file" -C "$TMP"
  sudo install "$TMP/istioctl" /usr/local/bin/istioctl
  ok "istioctl $ISTIO_VERSION"
}

inotify() {
  say "inotify limits"
  # The lab's many pods watch more files than Ubuntu's default allows, and pods then
  # fail with "too many open files". The file in sysctl.d keeps the limit after a reboot.
  local conf=/etc/sysctl.d/99-k8s-lab.conf
  local want=$'fs.inotify.max_user_instances=512\nfs.inotify.max_user_watches=524288'
  if [ "$(cat "$conf" 2>/dev/null)" != "$want" ]; then
    echo "$want" | sudo tee "$conf" >/dev/null
  fi
  sudo sysctl -q --system
  ok "max_user_instances $(cat /proc/sys/fs/inotify/max_user_instances)"
}

repository() {
  say "The lab repository"
  # When the script runs from a checkout (proxmox/install-lab.sh inside the repository),
  # it uses that checkout as it is, so an unpushed branch works too.
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [ -x "$here/scripts/provision.sh" ] && git -C "$here" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    LAB_DIR="$here"
    ok "using the checkout at $LAB_DIR ($(git -C "$LAB_DIR" rev-parse --abbrev-ref HEAD))"
  elif [ -d "$LAB_DIR/.git" ]; then
    if [ -n "$(git -C "$LAB_DIR" status --porcelain)" ]; then
      ok "$LAB_DIR has local changes, leaving it as it is"
    else
      git -C "$LAB_DIR" pull --ff-only -q
      ok "updated $LAB_DIR to $(git -C "$LAB_DIR" log -1 --format='%h %s')"
    fi
  else
    git clone -q "$LAB_REPO_URL" "$LAB_DIR"
    ok "cloned $LAB_REPO_URL into $LAB_DIR"
  fi
}

# as_docker <command...>: runs a command with the docker group, which a fresh
# group membership only gives after the next login.
as_docker() {
  if id -nG | grep -qw docker; then "$@"; else sg docker -c "$(printf '%q ' "$@")"; fi
}

lab() {
  say "Provisioning the lab (about 10 minutes the first time)"
  local t0; t0=$(date +%s)
  as_docker "$LAB_DIR/scripts/provision.sh"
  ok "provision.sh finished in $(( $(date +%s) - t0 )) seconds"
}

ollama_install() {
  say "Ollama $OLLAMA_VERSION for the AI modules"
  if ! /usr/local/bin/ollama --version 2>/dev/null | grep -q "$OLLAMA_VERSION"; then
    local file="ollama-linux-$ARCH.tar.zst"
    local base="https://github.com/ollama/ollama/releases/download/v$OLLAMA_VERSION"
    fetch "$base/$file" "$file"
    fetch "$base/sha256sum.txt" ollama-sums
    check "$file" "$(awk -v f="$file" '$2 ~ f"$" {print $1}' "$TMP/ollama-sums")"
    sudo rm -rf /usr/local/lib/ollama
    zstd -dc "$TMP/$file" | sudo tar -x -C /usr/local
    ok "ollama $OLLAMA_VERSION in /usr/local/bin"
  else
    ok "ollama $OLLAMA_VERSION already installed"
  fi
  id ollama >/dev/null 2>&1 || sudo useradd -r -s /bin/false -U -m -d /usr/share/ollama ollama
  # Pods reach Ollama through the k3d network's gateway, not through 127.0.0.1,
  # so Ollama listens on every interface (README.md, section "Ollama on Linux", explains the trade-off).
  sudo tee /etc/systemd/system/ollama.service >/dev/null <<'UNIT'
[Unit]
Description=Ollama Service
After=network-online.target

[Service]
ExecStart=/usr/local/bin/ollama serve
User=ollama
Group=ollama
Restart=always
RestartSec=3
Environment="OLLAMA_HOST=0.0.0.0"

[Install]
WantedBy=multi-user.target
UNIT
  sudo systemctl daemon-reload
  sudo systemctl enable -q ollama
  sudo systemctl restart ollama
  for _ in $(seq 1 30); do curl -fs -m 2 http://localhost:11434/api/tags >/dev/null && break; sleep 1; done
  for m in $OLLAMA_MODELS; do
    if /usr/local/bin/ollama list | awk 'NR>1 {print $1}' | grep -qx "$m\(:latest\)\?"; then
      ok "model $m already pulled"
    else
      /usr/local/bin/ollama pull "$m" >/dev/null
      ok "pulled $m"
    fi
  done
}

ollama_dns() {
  say "host.docker.internal inside the cluster"
  # Plain Docker Engine has no host.docker.internal, so CoreDNS learns that the name
  # means the gateway of the k3d network, which is this machine.
  local gw
  gw="$(as_docker docker network inspect k3d-k8s-lab -f '{{(index .IPAM.Config 0).Gateway}}')"
  kubectl -n kube-system create configmap coredns-custom \
    --from-literal=hostdocker.server="host.docker.internal:53 {
  hosts {
    $gw host.docker.internal
  }
}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n kube-system rollout restart deploy/coredns >/dev/null
  kubectl -n kube-system rollout status deploy/coredns --timeout=120s >/dev/null
  local answer
  answer="$(kubectl run ollama-check --rm -i --restart=Never --image=curlimages/curl:8.11.1 -q -- \
    curl -s -m 10 http://host.docker.internal:11434/api/tags 2>/dev/null || true)"
  if echo "$answer" | grep -q '"models"'; then
    ok "a pod reaches Ollama at host.docker.internal ($gw)"
  else
    die "a pod gets no model list from host.docker.internal:11434 (got: ${answer:-nothing})"
  fi
}

packages
say "Lab tools for $ARCH"
kubectl_tool
helm_tool
k3d_tool
istioctl_tool
inotify
repository
[ "$with_ollama" = 0 ] || ollama_install
[ "$provision" = 0 ] || lab
[ "$with_ollama" = 0 ] || [ "$provision" = 0 ] || ollama_dns

say "Done in $(( $(date +%s) - start )) seconds"
echo "The repository is in $LAB_DIR. Log out and back in once so docker works without sudo."
echo "Check the course: cd $LAB_DIR && ./platform-engineering/verify.sh"
