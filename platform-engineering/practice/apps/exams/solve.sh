#!/usr/bin/env bash
# Applies the reference solution of every task of an application practice exam, the same commands as the
# <details> blocks in its file. It exists to test score.sh: after setup.sh, score.sh
# gives 0; after this script, it gives 100. Don't run it before you've tried the exam.
#   ./platform-engineering/practice-exam.sh solve 1          practice exam 1, every task
#   ./platform-engineering/practice-exam.sh solve 3 12  practice exam 3, one task
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOCK="${MOCK:-1}"
NS_LABEL=mock
. "$HERE/../tasks/lib.sh"
for f in "$HERE"/../tasks/0*.sh; do . "$f"; done
if [ "$MOCK" = 1 ]; then . "$HERE/tasks.sh"; else . "$HERE/tasks-$MOCK.sh"; fi

for n in ${*:-${MOCK_SOLVE_ORDER:-$MOCK_TASKS}}; do
  echo "== solving task $n: $(mock_title "$n")"
  "solve_m$n" 2>&1 | sed 's/^/   /'
done
