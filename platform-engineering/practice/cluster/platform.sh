# Where the two practice nodes live and how the scripts reach them. Sourced by the cluster
# scripts and by tasks/lib.sh; runs on your machine (bash 3.2 is fine).
#
#   PRACTICE_PLATFORM=kind      the default: two kind nodes, which are Docker containers that run
#                               systemd, containerd and the kubelet, reached with "docker exec"
#     PRACTICE_CP   control plane node       (default practice-control-plane)
#     PRACTICE_W1   worker node              (default practice-worker)
#   PRACTICE_PLATFORM=orbstack  two OrbStack Linux machines, reached with "orb -m <node> -u root"
#     PRACTICE_CP, PRACTICE_W1               (default cks-cp and cks-w1, the machines' names)
#   PRACTICE_PLATFORM=vms       two Ubuntu 24.04 VMs you reach over SSH (Proxmox or any other
#                               hypervisor or cloud), as a user with passwordless sudo
#     PRACTICE_CP, PRACTICE_W1               (default cks-cp and cks-w1, set as their hostnames)
#     PRACTICE_CP_HOST   address of the control plane VM   (default 192.168.1.221)
#     PRACTICE_W1_HOST   address of the worker VM          (default 192.168.1.222)
#     PRACTICE_SSH_USER  login user on both VMs            (default ubuntu)
#     PRACTICE_SSH_KEY   private key for that user         (default ~/.ssh/cks_proxmox)
#     PRACTICE_SSH_OPTS  extra ssh options, for example "-o UserKnownHostsFile=/some/file"
#
# The older CKS_* names (CKS_PLATFORM, CKS_CP, CKS_SSH_KEY and so on) still work when the
# PRACTICE_* name is unset. Every command that runs on a node goes through node_sh,
# node_script or node_file below, and each of them sets CP and W1 to the two node names in the
# node's shell, so a task script says "kubectl label node $W1" on every platform.

PRACTICE_PLATFORM="${PRACTICE_PLATFORM:-${CKS_PLATFORM:-kind}}"
if [ "$PRACTICE_PLATFORM" = kind ]; then _pc_cp=practice-control-plane; _pc_w1=practice-worker
else _pc_cp=cks-cp; _pc_w1=cks-w1; fi
PRACTICE_CP="${PRACTICE_CP:-${CKS_CP:-$_pc_cp}}"
PRACTICE_W1="${PRACTICE_W1:-${CKS_W1:-$_pc_w1}}"
CP="$PRACTICE_CP"
W1="$PRACTICE_W1"
PRACTICE_CLUSTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The kind cluster's name. kind calls its nodes <name>-control-plane and <name>-worker.
PRACTICE_KIND_NAME="${PRACTICE_KIND_NAME:-practice}"
# The local image registry: a container next to the kind nodes, or a service on the control plane.
PRACTICE_REGISTRY=registry.practice:5000

case "$PRACTICE_PLATFORM" in
  kind|orbstack) ;;
  vms)
    PRACTICE_CP_HOST="${PRACTICE_CP_HOST:-${CKS_CP_HOST:-192.168.1.221}}"
    PRACTICE_W1_HOST="${PRACTICE_W1_HOST:-${CKS_W1_HOST:-192.168.1.222}}"
    PRACTICE_SSH_USER="${PRACTICE_SSH_USER:-${CKS_SSH_USER:-ubuntu}}"
    PRACTICE_SSH_KEY="${PRACTICE_SSH_KEY:-${CKS_SSH_KEY:-$HOME/.ssh/cks_proxmox}}"
    PRACTICE_SSH_OPTS="${PRACTICE_SSH_OPTS:-${CKS_SSH_OPTS:-}}"
    ;;
  *) echo "PRACTICE_PLATFORM must be kind, orbstack or vms, not '$PRACTICE_PLATFORM'" >&2; exit 1 ;;
esac

# The account on a node that gets a copy of the admin kubeconfig, like the exam's default user.
# OrbStack names it after your Mac user and gives it uid 501; a kind node has root only.
case "$PRACTICE_PLATFORM" in
  vms) PRACTICE_NODE_USER="$PRACTICE_SSH_USER" ;;
  orbstack) PRACTICE_NODE_USER=501 ;;
  kind) PRACTICE_NODE_USER=root ;;
esac

# Quote arguments so the remote shell sees them as the local one does.
_pc_quote() { [ $# -eq 0 ] || printf '%q ' "$@"; }

# The first line of every node shell: the two node names as CP and W1.
_pc_env() { printf 'CP=%q; W1=%q; ' "$CP" "$W1"; }

# ssh to a node by its name. One shared connection per node keeps the hundreds of short
# commands in a test run fast.
_pc_ssh() {
  local h
  case "$1" in
    "$CP") h="$PRACTICE_CP_HOST" ;;
    "$W1") h="$PRACTICE_W1_HOST" ;;
    *) h="$1" ;;
  esac
  shift
  # shellcheck disable=SC2086
  ssh -i "$PRACTICE_SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 \
    -o ServerAliveInterval=15 -o ControlMaster=auto -o ControlPath=/tmp/practice-ssh-%C -o ControlPersist=120 \
    $PRACTICE_SSH_OPTS "$PRACTICE_SSH_USER@$h" "$@"
}

# on <node> <command line>: run one command line as root on a node. node_sh is the same thing.
#   on practice-worker "systemctl restart kubelet"
node_sh() {
  local m="$1"; shift
  case "$PRACTICE_PLATFORM" in
    kind) docker exec -i -w /root "$m" bash -c "$(_pc_env)$*" ;;
    vms) _pc_ssh "$m" "sudo -H bash -c $(printf '%q' "$(_pc_env)$*")" ;;
    *) orb -m "$m" -u root bash -c "$(_pc_env)$*" ;;
  esac
}
on() { local m="$1"; shift; node_sh "$m" "$*"; }

# Run a script from stdin as root on a node: node_script practice-worker <<'EOF' ... EOF
node_script() {
  local m="$1"; shift
  case "$PRACTICE_PLATFORM" in
    kind) { _pc_env; echo; cat; } | docker exec -i -w /root "$m" bash -s "$@" ;;
    vms) { _pc_env; echo; cat; } | _pc_ssh "$m" "sudo -H bash -s $(_pc_quote "$@")" ;;
    *) { _pc_env; echo; cat; } | orb -m "$m" -u root bash -s "$@" ;;
  esac
}

# Run kubectl as root on the control plane.
node_kubectl() {
  case "$PRACTICE_PLATFORM" in
    kind) docker exec -i -w /root "$CP" kubectl "$@" ;;
    vms) _pc_ssh "$CP" "sudo -H kubectl $(_pc_quote "$@")" ;;
    *) orb -m "$CP" -u root kubectl "$@" ;;
  esac
}

# Run a script from this folder as root on a node, with K8S_VERSION passed through:
# node_file cks-w1 tools.sh w1. OrbStack shows your Mac's files inside the machine; a VM
# gets a copy of the scripts in /tmp/practice-cluster first.
node_file() {
  local m="$1" f="$2"; shift 2
  case "$PRACTICE_PLATFORM" in
    vms)
      (cd "$PRACTICE_CLUSTER_DIR" && COPYFILE_DISABLE=1 tar -cf - node-prep.sh tools.sh image-policy) \
        | _pc_ssh "$m" "sudo rm -rf /tmp/practice-cluster && sudo mkdir -p /tmp/practice-cluster && sudo tar --warning=no-unknown-keyword -xf - -C /tmp/practice-cluster" \
        && _pc_ssh "$m" "sudo -H env K8S_VERSION=$(printf '%q' "${K8S_VERSION:-}") bash /tmp/practice-cluster/$f $(_pc_quote "$@")" ;;
    kind)
      docker exec -i "$m" env K8S_VERSION="${K8S_VERSION:-}" bash -s "$@" < "$PRACTICE_CLUSTER_DIR/$f" ;;
    *)
      orb -m "$m" -u root env K8S_VERSION="${K8S_VERSION:-}" bash "$PRACTICE_CLUSTER_DIR/$f" "$@" ;;
  esac
}

# How to open a shell on a node, for the messages the scripts print.
node_shell_hint() {
  case "$PRACTICE_PLATFORM" in
    kind) if [ "$1" = "$W1" ]; then echo "./lab.sh practice shell worker"; else echo "./lab.sh practice shell"; fi ;;
    vms)
      local h="$PRACTICE_CP_HOST"; [ "$1" = "$W1" ] && h="$PRACTICE_W1_HOST"
      echo "ssh -i $PRACTICE_SSH_KEY $PRACTICE_SSH_USER@$h" ;;
    *) echo "orb -m $1" ;;
  esac
}
