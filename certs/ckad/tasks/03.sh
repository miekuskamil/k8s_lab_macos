# Domain 03, application observability and maintenance. Functions for task.sh: setup_3_N, check_3_N, solve_3_N.

# A busybox web server: the container writes the files it serves, then runs httpd on 8080.
WEB_CMD='mkdir -p /www && echo ok > /www/index.html && echo ready > /www/ready && echo live > /www/live && exec httpd -f -p 8080 -h /www'

# ---- Task 1: readiness, liveness and startup probes ------------------------------------------
setup_3_1() {
  ns_fresh probes
  cp_sh "kubectl -n probes create deploy api --image=busybox:1.36 --replicas=2 --port=8080 -- sh -c '$WEB_CMD' >/dev/null
    kubectl -n probes rollout status deploy api --timeout=120s"
}
check_3_1() {
  check_json "container 1 has a readiness probe: GET /ready on 8080 every 5s" "kubectl -n probes get deploy api -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["readinessProbe"]; r["httpGet"]["path"]=="/ready" and str(r["httpGet"]["port"])=="8080" and r["periodSeconds"]==5'
  check_json "a liveness probe: TCP 8080 every 10s, 3 failures allowed" "kubectl -n probes get deploy api -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["livenessProbe"]; str(r["tcpSocket"]["port"])=="8080" and r["periodSeconds"]==10 and r["failureThreshold"]==3'
  check_json "a startup probe: GET /live, up to 30 tries 2s apart" "kubectl -n probes get deploy api -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["startupProbe"]; r["httpGet"]["path"]=="/live" and r["failureThreshold"]==30 and r["periodSeconds"]==2'
  check_cp "both pods are ready" "kubectl -n probes rollout status deploy api --timeout=90s && kubectl -n probes get deploy api -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
}
solve_3_1() {
  put_file /opt/ckad/3.1/probes.yaml <<'EOF'
spec:
  template:
    spec:
      containers:
      - name: busybox
        startupProbe:
          httpGet:
            path: /live
            port: 8080
          periodSeconds: 2
          failureThreshold: 30
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          periodSeconds: 5
        livenessProbe:
          tcpSocket:
            port: 8080
          periodSeconds: 10
          failureThreshold: 3
EOF
  shown <<'EOF'
k -n probes patch deploy api --patch-file /opt/ckad/3.1/probes.yaml
k -n probes rollout status deploy api
k -n probes describe pod -l app=api | grep -E 'Liveness|Readiness|Startup' | sort -u
EOF
}

# ---- Task 2: probes that kill a healthy app -------------------------------------------------
setup_3_2() {
  ns_fresh probes-fix
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  namespace: probes-fix
spec:
  replicas: 2
  selector:
    matchLabels: {app: shop}
  template:
    metadata:
      labels: {app: shop}
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet: {path: /, port: 8080}
          initialDelaySeconds: 3
          periodSeconds: 3
          failureThreshold: 2
        readinessProbe:
          httpGet: {path: /healthz, port: 80}
          periodSeconds: 3
EOF
  cp_sh 'sleep 25; kubectl -n probes-fix get pods'
}
check_3_2() {
  check_cp "both pods of shop are ready" "kubectl -n probes-fix rollout status deploy shop --timeout=90s && kubectl -n probes-fix get deploy shop -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
  check_cp "no restart in the 20 seconds after the rollout" \
    "sleep 20; [ \"\$(kubectl -n probes-fix get pods -l app=shop -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}')\" = '0 0' ]"
  check_json "both probes still exist and check port 80" "kubectl -n probes-fix get deploy shop -o json" \
    'c=p["spec"]["template"]["spec"]["containers"][0]; str(c["livenessProbe"]["httpGet"]["port"])=="80" and str(c["readinessProbe"]["httpGet"]["port"])=="80"'
}
solve_3_2() {
  shown <<'EOF'
k -n probes-fix get pods
k -n probes-fix events --types=Warning | tail -3
k -n probes-fix patch deploy shop --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/httpGet/port","value":80},{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'
k -n probes-fix rollout status deploy shop
EOF
  settled probes-fix shop 2
  shown <<'EOF'
k -n probes-fix get pods
EOF
}

# ---- Task 3: logs of a container that crashed -------------------------------------------------
setup_3_3() {
  ns_fresh logs
  cp_sh 'rm -rf /opt/ckad/3.3; mkdir -p /opt/ckad/3.3
    kubectl -n logs create deploy billing --image=busybox:1.36 -- sh -c "echo starting billing; sleep 12; if [ -z \"\$DB_URL\" ]; then echo FATAL: environment variable DB_URL is not set; exit 1; fi; echo connected to \$DB_URL; exec sleep 1d" >/dev/null
    sleep 30; kubectl -n logs get pods'
}
check_3_3() {
  check_cp "/opt/ckad/3.3/crash.log holds the crash message" "grep -q 'FATAL: environment variable DB_URL is not set' /opt/ckad/3.3/crash.log"
  check_cp "billing's pod is ready and logs 'connected to postgres://db.logs:5432/billing'" \
    "kubectl -n logs rollout status deploy billing --timeout=90s && for i in \$(seq 1 15); do kubectl -n logs logs deploy/billing 2>/dev/null | grep -q 'connected to postgres://db.logs:5432/billing' && exit 0; sleep 2; done; exit 1"
}
solve_3_3() {
  # Wait until the container runs again after a crash, so that --previous names the crashed run.
  cp_sh "for i in \$(seq 1 60); do kubectl -n logs get pod -l app=billing -o jsonpath='{.items[0].status.containerStatuses[0].restartCount} {.items[0].status.containerStatuses[0].state.running.startedAt}' | grep -qE '^[1-9][0-9]* .+' && exit 0; sleep 2; done"
  shown <<'EOF'
k -n logs get pods
k -n logs logs deploy/billing --previous
k -n logs logs deploy/billing --previous > /opt/ckad/3.3/crash.log
k -n logs set env deploy/billing DB_URL=postgres://db.logs:5432/billing
k -n logs rollout status deploy billing
EOF
  settled logs billing 1
  cp_sh "for i in \$(seq 1 20); do kubectl -n logs logs deploy/billing | grep -q connected && exit 0; sleep 2; done"
  shown <<'EOF'
k -n logs logs deploy/billing
EOF
}

# ---- Task 4: which pod uses the most CPU ----------------------------------------------------------
setup_3_4() {
  ns_fresh metrics-load
  need_metrics
  cp_sh 'rm -rf /opt/ckad/3.4; mkdir -p /opt/ckad/3.4
    kubectl -n metrics-load run calc-a --image=busybox:1.36 -- sleep 1d >/dev/null
    kubectl -n metrics-load run calc-b --image=busybox:1.36 --overrides='"'"'{"spec":{"containers":[{"name":"calc-b","image":"busybox:1.36","command":["sh","-c","while true; do :; done"],"resources":{"limits":{"cpu":"150m"}}}]}}'"'"' >/dev/null
    kubectl -n metrics-load run calc-c --image=busybox:1.36 --overrides='"'"'{"spec":{"containers":[{"name":"calc-c","image":"busybox:1.36","command":["sh","-c","while true; do :; done"],"resources":{"limits":{"cpu":"40m"}}}]}}'"'"' >/dev/null
    kubectl -n metrics-load wait pod --all --for=condition=Ready --timeout=90s >/dev/null
    for i in $(seq 1 40); do [ "$(kubectl -n metrics-load top pod --no-headers 2>/dev/null | wc -l)" = 3 ] && break; sleep 3; done
    kubectl -n metrics-load get pods'
}
check_3_4() {
  check_cp "/opt/ckad/3.4/top-pod.txt names calc-b" "grep -qx calc-b /opt/ckad/3.4/top-pod.txt"
  check_cp "/opt/ckad/3.4/top.sh lists the pods of metrics-load, busiest first" \
    "grep -q 'top pod' /opt/ckad/3.4/top.sh && bash /opt/ckad/3.4/top.sh | grep -v NAME | head -1 | grep -q '^calc-b '"
}
solve_3_4() {
  shown <<'EOF'
echo 'kubectl -n metrics-load top pod --sort-by=cpu' > /opt/ckad/3.4/top.sh
bash /opt/ckad/3.4/top.sh
echo calc-b > /opt/ckad/3.4/top-pod.txt
EOF
}

# ---- Task 5: debug a container that has no shell -------------------------------------------------
setup_3_5() {
  ns_fresh debugging
  cp_sh 'rm -rf /opt/ckad/3.5; mkdir -p /opt/ckad/3.5
    kubectl -n debugging run vault --image=registry.k8s.io/pause:3.10.1 --overrides='"'"'{"spec":{"containers":[{"name":"app","image":"registry.k8s.io/pause:3.10.1"}]}}'"'"' >/dev/null
    kubectl -n debugging wait pod vault --for=condition=Ready --timeout=60s >/dev/null
    kubectl -n debugging exec vault -c app -- sh -c true 2>&1 | tail -1'
}
check_3_5() {
  check_json "pod vault has an ephemeral container debugger (busybox:1.36) that targets app" "kubectl -n debugging get pod vault -o json" \
    'any(e["name"]=="debugger" and e["image"]=="busybox:1.36" and e.get("targetContainerName")=="app" for e in p["spec"].get("ephemeralContainers",[]))'
  check_cp "/opt/ckad/3.5/process.txt holds the command of app's process" "grep -q '/pause' /opt/ckad/3.5/process.txt"
  check_cp "pod vault was not restarted or replaced" "kubectl -n debugging get pod vault -o jsonpath='{.status.containerStatuses[0].restartCount}' | grep -qx 0"
}
solve_3_5() {
  shown <<'EOF'
k -n debugging debug vault --image=busybox:1.36 --target=app -c debugger -- sleep 1d
k -n debugging wait pod vault --for=jsonpath='{.status.ephemeralContainerStatuses[0].state.running}' --timeout=60s
k -n debugging exec vault -c debugger -- ps
k -n debugging exec vault -c debugger -- ps -o args | grep -v -E 'ps|sleep|COMMAND' > /opt/ckad/3.5/process.txt
cat /opt/ckad/3.5/process.txt
EOF
}

# ---- Task 6: pods that stay Pending -----------------------------------------------------------
setup_3_6() {
  ns_fresh pending
  cp_sh 'kubectl label node cks-w1 ckad-disk- >/dev/null 2>&1; true'
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report
  namespace: pending
spec:
  replicas: 2
  selector:
    matchLabels: {app: report}
  template:
    metadata:
      labels: {app: report}
    spec:
      nodeSelector:
        ckad-disk: ssd
      containers:
      - name: report
        image: busybox:1.36
        command: ["sleep", "1d"]
        resources:
          requests:
            cpu: "40"
            memory: 64Mi
EOF
  cp_sh 'sleep 3; kubectl -n pending get pods'
}
check_3_6() {
  check_cp "node cks-w1 carries the label ckad-disk=ssd" "kubectl get node cks-w1 -o jsonpath='{.metadata.labels.ckad-disk}' | grep -qx ssd"
  check_json "the nodeSelector stays, and each pod requests 100m CPU" "kubectl -n pending get deploy report -o json" \
    't=p["spec"]["template"]["spec"]; t.get("nodeSelector")=={"ckad-disk":"ssd"} and t["containers"][0]["resources"]["requests"]["cpu"]=="100m"'
  check_cp "both pods run on cks-w1" \
    "kubectl -n pending rollout status deploy report --timeout=90s && [ \"\$(kubectl -n pending get pods -l app=report --field-selector=status.phase=Running -o jsonpath='{.items[*].spec.nodeName}')\" = 'cks-w1 cks-w1' ]"
}
solve_3_6() {
  shown <<'EOF'
k -n pending get pods
k -n pending events --types=Warning | tail -1
k get nodes -L ckad-disk
k label node cks-w1 ckad-disk=ssd
k -n pending set resources deploy report --requests=cpu=100m,memory=64Mi
k -n pending rollout status deploy report
k -n pending get pods -o wide
EOF
}

# ---- Task 7: manifests written for APIs that no longer exist ------------------------------------------
setup_3_7() {
  ns_fresh upgrade
  put_file /opt/ckad/3.7/legacy.yaml <<'EOF'
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: catalog
  namespace: upgrade
spec:
  replicas: 2
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        resources:
          requests:
            cpu: 50m
---
apiVersion: policy/v1beta1
kind: PodDisruptionBudget
metadata:
  name: catalog
  namespace: upgrade
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: catalog
---
apiVersion: autoscaling/v2beta1
kind: HorizontalPodAutoscaler
metadata:
  name: catalog
  namespace: upgrade
spec:
  scaleTargetRef:
    apiVersion: extensions/v1beta1
    kind: Deployment
    name: catalog
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      targetAverageUtilization: 70
EOF
  cp_sh 'kubectl apply -f /opt/ckad/3.7/legacy.yaml 2>&1 | grep -o "no matches for kind .*" | sort -u'
}
check_3_7() {
  check_cp "/opt/ckad/3.7/current.yaml uses apps/v1, policy/v1 and autoscaling/v2 only" \
    "grep -q 'apiVersion: apps/v1' /opt/ckad/3.7/current.yaml && grep -q 'apiVersion: policy/v1\$' /opt/ckad/3.7/current.yaml && grep -q 'apiVersion: autoscaling/v2\$' /opt/ckad/3.7/current.yaml && ! grep -q 'v1beta\\|v2beta' /opt/ckad/3.7/current.yaml"
  check_cp "the file applies cleanly (server dry run)" "kubectl apply -f /opt/ckad/3.7/current.yaml --dry-run=server"
  check_cp "Deployment catalog runs 2 ready pods in upgrade" "kubectl -n upgrade rollout status deploy catalog --timeout=90s && kubectl -n upgrade get deploy catalog -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
  check_json "the HPA targets Deployment catalog at 70% CPU, 2 to 5 replicas" "kubectl -n upgrade get hpa catalog -o json" \
    's=p["spec"]; s["scaleTargetRef"]["name"]=="catalog" and s["scaleTargetRef"]["apiVersion"]=="apps/v1" and s["minReplicas"]==2 and s["maxReplicas"]==5 and s["metrics"][0]["resource"]["target"]=={"type":"Utilization","averageUtilization":70}'
  check_cp "the PodDisruptionBudget keeps 1 pod of catalog" "kubectl -n upgrade get pdb catalog -o jsonpath='{.spec.minAvailable}' | grep -qx 1"
}
solve_3_7() {
  put_file /opt/ckad/3.7/current.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: upgrade
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        resources:
          requests:
            cpu: 50m
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: catalog
  namespace: upgrade
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: catalog
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: catalog
  namespace: upgrade
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: catalog
  minReplicas: 2
  maxReplicas: 5
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
EOF
  shown <<'EOF'
k api-resources | grep -E '^(deployments|poddisruptionbudgets|horizontalpodautoscalers) '
k convert -f /opt/ckad/3.7/legacy.yaml
k explain hpa.spec.metrics.resource.target --api-version=autoscaling/v2 | grep -E '^ +[a-zA-Z]+\s+<'
k apply -f /opt/ckad/3.7/current.yaml
k -n upgrade rollout status deploy catalog
k -n upgrade get deploy,pdb,hpa
EOF
}

# ---- Task 8: a client that never reaches its backend ---------------------------------------------------
setup_3_8() {
  ns_fresh troubleshoot
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: troubleshoot
spec:
  replicas: 2
  selector:
    matchLabels: {app: backend}
  template:
    metadata:
      labels: {app: backend}
    spec:
      containers:
      - name: web
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www && echo backend ok > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet: {path: /health, port: 8080}
          periodSeconds: 3
---
apiVersion: v1
kind: Service
metadata:
  name: backend
  namespace: troubleshoot
spec:
  selector: {app: back-end}
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: troubleshoot
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "1d"]
EOF
  cp_sh 'kubectl -n troubleshoot wait pod client --for=condition=Ready --timeout=90s >/dev/null; kubectl -n troubleshoot exec client -- wget -qO- -T 3 http://backend 2>&1 | tail -1'
}
check_3_8() {
  check_cp "client gets 'backend ok' from http://backend" "kubectl -n troubleshoot exec client -- wget -qO- -T 3 http://backend | grep -qx 'backend ok'"
  check_cp "Service backend has 2 ready endpoints" \
    "[ \$(kubectl -n troubleshoot get endpointslice -l kubernetes.io/service-name=backend -o jsonpath='{range .items[*].endpoints[?(@.conditions.ready==true)]}{.addresses[0]} {end}' | wc -w) = 2 ]"
  check_json "the Deployment keeps its labels and a readiness probe" "kubectl -n troubleshoot get deploy backend -o json" \
    't=p["spec"]["template"]; t["metadata"]["labels"]=={"app":"backend"} and "readinessProbe" in t["spec"]["containers"][0]'
}
solve_3_8() {
  shown <<'EOF'
k -n troubleshoot get svc,endpointslice
k -n troubleshoot get pods --show-labels
k -n troubleshoot describe pod -l app=backend | grep Readiness | head -2
k -n troubleshoot patch svc backend -p '{"spec":{"selector":{"app":"backend"},"ports":[{"port":80,"targetPort":8080}]}}'
k -n troubleshoot patch deploy backend --type=json -p '[{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/httpGet/path","value":"/"}]'
k -n troubleshoot rollout status deploy backend
k -n troubleshoot get endpointslice
k -n troubleshoot exec client -- wget -qO- http://backend
EOF
}
