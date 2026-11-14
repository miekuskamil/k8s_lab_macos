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

# ---- Task 5: an AppArmor profile (Lima) ----------------------------------------------------
setup_6_5() {
  need_lima || return 1
  onlima <<'EOF'
mkdir -p /root/cks
cat > /root/cks/cks-deny-write <<'PROFILE'
#include <tunables/global>

profile cks-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file
  deny /** w,
}
PROFILE
apparmor_parser -R /etc/apparmor.d/cks-deny-write 2>/dev/null; rm -f /etc/apparmor.d/cks-deny-write
apparmor_parser -Q /root/cks/cks-deny-write 2>&1 | tail -1
kubectl create ns apparmor --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n apparmor get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n apparmor delete pod writer --ignore-not-found --now >/dev/null
EOF
}
check_6_5() {
  check_lima "the profile in /root/cks/cks-deny-write parses and still denies every write" \
    "apparmor_parser -Q /root/cks/cks-deny-write && grep -Eq '^\s*deny /\*\* w,' /root/cks/cks-deny-write"
  check_lima "profile cks-deny-write is loaded in enforce mode" \
    "aa-status 2>/dev/null | sed -n '/profiles are in enforce mode/,/profiles are in complain mode/p' | grep -qx '   cks-deny-write'"
  check_lima "pod writer asks for the Localhost profile cks-deny-write" \
    "kubectl -n apparmor get pod writer -o jsonpath='{.spec.containers[0].securityContext.appArmorProfile.type}/{.spec.containers[0].securityContext.appArmorProfile.localhostProfile}' | grep -qx Localhost/cks-deny-write"
  check_lima "pod writer runs, confined by the profile" \
    "kubectl -n apparmor wait pod writer --for=condition=Ready --timeout=60s && kubectl -n apparmor exec writer -- cat /proc/1/attr/current | grep -qx 'cks-deny-write (enforce)'"
  check_lima "the write to /tmp/x was denied" "kubectl -n apparmor logs writer | grep -q 'Permission denied'"
}
solve_6_5() {
  need_lima || return 1
  onlima <<'EOF'
sed -i 's/^  file$/  file,/' /root/cks/cks-deny-write
cp /root/cks/cks-deny-write /etc/apparmor.d/cks-deny-write
apparmor_parser -r /etc/apparmor.d/cks-deny-write
aa-status | grep cks-deny-write
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: writer, namespace: apparmor}
spec:
  containers:
  - name: c
    image: busybox:1.36
    command: [sh, -c, "echo hi > /tmp/x; sleep 1d"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: cks-deny-write
YAML
kubectl -n apparmor wait pod writer --for=condition=Ready --timeout=90s
kubectl -n apparmor logs writer
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

# ---- Task 7: a Falco rule with a list and a macro --------------------------------------------
setup_6_7() {
  oncp <<'EOF'
kubectl create ns falco-test --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n falco-test get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n falco-test run target --image=nginx:1.27-alpine 2>/dev/null
kubectl -n falco-test wait pod target --for=condition=Ready --timeout=120s >/dev/null
EOF
  w1_sh 'rm -f /etc/falco/rules.d/cks-pkg.yaml; systemctl is-active falco-modern-bpf'
}
falco_sees() {  # falco_sees "<command in falco-test/target>" "<regex in the journal>"
  local n since
  for n in 1 2 3 4 5 6 7 8 9 10; do
    since="$(w1_sh 'date "+%Y-%m-%d %H:%M:%S"')"
    k -n falco-test exec target -- sh -c "$1" >/dev/null 2>&1
    sleep 2
    w1_sh "journalctl -u falco-modern-bpf --since '$since' --no-pager | grep -qE '$2'" && return 0
  done
  return 1
}
check_6_7() {
  local f=/etc/falco/rules.d/cks-pkg.yaml
  local py='import yaml,sys; d=yaml.safe_load(open(sys.argv[1])); L={x["list"]:x for x in d if "list" in x}; M={x["macro"] for x in d if "macro" in x}; R={x["rule"]:x for x in d if "rule" in x}'
  check_w1 "$f defines the list cks_pkg_mgrs with apk, apt, apt-get, dpkg and pip" \
    "python3 -c '$py; sys.exit(0 if {\"apk\",\"apt\",\"apt-get\",\"dpkg\",\"pip\"} <= set(L[\"cks_pkg_mgrs\"][\"items\"]) else 1)' $f"
  check_w1 "$f defines the macro cks_in_pod, and the rule uses the macro and the list" \
    "python3 -c '$py; c=R[\"Package manager in pod\"][\"condition\"]; sys.exit(0 if \"cks_in_pod\" in M and \"cks_in_pod\" in c and \"cks_pkg_mgrs\" in c else 1)' $f"
  check_w1 "falco accepts the rules" "falco -V /etc/falco/falco_rules.yaml -V $f >/dev/null 2>&1"
  check "apk in falco-test/target raises an Error alert with ns, pod and process" \
    falco_sees "apk --version" "Error package manager in pod \\(ns=falco-test pod=target proc=apk\\)"
}
solve_6_7() {
  onw1 <<'EOF'
cat > /etc/falco/rules.d/cks-pkg.yaml <<'YAML'
- list: cks_pkg_mgrs
  items: [apk, apt, apt-get, dpkg, pip]

- macro: cks_in_pod
  condition: (container and k8s.ns.name exists)

- rule: Package manager in pod
  desc: A package manager runs inside a Kubernetes pod
  condition: spawned_process and cks_in_pod and proc.name in (cks_pkg_mgrs)
  output: "package manager in pod (ns=%k8s.ns.name pod=%k8s.pod.name proc=%proc.name)"
  priority: ERROR
YAML
for i in $(seq 1 15); do journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -q 'cks-pkg.yaml' && break; sleep 2; done
journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -iE 'cks-pkg|error' | tail -2
EOF
}

# ---- Task 8: change what a default Falco rule does ----------------------------------------------
setup_6_8() {
  setup_6_7 >/dev/null
  w1_sh 'rm -f /etc/falco/rules.d/cks-override.yaml; dpkg -V falco | grep falco_rules.yaml || echo "  /etc/falco/falco_rules.yaml matches the package"'
}
# A shell with a terminal needs a TTY: script(1) gives kubectl one.
tty_shell() { cp_sh "script -qec \"kubectl -n falco-test exec -it target -- sh -c 'echo $1'\" /dev/null"; }
falco_tty_alert_since() { w1_sh "journalctl -u falco-modern-bpf --since '$1' --no-pager | grep -q 'shell was spawned in a container with an attached terminal.*k8s_ns_name=falco-test'"; }
check_6_8() {
  check_w1 "/etc/falco/falco_rules.yaml is unchanged" "! dpkg -V falco | grep -q falco_rules.yaml"
  check "reading /etc/shadow in falco-test/target raises a Critical alert" \
    falco_sees "cat /etc/shadow" "Critical Sensitive file opened for reading by non-trusted program.*k8s_ns_name=falco-test"
  local since; since="$(w1_sh 'date "+%Y-%m-%d %H:%M:%S"')"
  tty_shell "tty$RANDOM" >/dev/null 2>&1; sleep 4
  check "a shell with a terminal in falco-test/target raises no alert" bash -c "! falco_tty_alert_since '$since'"
}
solve_6_8() {
  onw1 <<'EOF'
cat > /etc/falco/rules.d/cks-override.yaml <<'YAML'
- rule: Read sensitive file untrusted
  priority: CRITICAL
  override:
    priority: replace

- rule: Terminal shell in container
  enabled: false
  override:
    enabled: replace
YAML
for i in $(seq 1 15); do journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -q 'cks-override.yaml' && break; sleep 2; done
journalctl -u falco-modern-bpf --since '-1min' --no-pager | grep -iE 'cks-override|error' | tail -2
EOF
}

# ---- Task 9: which pod hunts for keys? ----------------------------------------------------------
setup_6_9() {
  oncp <<'EOF'
kubectl create ns shop-runtime --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n shop-runtime get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n shop-runtime create deploy cart --image=nginx:1.27-alpine 2>/dev/null
kubectl -n shop-runtime create deploy inventory --image=busybox:1.36 -- sh -c 'while true; do find / -name id_rsa 2>/dev/null; sleep 15; done' 2>/dev/null
kubectl -n shop-runtime create deploy reports --image=busybox:1.36 -- sh -c 'while true; do ls / >/dev/null; sleep 15; done' 2>/dev/null
kubectl -n shop-runtime wait deploy --all --for=condition=Available --timeout=120s >/dev/null
mkdir -p /root/cks && rm -f /root/cks/falco-finding.txt
EOF
}
check_6_9() {
  check_cp "/root/cks/falco-finding.txt holds the rule name and shop-runtime/inventory" \
    "grep -qx 'Search Private Keys or Passwords' /root/cks/falco-finding.txt && grep -qx 'shop-runtime/inventory' /root/cks/falco-finding.txt"
  check_cp "Deployment inventory is gone" "! kubectl -n shop-runtime get deploy inventory"
  check_cp "Deployments cart and reports still run" "kubectl -n shop-runtime get deploy cart reports"
}
solve_6_9() {
  local line pod rule
  line="$(w1_sh "for i in \$(seq 1 30); do l=\$(journalctl -u falco-modern-bpf --since '-5min' --no-pager | grep 'k8s_ns_name=shop-runtime' | tail -1); [ -n \"\$l\" ] && echo \"\$l\" && break; sleep 2; done")"
  echo "  $line" | cut -c1-200
  pod="$(echo "$line" | grep -o 'k8s_pod_name=[^ ]*' | cut -d= -f2)"
  rule="$(w1_sh "journalctl -u falco-modern-bpf --since '-5min' --no-pager -o cat | grep -m1 'k8s_pod_name=$pod'" | sed 's/^[0-9:.]* [A-Za-z]* //' | cut -d'(' -f1 | sed 's/ *$//')"
  echo "  output text: $rule"
  oncp <<EOF
d=\$(kubectl -n shop-runtime get pod $pod -o jsonpath='{.metadata.labels.app}')
printf 'Search Private Keys or Passwords\nshop-runtime/%s\n' "\$d" > /root/cks/falco-finding.txt
cat /root/cks/falco-finding.txt
kubectl -n shop-runtime delete deploy "\$d"
EOF
}

# ---- Users with client certificates, for the audit tasks ---------------------------------------
# cks_users alice bob: writes /opt/cks-check/users/<name>.kubeconfig on cks-cp, signed by the cluster CA.
cks_users() {
  cp_sh "mkdir -p /opt/cks-check/users && cd /opt/cks-check/users
    SERVER=\$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    for u in $*; do
      [ -f \$u.kubeconfig ] && continue
      openssl req -newkey rsa:2048 -nodes -subj \"/CN=\$u/O=cks-users\" -keyout \$u.key -out \$u.csr 2>/dev/null
      openssl x509 -req -in \$u.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -days 30 -out \$u.crt 2>/dev/null
      kubectl config set-cluster cks --server=\$SERVER --certificate-authority=/etc/kubernetes/pki/ca.crt --embed-certs --kubeconfig=\$u.kubeconfig >/dev/null
      kubectl config set-credentials \$u --client-certificate=\$u.crt --client-key=\$u.key --embed-certs --kubeconfig=\$u.kubeconfig >/dev/null
      kubectl config set-context default --cluster=cks --user=\$u --kubeconfig=\$u.kubeconfig >/dev/null
      kubectl config use-context default --kubeconfig=\$u.kubeconfig >/dev/null
    done"
}
as_user() { local u="$1"; shift; cp_sh "kubectl --kubeconfig=/opt/cks-check/users/$u.kubeconfig $*"; }

# ---- Task 10: read the audit log like a detective -----------------------------------------------
setup_6_10() {
  if ! cp_sh "grep -q -- '--audit-policy-file=' /etc/kubernetes/manifests/kube-apiserver.yaml"; then
    echo "  task 6.10 needs audit logging from task 6.1; applying that solution first"
    solve_6_1 >/dev/null 2>&1
  fi
  cks_users alice bob carol
  oncp <<'EOF'
kubectl create ns hr --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n hr get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n hr create role secret-admin --verb=get,list,delete --resource=secrets 2>/dev/null
for u in alice bob carol; do kubectl -n hr create rolebinding $u-secrets --role=secret-admin --user=$u 2>/dev/null; done
for s in salaries old-salaries bonus; do kubectl -n hr create secret generic $s --from-literal=x=1 2>/dev/null; done
mkdir -p /root/cks && rm -f /root/cks/audit-answers.txt
EOF
  as_user carol -n hr get secrets >/dev/null
  as_user alice -n hr get secret salaries >/dev/null
  as_user carol -n hr get secret bonus >/dev/null
  as_user bob -n hr delete secret old-salaries >/dev/null
  as_user carol -n hr get secrets >/dev/null
  echo "  somebody has been busy in namespace hr"
}
check_6_10() {
  check_cp "line 1 of /root/cks/audit-answers.txt: alice read salaries" "sed -n 1p /root/cks/audit-answers.txt | grep -qx alice"
  check_cp "line 2: bob deleted old-salaries" "sed -n 2p /root/cks/audit-answers.txt | grep -qx bob"
  check_cp "line 3: carol listed the Secrets 2 times" "sed -n 3p /root/cks/audit-answers.txt | grep -qx 2"
  check_cp "bob may no longer delete Secrets in hr, alice and carol keep their rights" \
    "! kubectl auth can-i delete secrets -n hr --as=bob && kubectl auth can-i get secrets -n hr --as=alice && kubectl auth can-i list secrets -n hr --as=carol"
}
solve_6_10() {
  oncp <<'EOF'
L=/var/log/kubernetes/audit/audit.log
q() { python3 -c '
import json,sys
v,n=sys.argv[1],sys.argv[2]
for l in open("/var/log/kubernetes/audit/audit.log"):
    e=json.loads(l); o=e.get("objectRef",{})
    if e.get("stage")=="ResponseComplete" and o.get("namespace")=="hr" and o.get("resource")=="secrets" and e["verb"]==v and o.get("name","")==n:
        print(e["user"]["username"])' "$1" "$2"; }
{ q get salaries | sort -u; q delete old-salaries | sort -u; q list "" | grep -c '^carol$'; } > /root/cks/audit-answers.txt
cat /root/cks/audit-answers.txt
kubectl -n hr delete rolebinding bob-secrets
EOF
}

# ---- Task 11: an audit policy per user and per resource ------------------------------------------
AUDIT_POLICY_11='apiVersion: audit.k8s.io/v1
kind: Policy
omitStages: [RequestReceived]
rules:
- level: None
  users: ["system:kube-proxy"]
- level: None
  resources:
  - group: ""
    resources: [events]
- level: Metadata
  resources:
  - group: ""
    resources: [secrets, configmaps]
- level: RequestResponse
  users: [alice]
- level: Request
  verbs: [create, delete]
  resources:
  - group: ""
    resources: [pods]
- level: None'
setup_6_11() {
  if ! cp_sh "grep -q -- '--audit-policy-file=/etc/kubernetes/audit/policy.yaml' /etc/kubernetes/manifests/kube-apiserver.yaml"; then
    echo "  task 6.11 builds on task 6.1's flags; applying that solution first"
    solve_6_1 >/dev/null 2>&1
  elif ! cp_sh "grep -q 'namespaces: \[audit-me\]' /etc/kubernetes/audit/policy.yaml"; then
    echo "  putting task 6.1's policy back"
    solve_6_1 >/dev/null 2>&1; restart_apiserver
  fi
  cks_users alice
  oncp <<'EOF'
kubectl create ns audit-11 --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n audit-11 get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n audit-11 create rolebinding alice-edit --clusterrole=edit --user=alice 2>/dev/null
kubectl -n audit-11 create secret generic s1 --from-literal=x=1 2>/dev/null
cat /etc/kubernetes/audit/policy.yaml
EOF
}
# Makes fresh traffic, then asks the log for one entry. Arguments: a JSON filter as in audit_has.
audit11() { audit_has "$1"; }
check_6_11() {
  local m="m$RANDOM"
  as_user alice -n audit-11 get secret s1 >/dev/null 2>&1
  as_user alice -n audit-11 create deploy "a$m" --image=busybox:1.36 -- sleep 1 >/dev/null 2>&1
  cp_sh "kubectl -n audit-11 run p$m --image=busybox:1.36 -- sleep 1 >/dev/null; kubectl -n audit-11 get pod p$m >/dev/null; kubectl -n audit-11 create configmap c$m --from-literal=a=b >/dev/null; sleep 3" >/dev/null 2>&1
  check "alice's get on a Secret appears at Metadata" audit_has '{"resource":"secrets","namespace":"audit-11","name":"s1","verb":"get","level":"Metadata"}'
  check "alice's Deployment create appears at RequestResponse" \
    audit_has "{\"resource\":\"deployments\",\"namespace\":\"audit-11\",\"name\":\"a$m\",\"verb\":\"create\",\"level\":\"RequestResponse\",\"has\":[\"responseObject\"]}"
  check "an admin's pod create appears at Request" \
    audit_has "{\"resource\":\"pods\",\"namespace\":\"audit-11\",\"name\":\"p$m\",\"verb\":\"create\",\"level\":\"Request\"}"
  check "an admin's pod get does not appear" audit_lacks "{\"resource\":\"pods\",\"namespace\":\"audit-11\",\"name\":\"p$m\",\"verb\":\"get\"}"
  check "a ConfigMap create appears at Metadata" \
    audit_has "{\"resource\":\"configmaps\",\"namespace\":\"audit-11\",\"name\":\"c$m\",\"verb\":\"create\",\"level\":\"Metadata\"}"
  check "events appear nowhere in the log since the change" \
    cp_sh "f=/var/log/kubernetes/audit/audit.log; t=\$(stat -c %Y /etc/kubernetes/audit/policy.yaml); python3 -c '
import json,sys,datetime
t=float(sys.argv[1])
for l in open(\"/var/log/kubernetes/audit/audit.log\"):
    e=json.loads(l)
    ts=datetime.datetime.fromisoformat(e[\"requestReceivedTimestamp\"].replace(\"Z\",\"+00:00\")).timestamp()
    if ts>t+60 and e.get(\"objectRef\",{}).get(\"resource\")==\"events\": sys.exit(1)' \$t"
}
solve_6_11() {
  cp_sh "cp /etc/kubernetes/audit/policy.yaml /root/policy.yaml.before-6.11 && cat > /etc/kubernetes/audit/policy.yaml <<'YAML'
$AUDIT_POLICY_11
YAML"
  restart_apiserver
}

# ---- Task 12: AppArmor for a Deployment (Lima) ----------------------------------------------------
setup_6_12() {
  need_lima || return 1
  onlima <<'EOF'
cat > /etc/apparmor.d/cks-nginx <<'PROFILE'
#include <tunables/global>

profile cks-nginx flags=(attach_disconnected,mediate_deleted) {
  #include <abstractions/base>
  network,
  capability,
  file,
  umount,
  deny /usr/share/nginx/html/** w,
}
PROFILE
apparmor_parser -R /etc/apparmor.d/cks-nginx 2>/dev/null; true
kubectl create ns aa-web --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n aa-web get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n aa-web delete deploy web --ignore-not-found >/dev/null
kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata: {name: web, namespace: aa-web}
spec:
  selector: {matchLabels: {app: web}}
  template:
    metadata: {labels: {app: web}}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        securityContext:
          appArmorProfile: {type: Localhost, localhostProfile: cks-nginx}
YAML
sleep 15
kubectl -n aa-web get pods -o wide --no-headers | awk '{print "  " $1, $3}'
kubectl -n aa-web get events --field-selector reason=Failed -o jsonpath='{range .items[-1:]}  {.message}{"\n"}{end}' 2>/dev/null
EOF
}
check_6_12() {
  check_lima "profile cks-nginx is loaded in enforce mode" \
    "aa-status 2>/dev/null | sed -n '/profiles are in enforce mode/,/profiles are in complain mode/p' | grep -qx '   cks-nginx'"
  check_lima "Deployment web has a ready pod" "kubectl -n aa-web rollout status deploy web --timeout=90s"
  check_lima "a write below /usr/share/nginx/html fails with Permission denied" \
    "kubectl -n aa-web exec deploy/web -- sh -c 'echo x > /usr/share/nginx/html/index.html' 2>&1 | grep -q 'Permission denied'"
  check_lima "a write to /tmp still works, and nginx serves" \
    "kubectl -n aa-web exec deploy/web -- sh -c 'echo ok > /tmp/x' && kubectl -n aa-web exec deploy/web -- wget -qO- -T 3 http://127.0.0.1 | grep -q nginx"
}
solve_6_12() {
  need_lima || return 1
  onlima <<'EOF'
apparmor_parser -r /etc/apparmor.d/cks-nginx
aa-status | grep cks-nginx
kubectl -n aa-web rollout restart deploy web
kubectl -n aa-web rollout status deploy web --timeout=120s
EOF
}

# ---- Task 13: pods that are not immutable ---------------------------------------------------------
setup_6_13() {
  oncp <<'EOF'
kubectl create ns immutable-check --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n immutable-check get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl label ns immutable-check pod-security.kubernetes.io/enforce=privileged --overwrite >/dev/null
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: frozen, namespace: immutable-check}
spec:
  containers:
  - {name: c, image: busybox:1.36, command: [sleep, 1d], securityContext: {readOnlyRootFilesystem: true}}
---
apiVersion: v1
kind: Pod
metadata: {name: frozen-too, namespace: immutable-check}
spec:
  containers:
  - name: c
    image: nginx:1.27-alpine
    securityContext: {readOnlyRootFilesystem: true}
    volumeMounts: [{name: cache, mountPath: /var/cache/nginx}, {name: run, mountPath: /run}, {name: tmp, mountPath: /tmp}]
  volumes: [{name: cache, emptyDir: {}}, {name: run, emptyDir: {}}, {name: tmp, emptyDir: {}}]
---
apiVersion: v1
kind: Pod
metadata: {name: writable, namespace: immutable-check}
spec:
  containers:
  - {name: c, image: busybox:1.36, command: [sleep, 1d]}
---
apiVersion: v1
kind: Pod
metadata: {name: half-frozen, namespace: immutable-check}
spec:
  containers:
  - {name: a, image: busybox:1.36, command: [sleep, 1d], securityContext: {readOnlyRootFilesystem: true}}
  - {name: b, image: busybox:1.36, command: [sleep, 1d]}
---
apiVersion: v1
kind: Pod
metadata: {name: frozen-but-privileged, namespace: immutable-check}
spec:
  containers:
  - {name: c, image: busybox:1.36, command: [sleep, 1d], securityContext: {readOnlyRootFilesystem: true, privileged: true}}
YAML
kubectl -n immutable-check wait pod --all --for=condition=Ready --timeout=120s >/dev/null
kubectl -n immutable-check get pods --no-headers | awk '{print "  " $1}'
EOF
}
check_6_13() {
  check_cp "writable, half-frozen and frozen-but-privileged are gone" \
    "! kubectl -n immutable-check get pod writable 2>/dev/null && ! kubectl -n immutable-check get pod half-frozen 2>/dev/null && ! kubectl -n immutable-check get pod frozen-but-privileged 2>/dev/null"
  check_cp "frozen and frozen-too still run" "kubectl -n immutable-check get pod frozen frozen-too"
}
solve_6_13() {
  oncp <<'EOF'
kubectl -n immutable-check get pods -o json | python3 -c '
import json,sys
for p in json.load(sys.stdin)["items"]:
    cs=p["spec"]["containers"]
    ok=all((c.get("securityContext") or {}).get("readOnlyRootFilesystem") and not (c.get("securityContext") or {}).get("privileged") for c in cs)
    if not ok: print(p["metadata"]["name"])' | while read p; do echo "deleting $p"; kubectl -n immutable-check delete pod $p --now >/dev/null; done
EOF
}
