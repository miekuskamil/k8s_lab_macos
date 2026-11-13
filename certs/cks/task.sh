#!/usr/bin/env bash
# Prepares and checks the CKS track's tasks. Run it on your Mac, from the repo.
#   ./certs/cks/task.sh setup 1.3    seeds the starting state for task 3 of domain 01
#   ./certs/cks/task.sh check 1.3    prints PASS or FAIL for each thing the task asks
#   ./certs/cks/task.sh solve 1.3    applies the reference solution (the one in the <details> block)
#   ./certs/cks/task.sh list         lists every task
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/tasks/lib.sh"
for f in "$HERE"/tasks/0*.sh; do . "$f"; done

action="${1:-}"; id="${2:-}"
case "$action" in
  list)
    declare -F | awk '{print $3}' | grep '^check_' | sed 's/^check_//; s/_/./' | sort -t. -k1,1n -k2,2n
    exit 0 ;;
  setup|check|solve) ;;
  *) sed -n '2,6p' "$0"; exit 1 ;;
esac
fn="${action}_${id/./_}"
if ! declare -F "$fn" >/dev/null; then
  echo "no task $id (try: $0 list)"; exit 1
fi
echo "== $action task $id"
"$fn"
if [ "$action" = check ]; then
  echo "== task $id: $PASSES passed, $FAILS failed"
  [ "$FAILS" -eq 0 ]
fi
