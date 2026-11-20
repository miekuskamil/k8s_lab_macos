#!/usr/bin/env bash
# Seeds the starting state of every task of a CKAD mock exam and starts its 2-hour clock.
# Run it on your Mac, after a CKAD reset:
#   ./certs/ckad/cluster/reset.sh && ./certs/ckad/mock-exam/setup.sh            mock exam 1
#   ./certs/ckad/cluster/reset.sh && MOCK=2 ./certs/ckad/mock-exam/setup.sh     mock exam 2
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOCK="${MOCK:-1}"
NS_LABEL=mock
. "$HERE/../tasks/lib.sh"
for f in "$HERE"/../tasks/0*.sh; do . "$f"; done      # the mocks reuse helpers from the domain tasks
if [ "$MOCK" = 1 ]; then . "$HERE/tasks.sh"; else . "$HERE/tasks-$MOCK.sh"; fi

v="$(k get node cks-cp -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)"
if [ "$v" != v1.37.1 ]; then
  echo "cks-cp runs '$v', and the mock exam needs the practice cluster at v1.37.1."
  echo "Run ./certs/cks/cluster/reset.sh and ./certs/ckad/cluster/extras.sh first."
  exit 1
fi
need_extras || exit 1
if [ -n "$(k get ns -l ckad -o name 2>/dev/null)" ]; then
  echo "Namespaces from earlier CKAD tasks or mocks are still there. Run ./certs/ckad/cluster/reset.sh first."
  exit 1
fi
need_metrics

for n in ${MOCK_SETUP_ORDER:-$MOCK_TASKS}; do
  echo "== setting up task $n: $(mock_title "$n")"
  "setup_m$n" 2>&1 | grep -vE '^[a-z.]+/[^ ]+ (created|labeled|configured)$' | sed 's/^/   /'
done
date +%s > "$HERE/.started-$MOCK"
echo
echo "Ready. The clock runs from now: 2 hours. Open certs/ckad/$( [ "$MOCK" = 1 ] && echo mock-exam.md || echo mock-exam-$MOCK.md )."
echo "Score yourself at any time with MOCK=$MOCK ./certs/ckad/mock-exam/score.sh"
