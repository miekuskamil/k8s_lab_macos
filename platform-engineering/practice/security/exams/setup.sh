#!/usr/bin/env bash
# Seeds the starting state of all 17 tasks of a practice exam and starts its 2-hour clock.
# Run it on your Mac, on a fresh cluster:
#   ./platform-engineering/practice/cluster/reset.sh && ./platform-engineering/practice-exam.sh setup 4          practice exam 4
#   ./platform-engineering/practice/cluster/reset.sh && ./platform-engineering/practice/cluster/lima.sh reset && ./platform-engineering/practice-exam.sh setup 5
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOCK="${MOCK:-1}"
. "$HERE/../tasks/lib.sh"
for f in "$HERE"/../tasks/0*.sh; do . "$f"; done      # mocks 2 and 3 reuse helpers from the domain tasks
. "$HERE/tasks.sh"
[ "$MOCK" = 1 ] || . "$HERE/tasks-$MOCK.sh"

v="$(k get node $CP -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)"
if [ "$v" != v1.37.1 ]; then
  echo "$CP runs '$v', and the practice exam needs a fresh cluster at v1.37.1."
  echo "Run ./platform-engineering/practice/cluster/reset.sh first."
  exit 1
fi
if [ "${MOCK_NEEDS_LIMA:-no}" = yes ] && ! need_lima; then exit 1; fi

# Some tasks break the control plane on purpose, so their setup runs last.
for n in ${MOCK_SETUP_ORDER:-$MOCK_TASKS}; do
  echo "== setting up task $n: $(mock_title "$n")"
  "setup_m$n" 2>&1 | grep -vE '^(pod|service|deployment\.apps|serviceaccount|secret|role|rolebinding)(\.rbac\.authorization\.k8s\.io)?/.* created$' | sed 's/^/   /'
done
if [ -z "${MOCK_SETUP_ORDER:-}" ]; then
  echo "== waiting for the task pods"
  k wait pod --all -A --for=condition=Ready --timeout=300s >/dev/null 2>&1 || true
  k get pods -A --no-headers | awk '$4 != "Running" {print "   not running yet: " $1 "/" $2 " " $4}'
fi
date +%s > "$HERE/.started-$MOCK"
echo
echo "Ready. The clock runs from now: 2 hours. Open platform-engineering/3-advanced/practice-exam-$((MOCK + 3)).md."
echo "Score yourself at any time with ./platform-engineering/practice-exam.sh score $((MOCK + 3))"
