# Practice exam 2: things that are broken, and tasks that build on each other.
# setup_mN seeds task N, score_mN checks it, solve_mN is the reference solution.

MOCK_TASKS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16"
mock_points() {
  case "$1" in
    1) echo 5;; 2) echo 6;; 3) echo 6;; 4) echo 6;; 5) echo 7;; 6) echo 6;; 7) echo 7;; 8) echo 6;;
    9) echo 5;; 10) echo 7;; 11) echo 6;; 12) echo 6;; 13) echo 6;; 14) echo 7;; 15) echo 6;; 16) echo 8;;
  esac
}
mock_title() {
  case "$1" in
    1) echo "Pending pods";; 2) echo "A container that exits";; 3) echo "A Service with no endpoints";;
    4) echo "Ingress answers 503";; 5) echo "Refused by Pod Security";; 6) echo "Refused by a quota";;
    7) echo "A Helm upgrade gone wrong";; 8) echo "An overlay that won't build";; 9) echo "Old API versions";;
    10) echo "Forbidden in the logs";; 11) echo "A liveness probe that kills";; 12) echo "A Job that never ends";;
    13) echo "Blocked by a default deny";; 14) echo "A Dockerfile that won't build";;
    15) echo "CreateContainerConfigError";; 16) echo "From image to Ingress";;
  esac
}

# ---- 1. Pending pods (5) ----------------------------------------------------------------------
setup_m1() {
  ns_new k2-sched
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: render, namespace: k2-sched}
spec:
  replicas: 2
  selector: {matchLabels: {app: render}}
  template:
    metadata: {labels: {app: render}}
    spec:
      nodeSelector: {kubernetes.io/hostname: cks-w2}
      containers:
      - name: render
        image: busybox:1.36
        command: [sleep, 1d]
        resources:
          requests: {memory: 64Gi}
EOF
}
score_m1() {
  check_cp "Deployment render has 2 ready pods" "kubectl -n k2-sched rollout status deploy render --timeout=10s && kubectl -n k2-sched get deploy render -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
  check_cp "they run on cks-w1" "[ \"\$(kubectl -n k2-sched get pod -l app=render --field-selector=status.phase=Running -o jsonpath='{.items[*].spec.nodeName}')\" = 'cks-w1 cks-w1' ]"
  check_json "each pod requests 64Mi memory" "kubectl -n k2-sched get deploy render -o json" \
    'p["spec"]["template"]["spec"]["containers"][0]["resources"]["requests"]["memory"]=="64Mi"'
}
solve_m1() {
  cp_sh "kubectl -n k2-sched patch deploy render --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/nodeSelector\",\"value\":{\"kubernetes.io/hostname\":\"cks-w1\"}},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/memory\",\"value\":\"64Mi\"}]'
    kubectl -n k2-sched rollout status deploy render --timeout=120s"
}

# ---- 2. A container that exits (6) -------------------------------------------------------------
setup_m2() {
  ns_new k2-crash
  cp_sh "kubectl -n k2-crash create deploy poller --image=busybox:1.36 -- sh -c 'echo polling; sleep 5; echo done' >/dev/null"
}
score_m2() {
  check_cp "Deployment poller runs without restarts for 20 seconds" \
    "kubectl -n k2-crash rollout status deploy poller --timeout=10s && sleep 20 && kubectl -n k2-crash get pod -l app=poller --field-selector=status.phase=Running -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' | grep -qx 0"
  check_cp "its container polls every 10 seconds in a loop that logs 'polling'" \
    "kubectl -n k2-crash logs deploy/poller | grep -q polling && kubectl -n k2-crash get deploy poller -o yaml | grep -q 'while'"
  check_cp "/opt/ckad/m2/2/reason.txt names why the old pods restarted" "grep -qiE 'completed|exit code 0|exited' /opt/ckad/m2/2/reason.txt"
}
solve_m2() {
  cp_sh "mkdir -p /opt/ckad/m2/2
    for i in \$(seq 1 30); do kubectl -n k2-crash get pod -l app=poller -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}' | grep -q . && break; sleep 2; done
    kubectl -n k2-crash get pod -l app=poller -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason} exit code {.items[0].status.containerStatuses[0].lastState.terminated.exitCode}' > /opt/ckad/m2/2/reason.txt
    cat /opt/ckad/m2/2/reason.txt
    kubectl -n k2-crash patch deploy poller --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/command\",\"value\":[\"sh\",\"-c\",\"while true; do echo polling; sleep 10; done\"]}]'
    kubectl -n k2-crash rollout status deploy poller --timeout=120s"
  settled k2-crash poller 1
}

# ---- 3. A Service with no endpoints (6) -----------------------------------------------------------
setup_m3() {
  ns_new k2-svc
  web_app k2-svc orders orders 9000 2 app=orders tier=api
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: orders, namespace: k2-svc}
spec:
  selector: {app: orders, tier: backend}
  ports: [{port: 80, targetPort: 8080}]
EOF
  client_pod k2-svc client
}
score_m3() {
  check_cp "client gets 'orders' from http://orders" "$(reach k2-svc client http://orders) | grep -qx orders"
  check_cp "Service orders has 2 endpoints" "[ \$(kubectl -n k2-svc get endpointslice -l kubernetes.io/service-name=orders -o jsonpath='{.items[*].endpoints[*].addresses[0]}' | wc -w) = 2 ]"
  check_cp "the Deployment is unchanged" "kubectl -n k2-svc get deploy orders -o jsonpath='{.metadata.generation}' | grep -qx 1"
}
solve_m3() {
  cp_sh "kubectl -n k2-svc patch svc orders -p '{\"spec\":{\"selector\":{\"app\":\"orders\",\"tier\":\"api\"},\"ports\":[{\"port\":80,\"targetPort\":9000}]}}'"
}

# ---- 4. Ingress answers 503 (6) ---------------------------------------------------------------------
setup_m4() {
  ns_new k2-ing
  web_app k2-ing wiki wiki 8080 1 app=wiki
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: wiki, namespace: k2-ing}
spec:
  selector: {app: wiki}
  ports: [{name: web, port: 8888, targetPort: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: {name: wiki, namespace: k2-ing}
spec:
  ingressClassName: nginx
  rules:
  - host: wiki.k2.local
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: wiki-svc, port: {number: 80}}}}
EOF
}
score_m4() {
  check_cp "wiki.k2.local answers wiki through port 30080" "for i in \$(seq 1 15); do curl -s -m 3 -H 'Host: wiki.k2.local' http://$W1IP:30080/ | grep -qx wiki && exit 0; sleep 2; done; exit 1"
  check_cp "Service wiki keeps port 8888" "kubectl -n k2-ing get svc wiki -o jsonpath='{.spec.ports[0].port}' | grep -qx 8888"
}
solve_m4() {
  cp_sh "kubectl -n k2-ing patch ingress wiki --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths/0/backend/service\",\"value\":{\"name\":\"wiki\",\"port\":{\"number\":8888}}}]'"
}

# ---- 5. Refused by Pod Security (7) -------------------------------------------------------------------
setup_m5() {
  ns_new k2-psa
  cp_sh "kubectl label ns k2-psa pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
    kubectl -n k2-psa create deploy metrics --image=busybox:1.36 --replicas=2 -- sh -c 'while true; do date >> /data/metrics.log; sleep 5; done' >/dev/null"
}
score_m5() {
  check_cp "Deployment metrics has 2 ready pods" "kubectl -n k2-psa rollout status deploy metrics --timeout=10s && kubectl -n k2-psa get deploy metrics -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
  check_cp "the namespace still enforces restricted" "kubectl get ns k2-psa -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -qx restricted"
  check_cp "the app writes /data/metrics.log" "kubectl -n k2-psa exec --pod-running-timeout=5s deploy/metrics -- sh -c 'sleep 6; test -s /data/metrics.log'"
}
solve_m5() {
  cp_sh "kubectl -n k2-psa patch deploy metrics -p '{\"spec\":{\"template\":{\"spec\":{\"securityContext\":{\"runAsNonRoot\":true,\"runAsUser\":1000,\"seccompProfile\":{\"type\":\"RuntimeDefault\"}},\"volumes\":[{\"name\":\"data\",\"emptyDir\":{}}],\"containers\":[{\"name\":\"busybox\",\"volumeMounts\":[{\"name\":\"data\",\"mountPath\":\"/data\"}],\"securityContext\":{\"allowPrivilegeEscalation\":false,\"capabilities\":{\"drop\":[\"ALL\"]}}}]}}}}'
    kubectl -n k2-psa rollout status deploy metrics --timeout=120s"
}

# ---- 6. Refused by a quota (6) ------------------------------------------------------------------------
setup_m6() {
  ns_new k2-quota
  cp_sh "kubectl -n k2-quota create quota team --hard=requests.cpu=400m,requests.memory=400Mi,limits.cpu=800m,limits.memory=800Mi,pods=6 >/dev/null
    kubectl -n k2-quota create deploy search --image=busybox:1.36 --replicas=4 -- sleep 1d >/dev/null"
}
score_m6() {
  check_cp "Deployment search has 4 ready pods" "kubectl -n k2-quota rollout status deploy search --timeout=10s && kubectl -n k2-quota get deploy search -o jsonpath='{.status.readyReplicas}' | grep -qx 4"
  check_json "LimitRange defaults in k2-quota gives containers defaults, so the quota counts them" "kubectl -n k2-quota get limitrange defaults -o json" \
    'l=p["spec"]["limits"][0]; all(k in l["default"] for k in ("cpu","memory")) and all(k in l["defaultRequest"] for k in ("cpu","memory"))'
  check_cp "the quota is unchanged" "kubectl -n k2-quota get quota team -o jsonpath='{.spec.hard.requests\.cpu}' | grep -qx 400m"
}
solve_m6() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: v1
kind: LimitRange
metadata: {name: defaults, namespace: k2-quota}
spec:
  limits:
  - type: Container
    default: {cpu: 200m, memory: 128Mi}
    defaultRequest: {cpu: 100m, memory: 64Mi}
EOF
    kubectl -n k2-quota rollout restart deploy search
    kubectl -n k2-quota rollout status deploy search --timeout=120s"
}

# ---- 7. A Helm upgrade gone wrong (7) ------------------------------------------------------------------
setup_m7() {
  charts_ready || return 1
  ns_new k2-helm
  cp_sh "helm -n k2-helm install portal oci://registry.ckad:5000/charts/webapp --version 0.1.0 --plain-http --set replicaCount=2 --wait --timeout 120s >/dev/null 2>&1
    helm -n k2-helm upgrade portal oci://registry.ckad:5000/charts/webapp --version 0.2.0 --plain-http --set image.repository=docker.io/library/ngnix --wait --timeout 10s >/dev/null 2>&1; true"
}
score_m7() {
  check_cp "the newest revision of portal is deployed from chart 0.2.0 with nginx" \
    "helm -n k2-helm history portal -o json | python3 -c 'import json,sys; h=json.load(sys.stdin)[-1]; sys.exit(0 if h[\"status\"]==\"deployed\" and h[\"chart\"]==\"webapp-0.2.0\" else 1)' && kubectl -n k2-helm get deploy portal-webapp -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -q '/nginx:'"
  check_cp "it runs 2 ready pods" "kubectl -n k2-helm rollout status deploy portal-webapp --timeout=10s && kubectl -n k2-helm get deploy portal-webapp -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
  check_cp "/opt/ckad/m2/7/failed.txt names the revision that failed" "grep -qx 2 /opt/ckad/m2/7/failed.txt"
}
solve_m7() {
  cp_sh "mkdir -p /opt/ckad/m2/7
    helm -n k2-helm history portal -o json | python3 -c 'import json,sys; print([h[\"revision\"] for h in json.load(sys.stdin) if h[\"status\"]==\"failed\"][-1])' > /opt/ckad/m2/7/failed.txt
    helm -n k2-helm upgrade portal oci://registry.ckad:5000/charts/webapp --version 0.2.0 --plain-http --set replicaCount=2
    kubectl -n k2-helm rollout status deploy portal-webapp --timeout=120s
    helm -n k2-helm history portal"
}

# ---- 8. An overlay that won't build (6) -------------------------------------------------------------------
setup_m8() {
  ns_new k2-kust
  put_file /opt/ckad/m2/8/base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
- service.yaml
EOF
  put_file /opt/ckad/m2/8/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: gateway
spec:
  replicas: 1
  selector:
    matchLabels: {app: gateway}
  template:
    metadata:
      labels: {app: gateway}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
EOF
  put_file /opt/ckad/m2/8/base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: gateway
spec:
  selector: {app: gateway}
  ports: [{port: 80}]
EOF
  put_file /opt/ckad/m2/8/overlays/live/kustomization.yaml <<'EOF'
resources:
- ../base
namespace: k2-kust
nameSuffix: -live
replicas:
- name: gateway-live
  count: 2
EOF
}
score_m8() {
  check_cp "Deployment gateway-live in k2-kust has 2 ready pods" "kubectl -n k2-kust get deploy gateway-live -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
  check_cp "Service gateway-live exists in k2-kust" "kubectl -n k2-kust get svc gateway-live"
  check_cp "the overlay builds" "kubectl kustomize /opt/ckad/m2/8/overlays/live >/dev/null"
}
solve_m8() {
  cp_sh "cd /opt/ckad/m2/8/overlays/live && sed -i 's|- ../base|- ../../base|; s|name: gateway-live|name: gateway|' kustomization.yaml && kubectl apply -k . && kubectl -n k2-kust rollout status deploy gateway-live --timeout=120s"
}

# ---- 9. Old API versions (5) ------------------------------------------------------------------------------
setup_m9() {
  ns_new k2-api
  put_file /opt/ckad/m2/9/old.yaml <<'EOF'
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: rotate
  namespace: k2-api
spec:
  schedule: "0 */6 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: rotate
            image: busybox:1.36
            command: ["echo", "rotated"]
---
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
metadata:
  name: rotate
  namespace: k2-api
spec:
  rules:
  - host: rotate.k2.local
    http:
      paths:
      - path: /
        backend:
          serviceName: rotate
          servicePort: 80
EOF
}
score_m9() {
  check_cp "CronJob rotate exists in k2-api as batch/v1" "kubectl -n k2-api get cronjob.v1.batch rotate -o jsonpath='{.spec.schedule}' | grep -qx '0 \*/6 \* \* \*'"
  check_json "Ingress rotate uses the networking.k8s.io/v1 backend form, Prefix, Service rotate port 80, class nginx" "kubectl -n k2-api get ingress rotate -o json" \
    'x=p["spec"]["rules"][0]["http"]["paths"][0]; p["spec"].get("ingressClassName")=="nginx" and x["pathType"]=="Prefix" and x["backend"]["service"]=={"name":"rotate","port":{"number":80}}'
  check_cp "/opt/ckad/m2/9/new.yaml has no beta versions" "test -s /opt/ckad/m2/9/new.yaml && ! grep -q beta /opt/ckad/m2/9/new.yaml"
}
solve_m9() {
  put_file /opt/ckad/m2/9/new.yaml <<'EOF'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: rotate
  namespace: k2-api
spec:
  schedule: "0 */6 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: rotate
            image: busybox:1.36
            command: ["echo", "rotated"]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rotate
  namespace: k2-api
spec:
  ingressClassName: nginx
  rules:
  - host: rotate.k2.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rotate
            port:
              number: 80
EOF
  cp_sh 'kubectl apply -f /opt/ckad/m2/9/new.yaml'
}

# ---- 10. Forbidden in the logs (7) ----------------------------------------------------------------------
setup_m10() {
  ns_new k2-ops k2-apps
  cp_sh "kubectl -n k2-apps create deploy billing --image=busybox:1.36 -- sleep 1d >/dev/null
    kubectl -n k2-ops create sa scaler >/dev/null
    kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: scaler, namespace: k2-ops}
spec:
  serviceAccountName: scaler
  containers:
  - name: scaler
    image: busybox:1.36
    command:
    - sh
    - -c
    - |
      T=/var/run/secrets/kubernetes.io/serviceaccount/token
      while true; do
        if wget -qO- --no-check-certificate --header \"Authorization: Bearer \$(cat \$T)\" https://kubernetes.default.svc/apis/apps/v1/namespaces/k2-apps/deployments/billing/scale >/tmp/s 2>/tmp/e; then
          echo \"\$(date +%T) read the scale of billing: \$(grep -o '\\\"replicas\\\": *[0-9]*' /tmp/s | head -1)\"
        else
          echo \"\$(date +%T) \$(cat /tmp/e)\"
        fi
        sleep 5
      done
EOF"
}
SA10=system:serviceaccount:k2-ops:scaler
score_m10() {
  check_cp "scaler may get and update deployments/scale in k2-apps" \
    "kubectl auth can-i get deployments --subresource=scale -n k2-apps --as=$SA10 && kubectl auth can-i update deployments --subresource=scale -n k2-apps --as=$SA10"
  check_cp "scaler may not delete deployments, nor touch other namespaces" \
    "! kubectl auth can-i delete deployments -n k2-apps --as=$SA10 && ! kubectl auth can-i get deployments --subresource=scale -n default --as=$SA10"
  check_cp "the scaler's log shows it read the scale" "for i in \$(seq 1 10); do kubectl -n k2-ops logs scaler --tail=1 | grep -q 'read the scale' && exit 0; sleep 2; done; exit 1"
}
solve_m10() {
  cp_sh "kubectl -n k2-apps create role scaler --verb=get,update,patch --resource=deployments/scale
    kubectl -n k2-apps create rolebinding scaler --role=scaler --serviceaccount=k2-ops:scaler"
}

# ---- 11. A liveness probe that kills (6) ------------------------------------------------------------------
setup_m11() {
  ns_new k2-probe
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: slowstart, namespace: k2-probe}
spec:
  replicas: 1
  selector: {matchLabels: {app: slowstart}}
  template:
    metadata: {labels: {app: slowstart}}
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "sleep 25; mkdir -p /www && echo up > /www/index.html && exec httpd -f -p 8080 -h /www"]
        livenessProbe:
          httpGet: {path: /, port: 8080}
          periodSeconds: 5
          failureThreshold: 2
EOF
}
score_m11() {
  check_json "the container has a startup probe on / port 8080 that allows at least 40 seconds" "kubectl -n k2-probe get deploy slowstart -o json" \
    's=p["spec"]["template"]["spec"]["containers"][0]["startupProbe"]; s["httpGet"]["path"]=="/" and str(s["httpGet"]["port"])=="8080" and s.get("periodSeconds",10)*s.get("failureThreshold",3)>=40'
  check_cp "the liveness probe stays as it was" "kubectl -n k2-probe get deploy slowstart -o jsonpath='{.spec.template.spec.containers[0].livenessProbe.periodSeconds}' | grep -qx 5"
  check_cp "the new pod is ready without a restart" \
    "kubectl -n k2-probe rollout status deploy slowstart --timeout=10s && kubectl -n k2-probe get pod -l app=slowstart --field-selector=status.phase=Running -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}' | grep -qx 0"
}
solve_m11() {
  cp_sh "kubectl -n k2-probe patch deploy slowstart --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/startupProbe\",\"value\":{\"httpGet\":{\"path\":\"/\",\"port\":8080},\"periodSeconds\":5,\"failureThreshold\":12}}]'
    kubectl -n k2-probe rollout status deploy slowstart --timeout=120s"
  settled k2-probe slowstart 1
}

# ---- 12. A Job that never ends (6) -------------------------------------------------------------------------
setup_m12() {
  ns_new k2-job
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: migrate, namespace: k2-job}
spec:
  backoffLimit: 100
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: migrate
        image: busybox:1.36
        command: ["sh", "-c", "test -f /config/schema.sql && echo migrated $(wc -l < /config/schema.sql) statements"]
EOF
}
score_m12() {
  check_cp "Job migrate in k2-job completed" "kubectl -n k2-job wait job migrate --for=condition=Complete --timeout=10s"
  check_cp "its log says it migrated 2 statements" "kubectl -n k2-job logs job/migrate | grep -q 'migrated 2 statements'"
  check_json "the Job retries at most 4 times" "kubectl -n k2-job get job migrate -o json" \
    'p["spec"]["backoffLimit"]<=4'
}
solve_m12() {
  cp_sh "printf 'CREATE TABLE a (id int);\nCREATE TABLE b (id int);\n' > /tmp/schema.sql
    kubectl -n k2-job create cm schema --from-file=schema.sql=/tmp/schema.sql
    kubectl -n k2-job get job migrate -o json | python3 -c '
import json,sys
d=json.load(sys.stdin)
for k in (\"uid\",\"resourceVersion\",\"creationTimestamp\",\"generation\",\"managedFields\"): d[\"metadata\"].pop(k,None)
d.pop(\"status\",None); s=d[\"spec\"]; s.pop(\"selector\",None); s[\"backoffLimit\"]=4
t=s[\"template\"]; t[\"metadata\"].pop(\"labels\",None)
t[\"spec\"][\"volumes\"]=[{\"name\":\"config\",\"configMap\":{\"name\":\"schema\"}}]
t[\"spec\"][\"containers\"][0][\"volumeMounts\"]=[{\"name\":\"config\",\"mountPath\":\"/config\"}]
print(json.dumps(d))' > /tmp/migrate.json
    kubectl -n k2-job delete job migrate
    kubectl apply -f /tmp/migrate.json
    kubectl -n k2-job wait job migrate --for=condition=Complete --timeout=60s"
}

# ---- 13. Blocked by a default deny (6) -----------------------------------------------------------------------
setup_m13() {
  ns_new k2-net
  web_app k2-net inventory inventory 8080 0 app=inventory
  client_pod k2-net storefront app=storefront
  cp_sh "kubectl -n k2-net expose pod inventory --port=80 --target-port=8080 >/dev/null
    kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: k2-net}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
EOF
}
score_m13() {
  check_cp "storefront reaches http://inventory" "$(reach k2-net storefront http://inventory) | grep -qx inventory"
  check_cp "default-deny is unchanged" "kubectl -n k2-net get netpol default-deny -o jsonpath='{.spec.podSelector}{.spec.policyTypes}' | grep -qx '{}\[\"Ingress\",\"Egress\"\]'"
  check_cp "inventory still reaches nothing outside (its egress stays closed)" "! kubectl -n k2-net exec inventory -- wget -qO- -T 3 http://kubernetes.default 2>/dev/null"
}
solve_m13() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: storefront-egress, namespace: k2-net}
spec:
  podSelector: {matchLabels: {app: storefront}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {app: inventory}}}]
    ports: [{protocol: TCP, port: 8080}]
  - ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: inventory-ingress, namespace: k2-net}
spec:
  podSelector: {matchLabels: {app: inventory}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: storefront}}}]
    ports: [{protocol: TCP, port: 8080}]
EOF"
}

# ---- 14. A Dockerfile that won't build (7) -----------------------------------------------------------------------
setup_m14() {
  ns_new k2-image
  put_file /opt/ckad/m2/14/Dockerfile <<'EOF'
FROM docker.io/library/busybox:1.36
COPY src/serve.sh /usr/local/bin/serve.sh
RUN chmod 755 /usr/local/bin/serve.sh
EXPOSE 8080
CMD ["serve.sh"]
EOF
  put_file /opt/ckad/m2/14/app/serve.sh <<'EOF'
#!/bin/sh
mkdir -p /tmp/www && echo "label v2" > /tmp/www/index.html
exec httpd -f -p 8080 -h /tmp/www
EOF
  cp_sh "kubectl -n k2-image create deploy label --image=registry.ckad:5000/label:v1 --port=8080 >/dev/null"
}
score_m14() {
  check_cp "the registry holds label:v2" "curl -fsS http://registry.ckad:5000/v2/label/tags/list | grep -q '\"v2\"'"
  check_cp "Deployment label runs registry.ckad:5000/label:v2 and is ready" \
    "kubectl -n k2-image get deploy label -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qx registry.ckad:5000/label:v2 && kubectl -n k2-image rollout status deploy label --timeout=10s"
  check_cp "the pod answers 'label v2' on 8080" "kubectl -n k2-image exec --pod-running-timeout=5s deploy/label -- wget -qO- localhost:8080 | grep -qx 'label v2'"
}
solve_m14() {
  cp_sh "cd /opt/ckad/m2/14 && sed -i 's|COPY src/serve.sh|COPY app/serve.sh|' Dockerfile
    podman build -q -t registry.ckad:5000/label:v2 . && podman push -q registry.ckad:5000/label:v2
    kubectl -n k2-image set image deploy/label label=registry.ckad:5000/label:v2
    kubectl -n k2-image rollout status deploy label --timeout=120s"
}

# ---- 15. CreateContainerConfigError (6) ---------------------------------------------------------------------------
setup_m15() {
  ns_new k2-cfg
  cp_sh "kubectl -n k2-cfg create secret generic smtp --from-literal=username=mailer --from-literal=password=m4il-pw >/dev/null
    kubectl -n k2-cfg create cm mail-settings --from-literal=SMTP_HOST=smtp.k2.local >/dev/null
    kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: mailer, namespace: k2-cfg}
spec:
  replicas: 1
  selector: {matchLabels: {app: mailer}}
  template:
    metadata: {labels: {app: mailer}}
    spec:
      containers:
      - name: mailer
        image: busybox:1.36
        command: ["sh", "-c", "echo sending as $SMTP_USER via $SMTP_HOST; sleep 1d"]
        env:
        - name: SMTP_USER
          valueFrom: {secretKeyRef: {name: smtp-credentials, key: user}}
        - name: SMTP_HOST
          valueFrom: {configMapKeyRef: {name: mail-settings, key: smtp_host}}
EOF
}
score_m15() {
  check_cp "Deployment mailer has a ready pod" "kubectl -n k2-cfg rollout status deploy mailer --timeout=10s"
  check_cp "it logs 'sending as mailer via smtp.k2.local'" "for i in \$(seq 1 10); do kubectl -n k2-cfg logs deploy/mailer 2>/dev/null | grep -q 'sending as mailer via smtp.k2.local' && exit 0; sleep 2; done; exit 1"
  check_cp "the Secret and the ConfigMap are unchanged" "kubectl -n k2-cfg get secret smtp -o jsonpath='{.data.username}' | base64 -d | grep -qx mailer && kubectl -n k2-cfg get cm mail-settings -o jsonpath='{.data.SMTP_HOST}' | grep -qx smtp.k2.local"
}
solve_m15() {
  cp_sh "kubectl -n k2-cfg patch deploy mailer --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/0/valueFrom/secretKeyRef\",\"value\":{\"name\":\"smtp\",\"key\":\"username\"}},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/env/1/valueFrom/configMapKeyRef/key\",\"value\":\"SMTP_HOST\"}]'
    kubectl -n k2-cfg rollout status deploy mailer --timeout=120s"
  settled k2-cfg mailer 1
}

# ---- 16. From image to Ingress (8) -----------------------------------------------------------------------------------
setup_m16() {
  ns_new k2-chain
  put_file /opt/ckad/m2/16/Dockerfile <<'EOF'
FROM docker.io/library/busybox:1.36
RUN mkdir -p /www && echo "status page" > /www/index.html
USER 1000
CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
EOF
}
score_m16() {
  check_cp "Deployment status runs registry.ckad:5000/status:1 with 2 ready pods" \
    "kubectl -n k2-chain get deploy status -o jsonpath='{.spec.template.spec.containers[0].image} {.status.readyReplicas}' | grep -qx 'registry.ckad:5000/status:1 2'"
  check_cp "Service status sends port 80 to 8080" "kubectl -n k2-chain get svc status -o jsonpath='{.spec.ports[0].port}/{.spec.ports[0].targetPort}' | grep -qx 80/8080"
  check_cp "status.k2.local/ answers 'status page' through the ingress" \
    "for i in \$(seq 1 15); do curl -s -m 3 -H 'Host: status.k2.local' http://$W1IP:30080/ | grep -qx 'status page' && exit 0; sleep 2; done; exit 1"
  check_cp "the pods have a readiness probe on 8080" "kubectl -n k2-chain get deploy status -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}' | grep -qx 8080"
}
solve_m16() {
  cp_sh "cd /opt/ckad/m2/16 && podman build -q -t registry.ckad:5000/status:1 . && podman push -q registry.ckad:5000/status:1
    kubectl -n k2-chain create deploy status --image=registry.ckad:5000/status:1 --replicas=2 --port=8080
    kubectl -n k2-chain patch deploy status --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/readinessProbe\",\"value\":{\"httpGet\":{\"path\":\"/\",\"port\":8080}}}]'
    kubectl -n k2-chain expose deploy status --port=80 --target-port=8080
    kubectl -n k2-chain create ingress status --class=nginx --rule='status.k2.local/*=status:80'
    kubectl -n k2-chain rollout status deploy status --timeout=120s"
}
