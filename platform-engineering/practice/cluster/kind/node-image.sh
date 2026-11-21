#!/usr/bin/env bash
# Runs once, inside "docker build", to turn the kind node image into the practice node image.
# Every tool the tasks use goes into the image here, so a new cluster starts in about two minutes
# and needs nothing from the internet but the Kubernetes images. The versions match the ones
# tools.sh, node-prep.sh and app-extras/extras-node.sh install on OrbStack machines and VMs.
set -euo pipefail

K8S_VERSION="${K8S_VERSION:?}"
ETCD_VERSION="${ETCD_VERSION:?}"
TRIVY_VERSION="${TRIVY_VERSION:?}"
KUBE_BENCH_VERSION="${KUBE_BENCH_VERSION:?}"
KUBESEC_VERSION="${KUBESEC_VERSION:?}"
BOM_VERSION="${BOM_VERSION:?}"
GVISOR_RELEASE="${GVISOR_RELEASE:?}"
FALCO_VERSION="${FALCO_VERSION:?}"
HELM_VERSION="${HELM_VERSION:?}"
K8S_MINOR="${K8S_VERSION%.*}"
ARCH="$(dpkg --print-architecture)"   # arm64 on an Apple silicon Mac, amd64 on most PCs
export DEBIAN_FRONTEND=noninteractive
tmp="$(mktemp -d)"

echo "--- Debian packages the tasks and their checks use"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  python3 python3-yaml vim less procps psmisc iproute2 iputils-ping netcat-openbsd dnsutils openssl ca-certificates \
  curl gpg bzip2 jq bash-completion sudo file passwd login socat conntrack ethtool podman >/dev/null

echo "--- kubeadm, kubelet and kubectl $K8S_VERSION from pkgs.k8s.io, held like on a kubeadm node"
# The kind image carries v1.37.0 binaries without a package manager entry. The packages replace
# them at /usr/bin, and apt then upgrades them the same way it does on an exam node (module 39).
mkdir -p /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/Release.key" \
  | gpg --batch --yes --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_MINOR}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq
# kind's own kubelet unit files stay (confold), because they set the node up for life in a container.
apt-get install -y -qq --no-install-recommends -o Dpkg::Options::=--force-confold \
  "kubelet=${K8S_VERSION}-*" "kubeadm=${K8S_VERSION}-*" "kubectl=${K8S_VERSION}-*" >/dev/null
apt-mark hold kubelet kubeadm kubectl >/dev/null
# kind reads this file to choose the Kubernetes version it asks kubeadm for.
echo "v${K8S_VERSION}" > /kind/version
# The package drops its own kubelet unit under /usr/lib; kind's unit in /etc keeps priority.

echo "--- etcdctl $ETCD_VERSION"
curl -fsSL "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C "$tmp"
install -m 755 "$tmp/etcd-v${ETCD_VERSION}-linux-${ARCH}/etcdctl" "$tmp/etcd-v${ETCD_VERSION}-linux-${ARCH}/etcdutl" /usr/local/bin/

echo "--- trivy $TRIVY_VERSION"
curl -fsSL -o "$tmp/trivy.deb" "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-$([ "$ARCH" = arm64 ] && echo ARM64 || echo 64bit).deb"
dpkg -i "$tmp/trivy.deb" >/dev/null

echo "--- kube-bench $KUBE_BENCH_VERSION"
curl -fsSL -o "$tmp/kb.deb" "https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_linux_${ARCH}.deb"
dpkg -i "$tmp/kb.deb" >/dev/null

echo "--- kubesec $KUBESEC_VERSION"
curl -fsSL "https://github.com/controlplaneio/kubesec/releases/download/v${KUBESEC_VERSION}/kubesec_linux_${ARCH}.tar.gz" | tar -xz -C "$tmp"
install -m 755 "$tmp/kubesec" /usr/local/bin/

echo "--- bom $BOM_VERSION"
curl -fsSL -o /usr/local/bin/bom "https://github.com/kubernetes-sigs/bom/releases/download/v${BOM_VERSION}/bom-${ARCH}-linux"
chmod 755 /usr/local/bin/bom

echo "--- helm $HELM_VERSION and kubectl-convert $K8S_VERSION"
curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C "$tmp"
install -m 755 "$tmp/linux-${ARCH}/helm" /usr/local/bin/helm
curl -fsSL -o /usr/local/bin/kubectl-convert "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/${ARCH}/kubectl-convert"
chmod 755 /usr/local/bin/kubectl-convert

echo "--- gVisor release $GVISOR_RELEASE (create.sh registers it with containerd on the worker only)"
curl -fsSL "https://storage.googleapis.com/gvisor/releases/release/${GVISOR_RELEASE}/$(uname -m)/gvisor.tar.bz2" \
  | tar -xj -C /usr/local/bin runsc containerd-shim-runsc-v1 gvisor-bin

echo "--- Falco $FALCO_VERSION (create.sh starts it on the worker only)"
curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | gpg --batch --yes --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
  > /etc/apt/sources.list.d/falcosecurity.list
apt-get update -qq
FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=none apt-get install -y -qq --no-install-recommends "falco=${FALCO_VERSION}" >/dev/null
apt-mark hold falco >/dev/null
# The worker runs the modern eBPF probe, which ships inside the falco binary and needs no driver build.
for u in falco-kmod falco-bpf falco-modern-bpf falco-custom falcoctl-artifact-follow; do systemctl disable "$u" >/dev/null 2>&1 || true; done

echo "--- podman: pushes to the plain HTTP registry, keeps its images on the node's /var"
mkdir -p /etc/containers/registries.conf.d
cat > /etc/containers/registries.conf.d/50-practice.conf <<'EOF'
unqualified-search-registries = ["docker.io"]

[[registry]]
location = "registry.practice:5000"
insecure = true
EOF

# Debian's podman package drops a bridge network into /etc/cni/net.d, where containerd would find it
# before Calico's and give pods addresses on a network nothing routes. podman itself uses netavark.
rm -f /etc/cni/net.d/87-podman-bridge.conflist
# A kind node runs systemd without D-Bus, so podman manages the cgroups of its build containers itself.
mkdir -p /etc/containers/containers.conf.d
printf '[engine]\ncgroup_manager = "cgroupfs"\nevents_logger = "file"\n' > /etc/containers/containers.conf.d/50-practice.conf

echo "--- containerd pulls from registry.practice:5000 over plain HTTP"
mkdir -p /etc/containerd/certs.d/registry.practice:5000
cat > /etc/containerd/certs.d/registry.practice:5000/hosts.toml <<'EOF'
server = "http://registry.practice:5000"

[host."http://registry.practice:5000"]
  capabilities = ["pull", "resolve"]
EOF

echo "--- shell setup: kubectl alias and completion, like on an exam node"
cat >> /etc/bash.bashrc <<'EOF'
alias k=kubectl
source <(kubectl completion bash)
complete -o default -F __start_kubectl k
source <(helm completion bash)
export do="--dry-run=client -o yaml"
EOF
printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\n' > /etc/crictl.yaml

# The package lists stay, so "apt-get install kubeadm=1.37.2-1.1" finds the package without an
# "apt-get update" first, as in module 39. Package upgrades keep the node's changed config files.
printf 'Dpkg::Options {"--force-confdef";"--force-confold";};\n' > /etc/apt/apt.conf.d/90-practice
apt-get clean
rm -rf "$tmp" /root/.cache
echo "--- done: $(kubeadm version -o short), $(etcdctl version | head -1), trivy $(trivy --version | awk 'NR==1{print $2}'), $(helm version --short), $(podman --version), runsc $(runsc --version | awk 'NR==1{print $3}'), $(falco --version | head -1)"
