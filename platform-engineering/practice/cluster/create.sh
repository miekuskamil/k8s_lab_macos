#!/usr/bin/env bash
# Builds the practice cluster on two nodes. ./lab.sh practice up runs it.
#   kind (the default)   two Docker containers, practice-control-plane and practice-worker: see kind/kind.sh
#   orbstack or vms      two Linux machines, cks-cp and cks-w1, built below:
#     cks-cp  control plane (kubeadm, etcd, Calico), plus etcdctl, trivy, kube-bench, kubesec
#     cks-w1  worker, plus gVisor (runsc) and Falco
# Safe to run again: every step skips what is already done.
# Usage: ./platform-engineering/practice/cluster/create.sh
#        PRACTICE_PLATFORM=orbstack ./platform-engineering/practice/cluster/create.sh   on two OrbStack machines
#        PRACTICE_PLATFORM=vms ./platform-engineering/practice/cluster/create.sh        on two Ubuntu 24.04 VMs over SSH (see platform.sh)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/platform.sh"
[ "$PRACTICE_PLATFORM" = kind ] && exec "$HERE/kind/kind.sh" create
K8S_VERSION="${K8S_VERSION:-1.37.1}"
CALICO_VERSION="${CALICO_VERSION:-3.32.3}"
INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-1.15.1}"

say() { printf '\n=== %s\n' "$*"; }

say "1/7 machines"
for m in "$CP" "$W1"; do
  if [ "$PRACTICE_PLATFORM" = vms ]; then
    # The VMs exist already. Each needs SSH, passwordless sudo and the node's name as hostname,
    # because kubeadm names a node after its host and the tasks use the names in $CP and $W1.
    on "$m" true </dev/null || { echo "no SSH to $m as $PRACTICE_SSH_USER with passwordless sudo: $(node_shell_hint "$m")"; exit 1; }
    on "$m" "command -v cloud-init >/dev/null && cloud-init status --wait >/dev/null 2>&1
      if [ \"\$(hostname)\" != $m ]; then
        hostnamectl set-hostname $m
        grep -q ' $m\$' /etc/hosts || echo '127.0.1.1 $m' >> /etc/hosts
        mkdir -p /etc/cloud/cloud.cfg.d && echo 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-practice-hostname.cfg
      fi
      echo \"$m is up: \$(. /etc/os-release; echo \$PRETTY_NAME), \$(dpkg --print-architecture), kernel \$(uname -r)\""
  elif orb list | awk '{print $1}' | grep -qx "$m"; then
    orb start "$m" >/dev/null 2>&1 || true
    echo "$m exists"
  else
    orb create -a arm64 ubuntu:noble "$m"
  fi
done

say "2/7 containerd and kubeadm $K8S_VERSION on both nodes"
for m in "$CP" "$W1"; do
  # A node that already belongs to the cluster keeps its packages, so a rerun never undoes an upgrade.
  if on "$m" "test -f /etc/kubernetes/kubelet.conf"; then
    echo "$m is already a cluster node, skipping"
  else
    K8S_VERSION="$K8S_VERSION" node_file "$m" node-prep.sh
  fi
done

say "3/7 kubeadm init on $CP"
if [ "$PRACTICE_PLATFORM" = vms ]; then
  # The address the node uses to reach the outside, whatever its network card is called.
  CP_IP="$(on "$CP" "ip -4 -o route get 1.1.1.1 | sed 's/.* src \([0-9.]*\).*/\1/'")"
else
  CP_IP="$(on "$CP" "ip -4 -o addr show eth0 | awk '{print \$4}' | cut -d/ -f1")"
fi
if on "$CP" "test -f /etc/kubernetes/admin.conf"; then
  echo "already initialised"
else
  sed -e "s/__CP_IP__/$CP_IP/g" -e "s/__CP_NAME__/$CP/" -e "s/__K8S_VERSION__/$K8S_VERSION/" "$HERE/kubeadm-config.yaml" \
    | on "$CP" "mkdir -p /etc/kubeadm && cat > /etc/kubeadm/config.yaml && kubeadm init --config /etc/kubeadm/config.yaml >/var/log/kubeadm-init.log 2>&1 || { tail -30 /var/log/kubeadm-init.log; exit 1; }"
fi
# kubectl works for root and for the default user, like on an exam node.
on "$CP" 'mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config
  H=$(getent passwd '"$PRACTICE_NODE_USER"' | cut -d: -f6); mkdir -p "$H/.kube" && cp /etc/kubernetes/admin.conf "$H/.kube/config" && chown -R '"$PRACTICE_NODE_USER:$PRACTICE_NODE_USER"' "$H/.kube"
  grep -q "alias k=kubectl" /etc/bash.bashrc || printf "alias k=kubectl\nsource <(kubectl completion bash)\ncomplete -o default -F __start_kubectl k\nexport do=\"--dry-run=client -o yaml\"\n" >> /etc/bash.bashrc'

say "4/7 Calico $CALICO_VERSION (enforces NetworkPolicy)"
on "$CP" "curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml \
  | sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' -e 's|#   value: \"192.168.0.0/16\"|  value: \"10.244.0.0/16\"|' \
  | kubectl apply -f - >/dev/null && kubectl -n kube-system rollout status ds/calico-node --timeout=300s"

say "5/7 join $W1"
if on "$W1" "test -f /etc/kubernetes/kubelet.conf"; then
  echo "already joined"
else
  JOIN="$(on "$CP" "kubeadm token create --print-join-command")"
  on "$W1" "$JOIN --ignore-preflight-errors=Swap,SystemVerification >/var/log/kubeadm-join.log 2>&1 || { tail -20 /var/log/kubeadm-join.log; exit 1; }"
fi
on "$CP" "kubectl wait node --all --for=condition=Ready --timeout=300s >/dev/null && kubectl -n kube-system rollout status ds/calico-node --timeout=300s >/dev/null"

say "6/7 security tools"
node_file "$CP" tools.sh cp
node_file "$W1" tools.sh w1

say "7/7 ingress-nginx $INGRESS_NGINX_VERSION on NodePorts 30080 and 30443"
# The project was retired in March 2026, but the Ingress API it serves is the same one the exam asks about.
on "$CP" "curl -fsSL https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v${INGRESS_NGINX_VERSION}/deploy/static/provider/baremetal/deploy.yaml \
  | kubectl apply -f - >/dev/null
  kubectl -n ingress-nginx patch svc ingress-nginx-controller --type=json -p='[
    {\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":30080},
    {\"op\":\"replace\",\"path\":\"/spec/ports/1/nodePort\",\"value\":30443}]' >/dev/null
  kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s"

say "ready"
on "$CP" "kubectl get nodes -o wide"
cat <<EOF

Work on the control plane the way the exam does, from a shell on the node:
  $(node_shell_hint $CP)          # then: kubectl get nodes
  $(node_shell_hint $W1)          # for node tasks on the worker (sudo -i for root)
EOF
