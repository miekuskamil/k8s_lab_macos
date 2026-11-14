#!/usr/bin/env bash
# Seeds the starting state of all 17 mock exam tasks. Run it on your Mac, on a fresh cluster:
#   ./certs/cks/cluster/reset.sh && ./certs/cks/mock-exam/setup.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../tasks/lib.sh"
. "$HERE/tasks.sh"

v="$(k get node cks-cp -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)"
if [ "$v" != v1.37.1 ]; then
  echo "cks-cp runs '$v', and the mock exam needs a fresh cluster at v1.37.1."
  echo "Run ./certs/cks/cluster/reset.sh first."
  exit 1
fi
for n in $MOCK_TASKS; do
  echo "== setting up task $n: $(mock_title "$n")"
  "setup_m$n" 2>&1 | grep -vE '^(pod|service|deployment\.apps)/.* created$' | sed 's/^/   /'
done
echo "== waiting for the task pods"
k wait pod --all -A --for=condition=Ready --timeout=300s >/dev/null 2>&1 || true
k get pods -A --no-headers | awk '$4 != "Running" {print "   not running yet: " $1 "/" $2 " " $4}'
echo
echo "Ready. Start a 2-hour timer and open certs/cks/mock-exam.md."
echo "Score yourself at any time with ./certs/cks/mock-exam/score.sh"
