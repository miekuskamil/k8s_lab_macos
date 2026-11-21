#!/usr/bin/env bash
# Prepares and checks the timed tasks of tracks 0, 1 and 4. Run it from the repo.
#   ./platform-engineering/task.sh setup 4.1.3    seeds the starting state for task 3 of module 4.1
#   ./platform-engineering/task.sh check 4.1.3    prints PASS or FAIL for each thing the task asks
#   ./platform-engineering/task.sh solve 4.1.3    applies the reference solution (the one in the <details> block)
#   ./platform-engineering/task.sh list           lists every task
# A task id is track.module.task. The task scripts live in practice/apps (modules 1.2 to 1.6)
# and practice/security (modules 4.1 to 4.7) under their own ids, such as 1.3. This script
# turns a task id into that id.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

# Module 4.7 collects the tasks that need a kernel of their own. Each line: task id, folder, id there.
KERNEL_TASKS="4.7.1 security 1.9
4.7.2 security 1.10
4.7.3 security 1.11
4.7.4 security 3.7
4.7.5 security 4.10
4.7.6 security 6.5
4.7.7 security 6.12"

# task id -> "folder id-there", or nothing when the id names no task
resolve() {
  local id="$1" line track mod n
  line="$(printf '%s\n' "$KERNEL_TASKS" | awk -v id="$id" '$1 "" == id "" {print $2, $3}')"
  if [ -n "$line" ]; then echo "$line"; return; fi
  IFS=. read -r track mod n <<<"$id"
  [ -n "${n:-}" ] || return 0
  case "$track.$mod" in
    1.2|1.3|1.4|1.5|1.6) echo "apps $((mod - 1)).$n" ;;
    4.1|4.2|4.3|4.4|4.5|4.6) local old="security $mod.$n"
      # a task that moved to module 4.7 has no id in its old module any more
      printf '%s\n' "$KERNEL_TASKS" | awk '{print $2, $3}' | grep -Fqx "$old" || echo "$old" ;;
  esac
}

# "folder id-there" -> task id
task_id() {
  local folder="$1" old="$2" line
  line="$(printf '%s\n' "$KERNEL_TASKS" | awk -v f="$folder" -v o="$old" '$2 "" == f "" && $3 "" == o "" {print $1}')"
  if [ -n "$line" ]; then echo "$line"; return; fi
  if [ "$folder" = apps ]; then echo "1.$(( ${old%%.*} + 1 )).${old#*.}"; else echo "4.$old"; fi
}

action="${1:-}"; id="${2:-}"
case "$action" in
  list)
    {
      "$HERE/0-docker/task.sh" list
      for folder in apps security; do
        "$HERE/practice/$folder/task.sh" list | while read -r old; do task_id "$folder" "$old"; done
      done
    } | sort -t. -k1,1n -k2,2n -k3,3n
    exit 0 ;;
  setup|check|solve) ;;
  *) sed -n '2,6p' "$0"; exit 1 ;;
esac
# The Docker track (0.x) keeps its tasks in 0-docker/ under their own ids.
case "$id" in 0.*) exec "$HERE/0-docker/task.sh" "$action" "$id" ;; esac
where="$(resolve "$id")"
if [ -z "$where" ]; then
  echo "no task $id (try: $0 list)"; exit 1
fi
TASK_LABEL="$id" exec "$HERE/practice/${where% *}/task.sh" "$action" "${where#* }"
