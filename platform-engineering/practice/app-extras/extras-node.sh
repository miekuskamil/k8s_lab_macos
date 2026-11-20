#!/usr/bin/env bash
# Runs as root inside one node of the practice cluster; extras.sh sends it there.
#   extras-node.sh cp <cp-ip>   helm, kubectl-convert, podman and a local image registry on cks-cp
#   extras-node.sh w1 <cp-ip>   only the registry's name and the containerd setting on cks-w1
# Safe to run again: every step checks what is already there.
set -euo pipefail

ROLE="${1:?usage: extras-node.sh cp|w1 <cp-ip>}"
CP_IP="${2:?the control plane IP}"
HELM_VERSION="${HELM_VERSION:-4.3.1}"
REGISTRY_VERSION="${REGISTRY_VERSION:-3.1.2}"
K8S_VERSION="${K8S_VERSION:-1.37.1}"
REG=registry.ckad:5000
ARCH="$(dpkg --print-architecture)"   # arm64 on a Mac, amd64 on most VMs
export DEBIAN_FRONTEND=noninteractive
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo "--- the name registry.ckad points to cks-cp ($CP_IP)"
sed -i '/ registry\.ckad$/d' /etc/hosts
echo "$CP_IP registry.ckad" >> /etc/hosts

echo "--- containerd pulls from $REG over plain HTTP"
# containerd 2.x reads per-registry settings from the folder that config_path names.
mkdir -p "/etc/containerd/certs.d/$REG"
cat > "/etc/containerd/certs.d/$REG/hosts.toml" <<EOF
server = "http://$REG"

[host."http://$REG"]
  capabilities = ["pull", "resolve"]
EOF
# kubeadm's node prep writes containerd's default file, which leaves the folder setting empty.
if ! grep -q "config_path = '/etc/containerd/certs.d'" /etc/containerd/config.toml; then
  sed -i "/io.containerd.cri.v1.images'.registry\]/,/config_path/s|config_path = ''|config_path = '/etc/containerd/certs.d'|" /etc/containerd/config.toml
  systemctl restart containerd
fi
grep -q "config_path = '/etc/containerd/certs.d'" /etc/containerd/config.toml || { echo "could not set containerd's config_path"; exit 1; }

[ "$ROLE" = cp ] || { echo "--- done on $(hostname)"; exit 0; }

echo "--- helm $HELM_VERSION"
if ! helm version --short 2>/dev/null | grep -q "v$HELM_VERSION"; then
  curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${ARCH}.tar.gz" | tar -xz -C "$tmp"
  install -m 755 "$tmp/linux-${ARCH}/helm" /usr/local/bin/helm
fi
grep -q "helm completion bash" /etc/bash.bashrc || echo 'source <(helm completion bash)' >> /etc/bash.bashrc

echo "--- kubectl-convert $K8S_VERSION"
if [ ! -x /usr/local/bin/kubectl-convert ]; then
  curl -fsSL -o /usr/local/bin/kubectl-convert "https://dl.k8s.io/release/v${K8S_VERSION}/bin/linux/${ARCH}/kubectl-convert"
  chmod 755 /usr/local/bin/kubectl-convert
fi

echo "--- podman (Ubuntu's package) to build and push images"
command -v podman >/dev/null || apt-get install -y -qq podman >/dev/null
mkdir -p /etc/containers/registries.conf.d
cat > /etc/containers/registries.conf.d/50-ckad.conf <<EOF
unqualified-search-registries = ["docker.io"]

[[registry]]
location = "$REG"
insecure = true
EOF

echo "--- registry $REGISTRY_VERSION on port 5000, as the systemd service ckad-registry"
if ! /usr/local/bin/registry --version 2>/dev/null | grep -q "v$REGISTRY_VERSION"; then
  curl -fsSL "https://github.com/distribution/distribution/releases/download/v${REGISTRY_VERSION}/registry_${REGISTRY_VERSION}_linux_${ARCH}.tar.gz" | tar -xz -C "$tmp"
  install -m 755 "$tmp/registry" /usr/local/bin/registry
fi
mkdir -p /etc/ckad-registry /var/lib/ckad-registry
cat > /etc/ckad-registry/config.yml <<'EOF'
version: 0.1
log:
  level: warn
storage:
  filesystem:
    rootdirectory: /var/lib/ckad-registry
  delete:
    enabled: true
http:
  addr: :5000
EOF
cat > /etc/systemd/system/ckad-registry.service <<'EOF'
[Unit]
Description=Local image registry for the CKAD track (registry.ckad:5000)
After=network-online.target

[Service]
ExecStart=/usr/local/bin/registry serve /etc/ckad-registry/config.yml
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now ckad-registry >/dev/null 2>&1
systemctl restart ckad-registry
for i in $(seq 1 20); do curl -fsS "http://$REG/v2/" >/dev/null 2>&1 && break; sleep 1; done

echo "--- done on $(hostname): $(helm version --short), $(podman --version), registry $(registry --version | awk '{print $3}'), kubectl-convert $(test -x /usr/local/bin/kubectl-convert && echo present)"
curl -fsS "http://$REG/v2/_catalog"
