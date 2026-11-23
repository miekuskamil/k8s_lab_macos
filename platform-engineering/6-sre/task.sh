#!/usr/bin/env bash
# The reliability track's tasks. Run them through ./lab.sh task (or platform-engineering/task.sh),
# which passes ids like 6.1.1 here.
#   task.sh setup 6.1.1    prepares task 1 of module 6.1 on the lab
#   task.sh check 6.1.1    prints PASS or FAIL for each thing the task asks
#   task.sh solve 6.1.1    applies the reference solution (the one in the module's <details> block)
#   task.sh list           lists every task
# The tasks need the lab (k3d) and kubectl, and bash 3.2 is enough.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/tasks/lib.sh"
for f in "$HERE"/tasks/0*.sh; do . "$f"; done

action="${1:-}"; id="${2:-}"
case "$action" in
  list)
    declare -F | awk '{print $3}' | grep '^check_6_' | sed 's/^check_//; s/_/./g' | sort -t. -k1,1n -k2,2n -k3,3n
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
