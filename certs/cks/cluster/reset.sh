#!/usr/bin/env bash
# Returns the practice cluster to a fresh state without recreating the machines.
# kubeadm reset wipes /etc/kubernetes (manifests, audit policy, admission configs),
# node-prep.sh puts the packages back at the starting version (it undoes an upgrade),
# and create.sh builds the cluster again. Takes about 4 minutes in the test run.
# Usage: ./certs/cks/cluster/reset.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
on() { local m="$1"; shift; orb -m "$m" -u root bash -c "$*"; }

for m in cks-w1 cks-cp; do
  echo "=== wiping $m"
  orb start "$m" >/dev/null 2>&1 || true
  on "$m" '
    kubeadm reset -f >/dev/null 2>&1 || true
    rm -rf /etc/cni/net.d/* /var/lib/etcd /var/lib/kubelet/* /etc/kubeadm /root/.kube /var/log/kubernetes
    H=$(getent passwd 501 | cut -d: -f6); rm -rf "$H/.kube"
    iptables-save | grep -v -E "KUBE|cali" | iptables-restore 2>/dev/null || true
    ip link delete tunl0 2>/dev/null || true
    # Undo changes the tasks make on the nodes.
    rm -f /etc/falco/falco_rules.local.yaml /etc/falco/rules.d/cks-*.yaml
    rm -rf /etc/apparmor.d/cks-* /var/lib/kubelet/seccomp/profiles
    systemctl is-enabled falco-modern-bpf >/dev/null 2>&1 && systemctl restart falco-modern-bpf || true
    for s in snapd cups apache2 nginx; do systemctl is-enabled "$s" >/dev/null 2>&1 && systemctl disable --now "$s" >/dev/null 2>&1 || true; done
    userdel -r cks-dev >/dev/null 2>&1 || true
  '
done

"$HERE/create.sh"
