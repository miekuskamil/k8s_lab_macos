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
# Module 29: the plain app and its client
"${K[@]}" delete namespace course-life --ignore-not-found >/dev/null
# Module 28: the release first (Alloy's ClusterRole outlives the namespace), then the
# namespace and Grafana's Pyroscope data source.
if helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n course-profiling status pyroscope >/dev/null 2>&1; then
  helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n course-profiling uninstall pyroscope --wait >/dev/null 2>&1 || true
fi
"${K[@]}" delete namespace course-profiling --ignore-not-found >/dev/null
# Module 27: Qdrant's release, then the namespace. Its volume goes with the PVC.
# The rag image and the Ollama models on your Mac stay.
if helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n course-rag status qdrant >/dev/null 2>&1; then
  helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n course-rag uninstall qdrant --wait >/dev/null 2>&1 || true
fi
"${K[@]}" delete namespace course-rag --ignore-not-found >/dev/null
# Module 26: policies before Kyverno itself, so nothing blocks the clean-up. The chart's
# own hook removes the webhooks Kyverno created at runtime, and its CRDs.
if helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n kyverno status kyverno >/dev/null 2>&1; then
  "${K[@]}" delete clusterpolicies.kyverno.io,validatingpolicies.policies.kyverno.io --all --ignore-not-found >/dev/null 2>&1 || true
  "${K[@]}" -n kyverno delete policyexceptions.kyverno.io --all --ignore-not-found >/dev/null 2>&1 || true
  helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n kyverno uninstall kyverno --wait >/dev/null 2>&1 || true
fi
"${K[@]}" delete namespace kyverno course-policy course-tenant-a --ignore-not-found >/dev/null
# Module 25: Helm releases first, because the Collector's ClusterRole and binding
# outlive a namespace delete. Then the namespace and Grafana's Tempo data source.
for release in otel-collector tempo; do
  if helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n course-otel status "$release" >/dev/null 2>&1; then
    helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n course-otel uninstall "$release" --wait >/dev/null 2>&1 || true
  fi
done
"${K[@]}" delete namespace course-otel --ignore-not-found >/dev/null
# A provisioned data source is read-only and outlives its ConfigMap, so replace the file
# with a deleteDatasources instruction, wait until Grafana drops it, then remove the file.
#   remove_datasource <configmap> <uid> <name>
remove_datasource() {
  local cm=$1 uid=$2 name=$3
  has_it() {
    "${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- sh -c \
      "curl -s -o /dev/null -w '%{http_code}' -u \"\$GF_SECURITY_ADMIN_USER:\$GF_SECURITY_ADMIN_PASSWORD\" localhost:3000/api/datasources/uid/$uid" 2>/dev/null | grep -q 200
  }
  if has_it; then
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: %s\n  namespace: observability\n  labels:\n    grafana_datasource: "1"\ndata:\n  delete.yaml: |\n    apiVersion: 1\n    deleteDatasources:\n      - name: %s\n        orgId: 1\n' "$cm" "$name" \
      | "${K[@]}" apply -f - >/dev/null
    for _ in $(seq 1 24); do has_it || break; sleep 5; done
  fi
  "${K[@]}" -n observability delete configmap "$cm" --ignore-not-found >/dev/null
}
remove_datasource course-tempo-datasource tempo Tempo
remove_datasource course-pyroscope-datasource pyroscope Pyroscope
# Module 24: the dashboard's namespace, and the alert rule and folder that live only in Grafana
"${K[@]}" delete namespace course-dashboards --ignore-not-found >/dev/null
"${K[@]}" -n observability exec deploy/kube-prometheus-stack-grafana -c grafana -- sh -c \
  'A="$GF_SECURITY_ADMIN_USER:$GF_SECURITY_ADMIN_PASSWORD"
   curl -s -o /dev/null -u "$A" -X DELETE localhost:3000/api/v1/provisioning/alert-rules/shop-burn-grafana
   curl -s -o /dev/null -u "$A" -X DELETE "localhost:3000/api/folders/course?forceDeleteRules=true"' >/dev/null 2>&1 || true
# Module 23: the receiver, its Alertmanager route and the SLO rules all live in one namespace
"${K[@]}" delete namespace course-alerts --ignore-not-found >/dev/null
# Module 22: the ApplicationSet first (its Applications' finalizers delete what they
# deployed), then the hand-made Application, the project, Gitea and the namespaces.
"${K[@]}" -n argocd delete applicationset podinfo --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
"${K[@]}" -n argocd delete application podinfo-dev podinfo-prod --ignore-not-found --wait=true --timeout=60s >/dev/null 2>&1 || true
"${K[@]}" -n argocd delete appproject team-shop --ignore-not-found >/dev/null
"${K[@]}" delete clusterrole podinfo-reads-everything --ignore-not-found >/dev/null
"${K[@]}" delete namespace course-gitops course-gitops-dev course-gitops-prod --ignore-not-found >/dev/null
# Module 21: the backup markers. The k3s upgrade itself stays, like module 14's.
"${K[@]}" -n default delete configmap before-backup after-backup --ignore-not-found >/dev/null
# Module 20: the ops app and the extra node
"${K[@]}" delete namespace course-ops --ignore-not-found >/dev/null
if k3d node list 2>/dev/null | grep -q '^k3d-agent-0'; then
  "${K[@]}" drain k3d-agent-0 --ignore-daemonsets --delete-emptydir-data --disable-eviction --timeout=120s >/dev/null 2>&1 || true
  k3d node delete k3d-agent-0 >/dev/null 2>&1 || true
fi
"${K[@]}" delete node k3d-agent-0 --ignore-not-found >/dev/null
# Module 19: kagent, its CRDs and the agent's test namespace
if helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n kagent status kagent >/dev/null 2>&1; then
  helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n kagent uninstall kagent --wait >/dev/null 2>&1 || true
fi
if helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n kagent status kagent-crds >/dev/null 2>&1; then
  helm --kube-context "${KUBE_CONTEXT:-k3d-k8s-lab}" -n kagent uninstall kagent-crds >/dev/null 2>&1 || true
fi
"${K[@]}" delete namespace kagent course-agent --ignore-not-found >/dev/null
"${K[@]}" delete clusterrolebinding kagent-tools-view --ignore-not-found >/dev/null
# Module 18: the model servers. Deleting the namespace removes the downloaded models too.
"${K[@]}" delete namespace ai --ignore-not-found >/dev/null
"${K[@]}" -n observability delete servicemonitor ai-models --ignore-not-found >/dev/null
# Module 17: the shop assistant and the Ollama ServiceEntry
"${K[@]}" -n shop delete deployment,service,serviceaccount -l app=assistant --ignore-not-found >/dev/null
"${K[@]}" -n shop delete serviceaccount assistant --ignore-not-found >/dev/null
"${K[@]}" -n shop delete httproute assistant ollama-timeout --ignore-not-found >/dev/null
"${K[@]}" -n shop delete serviceentry ollama --ignore-not-found >/dev/null
"${K[@]}" -n shop delete authorizationpolicy backend-allow-assistant ollama-chat-only --ignore-not-found >/dev/null
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
