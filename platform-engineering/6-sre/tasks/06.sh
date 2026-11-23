# Module 6.6, capacity and cost. Functions for task.sh: setup_6_6_N, check_6_6_N, solve_6_6_N.

# ---- Task 1: right-size a Deployment's requests -------------------------------------------
setup_6_6_1() {
  "${K[@]}" apply -f "$M/6.6-capacity-demo.yaml" >/dev/null || return 1
  for app in overprovisioned right-sized; do
    "${K[@]}" -n course-capacity rollout status "deploy/$app" --timeout=120s >/dev/null || return 1
  done
  echo "Both Deployments run two idle pods. overprovisioned requests 250m CPU and 256Mi per pod."
  echo "Set its requests to 100m CPU and 128Mi. Keep two replicas and limits above the requests."
}
check_6_6_1() {
  local resources
  resources="$("${K[@]}" -n course-capacity get deploy overprovisioned -o jsonpath='{.spec.replicas} {.spec.template.spec.containers[0].resources.requests.cpu} {.spec.template.spec.containers[0].resources.requests.memory} {.spec.template.spec.containers[0].resources.limits.cpu} {.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null)"
  check "it keeps two replicas and lowers requests to 100m and 128Mi" matches "$resources" '^2 100m 128Mi '
  check "limits remain above the requests" matches "$resources" '^2 100m 128Mi 500m 512Mi$'
}
solve_6_6_1() {
  shown <<'EOF'
kubectl -n course-capacity set resources deployment/overprovisioned --requests=cpu=100m,memory=128Mi --limits=cpu=500m,memory=512Mi
kubectl -n course-capacity get deployment overprovisioned
EOF
}
