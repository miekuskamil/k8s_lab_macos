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

# ---- Task 5: rotate the encryption key ----------------------------------------------------
setup_4_5() {
  if ! cp_sh "grep -q -- '--encryption-provider-config=' /etc/kubernetes/manifests/kube-apiserver.yaml"; then
    echo "  task 4.5 starts from task 4.2's result; applying that solution first"
    solve_4_2 | sed 's/^/  /'
  fi
  oncp <<EOF
kubectl create ns rotate-me --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in \$(seq 1 30); do kubectl -n rotate-me get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n rotate-me create secret generic app-secret --from-literal=token=r0tat3-me 2>/dev/null
grep -A6 'aescbc' /etc/kubernetes/enc/enc.yaml | sed 's/secret: .*/secret: <hidden>/'
echo "  stored as: \$($ETCDCTL get /registry/secrets/rotate-me/app-secret --print-value-only | head -c 23)"
EOF
}
# Prints how many Secrets in etcd are NOT written with key2.
not_key2() { cp_sh "for k in \$($ETCDCTL get /registry/secrets --prefix --keys-only); do $ETCDCTL get \$k --print-value-only | head -c 23 | grep -q 'k8s:enc:aescbc:v1:key2:' || echo \$k; done | wc -l"; }
check_4_5() {
  check_cp "app-secret is stored with key2" \
    "$ETCDCTL get /registry/secrets/rotate-me/app-secret --print-value-only | head -c 23 | grep -q 'k8s:enc:aescbc:v1:key2:'"
  check "every Secret in etcd is stored with key2" bash -c "[ \"\$1\" -eq 0 ]" _ "$(not_key2)"
  check_cp "the configuration no longer holds key1, and key2 comes first" \
    "! grep -q 'name: key1' /etc/kubernetes/enc/enc.yaml && grep -m1 'name: key' /etc/kubernetes/enc/enc.yaml | grep -q key2"
  check_cp "kubectl still reads app-secret" \
    "kubectl -n rotate-me get secret app-secret -o jsonpath='{.data.token}' | base64 -d | grep -qx r0tat3-me"
}
solve_4_5() {
  # Step 1: key2 first, key1 still there to read old data. Restart, rewrite, then drop key1.
  oncp <<'EOF'
cp /etc/kubernetes/enc/enc.yaml /root/enc.yaml.before-4.5
K2=$(head -c 32 /dev/urandom | base64)
python3 - "$K2" <<'PY'
import sys
p = "/etc/kubernetes/enc/enc.yaml"; s = open(p).read()
s = s.replace("      keys:\n", "      keys:\n      - name: key2\n        secret: %s\n" % sys.argv[1], 1)
open(p, "w").write(s)
PY
grep -E 'name: key' /etc/kubernetes/enc/enc.yaml
EOF
  restart_apiserver
  cp_sh 'kubectl get secrets -A -o json | kubectl replace -f - >/dev/null && echo "rewrote $(kubectl get secrets -A --no-headers | wc -l) Secrets"'
  oncp <<'EOF'
python3 - <<'PY'
import re
p = "/etc/kubernetes/enc/enc.yaml"; s = open(p).read()
s = re.sub(r"      - name: key1\n        secret: .*\n", "", s)
open(p, "w").write(s)
PY
grep -E 'name: key' /etc/kubernetes/enc/enc.yaml
EOF
  restart_apiserver
}
# The API server reads the encryption config only at start. Moving the manifest out and back
# makes the kubelet restart the static pod, the same as an edit does.
restart_apiserver() {
  cp_sh 'mv /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.tmp
    for i in $(seq 1 30); do crictl ps --name kube-apiserver -q | grep -q . || break; sleep 2; done
    mv /root/kube-apiserver.yaml.tmp /etc/kubernetes/manifests/kube-apiserver.yaml'
  sleep 5; wait_api; wait_static kube-apiserver
}

# ---- Task 6: Pod Security levels, modes and versions ---------------------------------------
setup_4_6() {
  oncp <<'EOF'
kubectl create ns psa-levels --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n psa-levels get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl label ns psa-levels pod-security.kubernetes.io/enforce- pod-security.kubernetes.io/warn- pod-security.kubernetes.io/audit- >/dev/null 2>&1
kubectl -n psa-levels create deploy legacy --image=nginx:1.27-alpine 2>/dev/null
kubectl -n psa-levels rollout status deploy legacy --timeout=120s
EOF
}
nslabel() { k get ns psa-levels -o jsonpath="{.metadata.labels.pod-security\.kubernetes\.io/$1}"; }
check_4_6() {
  check "enforce is baseline, pinned to v1.37" bash -c "[ \"\$1\" = baseline/v1.37 ]" _ "$(nslabel enforce)/$(nslabel enforce-version)"
  check "warn and audit are restricted, at version latest" \
    bash -c "[ \"\$1\" = restricted/latest/restricted/latest ]" _ "$(nslabel warn)/$(nslabel warn-version)/$(nslabel audit)/$(nslabel audit-version)"
  check_cp "a privileged pod is refused" "! kubectl -n psa-levels run t1 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1"
  check_cp "a root nginx pod is admitted, with a restricted warning" \
    "kubectl -n psa-levels run t2 --image=nginx:1.27-alpine --dry-run=server 2>&1 | grep -q 'would violate PodSecurity \"restricted:latest\"'"
  check_cp "Deployment legacy keeps its ready pod" "kubectl -n psa-levels get deploy legacy -o jsonpath='{.status.readyReplicas}' | grep -qx 1"
}
solve_4_6() {
  oncp <<'EOF'
kubectl label ns psa-levels --overwrite \
  pod-security.kubernetes.io/enforce=baseline pod-security.kubernetes.io/enforce-version=v1.37 \
  pod-security.kubernetes.io/warn=restricted pod-security.kubernetes.io/warn-version=latest \
  pod-security.kubernetes.io/audit=restricted pod-security.kubernetes.io/audit-version=latest
EOF
}

# ---- Task 7: cluster-wide Pod Security defaults with exemptions ------------------------------
setup_4_7() {
  oncp <<'EOF'
for n in psa-default monitoring-agents; do kubectl create ns $n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done
for n in psa-default monitoring-agents; do for i in $(seq 1 30); do kubectl -n $n get sa default >/dev/null 2>&1 && break; sleep 1; done; done
echo "  a privileged pod in psa-default today: $(kubectl -n psa-default run t --image=busybox:1.36 --privileged --dry-run=server -- sleep 1 2>&1 | tail -1)"
EOF
}
check_4_7() {
  check_cp "the API server reads /etc/kubernetes/admission/psa.yaml" \
    "grep -q -- '--admission-control-config-file=/etc/kubernetes/admission/psa.yaml' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check_cp "a privileged pod in the unlabelled namespace psa-default is refused" \
    "! kubectl -n psa-default run t1 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1"
  check_cp "a root nginx pod in psa-default gets a restricted warning but runs" \
    "kubectl -n psa-default run t2 --image=nginx:1.27-alpine --dry-run=server 2>&1 | grep -q 'would violate PodSecurity \"restricted:latest\"'"
  check_cp "a privileged pod in monitoring-agents is admitted" \
    "kubectl -n monitoring-agents run t3 --image=busybox:1.36 --privileged --dry-run=server -- sleep 1"
  check_cp "the API server pod is Ready" "kubectl -n kube-system wait pod -l component=kube-apiserver --for=condition=Ready --timeout=60s"
}
solve_4_7() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/admission
cat > /etc/kubernetes/admission/psa.yaml <<'YAML'
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    defaults:
      enforce: baseline
      enforce-version: latest
      audit: restricted
      audit-version: latest
      warn: restricted
      warn-version: latest
    exemptions:
      usernames: []
      runtimeClasses: []
      namespaces: [kube-system, monitoring-agents]
YAML
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.before-4.7
EOF
  set_flag kube-apiserver --admission-control-config-file /etc/kubernetes/admission/psa.yaml
  apiserver_mount admission /etc/kubernetes/admission
  sleep 5; wait_api; wait_static kube-apiserver
}

# ---- Task 8: pods that reach into the node ----------------------------------------------------
setup_4_8() {
  oncp <<'EOF'
for n in team-blue team-green; do kubectl create ns $n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done
for n in team-blue team-green; do for i in $(seq 1 30); do kubectl -n $n get sa default >/dev/null 2>&1 && break; sleep 1; done; done
# Old namespaces that somebody once marked privileged, so Pod Security lets everything in.
kubectl label ns team-blue team-green pod-security.kubernetes.io/enforce=privileged --overwrite >/dev/null
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: web, namespace: team-blue}
spec:
  containers: [{name: c, image: nginx:1.27-alpine}]
---
apiVersion: v1
kind: Pod
metadata: {name: node-debug, namespace: team-blue}
spec:
  hostPID: true
  containers: [{name: c, image: busybox:1.36, command: [sleep, 1d]}]
---
apiVersion: v1
kind: Pod
metadata: {name: log-reader, namespace: team-blue}
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
    volumeMounts: [{name: host, mountPath: /host}]
  volumes: [{name: host, hostPath: {path: /}}]
---
apiVersion: v1
kind: Pod
metadata: {name: api, namespace: team-green}
spec:
  containers: [{name: c, image: busybox:1.36, command: [sleep, 1d]}]
---
apiVersion: v1
kind: Pod
metadata: {name: net-tool, namespace: team-green}
spec:
  hostNetwork: true
  containers: [{name: c, image: busybox:1.36, command: [sleep, 1d]}]
---
apiVersion: v1
kind: Pod
metadata: {name: metrics, namespace: team-green}
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
    securityContext: {privileged: true}
---
apiVersion: v1
kind: Pod
metadata: {name: cache, namespace: team-green}
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
    volumeMounts: [{name: tmp, mountPath: /cache}]
  volumes: [{name: tmp, emptyDir: {}}]
YAML
for n in team-blue team-green; do kubectl -n $n wait pod --all --for=condition=Ready --timeout=120s >/dev/null; done
kubectl get pods -A --no-headers | grep -E '^team-(blue|green) ' | awk '{print "  " $1 "/" $2}'
EOF
}
check_4_8() {
  check_cp "node-debug (hostPID) is gone" "! kubectl -n team-blue get pod node-debug"
  check_cp "log-reader (hostPath /) is gone" "! kubectl -n team-blue get pod log-reader"
  check_cp "net-tool (hostNetwork) is gone" "! kubectl -n team-green get pod net-tool"
  check_cp "metrics (privileged) is gone" "! kubectl -n team-green get pod metrics"
  check_cp "web, api and cache still run" \
    "kubectl -n team-blue get pod web && kubectl -n team-green get pod api cache"
}
solve_4_8() {
  oncp <<'EOF'
for n in team-blue team-green; do
  kubectl -n $n get pods -o json | python3 -c '
import json,sys
for p in json.load(sys.stdin)["items"]:
    s=p["spec"]; why=[]
    for f in ("hostPID","hostNetwork","hostIPC"):
        if s.get(f): why.append(f)
    if any("hostPath" in v for v in s.get("volumes",[])): why.append("hostPath")
    if any((c.get("securityContext") or {}).get("privileged") for c in s["containers"]): why.append("privileged")
    if why: print(p["metadata"]["name"], ",".join(why))' | while read pod why; do
    echo "$n/$pod: $why"; kubectl -n $n delete pod $pod --now >/dev/null
  done
done
EOF
}

# ---- Task 9: a sandbox only on the nodes that have it -----------------------------------------
setup_4_9() {
  oncp <<'EOF'
kubectl create ns sandbox-sched --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n sandbox-sched get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl label node cks-w1 cks-cp sandbox- >/dev/null 2>&1
kubectl delete runtimeclass gvisor-pinned --ignore-not-found >/dev/null
kubectl -n sandbox-sched delete deploy scanner --ignore-not-found >/dev/null
EOF
  echo "  runsc on cks-w1: $(w1_sh 'command -v runsc')   runsc on cks-cp: $(cp_sh 'command -v runsc || echo none')"
}
check_4_9() {
  check_cp "cks-w1 carries the label sandbox=gvisor, cks-cp does not" \
    "kubectl get node cks-w1 -o jsonpath='{.metadata.labels.sandbox}' | grep -qx gvisor && ! kubectl get node cks-cp -o jsonpath='{.metadata.labels.sandbox}' | grep -q ."
  check_cp "RuntimeClass gvisor-pinned uses runsc and schedules onto sandbox=gvisor" \
    "kubectl get runtimeclass gvisor-pinned -o jsonpath='{.handler}/{.scheduling.nodeSelector.sandbox}' | grep -qx runsc/gvisor"
  check_cp "Deployment scanner has 3 ready pods, all on cks-w1, all under gVisor" \
    "kubectl -n sandbox-sched rollout status deploy scanner --timeout=120s && [ \$(kubectl -n sandbox-sched get pods -l app=scanner -o jsonpath='{range .items[*]}{.spec.nodeName}{\"\\n\"}{end}' | sort -u) = cks-w1 ] && kubectl -n sandbox-sched exec deploy/scanner -- dmesg | grep -q gVisor"
}
solve_4_9() {
  oncp <<'EOF'
kubectl label node cks-w1 sandbox=gvisor --overwrite
kubectl apply -f - <<'YAML'
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata: {name: gvisor-pinned}
handler: runsc
scheduling:
  nodeSelector: {sandbox: gvisor}
YAML
kubectl -n sandbox-sched create deploy scanner --image=busybox:1.36 --replicas=3 --dry-run=client -o json -- sleep 1d \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); d["spec"]["template"]["spec"]["runtimeClassName"]="gvisor-pinned"; print(json.dumps(d))' \
  | kubectl apply -f -
kubectl -n sandbox-sched rollout status deploy scanner --timeout=120s
kubectl -n sandbox-sched get pods -o wide --no-headers | awk '{print $1, $7}'
EOF
}

# ---- Task 10: pod-to-pod encryption with Cilium and WireGuard (Lima) ------------------------
setup_4_10() {
  need_lima || return 1
  onlima <<'EOF'
if [ "$(kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-wireguard}')" = true ]; then
  cilium upgrade --version 1.20.4 --reuse-values --set encryption.enabled=false >/dev/null 2>&1
  kubectl -n kube-system rollout restart ds/cilium >/dev/null
  kubectl -n kube-system rollout status ds/cilium --timeout=300s >/dev/null
fi
kubectl create ns wg-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n wg-test get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n wg-test run web --image=nginx:1.27-alpine --port 80 --expose 2>/dev/null
kubectl -n wg-test run client --image=busybox:1.36 -- sleep 1d 2>/dev/null
kubectl -n wg-test wait pod --all --for=condition=Ready --timeout=180s >/dev/null
cilium encrypt status
EOF
}
check_4_10() {
  check_lima "cilium-config has enable-wireguard: true" \
    "kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-wireguard}' | grep -qx true"
  check_lima "cilium encrypt status reports Wireguard on every node" "cilium encrypt status | grep -q 'Encryption: Wireguard (1/1 nodes)'"
  check_lima "the node has the WireGuard interface cilium_wg0" "ip link show cilium_wg0"
  check_lima "pods still reach each other" "kubectl -n wg-test exec client -- wget -qO- -T 5 http://web | grep -q nginx"
}
solve_4_10() {
  need_lima || return 1
  onlima <<'EOF'
cilium upgrade --version 1.20.4 --reuse-values --set encryption.enabled=true --set encryption.type=wireguard >/dev/null 2>&1
kubectl -n kube-system rollout restart ds/cilium
kubectl -n kube-system rollout status ds/cilium --timeout=300s
cilium status --wait >/dev/null
cilium encrypt status
EOF
}
