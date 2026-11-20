#!/usr/bin/env bash
# Seeds the starting state of every task of an application practice exam and starts its 2-hour clock.
# Run it on your Mac, after a application reset:
#   ./platform-engineering/practice/app-extras/reset.sh && ./platform-engineering/practice-exam.sh setup 1          practice exam 1
#   ./platform-engineering/practice/app-extras/reset.sh && ./platform-engineering/practice-exam.sh setup 2     practice exam 2
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOCK="${MOCK:-1}"
NS_LABEL=mock
. "$HERE/../tasks/lib.sh"
for f in "$HERE"/../tasks/0*.sh; do . "$f"; done      # the mocks reuse helpers from the domain tasks
if [ "$MOCK" = 1 ]; then . "$HERE/tasks.sh"; else . "$HERE/tasks-$MOCK.sh"; fi

v="$(k get node cks-cp -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)"
if [ "$v" != v1.37.1 ]; then
  echo "cks-cp runs '$v', and the practice exam needs the practice cluster at v1.37.1."
  echo "Run ./platform-engineering/practice/cluster/reset.sh and ./platform-engineering/practice/app-extras/extras.sh first."
  exit 1
fi
need_extras || exit 1
if [ -n "$(k get ns -l ckad -o name 2>/dev/null)" ]; then
  echo "Namespaces from earlier application tasks or practice exams are still there. Run ./platform-engineering/practice/app-extras/reset.sh first."
  exit 1
fi
need_metrics

for n in ${MOCK_SETUP_ORDER:-$MOCK_TASKS}; do
  echo "== setting up task $n: $(mock_title "$n")"
  "setup_m$n" 2>&1 | grep -vE '^[a-z.]+/[^ ]+ (created|labeled|configured)$' | sed 's/^/   /'
done
date +%s > "$HERE/.started-$MOCK"
echo
echo "Ready. The clock runs from now: 2 hours. Open platform-engineering/1-foundations/practice-exam-$MOCK.md."
echo "Score yourself at any time with ./platform-engineering/practice-exam.sh score $MOCK"
