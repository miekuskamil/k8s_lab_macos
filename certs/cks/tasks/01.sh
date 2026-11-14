# Domain 01, cluster setup. Functions for task.sh: setup_1_N, check_1_N, solve_1_N.

# ---- Task 1: default-deny and one allowed path ---------------------------------------
setup_1_1() {
  oncp <<'EOF'
kubectl create ns team-app --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n team-app get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n team-app delete networkpolicy --all >/dev/null
kubectl -n team-app run frontend --image=busybox:1.36 -l app=frontend -- sleep 1d 2>/dev/null
kubectl -n team-app run api --image=nginx:1.27-alpine -l app=api --port 80 --expose 2>/dev/null
kubectl -n team-app run db --image=nginx:1.27-alpine -l app=db --port 80 --expose 2>/dev/null
kubectl -n team-app wait pod --all --for=condition=Ready --timeout=120s
EOF
}
check_1_1() {
  check_cp "NetworkPolicy default-deny selects every pod, Ingress and Egress" \
    "kubectl -n team-app get netpol default-deny -o jsonpath='{.spec.podSelector}{.spec.policyTypes}' | grep -Fqx '{}[\"Ingress\",\"Egress\"]'"
  check_cp "frontend reaches api on port 80, by name" \
    "kubectl -n team-app exec frontend -- wget -qO- -T 3 http://api"
  check_cp "frontend does not reach db" \
    "! kubectl -n team-app exec frontend -- wget -qO- -T 3 http://db"
  check_cp "db does not reach api" \
    "! kubectl -n team-app exec db -- wget -qO- -T 3 http://api"
}
solve_1_1() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: team-app
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: team-app
spec:
  podSelector:
    matchLabels: {app: api}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels: {app: frontend}
    ports:
    - {protocol: TCP, port: 80}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: team-app
spec:
  podSelector:
    matchLabels: {app: frontend}
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels: {app: api}
    ports:
    - {protocol: TCP, port: 80}
  - to:
    - namespaceSelector:
        matchLabels: {kubernetes.io/metadata.name: kube-system}
      podSelector:
        matchLabels: {k8s-app: kube-dns}
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
YAML
EOF
}

# ---- Task 2: block the node metadata endpoint ----------------------------------------
setup_1_2() {
  oncp <<'EOF'
kubectl create ns batch --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n batch get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n batch delete networkpolicy --all >/dev/null
kubectl -n batch run worker --image=busybox:1.36 -l app=worker -- sleep 1d 2>/dev/null
kubectl -n batch wait pod worker --for=condition=Ready --timeout=120s
EOF
}
check_1_2() {
  check_cp "NetworkPolicy deny-metadata exists and selects every pod" \
    "kubectl -n batch get netpol deny-metadata -o jsonpath='{.spec.podSelector}' | grep -Fqx '{}'"
  check_cp "it allows 0.0.0.0/0 except 169.254.169.254/32" \
    "kubectl -n batch get netpol deny-metadata -o jsonpath='{.spec.egress[*].to[*].ipBlock.cidr}={.spec.egress[*].to[*].ipBlock.except[*]}' | grep -Fqx '0.0.0.0/0=169.254.169.254/32'"
  check_cp "the worker still resolves names and reaches the API server" \
    "kubectl -n batch exec worker -- nc -z -w 3 kubernetes.default.svc.cluster.local 443"
}
solve_1_2() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata
  namespace: batch
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except: [169.254.169.254/32]
YAML
EOF
}

# ---- Task 3: fix CIS findings with kube-bench ----------------------------------------
setup_1_3() {
  echo "  nothing to seed: a fresh kubeadm cluster already fails these checks"
}
check_1_3() {
  local out
  out="$(cp_sh 'kube-bench run --targets master,node --check 1.2.15,1.3.2,1.4.1,4.1.9 2>/dev/null')"
  local cis
  for cis in 1.2.15 1.3.2 1.4.1 4.1.9; do
    check "kube-bench $cis passes" bash -c "printf '%s\n' \"\$1\" | grep -q '^\[PASS\] $cis '" _ "$out"
  done
  check "every control plane pod runs" \
    k -n kube-system wait pod -l tier=control-plane --for=condition=Ready --timeout=60s
}
solve_1_3() {
  oncp <<'EOF'
cp /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/kube-controller-manager.yaml \
   /etc/kubernetes/manifests/kube-scheduler.yaml /root/
sed -i 's|    - kube-apiserver$|    - kube-apiserver\n    - --profiling=false|' /etc/kubernetes/manifests/kube-apiserver.yaml
sed -i 's|    - kube-controller-manager$|    - kube-controller-manager\n    - --profiling=false|' /etc/kubernetes/manifests/kube-controller-manager.yaml
sed -i 's|    - kube-scheduler$|    - kube-scheduler\n    - --profiling=false|' /etc/kubernetes/manifests/kube-scheduler.yaml
chmod 600 /var/lib/kubelet/config.yaml
EOF
  wait_api
  k -n kube-system wait pod -l tier=control-plane --for=condition=Ready --timeout=120s >/dev/null
}

# ---- Task 4: an Ingress with TLS -----------------------------------------------------
setup_1_4() {
  oncp <<'EOF'
kubectl create ns web --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n web get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n web create deploy shop --image=nginx:1.27-alpine --port 80 2>/dev/null
kubectl -n web expose deploy shop --port 80 2>/dev/null
mkdir -p /root/cks
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=shop.cks.local" \
  -addext "subjectAltName=DNS:shop.cks.local" -keyout /root/cks/shop.key -out /root/cks/shop.crt 2>/dev/null
kubectl -n web rollout status deploy shop --timeout=120s
ls -l /root/cks/shop.*
EOF
}
check_1_4() {
  check_cp "Secret shop-tls has type kubernetes.io/tls" \
    "kubectl -n web get secret shop-tls -o jsonpath='{.type}' | grep -qx kubernetes.io/tls"
  # The controller reloads nginx a few seconds after a change, so give it up to 30 seconds.
  check "HTTPS on shop.cks.local:30443 answers 200" \
    cp_sh "for i in \$(seq 1 15); do curl -sk -o /dev/null -w '%{http_code}' --resolve shop.cks.local:30443:127.0.0.1 https://shop.cks.local:30443/ | grep -qx 200 && exit 0; sleep 2; done; exit 1"
  check "the certificate served is CN=shop.cks.local, not the controller's fake one" \
    cp_sh "echo | openssl s_client -connect 127.0.0.1:30443 -servername shop.cks.local 2>/dev/null | openssl x509 -noout -subject | grep -q 'CN *= *shop.cks.local'"
  check "plain HTTP redirects to HTTPS (308)" \
    cp_sh "curl -s -o /dev/null -w '%{http_code}' --resolve shop.cks.local:30080:127.0.0.1 http://shop.cks.local:30080/ | grep -qx 308"
}
solve_1_4() {
  oncp <<'EOF'
kubectl -n web create secret tls shop-tls --cert=/root/cks/shop.crt --key=/root/cks/shop.key
kubectl -n web create ingress shop --class=nginx --rule="shop.cks.local/*=shop:80,tls=shop-tls"
for i in $(seq 1 30); do
  [ "$(curl -sk -o /dev/null -w '%{http_code}' --resolve shop.cks.local:30443:127.0.0.1 https://shop.cks.local:30443/)" = 200 ] && break
  sleep 2
done
EOF
}

# ---- Task 5: verify a platform binary ------------------------------------------------
setup_1_5() {
  oncp <<'EOF'
mkdir -p /opt/cks/bin && cd /opt/cks/bin
for b in kubectl kube-proxy; do
  [ -f "$b" ] || curl -fsSL -o "$b" "https://dl.k8s.io/release/v1.37.1/bin/linux/arm64/$b"
done
chmod 755 kubectl kube-proxy
# Someone "patched" kube-proxy: one extra byte changes the checksum.
tail -c 3 kube-proxy | grep -qa cks || printf 'cks' >> kube-proxy
ls -l /opt/cks/bin
EOF
}
check_1_5() {
  check "the tampered kube-proxy is gone" cp_sh 'test ! -e /opt/cks/bin/kube-proxy'
  check "kubectl stays, and matches the official v1.37.1 sha512" \
    cp_sh 'cd /opt/cks/bin && echo "$(curl -fsSL https://dl.k8s.io/release/v1.37.1/bin/linux/arm64/kubectl.sha512) kubectl" | sha512sum -c'
}
solve_1_5() {
  oncp <<'EOF'
cd /opt/cks/bin
for b in kubectl kube-proxy; do
  echo "$(curl -fsSL https://dl.k8s.io/release/v1.37.1/bin/linux/arm64/$b.sha512) $b" | sha512sum -c || rm -f "$b"
done
EOF
}
