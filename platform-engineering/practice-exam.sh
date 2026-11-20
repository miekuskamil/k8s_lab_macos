#!/usr/bin/env bash
# Runs the six timed practice exams. Run it on your Mac, from the repo.
#   ./platform-engineering/practice-exam.sh setup 4        seeds every task of exam 4 and starts its 2-hour clock
#   ./platform-engineering/practice-exam.sh score 4        scores exam 4 and shows the minutes since setup
#   ./platform-engineering/practice-exam.sh score 4 3 9    scores only tasks 3 and 9
#   ./platform-engineering/practice-exam.sh solve 4 [N]    applies the reference solution, of every task or of task N
# Exams 1 to 3 cover modules 33 to 37 and live in practice/apps/exams; exams 4 to 6 cover
# modules 38 to 43 and live in practice/security/exams, where each folder numbers its own as 1 to 3.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

action="${1:-}"; exam="${2:-}"
case "$action" in setup|score|solve) ;; *) sed -n '2,6p' "$0"; exit 1 ;; esac
case "$exam" in
  1|2|3) folder=apps; mock="$exam" ;;
  4|5|6) folder=security; mock=$((exam - 3)) ;;
  *) echo "name an exam from 1 to 6"; exit 1 ;;
esac
shift 2
MOCK="$mock" exec "$HERE/practice/$folder/exams/$action.sh" "$@"
