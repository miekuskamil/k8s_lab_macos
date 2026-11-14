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

# ---- Task 6: egress to DNS and the API server only --------------------------------------
setup_1_6() {
  oncp <<'EOF'
kubectl create ns egress-lab --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n egress-lab get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n egress-lab delete networkpolicy --all >/dev/null
kubectl -n egress-lab run agent --image=busybox:1.36 -l app=agent -- sleep 1d 2>/dev/null
kubectl -n egress-lab run web --image=nginx:1.27-alpine -l app=web --port 80 --expose 2>/dev/null
kubectl -n egress-lab wait pod --all --for=condition=Ready --timeout=120s
EOF
}
check_1_6() {
  check_cp "NetworkPolicy deny-all-egress selects every pod for Egress and allows nothing" \
    "kubectl -n egress-lab get netpol deny-all-egress -o jsonpath='{.spec.podSelector}{.spec.policyTypes}{.spec.egress}' | grep -Fqx '{}[\"Egress\"]'"
  check_cp "agent resolves kubernetes.default" \
    "kubectl -n egress-lab exec agent -- nslookup -timeout=3 kubernetes.default.svc.cluster.local"
  check_cp "agent reaches the API server through the kubernetes Service" \
    "kubectl -n egress-lab exec agent -- nc -z -w 3 kubernetes.default.svc.cluster.local 443"
  check_cp "agent does not reach web" "! kubectl -n egress-lab exec agent -- wget -qO- -T 3 http://web"
  check_cp "web reaches nothing, not even the API server" \
    "! kubectl -n egress-lab exec web -- nc -z -w 3 10.96.0.1 443"
}
solve_1_6() {
  oncp <<'EOF'
EP=$(kubectl get endpointslice -n default -l kubernetes.io/service-name=kubernetes -o jsonpath='{.items[0].endpoints[0].addresses[0]}')
PORT=$(kubectl get endpointslice -n default -l kubernetes.io/service-name=kubernetes -o jsonpath='{.items[0].ports[0].port}')
echo "API server endpoint: $EP:$PORT"
kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-egress
  namespace: egress-lab
spec:
  podSelector: {}
  policyTypes: [Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: agent-egress
  namespace: egress-lab
spec:
  podSelector:
    matchLabels: {app: agent}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector:
        matchLabels: {kubernetes.io/metadata.name: kube-system}
      podSelector:
        matchLabels: {k8s-app: kube-dns}
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
  - to:
    - ipBlock:
        cidr: $EP/32
    ports:
    - {protocol: TCP, port: $PORT}
YAML
EOF
}

# ---- Task 7: one rule or two ------------------------------------------------------------
setup_1_7() {
  oncp <<'EOF'
for n in team-db team-api team-web; do kubectl create ns $n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done
for n in team-db team-api team-web; do for i in $(seq 1 30); do kubectl -n $n get sa default >/dev/null 2>&1 && break; sleep 1; done; done
kubectl label ns team-api team=api --overwrite >/dev/null
kubectl label ns team-web team=web --overwrite >/dev/null
kubectl -n team-db run db --image=nginx:1.27-alpine -l app=db --port 80 --expose 2>/dev/null
kubectl -n team-api run api --image=busybox:1.36 -l app=api -- sleep 1d 2>/dev/null
kubectl -n team-api run debug --image=busybox:1.36 -l app=debug -- sleep 1d 2>/dev/null
kubectl -n team-web run api --image=busybox:1.36 -l app=api -- sleep 1d 2>/dev/null
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-ingress
  namespace: team-db
spec:
  podSelector:
    matchLabels: {app: db}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector:
        matchLabels: {team: api}
    - podSelector:
        matchLabels: {app: api}
    ports:
    - {protocol: TCP, port: 80}
YAML
for n in team-db team-api team-web; do kubectl -n $n wait pod --all --for=condition=Ready --timeout=120s >/dev/null; done
echo "  db-ingress is in place; debug in team-api reaches db: $(kubectl -n team-api exec debug -- wget -qO- -T 3 http://db.team-db >/dev/null 2>&1 && echo yes || echo no)"
EOF
}
check_1_7() {
  check_cp "NetworkPolicy db-ingress still exists" "kubectl -n team-db get netpol db-ingress"
  check_cp "api in team-api reaches db" "kubectl -n team-api exec api -- wget -qO- -T 3 http://db.team-db"
  check_cp "debug in team-api does not reach db" "! kubectl -n team-api exec debug -- wget -qO- -T 3 http://db.team-db"
  check_cp "api in team-web does not reach db" "! kubectl -n team-web exec api -- wget -qO- -T 3 http://db.team-db"
}
solve_1_7() {
  oncp <<'EOF'
kubectl -n team-db patch netpol db-ingress --type=json -p='[{"op":"replace","path":"/spec/ingress/0/from","value":[
  {"namespaceSelector":{"matchLabels":{"team":"api"}},"podSelector":{"matchLabels":{"app":"api"}}}]}]'
EOF
}

# ---- Task 8: a port range ---------------------------------------------------------------
setup_1_8() {
  oncp <<'EOF'
kubectl create ns ports --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n ports get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n ports delete networkpolicy --all >/dev/null
kubectl -n ports run server --image=busybox:1.36 -l app=server -- sh -c 'mkdir -p /www && echo ok > /www/index.html; for p in 7000 7050 7100 8000; do httpd -f -p $p -h /www & done; wait' 2>/dev/null
kubectl -n ports run client --image=busybox:1.36 -l app=client -- sleep 1d 2>/dev/null
kubectl -n ports wait pod --all --for=condition=Ready --timeout=120s
EOF
}
srv_ip() { k -n ports get pod server -o jsonpath='{.status.podIP}'; }
check_1_8() {
  local ip; ip="$(srv_ip)"
  check_cp "NetworkPolicy server-ports opens one port entry, 7000 to 7100 with endPort" \
    "kubectl -n ports get netpol server-ports -o jsonpath='{.spec.ingress[*].ports[*].port}-{.spec.ingress[*].ports[*].endPort}' | grep -qx '7000-7100'"
  check_cp "client reaches server on 7000, 7050 and 7100" \
    "for p in 7000 7050 7100; do kubectl -n ports exec client -- wget -qO- -T 3 http://$ip:\$p/ || exit 1; done"
  check_cp "client does not reach server on 8000" "! kubectl -n ports exec client -- wget -qO- -T 3 http://$ip:8000/"
}
solve_1_8() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: server-ports
  namespace: ports
spec:
  podSelector:
    matchLabels: {app: server}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: {}
    ports:
    - {protocol: TCP, port: 7000, endPort: 7100}
YAML
EOF
}

# ---- Task 9: a CiliumNetworkPolicy at layers 3 and 4 (Lima) ------------------------------
setup_1_9() {
  need_lima || return 1
  onlima <<'EOF'
kubectl create ns cilium-l4 --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n cilium-l4 get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n cilium-l4 delete cnp --all >/dev/null 2>&1
kubectl -n cilium-l4 run backend --image=nginx:1.27-alpine -l app=backend --port 80 --expose 2>/dev/null
kubectl -n cilium-l4 run frontend --image=busybox:1.36 -l app=frontend -- sleep 1d 2>/dev/null
kubectl -n cilium-l4 run other --image=busybox:1.36 -l app=other -- sleep 1d 2>/dev/null
kubectl -n cilium-l4 wait pod --all --for=condition=Ready --timeout=180s
EOF
}
check_1_9() {
  check_lima "CiliumNetworkPolicy backend-ingress selects app=backend and opens only TCP 80" \
    "kubectl -n cilium-l4 get cnp backend-ingress -o jsonpath='{.spec.endpointSelector.matchLabels.app}/{.spec.ingress[*].toPorts[*].ports[*].port}' | grep -qx backend/80"
  check_lima "frontend reaches backend on port 80" "kubectl -n cilium-l4 exec frontend -- wget -qO- -T 3 http://backend"
  check_lima "other does not reach backend" "! kubectl -n cilium-l4 exec other -- wget -qO- -T 3 http://backend"
}
solve_1_9() {
  need_lima || return 1
  onlima <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: backend-ingress
  namespace: cilium-l4
spec:
  endpointSelector:
    matchLabels: {app: backend}
  ingress:
  - fromEndpoints:
    - matchLabels: {app: frontend}
    toPorts:
    - ports:
      - {port: "80", protocol: TCP}
YAML
EOF
}

# ---- Task 10: an HTTP rule with Cilium (Lima) ---------------------------------------------
setup_1_10() {
  need_lima || return 1
  onlima <<'EOF'
kubectl create ns cilium-l7 --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n cilium-l7 get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n cilium-l7 delete cnp --all >/dev/null 2>&1
kubectl -n cilium-l7 run api --image=nginx:1.27-alpine -l app=api --port 80 --expose --command -- sh -c \
  'for d in public admin; do mkdir -p /usr/share/nginx/html/$d && echo $d > /usr/share/nginx/html/$d/index.html; done; exec nginx -g "daemon off;"' 2>/dev/null
kubectl -n cilium-l7 run client --image=busybox:1.36 -l app=client -- sleep 1d 2>/dev/null
kubectl -n cilium-l7 run other --image=busybox:1.36 -l app=other -- sleep 1d 2>/dev/null
kubectl -n cilium-l7 wait pod --all --for=condition=Ready --timeout=180s
EOF
}
# wget in busybox prints "server returned error: HTTP/1.1 403 Forbidden" on a refusal.
check_1_10() {
  check_lima "CiliumNetworkPolicy api-l7 has an HTTP rule" \
    "kubectl -n cilium-l7 get cnp api-l7 -o jsonpath='{.spec.ingress[*].toPorts[*].rules.http}' | grep -q path"
  check_lima "client gets /public/ with GET" "kubectl -n cilium-l7 exec client -- wget -qO- -T 5 http://api/public/ | grep -qx public"
  check_lima "client gets 403 for /admin/" "kubectl -n cilium-l7 exec client -- wget -qO- -T 5 http://api/admin/ 2>&1 | grep -q 403"
  check_lima "client gets 403 for a POST to /public/" "kubectl -n cilium-l7 exec client -- wget -qO- -T 5 --post-data=x http://api/public/ 2>&1 | grep -q 403"
  check_lima "other does not reach api at all" "! kubectl -n cilium-l7 exec other -- wget -qO- -T 3 http://api/public/"
}
solve_1_10() {
  need_lima || return 1
  onlima <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-l7
  namespace: cilium-l7
spec:
  endpointSelector:
    matchLabels: {app: api}
  ingress:
  - fromEndpoints:
    - matchLabels: {app: client}
    toPorts:
    - ports:
      - {port: "80", protocol: TCP}
      rules:
        http:
        - method: GET
          path: "/public/.*"
YAML
EOF
}

# ---- Task 11: entities and an explicit deny with Cilium (Lima) ---------------------------
setup_1_11() {
  need_lima || return 1
  onlima <<'EOF'
kubectl create ns cilium-egress --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n cilium-egress get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n cilium-egress delete cnp --all >/dev/null 2>&1
kubectl -n cilium-egress run agent --image=busybox:1.36 -l app=agent -- sleep 1d 2>/dev/null
kubectl -n cilium-egress run web --image=nginx:1.27-alpine -l app=web --port 80 --expose 2>/dev/null
kubectl -n cilium-egress wait pod --all --for=condition=Ready --timeout=180s
echo "  web reaches 1.1.1.1:443 before any policy: $(kubectl -n cilium-egress exec web -- nc -z -w 3 1.1.1.1 443 && echo yes || echo no)"
EOF
}
check_1_11() {
  check_lima "CiliumNetworkPolicy deny-world denies egress to the world entity for every pod" \
    "kubectl -n cilium-egress get cnp deny-world -o jsonpath='{.spec.endpointSelector}{.spec.egressDeny[*].toEntities[*]}' | grep -Fqx '{}world'"
  check_lima "CiliumNetworkPolicy agent-egress uses the kube-apiserver entity" \
    "kubectl -n cilium-egress get cnp agent-egress -o jsonpath='{.spec.egress[*].toEntities[*]}' | grep -qw kube-apiserver"
  check_lima "agent resolves names and reaches the API server" \
    "kubectl -n cilium-egress exec agent -- nc -z -w 3 kubernetes.default.svc.cluster.local 443"
  check_lima "agent does not reach web" "! kubectl -n cilium-egress exec agent -- wget -qO- -T 3 http://web"
  check_lima "web reaches nothing outside the cluster" "! kubectl -n cilium-egress exec web -- nc -z -w 3 1.1.1.1 443"
}
solve_1_11() {
  need_lima || return 1
  onlima <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: deny-world
  namespace: cilium-egress
spec:
  endpointSelector: {}
  egressDeny:
  - toEntities: [world]
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: agent-egress
  namespace: cilium-egress
spec:
  endpointSelector:
    matchLabels: {app: agent}
  egress:
  - toEntities: [kube-apiserver]
  - toEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: kube-system
        k8s-app: kube-dns
    toPorts:
    - ports:
      - {port: "53", protocol: ANY}
YAML
EOF
}

# ---- Task 12: TLS versions and ciphers for the API server and etcd -----------------------
API_CIPHERS=TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
setup_1_12() {
  cp_sh 'grep -E -- "--tls-|--cipher-suites" /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/etcd.yaml || echo "  no TLS flags set yet"
    echo | openssl s_client -connect 127.0.0.1:6443 -tls1_2 -cipher ECDHE-RSA-CHACHA20-POLY1305 2>/dev/null | grep -m1 "Cipher is"'
}
# tls_ok PORT "openssl options": the handshake succeeds.
tls_ok() { cp_sh "echo | timeout 5 openssl s_client -connect 127.0.0.1:$1 $2 2>/dev/null | grep -q 'Cipher is [A-Z]'"; }
tls_refused() { ! tls_ok "$@"; }
check_1_12() {
  check_cp "the API server sets --tls-min-version=VersionTLS12 and the two cipher suites" \
    "grep -q -- '--tls-min-version=VersionTLS12' /etc/kubernetes/manifests/kube-apiserver.yaml && grep -q -- '--tls-cipher-suites=$API_CIPHERS' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check "the API server accepts ECDHE-RSA-AES128-GCM-SHA256 on TLS 1.2" tls_ok 6443 "-tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256"
  check "the API server refuses ECDHE-RSA-CHACHA20-POLY1305 on TLS 1.2" tls_refused 6443 "-tls1_2 -cipher ECDHE-RSA-CHACHA20-POLY1305"
  check_cp "etcd sets --tls-min-version=TLS1.3" "grep -q -- '--tls-min-version=TLS1.3' /etc/kubernetes/manifests/etcd.yaml"
  check "etcd refuses TLS 1.2 on 2379" tls_refused 2379 "-tls1_2"
  check "etcd accepts TLS 1.3 on 2379" tls_ok 2379 "-tls1_3"
  check_cp "the API server and etcd pods are Ready" \
    "kubectl -n kube-system wait pod -l 'component in (kube-apiserver,etcd)' --for=condition=Ready --timeout=60s"
}
solve_1_12() {
  cp_sh 'cp /etc/kubernetes/manifests/kube-apiserver.yaml /etc/kubernetes/manifests/etcd.yaml /root/'
  set_flag etcd --tls-min-version TLS1.3
  sleep 5; wait_api
  set_flag kube-apiserver --tls-min-version VersionTLS12
  set_flag kube-apiserver --tls-cipher-suites "$API_CIPHERS"
  sleep 5; wait_api
  wait_static etcd; wait_static kube-apiserver
}

# ---- Task 13: harden the kubelet on cks-w1 -----------------------------------------------
setup_1_13() {
  onw1 <<'EOF'
f=/var/lib/kubelet/config.yaml
[ -f /root/kubelet-config.yaml.orig ] || cp $f /root/kubelet-config.yaml.orig
python3 - "$f" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(anonymous:\n\s+enabled:) false", r"\1 true", s)
s = re.sub(r"(authorization:\n\s+mode:) Webhook", r"\1 AlwaysAllow", s)
s = re.sub(r"\nreadOnlyPort: .*", "", s).rstrip("\n") + "\nreadOnlyPort: 10255\n"
open(p, "w").write(s)
PY
systemctl restart kubelet
for i in $(seq 1 30); do curl -s -o /dev/null http://127.0.0.1:10255/healthz && break; sleep 2; done
echo "  read-only port /pods: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:10255/pods)"
echo "  anonymous /pods on 10250: $(curl -sk -o /dev/null -w '%{http_code}' https://127.0.0.1:10250/pods)"
EOF
}
check_1_13() {
  check_w1 "nothing answers on the read-only port 10255" "! curl -s -m 3 -o /dev/null http://127.0.0.1:10255/pods"
  check_w1 "an anonymous request to the kubelet API gets 401" \
    "curl -sk -m 3 -o /dev/null -w '%{http_code}' https://127.0.0.1:10250/pods | grep -qx 401"
  check_w1 "the kubelet config sets authorization mode Webhook" \
    "grep -A1 '^authorization:' /var/lib/kubelet/config.yaml | grep -q 'mode: Webhook'"
  check_w1 "the kubelet refuses TLS 1.2" "! echo | timeout 5 openssl s_client -connect 127.0.0.1:10250 -tls1_2 2>/dev/null | grep -q 'Cipher is [A-Z]'"
  check_cp "cks-w1 is Ready and kubectl logs still works for its pods" \
    "kubectl wait node cks-w1 --for=condition=Ready --timeout=60s && kubectl -n kube-system logs \$(kubectl -n kube-system get pod -l k8s-app=calico-node --field-selector spec.nodeName=cks-w1 -o name) --tail=1"
}
solve_1_13() {
  onw1 <<'EOF'
f=/var/lib/kubelet/config.yaml
cp $f /root/kubelet-config.yaml.bak
python3 - "$f" <<'PY'
import sys, re
p = sys.argv[1]; s = open(p).read()
s = re.sub(r"(anonymous:\n\s+enabled:) true", r"\1 false", s)
s = re.sub(r"(authorization:\n\s+mode:) AlwaysAllow", r"\1 Webhook", s)
s = re.sub(r"\nreadOnlyPort: .*", "", s)
s = re.sub(r"\ntlsMinVersion: .*", "", s).rstrip("\n") + "\nreadOnlyPort: 0\ntlsMinVersion: VersionTLS13\n"
open(p, "w").write(s)
PY
systemctl restart kubelet
for i in $(seq 1 30); do curl -sk -o /dev/null https://127.0.0.1:10250/healthz && break; sleep 2; done
grep -E -A2 '^(authentication|authorization):' $f | head -8; grep -E 'readOnlyPort|tlsMinVersion' $f
EOF
}
