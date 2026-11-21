#!/usr/bin/env bash
# One entry point for the lab. Each command runs one of the scripts in scripts/ or
# platform-engineering/, so the course text and this file always do the same thing.
#
#   ./lab.sh help    lists the commands
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Your settings, when you made a lab.env from lab.env.example. Git ignores lab.env.
if [[ -f "$ROOT/lab.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  . "$ROOT/lab.env"
  set +a
fi
# The same variable and default that scripts/provision.sh uses.
CLUSTER_NAME="${CLUSTER_NAME:-k8s-lab}"
export CLUSTER_NAME
# verify.sh and reset.sh read the kubectl context from KUBE_CONTEXT.
export KUBE_CONTEXT="${KUBE_CONTEXT:-k3d-${CLUSTER_NAME}}"
K=(kubectl --context "$KUBE_CONTEXT")

usage() {
  cat <<'HELP'
Usage: ./lab.sh <command> [arguments]

  shell       open a shell in the toolbox container, which has every tool the lab
              needs; your machine needs only Docker and git (see "The toolbox" below)
  up          build the whole lab from nothing (about 10 minutes the first time)
  start       bring the lab back after a reboot, sleep or ./lab.sh stop
  stop        stop the cluster to free memory; ./lab.sh start resumes it
  status      show the cluster, nodes, ArgoCD apps and any pod that is not Running
  ui          open the web UIs on localhost; Ctrl-C closes them
  test        send 100 requests to the shop and print the version split
  test ID...  run the course checks for modules ID, for example: ./lab.sh test 3.4 3.5
  test all    run the course checks for every lab module that is safe to repeat (about 50 minutes)
  reset       undo course exercises and return to the Git baseline (--all also
              removes the course namespaces)
  down        delete the cluster and everything in it (asks first, --yes skips)
  ai          store the AI settings from lab.env in the cluster (see lab.env.example)
  ollama      run Ollama in a container, for machines without Ollama, and pull the
              two models the course uses
  help        show this list

The practice cluster for tracks 1 and 4 (two kubeadm nodes in Docker, built with kind):
  practice up              build it (about 3 minutes the first time, 2 after that)
  practice reset           build it again from scratch, to start a module clean
  practice down            delete it (asks first, --yes skips)
  practice shell [node]    open a root shell on the control plane, or on "worker"
  practice cilium up|reset|down|shell   with PRACTICE_PLATFORM=vms, the one-node Cilium
                           cluster on its own VM, for the Cilium tasks of module 4.7
  task setup|check|solve|list ID     the timed tasks, for example: ./lab.sh task setup 4.1.3
  exam setup|score|solve N [task]    the six practice exams, for example: ./lab.sh exam setup 4

The toolbox (toolbox/Dockerfile and compose.yaml):
  shell                    start the toolbox and open a shell in it, in the repo folder
  toolbox build            build the toolbox image again, after you changed toolbox/
  toolbox stop             stop and remove the toolbox container (your kubeconfig stays)
  Every command above works the same inside the toolbox. Run outside it, on a machine
  without kubectl, helm or k3d, a command goes through the toolbox by itself, except task
  and exam, which reach the nodes and the Lima VM from your machine with docker and limactl.
  LAB_USE_TOOLBOX=always or LAB_USE_TOOLBOX=never overrides that choice.

README.md is the guide: logins, everyday commands, the course and troubleshooting.
HELP
}

# --- The toolbox container -------------------------------------------------------------
COMPOSE=(docker compose -f "$ROOT/compose.yaml")
TOOLBOX_IMAGE="$(awk '/^ *image: k8s-lab\/toolbox:/ {print $2; exit}' "$ROOT/compose.yaml")"
# Settings that pass from your shell into the toolbox when they are set.
PASS_ENV=(CLUSTER_NAME KUBE_CONTEXT BASE_URL SKIP_IMAGE_BUILD ISTIO_VERSION ISTIO_PLATFORM
  SYNC_TIMEOUT_SECONDS LAB_OLLAMA_URL LAB_OLLAMA_MODEL PRACTICE_PLATFORM PRACTICE_KIND_NAME
  PRACTICE_NODE_IMAGE K8S_VERSION TERM
  # The practice cluster on your own VMs (PRACTICE_PLATFORM=vms), and the older CKS_* names.
  PRACTICE_CP PRACTICE_W1 PRACTICE_CP_HOST PRACTICE_W1_HOST PRACTICE_SSH_USER PRACTICE_SSH_KEY
  PRACTICE_SSH_OPTS PRACTICE_CILIUM_HOST PRACTICE_CILIUM CKS_PLATFORM CKS_CP_HOST CKS_W1_HOST CKS_SSH_USER CKS_SSH_KEY CKS_SSH_OPTS)

in_toolbox() { [[ "${LAB_TOOLBOX:-}" == 1 ]]; }

toolbox_compose_env() {
  # TOOLBOX_HASH labels the image with a checksum of toolbox/, so a git pull that changes
  # the toolbox leads to a rebuild on the next start.
  TOOLBOX_HASH="$(cat "$ROOT"/toolbox/* | cksum | awk '{print $1}')"
  export LAB_ROOT="$ROOT" HOST_UID="$(id -u)" HOST_GID="$(id -g)" TOOLBOX_HASH
  # compose.yaml mounts ~/.ssh read-only, so the practice VMs answer ssh from the toolbox too.
  # ssh-keygen makes this folder anyway; an empty one keeps Docker from creating it as root.
  [[ -d "$HOME/.ssh" ]] || { mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"; }
}

toolbox_start() {
  command -v docker >/dev/null 2>&1 || { echo "The toolbox needs Docker: install OrbStack, Docker Desktop or Docker Engine first." >&2; exit 1; }
  docker info >/dev/null 2>&1 || { echo "Docker does not answer. Start OrbStack or Docker first." >&2; exit 1; }
  docker compose version >/dev/null 2>&1 || { echo "The toolbox needs Docker Compose v2 (the 'docker compose' command)." >&2; exit 1; }
  toolbox_compose_env
  if [[ "$(docker image inspect -f '{{index .Config.Labels "lab.toolbox.hash"}}' "$TOOLBOX_IMAGE" 2>/dev/null)" != "$TOOLBOX_HASH" ]]; then
    echo "Building the toolbox image $TOOLBOX_IMAGE (about a minute the first time)" >&2
    "${COMPOSE[@]}" build lab >&2
  fi
  local out
  if ! out="$("${COMPOSE[@]}" up -d lab 2>&1)"; then
    echo "$out" >&2
    if grep -qiE "port is already allocated|address already in use|ports are not available" <<<"$out"; then
      echo >&2
      echo "Another program holds one of the UI ports 8081 3000 9090 9093 16686 20001 4466," >&2
      echo "for example a ./lab.sh ui that runs outside the toolbox. Stop it and try again." >&2
    fi
    exit 1
  fi
  # The container's start script creates your user and the kubeconfig first.
  local i
  for i in $(seq 1 60); do
    "${COMPOSE[@]}" exec -T lab test -f /run/lab-ready 2>/dev/null && return 0
    sleep 1
  done
  echo "The toolbox did not get ready in 60 seconds. Its log: docker logs k8s-lab-toolbox-lab-1" >&2
  exit 1
}

# toolbox_exec <command...>: run a command as your user in the toolbox, in the folder you are in.
toolbox_exec() {
  local wd="$ROOT" tty=() envs=() v
  [[ "$PWD" == "$ROOT" || "$PWD" == "$ROOT"/* ]] && wd="$PWD"
  [[ -t 0 && -t 1 ]] || tty=(-T)
  for v in "${PASS_ENV[@]}"; do
    [[ -n "${!v:-}" ]] && envs+=(-e "$v=${!v}")
  done
  "${COMPOSE[@]}" exec ${tty[@]+"${tty[@]}"} -u lab -w "$wd" ${envs[@]+"${envs[@]}"} lab "$@"
}

shell() {
  if in_toolbox; then
    echo "You are in the toolbox already."
    return 0
  fi
  toolbox_start
  # Clusters made outside the toolbox since it started get their kubectl context now.
  toolbox_exec /usr/local/lib/lab/kube-sync.sh
  cat <<'EOF'
You are in the lab toolbox: kubectl (alias k), helm, k3d, kind, istioctl, git and the rest.
The repo is the current folder. ./lab.sh help lists the commands; exit leaves the shell.
EOF
  toolbox_exec bash
}

toolbox_cmd() {
  in_toolbox && { echo "Run ./lab.sh toolbox on your machine, not inside the toolbox." >&2; exit 1; }
  toolbox_compose_env
  case "${1:-}" in
    build) "${COMPOSE[@]}" build lab ;;
    stop)  "${COMPOSE[@]}" rm -sf lab ;;
    *) echo "Usage: ./lab.sh toolbox build|stop" >&2; exit 1 ;;
  esac
}

# Run Ollama as a container next to the clusters, for machines that have no Ollama.
ollama_service() {
  in_toolbox && { echo "Run ./lab.sh ollama on your machine, not inside the toolbox." >&2; exit 1; }
  toolbox_compose_env
  "${COMPOSE[@]}" --profile ai up -d ollama
  echo "Ollama runs in the container k8s-lab-toolbox-ollama-1 on port ${LAB_OLLAMA_PORT:-11434}."
  echo "The first time it downloads the Ollama image (about 3.3 GB, 8.4 GB on disk) and pulls"
  echo "${LAB_OLLAMA_MODELS:-qwen2.5:3b nomic-embed-text} (about 2.2 GB)."
  echo "Follow the download: docker compose -p k8s-lab-toolbox logs -f ollama"
}

# Outside the toolbox, use it when this machine lacks the lab's tools.
want_toolbox() {
  in_toolbox && return 1
  case "${LAB_USE_TOOLBOX:-auto}" in
    always) return 0 ;;
    never) return 1 ;;
  esac
  local t
  for t in kubectl helm k3d; do
    command -v "$t" >/dev/null 2>&1 || return 0
  done
  return 1
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

# ./lab.sh practice up|reset|down|shell [node], and practice cilium up|reset|down|shell
practice() {
  local cluster="$ROOT/platform-engineering/practice/cluster" sub="${1:-}"
  [[ $# -gt 0 ]] && shift
  case "$sub" in
    up)    exec "$cluster/create.sh" "$@" ;;
    reset) exec "$cluster/reset.sh" "$@" ;;
    down)  exec "$cluster/destroy.sh" "$@" ;;
    cilium) exec "$cluster/cilium-vm.sh" "$@" ;;
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
    *) echo "Usage: ./lab.sh practice up|reset|down|shell [worker], or ./lab.sh practice cilium up|reset|down|shell" >&2; exit 1 ;;
  esac
}

command="${1:-help}"
[[ $# -gt 0 ]] && shift

# AI settings from lab.env go into the cluster after up and start (scripts/llm-settings.sh).
with_ai_settings() {
  local status=0
  "$@" || status=$?
  if [[ -f "$ROOT/lab.env" ]] && (( status == 0 )); then
    "$ROOT/scripts/llm-settings.sh" || status=$?
  fi
  exit "$status"
}

case "$command" in
  help|-h|--help|shell|toolbox|ollama) ;;
  # The timed tasks and exams reach the nodes with docker exec, orb or ssh, and the Lima VM
  # with limactl, which only the host has. So they run on the host, where bash 3.2 is enough.
  task|exam) [[ "${LAB_USE_TOOLBOX:-auto}" == always ]] && want_toolbox && { toolbox_start; toolbox_exec "$ROOT/lab.sh" "$command" "$@"; exit $?; } ;;
  # The practice cluster on OrbStack machines needs orb, which only the host has.
  practice) [[ "${PRACTICE_PLATFORM:-${CKS_PLATFORM:-kind}}" != orbstack ]] && want_toolbox && { toolbox_start; toolbox_exec "$ROOT/lab.sh" "$command" "$@"; exit $?; } ;;
  *)
    if want_toolbox; then
      toolbox_start
      exec_status=0
      toolbox_exec "$ROOT/lab.sh" "$command" "$@" || exec_status=$?
      exit "$exec_status"
    fi ;;
esac

if in_toolbox && [[ "$command" =~ ^(practice|task|exam)$ ]] && [[ "${PRACTICE_PLATFORM:-${CKS_PLATFORM:-kind}}" == orbstack ]]; then
  echo "With PRACTICE_PLATFORM=orbstack, run ./lab.sh $command in your Mac's own terminal, not in the toolbox:" >&2
  echo "it reaches the OrbStack machines with the orb command, which only your Mac has." >&2
  exit 1
fi

case "$command" in
  shell)  shell ;;
  toolbox) toolbox_cmd "$@" ;;
  ollama) ollama_service ;;
  ai)     exec "$ROOT/scripts/llm-settings.sh" "$@" ;;
  up)     with_ai_settings "$ROOT/scripts/provision.sh" "$@" ;;
  start)  with_ai_settings "$ROOT/scripts/start.sh" "$@" ;;
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
