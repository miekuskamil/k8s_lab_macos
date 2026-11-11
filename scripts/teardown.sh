#!/usr/bin/env bash
# Remove everything provision.sh created. Asks for confirmation unless you pass --yes.
set -euo pipefail

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Delete ArgoCD, Istio and the shop and observability namespaces from context orbstack? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

kubectl config use-context orbstack >/dev/null

echo "Deleting the root Application, which also deletes its children"
kubectl -n argocd delete application root --ignore-not-found --timeout=180s || true
kubectl -n argocd delete applications --all --ignore-not-found --timeout=120s || true

echo "Removing Helm releases"
for release in argocd:argocd ztunnel:istio-system istio-cni:istio-system istiod:istio-system istio-base:istio-system; do
  helm uninstall "${release%%:*}" -n "${release##*:}" >/dev/null 2>&1 || true
done

echo "Deleting namespaces"
kubectl delete namespace shop shop-ingress observability argocd istio-system --ignore-not-found --wait=false

echo "Done. Gateway API CRDs stay installed. Remove them with:"
echo "  kubectl delete -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/standard-install.yaml"
