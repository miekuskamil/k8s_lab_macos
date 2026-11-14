#!/usr/bin/env bash
# Runs as root inside one OrbStack machine. Installs containerd, runc,
# the CNI plugins, and kubeadm, kubelet and kubectl at one pinned version.
# create.sh copies it in and runs it on every node.
set -euo pipefail

K8S_VERSION="${K8S_VERSION:-1.37.1}"        # the cluster starts here; 02-cluster-hardening upgrades it
CONTAINERD_VERSION="${CONTAINERD_VERSION:-2.2.10}"
RUNC_VERSION="${RUNC_VERSION:-1.5.2}"
CNI_VERSION="${CNI_VERSION:-1.9.1}"
K8S_MINOR="${K8S_VERSION%.*}"
ARCH=arm64
export DEBIAN_FRONTEND=noninteractive

echo "--- packages"
apt-get update -qq
apt-get install -y -qq curl gpg bzip2 ca-certificates apt-transport-https jq vim \
  apparmor apparmor-utils auditd conntrack socat ebtables ethtool >/dev/null

echo "--- kernel settings"
# OrbStack's kernel has br_netfilter and overlay built in, so there is nothing to modprobe.
cat > /etc/sysctl.d/99-kubernetes.conf <<'EOF'
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system >/dev/null

echo "--- containerd $CONTAINERD_VERSION, runc $RUNC_VERSION, CNI plugins $CNI_VERSION"
if ! /usr/local/bin/containerd --version 2>/dev/null | grep -q "v$CONTAINERD_VERSION"; then
  curl -fsSL "https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${ARCH}.tar.gz" \
    | tar -xz -C /usr/local
  curl -fsSL -o /etc/systemd/system/containerd.service \
    https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
fi
curl -fsSL -o /usr/local/sbin/runc "https://github.com/opencontainers/runc/releases/download/v${RUNC_VERSION}/runc.${ARCH}"
chmod 755 /usr/local/sbin/runc
mkdir -p /opt/cni/bin /etc/cni/net.d
curl -fsSL "https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_VERSION}.tgz" \
  | tar -xz -C /opt/cni/bin

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml
# The kubelet and containerd must agree on the cgroup driver. systemd owns cgroups here.
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
if ! grep -q 'SystemdCgroup = true' /etc/containerd/config.toml; then
  # containerd 2.x leaves the option out of the default file; add it under the runc options.
  sed -i "/plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options\]/a\            SystemdCgroup = true" /etc/containerd/config.toml
fi
systemctl daemon-reload
systemctl enable --now containerd >/dev/null 2>&1
systemctl restart containerd

echo "--- kubeadm, kubelet, kubectl $K8S_VERSION"
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
apt-mark unhold kubelet kubeadm kubectl >/dev/null 2>&1 || true
apt-get install -y -qq --allow-downgrades \
  "kubelet=${K8S_VERSION}-*" "kubeadm=${K8S_VERSION}-*" "kubectl=${K8S_VERSION}-*" cri-tools >/dev/null
apt-mark hold kubelet kubeadm kubectl >/dev/null
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\n' > /etc/crictl.yaml
systemctl enable kubelet >/dev/null 2>&1

echo "--- done on $(hostname): $(kubeadm version -o short), $(containerd --version | awk '{print $3}')"
