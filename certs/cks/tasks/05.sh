# Domain 05, supply chain security. Functions for task.sh: setup_5_N, check_5_N, solve_5_N.

# ---- Task 1: shrink a Dockerfile ------------------------------------------------------
setup_5_1() {
  oncp <<'EOF'
mkdir -p /root/cks/app
printf 'import http.server\nhttp.server.HTTPServer(("", 8080), http.server.SimpleHTTPRequestHandler).serve_forever()\n' > /root/cks/app/app.py
cat > /root/cks/app/Dockerfile <<'DOCKERFILE'
FROM ubuntu:latest
RUN apt-get update && apt-get install -y python3 curl wget netcat-openbsd vim
COPY app.py /app/app.py
USER root
CMD ["python3", "/app/app.py"]
DOCKERFILE
cat /root/cks/app/Dockerfile
EOF
}
check_5_1() {
  local f=/root/cks/app/Dockerfile
  check_cp "the base image has an explicit tag, not latest" "grep -iE '^FROM ' $f | grep -vqE ':latest|^FROM +[^:]+\$'"
  check_cp "the base image is a slim, alpine or distroless variant" "grep -iE '^FROM ' $f | grep -qE 'alpine|slim|distroless'"
  check_cp "no RUN line installs curl, wget, netcat or vim" "! grep -iE '^RUN ' $f | grep -qE 'curl|wget|netcat|vim'"
  check_cp "the last USER is neither root nor 0" "grep -iE '^USER ' $f | tail -1 | grep -vqE 'USER +(root|0)\$'"
}
solve_5_1() {
  oncp <<'EOF'
cat > /root/cks/app/Dockerfile <<'DOCKERFILE'
FROM python:3.13-alpine
COPY app.py /app/app.py
USER 65534
CMD ["python3", "/app/app.py"]
DOCKERFILE
EOF
}

# ---- Task 2: find and remove vulnerable images ----------------------------------------
setup_5_2() {
  oncp <<'EOF'
kubectl create ns scan --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n scan get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n scan run web --image=nginx:1.19.0 2>/dev/null
kubectl -n scan run cache --image=redis:6.0.5 2>/dev/null
kubectl -n scan run tools --image=busybox:1.36 -- sleep 1d 2>/dev/null
kubectl -n scan wait pod --all --for=condition=Ready --timeout=180s
EOF
}
check_5_2() {
  check_cp "pod web (nginx:1.19.0, CRITICAL findings) is gone" "! kubectl -n scan get pod web"
  check_cp "pod cache (redis:6.0.5, CRITICAL findings) is gone" "! kubectl -n scan get pod cache"
  check_cp "pod tools (busybox:1.36, no CRITICAL findings) still runs" "kubectl -n scan get pod tools -o jsonpath='{.status.phase}' | grep -qx Running"
}
solve_5_2() {
  oncp <<'EOF'
for p in $(kubectl -n scan get pods -o name); do
  img=$(kubectl -n scan get $p -o jsonpath='{.spec.containers[0].image}')
  n=$(trivy image --quiet --severity CRITICAL --format json "$img" | python3 -c 'import json,sys; print(sum(len(r.get("Vulnerabilities") or []) for r in json.load(sys.stdin).get("Results",[])))')
  echo "$p $img CRITICAL=$n"
  [ "$n" -gt 0 ] && kubectl -n scan delete $p --now
done
EOF
}

# ---- Task 3: write an SBOM --------------------------------------------------------------
setup_5_3() {
  cp_sh 'mkdir -p /root/cks && rm -f /root/cks/kube-proxy.spdx.json /root/cks/kube-proxy.cdx.json /root/cks/iptables-version.txt && echo "  /root/cks is ready"'
}
check_5_3() {
  check_cp "/root/cks/kube-proxy.spdx.json is SPDX JSON for kube-proxy v1.37.1" \
    "python3 -c 'import json,sys; d=json.load(open(\"/root/cks/kube-proxy.spdx.json\")); sys.exit(0 if d[\"spdxVersion\"].startswith(\"SPDX-2\") and \"kube-proxy\" in json.dumps(d) and len(d[\"packages\"])>50 else 1)'"
  check_cp "/root/cks/kube-proxy.cdx.json is a CycloneDX SBOM" \
    "python3 -c 'import json,sys; d=json.load(open(\"/root/cks/kube-proxy.cdx.json\")); sys.exit(0 if d[\"bomFormat\"]==\"CycloneDX\" and len(d[\"components\"])>50 else 1)'"
  check_cp "/root/cks/iptables-version.txt holds the iptables version from the SBOM" \
    "v=\$(python3 -c 'import json; print([p[\"versionInfo\"] for p in json.load(open(\"/root/cks/kube-proxy.spdx.json\"))[\"packages\"] if p[\"name\"]==\"iptables\"][0])') && grep -qx \"\$v\" /root/cks/iptables-version.txt"
}
solve_5_3() {
  oncp <<'EOF'
cd /root/cks
bom generate --image registry.k8s.io/kube-proxy:v1.37.1 --format json --output kube-proxy.spdx.json 2>/dev/null
trivy image --quiet --format cyclonedx --output kube-proxy.cdx.json registry.k8s.io/kube-proxy:v1.37.1
grep -A3 '"name": "iptables"' kube-proxy.spdx.json | grep -m1 versionInfo | cut -d'"' -f4 > iptables-version.txt
cat iptables-version.txt
EOF
}

# ---- Task 4: static analysis with kubesec -----------------------------------------------
setup_5_4() {
  oncp <<'EOF'
mkdir -p /root/cks
cat > /root/cks/report.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: report
  namespace: reports
spec:
  hostPID: true
  containers:
  - name: report
    image: busybox:1.36
    command: [sleep, 1d]
    securityContext:
      privileged: true
YAML
kubectl create ns reports --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubesec scan /root/cks/report.yaml | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print("score", r["score"], "critical", [c["id"] for c in r["scoring"].get("critical",[])])'
EOF
}
check_5_4() {
  local q='import json,sys; r=json.load(sys.stdin)[0]; sys.exit(0 if r["score"]>=8 and not r["scoring"].get("critical") else 1)'
  check_cp "kubesec finds no critical issue and scores 8 or more" "kubesec scan /root/cks/report.yaml | python3 -c '$q'"
  check_cp "pod report runs in namespace reports" \
    "kubectl -n reports wait pod report --for=condition=Ready --timeout=90s"
  check_cp "the running pod has no hostPID and is not privileged" \
    "! kubectl -n reports get pod report -o jsonpath='{.spec.hostPID}{.spec.containers[0].securityContext.privileged}' | grep -q true"
}
solve_5_4() {
  oncp <<'EOF'
cat > /root/cks/report.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: report
  namespace: reports
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
  - name: report
    image: busybox:1.36
    command: [sleep, 1d]
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: {drop: [ALL]}
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
YAML
kubesec scan /root/cks/report.yaml | python3 -c 'import json,sys; r=json.load(sys.stdin)[0]; print("score", r["score"], "critical", [c["id"] for c in r["scoring"].get("critical",[])])'
kubectl delete -f /root/cks/report.yaml --ignore-not-found --now >/dev/null
kubectl apply -f /root/cks/report.yaml
kubectl -n reports wait pod report --for=condition=Ready --timeout=90s
EOF
}

# ---- Task 5: allow only approved registries ---------------------------------------------
setup_5_5() {
  cp_sh 'systemctl is-active image-policy; cat /etc/image-policy/allowed-registries; ls /etc/kubernetes/policy-webhook/'
}
check_5_5() {
  check_cp "the API server enables ImagePolicyWebhook" \
    "grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q ImagePolicyWebhook"
  check_cp "the admission configuration sets defaultAllow: false" \
    "f=\$(grep -- '--admission-control-config-file=' /etc/kubernetes/manifests/kube-apiserver.yaml | cut -d= -f2) && grep -q 'defaultAllow: false' \$f"
  check_cp "a pod with busybox:1.36 is admitted" "kubectl run ipw-ok --image=busybox:1.36 --dry-run=server -- sleep 1"
  check_cp "a pod with nginx:latest is refused" "! kubectl run ipw-latest --image=nginx:latest --dry-run=server"
  check_cp "a pod from quay.io/evil is refused" "! kubectl run ipw-evil --image=quay.io/evil/miner:1 --dry-run=server"
}
solve_5_5() {
  oncp <<'EOF'
mkdir -p /etc/kubernetes/admission
cat > /etc/kubernetes/admission/admission-config.yaml <<'YAML'
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
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.before-5.5
sed -i 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=NodeRestriction,ImagePolicyWebhook/' /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
  set_flag kube-apiserver --admission-control-config-file /etc/kubernetes/admission/admission-config.yaml
  apiserver_mount admission /etc/kubernetes/admission
  apiserver_mount policy-webhook /etc/kubernetes/policy-webhook
  sleep 5; wait_api
}
