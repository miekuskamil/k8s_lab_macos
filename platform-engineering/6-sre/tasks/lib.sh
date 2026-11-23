# Helpers for the reliability track's tasks, sourced by ../task.sh. Every command talks to the
# lab through kubectl, so a task runs the same from your terminal and from the toolbox.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
M="$ROOT/platform-engineering/manifests"
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")
H=(helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}")

PASSES=0
FAILS=0
# check "what" <command...>: the command's exit code decides PASS or FAIL.
check() {
  local what="$1"; shift
  if "$@" >/dev/null 2>&1; then
    printf '  PASS  %s\n' "$what"; PASSES=$((PASSES + 1))
  else
    printf '  FAIL  %s\n' "$what"; FAILS=$((FAILS + 1))
  fi
}
check_sh() { check "$1" bash -c "$2"; }
# matches <value> <extended regex>: for check "..." matches "$v" '^[0-9]+$'
matches() { [[ "$1" =~ $2 ]]; }
# at_least <number> <min> and below <number> <max>, for decimals too
at_least() { awk -v a="${1:-x}" -v b="$2" 'BEGIN { exit !(a != "x" && a + 0 >= b + 0) }'; }
below() { awk -v a="${1:-x}" -v b="$2" 'BEGIN { exit !(a != "x" && a + 0 < b + 0) }'; }

# prom <query>: the first result's value through the API server's service proxy, or nothing.
prom() {
  local q
  q="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
  "${K[@]}" get --raw "/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=$q" 2>/dev/null \
    | python3 -c 'import json,sys; r=json.load(sys.stdin)["data"]["result"]; print(r[0]["value"][1] if r else "")' 2>/dev/null
}
# prom_count <query>: how many series the query returns.
prom_count() {
  local q
  q="$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1")"
  "${K[@]}" get --raw "/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=$q" 2>/dev/null \
    | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["data"]["result"]))' 2>/dev/null || echo 0
}
# prom_rules: every loaded rule as "group<TAB>record-or-alert<TAB>health<TAB>expression".
prom_rules() {
  "${K[@]}" get --raw "/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/rules" 2>/dev/null \
    | python3 -c 'import json,sys
for g in json.load(sys.stdin)["data"]["groups"]:
    for r in g["rules"]:
        print(g["name"], r.get("name"), r.get("health"), " ".join(r.get("query","").split()), sep="\t")' 2>/dev/null
}
# grafana <curl arguments...>: call Grafana's API from inside its pod, as admin.
grafana() {
  "${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- \
    sh -c 'curl -s -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" "$@"' sh "$@" 2>/dev/null
}
# grafana_in <curl arguments...>: the same, with the request body on stdin (-d @-).
grafana_in() {
  "${K[@]}" -n observability exec -i deploy/kube-prometheus-stack-grafana -c grafana -- \
    sh -c 'curl -s -u "$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD" "$@"' sh "$@" 2>/dev/null
}
# dash_empty <uid> var=value...: how many panel queries of a Grafana dashboard return no data,
# with the variables filled in. Prints 99 when the dashboard is missing.
dash_empty() {
  local uid=$1; shift
  local code='import json, subprocess, sys, urllib.parse
d = json.load(sys.stdin)["dashboard"]
ctx, subs = sys.argv[1], dict(a.split("=", 1) for a in sys.argv[2:])
subs["__rate_interval"] = "1m"
empty = 0
for p in d["panels"]:
    for t in p.get("targets", []):
        e = t["expr"]
        for k in sorted(subs, key=len, reverse=True):
            e = e.replace("$" + k, subs[k])
        path = "/api/v1/namespaces/observability/services/kube-prometheus-stack-prometheus:9090/proxy/api/v1/query?query=" + urllib.parse.quote(e)
        out = subprocess.run(["kubectl", "--context", ctx, "get", "--raw", path], capture_output=True, text=True).stdout
        try:
            r = json.loads(out)["data"]["result"]
        except Exception:
            r = []
        empty += 0 if r else 1
print(empty)'
  grafana "localhost:3000/api/dashboards/uid/$uid" | python3 -c "$code" "${KUBE_CONTEXT:-k3d-k8s-lab}" "$@" 2>/dev/null || echo 99
}
# poll <seconds> <command...>: run the command every 5 s until it succeeds.
poll() { local t=$1 i; shift; for ((i = 0; i < t; i += 5)); do "$@" >/dev/null 2>&1 && return 0; sleep 5; done; return 1; }

# The checkout app of the track, on the baseline settings, and ready.
checkout_app() {
  "${K[@]}" apply -f "$M/6.1-checkout.yaml" >/dev/null
  "${K[@]}" -n course-sre rollout status deploy/checkout --timeout=180s >/dev/null 2>&1
  "${K[@]}" -n course-sre rollout status deploy/payments --timeout=180s >/dev/null 2>&1
  "${K[@]}" -n course-sre rollout status deploy/loadgen --timeout=120s >/dev/null 2>&1
}

# Run the reference solution from stdin, one command per line, from the repo folder, and print
# each command after a prompt the way the module's solution shows it. Lines starting with #
# are skipped.
shown() {
  local l
  cd "$ROOT" || return 1
  while IFS= read -r l; do
    case "$l" in ""|"#"*) continue ;; esac
    echo "\$ $l"
    eval "$l" </dev/null 2>&1
  done
}
