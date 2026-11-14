# CKS mock exam 3: setup_mN seeds task N, score_mN checks it, solve_mN is the reference
# solution. Sourced by setup.sh, score.sh and solve.sh with MOCK=3, after tasks/lib.sh,
# the domain task files and tasks.sh.

MOCK_TASKS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17"
# 11 restarts the API server, so it goes first. 1, 8 and 13 break the control plane, so they go
# last: without a controller manager, new namespaces get no default ServiceAccount and no pods,
# and under AlwaysAllow the kubelet's health probes get 401, so the API server restarts every
# few minutes. Task 1 creates its Deployment before task 8 starts that loop.
MOCK_SETUP_ORDER="11 2 3 4 5 6 7 9 10 12 14 15 16 17 1 8 13"
MOCK_SOLVE_ORDER="13 8 1 11 4 16 2 3 5 6 7 9 10 12 14 15 17"
MOCK_NEEDS_LIMA=yes
mock_points() {
  case "$1" in
    1) echo 8;; 2) echo 5;; 3) echo 6;; 4) echo 6;; 5) echo 4;; 6) echo 6;; 7) echo 5;; 8) echo 5;; 9) echo 4;;
    10) echo 4;; 11) echo 8;; 12) echo 5;; 13) echo 8;; 14) echo 5;; 15) echo 8;; 16) echo 7;; 17) echo 6;;
  esac
}
mock_title() {
  case "$1" in
    1) echo "Pods stay Pending";; 2) echo "One port range, two selectors";; 3) echo "Keep a job off the internet";;
    4) echo "CIS findings and etcd TLS";; 5) echo "An Ingress for two hosts";; 6) echo "A role that grows by itself";;
    7) echo "Old tokens and mounted ones";; 8) echo "Everyone is admin";; 9) echo "SSH the right way";;
    10) echo "Kernel modules nobody needs";; 11) echo "Rotate to a new provider";; 12) echo "gVisor where it exists";;
    13) echo "The API server doesn't start";; 14) echo "Delete what's vulnerable";; 15) echo "Tune Falco and act on it";;
    16) echo "An audit policy for one team";; 17) echo "seccomp and a read-only root";;
  esac
}
# Policies take a few seconds to reach Calico and Cilium, longer right after an API server
# restart, so network checks retry for up to 30 seconds.
eventually() { local i; for i in 1 2 3 4 5 6 7 8 9 10; do "$@" && return 0; sleep 3; done; return 1; }
mk_ns() { cp_sh "for n in $*; do kubectl create ns \$n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done; for n in $*; do for i in \$(seq 1 30); do kubectl -n \$n get sa default >/dev/null 2>&1 && break; sleep 1; done; done"; }
mk_ns_lima() { lima_sh "for n in $*; do kubectl create ns \$n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done; for n in $*; do for i in \$(seq 1 30); do kubectl -n \$n get sa default >/dev/null 2>&1 && break; sleep 1; done; done"; }
M3_ENC=/etc/kubernetes/enc/m3.yaml
M3_ADM=/etc/kubernetes/admission/m3.yaml
M3_LOG=/var/log/kubernetes/audit/m3.log

# ---- 1. Pods stay Pending (8) ----------------------------------------------------------------------------
setup_m1() {
  mk_ns m3-app
  cp_sh 'kubectl -n m3-app create deploy shop --image=nginx:1.27-alpine --replicas=2 2>/dev/null; kubectl -n m3-app rollout status deploy shop --timeout=120s >/dev/null'
  oncp <<'EOF'
sed -i 's|--authentication-kubeconfig=/etc/kubernetes/scheduler.conf|--authentication-kubeconfig=/etc/kubernetes/scheduler.conf\n    - --bind-address=127.0.0.1:10259|' /etc/kubernetes/manifests/kube-scheduler.yaml
sed -i 's|--root-ca-file=/etc/kubernetes/pki/ca.crt|--root-ca-file=/etc/kubernetes/pki/ca.pem|' /etc/kubernetes/manifests/kube-controller-manager.yaml
EOF
}
score_m1() {
  check_cp "Deployment m3-app/shop scaled to 4 has 4 ready pods" \
    "kubectl -n m3-app scale deploy shop --replicas=4 >/dev/null && kubectl -n m3-app rollout status deploy shop --timeout=90s"
  check_cp "kube-scheduler and kube-controller-manager are Ready" \
    "kubectl -n kube-system wait pod kube-scheduler-cks-cp kube-controller-manager-cks-cp --for=condition=Ready --timeout=30s"
  check_cp "the controller manager uses /etc/kubernetes/pki/ca.crt" "grep -q -- '--root-ca-file=/etc/kubernetes/pki/ca.crt\$' /etc/kubernetes/manifests/kube-controller-manager.yaml"
}
solve_m1() {
  oncp <<'EOF'
sed -i '/--bind-address=127.0.0.1:10259/d' /etc/kubernetes/manifests/kube-scheduler.yaml
sed -i 's|pki/ca.pem$|pki/ca.crt|' /etc/kubernetes/manifests/kube-controller-manager.yaml
EOF
  sleep 5; wait_static kube-scheduler; wait_static kube-controller-manager
}

# ---- 2. One port range, two selectors (5) ------------------------------------------------------------------
setup_m2() {
  mk_ns m3-svc m3-obs m3-other
  oncp <<'EOF'
kubectl label ns m3-obs team=observability --overwrite >/dev/null
kubectl -n m3-svc run metrics --image=busybox:1.36 -l app=metrics -- sh -c 'mkdir -p /w && echo ok > /w/index.html; for p in 9100 9150 9200 9300; do httpd -f -p $p -h /w & done; wait' 2>/dev/null
kubectl -n m3-obs run prometheus --image=busybox:1.36 -l app=prometheus -- sleep 1d 2>/dev/null
kubectl -n m3-obs run grafana --image=busybox:1.36 -l app=grafana -- sleep 1d 2>/dev/null
kubectl -n m3-other run prometheus --image=busybox:1.36 -l app=prometheus -- sleep 1d 2>/dev/null
EOF
}
m3ip() { k -n m3-svc get pod metrics -o jsonpath='{.status.podIP}'; }
score_m2() {
  local ip; ip="$(m3ip)"
  check_cp "NetworkPolicy metrics-scrape selects app=metrics with one range 9100-9200" \
    "kubectl -n m3-svc get netpol metrics-scrape -o jsonpath='{.spec.podSelector.matchLabels.app}/{.spec.ingress[*].ports[*].port}-{.spec.ingress[*].ports[*].endPort}' | grep -qx metrics/9100-9200"
  check "prometheus in m3-obs reaches 9100 and 9200" eventually cp_sh "kubectl -n m3-obs exec prometheus -- wget -qO- -T 3 http://$ip:9100/ && kubectl -n m3-obs exec prometheus -- wget -qO- -T 3 http://$ip:9200/"
  check "prometheus in m3-obs does not reach 9300" eventually cp_sh "! kubectl -n m3-obs exec prometheus -- wget -qO- -T 3 http://$ip:9300/"
  check "grafana in m3-obs and prometheus in m3-other do not reach 9100" eventually cp_sh \
    "! kubectl -n m3-obs exec grafana -- wget -qO- -T 3 http://$ip:9100/ && ! kubectl -n m3-other exec prometheus -- wget -qO- -T 3 http://$ip:9100/"
}
solve_m2() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: metrics-scrape, namespace: m3-svc}
spec:
  podSelector: {matchLabels: {app: metrics}}
  policyTypes: [Ingress]
  ingress:
  - from:
    - namespaceSelector: {matchLabels: {team: observability}}
      podSelector: {matchLabels: {app: prometheus}}
    ports: [{protocol: TCP, port: 9100, endPort: 9200}]
YAML
EOF
}

# ---- 3. Keep a job off the internet (6, Lima) -----------------------------------------------------------------
setup_m3() {
  mk_ns_lima m3-egress
  lima_sh 'kubectl -n m3-egress run job --image=busybox:1.36 -l app=job -- sleep 1d 2>/dev/null; kubectl -n m3-egress run web --image=nginx:1.27-alpine -l app=web --port 80 --expose 2>/dev/null; kubectl -n m3-egress run other --image=nginx:1.27-alpine -l app=other --port 80 --expose 2>/dev/null; true'
}
score_m3() {
  check_lima "CiliumNetworkPolicy no-world denies the world entity to every pod" \
    "kubectl -n m3-egress get cnp no-world -o jsonpath='{.spec.endpointSelector}{.spec.egressDeny[*].toEntities[*]}' | grep -Fqx '{}world'"
  check "job reaches the API server and web by name" eventually lima_sh \
    "kubectl -n m3-egress exec job -- nc -z -w 3 kubernetes.default.svc.cluster.local 443 && kubectl -n m3-egress exec job -- wget -qO- -T 3 http://web >/dev/null"
  check "job does not reach other" eventually lima_sh "! kubectl -n m3-egress exec job -- wget -qO- -T 3 http://other"
  check "job and web do not reach 1.1.1.1:443" eventually lima_sh \
    "! kubectl -n m3-egress exec job -- nc -z -w 3 1.1.1.1 443 && ! kubectl -n m3-egress exec web -- nc -z -w 3 1.1.1.1 443"
}
solve_m3() {
  onlima <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: no-world, namespace: m3-egress}
spec:
  endpointSelector: {}
  egressDeny: [{toEntities: [world]}]
---
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata: {name: job-egress, namespace: m3-egress}
spec:
  endpointSelector: {matchLabels: {app: job}}
  egress:
  - toEntities: [kube-apiserver]
  - toEndpoints: [{matchLabels: {app: web}}]
    toPorts: [{ports: [{port: "80", protocol: TCP}]}]
  - toEndpoints: [{matchLabels: {k8s:io.kubernetes.pod.namespace: kube-system, k8s-app: kube-dns}}]
    toPorts: [{ports: [{port: "53", protocol: ANY}]}]
YAML
EOF
}

# ---- 4. CIS findings and etcd TLS (6) -------------------------------------------------------------------------
setup_m4() { :; }
score_m4() {
  local out
  out="$(cp_sh 'kube-bench run --targets master --check 1.2.15,1.3.2 2>/dev/null')"
  check "kube-bench 1.2.15 (API server profiling) passes" bash -c "printf '%s\n' \"\$1\" | grep -q '^\[PASS\] 1.2.15 '" _ "$out"
  check "kube-bench 1.3.2 (controller manager profiling) passes" bash -c "printf '%s\n' \"\$1\" | grep -q '^\[PASS\] 1.3.2 '" _ "$out"
  check "etcd refuses TLS 1.2" tls_refused 2379 "-tls1_2"
  check_cp "etcd is Ready" "kubectl -n kube-system wait pod -l component=etcd --for=condition=Ready --timeout=60s"
}
solve_m4() {
  set_flag kube-controller-manager --profiling false
  set_flag etcd --tls-min-version TLS1.3
  sleep 5; wait_api
  set_flag kube-apiserver --profiling false
  sleep 5; wait_api; wait_static kube-apiserver; wait_static etcd; wait_static kube-controller-manager
}

# ---- 5. An Ingress for two hosts (4) ----------------------------------------------------------------------------
setup_m5() {
  mk_ns m3-web
  oncp <<'EOF'
kubectl -n m3-web create deploy shop --image=nginx:1.27-alpine --port 80 2>/dev/null
kubectl -n m3-web create deploy blog --image=busybox:1.36 --port 80 -- sh -c 'mkdir -p /w && echo blog > /w/index.html && httpd -f -p 80 -h /w' 2>/dev/null
kubectl -n m3-web expose deploy shop --port 80 2>/dev/null; kubectl -n m3-web expose deploy blog --port 80 2>/dev/null
mkdir -p /root/mock
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=shop.m3.local" -addext "subjectAltName=DNS:shop.m3.local,DNS:blog.m3.local" \
  -keyout /root/mock/m3.key -out /root/mock/m3.crt 2>/dev/null
EOF
}
https_m3() { cp_sh "for i in \$(seq 1 15); do curl -sk --resolve $1:30443:127.0.0.1 https://$1:30443/ | grep -q '$2' && exit 0; sleep 2; done; exit 1"; }
score_m5() {
  check "https://shop.m3.local serves nginx" https_m3 shop.m3.local 'Welcome to nginx'
  check "https://blog.m3.local serves blog" https_m3 blog.m3.local '^blog$'
  check_cp "both hosts get the m3 certificate" \
    "for h in shop.m3.local blog.m3.local; do echo | openssl s_client -connect 127.0.0.1:30443 -servername \$h 2>/dev/null | openssl x509 -noout -subject | grep -q 'shop.m3.local' || exit 1; done"
}
solve_m5() {
  oncp <<'EOF'
kubectl -n m3-web create secret tls m3-tls --cert=/root/mock/m3.crt --key=/root/mock/m3.key
kubectl -n m3-web create ingress sites --class=nginx --rule="shop.m3.local/*=shop:80,tls=m3-tls" --rule="blog.m3.local/*=blog:80,tls=m3-tls"
EOF
}

# ---- 6. A role that grows by itself (6) -------------------------------------------------------------------------
setup_m6() {
  mk_ns m3-ops
  oncp <<'EOF'
kubectl -n m3-ops create sa viewer 2>/dev/null
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: ops-view}
aggregationRule:
  clusterRoleSelectors: [{matchLabels: {rbac.m3/aggregate: "true"}}]
rules: []
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: ops-pods, labels: {rbac.m3/aggregate: "true"}}
rules: [{apiGroups: [""], resources: [pods, pods/log], verbs: [get, list, watch]}]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata: {name: ops-config, labels: {rbac.m3/aggregate: "true"}}
rules: [{apiGroups: [""], resources: [configmaps, secrets], verbs: [get, list]}]
YAML
kubectl create clusterrolebinding ops-view --clusterrole=ops-view --serviceaccount=m3-ops:viewer 2>/dev/null
EOF
}
as_m3v() { k auth can-i "$@" --as=system:serviceaccount:m3-ops:viewer; }
m3_no_secrets() { k get --raw=/readyz >/dev/null 2>&1 && ! as_m3v get secrets -A; }
score_m6() {
  check "viewer may no longer read Secrets" m3_no_secrets
  check "viewer lists Deployments in every namespace" as_m3v list deployments.apps -A
  check "viewer still lists pods and ConfigMaps" bash -c "orb -m $CKS_CP -u root kubectl auth can-i list pods -A --as=system:serviceaccount:m3-ops:viewer && orb -m $CKS_CP -u root kubectl auth can-i list configmaps -A --as=system:serviceaccount:m3-ops:viewer"
  check_cp "ops-view still aggregates" "kubectl get clusterrole ops-view -o jsonpath='{.aggregationRule.clusterRoleSelectors[0].matchLabels}' | grep -q rbac.m3"
}
solve_m6() {
  oncp <<'EOF'
kubectl create clusterrole ops-config --verb=get,list --resource=configmaps --dry-run=client -o json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); d["metadata"]["labels"]={"rbac.m3/aggregate":"true"}; print(json.dumps(d))' | kubectl replace -f -
kubectl create clusterrole ops-deploys --verb=get,list,watch --resource=deployments.apps --dry-run=client -o json \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); d["metadata"]["labels"]={"rbac.m3/aggregate":"true"}; print(json.dumps(d))' | kubectl apply -f -
sleep 2
EOF
}

# ---- 7. Old tokens and mounted ones (5) ---------------------------------------------------------------------------
setup_m7() {
  mk_ns m3-ci
  oncp <<'EOF'
kubectl -n m3-ci create sa builder 2>/dev/null
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Secret
metadata: {name: builder-token, namespace: m3-ci, annotations: {kubernetes.io/service-account.name: builder}}
type: kubernetes.io/service-account-token
---
apiVersion: v1
kind: Pod
metadata: {name: build, namespace: m3-ci}
spec:
  serviceAccountName: builder
  containers: [{name: c, image: busybox:1.36, command: [sleep, 1d]}]
YAML
EOF
}
score_m7() {
  check_cp "no service account token Secret is left in m3-ci" \
    "kubectl -n m3-ci get secrets --field-selector type=kubernetes.io/service-account-token --no-headers 2>&1 | grep -q 'No resources found'"
  check_cp "ServiceAccount builder mounts no token by default" "kubectl -n m3-ci get sa builder -o jsonpath='{.automountServiceAccountToken}' | grep -qx false"
  check_cp "pod build runs as builder without a token" \
    "kubectl -n m3-ci get pod build -o jsonpath='{.spec.serviceAccountName}' | grep -qx builder && kubectl -n m3-ci wait pod build --for=condition=Ready --timeout=60s && ! kubectl -n m3-ci exec build -- ls /var/run/secrets/kubernetes.io/serviceaccount/token"
}
solve_m7() {
  oncp <<'EOF'
kubectl -n m3-ci delete secret --field-selector type=kubernetes.io/service-account-token
kubectl -n m3-ci patch sa builder -p '{"automountServiceAccountToken": false}'
kubectl -n m3-ci get pod build -o json | python3 -c '
import json,sys
p=json.load(sys.stdin); s=p["spec"]
s["volumes"]=[v for v in s.get("volumes",[]) if not v["name"].startswith("kube-api-access-")]
for c in s["containers"]: c["volumeMounts"]=[m for m in c.get("volumeMounts",[]) if not m["name"].startswith("kube-api-access-")]
print(json.dumps(p))' | kubectl replace --force -f - >/dev/null
kubectl -n m3-ci wait pod build --for=condition=Ready --timeout=90s
EOF
}

# ---- 8. Everyone is admin (5) -------------------------------------------------------------------------------------
setup_m8() {
  cp_sh "sed -i 's/--authorization-mode=Node,RBAC\$/--authorization-mode=AlwaysAllow/' /etc/kubernetes/manifests/kube-apiserver.yaml"
}
m3_sa_secrets() { ! k auth can-i list secrets -A --as=system:serviceaccount:default:default; }
score_m8() {
  check_cp "--authorization-mode is Node,RBAC" "grep -q -- '--authorization-mode=Node,RBAC\$' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check "the default ServiceAccount may not list Secrets" m3_sa_secrets
}
solve_m8() {
  cp_sh "sed -i 's/--authorization-mode=AlwaysAllow\$/--authorization-mode=Node,RBAC/' /etc/kubernetes/manifests/kube-apiserver.yaml"
  sleep 5; wait_api; wait_static kube-apiserver
}

# ---- 9. SSH the right way (4) -------------------------------------------------------------------------------------
setup_m9() {
  onw1 <<'EOF'
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openssh-server >/dev/null
printf 'PasswordAuthentication yes\nPermitRootLogin yes\nX11Forwarding yes\n' > /etc/ssh/sshd_config.d/05-vendor.conf
systemctl restart ssh
EOF
}
score_m9() {
  check_w1 "sshd: permitrootlogin no, passwordauthentication no, x11forwarding no" \
    "sshd -T | grep -qx 'permitrootlogin no' && sshd -T | grep -qx 'passwordauthentication no' && sshd -T | grep -qx 'x11forwarding no'"
  check_w1 "sshd runs" "systemctl is-active -q ssh"
}
solve_m9() { w1_sh "sed -i 's/ yes\$/ no/' /etc/ssh/sshd_config.d/05-vendor.conf && sshd -t && systemctl restart ssh"; }

# ---- 10. Kernel modules nobody needs (4, Lima) ----------------------------------------------------------------------
setup_m10() { lima_sh 'rm -f /etc/modprobe.d/m3*.conf; modprobe udf; modprobe dccp; true'; }
score_m10() {
  check_lima "udf and dccp are not loaded" "! lsmod | grep -qE '^(udf|dccp) '"
  check_lima "modprobe refuses both, from a file in /etc/modprobe.d" \
    "modprobe -n -v udf 2>&1 | grep -q 'install /bin/false' && modprobe -n -v dccp 2>&1 | grep -q 'install /bin/false'"
}
solve_m10() { lima_sh "printf 'install udf /bin/false\nblacklist udf\ninstall dccp /bin/false\nblacklist dccp\n' > /etc/modprobe.d/m3.conf; modprobe -r udf dccp"; }

# ---- 11. Rotate to a new provider (8) --------------------------------------------------------------------------------
setup_m11() {
  mk_ns m3-vault
  oncp <<'EOF'
mkdir -p /etc/kubernetes/enc
cat > /etc/kubernetes/enc/m3.yaml <<YAML
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: [secrets]
  providers:
  - aescbc:
      keys:
      - name: legacy
        secret: $(head -c 32 /dev/urandom | base64)
  - identity: {}
YAML
kubectl -n m3-vault create secret generic db --from-literal=pw=m3-s3cret 2>/dev/null
EOF
  set_flag kube-apiserver --encryption-provider-config $M3_ENC
  apiserver_mount enc /etc/kubernetes/enc
  sleep 5; wait_api; wait_static kube-apiserver
  cp_sh 'kubectl get secrets -A -o json | kubectl replace -f - >/dev/null'
}
m3_not_new() { cp_sh "for k in \$($ETC get /registry/secrets --prefix --keys-only); do $ETC get \$k --print-value-only | head -c 26 | grep -q 'k8s:enc:secretbox:v1:new:' || echo \$k; done | wc -l"; }
score_m11() {
  check_cp "m3-vault/db is stored with secretbox key new" "$ETC get /registry/secrets/m3-vault/db --print-value-only | head -c 26 | grep -q 'k8s:enc:secretbox:v1:new:'"
  check "every Secret is stored with secretbox key new" bash -c "[ \"\$1\" -eq 0 ]" _ "$(m3_not_new)"
  check_cp "the configuration has no aescbc provider any more" "! grep -q aescbc $M3_ENC && grep -q secretbox $M3_ENC"
  check_cp "kubectl still reads m3-vault/db" "kubectl -n m3-vault get secret db -o jsonpath='{.data.pw}' | base64 -d | grep -qx m3-s3cret"
}
solve_m11() {
  cp_sh "python3 - <<'PY'
import base64, os
p='$M3_ENC'; s=open(p).read()
s=s.replace('  providers:\n', '  providers:\n  - secretbox:\n      keys:\n      - name: new\n        secret: %s\n' % base64.b64encode(os.urandom(32)).decode(), 1)
open(p,'w').write(s)
PY"
  restart_apiserver
  cp_sh 'kubectl get secrets -A -o json | kubectl replace -f - >/dev/null'
  cp_sh "python3 - <<'PY'
import re
p='$M3_ENC'; s=open(p).read()
s=re.sub(r'  - aescbc:\n      keys:\n      - name: legacy\n        secret: .*\n', '', s)
open(p,'w').write(s)
PY"
  restart_apiserver
}

# ---- 12. gVisor where it exists (5) ------------------------------------------------------------------------------------
setup_m12() { mk_ns m3-sbx; }
score_m12() {
  check_cp "RuntimeClass sandbox uses runsc and nodeSelector runtime=gvisor" \
    "kubectl get runtimeclass sandbox -o jsonpath='{.handler}/{.scheduling.nodeSelector.runtime}' | grep -qx runsc/gvisor"
  check_cp "cks-w1 carries runtime=gvisor" "kubectl get node cks-w1 -o jsonpath='{.metadata.labels.runtime}' | grep -qx gvisor"
  check_cp "pod m3-sbx/scan runs under gVisor" \
    "kubectl -n m3-sbx wait pod scan --for=condition=Ready --timeout=60s && kubectl -n m3-sbx exec scan -- dmesg | grep -q gVisor"
}
solve_m12() {
  oncp <<'EOF'
kubectl label node cks-w1 runtime=gvisor --overwrite
kubectl apply -f - <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: sandbox}
handler: runsc
scheduling: {nodeSelector: {runtime: gvisor}}
---
apiVersion: v1
kind: Pod
metadata: {name: scan, namespace: m3-sbx}
spec:
  runtimeClassName: sandbox
  containers: [{name: c, image: busybox:1.36, command: [sleep, 1d]}]
YAML
kubectl -n m3-sbx wait pod scan --for=condition=Ready --timeout=120s
EOF
}

# ---- 13. The API server doesn't start (8) -------------------------------------------------------------------------------
setup_m13() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/admission
cat > /etc/kubernetes/admission/m3.yaml <<'YAML'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    imagePolicy:
      kubeConfigFile: /etc/kubernetes/policy-webhook/kube.yaml
      allowTTL: 50
      denyTTL: 50
      retryBackoff: 500
      defaultAllow: false
YAML
sed -i 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=NodeRestriction,ImagePolicyWebhook/' /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
  set_flag kube-apiserver --admission-control-config-file $M3_ADM
  apiserver_mount admission /etc/kubernetes/admission
}
score_m13() {
  check_cp "the API server answers, with ImagePolicyWebhook enabled from $M3_ADM" \
    "kubectl get --raw=/readyz && grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q ImagePolicyWebhook && grep -q -- '--admission-control-config-file=$M3_ADM' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check_cp "defaultAllow stays false" "grep -q 'defaultAllow: false' $M3_ADM"
  check_cp "busybox:1.36 is admitted" "kubectl -n default run m13-ok --image=busybox:1.36 --dry-run=server -- sleep 1"
  check_cp "quay.io/evil/miner:1 is refused" "! kubectl -n default run m13-bad --image=quay.io/evil/miner:1 --dry-run=server"
}
solve_m13() {
  cp_sh "sed -i 's|policy-webhook/kube.yaml\$|policy-webhook/kubeconfig.yaml|' $M3_ADM"
  apiserver_mount policy-webhook /etc/kubernetes/policy-webhook
  sleep 5; wait_api
}

# ---- 14. Delete what's vulnerable (5) ------------------------------------------------------------------------------------
setup_m14() {
  mk_ns m3-prod
  oncp <<'EOF'
kubectl -n m3-prod create deploy session --image=redis:6.0.5 2>/dev/null
kubectl -n m3-prod create deploy front --image=nginx:1.27-alpine 2>/dev/null
kubectl -n m3-prod create deploy idle --image=registry.k8s.io/pause:3.10 2>/dev/null
kubectl -n m3-prod create deploy tools --image=busybox:1.36 -- sleep 1d 2>/dev/null
EOF
}
m3_crit() {
  cp_sh 'for d in session:redis:6.0.5 front:nginx:1.27-alpine idle:registry.k8s.io/pause:3.10 tools:busybox:1.36; do
    img=${d#*:}; n=$(trivy image --quiet --severity CRITICAL --format json "$img" 2>/dev/null | python3 -c "import json,sys; print(sum(len(r.get(\"Vulnerabilities\") or []) for r in json.load(sys.stdin).get(\"Results\",[])))")
    echo "${d%%:*} $n"; done'
}
# Deployments with CRITICAL findings must be gone, the others must stay. Reads "name count" lines.
m3_vuln_ok() {
  local d n
  [ -n "$1" ] || return 1
  while read -r d n; do
    if [ "$n" -gt 0 ]; then
      k -n m3-prod get deploy "$d" </dev/null >/dev/null 2>&1 && return 1
    else
      k -n m3-prod get deploy "$d" </dev/null >/dev/null 2>&1 || return 1
    fi
  done <<< "$1"
  return 0
}
score_m14() {
  check "every Deployment in m3-prod whose image has CRITICAL findings is gone, and the others stay" m3_vuln_ok "$(m3_crit)"
}
solve_m14() {
  m3_crit | while read -r d n; do
    echo "$d CRITICAL=$n"
    [ "$n" -gt 0 ] && k -n m3-prod delete deploy "$d" </dev/null >/dev/null
  done
}

# ---- 15. Tune Falco and act on it (8) ---------------------------------------------------------------------------------------
setup_m15() {
  mk_ns m3-run
  oncp <<'EOF'
kubectl -n m3-run create deploy indexer --image=busybox:1.36 -- sh -c 'while true; do grep -rs "BEGIN RSA PRIVATE" /etc; sleep 15; done' 2>/dev/null
kubectl -n m3-run create deploy api --image=busybox:1.36 -- sh -c 'while true; do sleep 15; done' 2>/dev/null
mkdir -p /root/mock
EOF
  w1_sh 'rm -f /etc/falco/rules.d/m3.yaml'
}
m3_alert() { w1_sh "journalctl -u falco-modern-bpf --since '-2min' --no-pager | grep -q 'Alert Grep private keys or passwords activities found.*k8s_ns_name=m3-run'"; }
score_m15() {
  check_w1 "falco_rules.yaml is unchanged, and an override in rules.d raises the rule to ALERT" \
    "! dpkg -V falco | grep -q falco_rules.yaml && grep -rqs 'rule: Search Private Keys or Passwords' /etc/falco/rules.d/ && grep -rqsi 'priority: *alert' /etc/falco/rules.d/"
  check_cp "/root/mock/key-hunter.txt names indexer, and indexer is scaled to 0" \
    "grep -qx indexer /root/mock/key-hunter.txt && kubectl -n m3-run get deploy indexer -o jsonpath='{.spec.replicas}' | grep -qx 0"
  check_cp "api keeps its replica" "kubectl -n m3-run get deploy api -o jsonpath='{.spec.replicas}' | grep -qx 1"
}
solve_m15() {
  onw1 <<'EOF'
cat > /etc/falco/rules.d/m3.yaml <<'YAML'
- rule: Search Private Keys or Passwords
  priority: ALERT
  override:
    priority: replace
YAML
for i in $(seq 1 15); do journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -q 'm3.yaml' && break; sleep 2; done
EOF
  local pod=""
  for _ in $(seq 1 20); do
    pod="$(w1_sh "journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep 'Alert Grep private keys' | grep -o 'k8s_pod_name=[^ ]*' | tail -1 | cut -d= -f2")"
    [ -n "$pod" ] && break; sleep 3
  done
  echo "Falco names pod $pod"
  cp_sh "d=\$(kubectl -n m3-run get pod $pod -o jsonpath='{.metadata.labels.app}'); echo \$d > /root/mock/key-hunter.txt; kubectl -n m3-run scale deploy \$d --replicas=0"
}

# ---- 16. An audit policy for one team (7) -------------------------------------------------------------------------------------
setup_m16() {
  cks_users gina
  mk_ns m3-audit
  cp_sh 'kubectl -n m3-audit create rolebinding gina --clusterrole=edit --user=gina 2>/dev/null; kubectl -n m3-audit create secret generic s --from-literal=a=b 2>/dev/null; true'
}
m3_audit() { cp_sh "python3 -c '
import json,sys
want=json.loads(sys.argv[1]); has=want.pop(\"has\",[]); hasnt=want.pop(\"hasnt\",[])
for line in open(\"$M3_LOG\"):
    e=json.loads(line); o=e.get(\"objectRef\",{})
    if all((o.get(k) if k in (\"resource\",\"namespace\",\"name\") else (e[\"user\"][\"username\"] if k==\"user\" else e.get(k)))==v for k,v in want.items()) and all(h in e for h in has) and not any(h in e for h in hasnt):
        sys.exit(0)
sys.exit(1)' '$1'"; }
score_m16() {
  local f=/etc/kubernetes/manifests/kube-apiserver.yaml m="m$RANDOM"
  check_cp "the API server logs with /etc/kubernetes/audit/m3-policy.yaml to $M3_LOG" \
    "grep -q -- '--audit-policy-file=/etc/kubernetes/audit/m3-policy.yaml' $f && grep -q -- '--audit-log-path=$M3_LOG' $f"
  as_user gina -n m3-audit create deploy "d$m" --image=busybox:1.36 -- sleep 1 >/dev/null 2>&1
  as_user gina -n m3-audit get secret s >/dev/null 2>&1
  cp_sh "kubectl -n m3-audit create deploy a$m --image=busybox:1.36 -- sleep 1 >/dev/null; kubectl -n m3-audit get pods >/dev/null; sleep 3" >/dev/null 2>&1
  check "gina's Deployment create appears at RequestResponse" m3_audit "{\"resource\":\"deployments\",\"name\":\"d$m\",\"user\":\"gina\",\"level\":\"RequestResponse\",\"has\":[\"responseObject\"]}"
  check "gina's Secret get appears at Metadata" m3_audit '{"resource":"secrets","namespace":"m3-audit","user":"gina","verb":"get","level":"Metadata","hasnt":["responseObject"]}'
  check "the admin's Deployment create appears at Metadata" m3_audit "{\"resource\":\"deployments\",\"name\":\"a$m\",\"verb\":\"create\",\"level\":\"Metadata\"}"
  check_cp "pod lists do not appear" "! grep -q '\"resource\":\"pods\",\"namespace\":\"m3-audit\".*\"verb\":\"list\"' $M3_LOG && ! grep -q '\"verb\":\"list\".*\"resource\":\"pods\",\"namespace\":\"m3-audit\"' $M3_LOG"
}
solve_m16() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
cat > /etc/kubernetes/audit/m3-policy.yaml <<'YAML'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: Metadata
  resources: [{group: "", resources: [secrets]}]
- level: RequestResponse
  userGroups: [cks-users]
  namespaces: [m3-audit]
  resources: [{group: apps, resources: [deployments]}]
- level: Metadata
  namespaces: [m3-audit]
  resources: [{group: apps, resources: [deployments]}]
- level: None
YAML
EOF
  set_flag kube-apiserver --audit-policy-file /etc/kubernetes/audit/m3-policy.yaml
  set_flag kube-apiserver --audit-log-path $M3_LOG
  apiserver_mount audit-policy /etc/kubernetes/audit
  apiserver_mount audit-log /var/log/kubernetes/audit false
  sleep 5; wait_api; wait_static kube-apiserver
}

# ---- 17. seccomp and a read-only root (6) -------------------------------------------------------------------------------------
setup_m17() {
  mk_ns m3-sec
  w1_sh 'mkdir -p /root/mock && printf "{\n  \"defaultAction\": \"SCMP_ACT_ALLOW\",\n  \"syscalls\": [{\"names\": [\"mkdir\", \"mkdirat\"], \"action\": \"SCMP_ACT_ERRNO\"}]\n}\n" > /root/mock/no-mkdir.json; rm -f /var/lib/kubelet/seccomp/m3.json'
}
score_m17() {
  check_cp "pod locked uses the Localhost profile m3.json and a read-only root file system" \
    "kubectl -n m3-sec get pod locked -o json | python3 -c 'import json,sys; s=json.load(sys.stdin)[\"spec\"]; c=s[\"containers\"][0].get(\"securityContext\",{}); sp=c.get(\"seccompProfile\") or s.get(\"securityContext\",{}).get(\"seccompProfile\") or {}; sys.exit(0 if sp.get(\"type\")==\"Localhost\" and sp.get(\"localhostProfile\")==\"m3.json\" and c.get(\"readOnlyRootFilesystem\") else 1)'"
  check_cp "locked runs on cks-w1; mkdir fails in /data, a file write there works" \
    "kubectl -n m3-sec wait pod locked --for=condition=Ready --timeout=60s && ! kubectl -n m3-sec exec locked -- mkdir /data/d && kubectl -n m3-sec exec locked -- sh -c 'echo ok > /data/f'"
}
solve_m17() {
  w1_sh 'mkdir -p /var/lib/kubelet/seccomp && cp /root/mock/no-mkdir.json /var/lib/kubelet/seccomp/m3.json'
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: locked, namespace: m3-sec}
spec:
  nodeName: cks-w1
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
    securityContext:
      readOnlyRootFilesystem: true
      seccompProfile: {type: Localhost, localhostProfile: m3.json}
    volumeMounts: [{name: data, mountPath: /data}]
  volumes: [{name: data, emptyDir: {}}]
YAML
kubectl -n m3-sec wait pod locked --for=condition=Ready --timeout=90s
EOF
}
