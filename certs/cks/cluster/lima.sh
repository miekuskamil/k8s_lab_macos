#!/usr/bin/env bash
# The third practice machine: a Lima virtual machine "cks-lima" with its own Ubuntu kernel,
# for the tasks the OrbStack machines can't run. It holds a one-node kubeadm cluster with
# Cilium as the CNI, and its kernel has AppArmor. macOS only.
#   ./certs/cks/cluster/lima.sh create    builds the VM and the cluster; safe to run again
#   ./certs/cks/cluster/lima.sh start     starts a stopped VM and waits for the cluster
#   ./certs/cks/cluster/lima.sh stop      stops the VM and frees its memory
#   ./certs/cks/cluster/lima.sh reset     back to a fresh cluster, VM and downloads kept
#   ./certs/cks/cluster/lima.sh destroy   deletes the VM
#   ./certs/cks/cluster/lima.sh shell     a root shell on the node, like "ssh cks-lima" in the exam
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VM=cks-lima
K8S_VERSION="${K8S_VERSION:-1.37.1}"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"
CILIUM_CLI_VERSION="${CILIUM_CLI_VERSION:-0.20.2}"

say() { printf '\n=== %s\n' "$*"; }
on() { limactl shell --workdir / "$VM" sudo bash -c "$*"; }
exists() { limactl list -q 2>/dev/null | grep -qx "$VM"; }
running() { [ "$(limactl list --format '{{.Status}}' "$VM" 2>/dev/null)" = Running ]; }

command -v limactl >/dev/null || { echo "Lima is missing: brew install lima"; exit 1; }

wait_cluster() {
  on 'for i in $(seq 1 90); do kubectl get --raw=/readyz >/dev/null 2>&1 && break; sleep 2; done
      kubectl wait node --all --for=condition=Ready --timeout=300s >/dev/null
      kubectl -n kube-system rollout status ds/cilium --timeout=300s >/dev/null && echo "cluster ready"'
}

build_cluster() {
  say "2/4 containerd and kubeadm $K8S_VERSION"
  if on "test -f /etc/kubernetes/kubelet.conf"; then
    echo "already a cluster node, skipping"
  else
    on "hostnamectl set-hostname $VM && grep -q ' $VM\$' /etc/hosts || echo '127.0.1.1 $VM' >> /etc/hosts"
    limactl shell --workdir / "$VM" sudo env K8S_VERSION="$K8S_VERSION" bash "$HERE/node-prep.sh"
  fi

  say "3/4 kubeadm init"
  if on "test -f /etc/kubernetes/admin.conf"; then
    echo "already initialised"
  else
    on "IP=\$(ip -4 -o route get 1.1.1.1 | sed 's/.* src \([0-9.]*\).*/\1/')
mkdir -p /etc/kubeadm && cat > /etc/kubeadm/config.yaml <<YAML
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: \$IP
nodeRegistration:
  name: $VM
  criSocket: unix:///run/containerd/containerd.sock
  taints: []                  # one node does everything, so workloads run on the control plane too
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
clusterName: cks-lima
kubernetesVersion: v$K8S_VERSION
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
YAML
kubeadm init --config /etc/kubeadm/config.yaml >/var/log/kubeadm-init.log 2>&1 || { tail -30 /var/log/kubeadm-init.log; exit 1; }"
  fi
  on 'mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config
    grep -q "alias k=kubectl" /etc/bash.bashrc || printf "alias k=kubectl\nsource <(kubectl completion bash)\ncomplete -o default -F __start_kubectl k\nexport do=\"--dry-run=client -o yaml\"\n" >> /etc/bash.bashrc'

  say "4/4 Cilium $CILIUM_VERSION"
  on "set -e
if ! cilium version --client 2>/dev/null | grep -q 'v$CILIUM_CLI_VERSION'; then
  curl -fsSL https://github.com/cilium/cilium-cli/releases/download/v$CILIUM_CLI_VERSION/cilium-linux-arm64.tar.gz | tar -xz -C /usr/local/bin cilium
fi
if ! kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
  cilium install --version $CILIUM_VERSION --set ipam.mode=kubernetes >/dev/null
fi
cilium status --wait --wait-duration 5m >/dev/null && echo \"cilium \$(cilium version 2>/dev/null | awk '/running/{print \$NF}') ready\""
  wait_cluster
}

case "${1:-}" in
  create)
    say "1/4 the VM $VM (Ubuntu 24.04, 2 CPUs, 3 GiB)"
    if exists; then
      running || limactl start "$VM"
      echo "$VM exists"
    else
      limactl start --name "$VM" --tty=false "$HERE/lima.yaml"
    fi
    build_cluster
    on 'echo "AppArmor: $(cat /sys/module/apparmor/parameters/enabled), $(aa-status 2>/dev/null | head -1)"; kubectl get nodes -o wide'
    cat <<EOF

Work on the node the way the exam does:
  ./certs/cks/cluster/lima.sh shell     # or: limactl shell $VM sudo -i
EOF
    ;;
  start)
    exists || { echo "$VM does not exist: $0 create"; exit 1; }
    running || limactl start "$VM"
    wait_cluster ;;
  stop)
    if exists && running; then limactl stop "$VM"; else echo "$VM is not running"; fi ;;
  reset)
    exists || { echo "$VM does not exist: $0 create"; exit 1; }
    running || limactl start "$VM"
    say "wiping the cluster on $VM"
    on 'kubeadm reset -f >/dev/null 2>&1 || true
      rm -rf /etc/cni/net.d/* /var/lib/etcd /var/lib/kubelet/* /etc/kubeadm /root/.kube /var/log/kubernetes
      iptables-save | grep -v -E "KUBE|CILIUM" | iptables-restore 2>/dev/null || true
      for l in cilium_host cilium_net cilium_vxlan; do ip link delete $l 2>/dev/null || true; done
      # Undo what the tasks change on the node.
      for p in /etc/apparmor.d/cks-*; do [ -e "$p" ] && apparmor_parser -R "$p" 2>/dev/null; done; true
      rm -rf /etc/apparmor.d/cks-* /etc/modprobe.d/cks-*.conf /root/cks'
    build_cluster ;;
  destroy)
    if exists; then limactl delete -f "$VM"; echo "deleted $VM"; else echo "$VM does not exist"; fi ;;
  shell)
    exec limactl shell --workdir / "$VM" sudo -i ;;
  *)
    sed -n '2,11p' "$0"; exit 1 ;;
esac
