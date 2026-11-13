#!/usr/bin/env bash
# Print the addresses and names from docs/life-of-a-request.md ("The cast in this run")
# and module 29, as they are in YOUR lab right now. Pod and Service IPs change with every
# rebuild and every pod restart; the names, ports and ranges stay the same.
#
# Usage: ./course/my-values.sh
# Scenario A rows need module 29's app: kubectl apply -f course/manifests/29-plain-app.yaml
set -u
NODE="${NODE:-k3d-k8s-lab-server-0}"
LB="${LB:-k3d-k8s-lab-serverlb}"

podip() { kubectl -n "$1" get pod -l "$2" -o jsonpath='{.items[0].status.podIP}' 2>/dev/null; }
svcip() { kubectl -n "$1" get svc "$2" -o jsonpath='{.spec.clusterIP}' 2>/dev/null; }
podname() { kubectl -n "$1" get pod -l "$2" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null; }
row() { printf '  %-34s %s\n' "$1" "${2:-(not running)}"; }

echo "Node"
row "node container" "$NODE"
row "node IP" "$(docker inspect "$NODE" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)"
row "this node's pod range" "$(kubectl get node "$NODE" -o jsonpath='{.spec.podCIDR}' 2>/dev/null)"
row "serverlb container IP" "$(docker inspect "$LB" -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)"

echo
echo "Scenario A (namespace course-life)"
if kubectl get ns course-life >/dev/null 2>&1; then
  row "client pod" "$(podip course-life app=client)"
  row "hello Service (ClusterIP)" "$(svcip course-life hello)"
  row "hello pod (nginx)" "$(podip course-life app=hello)"
  row "hello pod name" "$(podname course-life app=hello)"
else
  echo "  not deployed: kubectl apply -f course/manifests/29-plain-app.yaml"
fi

echo
echo "Scenario B (the shop)"
row "gateway Service (ClusterIP)" "$(svcip shop-ingress shop-gateway-istio)"
row "gateway pod" "$(podip shop-ingress gateway.networking.k8s.io/gateway-name=shop-gateway)"
row "svclb pod" "$(kubectl -n kube-system get pods -l svccontroller.k3s.cattle.io/svcname=shop-gateway-istio -o jsonpath='{.items[0].status.podIP}' 2>/dev/null)"
row "frontend pod" "$(podip shop app=frontend)"
row "backend Service (ClusterIP)" "$(svcip shop backend)"
row "waypoint pod" "$(podip shop gateway.networking.k8s.io/gateway-name=waypoint)"
row "backend-v1 pods" "$(kubectl -n shop get pod -l app=backend,version=v1 -o jsonpath='{.items[*].status.podIP}' 2>/dev/null)"
row "redis pod" "$(podip shop app=redis)"
