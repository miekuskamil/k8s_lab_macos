#!/usr/bin/env bash
# Put the lab back to its Git baseline after a course exercise.
#   ./course/reset.sh         restore routing, policies and experiment settings
#   ./course/reset.sh --all   also remove the course namespaces and the course client
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K=(kubectl --context "${KUBE_CONTEXT:-k3d-k8s-lab}")

echo "Removing course rules from the shop namespace"
"${K[@]}" -n shop delete virtualservice,destinationrule --all --ignore-not-found >/dev/null
"${K[@]}" -n shop delete telemetry waypoint-access-logs --ignore-not-found >/dev/null
"${K[@]}" -n shop delete authorizationpolicy backend-allow-course-client --ignore-not-found >/dev/null
"${K[@]}" -n course-sidecar delete virtualservice,destinationrule,peerauthentication --all --ignore-not-found >/dev/null 2>&1 || true
# Module 16: the classic ingress gateway. Deleting its namespace removes the Helm release too.
"${K[@]}" delete namespace istio-ingress --ignore-not-found >/dev/null
# Module 15: the faulty backend pod
"${K[@]}" -n shop delete deployment backend-v1-faulty --ignore-not-found >/dev/null
# Module 13: end-user authentication with JWT
"${K[@]}" -n shop-ingress delete requestauthentication shop-jwt --ignore-not-found >/dev/null
"${K[@]}" -n shop-ingress delete authorizationpolicy shop-require-jwt --ignore-not-found >/dev/null
# Module 12: egress to httpbin.org
"${K[@]}" -n shop delete serviceentry httpbin-org --ignore-not-found >/dev/null
"${K[@]}" -n shop delete authorizationpolicy httpbin-org-read-only --ignore-not-found >/dev/null
"${K[@]}" -n shop delete networkpolicy course-client-egress --ignore-not-found >/dev/null
# Module 11: the HTTP to HTTPS redirect and the shop certificate
"${K[@]}" -n shop delete httproute http-to-https --ignore-not-found >/dev/null
"${K[@]}" -n shop-ingress delete certificate shop-tls --ignore-not-found >/dev/null 2>&1 || true
"${K[@]}" -n shop-ingress delete secret shop-tls --ignore-not-found >/dev/null

echo "Applying the baseline Istio config from manifests/istio"
"${K[@]}" apply -f "$ROOT/manifests/istio/" >/dev/null

echo "Turning off the backend experiment settings"
"${K[@]}" -n shop set env deploy/backend-v1 deploy/backend-v2 RATE_LIMIT_RPS=0 EXTRA_LATENCY_MS=0 >/dev/null
"${K[@]}" -n shop rollout status deploy/backend-v1 --timeout=120s >/dev/null
"${K[@]}" -n shop rollout status deploy/backend-v2 --timeout=120s >/dev/null
"${K[@]}" -n shop wait --for=condition=Programmed gateway/waypoint --timeout=120s >/dev/null

if [[ "${1:-}" == "--all" ]]; then
  echo "Removing the course namespaces and the course client"
  "${K[@]}" delete namespace course-sidecar course-outside --ignore-not-found >/dev/null
  "${K[@]}" -n shop delete deployment/course-client serviceaccount/course-client --ignore-not-found >/dev/null
fi
# kubectl apply removes the argocd.argoproj.io/instance label that ArgoCD uses to
# track what it owns, because ArgoCD's own last apply included that label and the
# files on disk do not. A sync puts the labels back, so istio-config ends Synced.
echo "Asking ArgoCD to sync istio-config from Git"
"${K[@]}" -n argocd patch application istio-config --type merge \
  -p '{"operation":{"initiatedBy":{"username":"course-reset"},"sync":{}}}' >/dev/null 2>&1 || true
for _ in $(seq 1 24); do
  [[ "$("${K[@]}" -n argocd get application istio-config -o jsonpath='{.status.sync.status}' 2>/dev/null)" == "Synced" ]] && break
  sleep 5
done
echo "Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules."
