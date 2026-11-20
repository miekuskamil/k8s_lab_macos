#!/usr/bin/env bash
# One entry point for the lab. Each command runs one of the scripts in scripts/ or
# platform-engineering/, so the course text and this file always do the same thing.
#
#   ./lab.sh help    lists the commands
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# The same variable and default that scripts/provision.sh uses.
CLUSTER_NAME="${CLUSTER_NAME:-k8s-lab}"
K=(kubectl --context "k3d-${CLUSTER_NAME}")

usage() {
  cat <<'HELP'
Usage: ./lab.sh <command> [arguments]

  up          build the whole lab from nothing (about 10 minutes the first time)
  start       bring the lab back after a reboot, sleep or ./lab.sh stop
  stop        stop the cluster to free memory; ./lab.sh start resumes it
  status      show the cluster, nodes, ArgoCD apps and any pod that is not Running
  ui          open the web UIs on localhost; Ctrl-C closes them
  test        send 100 requests to the shop and print the version split
  test N...   run the course checks for modules N, for example: ./lab.sh test 4 5
  test all    run the course checks for every module (about 40 minutes)
  reset       undo course exercises and return to the Git baseline (--all also
              removes the course namespaces)
  down        delete the cluster and everything in it (asks first, --yes skips)
  help        show this list

The practice cluster for modules 33 to 43 (two kubeadm nodes in Docker, built with kind):
  practice up              build it (about 3 minutes the first time, 2 after that)
  practice reset           build it again from scratch, to start a module clean
  practice down            delete it (asks first, --yes skips)
  practice shell [node]    open a root shell on the control plane, or on "worker"
  task setup|check|solve|list ID     the timed tasks, for example: ./lab.sh task setup 38.3
  exam setup|score|solve N [task]    the six practice exams, for example: ./lab.sh exam setup 4
HELP
}

status() {
  if ! k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
    echo "No cluster named ${CLUSTER_NAME}. Run ./lab.sh up to build it."
    return 1
  fi
  if [[ -z "$(docker ps --filter "name=k3d-${CLUSTER_NAME}-server-0" --format '{{.Names}}')" ]]; then
    echo "Cluster ${CLUSTER_NAME} is stopped. Run ./lab.sh start."
    return 1
  fi
  echo "== Nodes"
  "${K[@]}" get nodes
  echo
  echo "== ArgoCD applications"
  "${K[@]}" -n argocd get applications
  echo
  echo "== Pods that are not Running or Completed"
  local pods
  pods="$("${K[@]}" get pods -A --no-headers | grep -vE ' (Running|Completed) ' || true)"
  echo "${pods:-none}"
}

# ./lab.sh practice up|reset|down|shell [node]
practice() {
  local cluster="$ROOT/platform-engineering/practice/cluster" sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    up)    exec "$cluster/create.sh" "$@" ;;
    reset) exec "$cluster/reset.sh" "$@" ;;
    down)  exec "$cluster/destroy.sh" "$@" ;;
    shell)
      # shellcheck source=/dev/null
      . "$cluster/platform.sh"
      local node="$CP"
      case "${1:-}" in
        ""|cp|control-plane) node="$CP" ;;
        w1|worker) node="$W1" ;;
        *) node="$1" ;;
      esac
      case "$PRACTICE_PLATFORM" in
        kind) exec docker exec -it -w /root "$node" bash ;;
        orbstack) exec orb -m "$node" -u root bash -c 'cd /root && exec bash -i' ;;
        vms) local h="$PRACTICE_CP_HOST"; [[ "$node" == "$W1" ]] && h="$PRACTICE_W1_HOST"
             exec ssh -t -i "$PRACTICE_SSH_KEY" $PRACTICE_SSH_OPTS "$PRACTICE_SSH_USER@$h" sudo -i ;;
      esac ;;
    *) echo "Usage: ./lab.sh practice up|reset|down|shell [worker]" >&2; exit 1 ;;
  esac
}

command="${1:-help}"
[[ $# -gt 0 ]] && shift

case "$command" in
  up)     exec "$ROOT/scripts/provision.sh" "$@" ;;
  start)  exec "$ROOT/scripts/start.sh" "$@" ;;
  stop)   exec k3d cluster stop "$CLUSTER_NAME" ;;
  status) status ;;
  ui)     exec "$ROOT/scripts/port-forward.sh" ;;
  test)
    if [[ $# -eq 0 ]]; then
      exec "$ROOT/scripts/traffic-test.sh"
    elif [[ "$1" == "all" ]]; then
      exec "$ROOT/platform-engineering/verify.sh"
    else
      exec "$ROOT/platform-engineering/verify.sh" "$@"
    fi
    ;;
  reset)  exec "$ROOT/platform-engineering/reset.sh" "$@" ;;
  down)   exec "$ROOT/scripts/teardown.sh" "$@" ;;
  practice) practice "$@" ;;
  task)   exec "$ROOT/platform-engineering/task.sh" "$@" ;;
  exam)   exec "$ROOT/platform-engineering/practice-exam.sh" "$@" ;;
  help|-h|--help) usage ;;
  *)
    echo "Unknown command: ${command}" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
