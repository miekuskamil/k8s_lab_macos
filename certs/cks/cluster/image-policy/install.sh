#!/usr/bin/env bash
# Runs as root on cks-cp. Installs the image policy back end as a systemd service,
# with its own CA and a server certificate for "localhost", and writes the kubeconfig
# the API server needs to reach it. It doesn't switch the API server over: that is the task.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CONF=/etc/image-policy
mkdir -p "$CONF"
install -m 755 "$HERE/server.py" /usr/local/bin/image-policy-server.py

if [ ! -f "$CONF/server.crt" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=image-policy-ca" \
    -keyout "$CONF/ca.key" -out "$CONF/ca.crt" 2>/dev/null
  openssl req -newkey rsa:2048 -nodes -subj "/CN=localhost" \
    -keyout "$CONF/server.key" -out "$CONF/server.csr" 2>/dev/null
  printf 'subjectAltName=DNS:localhost,IP:127.0.0.1\n' > "$CONF/san.ext"
  openssl x509 -req -in "$CONF/server.csr" -CA "$CONF/ca.crt" -CAkey "$CONF/ca.key" -CAcreateserial \
    -days 3650 -extfile "$CONF/san.ext" -out "$CONF/server.crt" 2>/dev/null
fi
[ -f "$CONF/allowed-registries" ] || printf 'registry.k8s.io/\ndocker.io/library/\nquay.io/calico/\n' > "$CONF/allowed-registries"

cat > /etc/systemd/system/image-policy.service <<'EOF'
[Unit]
Description=ImagePolicyWebhook back end for the CKS practice cluster
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 /usr/local/bin/image-policy-server.py 8443
Restart=always

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now image-policy >/dev/null 2>&1
systemctl restart image-policy

# The API server reads this kubeconfig: "cluster" is the webhook, "user" is how the API server logs in.
mkdir -p /etc/kubernetes/policy-webhook
cp "$CONF/ca.crt" /etc/kubernetes/policy-webhook/ca.crt
cat > /etc/kubernetes/policy-webhook/kubeconfig.yaml <<'EOF'
apiVersion: v1
kind: Config
clusters:
- name: image-policy
  cluster:
    certificate-authority: /etc/kubernetes/policy-webhook/ca.crt
    server: https://localhost:8443/review
users:
- name: api-server
  user: {}
contexts:
- name: default
  context: {cluster: image-policy, user: api-server}
current-context: default
EOF
echo "image-policy: $(systemctl is-active image-policy), allowed: $(paste -sd' ' "$CONF/allowed-registries")"
