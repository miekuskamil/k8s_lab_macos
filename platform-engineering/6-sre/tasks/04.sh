# Module 6.4, chaos engineering. Functions for task.sh: setup_6_4_N, check_6_4_N, solve_6_4_N.

# Chaos Mesh 2.8.7 with the module's values, unless it runs already.
chaos_mesh() {
  "${H[@]}" -n chaos-mesh status chaos-mesh >/dev/null 2>&1 && return 0
  echo "Installing Chaos Mesh 2.8.7 (about a minute)"
  "${H[@]}" upgrade --install chaos-mesh chaos-mesh --repo https://charts.chaos-mesh.org --version 2.8.7 \
    -n chaos-mesh --create-namespace -f "$M/6.4-chaos-mesh-values.yaml" --wait --timeout 5m >/dev/null
}
# order_ms <from-app> <url>: milliseconds one request takes, from a pod of the app
order_ms() {
  "${K[@]}" -n course-sre exec "deploy/$1" -- curl -s -o /dev/null -m 5 -w '%{time_total}' "$2" 2>/dev/null | awk '{printf "%d", $1 * 1000}'
}
no_chaos() {
  local kind
  for kind in networkchaos podchaos stresschaos httpchaos schedules; do
    "${K[@]}" delete "$kind.chaos-mesh.org" -A --all --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1
  done
}

# ---- Task 1: slow down only checkout's calls to payments ----------------------------------
setup_6_4_1() {
  checkout_app
  chaos_mesh
  no_chaos
  echo "Chaos Mesh runs, and no experiment is active. checkout and payments answer in a few ms."
}
check_6_4_1() {
  local j t direct
  j="$("${K[@]}" -n course-sre get networkchaos checkout-to-payments-delay -o json 2>/dev/null)"
  check "NetworkChaos course-sre/checkout-to-payments-delay exists" test -n "$j"
  check "it adds a 200 ms delay" matches "$(echo "$j" | python3 -c 'import json,sys; s=json.load(sys.stdin)["spec"]; print(s["action"], s.get("delay",{}).get("latency",""))' 2>/dev/null)" '^delay 200ms$'
  injected() { [ "$("${K[@]}" -n course-sre get networkchaos checkout-to-payments-delay -o jsonpath='{.status.conditions[?(@.type=="AllInjected")].status}' 2>/dev/null)" = True ]; }
  poll 60 injected
  check "Chaos Mesh injected it" injected
  t="$(order_ms loadgen http://checkout:8080/api/checkout)"
  check "an order through checkout takes 200 ms or more (${t:-?} ms)" at_least "$t" 200
  direct="$(order_ms loadgen http://payments:9898/api/info)"
  check "the client still reaches payments directly in under 100 ms (${direct:-?} ms)" below "$direct" 100
}
solve_6_4_1() {
  shown <<'EOF'
cat platform-engineering/6-sre/tasks/6.4.1-checkout-to-payments-delay.yaml
kubectl apply -f platform-engineering/6-sre/tasks/6.4.1-checkout-to-payments-delay.yaml
kubectl -n course-sre wait networkchaos/checkout-to-payments-delay --for=condition=AllInjected --timeout=60s
EOF
}

# ---- Task 2: find the experiment that nobody stopped --------------------------------------
setup_6_4_2() {
  checkout_app
  chaos_mesh
  no_chaos
  # An experiment with a harmless name, left behind in another namespace, that drops
  # 70% of the packets payments sends.
  "${K[@]}" apply -f - >/dev/null <<'EOF'
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: maintenance-window
  namespace: chaos-mesh
spec:
  action: loss
  mode: all
  selector:
    namespaces: [course-sre]
    labelSelectors: {app: payments}
  loss:
    loss: "70"
  duration: 2h
EOF
  # Remember the Deployments' generations, so the check sees whether they changed.
  "${K[@]}" -n course-sre create configmap task-6-4-2 --dry-run=client -o yaml \
    --from-literal=generations="$("${K[@]}" -n course-sre get deploy checkout payments -o jsonpath='{.items[*].metadata.generation}')" \
    | "${K[@]}" apply -f - >/dev/null
  echo "Orders started to fail a moment ago, and nobody changed checkout or payments."
  echo "Find out why and make the orders work again, without changing either Deployment (task 6.4.2)."
}
check_6_4_2() {
  local left codes
  left="$("${K[@]}" get networkchaos,podchaos,stresschaos,httpchaos,schedules.chaos-mesh.org -A --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  check "no chaos experiment exists in any namespace ($left left)" test "$left" = 0
  codes="$("${K[@]}" -n course-sre exec deploy/loadgen -- sh -c 'for i in $(seq 1 20); do curl -s -o /dev/null -m 3 -w "%{http_code}\n" http://checkout:8080/api/checkout; done' 2>/dev/null | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
  check "20 orders in a row answer 200 (${codes:-none})" matches "$codes" '^ ?20 200 $'
  check "checkout and payments were not changed" test "$("${K[@]}" -n course-sre get deploy checkout payments -o jsonpath='{.items[*].metadata.generation}')" = \
    "$("${K[@]}" -n course-sre get configmap task-6-4-2 -o jsonpath='{.data.generations}' 2>/dev/null)"
}
solve_6_4_2() {
  shown <<'EOF'
kubectl get networkchaos,podchaos,stresschaos -A
kubectl -n chaos-mesh describe networkchaos maintenance-window | grep -A3 -E '^  Action|^  Loss'
kubectl -n chaos-mesh delete networkchaos maintenance-window
EOF
}
