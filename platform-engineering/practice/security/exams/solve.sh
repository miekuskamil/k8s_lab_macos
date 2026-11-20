#!/usr/bin/env bash
# Applies the reference solution of every task of a mock exam, the same commands as the
# <details> blocks in its file. It exists to test score.sh: after setup.sh, score.sh
# gives 0; after this script, it gives 100. Don't run it before you've tried the exam.
#   ./certs/cks/mock-exam/solve.sh            mock exam 1, every task in its solve order
#   MOCK=3 ./certs/cks/mock-exam/solve.sh 12  mock exam 3, one task
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOCK="${MOCK:-1}"
. "$HERE/../tasks/lib.sh"
for f in "$HERE"/../tasks/0*.sh; do . "$f"; done
. "$HERE/tasks.sh"
[ "$MOCK" = 1 ] || . "$HERE/tasks-$MOCK.sh"

for n in ${*:-${MOCK_SOLVE_ORDER:-$MOCK_TASKS}}; do
  echo "== solving task $n: $(mock_title "$n")"
  "solve_m$n" 2>&1 | sed 's/^/   /'
done
