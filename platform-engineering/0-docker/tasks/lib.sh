# Helpers for the Docker track's tasks, sourced by ../task.sh. Every command talks to the same
# Docker engine as the toolbox, so a task runs the same from your terminal and from the toolbox.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DT="$ROOT/platform-engineering/0-docker"
W="$DT/work"
# Published ports: the toolbox reaches the Docker host as host.docker.internal, your own
# terminal as localhost.
PUB=localhost; [ "${LAB_TOOLBOX:-}" = 1 ] && PUB=host.docker.internal

PASSES=0
FAILS=0
# check "what" <command...>: the command's exit code decides PASS or FAIL.
check() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$what"; PASSES=$((PASSES + 1))
  else
    printf '  FAIL  %s\n' "$what"; FAILS=$((FAILS + 1))
  fi
}
# check_sh "what" 'shell code': the same, for a check written as shell code.
check_sh() { check "$1" bash -c "$2"; }

# A fresh task folder: taskdir 0.2.1 prints its path, relative to the repo.
taskdir() {
  rm -rf "$W/task-$1"; mkdir -p "$W/task-$1"
  echo "platform-engineering/0-docker/work/task-$1"
}
# Remove containers, networks or volumes a task uses, by name: gone c course-x; gone n course-net
gone() {
  local kind="$1"; shift
  case "$kind" in
    c) docker rm -f "$@" >/dev/null 2>&1 ;;
    n) docker network rm "$@" >/dev/null 2>&1 ;;
    v) docker volume rm -f "$@" >/dev/null 2>&1 ;;
    i) docker image rm -f "$@" >/dev/null 2>&1 ;;
    p) docker compose -p "$1" down -v --remove-orphans >/dev/null 2>&1 ;;
  esac
  true
}
# The value of a Go template for a container, or nothing: field course-x '{{.State.Status}}'
field() { docker inspect -f "$2" "$1" 2>/dev/null; }
# Poll a URL on a published port until it answers: http_code 8890 /path
http_code() { curl -s -m 5 --retry 8 --retry-all-errors --retry-delay 1 -o /dev/null -w '%{http_code}' "http://$PUB:$1${2:-/}" 2>/dev/null; }
http_body() { curl -s -m 5 --retry 8 --retry-all-errors --retry-delay 1 "http://$PUB:$1${2:-/}" 2>/dev/null; }

# Run the reference solution from stdin, one command per line, from the repo folder, and print
# each command after a prompt the way the module's solution shows it. Lines starting with #
# are skipped.
shown() {
  local l
  cd "$ROOT" || return 1
  while IFS= read -r l; do
    case "$l" in ""|"#"*) continue ;; esac
    echo "\$ $l"
    eval "$l" </dev/null 2>&1
  done
}
