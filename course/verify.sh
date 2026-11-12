#!/usr/bin/env bash
# Replay the key exercise of every course module and check the result.
# Use it to confirm the course works on your lab, or to check your own work.
#
#   ./course/verify.sh          run every module (about 12 minutes)
#   ./course/verify.sh 4 5      run only modules 4 and 5
#
# The script changes routing and policies while it runs and restores the baseline at the end.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
M="$ROOT/course/manifests"
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
I=(istioctl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
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

baseline() { "$ROOT/course/reset.sh" >/dev/null 2>&1; settle 5; }

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
}

module_2() {
  section "2: identity and mTLS"
  "${K[@]}" apply -f "$M/02-outside-client.yaml" >/dev/null
  "${K[@]}" -n course-outside rollout status deploy/client --timeout=180s >/dev/null
  "${K[@]}" label ns course-outside istio.io/dataplane-mode- >/dev/null 2>&1; settle 3
  expect "ztunnel holds a certificate for the backend identity" "$("${I[@]}" ztunnel-config certificates 2>/dev/null | grep -c 'ns/shop/sa/backend.*Leaf')" '^[1-9]'
  expect "a client outside the mesh cannot reach the frontend" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://frontend.shop:3000/healthz)" '^000$'
  "${K[@]}" label ns course-outside istio.io/dataplane-mode=ambient --overwrite >/dev/null; settle 6
  expect "after labeling its namespace, the same pod gets in without a restart" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://frontend.shop:3000/healthz)" '^200$'
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
  "${K[@]}" apply -f "$M/03-allow-course-client.yaml" >/dev/null; settle 4
  expect "with its own rule, GET /api/version is allowed" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' http://backend:8000/api/version)" '^200$'
  expect "the rule does not cover /api/orders" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' http://backend:8000/api/orders)" '^403$'
  expect "dialing a backend pod IP is refused by ztunnel (L4)" "$(in_shop curl -s -m 5 -o /dev/null -w '%{http_code}' "http://${pod_ip}:8000/api/orders")" '^000$'
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
  baseline
}

module_5() {
  section "5: resilience"
  baseline
  "${K[@]}" -n shop delete httproute backend-route >/dev/null
  "${K[@]}" apply -f "$ROOT/manifests/scenarios/b-fault-injection.yaml" >/dev/null; settle 6
  local out started elapsed
  out="$(burst 200 10 /api/orders)"
  between "fault injection: about 10% of 200 return 503" "$(echo "$out" | count_matching '^503')" 5 45
  started=$(date +%s); curl -s -o /dev/null -m 10 "$BASE/api/orders"; curl -s -o /dev/null -m 10 "$BASE/api/orders"; elapsed=$(( $(date +%s) - started ))
  between "fault injection: two requests take at least 1 second" "$elapsed" 1 5
  baseline
  "${K[@]}" apply -f "$M/05-timeout.yaml" >/dev/null; settle 5
  expect "timeout: a 300 ms request still succeeds" "$(code "$BASE/api/slow?ms=300")" '^200$'
  expect "timeout: a 3 s request is cut off with 504" "$(code "$BASE/api/slow?ms=3000")" '^504$'
  baseline
  between "no circuit breaker: 50 parallel slow requests all succeed" "$(burst 200 50 '/api/slow?ms=300' | count_matching '^200')" 195 200
  "${K[@]}" apply -f "$ROOT/manifests/scenarios/c-circuit-breaker.yaml" >/dev/null; settle 6
  between "circuit breaker: most of 200 parallel requests get 503" "$(burst 200 50 '/api/slow?ms=300' | count_matching '^503')" 100 200
  baseline
  "${K[@]}" -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=20 >/dev/null
  "${K[@]}" -n shop rollout status deploy/backend-v1 --timeout=180s >/dev/null
  "${K[@]}" -n shop rollout status deploy/backend-v2 --timeout=180s >/dev/null; settle 20
  between "rate limit: some of 400 requests get 429" "$(burst 400 40 /api/orders | count_matching '^429')" 50 400
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
  baseline
}

module_7() {
  section "7: sidecar mode"
  "${K[@]}" apply -f "$M/07-sidecar-namespace.yaml" -f "$M/07-sidecar-apps.yaml" >/dev/null
  "${K[@]}" -n course-sidecar rollout status deploy/httpbin --timeout=240s >/dev/null
  "${K[@]}" -n course-sidecar rollout status deploy/client --timeout=240s >/dev/null
  "${K[@]}" apply -f "$M/02-outside-client.yaml" >/dev/null
  "${K[@]}" -n course-outside rollout status deploy/client --timeout=180s >/dev/null
  "${K[@]}" -n course-sidecar delete peerauthentication,virtualservice --all --ignore-not-found >/dev/null 2>&1; settle 4
  expect "injected pods run two containers" "$("${K[@]}" -n course-sidecar get pod -l app=httpbin -o jsonpath='{.items[0].spec.containers[*].name}')" 'httpbin istio-proxy'
  expect "httpbin sees the client certificate identity" "$(in_sidecar curl -s -m 5 http://httpbin:8000/headers | grep -c 'spiffe://cluster.local/ns/course-sidecar/sa/client')" '^[1-9]'
  expect "PERMISSIVE: a plaintext client gets in" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://httpbin.course-sidecar:8000/status/200)" '^200$'
  "${K[@]}" apply -f "$M/07-sidecar-strict-mtls.yaml" >/dev/null; settle 5
  expect "STRICT: the plaintext client is refused" "$(in_outside curl -s -m 5 -o /dev/null -w '%{http_code}' http://httpbin.course-sidecar:8000/status/200)" '^000$'
  expect "STRICT: the sidecar client still works" "$(in_sidecar curl -s -m 5 -o /dev/null -w '%{http_code}' http://httpbin:8000/status/200)" '^200$'
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
  expect "istioctl sees the sidecar proxies" "$("${I[@]}" proxy-status 2>/dev/null | grep -c 'course-sidecar')" '^2$'
}

module_8() {
  section "8: incidents"
  baseline
  "$ROOT/course/incident.sh" 1 >/dev/null; settle 5
  expect "incident 1 shows 403" "$(code "$BASE/api/orders")" '^403$'
  baseline
  "$ROOT/course/incident.sh" 2 >/dev/null; settle 6
  between "incident 2 shows 503 under parallel load" "$(burst 120 30 '/api/slow?ms=300' | count_matching '^503')" 30 120
  baseline
  "$ROOT/course/incident.sh" 3 >/dev/null; settle 6
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
  "$ROOT/course/incident.sh" 4 >/dev/null; settle 8
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
  local J="$ROOT/course/jwt"
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

modules=("$@")
if (( ${#modules[@]} == 0 )); then modules=(0 1 2 3 4 5 6 7 8 11 12 13); fi
# Start from the Git baseline, in case an exercise is still applied.
printf 'Restoring the baseline before the checks\n'
"$ROOT/course/reset.sh" >/dev/null 2>&1
for m in "${modules[@]}"; do
  if declare -F "module_$m" >/dev/null; then "module_$m"; else echo "No module $m"; fi
done

printf '\nRestoring the baseline\n'
"$ROOT/course/reset.sh" >/dev/null 2>&1
printf '\n%d checks passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
