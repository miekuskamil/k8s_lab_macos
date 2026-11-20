#!/usr/bin/env bash
# Takes the application tasks and practice exams off the practice cluster and leaves it where the security
# modules expect it. Faster than ./platform-engineering/practice/cluster/reset.sh, because the cluster stays up:
#   - deletes every namespace labelled ckad (the tasks and mocks label theirs)
#   - deletes the cluster-wide objects the tasks create: CRDs in the ckad.io group, and
#     ClusterRoles, ClusterRoleBindings, PersistentVolumes, StorageClasses, PriorityClasses
#     and IngressClasses whose names start with ckad-
#   - removes metrics-server, which the plain practice cluster doesn't run (tasks that need it add it back)
#   - empties /opt/ckad, podman's images and the local registry on the nodes
# helm, podman, kubectl-convert and the registry service stay installed; they don't touch Kubernetes.
# Usage: ./platform-engineering/practice/app-extras/reset.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../cluster/platform.sh"
METRICS_SERVER_VERSION="${METRICS_SERVER_VERSION:-0.9.1}"

if [ "$CKS_PLATFORM" = orbstack ]; then
  for m in "$CKS_CP" "$CKS_W1"; do orb start "$m" >/dev/null 2>&1 || true; done
fi

echo "=== Kubernetes objects"
node_sh "$CKS_CP" '
  for i in $(seq 1 60); do kubectl get --raw=/readyz >/dev/null 2>&1 && break; sleep 2; done
  ns=$(kubectl get ns -l ckad -o name)
  [ -z "$ns" ] || { echo "deleting $(echo $ns | wc -w) namespaces"; kubectl delete $ns --wait=false >/dev/null; }
  crd=$(kubectl get crd -o name | grep "\.ckad\.io$" || true)
  [ -z "$crd" ] || kubectl delete $crd
  for r in clusterrole clusterrolebinding pv storageclass priorityclass ingressclass validatingadmissionpolicy validatingadmissionpolicybinding; do
    o=$(kubectl get $r -o name 2>/dev/null | grep "/ckad-" || true)
    [ -z "$o" ] || kubectl delete $o --wait=false
  done
  for n in $(kubectl get nodes -o name); do
    for l in $(kubectl get $n -o json | python3 -c "import json,sys; print(\" \".join(k for k in json.load(sys.stdin)[\"metadata\"][\"labels\"] if k.startswith(\"ckad\")))"); do
      kubectl label $n $l- >/dev/null
    done
  done
  [ -z "$ns" ] || kubectl wait --for=delete $ns --timeout=180s >/dev/null 2>&1 || echo "some namespaces still terminating"
  # metrics-server goes last: a namespace only finishes deleting while every API group answers,
  # and the metrics API stops answering the moment metrics-server goes away.
  kubectl -n kube-system get deploy metrics-server >/dev/null 2>&1 && \
    curl -fsSL https://github.com/kubernetes-sigs/metrics-server/releases/download/v'"$METRICS_SERVER_VERSION"'/components.yaml \
    | kubectl delete -f - --ignore-not-found >/dev/null && echo "removed metrics-server"
  pv=$(kubectl get pv -o name | grep "/ckad-" || true)
  [ -z "$pv" ] || kubectl wait --for=delete $pv --timeout=60s >/dev/null 2>&1 || true
'

echo "=== files, images and the registry on the nodes"
node_sh "$CKS_CP" '
  rm -rf /opt/ckad /root/.config/helm /root/.cache/helm /root/ckad
  for u in $(kubectl config get-users 2>/dev/null | grep "^ckad-"); do kubectl config delete-user "$u" >/dev/null; done
  if command -v podman >/dev/null; then podman rm -af >/dev/null 2>&1; podman rmi -af >/dev/null 2>&1; fi
  if systemctl is-active ckad-registry >/dev/null 2>&1; then
    systemctl stop ckad-registry; rm -rf /var/lib/ckad-registry/*; systemctl start ckad-registry
  fi
  true'
node_sh "$CKS_W1" 'rm -rf /opt/ckad /var/lib/ckad-data; true'

echo "=== left in the cluster"
node_sh "$CKS_CP" 'kubectl get ns --no-headers | awk "{print \$1}" | tr "\n" " "; echo'
