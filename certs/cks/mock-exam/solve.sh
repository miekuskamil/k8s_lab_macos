#!/usr/bin/env bash
# Applies the reference solution of every mock exam task, the same commands as the
# <details> blocks in mock-exam.md. It exists to test score.sh: after setup.sh, score.sh
# gives 0; after this script, it gives 100. Don't run it before you've tried the exam.
#   ./certs/cks/mock-exam/solve.sh        all tasks, task 1 (the upgrade) first
#   ./certs/cks/mock-exam/solve.sh 12     one task
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../tasks/lib.sh"
. "$HERE/tasks.sh"

for n in ${*:-$MOCK_TASKS}; do
  echo "== solving task $n: $(mock_title "$n")"
  "solve_m$n" 2>&1 | sed 's/^/   /'
done
