# Domain 01, application design and build. Functions for task.sh: setup_1_N, check_1_N, solve_1_N.

REG=registry.ckad:5000
# Forget a repository in the local registry and in podman, so a setup starts clean: reg_forget greeter
reg_forget() { cp_sh "rm -rf /var/lib/ckad-registry/docker/registry/v2/repositories/$1; podman rmi -f \$(podman images -q $REG/$1) >/dev/null 2>&1; true"; }

# ---- Task 1: build an image and push it ------------------------------------------------
setup_1_1() {
  need_extras || return 1
  ns_fresh build
  reg_forget greeter
  cp_sh 'rm -rf /opt/ckad/1.1'
  put_file /opt/ckad/1.1/Dockerfile <<'EOF'
FROM docker.io/library/busybox:1.36
COPY greet.sh /usr/local/bin/greet.sh
RUN chmod 755 /usr/local/bin/greet.sh
ENV GREETING=hello
CMD ["/usr/local/bin/greet.sh"]
EOF
  put_file /opt/ckad/1.1/greet.sh <<'EOF'
#!/bin/sh
while true; do
  echo "$GREETING from $(hostname)"
  sleep 5
done
EOF
  cp_sh 'ls -l /opt/ckad/1.1'
}
check_1_1() {
  check_cp "the registry holds greeter:v1" "curl -fsS http://$REG/v2/greeter/tags/list | grep -q '\"v1\"'"
  check_cp "/opt/ckad/1.1/greeter-v1.tar is an image archive" "tar -tf /opt/ckad/1.1/greeter-v1.tar | grep -q manifest.json"
  check_cp "pod greeter in build runs $REG/greeter:v1" \
    "kubectl -n build get pod greeter -o jsonpath='{.spec.containers[0].image}' | grep -qx $REG/greeter:v1 && kubectl -n build wait pod greeter --for=condition=Ready --timeout=60s"
  check_cp "pod greeter logs 'hello from greeter'" "kubectl -n build logs greeter | grep -q 'hello from greeter'"
}
solve_1_1() {
  shown <<'EOF'
cd /opt/ckad/1.1
podman build -t registry.ckad:5000/greeter:v1 .
podman push registry.ckad:5000/greeter:v1
podman save -o greeter-v1.tar registry.ckad:5000/greeter:v1
k -n build run greeter --image=registry.ckad:5000/greeter:v1
k -n build wait pod greeter --for=condition=Ready --timeout=90s
k -n build logs greeter
EOF
}

# ---- Task 2: change a Dockerfile and roll the new image out ---------------------------
setup_1_2() {
  need_extras || return 1
  ns_fresh build-report
  reg_forget report
  put_file /opt/ckad/1.2/Dockerfile <<'EOF'
FROM docker.io/library/busybox:1.36
ENV APP_COLOR=red
COPY report.sh /report.sh
CMD ["sh", "/report.sh"]
EOF
  put_file /opt/ckad/1.2/report.sh <<'EOF'
while true; do
  echo "color=$APP_COLOR user=$(id -u)"
  sleep 5
done
EOF
  cp_sh "cd /opt/ckad/1.2 && podman build -q -t $REG/report:v1 . >/dev/null && podman push -q $REG/report:v1
    kubectl -n build-report create deploy report --image=$REG/report:v1 2>/dev/null
    kubectl -n build-report rollout status deploy report --timeout=120s"
}
check_1_2() {
  check_cp "Deployment report runs $REG/report:v2" \
    "kubectl -n build-report get deploy report -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qx $REG/report:v2"
  check_cp "the registry still holds report:v1 and now report:v2" \
    "curl -fsS http://$REG/v2/report/tags/list | grep -q '\"v1\"' && curl -fsS http://$REG/v2/report/tags/list | grep -q '\"v2\"'"
  check_cp "the new pods log color=blue user=1000" \
    "kubectl -n build-report rollout status deploy report --timeout=90s && for i in \$(seq 1 30); do kubectl -n build-report logs deploy/report 2>/dev/null | grep -q 'color=blue user=1000' && exit 0; sleep 2; done; exit 1"
}
solve_1_2() {
  cp_sh "cd /opt/ckad/1.2 && sed -i 's/APP_COLOR=red/APP_COLOR=blue/' Dockerfile && echo 'USER 1000' >> Dockerfile"
  shown <<'EOF'
cd /opt/ckad/1.2
cat Dockerfile
podman build -t registry.ckad:5000/report:v2 .
podman push registry.ckad:5000/report:v2
k -n build-report set image deploy/report report=registry.ckad:5000/report:v2
k -n build-report rollout status deploy report
k -n build-report get pods
EOF
  settled build-report report 1
  shown <<'EOF'
k -n build-report get pods
k -n build-report logs deploy/report
EOF
}

# ---- Task 3: an init container prepares the content -------------------------------------
setup_1_3() {
  ns_fresh init-web
  put_file /opt/ckad/1.3/web.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: init-web
spec:
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    ports:
    - containerPort: 80
EOF
  cp_sh 'cat /opt/ckad/1.3/web.yaml'
}
check_1_3() {
  check_json "pod web has an init container prepare" "kubectl -n init-web get pod web -o json" \
    '[c["name"] for c in p["spec"].get("initContainers",[])] == ["prepare"]'
  check_cp "pod web is Ready" "kubectl -n init-web wait pod web --for=condition=Ready --timeout=60s"
  check_cp "nginx serves 'ready from init'" "kubectl -n init-web exec web -c nginx -- wget -qO- http://localhost/ | grep -q 'ready from init'"
}
solve_1_3() {
  put_file /opt/ckad/1.3/web.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: init-web
spec:
  initContainers:
  - name: prepare
    image: busybox:1.36
    command: ["sh", "-c", "echo 'ready from init' > /work/index.html"]
    volumeMounts:
    - name: html
      mountPath: /work
  containers:
  - name: nginx
    image: nginx:1.27-alpine
    ports:
    - containerPort: 80
    volumeMounts:
    - name: html
      mountPath: /usr/share/nginx/html
  volumes:
  - name: html
    emptyDir: {}
EOF
  shown <<'EOF'
k apply -f /opt/ckad/1.3/web.yaml
k -n init-web get pod web
k -n init-web wait pod web --for=condition=Ready
k -n init-web exec web -c nginx -- wget -qO- http://localhost/
EOF
}

# ---- Task 4: a native sidecar that ships the log ----------------------------------------
setup_1_4() {
  ns_fresh sidecar
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  namespace: sidecar
spec:
  replicas: 1
  selector:
    matchLabels: {app: app}
  template:
    metadata:
      labels: {app: app}
    spec:
      containers:
      - name: app
        image: busybox:1.36
        command: ["sh", "-c", "i=0; while true; do i=$((i+1)); echo \"$(date +%T) order $i accepted\" >> /var/log/app/app.log; sleep 3; done"]
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
      volumes:
      - name: logs
        emptyDir: {}
EOF
  rolled sidecar app && cp_sh 'kubectl -n sidecar get deploy app'
}
check_1_4() {
  check_json "the pod template has a native sidecar named shipper" "kubectl -n sidecar get deploy app -o json" \
    'any(c["name"]=="shipper" and c.get("restartPolicy")=="Always" for c in p["spec"]["template"]["spec"].get("initContainers",[]))'
  check_cp "the Deployment is rolled out" "kubectl -n sidecar rollout status deploy app --timeout=90s"
  check_cp "the shipper's log shows the orders" "for i in \$(seq 1 30); do kubectl -n sidecar logs deploy/app -c shipper 2>/dev/null | grep -q 'order .* accepted' && exit 0; sleep 2; done; exit 1"
  check_cp "container app still writes the log" "kubectl -n sidecar exec deploy/app -c app -- tail -1 /var/log/app/app.log | grep -q accepted"
}
solve_1_4() {
  put_file /opt/ckad/1.4/patch.yaml <<'EOF'
spec:
  template:
    spec:
      initContainers:
      - name: shipper
        image: busybox:1.36
        restartPolicy: Always
        command: ["sh", "-c", "tail -F /var/log/app/app.log"]
        volumeMounts:
        - name: logs
          mountPath: /var/log/app
EOF
  shown <<'EOF'
k -n sidecar patch deploy app --patch-file /opt/ckad/1.4/patch.yaml
k -n sidecar rollout status deploy app
k -n sidecar get pod -l app=app
EOF
  settled sidecar app 1
  shown <<'EOF'
k -n sidecar get pod -l app=app
k -n sidecar logs deploy/app -c shipper --tail=3
EOF
}

# ---- Task 5: a Job with parallel completions ----------------------------------------------
setup_1_5() { ns_fresh batch; }
check_1_5() {
  check_json "Job checksum: 6 completions, 3 at a time, backoffLimit 3, deadline 120s" "kubectl -n batch get job checksum -o json" \
    'p["spec"]["completions"]==6 and p["spec"]["parallelism"]==3 and p["spec"]["backoffLimit"]==3 and p["spec"]["activeDeadlineSeconds"]==120'
  check_json "its pods carry the label job-type=checksum" "kubectl -n batch get job checksum -o json" \
    'p["spec"]["template"]["metadata"]["labels"].get("job-type")=="checksum"'
  check_cp "the Job completed 6 times" "kubectl -n batch wait job checksum --for=condition=Complete --timeout=120s"
  check_cp "a pod logged its checksum line" "kubectl -n batch logs job/checksum | grep -q 'checksum done on'"
}
solve_1_5() {
  shown <<'EOF'
mkdir -p /opt/ckad/1.5
k -n batch create job checksum --image=busybox:1.36 $do -- sh -c 'echo "checksum done on $(hostname)"; sleep 3' > /opt/ckad/1.5/job.yaml
EOF
  put_file /opt/ckad/1.5/job.yaml <<'EOF'
apiVersion: batch/v1
kind: Job
metadata:
  name: checksum
  namespace: batch
spec:
  completions: 6
  parallelism: 3
  backoffLimit: 3
  activeDeadlineSeconds: 120
  template:
    metadata:
      labels:
        job-type: checksum
    spec:
      containers:
      - name: checksum
        image: busybox:1.36
        command: ["sh", "-c", "echo \"checksum done on $(hostname)\"; sleep 3"]
      restartPolicy: Never
EOF
  shown <<'EOF'
k apply -f /opt/ckad/1.5/job.yaml
k -n batch get pods -l job-type=checksum
k -n batch wait job checksum --for=condition=Complete --timeout=120s
k -n batch get job checksum
EOF
}

# ---- Task 6: a CronJob, and a run right now -------------------------------------------------
setup_1_6() { ns_fresh batch-cron; }
check_json_cron='kubectl -n batch-cron get cronjob cleanup -o json'
check_1_6() {
  check_json "CronJob cleanup runs every 30 minutes and forbids overlaps" "$check_json_cron" \
    'p["spec"]["schedule"]=="*/30 * * * *" and p["spec"]["concurrencyPolicy"]=="Forbid"'
  check_json "it keeps 2 successful and 4 failed Jobs, and starts at most 60s late" "$check_json_cron" \
    'p["spec"]["successfulJobsHistoryLimit"]==2 and p["spec"]["failedJobsHistoryLimit"]==4 and p["spec"]["startingDeadlineSeconds"]==60'
  check_cp "Job cleanup-now came from the CronJob and completed" \
    "kubectl -n batch-cron get job cleanup-now -o jsonpath='{.metadata.ownerReferences[0].name}' | grep -qx cleanup && kubectl -n batch-cron wait job cleanup-now --for=condition=Complete --timeout=60s"
  check_cp "its pod logged 'removed temporary files'" "kubectl -n batch-cron logs job/cleanup-now | grep -q 'removed temporary files'"
}
solve_1_6() {
  shown <<'EOF'
mkdir -p /opt/ckad/1.6
k -n batch-cron create cronjob cleanup --image=busybox:1.36 --schedule='*/30 * * * *' $do -- sh -c 'echo removed temporary files' > /opt/ckad/1.6/cj.yaml
EOF
  cp_sh "cd /opt/ckad/1.6 && python3 - <<'PY'
p='cj.yaml'; s=open(p).read()
s=s.replace('  schedule: ', '  concurrencyPolicy: Forbid\n  successfulJobsHistoryLimit: 2\n  failedJobsHistoryLimit: 4\n  startingDeadlineSeconds: 60\n  schedule: ')
open(p,'w').write(s)
PY"
  shown <<'EOF'
grep -E 'concurrency|History|starting|schedule' /opt/ckad/1.6/cj.yaml
k apply -f /opt/ckad/1.6/cj.yaml
k -n batch-cron create job cleanup-now --from=cronjob/cleanup
k -n batch-cron wait job cleanup-now --for=condition=Complete
k -n batch-cron logs job/cleanup-now
EOF
}

# ---- Task 7: a DaemonSet on every node --------------------------------------------------------
setup_1_7() { ns_fresh agents; }
check_1_7() {
  check_cp "DaemonSet node-agent has a ready pod on both nodes" \
    "kubectl -n agents rollout status ds node-agent --timeout=90s && kubectl -n agents get ds node-agent -o jsonpath='{.status.numberReady}' | grep -qx 2"
  check_cp "one of its pods runs on cks-cp" "kubectl -n agents get pod -l app=node-agent -o wide | grep -q cks-cp"
  check_json "the container requests 10m CPU and 16Mi memory" "kubectl -n agents get ds node-agent -o json" \
    'p["spec"]["template"]["spec"]["containers"][0]["resources"]["requests"]=={"cpu":"10m","memory":"16Mi"}'
}
solve_1_7() {
  put_file /opt/ckad/1.7/ds.yaml <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
  namespace: agents
spec:
  selector:
    matchLabels:
      app: node-agent
  template:
    metadata:
      labels:
        app: node-agent
    spec:
      tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
      containers:
      - name: agent
        image: busybox:1.36
        command: ["sleep", "1d"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
EOF
  shown <<'EOF'
k describe node cks-cp | grep Taints
k apply -f /opt/ckad/1.7/ds.yaml
k -n agents rollout status ds node-agent
k -n agents get pod -o wide
EOF
}

# ---- Task 8: a PersistentVolume, a claim and a pod ----------------------------------------------
setup_1_8() { ns_fresh storage; cp_sh 'kubectl delete pv ckad-pv-data --ignore-not-found >/dev/null'; w1_sh 'rm -rf /var/lib/ckad-data'; }
check_1_8() {
  check_json "PersistentVolume ckad-pv-data: 1Gi, ReadWriteOnce, class manual, hostPath /var/lib/ckad-data" "kubectl get pv ckad-pv-data -o json" \
    'p["spec"]["capacity"]["storage"]=="1Gi" and p["spec"]["accessModes"]==["ReadWriteOnce"] and p["spec"]["storageClassName"]=="manual" and p["spec"]["hostPath"]["path"]=="/var/lib/ckad-data"'
  check_cp "PVC data-claim in storage is Bound to ckad-pv-data" \
    "kubectl -n storage get pvc data-claim -o jsonpath='{.status.phase} {.spec.volumeName}' | grep -qx 'Bound ckad-pv-data'"
  check_cp "pod writer mounts the claim at /data and is Ready" \
    "kubectl -n storage wait pod writer --for=condition=Ready --timeout=60s && kubectl -n storage get pod writer -o jsonpath='{.spec.volumes[*].persistentVolumeClaim.claimName}' | grep -qx data-claim"
  check_w1 "the file lands on cks-w1 in /var/lib/ckad-data/visits.log" "grep -q visit /var/lib/ckad-data/visits.log"
}
solve_1_8() {
  put_file /opt/ckad/1.8/storage.yaml <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ckad-pv-data
spec:
  capacity:
    storage: 1Gi
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  hostPath:
    path: /var/lib/ckad-data
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data-claim
  namespace: storage
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: manual
  resources:
    requests:
      storage: 500Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: writer
  namespace: storage
spec:
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo visit $(date +%T) >> /data/visits.log; sleep 5; done"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: data-claim
EOF
  shown <<'EOF'
k apply -f /opt/ckad/1.8/storage.yaml
k -n storage get pvc data-claim
k -n storage wait pod writer --for=condition=Ready
k -n storage get pod writer -o wide
EOF
  shown cks-w1 <<'EOF'
sleep 5
cat /var/lib/ckad-data/visits.log
EOF
}

# ---- Task 9: from a bare pod to a Deployment ----------------------------------------------------
setup_1_9() {
  ns_fresh legacy
  cp_sh "kubectl apply -f - >/dev/null && kubectl -n legacy wait pod api --for=condition=Ready --timeout=90s" <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: legacy
  labels: {app: api, tier: backend}
spec:
  containers:
  - name: api
    image: nginx:1.27-alpine
    env:
    - {name: MODE, value: production}
    - {name: LOG_LEVEL, value: warn}
    ports:
    - containerPort: 80
    resources:
      requests: {cpu: 50m, memory: 32Mi}
EOF
  cp_sh 'kubectl -n legacy get pod --show-labels'
}
check_1_9() {
  check_cp "Deployment api has 3 ready replicas" "kubectl -n legacy rollout status deploy api --timeout=90s && kubectl -n legacy get deploy api -o jsonpath='{.status.readyReplicas}' | grep -qx 3"
  check_json "its pods keep the labels, image, env and requests of the old pod" "kubectl -n legacy get deploy api -o json" \
    't=p["spec"]["template"]; c=t["spec"]["containers"][0]; t["metadata"]["labels"].get("app")=="api" and t["metadata"]["labels"].get("tier")=="backend" and c["image"]=="nginx:1.27-alpine" and {"name":"MODE","value":"production"} in c["env"] and {"name":"LOG_LEVEL","value":"warn"} in c["env"] and c["resources"]["requests"]=={"cpu":"50m","memory":"32Mi"}'
  check_cp "the bare pod api is gone" "! kubectl -n legacy get pod api"
}
solve_1_9() {
  shown <<'EOF'
mkdir -p /opt/ckad/1.9
k -n legacy get pod api -o yaml > /opt/ckad/1.9/pod.yaml
k -n legacy create deploy api --image=nginx:1.27-alpine --replicas=3 $do > /opt/ckad/1.9/deploy.yaml
EOF
  put_file /opt/ckad/1.9/deploy.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: legacy
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
        tier: backend
    spec:
      containers:
      - name: api
        image: nginx:1.27-alpine
        env:
        - name: MODE
          value: production
        - name: LOG_LEVEL
          value: warn
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
EOF
  shown <<'EOF'
k apply -f /opt/ckad/1.9/deploy.yaml
k -n legacy delete pod api
k -n legacy rollout status deploy api
k -n legacy get pod --show-labels
EOF
}

# ---- Task 10: init, sidecar and main container in one pod ------------------------------------------
setup_1_10() { ns_fresh etl; }
check_1_10() {
  check_json "pod pipeline: init container fetch runs once, exporter is a native sidecar" "kubectl -n etl get pod pipeline -o json" \
    'i={c["name"]:c.get("restartPolicy") for c in p["spec"]["initContainers"]}; i.get("fetch") is None and "fetch" in i and i.get("exporter")=="Always" and list(i)[0]=="fetch"'
  check_json "the main container is transform, and one emptyDir volume work is shared by all three" "kubectl -n etl get pod pipeline -o json" \
    's=p["spec"]; cs=s["initContainers"]+s["containers"]; [c["name"] for c in s["containers"]]==["transform"] and any(v["name"]=="work" and "emptyDir" in v for v in s["volumes"]) and all(any(m["name"]=="work" and m["mountPath"]=="/work" for m in c.get("volumeMounts",[])) for c in cs)'
  check_cp "pod pipeline is Ready" "kubectl -n etl wait pod pipeline --for=condition=Ready --timeout=60s"
  check_cp "the exporter serves output.txt in capitals on port 8080" \
    "kubectl -n etl exec pipeline -c transform -- wget -qO- http://localhost:8080/output.txt | grep -q '^ALPHA'"
}
solve_1_10() {
  put_file /opt/ckad/1.10/pipeline.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: pipeline
  namespace: etl
spec:
  initContainers:
  - name: fetch
    image: busybox:1.36
    command: ["sh", "-c", "printf 'alpha\\nbeta\\ngamma\\n' > /work/input.txt"]
    volumeMounts:
    - {name: work, mountPath: /work}
  - name: exporter
    image: busybox:1.36
    restartPolicy: Always
    command: ["httpd", "-f", "-p", "8080", "-h", "/work"]
    ports:
    - containerPort: 8080
    volumeMounts:
    - {name: work, mountPath: /work}
  containers:
  - name: transform
    image: busybox:1.36
    command: ["sh", "-c", "while true; do tr a-z A-Z < /work/input.txt > /work/output.txt; sleep 10; done"]
    volumeMounts:
    - {name: work, mountPath: /work}
  volumes:
  - name: work
    emptyDir: {}
EOF
  shown <<'EOF'
k apply -f /opt/ckad/1.10/pipeline.yaml
k -n etl wait pod pipeline --for=condition=Ready
k -n etl get pod pipeline
k -n etl exec pipeline -c transform -- wget -qO- http://localhost:8080/output.txt
EOF
}
