#!/usr/bin/env bash
# Seeds the starting state of all 17 tasks of a mock exam and starts its 2-hour clock.
# Run it on your Mac, on a fresh cluster:
#   ./certs/cks/cluster/reset.sh && ./certs/cks/mock-exam/setup.sh            mock exam 1
#   ./certs/cks/cluster/reset.sh && ./certs/cks/cluster/lima.sh reset && MOCK=2 ./certs/cks/mock-exam/setup.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MOCK="${MOCK:-1}"
. "$HERE/../tasks/lib.sh"
for f in "$HERE"/../tasks/0*.sh; do . "$f"; done      # mocks 2 and 3 reuse helpers from the domain tasks
. "$HERE/tasks.sh"
[ "$MOCK" = 1 ] || . "$HERE/tasks-$MOCK.sh"

v="$(k get node cks-cp -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)"
if [ "$v" != v1.37.1 ]; then
  echo "cks-cp runs '$v', and the mock exam needs a fresh cluster at v1.37.1."
  echo "Run ./certs/cks/cluster/reset.sh first."
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
echo "Ready. The clock runs from now: 2 hours. Open certs/cks/$( [ "$MOCK" = 1 ] && echo mock-exam.md || echo mock-exam-$MOCK.md )."
echo "Score yourself at any time with MOCK=$MOCK ./certs/cks/mock-exam/score.sh"
