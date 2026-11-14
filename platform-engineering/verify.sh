#!/usr/bin/env bash
# Replay the key exercise of every course module and check the result.
# Use it to confirm the course works on your lab, or to check your own work.
#
#   ./platform-engineering/verify.sh          run every module (about 40 minutes)
#   ./platform-engineering/verify.sh 4 5      run only modules 4 and 5
#
# The script changes routing and policies while it runs and restores the baseline at the end.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M="$ROOT/platform-engineering/manifests"
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
I=(istioctl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
# Where the AI modules find Ollama. On WSL with Ollama for Windows, or any other
# machine, set LAB_OLLAMA_URL, for example http://$(hostname).local:11434.
OLLAMA="${LAB_OLLAMA_URL:-http://localhost:11434}"
BASE="${BASE_URL:-http://localhost:8080}"
PASS=0
FAIL=0

section() { printf '\n== Module %s\n' "$*"; }
pass() { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s (got: %s)\n' "$1" "$2"; }
# expect <description> <actual> <extended regex the actual value must match>
expect() { if [[ "$2" =~ $3 ]]; then pass "$1"; else fail "$1" "$2"; fi; }
# between <description> <actual> <min> <max>
between() { if (( $2 >= $3 && $2 <= $4 )); then pass "$1 ($2)"; else fail "$1, expected $3 to $4" "$2"; fi; }

code() { curl -s -o /dev/null -m 10 -w '%{http_code}' "$@" 2>/dev/null || true; }
settle() { sleep "${1:-5}"; }
in_shop() { "${K[@]}" -n shop exec deploy/course-client -- "$@" 2>/dev/null || true; }
in_outside() { "${K[@]}" -n course-outside exec deploy/client -- "$@" 2>/dev/null || true; }
in_sidecar() { "${K[@]}" -n course-sidecar exec deploy/client -c curl -- "$@" 2>/dev/null || true; }

# burst <count> <concurrency> <path>: prints "<status> <version>" per request
burst() {
  seq 1 "$1" | xargs -P "$2" -I{} curl -s -o /dev/null -m 15 \
    -w '%{http_code} %header{x-app-version}\n' "${BASE}$3" 2>/dev/null
}
count_matching() { grep -c "$1" || true; }

baseline() { "$ROOT/platform-engineering/reset.sh" >/dev/null 2>&1; settle 5; }

module_0() {
  section "0: the lab is ready"
  expect "kubectl reaches the cluster" "$("${K[@]}" get nodes --no-headers 2>&1 | awk '{print $2}' | head -1)" '^Ready$'
  expect "istioctl is installed" "$("${I[@]}" version 2>&1 | grep -c 'control plane version')" '^1$'
  expect "the shop answers on localhost:8080" "$(code "$BASE/healthz")" '^200$'
  expect "no ArgoCD application is unhealthy" "$("${K[@]}" -n argocd get applications --no-headers | awk '$3!="Healthy"' | wc -l | tr -d ' ')" '^0$'
  expect "Kiali answers" "$("${K[@]}" -n istio-system get deploy kiali -o jsonpath='{.status.readyReplicas}')" '^1$'
}

module_1() {
  section "1: what a mesh adds"
  expect "the shop namespace is in ambient mode" "$("${K[@]}" get ns shop -o jsonpath='{.metadata.labels.istio\.io/dataplane-mode}')" '^ambient$'
  expect "shop pods have no sidecar (one container each)" "$("${K[@]}" -n shop get pods -l app=backend -o jsonpath='{.items[0].spec.containers[*].name}')" '^backend$'
  expect "ztunnel lists the backend as an HBONE workload" "$("${I[@]}" ztunnel-config workloads 2>/dev/null | grep -c 'backend-v1.*HBONE')" '^[1-9]'
  expect "responses pass through Envoy" "$(curl -s -m 10 -D - -o /dev/null "$BASE/api/version" | tr -d '\r' | grep -i '^server:')" 'istio-envoy'
  local services
  services="$("${I[@]}" ztunnel-config services 2>/dev/null)"
  expect "the backend Service uses the waypoint" "$(echo "$services" | awk '$1=="shop" && $2=="backend" {print $4}')" '^waypoint$'
  expect "the frontend Service has no waypoint" "$(echo "$services" | awk '$1=="shop" && $2=="frontend" {print $4}')" '^None$'
  expect "the backend Service carries the use-waypoint label" "$("${K[@]}" -n shop get svc backend -o jsonpath='{.metadata.labels.istio\.io/use-waypoint}')" '^waypoint$'
  local proxies
  proxies="$("${I[@]}" proxy-status 2>/dev/null)"
  expect "istiod manages the gateway, the waypoint and ztunnel" "$(echo "$proxies" | grep -oE '^(shop-gateway-istio|waypoint|ztunnel)-' | sort -u | wc -l | tr -d ' ')" '^3$'
  expect "no shop app pod has a proxy of its own" "$(echo "$proxies" | grep -cE '^(backend|frontend|redis)-')" '^0$'
}

module_2() {
  section "2: identity and mTLS"
  "${K[@]}" apply -f "$M/02-outside-client.yaml" >/dev/null
  "${K[@]}" -n course-outside rollout status deploy/client --timeout=180s >/dev/null
  "${K[@]}" label ns course-outside istio.io/dataplane-mode- >/dev/null 2>&1; settle 3
  expect "ztunnel holds a certificate for the backend identity" "$("${I[@]}" ztunnel-config certificates 2>/dev/null | grep -c 'ns/shop/sa/backend.*Leaf')" '^[1-9]'
  expect "a client outside the mesh cannot reach the frontend" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://frontend.shop:3000/healthz)" '^000$'
  settle 2
  expect "ztunnel logs the STRICT policy as the reason" "$("${K[@]}" -n istio-system logs ds/ztunnel --since=1m 2>/dev/null | grep 'src.namespace="course-outside"' | grep -c 'istio_converted_static_strict')" '^[1-9]'
  local client_pod
  client_pod="$("${K[@]}" -n course-outside get pod -l app=client -o jsonpath='{.items[0].metadata.name}')"
  expect "outside the mesh, ztunnel lists the client as TCP" "$("${I[@]}" ztunnel-config workloads 2>/dev/null | awk -v p="$client_pod" '$2==p {print $NF}')" '^TCP$'
  "${K[@]}" label ns course-outside istio.io/dataplane-mode=ambient --overwrite >/dev/null; settle 6
  expect "after labeling its namespace, the same pod gets in without a restart" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://frontend.shop:3000/healthz)" '^200$'
  expect "enrolled, ztunnel lists the same client pod as HBONE" "$("${I[@]}" ztunnel-config workloads 2>/dev/null | awk -v p="$client_pod" '$2==p {print $NF}')" '^HBONE$'
  expect "ztunnel holds a certificate for the client's service account" "$("${I[@]}" ztunnel-config certificates 2>/dev/null | grep -c 'ns/course-outside/sa/default.*Leaf')" '^[1-9]'
  expect "the client pod never restarted" "$("${K[@]}" -n course-outside get pod "$client_pod" -o jsonpath='{.status.containerStatuses[0].restartCount}')" '^0$'
  "${K[@]}" label ns course-outside istio.io/dataplane-mode- >/dev/null; settle 6
  expect "after removing the label, it is locked out again" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://frontend.shop:3000/healthz)" '^000$'
}

module_3() {
  section "3: authorization"
  "${K[@]}" apply -f "$M/03-course-client.yaml" >/dev/null
  "${K[@]}" -n shop rollout status deploy/course-client --timeout=180s >/dev/null
  "${K[@]}" -n shop delete authorizationpolicy backend-allow-course-client --ignore-not-found >/dev/null; settle 4
  local pod_ip
  pod_ip="$("${K[@]}" -n shop get pod -l app=backend,version=v1 -o jsonpath='{.items[0].status.podIP}')"
  expect "course-client is refused by the waypoint (L7)" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' http://backend:8000/api/version)" '^403$'
  expect "the waypoint writes the refusal body itself" "$(in_shop curl -s -m 5 http://backend:8000/api/version)" '^RBAC: access denied$'
  expect "the frontend has no policy and answers course-client" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' http://frontend:3000/healthz)" '^200$'
  "${K[@]}" apply -f "$M/03-allow-course-client.yaml" >/dev/null; settle 4
  expect "with its own rule, GET /api/version is allowed" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' http://backend:8000/api/version)" '^200$'
  expect "the rule does not cover /api/orders" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' http://backend:8000/api/orders)" '^403$'
  expect "dialing a backend pod IP is refused by ztunnel (L4)" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' "http://${pod_ip}:8000/api/orders")" '^000$'
  settle 2
  expect "ztunnel logs the L4 policy rejection" "$("${K[@]}" -n istio-system logs ds/ztunnel --since=1m 2>/dev/null | grep 'sa/course-client' | grep -c 'allow policies exist, but none allowed')" '^[1-9]'
  expect "the shop itself keeps working (ALLOW policies add up)" "$(code "$BASE/api/orders")" '^200$'
  # Policy changes reach ztunnel within a few seconds. Wait long enough to be sure.
  "${K[@]}" -n shop delete authorizationpolicy backend-only-from-waypoint >/dev/null; settle 10
  expect "without the L4 policy, the pod IP bypasses the waypoint rules" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' "http://${pod_ip}:8000/api/orders")" '^200$'
  "${K[@]}" apply -f "$ROOT/manifests/istio/security.yaml" >/dev/null; settle 10
  expect "with the L4 policy back, the bypass is closed" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' "http://${pod_ip}:8000/api/orders")" '^000$'
  "${K[@]}" -n shop delete authorizationpolicy backend-allow-course-client >/dev/null
}

module_4() {
  section "4: traffic routing"
  baseline
  local out
  out="$(burst 100 10 /api/version)"
  between "baseline sends everything to v1" "$(echo "$out" | count_matching ' v1$')" 100 100
  "${K[@]}" apply -f "$ROOT/manifests/scenarios/a-canary-httproute.yaml" >/dev/null; settle 5
  out="$(burst 300 10 /api/version)"
  between "canary 90/10: v2 gets about 10% of 300" "$(echo "$out" | count_matching ' v2$')" 10 60
  "${K[@]}" apply -f "$M/04-route-50-50.yaml" >/dev/null; settle 5
  out="$(burst 300 10 /api/version)"
  between "50/50: v2 gets about half of 300" "$(echo "$out" | count_matching ' v2$')" 110 190
  "${K[@]}" apply -f "$M/04-route-by-path.yaml" >/dev/null; settle 5
  between "path rule: /api/version always reaches v2" "$(burst 50 5 /api/version | count_matching ' v2$')" 50 50
  between "path rule: /api/orders always reaches v1" "$(burst 50 5 /api/orders | count_matching ' v1$')" 50 50
  expect "the waypoint holds the path match from the HTTPRoute" "$("${I[@]}" proxy-config routes deploy/waypoint -n shop 2>/dev/null | grep 'backend.shop' | grep -c 'PathPrefix:/api/version.*backend-route-0-istio-autogenerated-k8s-gateway')" '^[1-9]'
  sed 's/name: backend-v2/name: backend-v3/' "$M/04-route-by-path.yaml" | "${K[@]}" apply -f - >/dev/null; settle 5
  expect "a broken backendRef reports ResolvedRefs=False BackendNotFound" "$("${K[@]}" -n shop get httproute backend-route -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status} {.status.parents[0].conditions[?(@.type=="ResolvedRefs")].reason}')" '^False BackendNotFound$'
  expect "the broken rule fails /api/version" "$(code "$BASE/api/version")" '^500$'
  expect "the other rule keeps /api/orders working" "$(code "$BASE/api/orders")" '^200$'
  baseline
}

module_5() {
  section "5: resilience"
  baseline
  # waypoint_log <regex>: how many recent waypoint access log lines match
  waypoint_log() { settle 2; "${K[@]}" -n shop logs deploy/waypoint --since=2m 2>/dev/null | grep -cE "$1" || true; }
  "${K[@]}" -n shop delete httproute backend-route >/dev/null
  "${K[@]}" apply -f "$ROOT/manifests/scenarios/b-fault-injection.yaml" -f "$M/06-waypoint-access-logs.yaml" >/dev/null; settle 6
  local out started elapsed
  out="$(burst 200 10 /api/orders)"
  between "fault injection: about 10% of 200 return 503" "$(echo "$out" | count_matching '^503')" 5 45
  expect "fault injection: the waypoint logs the 503s with DI,FI" "$(waypoint_log '"GET /api/orders HTTP/1.1" 503 DI,FI')" '^[1-9]'
  between "fault injection: /api/version stays clean" "$(burst 40 5 /api/version | count_matching '^200')" 40 40
  started=$(date +%s); curl -s -o /dev/null -m 10 "$BASE/api/orders"; curl -s -o /dev/null -m 10 "$BASE/api/orders"; elapsed=$(( $(date +%s) - started ))
  between "fault injection: two requests take at least 1 second" "$elapsed" 1 5
  baseline
  "${K[@]}" apply -f "$M/05-timeout.yaml" -f "$M/06-waypoint-access-logs.yaml" >/dev/null; settle 5
  expect "timeout: a 300 ms request still succeeds" "$(code "$BASE/api/slow?ms=300")" '^200$'
  expect "timeout: a 3 s request is cut off with 504" "$(code "$BASE/api/slow?ms=3000")" '^504$'
  expect "timeout: the waypoint wrote the body" "$(curl -s -m 10 "$BASE/api/slow?ms=3000")" '^upstream request timeout$'
  expect "timeout: the access log shows UT response_timeout" "$(waypoint_log '504 UT response_timeout')" '^[1-9]'
  baseline
  between "no circuit breaker: 50 parallel slow requests all succeed" "$(burst 200 50 '/api/slow?ms=300' | count_matching '^200')" 195 200
  "${K[@]}" apply -f "$ROOT/manifests/scenarios/c-circuit-breaker.yaml" -f "$M/06-waypoint-access-logs.yaml" >/dev/null; settle 6
  between "circuit breaker: most of 200 parallel requests get 503" "$(burst 200 50 '/api/slow?ms=300' | count_matching '^503')" 100 200
  expect "circuit breaker: the access log shows UO overflow" "$(waypoint_log '503 UO upstream_reset_before_response_started\{overflow\}')" '^[1-9]'
  baseline
  "${K[@]}" apply -f "$M/06-waypoint-access-logs.yaml" >/dev/null
  "${K[@]}" -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=20 >/dev/null
  "${K[@]}" -n shop rollout status deploy/backend-v1 --timeout=180s >/dev/null
  "${K[@]}" -n shop rollout status deploy/backend-v2 --timeout=180s >/dev/null; settle 20
  between "rate limit: some of 400 requests get 429" "$(burst 400 40 /api/orders | count_matching '^429')" 50 400
  expect "rate limit: the 429s come from the backend (via_upstream, no flag)" "$(waypoint_log '"GET /api/orders HTTP/1.1" 429 - via_upstream')" '^[1-9]'
  expect "rate limit: ArgoCD left the setting alone" "$("${K[@]}" -n shop get deploy backend-v1 -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="RATE_LIMIT_RPS")].value}')" '^20$'
  baseline
}

module_6() {
  section "6: observability"
  baseline
  curl -s -o /dev/null -m 10 -X POST -H 'content-type: application/json' -d '{"item":"verify","quantity":1}' "$BASE/api/orders"
  settle 9
  local trace_id
  trace_id="$("${K[@]}" get --raw '/api/v1/namespaces/observability/services/jaeger-query:16686/proxy/api/traces?service=backend&operation=POST%20%2Fapi%2Forders&limit=1&lookback=2m' 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; print(d[0]["traceID"] if d else "none")' 2>/dev/null)"
  expect "Jaeger has a trace for POST /api/orders" "$trace_id" '^[0-9a-f]{16,32}$'
  expect "the same trace id appears in the backend logs" "$("${K[@]}" -n shop logs -l app=backend --tail=300 2>/dev/null | grep -c "$trace_id")" '^[1-9]'
  expect "that trace spans the gateway, the waypoint and the backend" "$("${K[@]}" get --raw "/api/v1/namespaces/observability/services/jaeger-query:16686/proxy/api/traces/${trace_id}" 2>/dev/null | python3 -c 'import json,sys; t=json.load(sys.stdin)["data"][0]; print(len({p["serviceName"] for p in t["processes"].values()}))' 2>/dev/null)" '^3$'
  "${K[@]}" apply -f "$M/06-waypoint-access-logs.yaml" >/dev/null; settle 5
  curl -s -o /dev/null -m 10 "$BASE/api/version"; settle 2
  expect "the waypoint writes access logs after the Telemetry rule" "$("${K[@]}" -n shop logs deploy/waypoint --tail=20 2>/dev/null | grep -c 'GET /api/version')" '^[1-9]'
  expect "Prometheus has waypoint request metrics" "$("${K[@]}" get --raw '/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=count(istio_requests_total%7Breporter%3D%22waypoint%22%7D)' 2>/dev/null | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else 0)' 2>/dev/null)" '^[1-9]'
  # Loki: the backend's log line for that trace arrives through Alloy within a few seconds.
  local loki_lines=0 now
  for _ in 1 2 3 4 5 6; do
    now=$(date +%s)
    loki_lines="$("${K[@]}" get --raw "/api/v1/namespaces/observability/services/loki:3100/proxy/loki/api/v1/query_range?query=%7Bnamespace%3D%22shop%22%2Capp%3D%22backend%22%7D%20%7C%3D%20%22${trace_id}%22&start=$((now - 600))000000000&end=${now}000000000&limit=100" 2>/dev/null | python3 -c 'import json,sys; print(sum(len(s["values"]) for s in json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo 0)"
    [[ "$loki_lines" =~ ^[1-9] ]] && break
    settle 5
  done
  expect "Loki finds the backend log line by trace id" "$loki_lines" '^[1-9]'
  expect "Grafana loads the Shop logs dashboard" "$("${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- sh -c \
    'curl -s -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" localhost:3000/api/dashboards/uid/shop-logs' 2>/dev/null | grep -o '"title":"Shop logs"' | head -1)" '^"title":"Shop logs"$'
  local logql; logql="$(python3 -c 'import urllib.parse; print(urllib.parse.quote("sum by (status) (count_over_time({namespace=\"shop\", app=\"backend\"} | json | message=\"request handled\" [5m]))"))')"
  expect "LogQL parses the backend's JSON and counts requests by status" "$("${K[@]}" get --raw "/api/v1/namespaces/observability/services/loki:3100/proxy/loki/api/v1/query?query=${logql}" 2>/dev/null | grep -o '"status":"2[0-9][0-9]"' | head -1)" '"status":"2'
  "${K[@]}" -n istio-system patch telemetry mesh-default --type merge \
    -p '{"spec":{"tracing":[{"providers":[{"name":"jaeger-otlp"}],"randomSamplingPercentage":10}]}}' >/dev/null; settle 8
  local t0; t0=$(date +%s)
  burst 200 10 /api/version >/dev/null; settle 12
  between "10% sampling: Jaeger keeps about 20 of 200 traces" "$("${K[@]}" get --raw "/api/v1/namespaces/observability/services/jaeger-query:16686/proxy/api/traces?service=shop-gateway-istio.shop-ingress&limit=500&start=${t0}000000&end=$(date +%s)000000" 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]))' 2>/dev/null || echo 0)" 4 60
  baseline
  expect "reset.sh puts sampling back to 100%" "$("${K[@]}" -n istio-system get telemetry mesh-default -o jsonpath='{.spec.tracing[0].randomSamplingPercentage}')" '^100$'
}

module_7() {
  section "7: sidecar mode"
  "${K[@]}" apply -f "$M/07-sidecar-namespace.yaml" -f "$M/07-sidecar-apps.yaml" -f "$M/07-sidecar-podmonitor.yaml" >/dev/null
  "${K[@]}" -n course-sidecar rollout status deploy/httpbin --timeout=240s >/dev/null
  "${K[@]}" -n course-sidecar rollout status deploy/client --timeout=240s >/dev/null
  "${K[@]}" apply -f "$M/02-outside-client.yaml" >/dev/null
  "${K[@]}" -n course-outside rollout status deploy/client --timeout=180s >/dev/null
  "${K[@]}" -n course-sidecar delete peerauthentication,virtualservice --all --ignore-not-found >/dev/null 2>&1; settle 4
  expect "injected pods run two containers" "$("${K[@]}" -n course-sidecar get pod -l app=httpbin -o jsonpath='{.items[0].spec.containers[*].name}')" 'httpbin istio-proxy'
  expect "the injector added the istio-init container" "$("${K[@]}" -n course-sidecar get pod -l app=httpbin -o jsonpath='{.items[0].spec.initContainers[*].name}')" '^istio-init$'
  local httpbin_pod
  httpbin_pod="$("${K[@]}" -n course-sidecar get pod -l app=httpbin -o jsonpath='{.items[0].metadata.name}')"
  expect "istioctl describe reports PERMISSIVE by default" "$("${I[@]}" x describe pod "$httpbin_pod.course-sidecar" 2>/dev/null | grep 'Workload mTLS mode')" 'PERMISSIVE'
  # The Prometheus operator turns the PodMonitor into a scrape job within seconds.
  local scrape_jobs=0
  for _ in 1 2 3 4 5 6; do
    scrape_jobs="$("${K[@]}" -n observability get secret prometheus-kube-prometheus-stack-prometheus -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip 2>/dev/null | grep -c 'podMonitor/course-sidecar/sidecars' || true)"
    [[ "$scrape_jobs" =~ ^[1-9] ]] && break
    settle 5
  done
  expect "the operator added the sidecar PodMonitor to Prometheus's config" "$scrape_jobs" '^[1-9]'
  expect "httpbin sees the client certificate identity" "$(in_sidecar curl -s -m 5 http://httpbin:8000/headers | grep -c 'spiffe://cluster.local/ns/course-sidecar/sa/client')" '^[1-9]'
  expect "PERMISSIVE: a plaintext client gets in" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://httpbin.course-sidecar:8000/status/200)" '^200$'
  "${K[@]}" apply -f "$M/07-sidecar-strict-mtls.yaml" >/dev/null; settle 5
  expect "STRICT: the plaintext client is refused" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://httpbin.course-sidecar:8000/status/200)" '^000$'
  expect "STRICT: the sidecar client still works" "$(in_sidecar curl -s -m 5 -o /dev/null -w '%{http_code}' http://httpbin:8000/status/200)" '^200$'
  expect "istioctl describe now reports STRICT" "$("${I[@]}" x describe pod "$httpbin_pod.course-sidecar" 2>/dev/null | grep 'Workload mTLS mode')" 'STRICT'
  local plain retried
  plain="$(in_sidecar sh -c 'ok=0; for i in $(seq 1 80); do c=$(curl -s -o /dev/null -w "%{http_code}" "http://httpbin:8000/unstable?failure_rate=0.5"); [ "$c" = 200 ] && ok=$((ok+1)); done; echo $ok')"
  "${K[@]}" apply -f "$M/07-sidecar-retries.yaml" >/dev/null; settle 5
  retried="$(in_sidecar sh -c 'ok=0; for i in $(seq 1 80); do c=$(curl -s -o /dev/null -w "%{http_code}" "http://httpbin:8000/unstable?failure_rate=0.5"); [ "$c" = 200 ] && ok=$((ok+1)); done; echo $ok')"
  if (( retried > plain )); then pass "retries raise the success count ($plain of 80 without, $retried of 80 with)"; else fail "retries raise the success count" "$plain without, $retried with"; fi
  "${K[@]}" apply -f "$M/07-sidecar-fault.yaml" >/dev/null; settle 5
  expect "the client sidecar injects a 2 s delay" "$(in_sidecar curl -s -m 10 -o /dev/null -w '%{time_total}' http://httpbin:8000/status/200)" '^2\.'
  "${K[@]}" -n course-sidecar delete virtualservice httpbin >/dev/null
  expect "cross-mode: the sidecar client reaches the ambient frontend" "$(in_sidecar curl -s -m 5 -o /dev/null -w '%{http_code}' http://frontend.shop:3000/healthz)" '^200$'
  expect "cross-mode: the sidecar client cannot reach the backend" "$(in_sidecar curl -s -m 5 -o /dev/null -w '%{http_code}' http://backend.shop:8000/api/version)" '^(503|000)$'
  settle 2
  expect "cross-mode: the backend's ztunnel rejects the sidecar's identity" "$("${K[@]}" -n istio-system logs ds/ztunnel --since=1m 2>/dev/null | grep 'ns/course-sidecar/sa/client' | grep -c 'allow policies exist, but none allowed')" '^[1-9]'
  expect "istioctl sees the sidecar proxies" "$("${I[@]}" proxy-status 2>/dev/null | grep -c 'course-sidecar')" '^2$'
}

module_8() {
  section "8: incidents"
  baseline
  "$ROOT/platform-engineering/incident.sh" 1 >/dev/null; settle 5
  expect "incident 1 shows 403" "$(code "$BASE/api/orders")" '^403$'
  baseline
  "$ROOT/platform-engineering/incident.sh" 2 >/dev/null; settle 6
  between "incident 2 shows 503 under parallel load" "$(burst 120 30 '/api/slow?ms=300' | count_matching '^503')" 30 120
  baseline
  "$ROOT/platform-engineering/incident.sh" 3 >/dev/null; settle 6
  local out
  out="$(burst 100 10 /api/orders)"
  between "incident 3 returns no errors" "$(echo "$out" | count_matching '^200')" 100 100
  between "incident 3 sends most traffic to v2" "$(echo "$out" | count_matching ' v2$')" 50 90
  # One URL per curl call: with several URLs, "-o /dev/null" only applies to the first one.
  local slow_v2=0 line
  for _ in 1 2 3 4 5 6 7 8; do
    line="$(curl -s -m 10 -o /dev/null -w '%{time_total} %header{x-app-version}' "$BASE/api/orders")"
    awk -v l="$line" 'BEGIN {split(l, f, " "); exit !(f[1] >= 0.6 && f[2] == "v2")}' && slow_v2=$((slow_v2 + 1))
  done
  expect "incident 3 makes v2 slow (v2 answers take 0.6 s or more)" "$slow_v2" '^[1-9]'
  baseline
  "$ROOT/platform-engineering/incident.sh" 4 >/dev/null; settle 8
  expect "incident 4 shows 502" "$(code "$BASE/api/orders")" '^502$'
  baseline
  expect "after the repair the shop answers 200" "$(code "$BASE/api/orders")" '^200$'
}

module_11() {
  section "11: TLS at the edge"
  baseline
  local ca="${TMPDIR:-/tmp}/k8s-lab-ca.crt" before after
  expect "the lab-ca issuer is Ready" "$("${K[@]}" get clusterissuer lab-ca -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')" '^True$'
  "${K[@]}" -n cert-manager get secret lab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > "$ca"
  "${K[@]}" apply -f "$M/11-certificate.yaml" >/dev/null
  expect "cert-manager issues the shop certificate" "$("${K[@]}" -n shop-ingress wait --for=condition=Ready certificate/shop-tls --timeout=90s 2>&1)" 'condition met'
  expect "the lab root CA signed it" "$("${K[@]}" -n shop-ingress get secret shop-tls -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -issuer)" 'k8s-lab root CA'
  "${K[@]}" apply -f "$M/11-gateway-https.yaml" >/dev/null
  "${K[@]}" -n shop-ingress wait --for=condition=Programmed gateway/shop-gateway --timeout=60s >/dev/null 2>&1
  local c=000
  for _ in $(seq 1 12); do c="$(code --cacert "$ca" "https://localhost:8443/healthz")"; [[ "$c" == 200 ]] && break; settle 5; done
  expect "HTTPS answers when curl trusts the lab CA" "$c" '^200$'
  expect "HTTPS fails when curl does not trust the lab CA" "$(curl -s -o /dev/null -m 10 -w '%{exitcode}' https://localhost:8443/healthz 2>/dev/null)" '^60$'
  "${K[@]}" apply -f "$M/11-redirect.yaml" >/dev/null; settle 8
  expect "plain HTTP gets a 301 to HTTPS" "$(curl -s -o /dev/null -m 10 -w '%{http_code} %{redirect_url}' "$BASE/api/orders")" '^301 https://localhost:8443/api/orders$'
  expect "following the redirect reaches the shop" "$(code -L --cacert "$ca" "$BASE/api/orders")" '^200$'
  before="$(openssl s_client -connect 127.0.0.1:8443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -serial 2>/dev/null)"
  local restarts; restarts="$("${K[@]}" -n shop-ingress get pods -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')"
  "${K[@]}" -n shop-ingress delete secret shop-tls >/dev/null
  after="$before"
  for _ in $(seq 1 20); do settle 3; after="$(openssl s_client -connect 127.0.0.1:8443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -serial 2>/dev/null)"; [[ -n "$after" && "$after" != "$before" ]] && break; done
  expect "a deleted Secret brings a new certificate (new serial)" "$([[ -n "$after" && "$after" != "$before" ]] && echo changed || echo "same: $after")" '^changed$'
  expect "the gateway serves it without a restart" "$("${K[@]}" -n shop-ingress get pods -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}')" "^${restarts}\$"
  baseline
  expect "after the reset plain HTTP serves the shop again" "$(code "$BASE/api/orders")" '^200$'
  rm -f "$ca"
}

module_12() {
  section "12: egress"
  baseline
  "${K[@]}" apply -f "$M/03-course-client.yaml" >/dev/null
  # A fresh pod picks up DNS capture, which older labs turned on after the pod started.
  "${K[@]}" -n shop rollout restart deploy/course-client >/dev/null
  "${K[@]}" -n shop rollout status deploy/course-client --timeout=120s >/dev/null
  ext() { in_shop curl -s -o /dev/null -m 10 -w '%{http_code}' "$@"; }
  expect "by default a mesh pod reaches any website" "$(ext https://example.com)" '^200$'
  "${K[@]}" apply -f "$M/12-serviceentry.yaml" >/dev/null; settle 8
  expect "DNS answers httpbin.org with the ServiceEntry's virtual IP" "$(in_shop nslookup httpbin.org | grep -A1 'Name:' | grep -o '240\.240\.[0-9.]*' | head -1)" '^240\.240\.'
  expect "the waypoint adds TLS (httpbin sees https)" "$(in_shop curl -s -m 15 http://httpbin.org/get | grep '"url"')" 'https://httpbin.org/get'
  settle 2
  expect "ztunnel sends the call to the waypoint" "$("${K[@]}" -n istio-system logs ds/ztunnel --since=30s | grep course-client | grep 'dst.service="httpbin.org"' | grep -c 'dst.workload="waypoint')" '^[1-9]'
  "${K[@]}" apply -f "$M/12-egress-lockdown.yaml" >/dev/null; settle 5
  expect "with the NetworkPolicy, other websites are blocked" "$(ext https://example.com)" '^000$'
  expect "httpbin.org still works through the waypoint" "$(ext http://httpbin.org/get)" '^200$'
  "${K[@]}" apply -f "$M/12-egress-policy.yaml" >/dev/null; settle 6
  expect "the L7 rule allows GET /get" "$(ext http://httpbin.org/get)" '^200$'
  expect "the L7 rule blocks GET /ip" "$(ext http://httpbin.org/ip)" '^403$'
  expect "the L7 rule blocks POST /post" "$(ext -X POST http://httpbin.org/post)" '^403$'
  baseline
  expect "after the reset the course client reaches any website again" "$(ext https://example.com)" '^200$'
}

module_13() {
  section "13: end-user authentication with JWT"
  baseline
  local J="$ROOT/platform-engineering/jwt"
  tok() { code -H "Authorization: Bearer $(cat "$J/$1.jwt")" "${@:2}"; }
  "${K[@]}" apply -f "$M/13-request-authentication.yaml" >/dev/null; settle 6
  expect "with RequestAuthentication only, no token still passes" "$(code "$BASE/api/orders")" '^200$'
  expect "a valid token passes" "$(tok alice "$BASE/api/orders")" '^200$'
  expect "an expired token gets 401" "$(tok expired "$BASE/api/orders")" '^401$'
  expect "a token signed with an unknown key gets 401" "$(tok forged "$BASE/api/orders")" '^401$'
  "${K[@]}" apply -f "$M/13-require-jwt.yaml" >/dev/null; settle 6
  expect "the web page stays open without a token" "$(code "$BASE/")" '^200$'
  expect "the API now needs a token (403 without one)" "$(code "$BASE/api/orders")" '^403$'
  expect "alice reads orders" "$(tok alice "$BASE/api/orders")" '^200$'
  expect "alice may not create orders" "$(tok alice -X POST -H 'Content-Type: application/json' -d '{"item":"book","quantity":1}' "$BASE/api/orders")" '^403$'
  expect "an admin token creates an order" "$(tok admin -X POST -H 'Content-Type: application/json' -d '{"item":"book","quantity":1}' "$BASE/api/orders")" '^201$'
  baseline
  expect "after the reset the API answers without a token" "$(code "$BASE/api/orders")" '^200$'
}

module_15() {
  section "15: outlier detection and retries"
  baseline
  "${K[@]}" apply -f "$M/15-faulty-pod.yaml" >/dev/null
  "${K[@]}" -n shop rollout status deploy/backend-v1-faulty --timeout=120s >/dev/null 2>&1; settle 5
  faulty_calls() { "${K[@]}" -n shop logs deploy/backend-v1-faulty --since=30m 2>/dev/null | grep -c '/api/orders' || true; }
  local out before
  out="$(burst 90 3 /api/orders)"
  between "a faulty pod makes about a third of requests fail" "$(echo "$out" | count_matching '^503')" 15 50
  "${K[@]}" apply -f "$M/15-outlier-detection.yaml" >/dev/null; settle 6
  burst 30 3 /api/orders >/dev/null; settle 2
  between "outlier detection ejects it: no more failures" "$(burst 90 3 /api/orders | count_matching '^503')" 0 0
  "${K[@]}" -n shop delete destinationrule backend-v1-outlier >/dev/null
  "${K[@]}" -n shop delete httproute backend-route >/dev/null
  "${K[@]}" apply -f "$M/15-retries.yaml" >/dev/null; settle 8
  before="$(faulty_calls)"
  between "retries alone hide every failure" "$(burst 90 3 /api/orders | count_matching '^200')" 90 90
  settle 2
  between "but the faulty pod still gets calls" "$(( $(faulty_calls) - before ))" 15 60
  "${K[@]}" apply -f "$M/15-outlier-detection.yaml" >/dev/null; settle 6
  before="$(faulty_calls)"
  between "retries plus outlier detection: no failures" "$(burst 90 3 /api/orders | count_matching '^200')" 90 90
  settle 2
  between "and the faulty pod is left alone" "$(( $(faulty_calls) - before ))" 0 6
  baseline
  expect "after the reset the faulty pod is gone" "$("${K[@]}" -n shop get deploy backend-v1-faulty 2>&1 | grep -c NotFound)" '^1$'
  expect "and the shop answers 200" "$(code "$BASE/api/orders")" '^200$'
}

module_16() {
  section "16: the Istio API (Gateway and VirtualService)"
  baseline
  helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" install istio-ingress istio/gateway -n istio-ingress --create-namespace \
    --version 1.24.2 --skip-schema-validation --set service.type=ClusterIP --wait --timeout 3m >/dev/null 2>&1
  expect "the classic gateway runs, with a proxy injected" "$("${K[@]}" -n istio-ingress get pods -l istio=ingress -o jsonpath='{.items[0].spec.containers[0].image}')" 'proxyv2'
  "${K[@]}" apply -f "$M/16-istio-gateway.yaml" -f "$M/16-ingress-virtualservice.yaml" >/dev/null
  "${K[@]}" -n istio-ingress port-forward svc/istio-ingress 9080:80 >/dev/null 2>&1 &
  local pf=$! c=000
  for _ in $(seq 1 12); do settle 3; c="$(code http://localhost:9080/)"; [[ "$c" == 200 ]] && break; done
  expect "the shop answers through the Istio Gateway and VirtualService" "$c" '^200$'
  "${K[@]}" -n shop delete httproute backend-route >/dev/null
  "${K[@]}" apply -f "$M/16-subsets.yaml" -f "$M/16-canary-virtualservice.yaml" >/dev/null; settle 8
  local out; out="$(BASE=http://localhost:9080 burst 200 5 /api/orders)"
  between "the VirtualService splits about 90/10 with subsets (v2 share of 200)" "$(echo "$out" | count_matching ' v2$')" 6 40
  "${K[@]}" apply -f "$M/03-course-client.yaml" -f "$M/03-allow-course-client.yaml" >/dev/null
  "${K[@]}" -n shop rollout status deploy/course-client --timeout=120s >/dev/null 2>&1; settle 5
  expect "the header x-version: v2 always reaches v2" "$(in_shop sh -c 'for i in $(seq 1 10); do curl -s -o /dev/null -w "%header{x-app-version}\n" -H "x-version: v2" http://backend:8000/api/version; done' | sort -u | tr -d '\n')" '^v2$'
  kill "$pf" 2>/dev/null; wait "$pf" 2>/dev/null
  baseline
  expect "after the reset the classic gateway is gone" "$("${K[@]}" get ns istio-ingress 2>&1 | grep -c NotFound)" '^1$'
}

module_17() {
  section "17: an LLM as a mesh service"
  baseline
  local model
  model="${LAB_OLLAMA_MODEL:-$(curl -s -m 5 $OLLAMA/api/tags | python3 -c 'import json,sys; m=json.load(sys.stdin)["models"]; c=[x["name"] for x in m if "embed" not in x["name"]]; print(c[0] if c else "")' 2>/dev/null)}"
  if [[ -z "$model" ]]; then
    fail "Ollama runs on this machine with at least one model" "no answer from $OLLAMA/api/tags"
    return
  fi
  ask() { curl -s -m 180 -X POST "$BASE/api/ask" -H 'Content-Type: application/json' -d "{\"question\":\"$1\"}" 2>/dev/null; }
  "${K[@]}" apply -f "$M/17-assistant.yaml" -f "$M/03-course-client.yaml" >/dev/null
  "${K[@]}" -n shop set env deploy/assistant OLLAMA_MODEL="$model" >/dev/null
  "${K[@]}" -n shop rollout status deploy/assistant --timeout=120s >/dev/null 2>&1
  "${K[@]}" -n shop rollout status deploy/course-client --timeout=120s >/dev/null 2>&1; settle 5
  expect "without permission the backend refuses the assistant (403)" "$(ask 'How many orders are there?')" '403 Forbidden'
  "${K[@]}" apply -f "$M/17-allow-assistant.yaml" >/dev/null; settle 6
  expect "with the allow policy the model answers ($model)" "$(ask 'How many orders are there?' | python3 -c 'import json,sys; d=json.load(sys.stdin); print("answered" if d.get("answer") and d.get("output_tokens",0)>0 else d)' 2>&1)" '^answered$'
  "${K[@]}" apply -f "$M/17-ollama-serviceentry.yaml" >/dev/null; settle 4
  "${K[@]}" -n shop rollout restart deploy/assistant >/dev/null
  "${K[@]}" -n shop rollout status deploy/assistant --timeout=120s >/dev/null 2>&1; settle 4
  expect "the ServiceEntry gets a virtual IP" "$("${K[@]}" -n shop get serviceentry ollama -o jsonpath='{.status.addresses[0].value}')" '^240\.240\.'
  local trace_id; trace_id="$(ask 'Which item was ordered most?' | python3 -c 'import json,sys; print(json.load(sys.stdin).get("trace_id",""))' 2>/dev/null)"
  settle 2
  expect "model calls now go through the waypoint, by name" "$("${K[@]}" -n istio-system logs ds/ztunnel --since=1m | grep 'src.workload="assistant' | grep -c 'dst.service="host.docker.internal".*dst.workload="waypoint')" '^[1-9]'
  "${K[@]}" apply -f "$M/17-ollama-policy.yaml" >/dev/null; settle 6
  expect "other workloads may not list Ollama's models (403)" "$(in_shop curl -s -o /dev/null -m 20 -w '%{http_code}' http://host.docker.internal:11434/api/tags)" '^403$'
  expect "nor delete one (403, before it reaches Ollama)" "$(in_shop curl -s -o /dev/null -m 20 -w '%{http_code}' -X DELETE -d '{"model":"lab-model-that-does-not-exist"}' http://host.docker.internal:11434/api/delete)" '^403$'
  expect "the assistant still gets answers" "$(ask 'How many orders are there?' | grep -c '"answer"')" '^1$'
  settle 10
  expect "Jaeger shows the model call with its token counts" "$("${K[@]}" get --raw "/api/v1/namespaces/observability/services/jaeger-query:16686/proxy/api/traces/${trace_id}" 2>/dev/null | grep -c 'gen_ai.usage.output_tokens')" '^[1-9]'
  "${K[@]}" apply -f "$M/17-llm-timeout.yaml" >/dev/null; settle 8
  expect "a 100 ms route timeout cuts the model call off (504)" "$(ask 'How many orders are there?')" '504 Gateway Timeout'
  baseline
  expect "after the reset the assistant is gone" "$("${K[@]}" -n shop get deploy assistant 2>&1 | grep -c NotFound)" '^1$'
}

# Modules 17 and 18 are not in the default run: 17 needs Ollama on your machine, and
# 18 downloads about 900 MB of models. Run them with: ./platform-engineering/verify.sh 17 18
module_18() {
  section "18: serving models inside the cluster"
  baseline
  local prom='/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query'
  "${K[@]}" apply -f "$M/18-namespace.yaml" >/dev/null && "${K[@]}" apply -f "$M/18-llm-qwen.yaml" -f "$M/03-course-client.yaml" >/dev/null
  expect "two Qwen model servers download the model and become ready" "$("${K[@]}" -n ai rollout status deploy/llm-qwen --timeout=600s 2>&1 | tail -1)" 'successfully rolled out'
  "${K[@]}" -n shop rollout status deploy/course-client --timeout=120s >/dev/null 2>&1; settle 5
  expect "Qwen answers through the mesh" "$(in_shop curl -s -m 60 http://llm-qwen.ai.svc.cluster.local:8080/v1/chat/completions -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"Say hi."}],"max_tokens":5}' | grep -o '"model":"[^"]*"')" 'qwen2.5-0.5b'
  local l4 l7=0 n
  l4="$("$ROOT/platform-engineering/llm-load.sh" | sed -n 's/.*it (over 2 s): \([0-9]*\) of 10/\1/p')"
  between "with ztunnel alone, short questions get stuck behind a long one" "${l4:-0}" 2 10
  "${K[@]}" apply -f "$M/18-waypoint.yaml" >/dev/null
  "${K[@]}" label ns ai istio.io/use-waypoint=waypoint --overwrite >/dev/null
  "${K[@]}" -n ai wait --for=condition=Programmed gateway/waypoint --timeout=120s >/dev/null 2>&1; settle 10
  for _ in 1 2 3; do n="$("$ROOT/platform-engineering/llm-load.sh" | sed -n 's/.*it (over 2 s): \([0-9]*\) of 10/\1/p')"; l7=$(( l7 + ${n:-10} )); done
  between "with the waypoint's least-request balancing, fewer get stuck (3 runs, out of 30)" "$l7" 0 12
  settle 20
  expect "Prometheus collects the model servers' token counts" "$("${K[@]}" get --raw "${prom}?query=sum(llamacpp%3Atokens_predicted_total)" | grep -c '"value"')" '^1$'
  "${K[@]}" apply -f "$M/18-llm-smol.yaml" >/dev/null
  "${K[@]}" -n ai rollout status deploy/llm-smol --timeout=600s >/dev/null 2>&1
  "${K[@]}" apply -f "$M/18-route-by-model.yaml" >/dev/null; settle 10
  local llm='http://llm.ai.svc.cluster.local:8080/v1/chat/completions'
  expect "the header x-model: smollm2 picks the second model" "$(in_shop curl -s -m 60 "$llm" -H 'Content-Type: application/json' -H 'x-model: smollm2' -d '{"messages":[{"role":"user","content":"Name a colour."}],"max_tokens":5}' | grep -o '"model":"[^"]*"')" 'smollm2-360m'
  expect "a model named only in the JSON body is ignored by the route" "$(in_shop curl -s -m 60 "$llm" -H 'Content-Type: application/json' -d '{"model":"smollm2-360m","messages":[{"role":"user","content":"Name a colour."}],"max_tokens":5}' | grep -o '"model":"[^"]*"')" 'qwen2.5-0.5b'
  baseline
  expect "after the reset the ai namespace is gone" "$("${K[@]}" get ns ai 2>&1 | grep -c NotFound)" '^1$'
}

# Module 19 also needs Ollama on your machine, and installs kagent: ./platform-engineering/verify.sh 19
module_19() {
  section "19: AI agents and their tools"
  baseline
  local model H=(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n kagent)
  model="${LAB_OLLAMA_MODEL:-$(curl -s -m 5 $OLLAMA/api/tags | python3 -c 'import json,sys; m=json.load(sys.stdin)["models"]; c=[x["name"] for x in m if "embed" not in x["name"]]; print(c[0] if c else "")' 2>/dev/null)}"
  if [[ -z "$model" ]]; then fail "Ollama runs on this machine with at least one model" "no answer from $OLLAMA/api/tags"; return; fi
  "${H[@]}" upgrade --install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds --version 0.10.6 --create-namespace --wait >/dev/null 2>&1
  "${H[@]}" upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent --version 0.10.6 \
    -f "$M/19-kagent-values.yaml" --set providers.ollama.model="$model" --wait --timeout 10m >/dev/null 2>&1
  "${K[@]}" apply -f "$M/03-course-client.yaml" -f "$M/19-agent-target.yaml" >/dev/null
  "${K[@]}" -n shop rollout status deploy/course-client --timeout=120s >/dev/null 2>&1
  "${K[@]}" -n kagent wait --for=condition=Ready agent/k8s-agent --timeout=180s >/dev/null 2>&1
  local accepted=False
  for _ in $(seq 1 12); do
    "${K[@]}" -n kagent annotate remotemcpserver kagent-tool-server lab/retry="$(date +%s)" --overwrite >/dev/null 2>&1; settle 5
    accepted="$("${K[@]}" -n kagent get remotemcpserver kagent-tool-server -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}')"
    [[ "$accepted" == True ]] && break
  done
  expect "kagent runs, and its agents found their tools" "$accepted" '^True$'
  agent() {
    in_shop curl -s -m 300 -X POST http://kagent-controller.kagent:8083/api/a2a/kagent/k8s-agent/ -H 'Content-Type: application/json' \
      -d "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"message/send\",\"params\":{\"message\":{\"role\":\"user\",\"messageId\":\"$RANDOM$RANDOM\",\"parts\":[{\"kind\":\"text\",\"text\":\"$1\"}]}}}"
  }
  expect "the agent answers by calling a Kubernetes tool" "$(agent 'How many pods run in the namespace course-agent? One sentence.' | grep -o '"name":"k8s_get_resources"' | head -1)" 'k8s_get_resources'
  local mcp; mcp="$(cat "$ROOT/platform-engineering/mcp-call.sh")"
  expect "before the policy, any pod lists every Secret through the tool server" "$(in_shop sh -c "$mcp" | grep -c 'lab-root-ca')" '^[1-9]'
  "${K[@]}" label ns kagent istio.io/dataplane-mode=ambient --overwrite >/dev/null
  # Enrolling breaks connections that were open before (the controller's database pool), so restart.
  "${K[@]}" -n kagent rollout restart deploy >/dev/null
  for d in $("${K[@]}" -n kagent get deploy -o name); do "${K[@]}" -n kagent rollout status "$d" --timeout=180s >/dev/null 2>&1; done
  "${K[@]}" apply -f "$M/19-tools-policy.yaml" >/dev/null; settle 15
  expect "with the policy, that pod gets no session at all" "$(in_shop sh -c "$mcp" | grep -c 'lab-root-ca')" '^0$'
  expect "the agent still uses its tools" "$(agent 'List the pods in the namespace course-agent. One line.' | grep -o '"name":"k8s_get_resources"' | head -1)" 'k8s_get_resources'
  agent 'Delete the pod agent-target in the namespace course-agent with the k8s_delete_resource tool. Call the tool once. If it fails, do not retry: quote the error message.' >/dev/null
  settle 3
  expect "with cluster-admin rights, the agent deletes the pod" "$("${K[@]}" -n course-agent get pod agent-target 2>&1 | grep -c NotFound)" '^1$'
  "${K[@]}" apply -f "$M/19-agent-target.yaml" >/dev/null
  "${K[@]}" -n course-agent wait --for=condition=Ready pod/agent-target --timeout=90s >/dev/null 2>&1
  "${K[@]}" delete clusterrolebinding kagent-tools-cluster-admin-rolebinding --ignore-not-found >/dev/null
  "${K[@]}" apply -f "$M/19-tools-read-only.yaml" >/dev/null; settle 3
  agent 'Delete the pod agent-target in the namespace course-agent with the k8s_delete_resource tool. Call the tool once. If it fails, do not retry: quote the error message.' >/dev/null
  settle 3
  expect "with the view role, the same request leaves the pod alone" "$("${K[@]}" -n course-agent get pod agent-target --no-headers 2>&1 | awk '{print $3}')" '^Running$'
  baseline
  expect "after the reset kagent is gone" "$("${K[@]}" get ns kagent 2>&1 | grep -c NotFound)" '^1$'
}

module_20() {
  section "20: nodes, drains and cleanup"
  baseline
  local node=k3d-agent-0 log="${TMPDIR:-/tmp}/k8s-lab-drain.log"
  k3d node create agent --cluster "${CLUSTER_NAME:-k8s-lab}" --role agent --wait >/dev/null 2>&1
  "${K[@]}" wait --for=condition=Ready "node/$node" --timeout=120s >/dev/null 2>&1
  k3d image import "k8s-lab/backend:1.0.3" "k8s-lab/frontend:1.0.3" "k8s-lab/assistant:1.1.0" -c "${CLUSTER_NAME:-k8s-lab}" >/dev/null 2>&1
  "${K[@]}" -n istio-system rollout status ds/ztunnel --timeout=180s >/dev/null 2>&1
  expect "a second node joins, and ztunnel starts on it" "$("${K[@]}" -n istio-system get pods -l app=ztunnel --field-selector spec.nodeName=$node -o jsonpath='{.items[0].status.phase}')" '^Running$'
  "${K[@]}" apply -f "$M/20-ops-app.yaml" -f "$M/03-course-client.yaml" >/dev/null
  "${K[@]}" -n course-ops rollout status deploy/web --timeout=180s >/dev/null 2>&1
  "${K[@]}" -n shop rollout status deploy/course-client --timeout=120s >/dev/null 2>&1; settle 5
  expect "the two web replicas land on different nodes" "$("${K[@]}" -n course-ops get pods -l app=web -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' | sort -u | wc -l | tr -d ' ')" '^2$'
  expect "traffic crosses nodes through the mesh" "$(in_shop sh -c 'for i in $(seq 1 20); do curl -s -o /dev/null -w "%{http_code}\n" http://web.course-ops:8000/status/200; done' | grep -c 200)" '^20$'
  "${K[@]}" apply -f "$M/20-pdb.yaml" >/dev/null
  in_shop sh -c 'end=$(( $(date +%s)+40 )); while [ $(date +%s) -lt $end ]; do curl -s -o /dev/null -m 3 -w "%{http_code}\n" http://web.course-ops:8000/status/200; sleep 0.1; done' > "$log" &
  local loader=$!
  settle 5
  "${K[@]}" drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=120s >/dev/null 2>&1
  wait "$loader" 2>/dev/null
  between "a drain with a PodDisruptionBudget fails no requests ($(wc -l < "$log" | tr -d ' ') sent)" "$(grep -vc '^200$' "$log" || true)" 0 2
  "${K[@]}" uncordon "$node" >/dev/null
  "${K[@]}" -n course-ops rollout restart deploy/web >/dev/null
  "${K[@]}" -n course-ops rollout status deploy/web --timeout=120s >/dev/null 2>&1; settle 5
  "${K[@]}" apply -f "$M/20-pdb-too-strict.yaml" >/dev/null
  if [[ -n "$("${K[@]}" -n course-ops get pods -l app=web --field-selector spec.nodeName=$node -o name)" ]]; then
    expect "a budget that can never be met blocks the drain" "$("${K[@]}" drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=20s 2>&1 | grep -c "violate the pod's disruption budget")" '^[1-9]'
  else
    pass "a budget that can never be met blocks the drain (skipped: no web pod on $node this time)"
  fi
  "${K[@]}" apply -f "$M/20-pdb.yaml" >/dev/null
  "${K[@]}" apply -f "$M/20-job-ttl.yaml" >/dev/null
  "${K[@]}" -n course-ops wait --for=condition=Complete job/nightly-report --timeout=60s >/dev/null 2>&1; settle 40
  expect "a finished Job with ttlSecondsAfterFinished deletes itself" "$("${K[@]}" -n course-ops get job nightly-report 2>&1 | grep -c NotFound)" '^1$'
  local before; before="$(docker exec "$node" crictl images -q 2>/dev/null | wc -l | tr -d ' ')"
  docker exec "$node" crictl rmi --prune >/dev/null 2>&1
  between "pruning removes images no container uses ($before before)" "$(docker exec "$node" crictl images -q 2>/dev/null | wc -l | tr -d ' ')" 0 "$(( before - 1 ))"
  "${K[@]}" drain "$node" --ignore-daemonsets --delete-emptydir-data --timeout=120s >/dev/null 2>&1
  k3d node delete "$node" >/dev/null 2>&1
  expect "after k3d deletes the node, Kubernetes still lists it" "$("${K[@]}" get node "$node" --no-headers 2>&1 | grep -c "$node")" '^1$'
  "${K[@]}" delete node "$node" >/dev/null
  expect "kubectl delete node removes it" "$("${K[@]}" get nodes --no-headers | wc -l | tr -d ' ')" '^1$'
  baseline
  expect "after the reset course-ops is gone" "$("${K[@]}" get ns course-ops 2>&1 | grep -c NotFound)" '^1$'
  rm -f "$log"
}

module_22() {
  section "22: GitOps with ArgoCD"
  baseline
  local work="${TMPDIR:-/tmp}/k8s-lab-gitops" port=3011 pf
  app() { "${K[@]}" -n argocd get app "$1" -o jsonpath="$2" 2>/dev/null; }
  refresh() { "${K[@]}" -n argocd annotate app "$1" argocd.argoproj.io/refresh=normal --overwrite >/dev/null 2>&1; }
  # wait_app <app> <jsonpath> <regex> <seconds>: poll until the value matches, print it
  wait_app() { local v i; for ((i = 0; i < $4; i += 2)); do v="$(app "$1" "$2")"; [[ "$v" =~ $3 ]] && break; sleep 2; done; printf '%s' "$v"; }
  g() { git -C "$work" -c user.name=lab -c user.email=lab@example.invalid "$@" >/dev/null 2>&1; }
  push() { g push "http://lab:lab-gitops-pass@localhost:$port/lab/podinfo-gitops.git" main; refresh podinfo-dev; }
  "${K[@]}" apply -f "$M/22-gitea.yaml" >/dev/null
  "${K[@]}" -n course-gitops rollout status deploy/gitea --timeout=180s >/dev/null 2>&1
  "${K[@]}" -n course-gitops exec deploy/gitea -- gitea admin user create --username lab --password lab-gitops-pass \
    --email lab@example.invalid --admin --must-change-password=false >/dev/null 2>&1
  "${K[@]}" -n course-gitops port-forward svc/gitea "$port:3000" >/dev/null 2>&1 &
  pf=$!; settle 3
  rm -rf "$work"; cp -R "$ROOT/platform-engineering/gitops-repo" "$work"
  git -C "$work" init -q -b main; g add .; g commit -m "podinfo, dev and prod"
  expect "a push creates the repository in Gitea" "$(push; curl -s "localhost:$port/api/v1/repos/lab/podinfo-gitops" | grep -o '"private":false')" '^"private":false$'
  "${K[@]}" apply -f "$M/22-project.yaml" -f "$M/22-app-dev.yaml" >/dev/null 2>&1
  expect "ArgoCD deploys the dev app from Gitea" "$(wait_app podinfo-dev '{.status.sync.status} {.status.health.status}' '^Synced Healthy$' 90)" '^Synced Healthy$'
  "${K[@]}" -n course-gitops-dev scale deploy/podinfo --replicas=3 >/dev/null; settle 15
  expect "without selfHeal, drift shows as OutOfSync and stays" "$(app podinfo-dev '{.status.sync.status}') $("${K[@]}" -n course-gitops-dev get deploy podinfo -o jsonpath='{.spec.replicas}')" '^OutOfSync 3$'
  "${K[@]}" -n argocd patch app podinfo-dev --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}' >/dev/null; settle 10
  expect "with selfHeal, ArgoCD undoes the kubectl scale" "$("${K[@]}" -n course-gitops-dev get deploy podinfo -o jsonpath='{.spec.replicas}')" '^1$'
  sed -i.bak 's/hello from git/hello from commit 2/' "$work/base/deployment.yaml"; rm -f "$work/base/deployment.yaml.bak"
  g commit -am "new message"; push; settle 5
  "${K[@]}" -n course-gitops-dev rollout status deploy/podinfo --timeout=90s >/dev/null 2>&1
  expect "a pushed commit reaches the pod" "$("${K[@]}" -n course-gitops-dev exec deploy/podinfo -- wget -qO- localhost:9898 2>/dev/null | grep -o 'hello from commit 2')" '^hello from commit 2$'
  sed -i.bak 's/podinfo:6.7.1/podinfo:6.7.99/' "$work/base/deployment.yaml"; rm -f "$work/base/deployment.yaml.bak"
  g commit -am "bump podinfo"; push
  expect "a broken image tag is Synced and Degraded at once" "$(wait_app podinfo-dev '{.status.sync.status} {.status.health.status}' '^Synced Degraded$' 120)" '^Synced Degraded$'
  g revert --no-edit HEAD; push
  expect "git revert brings the app back" "$(wait_app podinfo-dev '{.status.sync.status} {.status.health.status}' '^Synced Healthy$' 60)" '^Synced Healthy$'
  cp "$ROOT/platform-engineering/gitops-extras/migrate-job.yaml" "$ROOT/platform-engineering/gitops-extras/config-wave.yaml" "$work/base/"
  printf '  - migrate-job.yaml\n  - config-wave.yaml\n' >> "$work/base/kustomization.yaml"
  g add .; g commit -m "migration hook and settings"; push
  # Wait for this commit's sync, not the last one's "Succeeded".
  local head; head="$(git -C "$work" rev-parse HEAD)"
  wait_app podinfo-dev '{.status.operationState.operation.sync.revision} {.status.operationState.phase}' "^$head Succeeded$" 90 >/dev/null
  expect "the PreSync hook ran before the sync" "$("${K[@]}" -n course-gitops-dev logs job/migrate 2>/dev/null | head -1)" '^migrating the schema$'
  expect "the wave -1 ConfigMap exists" "$("${K[@]}" -n course-gitops-dev get cm podinfo-settings -o jsonpath='{.data.feature}' 2>/dev/null)" '^orders-v2$'
  cp "$ROOT/platform-engineering/gitops-extras/sneaky-clusterrole.yaml" "$work/base/"
  printf '  - sneaky-clusterrole.yaml\n' >> "$work/base/kustomization.yaml"
  g add .; g commit -m "let podinfo read everything"; push; settle 10
  expect "the project refuses a ClusterRole" "$(app podinfo-dev '{.status.operationState.syncResult.resources[?(@.kind=="ClusterRole")].message}')" 'not permitted in project team-shop'
  expect "and nothing created it" "$("${K[@]}" get clusterrole podinfo-reads-everything 2>&1 | grep -c NotFound)" '^1$'
  g revert --no-edit HEAD; push
  "${K[@]}" -n argocd patch app podinfo-dev --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}' >/dev/null 2>&1
  expect "terminating the retries lets the revert through" "$(wait_app podinfo-dev '{.status.sync.status} {.status.health.status}' '^Synced Healthy$' 60)" '^Synced Healthy$'
  "${K[@]}" -n argocd delete app podinfo-dev --wait=true --timeout=90s >/dev/null 2>&1
  expect "deleting the Application deletes what it deployed" "$("${K[@]}" -n course-gitops-dev get deploy podinfo 2>&1 | grep -c NotFound)" '^1$'
  "${K[@]}" apply -f "$M/22-appset.yaml" >/dev/null
  wait_app podinfo-prod '{.status.health.status}' '^Healthy$' 90 >/dev/null
  expect "the ApplicationSet deploys dev with 1 replica and prod with 2" "$("${K[@]}" -n course-gitops-dev get deploy podinfo -o jsonpath='{.status.readyReplicas}' 2>/dev/null) $("${K[@]}" -n course-gitops-prod get deploy podinfo -o jsonpath='{.status.readyReplicas}' 2>/dev/null)" '^1 2$'
  "${K[@]}" -n argocd delete app podinfo-prod --wait=true --timeout=90s >/dev/null 2>&1
  expect "the ApplicationSet recreates a deleted Application" "$(wait_app podinfo-prod '{.status.health.status}' '^Healthy$' 90)" '^Healthy$'
  kill "$pf" 2>/dev/null; wait "$pf" 2>/dev/null; rm -rf "$work"
  baseline
  expect "after the reset the course-gitops namespaces and project are gone" "$("${K[@]}" get ns course-gitops course-gitops-dev course-gitops-prod 2>&1 | grep -c NotFound) $("${K[@]}" -n argocd get appproject team-shop 2>&1 | grep -c NotFound)" '^3 1$'
}

module_23() {
  section "23: Prometheus and alerting"
  baseline
  local port=9092 pf loader
  "${K[@]}" -n observability port-forward svc/kube-prometheus-stack-prometheus "$port:9090" >/dev/null 2>&1 &
  pf=$!; settle 3
  # prom <query>: the first result's value, or nothing
  prom() { curl -s "localhost:$port/api/v1/query" --data-urlencode "query=$1" | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null; }
  alert_state() { curl -s "localhost:$port/api/v1/alerts" | python3 -c 'import json,sys; a=[x for x in json.load(sys.stdin)["data"]["alerts"] if x["labels"]["alertname"]=="ShopBackendErrorBudgetBurn"]; print(a[0]["state"] if a else "none")' 2>/dev/null; }
  # poll <seconds> <command...>: run the command every 5 s until it succeeds
  poll() { local t=$1 i; shift; for ((i = 0; i < t; i += 5)); do "$@" && return 0; sleep 5; done; return 1; }
  expect "Prometheus sends alerts to Alertmanager" "$(curl -s "localhost:$port/api/v1/alertmanagers" | grep -o '"activeAlertmanagers":\[{"url":"http://[0-9.]*:9093' | grep -c 9093)" '^1$'
  "${K[@]}" apply -f "$M/23-alert-receiver.yaml" -f "$M/23-shop-slo.yaml" >/dev/null
  "${K[@]}" -n course-alerts rollout status deploy/alert-receiver --timeout=120s >/dev/null 2>&1
  rules_loaded() { [[ "$(curl -s "localhost:$port/api/v1/rules" | grep -o '"name":"shop-slo-[a-z]*"' | sort -u | wc -l | tr -d ' ')" == 2 ]]; }
  poll 150 rules_loaded
  expect "Prometheus loads both SLO rule groups" "$(curl -s "localhost:$port/api/v1/rules" | grep -o '"name":"shop-slo-[a-z]*"' | sort -u | wc -l | tr -d ' ')" '^2$'
  route_merged() { "${K[@]}" -n observability exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- cat /etc/alertmanager/config_out/alertmanager.env.yaml 2>/dev/null | grep -q 'course-alerts/shop-pager/pager'; }
  poll 150 route_merged
  expect "Alertmanager merges the team's route" "$(route_merged && echo merged)" '^merged$'
  "${K[@]}" apply -f "$M/15-faulty-pod.yaml" >/dev/null
  "${K[@]}" -n shop rollout status deploy/backend-v1-faulty --timeout=120s >/dev/null 2>&1
  "$ROOT/platform-engineering/load.sh" 420 /api/orders 5 >/dev/null 2>&1 &
  loader=$!; disown "$loader"
  firing() { [[ "$(alert_state)" == firing ]]; }
  poll 240 firing
  between "with one broken pod of three, the 5m error ratio in percent" "$(prom 'shop:backend_error_ratio:rate5m' | awk '{printf "%d", $1 * 100}')" 15 60
  expect "the burn-rate alert fires" "$(alert_state)" '^firing$'
  delivered() { "${K[@]}" -n course-alerts logs deploy/alert-receiver 2>/dev/null | grep -q '"status":"firing"'; }
  poll 60 delivered
  expect "the receiver gets the page" "$("${K[@]}" -n course-alerts logs deploy/alert-receiver 2>/dev/null | grep -o '"alertname":"ShopBackendErrorBudgetBurn"' | head -1)" 'ShopBackendErrorBudgetBurn'
  "${K[@]}" -n shop delete deployment backend-v1-faulty >/dev/null
  cleared() { [[ "$(alert_state)" == none ]]; }
  poll 150 cleared
  expect "the alert clears while the 5m ratio is still above the threshold" "$(alert_state) $(prom 'shop:backend_error_ratio:rate5m > 0.144' | grep -c .)" '^none 1$'
  resolved() { "${K[@]}" -n course-alerts logs deploy/alert-receiver 2>/dev/null | grep -q '"status":"resolved"'; }
  poll 90 resolved
  expect "the receiver gets the resolved message" "$("${K[@]}" -n course-alerts logs deploy/alert-receiver 2>/dev/null | grep -c '"status":"resolved"')" '^[1-9]'
  kill "$loader" 2>/dev/null; pkill -f "platform-engineering/load.sh" 2>/dev/null
  between "Prometheus holds many series in total (thousands)" "$(prom 'count({__name__=~".+"})' | awk '{printf "%d", $1 / 1000}')" 10 1000
  expect "the API server's histogram is the biggest metric" "$(curl -s "localhost:$port/api/v1/query" --data-urlencode 'query=topk(1, count by (__name__) ({__name__=~".+"}))' | grep -o '"__name__":"[a-z_]*"')" 'apiserver_'
  kill "$pf" 2>/dev/null; wait "$pf" 2>/dev/null
  baseline
  expect "after the reset course-alerts is gone" "$("${K[@]}" get ns course-alerts 2>&1 | grep -c NotFound)" '^1$'
}

module_24() {
  section "24: Grafana as code"
  baseline
  local gport=3998 pport=9094 pf1 pf2 pw S="${TMPDIR:-/tmp}"
  pw="$("${K[@]}" -n observability get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d)"
  "${K[@]}" -n observability port-forward svc/kube-prometheus-stack-grafana "$gport:80" >/dev/null 2>&1 &
  pf1=$!
  "${K[@]}" -n observability port-forward svc/kube-prometheus-stack-prometheus "$pport:9090" >/dev/null 2>&1 &
  pf2=$!; settle 3
  gf() { curl -s -u "admin:$pw" "$@"; }
  prom() { curl -s "localhost:$pport/api/v1/query" --data-urlencode "query=$1" | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null; }
  poll() { local t=$1 i; shift; for ((i = 0; i < t; i += 5)); do "$@" && return 0; sleep 5; done; return 1; }
  "${K[@]}" apply -f "$M/24-slo-dashboard.yaml" >/dev/null
  loaded() { gf "localhost:$gport/api/dashboards/uid/shop-slo" | grep -q '"provisioned":true'; }
  poll 60 loaded
  expect "the sidecar loads the dashboard from its ConfigMap" "$(gf "localhost:$gport/api/dashboards/uid/shop-slo" | grep -o '"title":"Shop SLO"' | head -1)" '^"title":"Shop SLO"$'
  gf "localhost:$gport/api/dashboards/uid/shop-slo" | python3 -c 'import json,sys; d=json.load(sys.stdin)["dashboard"]; d["title"]="edited"; print(json.dumps({"dashboard":d,"overwrite":True}))' > "$S/k8s-lab-dash.json"
  expect "Grafana refuses to save over a provisioned dashboard" "$(gf -H 'Content-Type: application/json' -X POST "localhost:$gport/api/dashboards/db" -d @"$S/k8s-lab-dash.json")" 'Cannot save provisioned dashboard'
  rm -f "$S/k8s-lab-dash.json"
  # The panel queries, with $service=backend and $window=5m
  local sel='reporter="waypoint", destination_service_namespace="shop", destination_canonical_service="backend"'
  "$ROOT/platform-engineering/load.sh" 120 /api/orders 5 >/dev/null 2>&1 &
  local loader=$!; disown "$loader"; settle 70
  # Built in a variable: bash 3.2 (macOS) mis-parses escaped quotes inside "$( ... )".
  local errsel="$sel, response_code=~\"5..\"" avail
  # $window=1m: right after module 23, the 5m window still holds its faulty pod's errors.
  avail="1 - (sum(rate(istio_requests_total{$errsel}[1m])) or vector(0)) / sum(rate(istio_requests_total{$sel}[1m]))"
  between "the availability panel reads close to 100% over 1m (percent)" "$(prom "$avail" | awk '{printf "%d", $1 * 100}')" 95 100
  between "the requests-per-second panel sees the load (x10)" "$(prom "sum(rate(istio_requests_total{$sel}[5m]))" | awk '{printf "%d", $1 * 10}')" 10 80
  expect "the p95 panel returns a latency" "$(prom "histogram_quantile(0.95, sum by (le) (rate(istio_request_duration_milliseconds_bucket{$sel}[5m])))")" '^[0-9.]+$'
  expect "the service variable lists the backend" "$(curl -s -G "localhost:$pport/api/v1/label/destination_canonical_service/values" --data-urlencode 'match[]=istio_requests_total{reporter="waypoint", destination_service_namespace="shop", destination_canonical_service!="unknown"}' | grep -o '"backend"')" '^"backend"$'
  gf -H 'Content-Type: application/json' -X POST "localhost:$gport/api/folders" -d '{"uid":"course","title":"Course"}' >/dev/null
  expect "the Grafana-managed rule is accepted" "$(gf -H 'Content-Type: application/json' -X POST "localhost:$gport/api/v1/provisioning/alert-rules" -d @"$M/24-grafana-rule.json" | grep -o '"uid":"shop-burn-grafana"')" 'shop-burn-grafana'
  evaluated() { gf "localhost:$gport/api/prometheus/grafana/api/v1/rules" | grep -q '"health":"ok"'; }
  poll 90 evaluated
  expect "Grafana evaluates it" "$(gf "localhost:$gport/api/prometheus/grafana/api/v1/rules" | grep -o '"health":"ok"' | head -1)" '"health":"ok"'
  expect "its default contact point is a placeholder email" "$(gf "localhost:$gport/api/v1/provisioning/contact-points" | grep -o 'example@email.com' | head -1)" '^example@email.com$'
  local tid=""
  for _ in 1 2 3 4 5 6; do
    curl -s -o /dev/null "$BASE/api/orders"; settle 10
    tid="$(gf "localhost:$gport/api/datasources/proxy/uid/jaeger/api/traces?service=backend&limit=1&lookback=5m" | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; print(d[0]["traceID"] if d else "")' 2>/dev/null)"
    [[ -n "$tid" ]] && break
  done
  # loki_hits: how many log lines carry this trace id. Loki needs some seconds to ingest.
  local logq="{namespace=\"shop\"} |= \"$tid\"" hits=0
  loki_hits() { local now; now="$(date +%s)"; gf -G "localhost:$gport/api/datasources/proxy/uid/loki/loki/api/v1/query_range" --data-urlencode "query=$logq" --data-urlencode "start=$((now - 600))000000000" --data-urlencode "end=${now}000000000" | grep -c "$tid"; }
  for _ in 1 2 3 4 5 6 7 8; do hits="$(loki_hits)"; [[ "$hits" != 0 ]] && break; sleep 5; done
  expect "a Jaeger trace id finds its log line in Loki" "$hits" '^[1-9]'
  expect "the trace-to-logs link in Grafana keeps its variable" "$(gf "localhost:$gport/api/datasources/uid/jaeger" | grep -o '__trace.traceId' | head -1)" '^__trace.traceId$'
  kill "$loader" 2>/dev/null; pkill -f "platform-engineering/load.sh" 2>/dev/null
  baseline
  expect "after the reset the dashboard and the Grafana rule are gone" "$(gf "localhost:$gport/api/dashboards/uid/shop-slo" | grep -c 'not found') $(gf "localhost:$gport/api/v1/provisioning/alert-rules/shop-burn-grafana" -o /dev/null -w '%{http_code}')" '^1 404$'
  kill "$pf1" "$pf2" 2>/dev/null; wait "$pf1" "$pf2" 2>/dev/null
}

module_25() {
  section "25: OpenTelemetry Collector and Tempo"
  baseline
  local H=(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}")
  local tempo="/api/v1/namespaces/course-otel/services/tempo:3200/proxy"
  "${H[@]}" repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1
  "${H[@]}" repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts >/dev/null 2>&1
  "${H[@]}" repo update grafana open-telemetry >/dev/null 2>&1
  expect "Tempo installs" "$("${H[@]}" install tempo grafana/tempo --version 1.24.4 -n course-otel --create-namespace -f "$M/25-tempo-values.yaml" --wait --timeout 5m 2>&1 | grep -c 'STATUS: deployed')" '^1$'
  expect "the Collector installs without deprecation warnings" "$("${H[@]}" install otel-collector open-telemetry/opentelemetry-collector --version 0.178.0 -n course-otel -f "$M/25-collector-values.yaml" --wait --timeout 5m 2>&1 | grep -cE 'STATUS: deployed|DEPRECATION')" '^1$'
  # The back ends first, then the app: an app that starts before its Collector backs off.
  "${K[@]}" apply -f "$M/25-orders-app.yaml" >/dev/null
  "${K[@]}" apply -f "$M/25-collector-podmonitor.yaml" -f "$M/25-tempo-datasource.yaml" >/dev/null
  "${K[@]}" -n course-otel rollout status deploy/orders --timeout=120s >/dev/null 2>&1
  # tql <TraceQL>: how many traces from the last 10 minutes match
  tql() { local q; q="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))' "$1")"
    "${K[@]}" get --raw "$tempo/api/search?limit=20&start=$(( $(date +%s) - 600 ))&end=$(date +%s)&q=$q" 2>/dev/null | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("traces",[])))' 2>/dev/null || echo 0; }
  local n=0
  for _ in $(seq 1 48); do n="$(tql '{ resource.service.name = "orders" }')"; [[ "$n" =~ ^[1-9] ]] && break; settle 5; done
  expect "Tempo receives traces, renamed to orders by the Collector" "$n" '^[1-9]'
  local ns_tag=""
  for _ in $(seq 1 24); do ns_tag="$("${K[@]}" get --raw "$tempo/api/search/tag/k8s.namespace.name/values" 2>/dev/null | grep -o '"course-otel"')"; [[ -n "$ns_tag" ]] && break; settle 5; done
  expect "the Collector added Kubernetes attributes" "$ns_tag" '^"course-otel"$'
  # 5% of requests fail, so the first 503 takes a moment
  for _ in $(seq 1 36); do n="$(tql '{ resource.service.name = "orders" && span.http.status_code >= 500 }')"; [[ "$n" =~ ^[1-9] ]] && break; settle 5; done
  expect "TraceQL finds failed requests" "$n" '^[1-9]'
  expect "TraceQL finds slow requests" "$(tql '{ resource.service.name = "orders" && duration > 400ms }')" '^[1-9]'
  expect "a structural query finds requests that called Redis" "$(tql '{ resource.service.name = "orders" } >> { span.db.system = "redis" }')" '^[1-9]'
  expect "Tempo survived the structural query" "$("${K[@]}" -n course-otel get pod tempo-0 -o jsonpath='{.status.containerStatuses[0].restartCount}')" '^0$'
  expect "the same traces reach Jaeger" "$("${K[@]}" get --raw '/api/v1/namespaces/observability/services/jaeger-query:16686/proxy/api/services' 2>/dev/null | grep -o '"orders"')" '^"orders"$'
  local rate=""
  # A new PodMonitor reaches Prometheus through a Secret update: allow up to 6 minutes.
  for _ in $(seq 1 36); do
    rate="$("${K[@]}" get --raw '/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=sum%28rate%28traces_span_metrics_calls_total%7Bservice_name%3D%22orders%22%2Chttp_status_code%3D%22503%22%7D%5B2m%5D%29%29' 2>/dev/null | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null)"
    [[ "$rate" =~ ^0\.0*[1-9] || "$rate" =~ ^[1-9] ]] && break; settle 10
  done
  expect "span metrics in Prometheus count the 503s" "$rate" '^(0\.0*[1-9]|[1-9])'
  expect "Grafana has the Tempo data source" "$("${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- sh -c 'curl -s -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" localhost:3000/api/datasources/uid/tempo' 2>/dev/null | grep -o '"type":"tempo"')" '^"type":"tempo"$'
  baseline
  expect "after the reset course-otel, its ClusterRole and the data source are gone" "$("${K[@]}" get ns course-otel 2>&1 | grep -c NotFound) $("${K[@]}" get clusterrole otel-collector 2>&1 | grep -c NotFound) $("${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- sh -c 'curl -s -o /dev/null -w "%{http_code}" -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" localhost:3000/api/datasources/uid/tempo' 2>/dev/null)" '^1 1 404$'
}

module_26() {
  section "26: Kyverno, policy as code"
  baseline
  local H=(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}")
  "${H[@]}" repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1
  "${H[@]}" repo update kyverno >/dev/null 2>&1
  expect "Kyverno installs" "$("${H[@]}" install kyverno kyverno/kyverno --version 3.8.2 -n kyverno --create-namespace -f "$M/26-kyverno-values.yaml" --wait --timeout 6m 2>&1 | grep -c 'STATUS: deployed')" '^1$'
  "${K[@]}" apply -f "$M/26-namespace.yaml" -f "$M/26-legacy-app.yaml" >/dev/null
  "${K[@]}" -n course-policy rollout status deploy/legacy --timeout=120s >/dev/null 2>&1
  "${K[@]}" apply -f "$M/26-require-limits.yaml" >/dev/null
  report_fails() { "${K[@]}" -n course-policy get policyreport -o jsonpath='{range .items[*].results[?(@.result=="fail")]}{.policy}{"\n"}{end}' 2>/dev/null | grep -c "$1"; }
  for _ in $(seq 1 24); do [[ "$(report_fails require-memory-limits)" =~ ^[1-9] ]] && break; settle 5; done
  expect "Audit reports the legacy app without blocking it" "$(report_fails require-memory-limits) $("${K[@]}" -n course-policy get deploy legacy -o jsonpath='{.status.readyReplicas}')" '^[1-9][0-9]* 1$'
  "${K[@]}" apply -f "$M/26-disallow-latest.yaml" >/dev/null; settle 3
  expect "Enforce refuses an image with the latest tag" "$("${K[@]}" -n course-policy run t1 --image=nginx:latest 2>&1 | grep -c 'Use a specific image tag')" '^[1-9]'
  expect "Enforce refuses an image with no tag" "$("${K[@]}" -n course-policy run t2 --image=nginx 2>&1 | grep -c 'Use a specific image tag')" '^[1-9]'
  expect "a tagged image passes" "$("${K[@]}" -n course-policy run t3 --image=nginx:1.27-alpine 2>&1)" 'created'
  "${K[@]}" -n course-policy rollout restart deploy/legacy >/dev/null; settle 8
  expect "a restart of the legacy app hangs: its new pods are refused" "$("${K[@]}" -n course-policy get events --field-selector reason=FailedCreate 2>/dev/null | grep -c 'kyverno')" '^[1-9]'
  "${K[@]}" apply -f "$M/26-exception.yaml" >/dev/null
  expect "the PolicyException lets the rollout finish" "$("${K[@]}" -n course-policy rollout status deploy/legacy --timeout=120s 2>&1 | grep -c 'successfully rolled out')" '^1$'
  sed 's/namespace: kyverno/namespace: course-policy/; s/name: legacy-may-use-latest/name: self-service/; s/"legacy\*"/"other*"/' "$M/26-exception.yaml" | "${K[@]}" apply -f - >/dev/null 2>&1; settle 3
  expect "an exception in the team's own namespace is ignored" "$("${K[@]}" -n course-policy run other --image=nginx:latest 2>&1 | grep -c 'Use a specific image tag')" '^[1-9]'
  "${K[@]}" -n course-policy delete policyexception self-service --ignore-not-found >/dev/null 2>&1
  "${K[@]}" apply -f "$M/26-add-defaults.yaml" >/dev/null; settle 3
  "${K[@]}" -n course-policy run plain --image=nginx:1.27-alpine >/dev/null 2>&1
  expect "mutation adds a team label and a memory limit" "$("${K[@]}" -n course-policy get pod plain -o jsonpath='{.metadata.labels.team} {.spec.containers[0].resources.limits.memory}')" '^unassigned 128Mi$'
  "${K[@]}" -n course-policy run owned --image=nginx:1.27-alpine --labels=team=payments >/dev/null 2>&1
  expect "mutation keeps a label that's already there" "$("${K[@]}" -n course-policy get pod owned -o jsonpath='{.metadata.labels.team}')" '^payments$'
  "${K[@]}" apply -f "$M/26-generate-tenant.yaml" >/dev/null; settle 3
  "${K[@]}" create namespace course-tenant-a >/dev/null 2>&1
  "${K[@]}" label namespace course-tenant-a course-policy/tenant=true >/dev/null; settle 5
  expect "a tenant namespace gets a quota and a default-deny NetworkPolicy" "$("${K[@]}" -n course-tenant-a get resourcequota tenant-quota -o name 2>/dev/null) $("${K[@]}" -n course-tenant-a get networkpolicy default-deny-ingress -o name 2>/dev/null)" 'tenant-quota .*default-deny-ingress'
  local uid_before; uid_before="$("${K[@]}" -n course-tenant-a get networkpolicy default-deny-ingress -o jsonpath='{.metadata.uid}')"
  "${K[@]}" -n course-tenant-a delete networkpolicy default-deny-ingress >/dev/null; settle 5
  expect "Kyverno recreates a deleted generated NetworkPolicy" "$("${K[@]}" -n course-tenant-a get networkpolicy default-deny-ingress -o jsonpath='{.metadata.uid}' 2>/dev/null | grep -vc "^$uid_before$")" '^1$'
  "${K[@]}" apply -f "$M/26-cel-policy.yaml" >/dev/null; settle 3
  expect "the CEL policy refuses a Deployment without an owner label" "$("${K[@]}" -n course-policy create deployment no-owner --image=nginx:1.27-alpine 2>&1 | grep -c 'need an owner label')" '^1$'
  expect "and leaves other namespaces alone" "$("${K[@]}" -n default create deployment no-owner --image=nginx:1.27-alpine --dry-run=server 2>&1)" 'created \(server dry run\)'
  baseline
  expect "after the reset Kyverno's webhooks, CRDs and namespaces are gone" "$("${K[@]}" get validatingwebhookconfigurations,mutatingwebhookconfigurations 2>/dev/null | grep -c kyverno) $("${K[@]}" get crd 2>/dev/null | grep -c kyverno) $("${K[@]}" get ns kyverno course-policy course-tenant-a 2>&1 | grep -c NotFound)" '^0 0 3$'
}

# Module 27 needs Ollama on your Mac with nomic-embed-text and qwen2.5:3b, so it only
# runs when named: ./platform-engineering/verify.sh 27
module_27() {
  section "27: RAG on Kubernetes"
  baseline
  local H=(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}") pf
  expect "Ollama has the two models" "$(curl -s -m 5 "$OLLAMA/api/tags" | python3 -c 'import json,sys; print("\n".join(m["name"] for m in json.load(sys.stdin)["models"]))' 2>/dev/null | grep -cE '^(nomic-embed-text|qwen2\.5:3b)')" '^2$'
  "${H[@]}" repo add qdrant https://qdrant.github.io/qdrant-helm >/dev/null 2>&1
  "${H[@]}" repo update qdrant >/dev/null 2>&1
  expect "Qdrant installs with a volume" "$("${H[@]}" install qdrant qdrant/qdrant --version 1.20.0 -n course-rag --create-namespace -f "$M/27-qdrant-values.yaml" --wait --timeout 5m 2>&1 | grep -c 'STATUS: deployed') $("${K[@]}" -n course-rag get pvc -o jsonpath='{.items[0].status.phase}')" '^1 Bound$'
  docker build -q -t k8s-lab/rag:1.2.0 "$ROOT/apps/rag" >/dev/null 2>&1
  k3d image import k8s-lab/rag:1.2.0 -c "${CLUSTER_NAME:-k8s-lab}" >/dev/null 2>&1
  "${K[@]}" -n course-rag create configmap course-docs --from-file="$ROOT/platform-engineering/" >/dev/null
  "${K[@]}" apply -f "$M/27-rag-app.yaml" >/dev/null
  expect "the rag app starts" "$("${K[@]}" -n course-rag rollout status deploy/rag --timeout=120s 2>&1 | grep -c 'successfully rolled out')" '^1$'
  "${K[@]}" -n course-rag port-forward svc/rag 8091:8000 >/dev/null 2>&1 &
  pf=$!; settle 3
  local ingest; ingest="$(curl -s -m 300 -X POST localhost:8091/ingest)"
  between "ingest splits the course into chunks" "$(echo "$ingest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chunks"])' 2>/dev/null || echo 0)" 300 1500
  expect "nomic-embed-text makes 768-dimension vectors" "$(echo "$ingest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["dimensions"])' 2>/dev/null)" '^768$'
  expect "Qdrant holds every chunk" "$("${K[@]}" get --raw /api/v1/namespaces/course-rag/services/qdrant:6333/proxy/collections/course 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["points_count"])' 2>/dev/null)" "^$(echo "$ingest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["chunks"])' 2>/dev/null)\$"
  expect "search puts module 22 first for the rollback question" "$(curl -s -G localhost:8091/search --data-urlencode 'q=how do I roll back a bad release with ArgoCD' | python3 -c 'import json,sys; print(json.load(sys.stdin)["results"][0]["file"])' 2>/dev/null)" '^22-gitops-with-argocd\.md$'
  local ask; ask="$(curl -s -m 300 -X POST localhost:8091/ask -H 'content-type: application/json' -d '{"question":"Which Kyverno chart version does module 26 install?"}')"
  expect "ask answers a factual question from the course" "$(echo "$ask" | python3 -c 'import json,sys; print(json.load(sys.stdin)["answer"])' 2>/dev/null)" '3\.8\.2'
  local off; off="$(curl -s -m 300 -X POST localhost:8091/ask -H 'content-type: application/json' -d '{"question":"What is the capital of Denmark?"}')"
  expect "an off-topic question gets I don't know" "$(echo "$off" | python3 -c 'import json,sys; print(json.load(sys.stdin)["answer"])' 2>/dev/null)" "(don't|do not) know"
  expect "and its best match scores below 0.6" "$(echo "$off" | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["sources"][0]["score"] < 0.6))' 2>/dev/null)" '^1$'
  kill "$pf" 2>/dev/null; wait "$pf" 2>/dev/null
  baseline
  expect "after the reset course-rag and its volume are gone" "$("${K[@]}" get ns course-rag 2>&1 | grep -c NotFound) $("${K[@]}" get pv 2>/dev/null | grep -c course-rag)" '^1 0$'
}

module_28() {
  section "28: continuous profiling with Pyroscope"
  baseline
  local H=(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}") pf
  "${H[@]}" repo add grafana https://grafana.github.io/helm-charts >/dev/null 2>&1
  "${H[@]}" repo update grafana >/dev/null 2>&1
  expect "Pyroscope and its Alloy agent install" "$("${H[@]}" install pyroscope grafana/pyroscope --version 2.4.2 -n course-profiling --create-namespace -f "$M/28-pyroscope-values.yaml" --wait --timeout 6m 2>&1 | grep -c 'STATUS: deployed') $("${K[@]}" -n course-profiling get pods --no-headers 2>/dev/null | grep -c Running)" '^1 2$'
  "${K[@]}" apply -f "$M/28-podinfo.yaml" -f "$M/28-pyroscope-datasource.yaml" >/dev/null
  "${K[@]}" -n course-profiling rollout status deploy/podinfo --timeout=120s >/dev/null 2>&1
  "${K[@]}" -n course-profiling port-forward svc/pyroscope 4041:4040 >/dev/null 2>&1 &
  pf=$!; settle 3
  # top <profile type> <function>: that function's share of the total, in percent
  top() { curl -s "localhost:4041/pyroscope/render?query=$1%7Bservice_name%3D%22podinfo%22%7D&from=now-5m&until=now&format=json" | python3 -c '
import json,sys
fb=json.load(sys.stdin)["flamebearer"]; T=fb["numTicks"] or 1; best=0
for lvl in fb["levels"]:
  for i in range(0,len(lvl),4):
    if fb["names"][lvl[i+3]]==sys.argv[1]: best=max(best,lvl[i+1])
print(int(100*best/T))' "$2" 2>/dev/null || echo 0; }
  local cpu=0
  for _ in $(seq 1 24); do cpu="$(top process_cpu:cpu:nanoseconds:cpu:nanoseconds main.beginStressTest.func1)"; [[ "$cpu" =~ ^[5-9][0-9]$|^100$ ]] && break; settle 5; done
  between "the CPU flame graph blames the stress test (percent of total)" "$cpu" 50 100
  local services; services="$(curl -s -X POST localhost:4041/querier.v1.QuerierService/LabelValues -H 'content-type: application/json' -d "{\"name\":\"service_name\",\"start\":$(( ($(date +%s) - 600) * 1000 )),\"end\":$(( $(date +%s) * 1000 ))}")"
  expect "the annotations opted podinfo in" "$(echo "$services" | grep -o '"podinfo"')" '^"podinfo"$'
  # Allocation profiles count up from the start, so Pyroscope needs two scrapes for a difference.
  local mem=0
  for _ in $(seq 1 24); do mem="$(top memory:alloc_space:bytes:space:bytes main.beginStressTest)"; [[ "$mem" =~ ^[1-9][0-9]$|^100$ ]] && break; settle 5; done
  between "the memory profile shows the stress test allocating (percent)" "$mem" 10 100
  kill "$pf" 2>/dev/null; wait "$pf" 2>/dev/null
  local ds=""
  for _ in $(seq 1 12); do ds="$("${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- sh -c 'curl -s -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" localhost:3000/api/datasources/uid/pyroscope' 2>/dev/null | grep -o '"type":"grafana-pyroscope-datasource"')"; [[ -n "$ds" ]] && break; settle 5; done
  expect "Grafana has the Pyroscope data source" "$ds" 'grafana-pyroscope-datasource'
  expect "podinfo runs at its CPU limit" "$("${K[@]}" top pod -n course-profiling -l app=podinfo --no-headers 2>/dev/null | awk '{print $2}')" '^(4[0-9][0-9]|50[0-9])m$'
  baseline
  expect "after the reset course-profiling, Alloy's ClusterRole and the data source are gone" "$("${K[@]}" get ns course-profiling 2>&1 | grep -c NotFound) $("${K[@]}" get clusterrole pyroscope-alloy 2>&1 | grep -c NotFound) $("${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- sh -c 'curl -s -o /dev/null -w "%{http_code}" -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" localhost:3000/api/datasources/uid/pyroscope' 2>/dev/null)" '^1 1 404$'
}

module_29() {
  section "29: the life of a request"
  baseline
  local N="${CLUSTER_NAME:-k8s-lab}" node pod pid
  node="k3d-${N}-server-0"
  "${K[@]}" apply -f "$M/29-plain-app.yaml" >/dev/null
  "${K[@]}" -n course-life rollout status deploy/hello --timeout=120s >/dev/null 2>&1
  "${K[@]}" -n course-life rollout status deploy/client --timeout=120s >/dev/null 2>&1
  local events; events="$("${K[@]}" -n course-life get events -o 'custom-columns=WHO:.source.component,REASON:.reason' --no-headers 2>/dev/null)"
  expect "three controllers and the kubelet hand the work along" "$(echo "$events" | grep -cE 'deployment-controller +ScalingReplicaSet|replicaset-controller +SuccessfulCreate|default-scheduler +Scheduled|kubelet +Started' | tr -d ' ')" '^[4-9]$|^[1-9][0-9]$'
  pod="$("${K[@]}" -n course-life get pod -l app=hello -o jsonpath='{.items[0].metadata.name}')"
  local rs; rs="$("${K[@]}" -n course-life get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].name}')"
  expect "the pod belongs to a ReplicaSet, which belongs to the Deployment" "$("${K[@]}" -n course-life get pod "$pod" -o jsonpath='{.metadata.ownerReferences[0].kind}') $("${K[@]}" -n course-life get rs "$rs" -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}')" '^ReplicaSet Deployment/hello$'
  expect "you are system:admin in system:masters" "$("${K[@]}" auth whoami 2>/dev/null | grep -c 'system:masters')" '^1$'
  expect "RBAC refuses the frontend's service account" "$("${K[@]}" auth can-i create deployments -n course-life --as=system:serviceaccount:shop:frontend 2>/dev/null)" '^no$'
  expect "a watch delivers ADDED events" "$("${K[@]}" get --raw "/api/v1/namespaces/course-life/pods?watch=1&timeoutSeconds=2&labelSelector=app%3Dhello" 2>/dev/null | grep -c '"type":"ADDED"')" '^1$'
  "${K[@]}" -n course-life run greedy --image=nginx:1.27-alpine --overrides='{"spec":{"containers":[{"name":"greedy","image":"nginx:1.27-alpine","resources":{"requests":{"memory":"64Gi"}}}]}}' >/dev/null 2>&1
  "${K[@]}" -n course-life run picky --image=nginx:1.27-alpine --overrides='{"spec":{"nodeSelector":{"disktype":"ssd"}}}' >/dev/null 2>&1
  settle 5
  local sched; sched="$("${K[@]}" -n course-life get events --field-selector reason=FailedScheduling -o jsonpath='{range .items[*]}{.message}{"\n"}{end}' 2>/dev/null)"
  expect "the scheduler's filter refuses 64Gi" "$(echo "$sched" | grep -c 'Insufficient memory')" '^[1-9]'
  expect "and a nodeSelector no node matches" "$(echo "$sched" | grep -c "didn't match Pod's node affinity/selector")" '^[1-9]'
  "${K[@]}" -n course-life delete pod greedy picky --wait=false >/dev/null 2>&1
  expect "API validation refuses negative replicas" "$("${K[@]}" -n course-life create deployment bad --image=nginx:1.27-alpine --replicas=-1 --dry-run=client -o yaml | "${K[@]}" apply -f - 2>&1 | grep -c 'must be greater than or equal to 0')" '^1$'
  expect "Istio's admission webhook refuses an unknown attribute" "$(printf 'apiVersion: security.istio.io/v1\nkind: AuthorizationPolicy\nmetadata:\n  name: broken\n  namespace: course-life\nspec:\n  rules:\n  - when:\n    - key: request.colour\n      values: ["blue"]\n' | "${K[@]}" apply -f - 2>&1 | grep -c 'unknown attribute')" '^[1-9]'
  local svcip podip; svcip="$("${K[@]}" -n course-life get svc hello -o jsonpath='{.spec.clusterIP}')"; podip="$("${K[@]}" -n course-life get pod "$pod" -o jsonpath='{.status.podIP}')"
  expect "scenario A: the client reaches the Service" "$("${K[@]}" -n course-life exec deploy/client -- curl -s -o /dev/null -w '%{http_code}' http://hello 2>/dev/null)" '^200$'
  expect "kube-proxy DNATs the ClusterIP to the pod" "$(docker exec "$node" sh -c 'iptables-save -t nat' 2>/dev/null | grep 'course-life/hello' | grep -c "DNAT --to-destination ${podip}:80")" '^[1-9]'
  expect "conntrack holds both directions of the rewrite" "$(docker exec "$node" conntrack -L -d "$svcip" 2>/dev/null | grep -c "src=${podip}")" '^[1-9]'
  local lbip gwip; lbip="$("${K[@]}" -n shop-ingress get svc shop-gateway-istio -o jsonpath='{.status.loadBalancer.ingress[0].ip}')"; gwip="$("${K[@]}" -n shop-ingress get pod -l gateway.networking.k8s.io/gateway-name=shop-gateway -o jsonpath='{.items[0].status.podIP}')"
  curl -s -o /dev/null localhost:8080/ 2>/dev/null
  expect "scenario B: kube-proxy DNATs the load balancer IP straight to the gateway pod" "$(docker exec "$node" conntrack -L -p tcp -d "$lbip" --dport 8080 2>/dev/null | grep -c "src=${gwip} ")" '^[1-9]'
  local gw; gw="$("${K[@]}" -n shop-ingress get pod -l gateway.networking.k8s.io/gateway-name=shop-gateway -o name | head -1)"
  expect "the gateway's Envoy opens HBONE to the frontend itself" "$("${I[@]}" proxy-config endpoints "$gw" -n shop-ingress 2>/dev/null | grep frontend | grep -c 'envoy://connect_originate/')" '^[1-9]'
  local cid; cid="$(docker exec "$node" crictl ps --name frontend -q 2>/dev/null | head -1)"
  pid="$(docker exec "$node" crictl inspect --output go-template --template '{{.info.pid}}' "$cid" 2>/dev/null)"
  expect "ztunnel listens inside the frontend pod" "$(docker exec "$node" sh -c "cat /proc/$pid/net/tcp /proc/$pid/net/tcp6" 2>/dev/null | python3 -c 'import sys; print(" ".join(str(p) for p in sorted({int(l.split()[1].split(":")[1],16) for l in sys.stdin if len(l.split())>3 and l.split()[3]=="0A"})))')" '15001 15006 15008 15053'
  expect "istio-cni redirects the pod's outgoing TCP to ztunnel" "$(docker exec "$node" nsenter -t "$pid" -n iptables-save 2>/dev/null | grep -c 'REDIRECT --to-ports 15001')" '^[1-9]'
  expect "ztunnel holds the frontend's 24-hour certificate" "$("${I[@]}" ztunnel-config certificates 2>/dev/null | grep 'ns/shop/sa/frontend' | grep -c Leaf)" '^[1-9]'
  baseline
  expect "after the reset course-life is gone" "$("${K[@]}" get ns course-life 2>&1 | grep -c NotFound)" '^1$'
}

# Module 21 upgrades k3s for real, so it is not in the default run: ./platform-engineering/verify.sh 21
module_21() {
  section "21: k3s certificates, backups and upgrades (the upgrade is one-way)"
  local N="k3d-${CLUSTER_NAME:-k8s-lab}-server-0" B="${TMPDIR:-/tmp}/k8s-lab-k3s-backup" target=v1.31.14+k3s1
  local suc=https://github.com/rancher/system-upgrade-controller/releases/download/v0.20.2
  if [[ "$("${K[@]}" get node "$N" -o jsonpath='{.status.nodeInfo.kubeletVersion}')" == "$target" ]]; then
    fail "the lab runs the course version of k3s" "already $target; run ./scripts/teardown.sh --yes && ./scripts/provision.sh first"
    return
  fi
  baseline
  # The table's columns differ between k3s versions, so check the certificate file itself.
  expect "k3s lists its certificates, including the admin client certificate" "$(docker exec "$N" k3s certificate check --output table 2>/dev/null | grep -c 'client-admin.crt')" '^[1-9]'
  expect "client certificates live for one year" "$(docker exec "$N" cat /var/lib/rancher/k3s/server/tls/client-admin.crt | openssl x509 -noout -enddate | grep -c "$(( $(date -u +%Y) + 1 ))")" '^1$'
  local key_before; key_before="$(docker exec "$N" cat /var/lib/rancher/k3s/server/tls/client-admin.crt | openssl x509 -noout -pubkey | openssl sha256)"
  docker exec "$N" k3s certificate rotate >/dev/null 2>&1
  docker restart "$N" >/dev/null; "$ROOT/scripts/start.sh" --quiet >/dev/null 2>&1
  expect "certificate rotate gives the admin certificate a new key" "$(docker exec "$N" cat /var/lib/rancher/k3s/server/tls/client-admin.crt | openssl x509 -noout -pubkey | openssl sha256 | grep -c "$key_before")" '^0$'
  expect "kubectl still works: the CA stayed the same" "$("${K[@]}" get nodes --no-headers | awk '{print $2}')" '^Ready$'
  rm -rf "$B"; mkdir -p "$B"
  "${K[@]}" -n default create configmap before-backup --from-literal=note="made before the backup" >/dev/null
  k3d cluster stop "${CLUSTER_NAME:-k8s-lab}" >/dev/null 2>&1
  docker cp "$N:/var/lib/rancher/k3s/server/db" "$B/" && docker cp "$N:/var/lib/rancher/k3s/server/token" "$B/token"
  k3d cluster start "${CLUSTER_NAME:-k8s-lab}" >/dev/null 2>&1; "$ROOT/scripts/start.sh" --quiet >/dev/null 2>&1
  "${K[@]}" -n default create configmap after-backup --from-literal=note="made after the backup" >/dev/null
  "${K[@]}" -n default delete configmap before-backup >/dev/null
  k3d cluster stop "${CLUSTER_NAME:-k8s-lab}" >/dev/null 2>&1
  docker cp "$B/db/." "$N:/var/lib/rancher/k3s/server/db/" && docker cp "$B/token" "$N:/var/lib/rancher/k3s/server/token"
  k3d cluster start "${CLUSTER_NAME:-k8s-lab}" >/dev/null 2>&1; "$ROOT/scripts/start.sh" --quiet >/dev/null 2>&1
  expect "the restore brings back the state of the backup" "$("${K[@]}" -n default get cm --no-headers | awk '{print $1}' | grep backup | paste -sd' ' -)" '^before-backup$'
  "${K[@]}" -n default delete configmap before-backup after-backup --ignore-not-found >/dev/null
  rm -rf "$B"
  "${K[@]}" apply -f "$suc/crd.yaml" -f "$suc/system-upgrade-controller.yaml" >/dev/null
  "${K[@]}" -n system-upgrade rollout status deploy/system-upgrade-controller --timeout=180s >/dev/null 2>&1
  "${K[@]}" apply -f "$M/21-upgrade-plan.yaml" >/dev/null
  local v=""
  for _ in $(seq 1 60); do v="$("${K[@]}" get node "$N" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null)"; [[ "$v" == "$target" ]] && break; settle 10; done
  expect "the system-upgrade-controller upgrades k3s to $target" "$v" "^${target//+/\\+}$"
  for _ in $(seq 1 30); do [[ "$("${K[@]}" -n system-upgrade get plan server-plan -o jsonpath='{.status.conditions[?(@.type=="Complete")].status}')" == True ]] && break; settle 10; done
  settle 30
  expect "after the upgrade, containerd looks for CNI plugins in a new place" "$(docker exec "$N" grep -c 'bin_dirs = \["/var/lib/rancher/k3s/data/cni"\]' /var/lib/rancher/k3s/agent/etc/containerd/config.toml)" '^1$'
  "$ROOT/scripts/provision.sh" >/dev/null 2>&1
  "$ROOT/platform-engineering/fix-ip-leases.sh" >/dev/null 2>&1
  "$ROOT/scripts/start.sh" --quiet >/dev/null 2>&1; settle 10
  expect "provision.sh moves istio-cni to the new directory" "$(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n istio-system get values istio-cni -o json | grep -o '"cniBinDir":"[^"]*"')" 'k3s/data/cni'
  expect "after the repair the shop answers 200" "$(code "$BASE/api/orders")" '^200$'
}

# Module 14 upgrades Istio for real and cannot be undone, so it is not in the default
# run. Use it on a lab that runs the course version: ./platform-engineering/verify.sh 14
module_14() {
  section "14: upgrading Istio (one-way: rebuild the lab to return)"
  local NEW=1.25.5 REV=1-25-5 H=(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n istio-system)
  if "${H[@]}" list -q | grep -q '^istiod-'; then
    fail "the lab runs the course version of Istio" "already upgraded; run ./scripts/teardown.sh --yes && ./scripts/provision.sh first"
    return
  fi
  baseline
  "${K[@]}" apply -f "$M/07-sidecar-namespace.yaml" -f "$M/07-sidecar-apps.yaml" -f "$M/07-sidecar-podmonitor.yaml" >/dev/null
  "${K[@]}" -n course-sidecar rollout status deploy/httpbin --timeout=120s >/dev/null 2>&1
  "${K[@]}" -n course-sidecar rollout status deploy/client --timeout=120s >/dev/null 2>&1
  local log="${TMPDIR:-/tmp}/k8s-lab-upgrade-traffic.log"; : > "$log"
  ( while true; do curl -s -o /dev/null -m 3 -w '%{http_code}\n' "$BASE/api/orders" >> "$log"; sleep 0.1; done ) &
  local loader=$!
  helm repo update istio >/dev/null 2>&1
  "${H[@]}" upgrade istio-base istio/base --version "$NEW" -f "$ROOT/helm/istio-base-values.yaml" --force-conflicts --wait >/dev/null 2>&1
  expect "1. the CRDs come from the new base chart" "$("${H[@]}" list -o json | grep -o '"chart":"base-[0-9.]*"')" "base-${NEW}"
  "${H[@]}" install "istiod-${REV}" istio/istiod --version "$NEW" --set revision="$REV" --set profile=ambient \
    --set global.platform=k3s -f "$ROOT/helm/istiod-values.yaml" --wait --timeout 5m >/dev/null 2>&1
  expect "2. the canary control plane runs next to the old one" "$("${K[@]}" -n istio-system get deploy -l app=istiod --no-headers | wc -l | tr -d ' ')" '^2$'
  expect "2. the waypoint still talks to the old control plane" "$("${I[@]}" proxy-status 2>/dev/null | grep -c '^waypoint')" '^1$'
  local bin; bin="$("${H[@]}" get values istio-cni -o json | sed -n 's/.*"cniBinDir":"\([^"]*\)".*/\1/p')"
  "${H[@]}" upgrade istio-cni istio/cni --version "$NEW" -f "$ROOT/helm/istio-cni-values.yaml" --set global.platform=k3s \
    --set cni.cniBinDir="$bin" --force-conflicts --wait --timeout 5m >/dev/null 2>&1
  expect "3. istio-cni runs the new version" "$("${K[@]}" -n istio-system get ds istio-cni-node -o jsonpath='{.spec.template.spec.containers[0].image}')" ":${NEW}"
  "${H[@]}" upgrade ztunnel istio/ztunnel --version "$NEW" -f "$ROOT/helm/ztunnel-values.yaml" --set revision="$REV" --force-conflicts --wait --timeout 5m >/dev/null 2>&1
  expect "4. ztunnel runs the new version" "$("${K[@]}" -n istio-system get ds ztunnel -o jsonpath='{.spec.template.spec.containers[0].image}')" ":${NEW}"
  "${K[@]}" -n shop label gateway waypoint istio.io/rev="$REV" --overwrite >/dev/null
  "${K[@]}" -n shop rollout status deploy/waypoint --timeout=180s >/dev/null 2>&1; settle 5
  expect "5. the waypoint moved to the new control plane" "$("${I[@]}" proxy-status --revision "$REV" 2>/dev/null | grep '^waypoint' | grep -c "$NEW")" '^1$'
  "${K[@]}" -n shop label gateway waypoint istio.io/rev=default --overwrite >/dev/null
  "${K[@]}" -n shop rollout status deploy/waypoint --timeout=180s >/dev/null 2>&1; settle 8
  expect "5. rollback: relabelled to default, the waypoint is back on the old version" "$("${I[@]}" proxy-status 2>/dev/null | grep '^waypoint' | grep -vc "$NEW")" '^1$'
  "${K[@]}" -n shop label gateway waypoint istio.io/rev="$REV" --overwrite >/dev/null
  "${K[@]}" -n shop rollout status deploy/waypoint --timeout=180s >/dev/null 2>&1; settle 8
  "${K[@]}" -n shop-ingress label gateway shop-gateway istio.io/rev="$REV" --overwrite >/dev/null
  "${K[@]}" -n shop-ingress rollout status deploy/shop-gateway-istio --timeout=180s >/dev/null 2>&1; settle 5
  expect "6. the ingress gateway moved too" "$("${I[@]}" proxy-status --revision "$REV" 2>/dev/null | grep '^shop-gateway' | grep -c "$NEW")" '^1$'
  "${K[@]}" label ns course-sidecar istio-injection- istio.io/rev="$REV" --overwrite >/dev/null
  "${K[@]}" -n course-sidecar rollout restart deploy >/dev/null
  "${K[@]}" -n course-sidecar rollout status deploy/httpbin --timeout=180s >/dev/null 2>&1
  "${K[@]}" -n course-sidecar rollout status deploy/client --timeout=180s >/dev/null 2>&1; settle 15
  expect "7. restarted sidecars carry the new proxy" "$("${K[@]}" -n course-sidecar get pods -l app=httpbin -o jsonpath='{.items[*].spec.containers[*].image}')" "proxyv2:${NEW}"
  expect "7. nothing uses the old control plane any more" "$("${I[@]}" proxy-status 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')" '^0$'
  helm template istiod istio/istiod --version "$NEW" -s templates/revision-tags.yaml --set revisionTags="{default}" \
    --set revision="$REV" -n istio-system | "${K[@]}" apply -f - >/dev/null
  "${H[@]}" upgrade istio-base istio/base --version "$NEW" -f "$ROOT/helm/istio-base-values.yaml" --set defaultRevision="$REV" --force-conflicts --wait >/dev/null 2>&1
  expect "8. the default validator points at the new control plane" "$("${K[@]}" get validatingwebhookconfiguration istiod-default-validator -o jsonpath='{.webhooks[0].clientConfig.service.name}')" "^istiod-${REV}$"
  "${H[@]}" delete istiod >/dev/null 2>&1; settle 10
  expect "9. only the new control plane is left" "$("${K[@]}" -n istio-system get deploy -l app=istiod -o name)" "istiod-${REV}$"
  expect "9. Istio still validates new resources" "$("${K[@]}" apply --dry-run=server -f "$M/12-serviceentry.yaml" 2>&1 | grep -c 'created (server dry run)')" '^2$'
  kill "$loader" 2>/dev/null; wait "$loader" 2>/dev/null
  local total failed; total="$(wc -l < "$log" | tr -d ' ')"; failed="$(grep -vc '^200$' "$log" || true)"
  expect "the shop kept answering during the upgrade ($failed of $total requests failed)" "$(( failed * 100 <= total * 5 ))" '^1$'
  expect "after the upgrade the shop answers 200" "$(code "$BASE/api/orders")" '^200$'
  rm -f "$log"
}

modules=("$@")
if (( ${#modules[@]} == 0 )); then modules=(0 1 2 3 4 5 6 7 8 11 12 13 15 16 20 22 23 24 25 26 28 29); fi
# Start from the Git baseline, in case an exercise is still applied.
printf 'Restoring the baseline before the checks\n'
"$ROOT/platform-engineering/reset.sh" >/dev/null 2>&1
for m in "${modules[@]}"; do
  if declare -F "module_$m" >/dev/null; then "module_$m"; else echo "No module $m"; fi
done

printf '\nRestoring the baseline\n'
# --all also removes the module 7 namespaces and the course client, so the lab ends
# exactly as a fresh provision leaves it (module 0 expects 3 proxies).
"$ROOT/platform-engineering/reset.sh" --all >/dev/null 2>&1
printf '\n%d checks passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
