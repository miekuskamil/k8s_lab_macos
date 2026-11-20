# Helpers for the security task scripts. Sourced by task.sh and exams/*.sh; runs on your machine
# (bash 3.2 is fine). Everything on the cluster goes through cluster/platform.sh: "orb -m <node>
# -u root" on OrbStack, ssh and sudo with CKS_PLATFORM=vms.

CKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CKS_DIR/../cluster/platform.sh"

# Run a script from stdin as root on a node: oncp <<'EOF' ... EOF
oncp() { node_script "$CKS_CP" "$@"; }
onw1() { node_script "$CKS_W1" "$@"; }
# Run one command line on a node and print its output.
cp_sh() { node_sh "$CKS_CP" "$*"; }
w1_sh() { node_sh "$CKS_W1" "$*"; }
k() { node_kubectl "$@"; }
# Some checks run in "bash -c", so that shell needs the helpers and the settings too.
export CKS_PLATFORM CKS_CP CKS_W1 CKS_CP_HOST CKS_W1_HOST CKS_SSH_USER CKS_SSH_KEY CKS_SSH_OPTS
export -f _cks_quote _cks_ssh node_sh node_script node_kubectl cp_sh w1_sh k

# The Lima VM (cluster/lima.sh) runs the Cilium tasks on a kernel of its own, and under
# OrbStack the AppArmor and kernel module tasks as well.
CKS_LIMA="${CKS_LIMA:-cks-lima}"
onlima() { limactl shell --workdir / "$CKS_LIMA" sudo bash -s "$@"; }
lima_sh() { limactl shell --workdir / "$CKS_LIMA" sudo bash -c "$*"; }
kl() { limactl shell --workdir / "$CKS_LIMA" sudo kubectl "$@"; }
# Stop early with a clear message when a Lima task runs while the VM is down.
need_lima() {
  if [ "$(limactl list --format '{{.Status}}' "$CKS_LIMA" 2>/dev/null)" != Running ]; then
    echo "  this task runs on the Lima VM $CKS_LIMA: ./platform-engineering/practice/cluster/lima.sh start (or create)"
    return 1
  fi
}

# The AppArmor and kernel module tasks need a kernel that belongs to one machine. OrbStack's
# shared kernel has no AppArmor, so there they run on the Lima VM. A real VM has a kernel of its
# own, so with CKS_PLATFORM=vms they run on cks-w1, where the pods land. The scripts these
# helpers run call kubectl on the node, so on cks-w1 they get the admin kubeconfig in a
# temporary file that the script deletes when it ends.
if [ "$CKS_PLATFORM" = vms ]; then
  _cks_admin_prelude() {
    # ssh reads stdin, which holds the caller's script here, so it gets /dev/null instead.
    [ -n "${_CKS_ADMIN_CONF:-}" ] || _CKS_ADMIN_CONF="$(cp_sh 'cat /etc/kubernetes/admin.conf' </dev/null)"
    echo 'KUBECONFIG="$(mktemp)"; export KUBECONFIG; trap '"'"'rm -f "$KUBECONFIG"'"'"' EXIT'
    echo "cat > \"\$KUBECONFIG\" <<'CKS_ADMIN_CONF'"
    printf '%s\n' "$_CKS_ADMIN_CONF"
    echo 'CKS_ADMIN_CONF'
  }
  onkern() { { _cks_admin_prelude; cat; } | onw1 "$@"; }
  kern_sh() { { _cks_admin_prelude; printf '%s\n' "$*"; } | onw1; }
  need_kernel() { :; }
else
  onkern() { onlima "$@"; }
  kern_sh() { lima_sh "$@"; }
  need_kernel() { need_lima; }
fi
check_kern() { local what="$1"; shift; check "$what" kern_sh "$*"; }

PASSES=0
FAILS=0
# check "what" <command...>: the command's exit code decides PASS or FAIL.
# FIRST_OK records whether the first check since the counters were reset passed.
FIRST_OK=""
check() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$what"; PASSES=$((PASSES + 1))
    [ -n "$FIRST_OK" ] || FIRST_OK=yes
  else
    printf '  FAIL  %s\n' "$what"; FAILS=$((FAILS + 1))
    [ -n "$FIRST_OK" ] || FIRST_OK=no
  fi
}
# Like check, but the command runs on cks-cp (or cks-w1) as root.
check_cp() { local what="$1"; shift; check "$what" cp_sh "$*"; }
check_w1() { local what="$1"; shift; check "$what" w1_sh "$*"; }
check_lima() { local what="$1"; shift; check "$what" lima_sh "$*"; }

# Wait until the API server answers again after a static pod edit.
wait_api() {
  cp_sh 'for i in $(seq 1 90); do kubectl get --raw=/readyz >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'
}

# Wait until a static pod's mirror pod is Ready again: wait_static kube-scheduler
wait_static() {
  cp_sh "for i in \$(seq 1 60); do kubectl -n kube-system get pod $1-cks-cp -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null | grep -qx True && exit 0; sleep 3; done; exit 1"
}

# Mount a host folder into the API server pod: apiserver_mount auth-config /etc/kubernetes/auth
# Skips the edit when a volume of that name already exists.
apiserver_mount() {
  cp_sh "f=/etc/kubernetes/manifests/kube-apiserver.yaml
    grep -q 'name: $1\$' \$f && exit 0
    sed -i 's|^    volumeMounts:\$|    volumeMounts:\n    - mountPath: $2\n      name: $1\n      readOnly: ${3:-true}|' \$f
    sed -i 's|^  volumes:\$|  volumes:\n  - hostPath:\n      path: $2\n      type: DirectoryOrCreate\n    name: $1|' \$f"
}

# Edit a flag in a static pod manifest on cks-cp: set_flag kube-apiserver --profiling false
# Adds the flag when missing, replaces its value when present.
set_flag() {
  cp_sh "f=/etc/kubernetes/manifests/$1.yaml
    if grep -q -- '- $2=' \$f; then sed -i 's|- $2=.*|- $2=$3|' \$f
    else sed -i '0,/- $1\$/s||- $1\n    - $2=$3|' \$f; fi"
}
