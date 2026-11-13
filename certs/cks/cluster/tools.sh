#!/usr/bin/env bash
# Runs as root inside one node. Installs the security tools the CKS tasks use.
#   tools.sh cp   etcdctl, trivy, kube-bench, kubesec, bom and the image policy back end on the control plane
#   tools.sh w1   gVisor (runsc) and Falco on the worker, where the workloads run
set -euo pipefail

ROLE="${1:?usage: tools.sh cp|w1}"
ETCD_VERSION="${ETCD_VERSION:-3.7.0}"      # matches the etcd image kubeadm 1.37 runs
TRIVY_VERSION="${TRIVY_VERSION:-0.76.1}"
KUBE_BENCH_VERSION="${KUBE_BENCH_VERSION:-0.16.0}"
KUBESEC_VERSION="${KUBESEC_VERSION:-2.15.0}"
BOM_VERSION="${BOM_VERSION:-0.8.0}"
GVISOR_RELEASE="${GVISOR_RELEASE:-20261026}"
FALCO_VERSION="${FALCO_VERSION:-0.45.1}"
export DEBIAN_FRONTEND=noninteractive
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

if [ "$ROLE" = cp ]; then
  echo "--- etcdctl $ETCD_VERSION"
  curl -fsSL "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-arm64.tar.gz" \
    | tar -xz -C "$tmp"
  install -m 755 "$tmp/etcd-v${ETCD_VERSION}-linux-arm64/etcdctl" "$tmp/etcd-v${ETCD_VERSION}-linux-arm64/etcdutl" /usr/local/bin/

  echo "--- trivy $TRIVY_VERSION"
  curl -fsSL -o "$tmp/trivy.deb" "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-ARM64.deb"
  dpkg -i "$tmp/trivy.deb" >/dev/null

  echo "--- kube-bench $KUBE_BENCH_VERSION"
  curl -fsSL -o "$tmp/kb.deb" "https://github.com/aquasecurity/kube-bench/releases/download/v${KUBE_BENCH_VERSION}/kube-bench_${KUBE_BENCH_VERSION}_linux_arm64.deb"
  dpkg -i "$tmp/kb.deb" >/dev/null

  echo "--- kubesec $KUBESEC_VERSION"
  curl -fsSL "https://github.com/controlplaneio/kubesec/releases/download/v${KUBESEC_VERSION}/kubesec_linux_arm64.tar.gz" | tar -xz -C "$tmp"
  install -m 755 "$tmp/kubesec" /usr/local/bin/

  echo "--- bom $BOM_VERSION (SBOM generator, its docs are allowed in the exam)"
  curl -fsSL -o /usr/local/bin/bom "https://github.com/kubernetes-sigs/bom/releases/download/v${BOM_VERSION}/bom-arm64-linux"
  chmod 755 /usr/local/bin/bom

  echo "--- image policy webhook back end (for 05-supply-chain-security)"
  bash "$(cd "$(dirname "$0")" && pwd)/image-policy/install.sh"

  echo "--- done: $(etcdctl version | head -1), trivy $(trivy --version | awk 'NR==1{print $2}'), kube-bench $(kube-bench version 2>/dev/null)"
fi

if [ "$ROLE" = w1 ]; then
  echo "--- gVisor release $GVISOR_RELEASE"
  # The tarball holds runsc, the containerd shim, and a gvisor-bin/ folder runsc looks for next to itself.
  curl -fsSL "https://storage.googleapis.com/gvisor/releases/release/${GVISOR_RELEASE}/aarch64/gvisor.tar.bz2" \
    | tar -xj -C /usr/local/bin runsc containerd-shim-runsc-v1 gvisor-bin
  # Tell containerd about a second runtime handler called runsc.
  if ! grep -q "runtimes.runsc\]" /etc/containerd/config.toml; then
    cat >> /etc/containerd/config.toml <<'EOF'

[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
  runtime_type = 'io.containerd.runsc.v1'
EOF
    systemctl restart containerd
  fi

  echo "--- Falco $FALCO_VERSION with the modern eBPF probe"
  curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | gpg --batch --yes --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" \
    > /etc/apt/sources.list.d/falcosecurity.list
  apt-get update -qq
  FALCO_FRONTEND=noninteractive FALCO_DRIVER_CHOICE=modern_ebpf apt-get install -y -qq "falco=${FALCO_VERSION}" >/dev/null
  apt-mark hold falco >/dev/null
  systemctl enable --now falco-modern-bpf.service >/dev/null 2>&1 || true
  echo "--- done: runsc $(runsc --version | awk 'NR==1{print $3}'), $(falco --version | head -1), falco service $(systemctl is-active falco-modern-bpf)"
fi
