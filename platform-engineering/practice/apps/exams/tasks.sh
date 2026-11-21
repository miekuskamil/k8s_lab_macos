# Practice exam 1: one topic per task. setup_mN seeds task N, score_mN checks it, solve_mN
# is the reference solution. Sourced by setup.sh, score.sh and solve.sh after tasks/lib.sh.

MOCK_TASKS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16"
mock_points() {
  case "$1" in
    1) echo 8;; 2) echo 6;; 3) echo 5;; 4) echo 6;; 5) echo 6;; 6) echo 6;; 7) echo 6;; 8) echo 6;;
    9) echo 5;; 10) echo 4;; 11) echo 8;; 12) echo 6;; 13) echo 8;; 14) echo 6;; 15) echo 8;; 16) echo 6;;
  esac
}
mock_title() {
  case "$1" in
    1) echo "Build, push and run an image";; 2) echo "A log sidecar";; 3) echo "A nightly CronJob";;
    4) echo "Update, then roll back";; 5) echo "A quarter of the traffic";; 6) echo "A Helm release";;
    7) echo "A Kustomize overlay";; 8) echo "Probes for an API";; 9) echo "Why the pod crashes";;
    10) echo "The hungriest pod";; 11) echo "ConfigMap and Secret";; 12) echo "Defaults and requests";;
    13) echo "A ServiceAccount that reads ConfigMaps";; 14) echo "Run as a normal user";;
    15) echo "Service and Ingress";; 16) echo "Only the frontend reaches the API";;
  esac
}

# ---- 1. Build, push and run an image (8) -------------------------------------------------
setup_m1() {
  ns_new k1-build
  put_file /opt/apps/m1/1/Dockerfile <<'EOF'
FROM docker.io/library/busybox:1.36
WORKDIR /app
COPY ticker.sh .
ENV INTERVAL=5
CMD ["sh", "ticker.sh"]
EOF
  put_file /opt/apps/m1/1/ticker.sh <<'EOF'
while true; do echo "tick from $(hostname) every ${INTERVAL}s"; sleep "$INTERVAL"; done
EOF
}
score_m1() {
  check_cp "the registry holds ticker:1.0" "curl -fsS http://registry.practice:5000/v2/ticker/tags/list | grep -q '\"1.0\"'"
  check_cp "Deployment ticker in k1-build runs registry.practice:5000/ticker:1.0 with 2 ready pods" \
    "kubectl -n k1-build get deploy ticker -o jsonpath='{.spec.template.spec.containers[0].image} {.status.readyReplicas}' | grep -qx 'registry.practice:5000/ticker:1.0 2'"
  check_cp "its pods log 'tick from'" "kubectl -n k1-build logs deploy/ticker | grep -q 'tick from'"
  check_cp "/opt/apps/m1/1/ticker.tar holds the image" "tar -tf /opt/apps/m1/1/ticker.tar | grep -q manifest.json"
}
solve_m1() {
  cp_sh 'cd /opt/apps/m1/1 && podman build -q -t registry.practice:5000/ticker:1.0 . && podman push -q registry.practice:5000/ticker:1.0 && podman save -q -o ticker.tar registry.practice:5000/ticker:1.0
    kubectl -n k1-build create deploy ticker --image=registry.practice:5000/ticker:1.0 --replicas=2
    kubectl -n k1-build rollout status deploy ticker --timeout=120s'
}

# ---- 2. A log sidecar (6) -------------------------------------------------------------------
setup_m2() {
  ns_new k1-pods
  put_file /opt/apps/m1/2/audit.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: audit
  namespace: k1-pods
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date +%T) user login\" >> /var/log/audit.log; sleep 2; done"]
EOF
}
score_m2() {
  check_json "pod audit has a native sidecar log-tail" "kubectl -n k1-pods get pod audit -o json" \
    'any(c["name"]=="log-tail" and c.get("restartPolicy")=="Always" for c in p["spec"].get("initContainers",[]))'
  check_cp "app and log-tail share an emptyDir at /var/log" \
    "kubectl -n k1-pods get pod audit -o json | python3 -c 'import json,sys; s=json.load(sys.stdin)[\"spec\"]; v=[x[\"name\"] for x in s[\"volumes\"] if \"emptyDir\" in x]; cs=s[\"containers\"]+s[\"initContainers\"]; sys.exit(0 if all(any(m[\"name\"] in v and m[\"mountPath\"]==\"/var/log\" for m in c.get(\"volumeMounts\",[])) for c in cs) else 1)'"
  check_cp "kubectl logs audit -c log-tail shows the logins" \
    "for i in \$(seq 1 15); do kubectl -n k1-pods logs audit -c log-tail 2>/dev/null | grep -q 'user login' && exit 0; sleep 2; done; exit 1"
}
solve_m2() {
  put_file /opt/apps/m1/2/audit.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: audit
  namespace: k1-pods
spec:
  initContainers:
  - name: log-tail
    image: busybox:1.36
    restartPolicy: Always
    command: ["sh", "-c", "tail -F /var/log/audit.log"]
    volumeMounts:
    - {name: logs, mountPath: /var/log}
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo \"$(date +%T) user login\" >> /var/log/audit.log; sleep 2; done"]
    volumeMounts:
    - {name: logs, mountPath: /var/log}
  volumes:
  - name: logs
    emptyDir: {}
EOF
  cp_sh 'kubectl apply -f /opt/apps/m1/2/audit.yaml && kubectl -n k1-pods wait pod audit --for=condition=Ready --timeout=90s'
}

# ---- 3. A nightly CronJob (5) ---------------------------------------------------------------
setup_m3() { ns_new k1-batch; }
score_m3() {
  check_json "CronJob report runs at 01:30 every day, keeps 1 good and 1 failed Job" "kubectl -n k1-batch get cronjob report -o json" \
    's=p["spec"]; s["schedule"]=="30 1 * * *" and s["successfulJobsHistoryLimit"]==1 and s["failedJobsHistoryLimit"]==1'
  check_json "its Job retries at most twice and its pods never restart in place" "kubectl -n k1-batch get cronjob report -o json" \
    'j=p["spec"]["jobTemplate"]["spec"]; j["backoffLimit"]==2 and j["template"]["spec"]["restartPolicy"]=="Never"'
  check_cp "Job report-now ran from it and printed 'report done'" \
    "kubectl -n k1-batch wait job report-now --for=condition=Complete --timeout=10s && kubectl -n k1-batch logs job/report-now | grep -q 'report done'"
}
solve_m3() {
  cp_sh "kubectl -n k1-batch create cronjob report --image=busybox:1.36 --schedule='30 1 * * *' --dry-run=client -o json -- sh -c 'echo report done' \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d[\"spec\"]; s[\"successfulJobsHistoryLimit\"]=1; s[\"failedJobsHistoryLimit\"]=1; j=s[\"jobTemplate\"][\"spec\"]; j[\"backoffLimit\"]=2; j[\"template\"][\"spec\"][\"restartPolicy\"]=\"Never\"; print(json.dumps(d))' \
    | kubectl apply -f -
    kubectl -n k1-batch create job report-now --from=cronjob/report
    kubectl -n k1-batch wait job report-now --for=condition=Complete --timeout=60s"
}

# ---- 4. Update, then roll back (6) ------------------------------------------------------------
setup_m4() {
  ns_new k1-roll
  cp_sh 'kubectl -n k1-roll create deploy store --image=nginx:1.27-alpine --replicas=2 >/dev/null
    kubectl -n k1-roll rollout status deploy store --timeout=120s >/dev/null'
}
score_m4() {
  check_cp "Deployment store has three revisions and runs nginx:1.27-alpine again" \
    "[ \$(kubectl -n k1-roll get rs -l app=store --no-headers | wc -l) -ge 2 ] && kubectl -n k1-roll get deploy store -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision} {.spec.template.spec.containers[0].image}' | grep -qx '3 nginx:1.27-alpine'"
  check_cp "/opt/apps/m1/4/history.txt holds the history with the 1.28 update" "grep -q 'image 1.28' /opt/apps/m1/4/history.txt"
  check_cp "both pods are ready" "kubectl -n k1-roll rollout status deploy store --timeout=10s"
}
solve_m4() {
  cp_sh "mkdir -p /opt/apps/m1/4
    kubectl -n k1-roll set image deploy/store nginx=nginx:1.28-alpine
    kubectl -n k1-roll annotate deploy store kubernetes.io/change-cause='image 1.28' --overwrite
    kubectl -n k1-roll rollout status deploy store --timeout=120s
    kubectl -n k1-roll rollout history deploy store > /opt/apps/m1/4/history.txt
    kubectl -n k1-roll rollout undo deploy store
    kubectl -n k1-roll rollout status deploy store --timeout=120s"
}

# ---- 5. A quarter of the traffic (6) --------------------------------------------------------------------
setup_m5() {
  ns_new k1-canary
  echo_deploy k1-canary checkout-v1 v1 3 app=checkout version=v1
  cp_sh 'kubectl -n k1-canary expose deploy checkout-v1 --name=checkout --port=80 --target-port=8080 --selector=app=checkout >/dev/null'
  client_pod k1-canary client
}
score_m5() {
  check_cp "Deployment checkout-v2 runs 1 pod labelled app=checkout, version=v2, answering v2" \
    "kubectl -n k1-canary get deploy checkout-v2 -o jsonpath='{.status.readyReplicas} {.spec.template.metadata.labels.app} {.spec.template.metadata.labels.version}' | grep -qx '1 checkout v2' && kubectl -n k1-canary exec --pod-running-timeout=5s deploy/checkout-v2 -- wget -qO- localhost:8080 | grep -qx v2"
  check_cp "checkout-v1 still runs 3 pods" "kubectl -n k1-canary get deploy checkout-v1 -o jsonpath='{.status.readyReplicas}' | grep -qx 3"
  check_cp "Service checkout has 4 endpoints" "[ \$(kubectl -n k1-canary get endpointslice -l kubernetes.io/service-name=checkout -o jsonpath='{.items[*].endpoints[*].addresses[0]}' | wc -w) = 4 ]"
}
solve_m5() {
  echo_deploy k1-canary checkout-v2 v2 1 app=checkout version=v2
  cp_sh 'kubectl -n k1-canary rollout status deploy checkout-v2 --timeout=120s'
}

# ---- 6. A Helm release (6) ------------------------------------------------------------------------
setup_m6() {
  charts_ready || return 1
  ns_new k1-helm
  put_file /opt/apps/m1/6/values.yaml <<'EOF'
replicaCount: 3
service:
  type: NodePort
EOF
}
score_m6() {
  check_cp "release catalog in k1-helm runs chart webapp 0.2.0" \
    "helm -n k1-helm list -o json | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin) if x[\"name\"]==\"catalog\"]; sys.exit(0 if r and r[0][\"status\"]==\"deployed\" and r[0][\"chart\"]==\"webapp-0.2.0\" else 1)'"
  check_cp "it runs 3 ready pods" "kubectl -n k1-helm get deploy catalog-webapp -o jsonpath='{.status.readyReplicas}' | grep -qx 3"
  check_cp "its Service is a NodePort" "kubectl -n k1-helm get svc catalog-webapp -o jsonpath='{.spec.type}' | grep -qx NodePort"
  check_cp "the user values carry image.pullPolicy=Always" "helm -n k1-helm get values catalog -o json | grep -q '\"pullPolicy\":\"Always\"'"
}
solve_m6() {
  cp_sh 'helm -n k1-helm install catalog oci://registry.practice:5000/charts/webapp --version 0.2.0 --plain-http -f /opt/apps/m1/6/values.yaml --set image.pullPolicy=Always
    kubectl -n k1-helm rollout status deploy catalog-webapp --timeout=120s'
}

# ---- 7. A Kustomize overlay (6) ---------------------------------------------------------------------
setup_m7() {
  ns_new k1-kust
  put_file /opt/apps/m1/7/base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
EOF
  put_file /opt/apps/m1/7/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
spec:
  replicas: 1
  selector:
    matchLabels: {app: frontend}
  template:
    metadata:
      labels: {app: frontend}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
EOF
}
score_m7() {
  check_cp "Deployment qa-frontend runs in k1-kust with 2 replicas" \
    "kubectl -n k1-kust get deploy qa-frontend -o jsonpath='{.spec.replicas} {.status.readyReplicas}' | grep -qx '2 2'"
  check_cp "its pods carry the label stage=qa" "kubectl -n k1-kust get deploy qa-frontend -o jsonpath='{.spec.template.metadata.labels.stage}' | grep -qx qa"
  check_cp "a ConfigMap qa-frontend-settings-<hash> holds STAGE=qa and feeds the pods' environment" \
    "cm=\$(kubectl -n k1-kust get deploy qa-frontend -o jsonpath='{.spec.template.spec.containers[0].envFrom[0].configMapRef.name}'); echo \$cm | grep -q '^qa-frontend-settings-' && kubectl -n k1-kust get cm \$cm -o jsonpath='{.data.STAGE}' | grep -qx qa"
  check_cp "the overlay is in /opt/apps/m1/7/overlays/qa" "test -f /opt/apps/m1/7/overlays/qa/kustomization.yaml"
}
solve_m7() {
  put_file /opt/apps/m1/7/overlays/qa/kustomization.yaml <<'EOF'
resources:
- ../../base
namespace: k1-kust
namePrefix: qa-
labels:
- pairs:
    stage: qa
  includeTemplates: true
replicas:
- name: frontend
  count: 2
configMapGenerator:
- name: frontend-settings
  literals:
  - STAGE=qa
patches:
- patch: |-
    - op: add
      path: /spec/template/spec/containers/0/envFrom
      value:
      - configMapRef:
          name: frontend-settings
  target:
    kind: Deployment
    name: frontend
EOF
  cp_sh 'kubectl apply -k /opt/apps/m1/7/overlays/qa && kubectl -n k1-kust rollout status deploy qa-frontend --timeout=120s'
}

# ---- 8. Probes for an API (6) ----------------------------------------------------------------------
setup_m8() {
  ns_new k1-probe
  cp_sh "kubectl -n k1-probe create deploy api --image=busybox:1.36 --replicas=2 -- sh -c '$WEB_CMD' >/dev/null"
}
score_m8() {
  check_json "readiness: GET /ready on 8080, first after 3s, every 4s" "kubectl -n k1-probe get deploy api -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["readinessProbe"]; r["httpGet"]["path"]=="/ready" and str(r["httpGet"]["port"])=="8080" and r["initialDelaySeconds"]==3 and r["periodSeconds"]==4'
  check_json "liveness: the command test -f /www/live, every 15s" "kubectl -n k1-probe get deploy api -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["livenessProbe"]; r["exec"]["command"]==["test","-f","/www/live"] and r["periodSeconds"]==15'
  check_cp "both pods are ready" "kubectl -n k1-probe rollout status deploy api --timeout=10s"
}
solve_m8() {
  cp_sh "kubectl -n k1-probe patch deploy api --type=json -p='[
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/readinessProbe\",\"value\":{\"httpGet\":{\"path\":\"/ready\",\"port\":8080},\"initialDelaySeconds\":3,\"periodSeconds\":4}},
    {\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/livenessProbe\",\"value\":{\"exec\":{\"command\":[\"test\",\"-f\",\"/www/live\"]},\"periodSeconds\":15}}]'
    kubectl -n k1-probe rollout status deploy api --timeout=120s"
}

# ---- 9. Why the pod crashes (5) ---------------------------------------------------------------------
setup_m9() {
  ns_new k1-logs
  cp_sh "kubectl -n k1-logs create deploy importer --image=busybox:1.36 -- sh -c 'echo reading /data/import.csv; sleep 8; echo ERROR 42: file /data/import.csv not found; exit 3' >/dev/null
    kubectl -n k1-logs create deploy exporter --image=busybox:1.36 -- sleep 1d >/dev/null"
}
score_m9() {
  check_cp "/opt/apps/m1/9/error.txt holds the error line" "grep -qx 'ERROR 42: file /data/import.csv not found' /opt/apps/m1/9/error.txt"
  check_cp "/opt/apps/m1/9/exit-code.txt holds the exit code" "grep -qx 3 /opt/apps/m1/9/exit-code.txt"
}
solve_m9() {
  cp_sh "mkdir -p /opt/apps/m1/9
    for i in \$(seq 1 40); do kubectl -n k1-logs get pod -l app=importer -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}' | grep -q . && break; sleep 2; done
    P=\$(kubectl -n k1-logs get pod -l app=importer -o name)
    { kubectl -n k1-logs logs \$P --previous; kubectl -n k1-logs logs \$P; } 2>/dev/null | grep -m1 ERROR > /opt/apps/m1/9/error.txt
    kubectl -n k1-logs get \$P -o jsonpath='{.status.containerStatuses[0].lastState.terminated.exitCode}' > /opt/apps/m1/9/exit-code.txt
    cat /opt/apps/m1/9/*.txt"
}

# ---- 10. The hungriest pod (4) -----------------------------------------------------------------------
setup_m10() {
  ns_new k1-top
  local n mb
  for n in small:8 large:96 medium:32; do
    mb=${n#*:}; n=${n%%:*}
    # A file in a memory-backed emptyDir counts as the container's memory.
    cp_sh "kubectl apply -f - >/dev/null" <<EOF
apiVersion: v1
kind: Pod
metadata: {name: $n, namespace: k1-top}
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sh", "-c", "dd if=/dev/zero of=/cache/fill bs=1M count=$mb 2>/dev/null; sleep 1d"]
    volumeMounts: [{name: cache, mountPath: /cache}]
  volumes:
  - name: cache
    emptyDir: {medium: Memory, sizeLimit: 200Mi}
EOF
  done
}
score_m10() {
  check_cp "/opt/apps/m1/10/pod.txt names the pod with the most memory in k1-top" "grep -qx large /opt/apps/m1/10/pod.txt"
}
solve_m10() {
  cp_sh "mkdir -p /opt/apps/m1/10
    for i in \$(seq 1 40); do [ \"\$(kubectl -n k1-top top pod --no-headers 2>/dev/null | wc -l)\" = 3 ] && break; sleep 3; done
    kubectl -n k1-top top pod --sort-by=memory --no-headers | head -1 | awk '{print \$1}' > /opt/apps/m1/10/pod.txt; cat /opt/apps/m1/10/pod.txt"
}

# ---- 11. ConfigMap and Secret (8) ------------------------------------------------------------------------
setup_m11() { ns_new k1-config; }
score_m11() {
  check_cp "pod shop prints SHOP_MODE=live from ConfigMap shop-config" \
    "kubectl -n k1-config get pod shop -o jsonpath='{.spec.containers[0].env[?(@.name==\"SHOP_MODE\")].valueFrom.configMapKeyRef.name}' | grep -qx shop-config && kubectl -n k1-config exec shop -- printenv SHOP_MODE | grep -qx live"
  check_cp "Secret shop-api holds key=abc-123" "kubectl -n k1-config get secret shop-api -o jsonpath='{.data.key}' | base64 -d | grep -qx abc-123"
  check_cp "the Secret is the file /run/secrets/shop/key in the pod" "kubectl -n k1-config exec shop -- cat /run/secrets/shop/key | grep -qx abc-123"
  check_cp "the key is not an environment variable" "! kubectl -n k1-config exec shop -- env | grep -q abc-123"
}
solve_m11() {
  cp_sh "kubectl -n k1-config create cm shop-config --from-literal=SHOP_MODE=live
    kubectl -n k1-config create secret generic shop-api --from-literal=key=abc-123
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: shop, namespace: k1-config}
spec:
  containers:
  - name: shop
    image: busybox:1.36
    command: [sleep, 1d]
    env:
    - name: SHOP_MODE
      valueFrom: {configMapKeyRef: {name: shop-config, key: SHOP_MODE}}
    volumeMounts:
    - {name: api, mountPath: /run/secrets/shop, readOnly: true}
  volumes:
  - name: api
    secret: {secretName: shop-api}
EOF
    kubectl -n k1-config wait pod shop --for=condition=Ready --timeout=60s"
}

# ---- 12. Defaults and requests (6) ---------------------------------------------------------------------
setup_m12() {
  ns_new k1-res
  cp_sh 'kubectl -n k1-res create deploy cache --image=busybox:1.36 -- sleep 1d >/dev/null'
}
score_m12() {
  check_json "LimitRange mem-defaults: default memory limit 256Mi, default request 128Mi" "kubectl -n k1-res get limitrange mem-defaults -o json" \
    'l=p["spec"]["limits"][0]; l["type"]=="Container" and l["default"]["memory"]=="256Mi" and l["defaultRequest"]["memory"]=="128Mi"'
  check_json "Deployment cache requests 250m CPU and limits it to 500m" "kubectl -n k1-res get deploy cache -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["resources"]; r["requests"]["cpu"]=="250m" and r["limits"]["cpu"]=="500m"'
  check_cp "the running cache pod got the memory defaults" \
    "kubectl -n k1-res rollout status deploy cache --timeout=10s && kubectl -n k1-res get pod -l app=cache --field-selector=status.phase=Running -o jsonpath='{.items[0].spec.containers[0].resources.limits.memory}' | grep -qx 256Mi"
}
solve_m12() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: v1
kind: LimitRange
metadata: {name: mem-defaults, namespace: k1-res}
spec:
  limits:
  - type: Container
    default: {memory: 256Mi}
    defaultRequest: {memory: 128Mi}
EOF
    kubectl -n k1-res set resources deploy cache --requests=cpu=250m --limits=cpu=500m
    kubectl -n k1-res rollout status deploy cache --timeout=120s"
}

# ---- 13. A ServiceAccount that reads ConfigMaps (8) ---------------------------------------------------------
setup_m13() {
  ns_new k1-rbac
  cp_sh 'kubectl -n k1-rbac create deploy config-sync --image=busybox:1.36 -- sleep 1d >/dev/null'
}
SA13=system:serviceaccount:k1-rbac:config-reader
score_m13() {
  check_cp "Deployment config-sync runs as ServiceAccount config-reader" \
    "kubectl -n k1-rbac get deploy config-sync -o jsonpath='{.spec.template.spec.serviceAccountName}' | grep -qx config-reader"
  check_cp "config-reader may get, list and watch ConfigMaps in k1-rbac" \
    "for v in get list watch; do kubectl auth can-i \$v configmaps -n k1-rbac --as=$SA13 | grep -qx yes || exit 1; done"
  check_cp "it may not change ConfigMaps or read Secrets" \
    "! kubectl auth can-i update configmaps -n k1-rbac --as=$SA13 && ! kubectl auth can-i get secrets -n k1-rbac --as=$SA13"
  check_cp "the Role is called config-reader and the RoleBinding config-reader" "kubectl -n k1-rbac get role config-reader && kubectl -n k1-rbac get rolebinding config-reader"
}
solve_m13() {
  cp_sh 'kubectl -n k1-rbac create sa config-reader
    kubectl -n k1-rbac create role config-reader --verb=get,list,watch --resource=configmaps
    kubectl -n k1-rbac create rolebinding config-reader --role=config-reader --serviceaccount=k1-rbac:config-reader
    kubectl -n k1-rbac set serviceaccount deploy config-sync config-reader
    kubectl -n k1-rbac rollout status deploy config-sync --timeout=120s'
}

# ---- 14. Run as a normal user (6) ------------------------------------------------------------------------
setup_m14() {
  ns_new k1-sec
  cp_sh "kubectl -n k1-sec create deploy worker --image=busybox:1.36 -- sh -c 'while true; do id > /tmp/whoami; sleep 5; done' >/dev/null"
}
score_m14() {
  check_cp "worker's process runs as uid 2000, gid 2000" \
    "kubectl -n k1-sec rollout status deploy worker --timeout=10s && kubectl -n k1-sec exec --pod-running-timeout=5s deploy/worker -- id | grep -q '^uid=2000 gid=2000'"
  check_json "runAsNonRoot is set, privilege escalation is off and every capability is dropped" "kubectl -n k1-sec get deploy worker -o json" \
    't=p["spec"]["template"]["spec"]; c=t["containers"][0].get("securityContext",{}); (t.get("securityContext",{}).get("runAsNonRoot") or c.get("runAsNonRoot")) is True and c.get("allowPrivilegeEscalation") is False and c["capabilities"]["drop"]==["ALL"]'
  check_cp "the app still writes /tmp/whoami" "kubectl -n k1-sec exec --pod-running-timeout=5s deploy/worker -- sh -c 'sleep 6; grep -q uid=2000 /tmp/whoami'"
}
solve_m14() {
  cp_sh "kubectl -n k1-sec patch deploy worker -p '{\"spec\":{\"template\":{\"spec\":{\"securityContext\":{\"runAsUser\":2000,\"runAsGroup\":2000,\"runAsNonRoot\":true},\"containers\":[{\"name\":\"busybox\",\"securityContext\":{\"allowPrivilegeEscalation\":false,\"capabilities\":{\"drop\":[\"ALL\"]}}}]}}}}'
    kubectl -n k1-sec rollout status deploy worker --timeout=120s"
  settled k1-sec worker 1
}

# ---- 15. Service and Ingress (8) ---------------------------------------------------------------------------
setup_m15() {
  ns_new k1-web
  web_app k1-web docs docs 8080 2 app=docs
}
score_m15() {
  check_json "Service docs: ClusterIP, port 80 to 8080" "kubectl -n k1-web get svc docs -o json" \
    's=p["spec"]; s["type"]=="ClusterIP" and s["ports"][0]["port"]==80 and str(s["ports"][0]["targetPort"])=="8080"'
  check_cp "Ingress docs (class nginx) sends docs.k1.local to it" \
    "for i in \$(seq 1 15); do curl -s -m 3 -H 'Host: docs.k1.local' http://$W1IP:30080/ | grep -qx docs && exit 0; sleep 2; done; exit 1"
  check_cp "the Ingress uses pathType Prefix on /" "kubectl -n k1-web get ingress docs -o jsonpath='{.spec.rules[0].http.paths[0].pathType}{.spec.rules[0].http.paths[0].path}' | grep -qx Prefix/"
}
solve_m15() {
  cp_sh "kubectl -n k1-web expose deploy docs --port=80 --target-port=8080
    kubectl -n k1-web create ingress docs --class=nginx --rule='docs.k1.local/*=docs:80'"
}

# ---- 16. Only the frontend reaches the API (6) ----------------------------------------------------------------
setup_m16() {
  ns_new k1-np
  web_app k1-np api api 8080 0 app=api
  client_pod k1-np frontend tier=frontend
  client_pod k1-np batch tier=batch
}
A16="http://\$(kubectl -n k1-np get pod api -o jsonpath='{.status.podIP}'):8080"
score_m16() {
  check_cp "NetworkPolicy api-ingress exists" "kubectl -n k1-np get netpol api-ingress"
  check_cp "frontend reaches api" "$(reach k1-np frontend "$A16") | grep -qx api"
  check_cp "batch does not reach api" "! $(reach k1-np batch "$A16")"
  check_cp "batch still reaches frontend's port (no default deny for other pods)" \
    "kubectl -n k1-np exec batch -- wget -qO- -T 3 http://\$(kubectl -n k1-np get pod frontend -o jsonpath='{.status.podIP}'):80 2>&1 | grep -q 'refused'"
}
solve_m16() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-ingress, namespace: k1-np}
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {tier: frontend}}}]
    ports: [{protocol: TCP, port: 8080}]
EOF"
}
