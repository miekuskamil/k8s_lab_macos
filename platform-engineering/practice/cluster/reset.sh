#!/usr/bin/env bash
# Returns the practice cluster to a fresh state. ./lab.sh practice reset runs it.
# On kind (the default) it deletes the two node containers and creates them again from the same
# image, which takes about two minutes. On OrbStack machines and VMs the machines stay:
# kubeadm reset wipes /etc/kubernetes (manifests, audit policy, admission configs),
# node-prep.sh puts the packages back at the starting version (it undoes an upgrade),
# and create.sh builds the cluster again. Takes about 4 minutes in the test run.
# Usage: ./platform-engineering/practice/cluster/reset.sh
#        ./platform-engineering/practice/cluster/reset.sh --wipe-only   wipes the nodes and stops there (destroy.sh uses it on VMs)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/platform.sh"
if [ "$PRACTICE_PLATFORM" = kind ]; then
  [ "${1:-}" = --wipe-only ] && exec "$HERE/kind/kind.sh" destroy
  exec "$HERE/kind/kind.sh" reset
fi

# On OrbStack the tasks' SSH server goes away again. On a VM it stays, because the scripts
# reach the node through it, and it reloads without the settings the tasks added.
if [ "$PRACTICE_PLATFORM" = vms ]; then
  SSH_UNDO='rm -rf /etc/ssh/sshd_config.d/10-legacy.conf /etc/ssh/sshd_config.d/05-vendor.conf
    sshd -t && systemctl reload ssh
    # The AppArmor and kernel module tasks run here instead of on the Lima VM, so undo them too.
    for p in cks-deny-write cks-nginx m2-readonly-html; do
      grep -q "^$p " /sys/kernel/security/apparmor/profiles 2>/dev/null && printf %s "$p" > /sys/kernel/security/apparmor/.remove
    done
    rm -f /etc/apparmor.d/m2-readonly-html /etc/modprobe.d/cks-*.conf /etc/modprobe.d/m3*.conf'
else
  SSH_UNDO='DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq vsftpd lighttpd openssh-server >/dev/null 2>&1 || true
    rm -rf /etc/ssh/sshd_config.d/10-legacy.conf /etc/ssh/sshd_config.d/05-vendor.conf'
fi

for m in "$W1" "$CP"; do
  echo "=== wiping $m"
  [ "$PRACTICE_PLATFORM" = vms ] || orb start "$m" >/dev/null 2>&1 || true
  on "$m" '
    kubeadm reset -f >/dev/null 2>&1 || true
    rm -rf /etc/cni/net.d/* /var/lib/etcd /var/lib/kubelet/* /etc/kubeadm /root/.kube /var/log/kubernetes
    # kubeadm reset leaves folders it did not create, so the folders the tasks add go too.
    rm -rf /etc/kubernetes/admission /etc/kubernetes/enc /etc/kubernetes/audit /etc/kubernetes/auth
    H=$(getent passwd '"$PRACTICE_NODE_USER"' | cut -d: -f6); rm -rf "$H/.kube"
    iptables-save | grep -v -E "KUBE|cali" | iptables-restore 2>/dev/null || true
    ip link delete tunl0 2>/dev/null || true
    # Undo changes the tasks make on the nodes.
    rm -f /etc/falco/falco_rules.local.yaml /etc/falco/rules.d/cks-*.yaml /etc/falco/rules.d/m2.yaml /etc/falco/rules.d/m3.yaml
    rm -rf /etc/apparmor.d/cks-* /var/lib/kubelet/seccomp/profiles /var/lib/kubelet/seccomp/m3.json
    systemctl is-enabled falco-modern-bpf >/dev/null 2>&1 && systemctl restart falco-modern-bpf || true
    for s in snapd cups apache2 nginx; do systemctl is-enabled "$s" >/dev/null 2>&1 && systemctl disable --now "$s" >/dev/null 2>&1 || true; done
    for u in cks-dev old-admin cks-ops intern; do userdel -r "$u" >/dev/null 2>&1 || true; done
    rm -f /etc/sudoers.d/cks-dev /etc/sudoers.d/intern
    for u in sysmon node-exporter-lite; do systemctl disable --now $u >/dev/null 2>&1 || true; done
    rm -rf /etc/systemd/system/sysmon.service /etc/systemd/system/node-exporter-lite.service /usr/local/lib/.sysmon /opt/.cache/nel /var/backups/k8s; systemctl daemon-reload
    DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq vsftpd lighttpd >/dev/null 2>&1 || true
    '"$SSH_UNDO"'
    rm -rf /opt/cks /opt/cks-check /root/cks /root/mock
  '
done

[ "${1:-}" = --wipe-only ] && exit 0
"$HERE/create.sh"
