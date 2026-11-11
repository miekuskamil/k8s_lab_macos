#!/usr/bin/env bash
# Send requests through the ingress gateway and summarize status codes, backend versions and latency.
#
# Usage: ./scripts/traffic-test.sh [count] [concurrency] [path]
# Example: ./scripts/traffic-test.sh 200 50 "/api/slow?ms=300"
set -euo pipefail

COUNT="${1:-100}"
CONCURRENCY="${2:-1}"
REQUEST_PATH="${3:-/api/orders}"
BASE_URL="${BASE_URL:-http://localhost:8080}"

echo "Sending $COUNT requests to ${BASE_URL}${REQUEST_PATH} with concurrency $CONCURRENCY"

seq 1 "$COUNT" | xargs -P "$CONCURRENCY" -I{} \
  curl -s -o /dev/null --max-time 10 \
    -w '%{http_code}|%header{x-app-version}|%{time_total}\n' \
    "${BASE_URL}${REQUEST_PATH}" |
  awk -F'|' '
    {
      status[$1]++
      version[($2 == "" ? "none" : $2)]++
      total += $3
      n++
      if ($3 > max) max = $3
    }
    END {
      print "\nStatus codes"
      for (s in status) printf "  %s  %d  (%.0f%%)\n", s, status[s], 100 * status[s] / n
      print "\nBackend versions"
      for (v in version) printf "  %s  %d  (%.0f%%)\n", v, version[v], 100 * version[v] / n
      printf "\nAverage latency %.0f ms, slowest %.0f ms\n", 1000 * total / n, 1000 * max
    }'
