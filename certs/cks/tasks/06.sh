# Domain 06, monitoring, logging and runtime security. Functions for task.sh: setup_6_N, check_6_N, solve_6_N.

AUDIT_LOG=/var/log/kubernetes/audit/audit.log

# ---- Task 1: turn on audit logging -----------------------------------------------------
setup_6_1() {
  oncp <<'EOF'
kubectl create ns audit-me --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n audit-me get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n audit-me create secret generic token --from-literal=t=abc 2>/dev/null
grep -c audit /etc/kubernetes/manifests/kube-apiserver.yaml || true
EOF
}
# Make some traffic, then look for it in the audit log.
audit_has() { cp_sh "python3 -c '
import json,sys
want=json.loads(sys.argv[1])
for line in open(\"$AUDIT_LOG\"):
    e=json.loads(line); o=e.get(\"objectRef\",{})
    if all((o.get(k) if k in (\"resource\",\"namespace\",\"name\") else e.get(k))==v for k,v in want.items() if k!=\"has\") and all(h in e for h in want.get(\"has\",[])):
        sys.exit(0)
sys.exit(1)' '$1'"; }
audit_lacks() { ! audit_has "$1"; }
audit_lacks_body() { cp_sh "python3 -c '
import json,sys
for line in open(\"$AUDIT_LOG\"):
    e=json.loads(line)
    if e.get(\"objectRef\",{}).get(\"resource\")==\"secrets\" and (\"requestObject\" in e or \"responseObject\" in e): sys.exit(1)
sys.exit(0)'"; }
check_6_1() {
  local f=/etc/kubernetes/manifests/kube-apiserver.yaml
  check_cp "--audit-policy-file is /etc/kubernetes/audit/policy.yaml" "grep -q -- '--audit-policy-file=/etc/kubernetes/audit/policy.yaml' $f"
  check_cp "--audit-log-path is $AUDIT_LOG" "grep -q -- '--audit-log-path=$AUDIT_LOG' $f"
  check_cp "--audit-log-maxage=30, maxbackup=10, maxsize=100" \
    "grep -q -- '--audit-log-maxage=30' $f && grep -q -- '--audit-log-maxbackup=10' $f && grep -q -- '--audit-log-maxsize=100' $f"
  cp_sh "kubectl -n audit-me get secret token >/dev/null; kubectl -n audit-me create configmap probe-\$RANDOM --from-literal=a=b >/dev/null; kubectl -n default create configmap probe-\$RANDOM --from-literal=a=b >/dev/null; sleep 2" >/dev/null 2>&1
  check "a get on a Secret appears at level Metadata" audit_has '{"resource":"secrets","namespace":"audit-me","verb":"get","level":"Metadata"}'
  check "no Secret appears with its body" audit_lacks_body
  check "a configmap create in audit-me appears at RequestResponse" audit_has '{"resource":"configmaps","namespace":"audit-me","verb":"create","level":"RequestResponse","has":["requestObject"]}'
  check "a configmap create in default does not appear" audit_lacks '{"resource":"configmaps","namespace":"default","verb":"create"}'
}
solve_6_1() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/audit /var/log/kubernetes/audit
cat > /etc/kubernetes/audit/policy.yaml <<'YAML'
apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: Metadata
  resources:
  - group: ""
    resources: [secrets]
- level: RequestResponse
  namespaces: [audit-me]
- level: None
YAML
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.before-6.1
EOF
  set_flag kube-apiserver --audit-policy-file /etc/kubernetes/audit/policy.yaml
  set_flag kube-apiserver --audit-log-path $AUDIT_LOG
  set_flag kube-apiserver --audit-log-maxage 30
  set_flag kube-apiserver --audit-log-maxbackup 10
  set_flag kube-apiserver --audit-log-maxsize 100
  apiserver_mount audit-policy /etc/kubernetes/audit
  apiserver_mount audit-log /var/log/kubernetes/audit false
  sleep 5; wait_api
}

# ---- Task 2: catch a shell with Falco ----------------------------------------------------
setup_6_2() {
  oncp <<'EOF'
kubectl create ns falco-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n falco-test get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n falco-test run target --image=nginx:1.27-alpine 2>/dev/null
kubectl -n falco-test wait pod target --for=condition=Ready --timeout=120s
EOF
  w1_sh 'rm -f /etc/falco/rules.d/cks-*.yaml /var/log/falco-shells.log; systemctl is-active falco-modern-bpf'
}
check_6_2() {
  check_w1 "a rule named 'Shell in container (cks)' exists in /etc/falco/rules.d/" "grep -rq 'rule: Shell in container (cks)' /etc/falco/rules.d/"
  check_w1 "falco accepts every rules file" "falco -V /etc/falco/falco_rules.yaml -V /etc/falco/rules.d/ >/dev/null 2>&1 || falco --validate /etc/falco/rules.d/ >/dev/null 2>&1"
  check "a shell in falco-test/target produces the alert with namespace, pod and command" falco_sees_shell
}
# Falco needs a few seconds to reload a new rules file, so try a fresh shell up to 10 times.
falco_sees_shell() {
  local n marker
  for n in 1 2 3 4 5 6 7 8 9 10; do
    marker="cks$RANDOM"
    k -n falco-test exec target -- sh -c "echo $marker" >/dev/null 2>&1
    sleep 2
    w1_sh "journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -q 'ns=falco-tes[t] pod=targe[t] .*cmd=sh -c echo $marker'" && return 0
  done
  return 1
}
solve_6_2() {
  onw1 <<'EOF'
cat > /etc/falco/rules.d/cks-shell.yaml <<'YAML'
- rule: Shell in container (cks)
  desc: A shell runs inside a container
  condition: spawned_process and container and proc.name in (sh, bash, ash, dash)
  output: "shell in container (time=%evt.time user=%user.name ns=%k8s.ns.name pod=%k8s.pod.name container=%container.name cmd=%proc.cmdline)"
  priority: WARNING
YAML
for i in $(seq 1 15); do journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -q 'cks-shell.yaml' && break; sleep 2; done
journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -iE 'reload|cks-shell|error' | tail -3
EOF
}

# ---- Task 3: make a container immutable ---------------------------------------------------
setup_6_3() {
  oncp <<'EOF'
kubectl create ns immutable --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n immutable get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n immutable create deploy web --image=nginx:1.27-alpine --port 80 2>/dev/null
kubectl -n immutable expose deploy web --port 80 2>/dev/null
kubectl -n immutable rollout status deploy web --timeout=120s
EOF
}
check_6_3() {
  check_cp "container web has readOnlyRootFilesystem: true" \
    "kubectl -n immutable get deploy web -o jsonpath='{.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem}' | grep -qx true"
  check_cp "the Deployment's pod is Ready" "kubectl -n immutable rollout status deploy web --timeout=90s"
  check_cp "writing to / fails inside the pod" "! kubectl -n immutable exec deploy/web -- touch /cks-was-here"
  check_cp "nginx still serves on the Service" \
    "kubectl -n immutable run curl-\$RANDOM --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- -T 5 http://web | grep -q 'Welcome to nginx'"
}
solve_6_3() {
  oncp <<'EOF'
kubectl -n immutable patch deploy web --type=json -p='[
 {"op":"add","path":"/spec/template/spec/containers/0/securityContext","value":{"readOnlyRootFilesystem":true}},
 {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts","value":[
   {"name":"cache","mountPath":"/var/cache/nginx"},{"name":"run","mountPath":"/run"},{"name":"tmp","mountPath":"/tmp"}]},
 {"op":"add","path":"/spec/template/spec/volumes","value":[
   {"name":"cache","emptyDir":{}},{"name":"run","emptyDir":{}},{"name":"tmp","emptyDir":{}}]}]'
kubectl -n immutable rollout status deploy web --timeout=120s
EOF
}

# ---- Task 4: a seccomp profile -----------------------------------------------------------
setup_6_4() {
  onw1 <<'EOF'
mkdir -p /root/cks
cat > /root/cks/no-chmod.json <<'JSON'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {"names": ["chmod", "fchmod", "fchmodat", "fchmodat2"], "action": "SCMP_ACT_ERRNO"}
  ]
}
JSON
rm -rf /var/lib/kubelet/seccomp/profiles
ls -l /root/cks/no-chmod.json
EOF
  oncp <<'EOF'
kubectl create ns seccomp --dry-run=client -o yaml | kubectl apply -f - >/dev/null
EOF
}
check_6_4() {
  check_w1 "the kubelet finds the profile at /var/lib/kubelet/seccomp/profiles/no-chmod.json" \
    "test -f /var/lib/kubelet/seccomp/profiles/no-chmod.json"
  check_cp "pod locked in seccomp uses the Localhost profile profiles/no-chmod.json" \
    "kubectl -n seccomp get pod locked -o jsonpath='{.spec.securityContext.seccompProfile.type}/{.spec.securityContext.seccompProfile.localhostProfile}' | grep -qx Localhost/profiles/no-chmod.json"
  check_cp "pod locked runs on cks-w1" "kubectl -n seccomp get pod locked -o jsonpath='{.status.phase}/{.spec.nodeName}' | grep -qx Running/cks-w1"
  check_cp "chmod fails inside pod locked" "kubectl -n seccomp get pod locked && ! kubectl -n seccomp exec locked -- sh -c 'touch /tmp/f && chmod 600 /tmp/f'"
  check_cp "other writes still work inside pod locked" "kubectl -n seccomp exec locked -- sh -c 'echo ok > /tmp/g'"
}
solve_6_4() {
  w1_sh 'mkdir -p /var/lib/kubelet/seccomp/profiles && cp /root/cks/no-chmod.json /var/lib/kubelet/seccomp/profiles/'
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: locked, namespace: seccomp}
spec:
  nodeName: cks-w1
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/no-chmod.json
  containers:
  - name: c
    image: busybox:1.36
    command: [sleep, 1d]
YAML
kubectl -n seccomp wait pod locked --for=condition=Ready --timeout=90s
kubectl -n seccomp exec locked -- sh -c 'touch /tmp/f && chmod 600 /tmp/f'
EOF
}

# ---- Task 5: an AppArmor profile -----------------------------------------------------------
setup_6_5() {
  onw1 <<'EOF'
mkdir -p /root/cks
cat > /root/cks/cks-deny-write <<'PROFILE'
#include <tunables/global>

profile cks-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file
  deny /** w,
}
PROFILE
apparmor_parser -Q /root/cks/cks-deny-write 2>&1 | tail -1
EOF
  oncp <<'EOF'
kubectl create ns apparmor --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n apparmor get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n apparmor delete pod writer --ignore-not-found --now >/dev/null
EOF
}
check_6_5() {
  check_w1 "apparmor_parser accepts /root/cks/cks-deny-write" "apparmor_parser -Q /root/cks/cks-deny-write"
  check_w1 "the profile still denies every write" "grep -Eq '^\s*deny /\*\* w,' /root/cks/cks-deny-write"
  check_cp "pod writer asks for the Localhost profile cks-deny-write" \
    "kubectl -n apparmor get pod writer -o jsonpath='{.spec.containers[0].securityContext.appArmorProfile.type}/{.spec.containers[0].securityContext.appArmorProfile.localhostProfile}' | grep -qx Localhost/cks-deny-write"
  check_cp "pod writer sits on cks-w1 (OrbStack's kernel has no AppArmor, so the kubelet refuses to start it)" \
    "kubectl -n apparmor get pod writer -o jsonpath='{.spec.nodeName}' | grep -qx cks-w1"
}
solve_6_5() {
  w1_sh "sed -i 's/^  file\$/  file,/' /root/cks/cks-deny-write && apparmor_parser -Q /root/cks/cks-deny-write; echo parse=\$?"
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: writer, namespace: apparmor}
spec:
  nodeName: cks-w1
  containers:
  - name: c
    image: busybox:1.36
    command: [sh, -c, "echo hi > /tmp/x; sleep 1d"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: cks-deny-write
YAML
sleep 5
kubectl -n apparmor get pod writer -o jsonpath='{.status.phase} {.status.reason}: {.status.message}{"\n"}'
EOF
}

# ---- Task 6: investigate an attack ----------------------------------------------------------
setup_6_6() {
  if ! cp_sh "grep -q -- '--audit-policy-file=' /etc/kubernetes/manifests/kube-apiserver.yaml"; then
    echo "  task 6.6 needs audit logging from task 6.1; applying that solution first"
    solve_6_1
  fi
  oncp <<'EOF'
kubectl create ns team-x --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n team-x get sa default >/dev/null 2>&1 && break; sleep 1; done
for sa in ci-bot docs-bot; do kubectl -n team-x create sa $sa 2>/dev/null; done
kubectl -n team-x create role secret-admin --verb=get,list,delete --resource=secrets 2>/dev/null
kubectl -n team-x create rolebinding ci-bot-secrets --role=secret-admin --serviceaccount=team-x:ci-bot 2>/dev/null
kubectl -n team-x create rolebinding docs-bot-secrets --role=secret-admin --serviceaccount=team-x:docs-bot 2>/dev/null
kubectl -n team-x delete secret prod-db --ignore-not-found >/dev/null
kubectl -n team-x create secret generic prod-db --from-literal=password=pr0d
kubectl -n team-x delete pod nightly-cleanup --ignore-not-found --now >/dev/null
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: nightly-cleanup, namespace: team-x}
spec:
  serviceAccountName: ci-bot
  restartPolicy: Never
  containers:
  - name: c
    image: curlimages/curl:8.11.1
    command: [sh, -c]
    args:
    - |
      T=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
      curl -sk -X DELETE -H "Authorization: Bearer $T" https://kubernetes.default.svc/api/v1/namespaces/team-x/secrets/prod-db -o /dev/null -w "%{http_code}\n"
YAML
for i in $(seq 1 60); do [ "$(kubectl -n team-x get pod nightly-cleanup -o jsonpath='{.status.phase}')" = Succeeded ] && break; sleep 2; done
kubectl -n team-x delete pod nightly-cleanup --now >/dev/null
kubectl -n team-x get secret prod-db 2>&1 | tail -1
EOF
}
check_6_6() {
  check_cp "/root/cks/culprit.txt names the ServiceAccount and the pod" \
    "grep -qx 'system:serviceaccount:team-x:ci-bot nightly-cleanup' /root/cks/culprit.txt"
  check_cp "RoleBinding ci-bot-secrets is gone" "! kubectl -n team-x get rolebinding ci-bot-secrets"
  check_cp "docs-bot keeps its RoleBinding" "kubectl -n team-x get rolebinding docs-bot-secrets"
  check_cp "ci-bot may no longer delete Secrets in team-x" \
    "! kubectl auth can-i delete secrets -n team-x --as=system:serviceaccount:team-x:ci-bot"
}
solve_6_6() {
  oncp <<'EOF'
mkdir -p /root/cks
grep '"resource":"secrets"' /var/log/kubernetes/audit/audit.log | grep '"verb":"delete"' | grep '"name":"prod-db"' | tail -1 \
  | python3 -c 'import json,sys; e=json.loads(sys.stdin.read()); print(e["user"]["username"], e["user"]["extra"]["authentication.kubernetes.io/pod-name"][0])' \
  | tee /root/cks/culprit.txt
kubectl -n team-x get rolebinding -o wide | grep ci-bot
kubectl -n team-x delete rolebinding ci-bot-secrets
EOF
}
