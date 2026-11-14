# Domain 04, minimize microservice vulnerabilities. Functions for task.sh: setup_4_N, check_4_N, solve_4_N.

ETCDCTL='etcdctl --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/apiserver-etcd-client.crt --key=/etc/kubernetes/pki/apiserver-etcd-client.key'

# ---- Task 1: enforce the restricted standard ------------------------------------------
setup_4_1() {
  oncp <<'EOF'
kubectl create ns secure-apps --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n secure-apps get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n secure-apps create deploy app --image=busybox:1.36 -- sleep 1d 2>/dev/null
kubectl -n secure-apps rollout status deploy app --timeout=120s
EOF
}
check_4_1() {
  check_cp "namespace secure-apps enforces the restricted standard" \
    "kubectl get ns secure-apps -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -qx restricted"
  check_cp "Deployment app has a ready pod that the namespace admitted" \
    "kubectl -n secure-apps rollout status deploy app --timeout=90s && kubectl -n secure-apps get deploy app -o jsonpath='{.status.readyReplicas}' | grep -qx 1"
  # A server-side dry run of the label lists every running pod that would violate the level.
  check_cp "no running pod in secure-apps violates restricted" \
    "! kubectl label --dry-run=server --overwrite ns secure-apps pod-security.kubernetes.io/enforce=restricted 2>&1 | grep -q violate"
  check_cp "a privileged pod is refused in secure-apps" \
    "! kubectl -n secure-apps run bad --image=busybox:1.36 --privileged --dry-run=server -- sleep 1"
}
solve_4_1() {
  oncp <<'EOF'
kubectl label ns secure-apps pod-security.kubernetes.io/enforce=restricted pod-security.kubernetes.io/warn=restricted --overwrite
kubectl -n secure-apps patch deploy app --type=json -p='[
 {"op":"add","path":"/spec/template/spec/securityContext","value":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}},
 {"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]'
kubectl -n secure-apps rollout status deploy app --timeout=120s
EOF
}

# ---- Task 2: encrypt Secrets at rest ---------------------------------------------------
setup_4_2() {
  oncp <<EOF
kubectl create ns vault-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n vault-test get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n vault-test create secret generic db-creds --from-literal=password=Sup3rS3cret 2>/dev/null
$ETCDCTL get /registry/secrets/vault-test/db-creds | grep -a -o -m1 "Sup3rS3cret"
EOF
}
check_4_2() {
  check_cp "the API server runs with --encryption-provider-config" \
    "grep -q -- '--encryption-provider-config=' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check_cp "Secret db-creds is stored with prefix k8s:enc:aescbc:v1:" \
    "$ETCDCTL get /registry/secrets/vault-test/db-creds --print-value-only | head -c 20 | grep -q 'k8s:enc:aescbc:v1:'"
  check_cp "the password no longer appears in etcd in clear text" \
    "! $ETCDCTL get /registry/secrets/vault-test/db-creds --print-value-only | grep -aq Sup3rS3cret"
  check_cp "kubectl still reads the Secret" \
    "kubectl -n vault-test get secret db-creds -o jsonpath='{.data.password}' | base64 -d | grep -qx Sup3rS3cret"
}
solve_4_2() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/enc
KEY=$(head -c 32 /dev/urandom | base64)
cat > /etc/kubernetes/enc/enc.yaml <<YAML
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources: [secrets]
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: $KEY
  - identity: {}
YAML
chmod 600 /etc/kubernetes/enc/enc.yaml
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.before-4.2
EOF
  set_flag kube-apiserver --encryption-provider-config /etc/kubernetes/enc/enc.yaml
  apiserver_mount enc /etc/kubernetes/enc
  sleep 5; wait_api
  cp_sh 'kubectl get secrets -A -o json | kubectl replace -f - >/dev/null && echo "rewrote $(kubectl get secrets -A --no-headers | wc -l) secrets"'
}

# ---- Task 3: a Secret as a file, not an environment variable ----------------------------
setup_4_3() {
  oncp <<'EOF'
kubectl create ns orders --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n orders get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n orders create secret generic api-token --from-literal=token=t0k3n-123 2>/dev/null
kubectl -n orders delete pod api --now --ignore-not-found >/dev/null
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: api, namespace: orders}
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: [sleep, 1d]
    env:
    - name: API_TOKEN
      valueFrom: {secretKeyRef: {name: api-token, key: token}}
YAML
kubectl -n orders wait pod api --for=condition=Ready --timeout=120s
EOF
}
check_4_3() {
  check_cp "pod api has no environment variable from a Secret" \
    "! kubectl -n orders get pod api -o jsonpath='{.spec.containers[*].env[*].valueFrom.secretKeyRef.name}' | grep -q ."
  check_cp "pod api mounts Secret api-token read-only at /etc/api" \
    "kubectl -n orders get pod api -o json | python3 -c 'import json,sys; p=json.load(sys.stdin)[\"spec\"]; v=[x[\"name\"] for x in p[\"volumes\"] if x.get(\"secret\",{}).get(\"secretName\")==\"api-token\"]; m=[x for x in p[\"containers\"][0][\"volumeMounts\"] if x[\"name\"] in v and x[\"mountPath\"]==\"/etc/api\" and x.get(\"readOnly\")]; sys.exit(0 if m else 1)'"
  check_cp "the token is readable at /etc/api/token" \
    "kubectl -n orders exec api -- cat /etc/api/token | grep -qx t0k3n-123"
}
solve_4_3() {
  oncp <<'EOF'
kubectl -n orders get pod api -o yaml > /root/api.yaml
kubectl -n orders delete pod api --now
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: api, namespace: orders}
spec:
  containers:
  - name: api
    image: busybox:1.36
    command: [sleep, 1d]
    volumeMounts:
    - {name: token, mountPath: /etc/api, readOnly: true}
  volumes:
  - name: token
    secret: {secretName: api-token}
YAML
kubectl -n orders wait pod api --for=condition=Ready --timeout=120s
EOF
}

# ---- Task 4: sandbox a pod with gVisor -------------------------------------------------
setup_4_4() {
  oncp <<'EOF'
kubectl create ns sandbox --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n sandbox get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n sandbox create deploy untrusted --image=busybox:1.36 -- sleep 1d 2>/dev/null
kubectl -n sandbox rollout status deploy untrusted --timeout=120s
EOF
  w1_sh 'grep -A1 "runtimes.runsc\]" /etc/containerd/config.toml'
}
check_4_4() {
  check_cp "RuntimeClass gvisor uses handler runsc" "kubectl get runtimeclass gvisor -o jsonpath='{.handler}' | grep -qx runsc"
  check_cp "Deployment untrusted uses RuntimeClass gvisor" \
    "kubectl -n sandbox get deploy untrusted -o jsonpath='{.spec.template.spec.runtimeClassName}' | grep -qx gvisor"
  check_cp "the running pod's kernel is gVisor" \
    "kubectl -n sandbox rollout status deploy untrusted --timeout=90s && kubectl -n sandbox exec deploy/untrusted -- dmesg | grep -q gVisor"
}
solve_4_4() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: gvisor}
handler: runsc
YAML
kubectl -n sandbox patch deploy untrusted -p '{"spec":{"template":{"spec":{"runtimeClassName":"gvisor"}}}}'
kubectl -n sandbox rollout status deploy untrusted --timeout=120s
kubectl -n sandbox exec deploy/untrusted -- dmesg | head -2
EOF
}
