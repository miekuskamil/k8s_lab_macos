#!/usr/bin/env bash
# Send steady traffic through the gateway so Grafana and Jaeger have something to show.
# A single burst is over before Prometheus has scraped twice, and rate() then shows nothing.
#
#   ./course/load.sh [seconds] [path] [requests-per-second]
#   ./course/load.sh 120 /api/orders 5
set -euo pipefail
DURATION="${1:-120}"
REQUEST_PATH="${2:-/api/orders}"
RPS="${3:-5}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT

echo "Sending about ${RPS} requests per second to ${BASE_URL}${REQUEST_PATH} for ${DURATION}s. Press Ctrl-C to stop."
end=$((SECONDS + DURATION))
while (( SECONDS < end )); do
  for _ in $(seq 1 "$RPS"); do
    curl -s -o /dev/null --max-time 10 -w '%{http_code} %header{x-app-version}\n' "${BASE_URL}${REQUEST_PATH}" >> "$OUT" &
  done
  sleep 1
done
wait

echo
echo "Status codes:"
awk '{c[$1]++} END {for (k in c) printf "  %s  %d\n", k, c[k]}' "$OUT" | sort
echo "Backend versions:"
awk '{v[($2 == "" ? "none" : $2)]++} END {for (k in v) printf "  %s  %d\n", k, v[k]}' "$OUT" | sort
