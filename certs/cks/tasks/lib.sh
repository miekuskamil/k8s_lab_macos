# Helpers for the CKS task scripts. Sourced by task.sh and mock-exam/*.sh; runs on the Mac
# (bash 3.2 is fine). Everything on the cluster goes through "orb -m <node> -u root".

CKS_CP="${CKS_CP:-cks-cp}"
CKS_W1="${CKS_W1:-cks-w1}"
CKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run a script from stdin as root on a node: oncp <<'EOF' ... EOF
oncp() { orb -m "$CKS_CP" -u root bash -s "$@"; }
onw1() { orb -m "$CKS_W1" -u root bash -s "$@"; }
# Run one command line on a node and print its output.
cp_sh() { orb -m "$CKS_CP" -u root bash -c "$*"; }
w1_sh() { orb -m "$CKS_W1" -u root bash -c "$*"; }
k() { orb -m "$CKS_CP" -u root kubectl "$@"; }

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

# Wait until the API server answers again after a static pod edit.
wait_api() {
  cp_sh 'for i in $(seq 1 90); do kubectl get --raw=/readyz >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1'
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
