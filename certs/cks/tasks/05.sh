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
grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q ImagePolicyWebhook || \
  sed -i 's/\(--enable-admission-plugins=.*\)$/\1,ImagePolicyWebhook/' /etc/kubernetes/manifests/kube-apiserver.yaml
EOF
  set_flag kube-apiserver --admission-control-config-file /etc/kubernetes/admission/admission-config.yaml
  apiserver_mount admission /etc/kubernetes/admission
  apiserver_mount policy-webhook /etc/kubernetes/policy-webhook
  sleep 5; wait_api
}

# Starts a task from task 5.5's result: ImagePolicyWebhook on, back end running.
ipw_base() {
  if ! cp_sh "grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q ImagePolicyWebhook"; then
    echo "  this task starts from task 5.5's result; applying that solution first"
    solve_5_5 >/dev/null 2>&1
  fi
  cp_sh 'systemctl start image-policy'
}

# ---- Task 6: the webhook's files are wrong --------------------------------------------------
setup_5_6() {
  ipw_base
  oncp <<'EOF'
cp /etc/kubernetes/admission/admission-config.yaml /root/admission-config.yaml.before-5.6
cp /etc/kubernetes/policy-webhook/kubeconfig.yaml /root/policy-kubeconfig.yaml.before-5.6
sed -i 's|kubeConfigFile: .*|kubeConfigFile: /etc/kubernetes/webhook/kubeconfig.yaml|' /etc/kubernetes/admission/admission-config.yaml
sed -i 's|certificate-authority: .*|certificate-authority: /etc/kubernetes/pki/ca.crt|' /etc/kubernetes/policy-webhook/kubeconfig.yaml
# Make the kubelet restart the API server so it reads the broken files.
mv /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.tmp
for i in $(seq 1 30); do crictl ps --name kube-apiserver -q | grep -q . || break; sleep 2; done
mv /root/kube-apiserver.yaml.tmp /etc/kubernetes/manifests/kube-apiserver.yaml
echo "  the API server restarted with the changed files at $(date +%H:%M:%S)"
EOF
}
check_5_6() {
  check_cp "the API server answers" "kubectl get --raw=/readyz"
  check_cp "ImagePolicyWebhook stays enabled, with defaultAllow: false" \
    "grep -- '--enable-admission-plugins=' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -q ImagePolicyWebhook && grep -q 'defaultAllow: false' /etc/kubernetes/admission/admission-config.yaml"
  check_cp "a pod with busybox:1.36 is admitted" "kubectl run ipw6-ok --image=busybox:1.36 --dry-run=server -- sleep 1"
  check_cp "a pod from quay.io/evil is refused by the back end" \
    "kubectl run ipw6-bad --image=quay.io/evil/miner:1 --dry-run=server 2>&1 | grep -q 'not from an allowed registry'"
}
solve_5_6() {
  oncp <<'EOF'
for c in $(crictl ps -a --name kube-apiserver --state exited -q | head -1); do crictl logs $c 2>&1 | grep run.go | tail -1; done
sed -i 's|kubeConfigFile: .*|kubeConfigFile: /etc/kubernetes/policy-webhook/kubeconfig.yaml|' /etc/kubernetes/admission/admission-config.yaml
sed -i 's|certificate-authority: .*|certificate-authority: /etc/kubernetes/policy-webhook/ca.crt|' /etc/kubernetes/policy-webhook/kubeconfig.yaml
EOF
  restart_apiserver
}

# ---- Task 7: the back end is down and nobody noticed ------------------------------------------
setup_5_7() {
  ipw_base
  oncp <<'EOF'
cp /etc/kubernetes/admission/admission-config.yaml /root/admission-config.yaml.before-5.7
sed -i 's/defaultAllow: false/defaultAllow: true/' /etc/kubernetes/admission/admission-config.yaml
systemctl disable --now image-policy >/dev/null 2>&1
EOF
  restart_apiserver
  cp_sh 'echo "  quay.io/evil/miner:1 today: $(kubectl run probe --image=quay.io/evil/miner:1 --dry-run=server 2>&1 | tail -1)"'
}
check_5_7() {
  check_cp "the admission configuration sets defaultAllow: false" "grep -q 'defaultAllow: false' /etc/kubernetes/admission/admission-config.yaml"
  check_cp "the image-policy service runs and starts at boot" "systemctl is-active -q image-policy && systemctl is-enabled -q image-policy"
  check_cp "a pod with busybox:1.36 is admitted" "kubectl run ipw7-ok --image=busybox:1.36 --dry-run=server -- sleep 1"
  check_cp "a pod from quay.io/evil is refused" "! kubectl run ipw7-bad --image=quay.io/evil/miner:1 --dry-run=server"
}
solve_5_7() {
  oncp <<'EOF'
journalctl -u image-policy -n 2 --no-pager
sed -i 's/defaultAllow: true/defaultAllow: false/' /etc/kubernetes/admission/admission-config.yaml
systemctl enable --now image-policy
EOF
  restart_apiserver
}

# ---- Task 8: pin an image by digest -----------------------------------------------------------
setup_5_8() {
  oncp <<'EOF'
kubectl create ns pinned --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n pinned get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n pinned create deploy web --image=nginx:1.27-alpine 2>/dev/null
kubectl -n pinned rollout status deploy web --timeout=120s
EOF
}
check_5_8() {
  check_cp "Deployment web names its image by a sha256 digest" \
    "kubectl -n pinned get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qE '^(docker.io/library/)?nginx(:1.27-alpine)?@sha256:[0-9a-f]{64}\$'"
  local want
  want="$(w1_sh "crictl inspecti -o json docker.io/library/nginx:1.27-alpine | python3 -c 'import json,sys; print(json.load(sys.stdin)[\"status\"][\"repoDigests\"][0].split(\"@\")[1])'")"
  check "the digest is the one nginx:1.27-alpine had on the node" \
    bash -c "[ -n \"\$1\" ] && orb -m $CKS_CP -u root kubectl -n pinned get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qF \"\$1\"" _ "$want"
  check_cp "the Deployment has a ready pod" "kubectl -n pinned rollout status deploy web --timeout=90s"
}
solve_5_8() {
  oncp <<'EOF'
ID=$(kubectl -n pinned get pod -l app=web -o jsonpath='{.items[0].status.containerStatuses[0].imageID}')
echo "imageID: $ID"
kubectl -n pinned set image deploy/web nginx="nginx@${ID#*@}"
kubectl -n pinned rollout status deploy web --timeout=120s
EOF
}

# ---- Task 9: scan what the cluster runs ---------------------------------------------------------
setup_5_9() {
  oncp <<'EOF'
for n in prod-a prod-b; do kubectl create ns $n --dry-run=client -o yaml | kubectl apply -f - >/dev/null; done
for n in prod-a prod-b; do for i in $(seq 1 30); do kubectl -n $n get sa default >/dev/null 2>&1 && break; sleep 1; done; done
kubectl -n prod-a create deploy web --image=nginx:1.19.0 2>/dev/null
kubectl -n prod-a create deploy tools --image=busybox:1.36 -- sleep 1d 2>/dev/null
kubectl -n prod-b create deploy cache --image=redis:6.0.5 2>/dev/null
kubectl -n prod-b create deploy pause --image=registry.k8s.io/pause:3.10 2>/dev/null
for n in prod-a prod-b; do kubectl -n $n wait deploy --all --for=condition=Available --timeout=180s >/dev/null; done
mkdir -p /root/cks && rm -f /root/cks/critical-images.txt
EOF
}
# Lists, sorted, the images in prod-a and prod-b that trivy finds CRITICAL vulnerabilities in.
critical_images() {
  cp_sh 'for img in $(kubectl get deploy -n prod-a -o jsonpath="{.items[*].spec.template.spec.containers[*].image}") $(kubectl get deploy -n prod-b -o jsonpath="{.items[*].spec.template.spec.containers[*].image}"); do
    n=$(trivy image --quiet --severity CRITICAL --format json "$img" 2>/dev/null | python3 -c "import json,sys; print(sum(len(r.get(\"Vulnerabilities\") or []) for r in json.load(sys.stdin).get(\"Results\",[])))")
    [ "$n" -gt 0 ] && echo "$img"; done | sort'
}
check_5_9() {
  local want; want="$(critical_images)"
  check "/root/cks/critical-images.txt lists exactly the images with CRITICAL findings" \
    bash -c "[ -n \"\$1\" ] && [ \"\$1\" = \"\$(orb -m $CKS_CP -u root cat /root/cks/critical-images.txt 2>/dev/null | sort)\" ]" _ "$want"
  check_cp "the Deployments running those images are scaled to 0" \
    "for d in prod-a/web prod-b/cache; do r=\$(kubectl -n \${d%/*} get deploy \${d#*/} -o jsonpath='{.spec.replicas}'); [ \"\$r\" = 0 ] || exit 1; done"
  check_cp "the Deployments with clean images keep their replica" \
    "for d in prod-a/tools prod-b/pause; do r=\$(kubectl -n \${d%/*} get deploy \${d#*/} -o jsonpath='{.spec.replicas}'); [ \"\$r\" = 1 ] || exit 1; done"
}
solve_5_9() {
  oncp <<'EOF'
for n in prod-a prod-b; do
  for d in $(kubectl -n $n get deploy -o name); do
    img=$(kubectl -n $n get $d -o jsonpath='{.spec.template.spec.containers[0].image}')
    c=$(trivy image --quiet --severity CRITICAL --format json "$img" | python3 -c 'import json,sys; print(sum(len(r.get("Vulnerabilities") or []) for r in json.load(sys.stdin).get("Results",[])))')
    echo "$n $d $img CRITICAL=$c"
    if [ "$c" -gt 0 ]; then echo "$img" >> /root/cks/critical-images.txt; kubectl -n $n scale $d --replicas=0 >/dev/null; fi
  done
done
sort -o /root/cks/critical-images.txt /root/cks/critical-images.txt
EOF
}

# ---- Task 10: which SBOM carries the risk? -------------------------------------------------------
setup_5_10() {
  oncp <<'EOF'
mkdir -p /root/cks/sboms && cd /root/cks/sboms && rm -f *.json /root/cks/risky-sboms.txt
i=0
for img in busybox:1.36 nginx:1.19.0 registry.k8s.io/pause:3.10; do
  i=$((i+1))
  trivy image --quiet --format cyclonedx "$img" 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); d["metadata"]["component"]["name"]="app-'$i'"; print(json.dumps(d))' > app-$i.cdx.json
done
ls /root/cks/sboms
EOF
}
risky_sboms() {
  cp_sh 'cd /root/cks/sboms && for f in app-*.cdx.json; do n=$(trivy sbom --quiet --severity CRITICAL --format json $f 2>/dev/null | python3 -c "import json,sys; print(sum(len(r.get(\"Vulnerabilities\") or []) for r in json.load(sys.stdin).get(\"Results\",[])))"); [ "$n" -gt 0 ] && echo $f; done | sort'
}
check_5_10() {
  local want; want="$(risky_sboms)"
  check "/root/cks/risky-sboms.txt names exactly the SBOMs with CRITICAL findings" \
    bash -c "[ -n \"\$1\" ] && [ \"\$1\" = \"\$(orb -m $CKS_CP -u root cat /root/cks/risky-sboms.txt 2>/dev/null | sort)\" ]" _ "$want"
}
solve_5_10() {
  oncp <<'EOF'
cd /root/cks/sboms
for f in app-*.cdx.json; do echo "$f: $(trivy sbom --quiet --severity CRITICAL $f 2>/dev/null | grep -m1 Total)"; done
for f in app-*.cdx.json; do trivy sbom --quiet --severity CRITICAL --exit-code 1 $f >/dev/null 2>&1 || echo $f; done > /root/cks/risky-sboms.txt
cat /root/cks/risky-sboms.txt
EOF
}
