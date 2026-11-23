# Module 6.8, the SRE game day. Functions for task.sh: setup_6_8_N, check_6_8_N, solve_6_8_N.

# ---- Task 1: triage a checkout outage -----------------------------------------------------
setup_6_8_1() {
  checkout_app || return 1
  chaos_mesh || return 1
  no_chaos || return 1
  "${K[@]}" apply -f "$M/6.1-checkout-slo-rules.yaml" -f "$M/6.1-budget-minutes.yaml" >/dev/null || return 1
  "${K[@]}" apply -f "$M/6.8-game-day.yaml" >/dev/null || return 1
  "${K[@]}" -n course-sre wait networkchaos/payments-maintenance-window --for=condition=AllInjected --timeout=60s >/dev/null || return 1
  "${K[@]}" -n course-sre create configmap task-6-8-1 --dry-run=client -o yaml \
    --from-literal=generations="$("${K[@]}" -n course-sre get deploy checkout payments -o jsonpath='{.items[*].metadata.generation}')" \
    | "${K[@]}" apply -f - >/dev/null || return 1
  incident() {
    [[ "$("${K[@]}" -n course-sre exec deploy/loadgen -- curl -s -o /dev/null -m 5 -w '%{http_code}' \
      http://checkout:8080/api/checkout 2>/dev/null)" == 504 ]]
  }
  poll 60 incident || { echo "The injected delay did not produce the expected 504." >&2; return 1; }
  page_firing() {
    [[ "$(prom 'ALERTS{alertname="CheckoutAvailabilityBudgetBurn",severity="page",alertstate="firing"}')" == 1 ]]
  }
  poll 180 page_firing || { echo "The availability page did not fire." >&2; return 1; }
  echo "Checkout returns 504s. No release changed, and the 30-minute game day has started."
  echo "Use the SLO, logs and cluster state to restore orders without changing either Deployment."
}
check_6_8_1() {
  local codes
  check "the maintenance-window fault is gone" test -z \
    "$("${K[@]}" -n course-sre get networkchaos payments-maintenance-window -o name 2>/dev/null)"
  codes="$("${K[@]}" -n course-sre exec deploy/loadgen -- sh -c 'for i in $(seq 1 20); do curl -s -o /dev/null -m 3 -w "%{http_code}\n" http://checkout:8080/api/checkout; done' 2>/dev/null | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
  check "20 orders in a row answer 200 (${codes:-none})" matches "$codes" '^ ?20 200 $'
  check "checkout and payments were not changed" test "$("${K[@]}" -n course-sre get deploy checkout payments -o jsonpath='{.items[*].metadata.generation}')" = \
    "$("${K[@]}" -n course-sre get configmap task-6-8-1 -o jsonpath='{.data.generations}' 2>/dev/null)"
}
solve_6_8_1() {
  shown <<'EOF'
kubectl -n course-sre get networkchaos
kubectl -n course-sre describe networkchaos payments-maintenance-window
kubectl -n course-sre delete networkchaos payments-maintenance-window
EOF
}
