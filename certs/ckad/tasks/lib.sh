# Helpers for the CKAD task scripts. Sourced by task.sh and mock-exam/*.sh; runs on your Mac
# (bash 3.2 is fine). It builds on the CKS helpers, so every node command goes through
# certs/cks/cluster/platform.sh: "orb -m <node> -u root" on OrbStack, ssh and sudo with CKS_PLATFORM=vms.

CKAD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$CKAD_DIR/../cks/tasks/lib.sh"

# Every namespace a CKAD task creates carries the label ckad=task (or ckad=mock), so the
# CKAD reset finds them all: ns_new web-team shop
NS_LABEL="${NS_LABEL:-task}"
ns_new() {
  local n
  for n in "$@"; do
    cp_sh "kubectl create ns $n --dry-run=client -o yaml | kubectl apply -f - >/dev/null
      kubectl label ns $n ckad=$NS_LABEL --overwrite >/dev/null
      for i in \$(seq 1 30); do kubectl -n $n get sa default >/dev/null 2>&1 && break; sleep 1; done"
  done
}

# Run commands on a node as root and print each one after a prompt, the way the solution
# transcripts show them. One command per line; lines starting with # are skipped.
#   shown <<'EOF'            on cks-cp
#   shown cks-w1 <<'EOF'     on cks-w1
shown() {
  local m="${1:-$CKS_CP}"
  {
    echo 'shopt -s expand_aliases; alias k=kubectl; export do="--dry-run=client -o yaml"; cd /root'
    echo "cat > /tmp/.ckad-shown <<'CKAD_SHOWN'"
    cat
    echo 'CKAD_SHOWN'
    echo 'while IFS= read -r l; do case "$l" in ""|"#"*) continue;; esac; echo "root@'"$m"':~# $l"; eval "$l" </dev/null 2>&1; done < /tmp/.ckad-shown; rm -f /tmp/.ckad-shown'
  } | node_script "$m"
}

# A namespace from scratch: deletes it first when an earlier run left it behind.
ns_fresh() {
  local n
  for n in "$@"; do
    cp_sh "kubectl get ns $n >/dev/null 2>&1 && kubectl delete ns $n --timeout=120s >/dev/null; true"
  done
  ns_new "$@"
}

# Wait until only the pods of the newest rollout are left: settled ns app-label count
# Old pods of a "sh -c" container take 30 seconds to stop, because sh as process 1 ignores SIGTERM.
settled() {
  cp_sh "for i in \$(seq 1 45); do [ \"\$(kubectl -n $1 get pods -l app=$2 --no-headers 2>/dev/null | wc -l)\" = $3 ] && exit 0; sleep 2; done; exit 1"
}

# Write a file on cks-cp from stdin: put_file /opt/ckad/1.3/pod.yaml <<'EOF' ... EOF
put_file() { cp_sh "mkdir -p \$(dirname $1) && cat > $1" ; }

# The tasks that use "kubectl top" need metrics-server; the CKAD reset removes it again.
need_metrics() { "$CKAD_DIR/cluster/extras.sh" metrics >/dev/null; }

# The tasks that use helm, podman or the registry need extras.sh first.
need_extras() {
  if ! cp_sh 'command -v helm && command -v podman && curl -fsS http://registry.ckad:5000/v2/' >/dev/null 2>&1; then
    echo "  this task needs the CKAD extras: ./certs/ckad/cluster/extras.sh"
    return 1
  fi
}

# Wait until a Deployment has rolled out: rolled ns name
rolled() { cp_sh "kubectl -n $1 rollout status deploy $2 --timeout=180s" >/dev/null; }

# A check that runs a Python test on JSON from kubectl, on cks-cp:
#   check_json "what" "kubectl -n x get pod y -o json" 'p["spec"]["containers"][0]["name"] == "app"'
# The JSON is in the variable p. Statements may come first, separated by ';' from the final test.
check_json() {
  local what="$1" get="$2" expr="$3"
  check_cp "$what" "$get | python3 -c 'import json,sys; p=json.load(sys.stdin); _e=sys.argv[1].rsplit(\";\",1); exec(_e[0]) if len(_e)>1 else None; sys.exit(0 if eval(_e[-1]) else 1)' '$expr'"
}
