# Module 6.2, Grafana in depth. Functions for task.sh: setup_6_2_N, check_6_2_N, solve_6_2_N.

# ---- Task 1: fix a broken dashboard -------------------------------------------------------
setup_6_2_1() {
  checkout_app
  "${K[@]}" apply -f "$ROOT/platform-engineering/6-sre/tasks/6.2.1-calls-dashboard.yaml" >/dev/null
  echo "The ConfigMap course-sre/dashboard-checkout-calls holds the dashboard 'Checkout / calls to payments'."
  echo "Its Result dropdown is empty and one panel shows No data. Fix the ConfigMap (task 6.2.1)."
}
check_6_2_1() {
  local d var vals
  d="$(grafana localhost:3000/api/dashboards/uid/checkout-calls)"
  check "Grafana has the dashboard checkout-calls, provisioned from its ConfigMap" \
    matches "$(echo "$d" | python3 -c 'import json,sys; print(json.load(sys.stdin)["meta"]["provisioned"])' 2>/dev/null)" '^True$'
  var="$(echo "$d" | python3 -c 'import json,sys; print(json.load(sys.stdin)["dashboard"]["templating"]["list"][0]["definition"])' 2>/dev/null)"
  # label_values(<selector>, <label>): ask Prometheus for the label's values on that selector
  vals="$(python3 - "$var" <<'EOF' | while read -r sel label; do "${K[@]}" get --raw "/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/label/$label/values?match%5B%5D=$sel" 2>/dev/null; done
import re, sys, urllib.parse
m = re.match(r"label_values\((.*),\s*(\w+)\)$", sys.argv[1].strip())
print(urllib.parse.quote(m.group(1)), m.group(2)) if m else None
EOF
)"
  check "the Result variable lists values, ok among them" matches "$vals" '"ok"'
  check "every panel returns data with Result set to All" test "$(dash_empty checkout-calls 'result=.*')" = 0
}
solve_6_2_1() {
  shown <<'EOF'
grep -n 'call_total\|chekout' platform-engineering/6-sre/tasks/6.2.1-calls-dashboard.yaml
sed -e 's/checkout_payments_call_total/checkout_payments_calls_total/g' -e 's/chekout/checkout/' platform-engineering/6-sre/tasks/6.2.1-calls-dashboard.yaml | kubectl apply -f -
EOF
  # The sidecar needs a few seconds to hand the new file to Grafana.
  sleep 15
}

# ---- Task 2: a Grafana alert rule on checkout's p95 ---------------------------------------
setup_6_2_2() {
  checkout_app
  "${K[@]}" apply -f "$M/6.2-gitea.yaml" >/dev/null
  "${K[@]}" -n course-sre rollout status deploy/alert-receiver --timeout=120s >/dev/null 2>&1
  grafana_in -H 'Content-Type: application/json' -X POST localhost:3000/api/v1/provisioning/contact-points -d @- < "$M/6.2-contact-point.json" >/dev/null
  grafana -H 'Content-Type: application/json' -X POST localhost:3000/api/folders -d '{"uid":"sre","title":"SRE"}' >/dev/null
  grafana -X DELETE localhost:3000/api/v1/provisioning/alert-rules/checkout-p95 >/dev/null
  echo "Grafana has the folder SRE (uid sre) and the contact point sre-webhook. No rule checkout-p95 exists."
}
check_6_2_2() {
  local r st
  r="$(grafana localhost:3000/api/v1/provisioning/alert-rules/checkout-p95 | python3 -c 'import json,sys
r = json.load(sys.stdin)
a = [d for d in r["data"] if d["datasourceUid"] != "__expr__"]
c = [d for d in r["data"] if d["model"].get("type") in ("threshold", "classic_conditions")]
ev = c[0]["model"]["conditions"][0]["evaluator"] if c else {}
print(r["folderUID"], a[0]["datasourceUid"] if a else "", r["for"], (r.get("notification_settings") or {}).get("receiver", ""), ev.get("type", ""), (ev.get("params") or [""])[0], sep="|")
print(a[0]["model"].get("expr", "") if a else "")' 2>/dev/null)"
  check "a Grafana rule with uid checkout-p95 exists in folder sre" matches "$r" '^sre\|'
  check "it queries the Prometheus data source" matches "$r" '^sre\|prometheus\|'
  check "it computes checkout's 95th percentile from the histogram" sh -c 'echo "$1" | tail -1 | grep -q "histogram_quantile(0.95" && echo "$1" | tail -1 | grep -q "checkout" && echo "$1" | tail -1 | grep -q "_bucket"' sh "$r"
  check "it fires above 0.25 s" matches "$(echo "$r" | head -1)" '\|gt\|0\.25$'
  check "it must hold for 1 minute" matches "$(echo "$r" | head -1)" '\|1m\|'
  check "it notifies the contact point sre-webhook" matches "$(echo "$r" | head -1)" '\|sre-webhook\|'
  st() { grafana localhost:3000/api/prometheus/grafana/api/v1/rules | python3 -c 'import json,sys; r=[r for g in json.load(sys.stdin)["data"]["groups"] for r in g["rules"] if r["name"] == sys.argv[1]]; print(r[0]["health"] if r else "none")' "$1" 2>/dev/null; }
  title="$(grafana localhost:3000/api/v1/provisioning/alert-rules/checkout-p95 | python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])' 2>/dev/null)"
  healthy() { [ "$(st "$title")" = ok ]; }
  poll 90 healthy
  check "Grafana evaluates it without errors" healthy
}
solve_6_2_2() {
  shown <<'EOF'
cat platform-engineering/6-sre/tasks/6.2.2-p95-rule.json
kubectl -n observability exec -i deploy/kube-prometheus-stack-grafana -c grafana -- curl -s -u admin:k8s-lab-admin -H 'Content-Type: application/json' -X POST localhost:3000/api/v1/provisioning/alert-rules -d @- < platform-engineering/6-sre/tasks/6.2.2-p95-rule.json
EOF
}
