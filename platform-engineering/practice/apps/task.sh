#!/usr/bin/env bash
# Prepares and checks the application modules' timed tasks under their original ids.
# Run ./platform-engineering/task.sh instead: it takes the task ids (4.1.3) the chapters show,
# finds the task here, and passes its id as TASK_LABEL so the output shows the module id.
#   task.sh setup|check|solve 1.3    task 3 of this folder's tasks/01.sh
#   task.sh list                     every task, by its id here
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/tasks/lib.sh"
for f in "$HERE"/tasks/0*.sh; do . "$f"; done

action="${1:-}"; id="${2:-}"
case "$action" in
  list)
    declare -F | awk '{print $3}' | grep '^check_[0-9]' | sed 's/^check_//; s/_/./' | sort -t. -k1,1n -k2,2n
    exit 0 ;;
  setup|check|solve) ;;
  *) sed -n '2,7p' "$0"; exit 1 ;;
esac
fn="${action}_${id/./_}"
if ! declare -F "$fn" >/dev/null; then
  echo "no task $id (try: $0 list)"; exit 1
fi
echo "== $action task ${TASK_LABEL:-$id}"
"$fn"
if [ "$action" = check ]; then
  echo "== task ${TASK_LABEL:-$id}: $PASSES passed, $FAILS failed"
  [ "$FAILS" -eq 0 ]
fi
