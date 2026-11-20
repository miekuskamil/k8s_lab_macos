#!/usr/bin/env bash
# Scores a mock exam from the cluster's state and shows the time since setup.sh. Run it on your Mac:
#   ./certs/cks/mock-exam/score.sh              mock exam 1, all tasks
#   MOCK=2 ./certs/cks/mock-exam/score.sh 4 9   mock exam 2, only tasks 4 and 9
# A task whose first check (its main change) passes gets its points split evenly over
# its checks, rounded down, like partial credit. Otherwise it gets 0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOCK="${MOCK:-1}"
. "$HERE/../tasks/lib.sh"
for f in "$HERE"/../tasks/0*.sh; do . "$f"; done
. "$HERE/tasks.sh"
[ "$MOCK" = 1 ] || . "$HERE/tasks-$MOCK.sh"

tasks="${*:-$MOCK_TASKS}"
total=0; max=0
summary=""
for n in $tasks; do
  PASSES=0; FAILS=0; FIRST_OK=""
  echo "== task $n: $(mock_title "$n")"
  "score_m$n"
  p="$(mock_points "$n")"
  # The first check is the task's main change. Without it, the task scores nothing,
  # so checks that only say "still works" never earn points for an untouched task.
  if [ "$FIRST_OK" = yes ]; then got=$(( p * PASSES / (PASSES + FAILS) )); else got=0; fi
  total=$((total + got)); max=$((max + p))
  printf '   %d of %d points\n' "$got" "$p"
  summary="$summary$(printf '%3s  %-40s %2d/%-2d' "$n" "$(mock_title "$n")" "$got" "$p")\n"
done
echo
printf 'task title                                      points\n'
printf "$summary"
echo "TOTAL: $total of $max points ($(( 100 * total / max ))%)."
if [ -f "$HERE/.started-$MOCK" ]; then
  min=$(( ( $(date +%s) - $(cat "$HERE/.started-$MOCK") ) / 60 ))
  if [ "$min" -gt 120 ]; then
    echo "TIME: $min minutes since setup. OVER the 2-hour limit by $((min - 120)) minutes: the real exam would have ended."
  else
    echo "TIME: $min minutes since setup, $((120 - min)) minutes left."
  fi
fi
