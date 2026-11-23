# Module 6.7, centralized logs. Functions for task.sh: setup_6_7_N, check_6_7_N, solve_6_7_N.

# ---- Task 1: repair Fluent Bit's Loki output -----------------------------------------------
fluentbit_task_logs() {
  local now
  now="$(date +%s)"
  "${K[@]}" get --raw "/api/v1/namespaces/observability/services/loki:3100/proxy/loki/api/v1/query_range?query=%7Bcollector%3D%22fluent-bit%22%2Cnamespace%3D%22course-sre%22%2Capp%3D%22checkout%22%7D%20%7C%3D%20%22internal%20error%22&start=$((now - 600))000000000&end=${now}000000000&limit=100" 2>/dev/null \
    | python3 -c 'import json,sys; print(sum(len(s["values"]) for s in json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo 0
}
setup_6_7_1() {
  checkout_app || return 1
  "${K[@]}" -n course-sre set env deploy/checkout ERROR_PERCENT=100 >/dev/null || return 1
  "${K[@]}" -n course-sre rollout status deploy/checkout --timeout=120s >/dev/null || return 1
  local broken="${TMPDIR:-/tmp}/fluent-bit-broken-values.yaml"
  sed 's/Host loki\.observability\.svc\.cluster\.local/Host loki-missing.observability.svc.cluster.local/' \
    "$M/6.7-fluent-bit-values.yaml" > "$broken" || { rm -f "$broken"; return 1; }
  "${H[@]}" upgrade --install fluent-bit fluent-bit --repo https://fluent.github.io/helm-charts --version 0.58.3 -n course-logging \
    --create-namespace -f "$broken" --wait --timeout 3m >/dev/null || { rm -f "$broken"; return 1; }
  rm -f "$broken" || return 1
  echo "Checkout logs internal errors, but Fluent Bit sends them to an invalid Loki host."
  echo "Repair the output and find at least five checkout error lines in Loki (task 6.7.1)."
}
check_6_7_1() {
  local n
  has_logs() {
    n="$(fluentbit_task_logs)"
    [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 5 ))
  }
  poll 90 has_logs
  n="$(fluentbit_task_logs)"
  check "Loki has at least five checkout error lines from Fluent Bit (got ${n:-0})" at_least "$n" 5
}
solve_6_7_1() {
  shown <<'EOF'
helm upgrade --install fluent-bit fluent-bit --repo https://fluent.github.io/helm-charts --version 0.58.3 -n course-logging --create-namespace -f platform-engineering/manifests/6.7-fluent-bit-values.yaml --wait --timeout 3m
kubectl -n course-sre set env deployment/checkout ERROR_PERCENT=100
EOF
}
