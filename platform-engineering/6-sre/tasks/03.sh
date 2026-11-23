# Module 6.3, autoscaling. Functions for task.sh: setup_6_3_N, check_6_3_N, solve_6_3_N.

# ---- Task 1: scale a CPU-bound deployment -------------------------------------------------
setup_6_3_1() {
  checkout_app
  "${K[@]}" -n course-sre delete hpa checkout --ignore-not-found >/dev/null
  "${K[@]}" -n course-sre delete scaledobject worker --ignore-not-found >/dev/null 2>&1 || true
  "${K[@]}" apply -f "$M/6.3-cpu-demo.yaml" >/dev/null
  "${K[@]}" -n course-sre delete hpa cpu-demo --ignore-not-found >/dev/null
  echo "cpu-demo is running two CPU-bound pods, but no HPA controls it."
  echo "Scale it between two and six replicas when average CPU exceeds 60% of its request."
}
check_6_3_1() {
  local spec
  spec="$("${K[@]}" -n course-sre get hpa cpu-demo -o jsonpath='{.spec.minReplicas} {.spec.maxReplicas} {.spec.metrics[0].resource.target.averageUtilization} {.spec.scaleTargetRef.name}' 2>/dev/null)"
  check "the CPU HPA targets cpu-demo with a 60% threshold and a 2-to-6 range" matches "$spec" '^2 6 60 cpu-demo$'
  cpu_scaled() { [[ "$("${K[@]}" -n course-sre get deploy cpu-demo -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" =~ ^[4-6]$ ]]; }
  if matches "$spec" '^2 6 60 cpu-demo$'; then
    poll 180 cpu_scaled
    check "the HPA adds replicas while CPU stays above target" cpu_scaled
  else
    check "the HPA adds replicas while CPU stays above target" false
  fi
}
solve_6_3_1() {
  shown <<'EOF'
kubectl apply -f platform-engineering/manifests/6.3-hpa-cpu.yaml
kubectl -n course-sre get hpa cpu-demo
EOF
}

# ---- Task 2: wake workers from a Redis queue ------------------------------------------------
setup_6_3_2() {
  checkout_app
  "${K[@]}" -n course-sre delete hpa checkout cpu-demo --ignore-not-found >/dev/null
  "${K[@]}" -n course-sre delete scaledobject worker --ignore-not-found >/dev/null 2>&1 || true
  "${K[@]}" -n course-sre delete deploy cpu-demo --ignore-not-found >/dev/null
  "${H[@]}" status keda -n keda >/dev/null 2>&1 || "${H[@]}" upgrade --install keda kedacore/keda --version 2.17.2 \
    -n keda --create-namespace -f "$M/6.3-keda-values.yaml" --wait --timeout 3m >/dev/null
  "${K[@]}" apply -f "$M/6.3-queue.yaml" >/dev/null
  "${K[@]}" -n course-sre rollout status deploy/queue --timeout=120s >/dev/null 2>&1
  "${K[@]}" -n course-sre delete scaledobject worker --ignore-not-found >/dev/null
  "${K[@]}" -n course-sre scale deployment/worker --replicas=0 >/dev/null
  "${K[@]}" -n course-sre exec deploy/queue -- sh -c 'redis-cli del orders >/dev/null; for i in $(seq 1 300); do redis-cli lpush orders "order-$i" >/dev/null; done' >/dev/null
  echo "Redis holds 300 orders, but the worker deployment has zero replicas."
  echo "Create a KEDA ScaledObject that wakes one worker for every 10 waiting orders, up to five."
}
check_6_3_2() {
  local spec
  spec="$("${K[@]}" -n course-sre get scaledobject worker -o jsonpath='{.spec.scaleTargetRef.name} {.spec.minReplicaCount} {.spec.maxReplicaCount} {.spec.triggers[0].type} {.spec.triggers[0].metadata.listLength}' 2>/dev/null)"
  check "KEDA watches the worker and the Redis list with a 0-to-5 range" matches "$spec" '^worker 0 5 redis 10$'
  workers_scaled() {
    [[ "$("${K[@]}" -n course-sre get scaledobject worker -o jsonpath='{.status.conditions[?(@.type=="Active")].status}' 2>/dev/null)" == True ]] &&
      [[ "$("${K[@]}" -n course-sre get deploy worker -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" =~ ^[3-5]$ ]]
  }
  if matches "$spec" '^worker 0 5 redis 10$'; then
    poll 180 workers_scaled
    check "KEDA starts workers for the queued orders" workers_scaled
  else
    check "KEDA starts workers for the queued orders" false
  fi
}
solve_6_3_2() {
  shown <<'EOF'
kubectl apply -f platform-engineering/manifests/6.3-scaledobject.yaml
kubectl -n course-sre get scaledobject worker
kubectl -n course-sre get deployment worker
EOF
}
