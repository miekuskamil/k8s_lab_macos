#!/usr/bin/env bash
# Prepares and checks the timed tasks of modules 33 to 44. Run it on your Mac, from the repo.
#   ./platform-engineering/task.sh setup 38.3    seeds the starting state for task 3 of module 38
#   ./platform-engineering/task.sh check 38.3    prints PASS or FAIL for each thing the task asks
#   ./platform-engineering/task.sh solve 38.3    applies the reference solution (the one in the <details> block)
#   ./platform-engineering/task.sh list          lists every task
# The task scripts live in practice/apps (modules 33 to 37) and practice/security (modules 38
# to 44) under their original ids, such as 1.3. This script turns a module id into that id.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# Module 44 collects the tasks that need a kernel of their own. Each line: module id, folder, id there.
KERNEL_TASKS="44.1 security 1.9
44.2 security 1.10
44.3 security 1.11
44.4 security 3.7
44.5 security 4.10
44.6 security 6.5
44.7 security 6.12"

# module id -> "folder id-there", or nothing when the id names no task
resolve() {
  local id="$1" mod="${1%%.*}" n="${1#*.}" line
  line="$(printf '%s\n' "$KERNEL_TASKS" | awk -v id="$id" '$1 "" == id "" {print $2, $3}')"
  if [ -n "$line" ]; then echo "$line"; return; fi
  case "$mod" in
    33|34|35|36|37) echo "apps $((mod - 32)).$n" ;;
    38|39|40|41|42|43) local old="security $((mod - 37)).$n"
      # a task that moved to module 44 has no id in its old module any more
      printf '%s\n' "$KERNEL_TASKS" | awk '{print $2, $3}' | grep -Fqx "$old" || echo "$old" ;;
  esac
}

# "folder id-there" -> module id
module_id() {
  local folder="$1" old="$2" line
  line="$(printf '%s\n' "$KERNEL_TASKS" | awk -v f="$folder" -v o="$old" '$2 "" == f "" && $3 "" == o "" {print $1}')"
  if [ -n "$line" ]; then echo "$line"; return; fi
  if [ "$folder" = apps ]; then echo "$(( ${old%%.*} + 32 )).${old#*.}"; else echo "$(( ${old%%.*} + 37 )).${old#*.}"; fi
}

action="${1:-}"; id="${2:-}"
case "$action" in
  list)
    for folder in apps security; do
      "$HERE/practice/$folder/task.sh" list | while read -r old; do module_id "$folder" "$old"; done
    done | sort -t. -k1,1n -k2,2n
    exit 0 ;;
  setup|check|solve) ;;
  *) sed -n '2,6p' "$0"; exit 1 ;;
esac
where="$(resolve "$id")"
if [ -z "$where" ]; then
  echo "no task $id (try: $0 list)"; exit 1
fi
TASK_LABEL="$id" exec "$HERE/practice/${where% *}/task.sh" "$action" "${where#* }"
