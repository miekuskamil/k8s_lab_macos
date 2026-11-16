# Where the two practice nodes live and how the scripts reach them. Sourced by the cluster
# scripts and by tasks/lib.sh; runs on your machine (bash 3.2 is fine).
#
#   CKS_PLATFORM=orbstack   the default: two OrbStack machines, reached with "orb -m <node> -u root"
#   CKS_PLATFORM=vms        two Ubuntu 24.04 VMs you reach over SSH (Proxmox or any other
#                           hypervisor or cloud), as a user with passwordless sudo
#     CKS_CP_HOST   address of the control plane VM   (default 192.168.1.221)
#     CKS_W1_HOST   address of the worker VM          (default 192.168.1.222)
#     CKS_SSH_USER  login user on both VMs            (default ubuntu)
#     CKS_SSH_KEY   private key for that user         (default ~/.ssh/cks_proxmox)
#     CKS_SSH_OPTS  extra ssh options, for example "-o UserKnownHostsFile=/some/file"
#
# Every command that runs on a node goes through node_sh, node_script or node_file below.

CKS_PLATFORM="${CKS_PLATFORM:-orbstack}"
CKS_CP="${CKS_CP:-cks-cp}"
CKS_W1="${CKS_W1:-cks-w1}"
CKS_CLUSTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$CKS_PLATFORM" in
  orbstack) ;;
  vms)
    CKS_CP_HOST="${CKS_CP_HOST:-192.168.1.221}"
    CKS_W1_HOST="${CKS_W1_HOST:-192.168.1.222}"
    CKS_SSH_USER="${CKS_SSH_USER:-ubuntu}"
    CKS_SSH_KEY="${CKS_SSH_KEY:-$HOME/.ssh/cks_proxmox}"
    CKS_SSH_OPTS="${CKS_SSH_OPTS:-}"
    ;;
  *) echo "CKS_PLATFORM must be orbstack or vms, not '$CKS_PLATFORM'" >&2; exit 1 ;;
esac

# The account on a node that gets a copy of the admin kubeconfig, like the exam's default user.
# OrbStack names it after your Mac user and gives it uid 501.
if [ "$CKS_PLATFORM" = vms ]; then CKS_NODE_USER="$CKS_SSH_USER"; else CKS_NODE_USER=501; fi

# Quote arguments so the remote shell sees them as the local one does.
_cks_quote() { [ $# -eq 0 ] || printf '%q ' "$@"; }

# ssh to a node by its name (cks-cp or cks-w1). One shared connection per node keeps the
# hundreds of short commands in a test run fast.
_cks_ssh() {
  local h
  case "$1" in
    "$CKS_CP") h="$CKS_CP_HOST" ;;
    "$CKS_W1") h="$CKS_W1_HOST" ;;
    *) h="$1" ;;
  esac
  shift
  # shellcheck disable=SC2086
  ssh -i "$CKS_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 -o ControlMaster=auto -o ControlPath=/tmp/cks-ssh-%C -o ControlPersist=120 \
    $CKS_SSH_OPTS "$CKS_SSH_USER@$h" "$@"
}

# Run one command line as root on a node: node_sh cks-cp "kubectl get nodes"
node_sh() {
  local m="$1"; shift
  if [ "$CKS_PLATFORM" = vms ]; then _cks_ssh "$m" "sudo -H bash -c $(printf '%q' "$*")"
  else orb -m "$m" -u root bash -c "$*"; fi
}

# Run a script from stdin as root on a node: node_script cks-w1 <<'EOF' ... EOF
node_script() {
  local m="$1"; shift
  if [ "$CKS_PLATFORM" = vms ]; then _cks_ssh "$m" "sudo -H bash -s $(_cks_quote "$@")"
  else orb -m "$m" -u root bash -s "$@"; fi
}

# Run kubectl as root on the control plane.
node_kubectl() {
  if [ "$CKS_PLATFORM" = vms ]; then _cks_ssh "$CKS_CP" "sudo -H kubectl $(_cks_quote "$@")"
  else orb -m "$CKS_CP" -u root kubectl "$@"; fi
}

# Run a script from this folder as root on a node, with K8S_VERSION passed through:
# node_file cks-w1 tools.sh w1. OrbStack shows your Mac's files inside the machine; a VM
# gets a copy of the scripts in /tmp/cks-cluster first.
node_file() {
  local m="$1" f="$2"; shift 2
  if [ "$CKS_PLATFORM" = vms ]; then
    (cd "$CKS_CLUSTER_DIR" && COPYFILE_DISABLE=1 tar -cf - node-prep.sh tools.sh image-policy) \
      | _cks_ssh "$m" "sudo rm -rf /tmp/cks-cluster && sudo mkdir -p /tmp/cks-cluster && sudo tar --warning=no-unknown-keyword -xf - -C /tmp/cks-cluster" \
      && _cks_ssh "$m" "sudo -H env K8S_VERSION=$(printf '%q' "${K8S_VERSION:-}") bash /tmp/cks-cluster/$f $(_cks_quote "$@")"
  else
    orb -m "$m" -u root env K8S_VERSION="${K8S_VERSION:-}" bash "$CKS_CLUSTER_DIR/$f" "$@"
  fi
}

# How to open a shell on a node, for the messages the scripts print.
node_shell_hint() {
  if [ "$CKS_PLATFORM" = vms ]; then
    local h="$CKS_CP_HOST"; [ "$1" = "$CKS_W1" ] && h="$CKS_W1_HOST"
    echo "ssh -i $CKS_SSH_KEY $CKS_SSH_USER@$h"
  else
    echo "orb -m $1"
  fi
}
