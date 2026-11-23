# Module 6.1, SLIs, SLOs and error budgets. Functions for task.sh: setup_6_1_N, check_6_1_N, solve_6_1_N.

PAY_SEL='namespace="course-sre", app="payments"'

# ---- Task 1: a hand-written availability SLO for payments ---------------------------------
setup_6_1_1() {
  checkout_app
  "${K[@]}" -n course-sre delete prometheusrule payments-slo --ignore-not-found >/dev/null
  # Prometheus drops a deleted rule only when the operator rewrites its rule files, up to two minutes later.
  dropped() { ! prom_rules | grep -qE $'\t(payments:sli_error:ratio_rate1h|PaymentsAvailabilityBurn)\t'; }
  poll 180 dropped
  echo "checkout and payments run in course-sre, and Prometheus scrapes both."
  echo "No PrometheusRule named payments-slo exists. Write it (task 6.1.1 in the module)."
}
check_6_1_1() {
  local rules want got
  check "PrometheusRule course-sre/payments-slo exists" "${K[@]}" -n course-sre get prometheusrule payments-slo
  # A new rule reaches Prometheus through a Secret, which takes up to two minutes.
  loaded() { prom_rules | grep -q 'payments:sli_error:ratio_rate1h'; }
  poll 150 loaded
  rules="$(prom_rules)"
  alert_line() { printf '%s\n' "$rules" | awk -F'\t' '$2=="PaymentsAvailabilityBurn" && $3=="ok"'; }
  check "Prometheus loaded payments:sli_error:ratio_rate5m and ratio_rate1h" \
    test "$(printf '%s\n' "$rules" | grep -cE $'\tpayments:sli_error:ratio_rate(5m|1h)\tok\t')" = 2
  want="$(prom "(sum(rate(http_request_duration_seconds_count{$PAY_SEL, status=~\"5..\"}[5m])) or vector(0)) / sum(rate(http_request_duration_seconds_count{$PAY_SEL}[5m]))")"
  got="$(prom 'payments:sli_error:ratio_rate5m')"
  check "the 5m ratio has a value now, even with no 5xx ($got)" matches "$got" '^[0-9.e-]+$'
  check "it matches the 5xx share of payments' requests over 5m" awk -v a="${got:-x}" -v b="${want:-y}" 'BEGIN { d = a - b; exit !(a != "x" && b != "y" && d < 0.002 && d > -0.002) }'
  check "Prometheus loaded an alert named PaymentsAvailabilityBurn" test -n "$(alert_line)"
  check "the alert compares both windows against 14.4 x 0.5% (0.072)" \
    sh -c 'echo "$1" | grep "ratio_rate5m" | grep "ratio_rate1h" | grep -qE "0\.072|14\.4 *\* *0\.005"' sh "$(alert_line)"
  check "the alert carries severity=page" matches "$("${K[@]}" -n course-sre get prometheusrule payments-slo -o yaml 2>/dev/null)" 'severity: "?page'
}
solve_6_1_1() {
  shown <<'EOF'
cat platform-engineering/6-sre/tasks/6.1.1-payments-slo.yaml
kubectl apply -f platform-engineering/6-sre/tasks/6.1.1-payments-slo.yaml
EOF
}

# ---- Task 2: a latency SLO for payments, generated with Sloth -----------------------------
setup_6_1_2() {
  checkout_app
  "${K[@]}" -n course-sre delete prometheusrule payments --ignore-not-found >/dev/null
  dropped() { ! prom_rules | grep -q 'sloth-slo-.*-payments-latency'; }
  poll 180 dropped
  echo "No PrometheusRule named payments exists. Write a Sloth spec, generate it and apply it (task 6.1.2)."
}
check_6_1_2() {
  local rules
  check "PrometheusRule course-sre/payments exists and Sloth generated it" \
    matches "$("${K[@]}" -n course-sre get prometheusrule payments -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}' 2>/dev/null)" '^sloth$'
  objective() { prom 'slo:objective:ratio{sloth_service="payments", sloth_slo="latency"}'; }
  # Sloth's groups load one by one, so wait until the ratio and both alerts are there too.
  loaded() { [ -n "$(objective)" ] && [ -n "$(prom 'slo:sli_error:ratio_rate5m{sloth_service="payments", sloth_slo="latency"}')" ] \
    && [ "$(prom_rules | grep -F 'sloth-slo-alerts-payments-latency' | grep -c $'\tok\t')" = 2 ]; }
  poll 150 loaded
  check "the SLO is payments / latency with objective 0.99" \
    awk -v a="$(objective)" 'BEGIN { exit !(a != "" && a > 0.9899 && a < 0.9901) }'
  rules="$(prom_rules)"
  check "its SLI counts requests slower than 100 ms (the le=\"0.1\" bucket)" \
    sh -c 'echo "$1" | grep -F "sloth-slo-sli-recordings-payments-latency" | grep -q "le=\"0.1\""' sh "$rules"
  check "the 5m error ratio has a value" matches "$(prom 'slo:sli_error:ratio_rate5m{sloth_service="payments", sloth_slo="latency"}')" '^[0-9.e-]+$'
  check "a page alert and a ticket alert exist for it" \
    test "$(printf '%s\n' "$rules" | grep -F 'sloth-slo-alerts-payments-latency' | grep -c $'\tok\t')" = 2
}
solve_6_1_2() {
  shown <<'EOF'
cat platform-engineering/6-sre/tasks/6.1.2-payments-sloth.yaml
docker run --rm -v "$PWD:$PWD" -w "$PWD" ghcr.io/slok/sloth:v0.16.0 generate -i platform-engineering/6-sre/tasks/6.1.2-payments-sloth.yaml 2>/dev/null | kubectl apply -f -
EOF
}

# ---- Task 3: silence the page for a planned migration -------------------------------------
am() { "${K[@]}" -n observability exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- "$@" 2>/dev/null; }
setup_6_1_3() {
  checkout_app
  "${K[@]}" apply -f "$M/6.1-checkout-slo-rules.yaml" >/dev/null
  # Expire any silence an earlier run left behind.
  local id
  for id in $(am amtool --alertmanager.url=http://localhost:9093 silence query -q alertname=CheckoutAvailabilityBudgetBurn); do
    am amtool --alertmanager.url=http://localhost:9093 silence expire "$id" >/dev/null
  done
  echo "The checkout SLO rules are loaded. Alertmanager holds no silence for CheckoutAvailabilityBudgetBurn."
}
check_6_1_3() {
  local s
  s="$(am wget -q -O - http://localhost:9093/api/v2/silences | python3 -c 'import json,sys,datetime
for x in json.load(sys.stdin):
    if x["status"]["state"] != "active": continue
    m = {y["name"]: (y["value"], y.get("isEqual", True), y.get("isRegex", False)) for y in x["matchers"]}
    if m.get("alertname", ("",))[0] != "CheckoutAvailabilityBudgetBurn": continue
    p = lambda t: datetime.datetime.fromisoformat(t.replace("Z", "+00:00"))
    hours = (p(x["endsAt"]) - p(x["startsAt"])).total_seconds() / 3600
    print(m.get("severity", ("",))[0], round(hours, 2), x["comment"])' 2>/dev/null | head -1)"
  check "an active silence matches alertname=CheckoutAvailabilityBudgetBurn" test -n "$s"
  check "it matches only severity=page, so tickets still arrive" matches "$s" '^page '
  check "it lasts 2 hours (got: ${s:-none})" awk -v h="$(echo "$s" | awk '{print $2}')" 'BEGIN { exit !(h >= 1.9 && h <= 2.1) }'
  check "its comment names the migration" matches "$s" '[Mm]igration'
}
solve_6_1_3() {
  shown <<'EOF'
kubectl -n observability exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- amtool --alertmanager.url=http://localhost:9093 silence add alertname=CheckoutAvailabilityBudgetBurn severity=page --duration=2h --author=you --comment="payments database migration"
kubectl -n observability exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- amtool --alertmanager.url=http://localhost:9093 silence query
EOF
}
