#!/usr/bin/env bash
# The Cilium VM on Proxmox or any other hypervisor: the counterpart of the Mac's Lima VM
# (lima.sh) for PRACTICE_PLATFORM=vms. It turns one Ubuntu 24.04 VM, reached over SSH, into a
# one-node kubeadm cluster with Cilium as the CNI, AppArmor and WireGuard, for the Cilium tasks
# of module 4.7 and task 3 of practice exams 5 and 6. ./lab.sh practice cilium runs it.
#   ./lab.sh practice cilium up       builds the cluster on the VM; safe to run again
#   ./lab.sh practice cilium reset    back to a fresh cluster, VM and downloads kept
#   ./lab.sh practice cilium down     wipes the cluster with kubeadm reset and keeps the VM
#   ./lab.sh practice cilium shell    a root shell on the node, like "ssh cks-lima" on a Mac
# Settings, next to the other PRACTICE_* ones in lab.env (see platform.sh):
#   PRACTICE_CILIUM_HOST  address of the VM     (default 192.168.1.223)
#   PRACTICE_CILIUM       its hostname and node name (default practice-cilium)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PRACTICE_PLATFORM="${PRACTICE_PLATFORM:-${CKS_PLATFORM:-kind}}"
if [ "$PRACTICE_PLATFORM" != vms ]; then
  echo "The Cilium VM belongs to PRACTICE_PLATFORM=vms. On a Mac, the Lima VM does this job:"
  echo "  ./platform-engineering/practice/cluster/lima.sh create"
  exit 1
fi
. "$HERE/platform.sh"
VM="$PRACTICE_CILIUM"
HOST="$PRACTICE_CILIUM_HOST"
K8S_VERSION="${K8S_VERSION:-1.37.1}"
CILIUM_VERSION="${CILIUM_VERSION:-1.20.4}"
CILIUM_CLI_VERSION="${CILIUM_CLI_VERSION:-0.20.2}"

say() { printf '\n=== %s\n' "$*"; }
# One command line as root on the VM. ssh reads stdin, so it gets /dev/null unless a caller pipes a file in.
vm() { _pc_ssh "$HOST" "sudo -H bash -c $(printf '%q' "$*")"; }

reachable() {
  vm true </dev/null 2>/dev/null && return 0
  echo "no SSH to $HOST as $PRACTICE_SSH_USER with passwordless sudo: ssh -i $PRACTICE_SSH_KEY $PRACTICE_SSH_USER@$HOST"
  echo "create the VM first, for example with proxmox/create-vms.sh cks, or set PRACTICE_CILIUM_HOST"
  exit 1
}

wait_cluster() {
  vm 'for i in $(seq 1 90); do kubectl get --raw=/readyz >/dev/null 2>&1 && break; sleep 2; done
      kubectl wait node --all --for=condition=Ready --timeout=300s >/dev/null
      kubectl -n kube-system rollout status ds/cilium --timeout=300s >/dev/null && echo "cluster ready"' </dev/null
}

build_cluster() {
  say "1/4 the VM $VM at $HOST"
  # The first boot upgrades packages through cloud-init, and apt waits for nobody, so wait for it.
  vm "command -v cloud-init >/dev/null && cloud-init status --wait >/dev/null 2>&1
    if [ \"\$(hostname)\" != $VM ]; then
      hostnamectl set-hostname $VM
      grep -q ' $VM\$' /etc/hosts || echo '127.0.1.1 $VM' >> /etc/hosts
      mkdir -p /etc/cloud/cloud.cfg.d && echo 'preserve_hostname: true' > /etc/cloud/cloud.cfg.d/99-practice-hostname.cfg
    fi
    echo \"$VM is up: \$(. /etc/os-release; echo \$PRETTY_NAME), \$(dpkg --print-architecture), kernel \$(uname -r)\"" </dev/null

  say "2/4 containerd and kubeadm $K8S_VERSION"
  if vm "test -f /etc/kubernetes/kubelet.conf" </dev/null; then
    echo "already a cluster node, skipping"
  else
    # The same node-prep.sh that the practice nodes and the Lima VM run.
    _pc_ssh "$HOST" "cat > /tmp/node-prep.sh" < "$HERE/node-prep.sh"
    _pc_ssh "$HOST" "sudo -H env K8S_VERSION=$K8S_VERSION bash /tmp/node-prep.sh" </dev/null
  fi

  say "3/4 kubeadm init"
  if vm "test -f /etc/kubernetes/admin.conf" </dev/null; then
    echo "already initialised"
  else
    vm "IP=\$(ip -4 -o route get 1.1.1.1 | sed 's/.* src \([0-9.]*\).*/\1/')
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
clusterName: $VM
kubernetesVersion: v$K8S_VERSION
networking:
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
YAML
kubeadm init --config /etc/kubeadm/config.yaml >/var/log/kubeadm-init.log 2>&1 || { tail -30 /var/log/kubeadm-init.log; exit 1; }" </dev/null
  fi
  # kubectl works for root and for the login user, like on an exam node.
  vm 'mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config
    H=$(getent passwd '"$PRACTICE_SSH_USER"' | cut -d: -f6); mkdir -p "$H/.kube" && cp /etc/kubernetes/admin.conf "$H/.kube/config" && chown -R '"$PRACTICE_SSH_USER:$PRACTICE_SSH_USER"' "$H/.kube"
    grep -q "alias k=kubectl" /etc/bash.bashrc || printf "alias k=kubectl\nsource <(kubectl completion bash)\ncomplete -o default -F __start_kubectl k\nexport do=\"--dry-run=client -o yaml\"\n" >> /etc/bash.bashrc' </dev/null

  say "4/4 Cilium $CILIUM_VERSION"
  vm 'for i in $(seq 1 90); do kubectl get --raw=/readyz >/dev/null 2>&1 && exit 0; sleep 2; done
      echo "the API server did not answer in 3 minutes"; exit 1' </dev/null
  vm "set -e
if ! cilium version --client 2>/dev/null | grep -q 'v$CILIUM_CLI_VERSION'; then
  curl -fsSL https://github.com/cilium/cilium-cli/releases/download/v$CILIUM_CLI_VERSION/cilium-linux-\$(dpkg --print-architecture).tar.gz | tar -xz -C /usr/local/bin cilium
fi
if ! kubectl -n kube-system get ds cilium >/dev/null 2>&1; then
  cilium install --version $CILIUM_VERSION --set ipam.mode=kubernetes >/dev/null
fi
cilium status --wait --wait-duration 5m >/dev/null && echo \"cilium \$(cilium version 2>/dev/null | awk '/running/{print \$NF}') ready\"" </dev/null
  wait_cluster
  vm 'echo "AppArmor: $(cat /sys/module/apparmor/parameters/enabled), $(aa-status 2>/dev/null | head -1)"
    echo "WireGuard: $(modprobe -n -v wireguard >/dev/null 2>&1 && echo available || echo missing)"
    kubectl get nodes -o wide' </dev/null
}

# Wipe the cluster and what the tasks changed on the node; the packages and downloads stay.
wipe() {
  say "wiping the cluster on $VM"
  vm 'kubeadm reset -f >/dev/null 2>&1 || true
    rm -rf /etc/cni/net.d/* /var/lib/etcd /var/lib/kubelet/* /etc/kubeadm /root/.kube /var/log/kubernetes
    iptables-save | grep -v -E "KUBE|CILIUM" | iptables-restore 2>/dev/null || true
    for l in cilium_host cilium_net cilium_vxlan cilium_wg0; do ip link delete $l 2>/dev/null || true; done
    for p in /etc/apparmor.d/cks-* /etc/apparmor.d/m2-*; do [ -e "$p" ] && apparmor_parser -R "$p" 2>/dev/null; done; true
    rm -rf /etc/apparmor.d/cks-* /etc/apparmor.d/m2-* /etc/modprobe.d/cks-*.conf /etc/modprobe.d/m3.conf /root/cks /root/mock' </dev/null
}

case "${1:-}" in
  up)
    reachable
    build_cluster
    echo
    echo "Work on the node the way the exam does: ./lab.sh practice cilium shell" ;;
  reset)
    reachable
    wipe
    build_cluster ;;
  down)
    if [ "${2:-}" != --yes ]; then
      read -r -p "Wipe the cluster on $VM ($HOST)? The VM stays. Type yes: " ok
      [ "$ok" = yes ] || { echo "kept"; exit 0; }
    fi
    reachable
    wipe
    echo "$VM keeps its packages: ./lab.sh practice cilium up builds the cluster again" ;;
  shell)
    # shellcheck disable=SC2086
    exec ssh -t -i "$PRACTICE_SSH_KEY" $PRACTICE_SSH_OPTS "$PRACTICE_SSH_USER@$HOST" sudo -i ;;
  *)
    sed -n '6,9p' "$0" | sed 's/^# *//'; exit 1 ;;
esac
