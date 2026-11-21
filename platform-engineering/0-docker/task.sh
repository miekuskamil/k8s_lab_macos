#!/usr/bin/env bash
# The Docker track's tasks. Run them through ./lab.sh task (or platform-engineering/task.sh),
# which passes ids like 0.2.1 here.
#   task.sh setup 0.2.1    prepares task 1 of module 0.2: files in platform-engineering/0-docker/work
#   task.sh check 0.2.1    prints PASS or FAIL for each thing the task asks
#   task.sh solve 0.2.1    runs the reference solution (the one in the module's <details> block)
#   task.sh list           lists every task
# The tasks need only Docker with the compose plugin, and bash 3.2 is enough.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/tasks/lib.sh"
for f in "$HERE"/tasks/0*.sh; do . "$f"; done

action="${1:-}"; id="${2:-}"
case "$action" in
  list)
    declare -F | awk '{print $3}' | grep '^check_0_' | sed 's/^check_//; s/_/./g' | sort -t. -k1,1n -k2,2n -k3,3n
    exit 0 ;;
  setup|check|solve) ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
fn="${action}_$(echo "$id" | tr . _)"
if ! declare -F "$fn" >/dev/null; then
  echo "no task $id (try: $0 list)"; exit 1
fi
echo "== $action task $id"
cd "$ROOT" || exit 1
"$fn"
if [ "$action" = check ]; then
  echo "== task $id: $PASSES passed, $FAILS failed"
  [ "$FAILS" -eq 0 ]
fi
