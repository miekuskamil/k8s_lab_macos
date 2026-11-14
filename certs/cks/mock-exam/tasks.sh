# The CKS mock exam: setup_mN seeds task N, score_mN checks it, solve_mN is the reference
# solution. Sourced by setup.sh, score.sh and solve.sh. Needs tasks/lib.sh first.

MOCK_TASKS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17"
# Points per task; they add up to 100.
mock_points() {
  case "$1" in
    1) echo 7;; 2) echo 7;; 3) echo 6;; 4) echo 4;; 5) echo 6;; 6) echo 4;; 7) echo 4;; 8) echo 4;;
    9) echo 6;; 10) echo 7;; 11) echo 5;; 12) echo 5;; 13) echo 9;; 14) echo 4;; 15) echo 8;; 16) echo 8;; 17) echo 6;;
  esac
}
mock_title() {
  case "$1" in
    1) echo "Upgrade the control plane";; 2) echo "Protect the database";; 3) echo "CIS findings";;
    4) echo "Ingress with TLS";; 5) echo "Take cluster-admin away";; 6) echo "No token in the metrics pod";;
    7) echo "Remove a web server from a node";; 8) echo "An intern with root";; 9) echo "Restricted namespace";;
    10) echo "Secrets encrypted with secretbox";; 11) echo "A sandboxed pod";; 12) echo "Vulnerable images";;
    13) echo "Approved registries only";; 14) echo "A smaller Node.js image";; 15) echo "Audit policy";;
    16) echo "Falco finds a snooper";; 17) echo "Harden a Deployment";;
  esac
}

ETC='etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt --key=/etc/kubernetes/pki/apiserver-etcd-client.key'
MOCK_AUDIT=/var/log/kubernetes/audit/mock.log
ns_wait='for n in $NSS; do kubectl create ns $n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done; for n in $NSS; do for i in $(seq 1 30); do kubectl -n $n get sa default >/dev/null 2>&1 && break; sleep 1; done; done'

# ---- 1. Upgrade the control plane (7) ------------------------------------------------------
setup_m1() { :; }
score_m1() {
  check_cp "cks-cp kubelet is v1.37.2" "kubectl get node cks-cp -o jsonpath='{.status.nodeInfo.kubeletVersion}' | grep -qx v1.37.2"
  check_cp "the API server image is v1.37.2" "kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].image}' | grep -q ':v1.37.2\$'"
  check_cp "cks-cp is schedulable again" "! kubectl get node cks-cp -o jsonpath='{.spec.unschedulable}' | grep -q true"
}
solve_m1() {
  oncp <<'EOF'
set -e
apt-mark unhold kubeadm >/dev/null; apt-get install -y -qq kubeadm=1.37.2-1.1 >/dev/null; apt-mark hold kubeadm >/dev/null
kubeadm upgrade apply v1.37.2 -y >/dev/null 2>&1
kubectl drain cks-cp --ignore-daemonsets --delete-emptydir-data >/dev/null
apt-mark unhold kubelet kubectl >/dev/null; apt-get install -y -qq kubelet=1.37.2-1.1 kubectl=1.37.2-1.1 >/dev/null; apt-mark hold kubelet kubectl >/dev/null
systemctl daemon-reload; systemctl restart kubelet
for i in $(seq 1 60); do kubectl uncordon cks-cp >/dev/null 2>&1 && break; sleep 2; done
EOF
}

# ---- 2. Protect the database (7) ------------------------------------------------------------
setup_m2() {
  oncp <<EOF
NSS="m-db m-other"; $ns_wait
kubectl -n m-db run db --image=nginx:1.27-alpine -l app=db --port 80 --expose 2>/dev/null
kubectl -n m-db run backend --image=busybox:1.36 -l app=backend -- sleep 1d 2>/dev/null
kubectl -n m-db run intruder --image=busybox:1.36 -l app=intruder -- sleep 1d 2>/dev/null
kubectl -n m-other run outsider --image=busybox:1.36 -l app=backend -- sleep 1d 2>/dev/null
EOF
}
score_m2() {
  check_cp "NetworkPolicy db-ingress exists in m-db" "kubectl -n m-db get netpol db-ingress"
  check_cp "backend reaches db on port 80" "kubectl -n m-db exec backend -- wget -qO- -T 3 http://db"
  check_cp "intruder does not reach db" "! kubectl -n m-db exec intruder -- wget -qO- -T 3 http://db"
  check_cp "a pod labelled app=backend in another namespace does not reach db" "! kubectl -n m-other exec outsider -- wget -qO- -T 3 http://db.m-db"
}
solve_m2() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db-ingress, namespace: m-db}
spec:
  podSelector: {matchLabels: {app: db}}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector: {matchLabels: {app: backend}}
    ports:
    - {protocol: TCP, port: 80}
YAML
EOF
}

# ---- 3. CIS findings (6) --------------------------------------------------------------------
setup_m3() { :; }
score_m3() {
  local out
  out="$(cp_sh 'kube-bench run --targets master --check 1.4.1,1.1.12 2>/dev/null')"
  check "kube-bench 1.4.1 (scheduler profiling) passes" bash -c "printf '%s\n' \"\$1\" | grep -q '^\[PASS\] 1.4.1 '" _ "$out"
  check "kube-bench 1.1.12 (etcd data directory owner) passes" bash -c "printf '%s\n' \"\$1\" | grep -q '^\[PASS\] 1.1.12 '" _ "$out"
  check_cp "the scheduler and etcd run" "kubectl -n kube-system wait pod -l 'component in (kube-scheduler,etcd)' --for=condition=Ready --timeout=60s"
}
solve_m3() {
  set_flag kube-scheduler --profiling false
  cp_sh 'id etcd >/dev/null 2>&1 || useradd -r -s /usr/sbin/nologin etcd; chown -R etcd:etcd /var/lib/etcd'
  sleep 5
  k -n kube-system wait pod -l component=kube-scheduler --for=condition=Ready --timeout=120s >/dev/null
}

# ---- 4. Ingress with TLS (4) ------------------------------------------------------------------
setup_m4() {
  oncp <<EOF
NSS="m-web"; $ns_wait
kubectl -n m-web create deploy site --image=nginx:1.27-alpine --port 80 2>/dev/null
kubectl -n m-web expose deploy site --port 80 2>/dev/null
mkdir -p /root/mock
openssl req -x509 -newkey rsa:2048 -nodes -days 365 -subj "/CN=site.cks.local" -addext "subjectAltName=DNS:site.cks.local" \
  -keyout /root/mock/site.key -out /root/mock/site.crt 2>/dev/null
EOF
}
score_m4() {
  check_cp "HTTPS for site.cks.local answers 200" \
    "for i in \$(seq 1 15); do curl -sk -o /dev/null -w '%{http_code}' --resolve site.cks.local:30443:127.0.0.1 https://site.cks.local:30443/ | grep -qx 200 && exit 0; sleep 2; done; exit 1"
  check_cp "the certificate is CN=site.cks.local" \
    "echo | openssl s_client -connect 127.0.0.1:30443 -servername site.cks.local 2>/dev/null | openssl x509 -noout -subject | grep -q 'CN *= *site.cks.local'"
}
solve_m4() {
  oncp <<'EOF'
kubectl -n m-web create secret tls site-tls --cert=/root/mock/site.crt --key=/root/mock/site.key
kubectl -n m-web create ingress site --class=nginx --rule="site.cks.local/*=site:80,tls=site-tls"
EOF
}

# ---- 5. Take cluster-admin away (6) ------------------------------------------------------------
setup_m5() {
  oncp <<EOF
NSS="m-ops"; $ns_wait
kubectl -n m-ops create sa deployer 2>/dev/null
kubectl create clusterrolebinding deployer-admin --clusterrole=cluster-admin --serviceaccount=m-ops:deployer 2>/dev/null
EOF
}
as_deployer() { k auth can-i "$@" --as=system:serviceaccount:m-ops:deployer; }
score_m5() {
  check_cp "ClusterRoleBinding deployer-admin is gone" "! kubectl get clusterrolebinding deployer-admin"
  check "deployer creates Deployments in m-ops" as_deployer create deployments.apps -n m-ops
  check "deployer patches Deployments in m-ops" as_deployer patch deployments.apps -n m-ops
  check "deployer does not delete Deployments in m-ops" bash -c "! orb -m $CKS_CP -u root kubectl auth can-i delete deployments.apps -n m-ops --as=system:serviceaccount:m-ops:deployer"
  check "deployer does not create Deployments in default" bash -c "! orb -m $CKS_CP -u root kubectl auth can-i create deployments.apps -n default --as=system:serviceaccount:m-ops:deployer"
  check "deployer does not read Secrets in m-ops" bash -c "! orb -m $CKS_CP -u root kubectl auth can-i get secrets -n m-ops --as=system:serviceaccount:m-ops:deployer"
}
solve_m5() {
  oncp <<'EOF'
kubectl delete clusterrolebinding deployer-admin
kubectl -n m-ops create role deployer --verb=get,list,watch,create,update,patch --resource=deployments.apps
kubectl -n m-ops create rolebinding deployer --role=deployer --serviceaccount=m-ops:deployer
EOF
}

# ---- 6. No token in the metrics pod (4) -----------------------------------------------------------
setup_m6() {
  oncp <<EOF
NSS="m-ops"; $ns_wait
kubectl -n m-ops run metrics --image=busybox:1.36 -- sleep 1d 2>/dev/null
EOF
}
score_m6() {
  check_cp "pod metrics sets automountServiceAccountToken: false" \
    "kubectl -n m-ops get pod metrics -o jsonpath='{.spec.automountServiceAccountToken}' | grep -qx false"
  check_cp "pod metrics runs and has no token file" \
    "kubectl -n m-ops wait pod metrics --for=condition=Ready --timeout=60s && ! kubectl -n m-ops exec metrics -- ls /var/run/secrets/kubernetes.io/serviceaccount/token"
}
solve_m6() {
  oncp <<'EOF'
# Set the field, and drop the exported kube-api-access volume and its mount: the export spells
# them out, and a spelled-out volume mounts the token whatever the field says.
kubectl -n m-ops get pod metrics -o json | python3 -c '
import json,sys
p=json.load(sys.stdin); s=p["spec"]
s["automountServiceAccountToken"]=False
s["volumes"]=[v for v in s.get("volumes",[]) if not v["name"].startswith("kube-api-access-")]
for c in s["containers"]:
    c["volumeMounts"]=[m for m in c.get("volumeMounts",[]) if not m["name"].startswith("kube-api-access-")]
print(json.dumps(p))' | kubectl replace --force -f - >/dev/null
kubectl -n m-ops wait pod metrics --for=condition=Ready --timeout=90s
EOF
}

# ---- 7. Remove a web server from a node (4) -------------------------------------------------------
setup_m7() {
  w1_sh 'DEBIAN_FRONTEND=noninteractive apt-get install -y -qq lighttpd >/dev/null 2>&1; systemctl enable --now lighttpd >/dev/null 2>&1; ss -tln | grep -q ":80 " && echo "  lighttpd listens on :80"'
}
score_m7() {
  check_w1 "nothing listens on TCP port 80 on cks-w1" "! ss -tln | grep -q ':80 '"
  check_w1 "the package that served it is removed" "! dpkg -l lighttpd 2>/dev/null | grep -q '^ii'"
}
solve_m7() { w1_sh 'systemctl disable --now lighttpd >/dev/null 2>&1; apt-get purge -y -qq lighttpd >/dev/null'; }

# ---- 8. An intern with root (4) ---------------------------------------------------------------------
setup_m8() {
  w1_sh 'id intern >/dev/null 2>&1 || useradd -m -s /bin/bash intern; usermod -aG sudo intern; echo "intern ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/intern; chmod 440 /etc/sudoers.d/intern'
}
score_m8() {
  check_w1 "sudo grants intern nothing" "sudo -l -U intern | grep -q 'not allowed to run sudo'"
  check_w1 "intern exists" "id intern"
}
solve_m8() { w1_sh 'gpasswd -d intern sudo >/dev/null; rm -f /etc/sudoers.d/intern'; }

# ---- 9. Restricted namespace (6) ----------------------------------------------------------------------
setup_m9() {
  oncp <<EOF
NSS="m-secure"; $ns_wait
kubectl -n m-secure create deploy api --image=busybox:1.36 -- sleep 1d 2>/dev/null
EOF
}
score_m9() {
  check_cp "m-secure enforces restricted" "kubectl get ns m-secure -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -qx restricted"
  check_cp "Deployment api has a ready pod" "kubectl -n m-secure rollout status deploy api --timeout=90s && kubectl -n m-secure get deploy api -o jsonpath='{.status.readyReplicas}' | grep -qx 1"
  check_cp "no running pod in m-secure violates restricted" "! kubectl label --dry-run=server --overwrite ns m-secure pod-security.kubernetes.io/enforce=restricted 2>&1 | grep -q violate"
}
solve_m9() {
  oncp <<'EOF'
kubectl label ns m-secure pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl -n m-secure patch deploy api --type=json -p='[
 {"op":"add","path":"/spec/template/spec/securityContext","value":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]'
kubectl -n m-secure rollout status deploy api --timeout=120s
EOF
}

# ---- 10. Secrets encrypted with secretbox (7) ----------------------------------------------------------
setup_m10() {
  oncp <<EOF
NSS="m-vault"; $ns_wait
kubectl -n m-vault create secret generic api-key --from-literal=key=k3y-v4lue 2>/dev/null
EOF
}
score_m10() {
  check_cp "the API server uses /etc/kubernetes/enc/mock.yaml" "grep -q -- '--encryption-provider-config=/etc/kubernetes/enc/mock.yaml' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check_cp "m-vault/api-key is stored with prefix k8s:enc:secretbox:v1:mock:" \
    "$ETC get /registry/secrets/m-vault/api-key --print-value-only | head -c 30 | grep -q 'k8s:enc:secretbox:v1:mock:'"
  check_cp "kubectl still reads it" "kubectl -n m-vault get secret api-key -o jsonpath='{.data.key}' | base64 -d | grep -qx k3y-v4lue"
}
solve_m10() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/enc
cat > /etc/kubernetes/enc/mock.yaml <<YAML
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: [secrets]
  providers:
  - secretbox:
      keys:
      - name: mock
        secret: $(head -c 32 /dev/urandom | base64)
  - identity: {}
YAML
EOF
  set_flag kube-apiserver --encryption-provider-config /etc/kubernetes/enc/mock.yaml
  apiserver_mount enc /etc/kubernetes/enc
  sleep 5; wait_api
  cp_sh 'kubectl get secrets -A -o json | kubectl replace -f - >/dev/null'
}

# ---- 11. A sandboxed pod (5) -----------------------------------------------------------------------------
setup_m11() {
  oncp <<EOF
NSS="m-sandbox"; $ns_wait
EOF
}
score_m11() {
  check_cp "RuntimeClass sandboxed uses handler runsc" "kubectl get runtimeclass sandboxed -o jsonpath='{.handler}' | grep -qx runsc"
  check_cp "pod m-sandbox/untrusted runs under gVisor" \
    "kubectl -n m-sandbox get pod untrusted -o jsonpath='{.spec.runtimeClassName}' | grep -qx sandboxed && kubectl -n m-sandbox exec untrusted -- dmesg | grep -q gVisor"
}
solve_m11() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: sandboxed}
handler: runsc
---
apiVersion: v1
kind: Pod
metadata: {name: untrusted, namespace: m-sandbox}
spec:
  runtimeClassName: sandboxed
  containers:
  - {name: c, image: busybox:1.36, command: [sleep, 1d]}
YAML
kubectl -n m-sandbox wait pod untrusted --for=condition=Ready --timeout=120s
EOF
}

# ---- 12. Vulnerable images (5) --------------------------------------------------------------------------
setup_m12() {
  oncp <<EOF
NSS="m-scan"; $ns_wait
kubectl -n m-scan run legacy-web --image=nginx:1.19.0 2>/dev/null
kubectl -n m-scan run session-store --image=redis:6.0.5 2>/dev/null
kubectl -n m-scan run debug --image=busybox:1.36 -- sleep 1d 2>/dev/null
EOF
}
score_m12() {
  check_cp "legacy-web is gone" "! kubectl -n m-scan get pod legacy-web"
  check_cp "session-store is gone" "! kubectl -n m-scan get pod session-store"
  check_cp "debug still runs" "kubectl -n m-scan get pod debug -o jsonpath='{.status.phase}' | grep -qx Running"
}
solve_m12() { k -n m-scan delete pod legacy-web session-store --now >/dev/null; }

# ---- 13. Approved registries only (9) -----------------------------------------------------------------------
setup_m13() { :; }
score_m13() {
  check_cp "ImagePolicyWebhook is enabled" "grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q ImagePolicyWebhook"
  check_cp "the admission config at /etc/kubernetes/admission/mock-admission.yaml sets defaultAllow: false" \
    "grep -q -- '--admission-control-config-file=/etc/kubernetes/admission/mock-admission.yaml' /etc/kubernetes/manifests/kube-apiserver.yaml && grep -q 'defaultAllow: false' /etc/kubernetes/admission/mock-admission.yaml"
  check_cp "busybox:1.36 is admitted" "kubectl run m13-ok --image=busybox:1.36 --dry-run=server -- sleep 1"
  check_cp "quay.io/evil/miner:1 is refused" "! kubectl run m13-bad --image=quay.io/evil/miner:1 --dry-run=server"
}
solve_m13() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/admission
cat > /etc/kubernetes/admission/mock-admission.yaml <<'YAML'
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
      defaultAllow: false
YAML
sed -i 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=NodeRestriction,ImagePolicyWebhook/' /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
  set_flag kube-apiserver --admission-control-config-file /etc/kubernetes/admission/mock-admission.yaml
  apiserver_mount admission /etc/kubernetes/admission
  apiserver_mount policy-webhook /etc/kubernetes/policy-webhook
  sleep 5; wait_api
}

# ---- 14. A smaller Node.js image (4) ---------------------------------------------------------------------------
setup_m14() {
  oncp <<'EOF'
mkdir -p /root/mock/build
cat > /root/mock/build/Dockerfile <<'DOCKERFILE'
FROM node:latest
RUN apt-get update && apt-get install -y curl wget vim
WORKDIR /app
COPY server.js .
USER root
CMD ["node", "server.js"]
DOCKERFILE
EOF
}
score_m14() {
  local f=/root/mock/build/Dockerfile
  check_cp "FROM node:22-alpine" "grep -qE '^FROM +node:22-alpine\$' $f"
  check_cp "no RUN line installs curl, wget or vim" "! grep -iE '^RUN ' $f | grep -qE 'curl|wget|vim'"
  check_cp "the last USER is node" "grep -iE '^USER ' $f | tail -1 | grep -qE '^USER +node\$'"
}
solve_m14() {
  cp_sh "sed -i -e 's/^FROM node:latest\$/FROM node:22-alpine/' -e '/^RUN apt-get/d' -e 's/^USER root\$/USER node/' /root/mock/build/Dockerfile"
}

# ---- 15. Audit policy (8) ----------------------------------------------------------------------------------------
setup_m15() {
  oncp <<EOF
NSS="m-audit"; $ns_wait
EOF
}
mock_audit() { cp_sh "python3 -c '
import json,sys
want=json.loads(sys.argv[1]); has=want.pop(\"has\",[]); hasnt=want.pop(\"hasnt\",[])
for line in open(\"$MOCK_AUDIT\"):
    e=json.loads(line); o=e.get(\"objectRef\",{})
    if all((o.get(k) if k in (\"resource\",\"namespace\") else e.get(k))==v for k,v in want.items()) and all(h in e for h in has) and not any(h in e for h in hasnt):
        sys.exit(0)
sys.exit(1)' '$1'"; }
score_m15() {
  local f=/etc/kubernetes/manifests/kube-apiserver.yaml
  check_cp "audit flags: policy, path, maxage 7, maxbackup 5, maxsize 50" \
    "grep -q -- '--audit-policy-file=/etc/kubernetes/audit/mock-policy.yaml' $f && grep -q -- '--audit-log-path=$MOCK_AUDIT' $f && grep -q -- '--audit-log-maxage=7' $f && grep -q -- '--audit-log-maxbackup=5' $f && grep -q -- '--audit-log-maxsize=50' $f"
  cp_sh "kubectl -n m-audit run probe-\$RANDOM --image=busybox:1.36 --dry-run=server -- true >/dev/null; kubectl -n m-audit create configmap m15-\$RANDOM --from-literal=a=b >/dev/null; kubectl create deploy m15-\$RANDOM --image=busybox:1.36 --dry-run=server >/dev/null; sleep 2" >/dev/null 2>&1
  check "a ConfigMap create appears at Metadata, without its body" mock_audit '{"resource":"configmaps","namespace":"m-audit","verb":"create","level":"Metadata","hasnt":["requestObject"]}'
  check "a pod create in m-audit appears at Request, with the request body only" mock_audit '{"resource":"pods","namespace":"m-audit","verb":"create","level":"Request","has":["requestObject"],"hasnt":["responseObject"]}'
  check_cp "a Deployment create in default does not appear" "test -s $MOCK_AUDIT && ! grep -q '\"resource\":\"deployments\",\"namespace\":\"default\"' $MOCK_AUDIT"
}
solve_m15() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
cat > /etc/kubernetes/audit/mock-policy.yaml <<'YAML'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: Metadata
  resources:
  - group: ""
    resources: [secrets, configmaps]
- level: Request
  namespaces: [m-audit]
  resources:
  - group: ""
    resources: [pods]
- level: None
YAML
EOF
  set_flag kube-apiserver --audit-policy-file /etc/kubernetes/audit/mock-policy.yaml
  set_flag kube-apiserver --audit-log-path $MOCK_AUDIT
  set_flag kube-apiserver --audit-log-maxage 7
  set_flag kube-apiserver --audit-log-maxbackup 5
  set_flag kube-apiserver --audit-log-maxsize 50
  apiserver_mount audit-policy /etc/kubernetes/audit
  apiserver_mount audit-log /var/log/kubernetes/audit false
  sleep 5; wait_api
}

# ---- 16. Falco finds a snooper (8) ----------------------------------------------------------------------------------
setup_m16() {
  oncp <<EOF
NSS="m-runtime"; $ns_wait
kubectl -n m-runtime create deploy reporter --image=busybox:1.36 -- sh -c 'while true; do cat /etc/shadow >/dev/null; sleep 5; done' 2>/dev/null
kubectl -n m-runtime create deploy web --image=nginx:1.27-alpine 2>/dev/null
mkdir -p /root/mock
EOF
}
score_m16() {
  check_cp "Deployment reporter is scaled to 0" "kubectl -n m-runtime get deploy reporter -o jsonpath='{.spec.replicas}' | grep -qx 0"
  check_cp "Deployment web still has 1 replica" "kubectl -n m-runtime get deploy web -o jsonpath='{.spec.replicas}' | grep -qx 1"
  check_cp "/root/mock/snooper.txt says reporter" "grep -qx reporter /root/mock/snooper.txt"
}
solve_m16() {
  local pod
  pod="$(w1_sh "journalctl -u falco-modern-bpf --since '-30min' --no-pager | grep 'file=/etc/shadow' | grep 'k8s_ns_name=m-runtime' | grep -o 'k8s_pod_name=[^ ]*' | tail -1 | cut -d= -f2")"
  echo "  Falco names pod: $pod"
  oncp <<EOF
deploy=\$(kubectl -n m-runtime get pod $pod -o jsonpath='{.metadata.ownerReferences[0].name}' | sed 's/-[a-z0-9]*\$//')
echo "\$deploy" > /root/mock/snooper.txt
kubectl -n m-runtime scale deploy \$deploy --replicas=0
EOF
}

# ---- 17. Harden a Deployment (6) ----------------------------------------------------------------------------------------
setup_m17() {
  oncp <<EOF
NSS="m-hard"; $ns_wait
kubectl -n m-hard create deploy app --image=busybox:1.36 -- sleep 1d 2>/dev/null
EOF
}
score_m17() {
  check_cp "container app: readOnlyRootFilesystem, no privilege escalation, seccomp RuntimeDefault" \
    "kubectl -n m-hard get deploy app -o json | python3 -c 'import json,sys; c=json.load(sys.stdin)[\"spec\"][\"template\"][\"spec\"][\"containers\"][0].get(\"securityContext\",{}); sys.exit(0 if c.get(\"readOnlyRootFilesystem\") and c.get(\"allowPrivilegeEscalation\") is False and c.get(\"seccompProfile\",{}).get(\"type\")==\"RuntimeDefault\" else 1)'"
  check_cp "the pod runs and its root file system refuses writes" \
    "kubectl -n m-hard rollout status deploy app --timeout=90s && ! kubectl -n m-hard exec deploy/app -- touch /x"
}
solve_m17() {
  oncp <<'EOF'
kubectl -n m-hard patch deploy app --type=json -p='[{"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"readOnlyRootFilesystem":true,"allowPrivilegeEscalation":false,"seccompProfile":{"type":"RuntimeDefault"}}}]'
kubectl -n m-hard rollout status deploy app --timeout=120s
EOF
}
