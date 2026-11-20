# Practice exam 3: the hardest, several objects per task.
# setup_mN seeds task N, score_mN checks it, solve_mN is the reference solution.

MOCK_TASKS="1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16"
mock_points() {
  case "$1" in
    1) echo 8;; 2) echo 7;; 3) echo 7;; 4) echo 7;; 5) echo 7;; 6) echo 6;; 7) echo 4;; 8) echo 7;;
    9) echo 6;; 10) echo 6;; 11) echo 6;; 12) echo 6;; 13) echo 7;; 14) echo 5;; 15) echo 5;; 16) echo 6;;
  esac
}
mock_title() {
  case "$1" in
    1) echo "Image with a build argument";; 2) echo "Blue-green behind an Ingress";; 3) echo "Helm: values, failure, rollback";;
    4) echo "StatefulSet with its own volumes";; 5) echo "Init, sidecar, probes";; 6) echo "A ClusterRole for custom resources";;
    7) echo "Custom resources by the numbers";; 8) echo "Three tiers, three policies";; 9) echo "Quota and LimitRange together";;
    10) echo "One volume, two sources";; 11) echo "Debug a copy of a crashing pod";; 12) echo "A history to read";;
    13) echo "Two overlays from one base";; 14) echo "A Job that cleans up after itself";;
    15) echo "An Ingress with a default backend";; 16) echo "Port 80 without root";;
  esac
}

# ---- 1. Image with a build argument (8) -----------------------------------------------------------
setup_m1() {
  ns_new k3-build
  put_file /opt/apps/m3/1/Dockerfile <<'EOF'
FROM docker.io/library/busybox:1.36
ARG VERSION=dev
ENV APP_VERSION=$VERSION
RUN mkdir -p /www && echo "version $VERSION" > /www/index.html
CMD ["httpd", "-f", "-p", "8080", "-h", "/www"]
EOF
}
score_m1() {
  check_cp "the registry holds pricing:2.4.0 and pricing:stable with the same digest" \
    "a=\$(curl -fsSI -H 'Accept: application/vnd.oci.image.manifest.v1+json' -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' http://registry.practice:5000/v2/pricing/manifests/2.4.0 | grep -i docker-content-digest); b=\$(curl -fsSI -H 'Accept: application/vnd.oci.image.manifest.v1+json' -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' http://registry.practice:5000/v2/pricing/manifests/stable | grep -i docker-content-digest); [ -n \"\$a\" ] && [ \"\$a\" = \"\$b\" ]"
  check_cp "Deployment pricing runs pricing:2.4.0 with 2 ready pods that answer 'version 2.4.0'" \
    "kubectl -n k3-build get deploy pricing -o jsonpath='{.spec.template.spec.containers[0].image} {.status.readyReplicas}' | grep -qx 'registry.practice:5000/pricing:2.4.0 2' && kubectl -n k3-build exec --pod-running-timeout=5s deploy/pricing -c pricing -- wget -qO- localhost:8080 | grep -qx 'version 2.4.0'"
  check_cp "its pods have an init container wait-dns that waits for the cluster DNS" \
    "kubectl -n k3-build get deploy pricing -o jsonpath='{.spec.template.spec.initContainers[0].name}' | grep -qx wait-dns"
  check_cp "/opt/apps/m3/1/pricing.tar is an OCI archive of the image" "tar -tf /opt/apps/m3/1/pricing.tar | grep -q '^index.json\$'"
}
solve_m1() {
  cp_sh "cd /opt/apps/m3/1 && podman build -q --build-arg VERSION=2.4.0 -t registry.practice:5000/pricing:2.4.0 . && podman tag registry.practice:5000/pricing:2.4.0 registry.practice:5000/pricing:stable
    podman push -q registry.practice:5000/pricing:2.4.0 && podman push -q registry.practice:5000/pricing:stable
    podman save -q --format oci-archive -o pricing.tar registry.practice:5000/pricing:2.4.0
    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata: {name: pricing, namespace: k3-build}
spec:
  replicas: 2
  selector: {matchLabels: {app: pricing}}
  template:
    metadata: {labels: {app: pricing}}
    spec:
      initContainers:
      - name: wait-dns
        image: busybox:1.36
        command: [sh, -c, 'until nslookup kubernetes.default.svc.cluster.local; do sleep 2; done']
      containers:
      - name: pricing
        image: registry.practice:5000/pricing:2.4.0
EOF
    kubectl -n k3-build rollout status deploy pricing --timeout=120s"
}

# ---- 2. Blue-green behind an Ingress (7) -----------------------------------------------------------
setup_m2() {
  ns_new k3-bg
  echo_deploy k3-bg app-blue blue 2 app=bgapp color=blue
  cp_sh "kubectl -n k3-bg expose deploy app-blue --name=app-blue --port=80 --target-port=8080 >/dev/null
    kubectl -n k3-bg create ingress app --class=nginx --rule='app.k3.local/*=app-blue:80' >/dev/null"
}
score_m2() {
  check_cp "app.k3.local answers green through the ingress" "for i in \$(seq 1 15); do curl -s -m 3 -H 'Host: app.k3.local' http://$W1IP:30080/ | grep -qx green && exit 0; sleep 2; done; exit 1"
  check_cp "Service app-green selects only color=green pods, 2 endpoints" \
    "kubectl -n k3-bg get svc app-green -o jsonpath='{.spec.selector.color}' | grep -qx green && [ \$(kubectl -n k3-bg get endpointslice -l kubernetes.io/service-name=app-green -o jsonpath='{.items[*].endpoints[*].addresses[0]}' | wc -w) = 2 ]"
  check_cp "app-blue and its Service still exist for a switch back" "kubectl -n k3-bg get deploy app-blue && kubectl -n k3-bg get svc app-blue"
  check_cp "preview.k3.local answers blue" "curl -s -m 3 -H 'Host: preview.k3.local' http://$W1IP:30080/ | grep -qx blue"
}
solve_m2() {
  echo_deploy k3-bg app-green green 2 app=bgapp color=green
  cp_sh "kubectl -n k3-bg rollout status deploy app-green --timeout=120s
    kubectl -n k3-bg expose deploy app-green --name=app-green --port=80 --target-port=8080
    kubectl -n k3-bg patch ingress app --type=json -p='[{\"op\":\"replace\",\"path\":\"/spec/rules/0/http/paths/0/backend/service/name\",\"value\":\"app-green\"},{\"op\":\"add\",\"path\":\"/spec/rules/-\",\"value\":{\"host\":\"preview.k3.local\",\"http\":{\"paths\":[{\"path\":\"/\",\"pathType\":\"Prefix\",\"backend\":{\"service\":{\"name\":\"app-blue\",\"port\":{\"number\":80}}}}]}}}]'"
}

# ---- 3. Helm: values, failure, rollback (7) ---------------------------------------------------------
setup_m3() {
  charts_ready || return 1
  ns_new k3-helm
  cp_sh "helm -n k3-helm install shop oci://registry.practice:5000/charts/webapp --version 0.1.0 --plain-http --set replicaCount=2 --wait --timeout 120s >/dev/null 2>&1
    helm -n k3-helm upgrade shop oci://registry.practice:5000/charts/webapp --version 0.2.0 --plain-http --reuse-values --set replicaCount=3 --wait --timeout 120s >/dev/null 2>&1
    helm -n k3-helm upgrade shop oci://registry.practice:5000/charts/webapp --version 0.2.0 --plain-http --reuse-values --set resources.requests.memory=64Gi --wait --timeout 10s >/dev/null 2>&1
    helm -n k3-helm install admin oci://registry.practice:5000/charts/webapp --version 0.1.0 --plain-http --set image.tag=gone --wait --timeout 10s >/dev/null 2>&1; true"
}
score_m3() {
  check_cp "release shop is back on the values of revision 2: chart 0.2.0, 3 replicas, no 64Gi request" \
    "helm -n k3-helm status shop | grep -q 'STATUS: deployed' && kubectl -n k3-helm get deploy shop-webapp -o jsonpath='{.status.readyReplicas}' | grep -qx 3 && ! kubectl -n k3-helm get deploy shop-webapp -o yaml | grep -q 64Gi"
  check_cp "shop's history shows a rollback to 2" "helm -n k3-helm history shop | grep -q 'Rollback to 2'"
  check_cp "release admin is gone" "! helm -n k3-helm status admin"
  check_cp "/opt/apps/m3/3/values-rev2.yaml holds revision 2's user values" "grep -q 'replicaCount: 3' /opt/apps/m3/3/values-rev2.yaml"
}
solve_m3() {
  cp_sh "mkdir -p /opt/apps/m3/3
    helm -n k3-helm get values shop --revision 2 > /opt/apps/m3/3/values-rev2.yaml
    helm -n k3-helm rollback shop 2 --wait --timeout 120s
    helm -n k3-helm uninstall admin
    helm -n k3-helm history shop"
}

# ---- 4. StatefulSet with its own volumes (7) ----------------------------------------------------------
setup_m4() {
  ns_new k3-sts
  w1_sh 'rm -rf /var/lib/ckad-data/k3'
  cp_sh "kubectl delete pv ckad-k3-0 ckad-k3-1 --ignore-not-found >/dev/null
    for i in 0 1; do kubectl apply -f - >/dev/null <<EOF
apiVersion: v1
kind: PersistentVolume
metadata: {name: ckad-k3-\$i, labels: {ckad: mock}}
spec:
  capacity: {storage: 1Gi}
  accessModes: [ReadWriteOnce]
  storageClassName: ckad-local
  persistentVolumeReclaimPolicy: Delete
  hostPath: {path: /var/lib/ckad-data/k3/vol-\$i, type: DirectoryOrCreate}
EOF
    done"
}
score_m4() {
  check_cp "StatefulSet queue has 2 ready pods behind headless Service queue" \
    "kubectl -n k3-sts get sts queue -o jsonpath='{.status.readyReplicas} {.spec.serviceName}' | grep -qx '2 queue' && kubectl -n k3-sts get svc queue -o jsonpath='{.spec.clusterIP}' | grep -qx None"
  check_cp "each pod has its own bound claim data-queue-N of class ckad-local" \
    "for i in 0 1; do kubectl -n k3-sts get pvc data-queue-\$i -o jsonpath='{.status.phase} {.spec.storageClassName}' | grep -qx 'Bound ckad-local' || exit 1; done"
  check_cp "queue-1 keeps its file /data/id after a restart" \
    "kubectl -n k3-sts exec queue-1 -- cat /data/id | grep -qx queue-1 && kubectl -n k3-sts delete pod queue-1 --wait=true >/dev/null && kubectl -n k3-sts wait pod queue-1 --for=condition=Ready --timeout=90s >/dev/null && kubectl -n k3-sts exec queue-1 -- cat /data/id | grep -qx queue-1"
}
solve_m4() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Service
metadata: {name: queue, namespace: k3-sts}
spec:
  clusterIP: None
  selector: {app: queue}
  ports: [{port: 8080}]
---
apiVersion: apps/v1
kind: StatefulSet
metadata: {name: queue, namespace: k3-sts}
spec:
  serviceName: queue
  replicas: 2
  selector: {matchLabels: {app: queue}}
  template:
    metadata: {labels: {app: queue}}
    spec:
      containers:
      - name: queue
        image: busybox:1.36
        command: [sh, -c, 'test -f /data/id || hostname > /data/id; sleep 1d']
        volumeMounts: [{name: data, mountPath: /data}]
  volumeClaimTemplates:
  - metadata: {name: data}
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: ckad-local
      resources: {requests: {storage: 1Gi}}
EOF
    kubectl -n k3-sts rollout status sts queue --timeout=120s"
}

# ---- 5. Init, sidecar, probes (7) --------------------------------------------------------------------------
setup_m5() { ns_new k3-pod; }
score_m5() {
  check_json "pod gateway: init config-gen, then native sidecar proxy, then app" "kubectl -n k3-pod get pod gateway -o json" \
    's=p["spec"]; [c["name"] for c in s["initContainers"]]==["config-gen","proxy"] and s["initContainers"][1].get("restartPolicy")=="Always" and s["initContainers"][0].get("restartPolicy") is None and [c["name"] for c in s["containers"]]==["app"]'
  check_json "proxy has a readiness probe on 9090, app a liveness probe that runs cat /conf/app.conf" "kubectl -n k3-pod get pod gateway -o json" \
    's=p["spec"]; str(s["initContainers"][1]["readinessProbe"]["httpGet"]["port"])=="9090" and s["containers"][0]["livenessProbe"]["exec"]["command"]==["cat","/conf/app.conf"]'
  check_cp "the pod is Ready and the proxy serves app.conf on 9090" \
    "kubectl -n k3-pod wait pod gateway --for=condition=Ready --timeout=10s && kubectl -n k3-pod exec gateway -c app -- wget -qO- localhost:9090/app.conf | grep -q 'mode=gateway'"
}
solve_m5() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: gateway, namespace: k3-pod}
spec:
  initContainers:
  - name: config-gen
    image: busybox:1.36
    command: [sh, -c, 'echo mode=gateway > /conf/app.conf']
    volumeMounts: [{name: conf, mountPath: /conf}]
  - name: proxy
    image: busybox:1.36
    restartPolicy: Always
    command: [httpd, -f, -p, '9090', -h, /conf]
    readinessProbe:
      httpGet: {path: /app.conf, port: 9090}
    volumeMounts: [{name: conf, mountPath: /conf}]
  containers:
  - name: app
    image: busybox:1.36
    command: [sleep, 1d]
    livenessProbe:
      exec: {command: [cat, /conf/app.conf]}
    volumeMounts: [{name: conf, mountPath: /conf}]
  volumes:
  - name: conf
    emptyDir: {}
EOF
    kubectl -n k3-pod wait pod gateway --for=condition=Ready --timeout=90s"
}

# ---- 6. A ClusterRole for custom resources (6) ----------------------------------------------------------------
setup_m6() {
  ns_new k3-team-a k3-team-b k3-tools
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata: {name: certificates.k3.ckad.io}
spec:
  group: k3.ckad.io
  scope: Namespaced
  names: {plural: certificates, singular: certificate, kind: Certificate, shortNames: [kcert]}
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              domain: {type: string}
              days: {type: integer}
EOF
  cp_sh 'kubectl -n k3-tools create sa cert-bot >/dev/null; kubectl wait crd certificates.k3.ckad.io --for=condition=Established --timeout=60s >/dev/null'
}
SA6=system:serviceaccount:k3-tools:cert-bot
score_m6() {
  check_cp "ClusterRole ckad-cert-manager allows get, list, create and update on certificates.k3.ckad.io" \
    "kubectl get clusterrole ckad-cert-manager && for v in get list create update; do kubectl auth can-i \$v certificates.k3.ckad.io -n k3-team-a --as=$SA6 | grep -qx yes || exit 1; done"
  check_cp "cert-bot has it in k3-team-a and k3-team-b" "kubectl auth can-i create certificates.k3.ckad.io -n k3-team-b --as=$SA6"
  check_cp "cert-bot has nothing in k3-tools or cluster-wide" \
    "! kubectl auth can-i list certificates.k3.ckad.io -n k3-tools --as=$SA6 && ! kubectl auth can-i list certificates.k3.ckad.io -A --as=$SA6 && ! kubectl auth can-i delete certificates.k3.ckad.io -n k3-team-a --as=$SA6"
}
solve_m6() {
  cp_sh "kubectl create clusterrole ckad-cert-manager --verb=get,list,create,update --resource=certificates.k3.ckad.io
    for n in k3-team-a k3-team-b; do kubectl -n \$n create rolebinding cert-bot --clusterrole=ckad-cert-manager --serviceaccount=k3-tools:cert-bot; done"
}

# ---- 7. Custom resources by the numbers (4) -------------------------------------------------------------------
setup_m7() {
  ns_new k3-certs
  cp_sh "for i in 1 2 3; do kubectl wait crd certificates.k3.ckad.io --for=condition=Established --timeout=60s >/dev/null 2>&1 && break; sleep 2; done
    kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: k3.ckad.io/v1
kind: Certificate
metadata: {name: shop, namespace: k3-team-a}
spec: {domain: shop.k3.local, days: 90}
---
apiVersion: k3.ckad.io/v1
kind: Certificate
metadata: {name: api, namespace: k3-team-b}
spec: {domain: api.k3.local, days: 14}
---
apiVersion: k3.ckad.io/v1
kind: Certificate
metadata: {name: blog, namespace: k3-team-b}
spec: {domain: blog.k3.local, days: 30}
EOF
}
score_m7() {
  check_cp "Certificate wiki in k3-certs: domain wiki.k3.local, 60 days" \
    "kubectl -n k3-certs get certificate wiki -o jsonpath='{.spec.domain} {.spec.days}' | grep -qx 'wiki.k3.local 60'"
  check_cp "/opt/apps/m3/7/expiring.txt lists the domain with the fewest days" "grep -qx api.k3.local /opt/apps/m3/7/expiring.txt"
}
solve_m7() {
  cp_sh "mkdir -p /opt/apps/m3/7
    kubectl apply -f - <<'EOF'
apiVersion: k3.ckad.io/v1
kind: Certificate
metadata: {name: wiki, namespace: k3-certs}
spec: {domain: wiki.k3.local, days: 60}
EOF
    kubectl get certificates -A --sort-by=.spec.days -o jsonpath='{.items[0].spec.domain}' > /opt/apps/m3/7/expiring.txt; echo >> /opt/apps/m3/7/expiring.txt
    cat /opt/apps/m3/7/expiring.txt"
}

# ---- 8. Three tiers, three policies (7) -----------------------------------------------------------------------
setup_m8() {
  ns_new k3-tiers
  web_app k3-tiers web web 8080 0 tier=web
  web_app k3-tiers api api 8080 0 tier=api
  web_app k3-tiers db db 5432 0 tier=db
  client_pod k3-tiers intruder tier=other
  cp_sh 'kubectl -n k3-tiers expose pod api --port=80 --target-port=8080 >/dev/null; kubectl -n k3-tiers expose pod db --port=5432 >/dev/null; kubectl -n k3-tiers expose pod web --port=80 --target-port=8080 >/dev/null'
}
score_m8() {
  check_cp "intruder does not reach api or db" "! kubectl -n k3-tiers exec intruder -- wget -qO- -T 3 http://api && ! kubectl -n k3-tiers exec intruder -- wget -qO- -T 3 http://db:5432"
  check_cp "web reaches api by name, api reaches db by name" \
    "kubectl -n k3-tiers exec web -- wget -qO- -T 3 http://api | grep -qx api && kubectl -n k3-tiers exec api -- wget -qO- -T 3 http://db:5432 | grep -qx db"
  check_cp "web does not reach db" "! kubectl -n k3-tiers exec web -- wget -qO- -T 3 http://db:5432"
  check_cp "db reaches nothing, not even web" "! kubectl -n k3-tiers exec db -- wget -qO- -T 3 http://web"
}
solve_m8() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: k3-tiers}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  egress:
  - ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: web, namespace: k3-tiers}
spec:
  podSelector: {matchLabels: {tier: web}}
  policyTypes: [Ingress, Egress]
  ingress:
  - ports: [{protocol: TCP, port: 8080}]
  egress:
  - to: [{podSelector: {matchLabels: {tier: api}}}]
    ports: [{protocol: TCP, port: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api, namespace: k3-tiers}
spec:
  podSelector: {matchLabels: {tier: api}}
  policyTypes: [Ingress, Egress]
  ingress:
  - from: [{podSelector: {matchLabels: {tier: web}}}]
    ports: [{protocol: TCP, port: 8080}]
  egress:
  - to: [{podSelector: {matchLabels: {tier: db}}}]
    ports: [{protocol: TCP, port: 5432}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db, namespace: k3-tiers}
spec:
  podSelector: {matchLabels: {tier: db}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {tier: api}}}]
    ports: [{protocol: TCP, port: 5432}]
EOF"
}

# ---- 9. Quota and LimitRange together (6) ------------------------------------------------------------------------
setup_m9() {
  ns_new k3-limits
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: v1
kind: ResourceQuota
metadata: {name: budget, namespace: k3-limits}
spec:
  hard: {requests.cpu: 600m, requests.memory: 600Mi, limits.cpu: "1", limits.memory: 1Gi}
---
apiVersion: v1
kind: LimitRange
metadata: {name: bounds, namespace: k3-limits}
spec:
  limits:
  - type: Container
    max: {cpu: 300m, memory: 256Mi}
    min: {cpu: 50m, memory: 32Mi}
EOF
  cp_sh "kubectl -n k3-limits create deploy indexer --image=busybox:1.36 --replicas=4 -- sleep 1d >/dev/null"
}
score_m9() {
  check_cp "Deployment indexer runs 4 ready pods" "kubectl -n k3-limits get deploy indexer -o jsonpath='{.spec.replicas} {.status.readyReplicas}' | grep -qx '4 4'"
  check_cp "the quota and the LimitRange are unchanged" "kubectl -n k3-limits get quota budget -o jsonpath='{.spec.hard.requests\.cpu}' | grep -qx 600m && kubectl -n k3-limits get limitrange bounds -o jsonpath='{.spec.limits[0].max.cpu}' | grep -qx 300m"
  check_json "each container sets requests and limits within the LimitRange" "kubectl -n k3-limits get deploy indexer -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["resources"]; all(k in r.get("requests",{}) and k in r.get("limits",{}) for k in ("cpu","memory"))'
}
solve_m9() {
  cp_sh "kubectl -n k3-limits scale deploy indexer --replicas=0
    kubectl -n k3-limits set resources deploy indexer --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi
    kubectl -n k3-limits scale deploy indexer --replicas=4
    kubectl -n k3-limits rollout status deploy indexer --timeout=120s"
}

# ---- 10. One volume, two sources (6) ------------------------------------------------------------------------------
setup_m10() {
  ns_new k3-proj
  cp_sh "kubectl -n k3-proj create cm tls-settings --from-literal=ciphers=modern --from-literal=port=8443 >/dev/null
    printf 'not-a-real-key\n' > /tmp/k3.key
    kubectl -n k3-proj create secret generic tls-key --from-file=server.key=/tmp/k3.key >/dev/null"
}
score_m10() {
  check_cp "pod edge sees /etc/tls/ciphers, /etc/tls/port and /etc/tls/server.key in one volume" \
    "kubectl -n k3-proj exec edge -- cat /etc/tls/ciphers | grep -qx modern && kubectl -n k3-proj exec edge -- cat /etc/tls/port | grep -qx 8443 && kubectl -n k3-proj exec edge -- cat /etc/tls/server.key | grep -qx not-a-real-key"
  check_json "the volume is one projected volume" "kubectl -n k3-proj get pod edge -o json" \
    'v=[x for x in p["spec"]["volumes"] if any(y.get("configMap",{}).get("name")=="tls-settings" for y in x.get("projected",{}).get("sources",[]))]; len(v)==1 and any(y.get("secret",{}).get("name")=="tls-key" for y in v[0]["projected"]["sources"])'
  check_cp "server.key has mode 0400" "kubectl -n k3-proj exec edge -- stat -L -c %a /etc/tls/server.key | grep -qx 400"
}
solve_m10() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: edge, namespace: k3-proj}
spec:
  containers:
  - name: edge
    image: busybox:1.36
    command: [sleep, 1d]
    volumeMounts: [{name: tls, mountPath: /etc/tls, readOnly: true}]
  volumes:
  - name: tls
    projected:
      sources:
      - configMap: {name: tls-settings}
      - secret:
          name: tls-key
          items: [{key: server.key, path: server.key, mode: 0400}]
EOF
    kubectl -n k3-proj wait pod edge --for=condition=Ready --timeout=60s"
}

# ---- 11. Debug a copy of a crashing pod (6) -----------------------------------------------------------------------
setup_m11() {
  ns_new k3-debug
  cp_sh "kubectl -n k3-debug run loader --image=busybox:1.36 --restart=Always -- sh -c 'cat /etc/loader/conf >/dev/null || exit 9; sleep 1d' >/dev/null"
}
score_m11() {
  check_cp "pod loader-debug exists and runs sleep 1d in container loader" \
    "kubectl -n k3-debug get pod loader-debug -o jsonpath='{.spec.containers[0].name} {.spec.containers[0].command}{.spec.containers[0].args}' | grep -q '^loader .*sleep' && kubectl -n k3-debug wait pod loader-debug --for=condition=Ready --timeout=10s"
  check_cp "the original pod loader is untouched" "kubectl -n k3-debug get pod loader -o jsonpath='{.spec.containers[0].args}' | grep -q 'exit 9'"
  check_cp "/opt/apps/m3/11/missing.txt names the missing path" "grep -qx /etc/loader/conf /opt/apps/m3/11/missing.txt"
}
solve_m11() {
  cp_sh "mkdir -p /opt/apps/m3/11
    kubectl -n k3-debug debug loader --copy-to=loader-debug --container=loader --image=busybox:1.36 -- sleep 1d
    kubectl -n k3-debug wait pod loader-debug --for=condition=Ready --timeout=60s
    kubectl -n k3-debug exec loader-debug -- ls /etc/loader 2>&1 | head -1
    echo /etc/loader/conf > /opt/apps/m3/11/missing.txt"
}

# ---- 12. A history to read (6) ---------------------------------------------------------------------------------
setup_m12() {
  ns_new k3-hist
  cp_sh "kubectl -n k3-hist create deploy portal --image=nginx:1.27-alpine --replicas=2 >/dev/null
    kubectl -n k3-hist annotate deploy portal kubernetes.io/change-cause='first release' >/dev/null
    kubectl -n k3-hist rollout status deploy portal --timeout=120s >/dev/null
    kubectl -n k3-hist set image deploy/portal nginx=nginx:1.28-alpine >/dev/null
    kubectl -n k3-hist annotate deploy portal kubernetes.io/change-cause='nginx 1.28' --overwrite >/dev/null
    kubectl -n k3-hist rollout status deploy portal --timeout=120s >/dev/null
    kubectl -n k3-hist set env deploy/portal FEATURE_X=on >/dev/null
    kubectl -n k3-hist annotate deploy portal kubernetes.io/change-cause='feature x' --overwrite >/dev/null
    kubectl -n k3-hist rollout status deploy portal --timeout=120s >/dev/null"
}
score_m12() {
  check_cp "portal runs the template of 'nginx 1.28': nginx 1.28 without FEATURE_X" \
    "kubectl -n k3-hist get deploy portal -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qx nginx:1.28-alpine && ! kubectl -n k3-hist get deploy portal -o yaml | grep -q FEATURE_X"
  check_cp "the history keeps at most 2 old ReplicaSets" "kubectl -n k3-hist get deploy portal -o jsonpath='{.spec.revisionHistoryLimit}' | grep -qx 2"
  check_cp "/opt/apps/m3/12/revision.txt holds the revision number of 'feature x'" "grep -qx 3 /opt/apps/m3/12/revision.txt"
}
solve_m12() {
  cp_sh "mkdir -p /opt/apps/m3/12
    kubectl -n k3-hist rollout history deploy portal
    kubectl -n k3-hist rollout history deploy portal | awk '/feature x/{print \$1}' > /opt/apps/m3/12/revision.txt
    kubectl -n k3-hist rollout undo deploy portal --to-revision=2
    kubectl -n k3-hist patch deploy portal -p '{\"spec\":{\"revisionHistoryLimit\":2}}'
    kubectl -n k3-hist rollout status deploy portal --timeout=120s"
}

# ---- 13. Two overlays from one base (7) ------------------------------------------------------------------------------
setup_m13() {
  ns_new k3-dev k3-prod
  put_file /opt/apps/m3/13/base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
configMapGenerator:
- name: search-config
  literals:
  - LOG=info
EOF
  put_file /opt/apps/m3/13/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search
spec:
  replicas: 1
  selector:
    matchLabels: {app: search}
  template:
    metadata:
      labels: {app: search}
    spec:
      containers:
      - name: search
        image: busybox:1.36
        command: ["sh", "-c", "echo log=$LOG; sleep 1d"]
        envFrom:
        - configMapRef: {name: search-config}
EOF
}
score_m13() {
  check_cp "k3-dev runs search with LOG=debug and 1 replica" \
    "kubectl -n k3-dev get deploy search -o jsonpath='{.status.readyReplicas}' | grep -qx 1 && kubectl -n k3-dev logs deploy/search | grep -qx log=debug"
  check_cp "k3-prod runs search with LOG=warn, 3 replicas, and a 128Mi memory limit" \
    "kubectl -n k3-prod get deploy search -o jsonpath='{.status.readyReplicas} {.spec.template.spec.containers[0].resources.limits.memory}' | grep -qx '3 128Mi' && kubectl -n k3-prod logs deploy/search | grep -qx log=warn"
  check_cp "the overlays live in /opt/apps/m3/13/overlays/dev and prod, and the base is unchanged" \
    "test -f /opt/apps/m3/13/overlays/dev/kustomization.yaml && test -f /opt/apps/m3/13/overlays/prod/kustomization.yaml && grep -q 'LOG=info' /opt/apps/m3/13/base/kustomization.yaml"
}
solve_m13() {
  put_file /opt/apps/m3/13/overlays/dev/kustomization.yaml <<'EOF'
resources:
- ../../base
namespace: k3-dev
configMapGenerator:
- name: search-config
  behavior: merge
  literals:
  - LOG=debug
EOF
  put_file /opt/apps/m3/13/overlays/prod/kustomization.yaml <<'EOF'
resources:
- ../../base
namespace: k3-prod
replicas:
- name: search
  count: 3
configMapGenerator:
- name: search-config
  behavior: merge
  literals:
  - LOG=warn
patches:
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: search
    spec:
      template:
        spec:
          containers:
          - name: search
            resources:
              limits:
                memory: 128Mi
EOF
  cp_sh 'kubectl apply -k /opt/apps/m3/13/overlays/dev && kubectl apply -k /opt/apps/m3/13/overlays/prod
    kubectl -n k3-dev rollout status deploy search --timeout=120s; kubectl -n k3-prod rollout status deploy search --timeout=120s'
}

# ---- 14. A Job that cleans up after itself (5) ---------------------------------------------------------------------------
setup_m14() { ns_new k3-jobs; }
score_m14() {
  check_json "Job thumbnails: 5 completions, 5 at a time, removed 120s after it finishes" "kubectl -n k3-jobs get job thumbnails -o json" \
    's=p["spec"]; s["completions"]==5 and s["parallelism"]==5 and s["ttlSecondsAfterFinished"]==120'
  check_json "its pods carry the index as JOB_COMPLETION_INDEX: completion mode Indexed" "kubectl -n k3-jobs get job thumbnails -o json" \
    'p["spec"]["completionMode"]=="Indexed"'
  check_cp "it completed, and pod 3 logged 'thumbnail 3 done'" \
    "kubectl -n k3-jobs wait job thumbnails --for=condition=Complete --timeout=10s && kubectl -n k3-jobs logs -l batch.kubernetes.io/job-completion-index=3 | grep -qx 'thumbnail 3 done'"
}
solve_m14() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: batch/v1
kind: Job
metadata: {name: thumbnails, namespace: k3-jobs}
spec:
  completions: 5
  parallelism: 5
  completionMode: Indexed
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: thumb
        image: busybox:1.36
        command: [sh, -c, 'echo thumbnail \$JOB_COMPLETION_INDEX done']
EOF
    kubectl -n k3-jobs wait job thumbnails --for=condition=Complete --timeout=90s"
}

# ---- 15. An Ingress with a default backend (5) ---------------------------------------------------------------------------
setup_m15() {
  ns_new k3-edge
  local n
  for n in shop sorry; do
    cp_sh "kubectl -n k3-edge create deploy $n --image=busybox:1.36 -- sh -c 'mkdir -p /www/shop && echo $n > /www/index.html && echo $n > /www/shop/index.html && exec httpd -f -p 8080 -h /www' >/dev/null
      kubectl -n k3-edge expose deploy $n --port=80 --target-port=8080 >/dev/null"
  done
}
E15="curl -s -m 3 -H 'Host: shop.k3.local' http://$W1IP:30080"
score_m15() {
  check_cp "Ingress edge sends shop.k3.local/shop/ to Service shop" "for i in \$(seq 1 15); do $E15/shop/ | grep -qx shop && exit 0; sleep 2; done; exit 1"
  check_cp "its default backend is Service sorry" "kubectl -n k3-edge get ingress edge -o jsonpath='{.spec.defaultBackend.service.name}' | grep -qx sorry"
  check_cp "any other path of shop.k3.local gets sorry" "$E15/ | grep -qx sorry && $E15/checkout/ | grep -q ."
}
solve_m15() {
  cp_sh "kubectl -n k3-edge create ingress edge --class=nginx --default-backend=sorry:80 --rule='shop.k3.local/shop*=shop:80'"
}

# ---- 16. Port 80 without root (6) --------------------------------------------------------------------------------------------
setup_m16() { ns_new k3-cap; }
score_m16() {
  check_cp "pod web80 runs as uid 101 and answers on port 80" \
    "kubectl -n k3-cap wait pod web80 --for=condition=Ready --timeout=10s && kubectl -n k3-cap exec web80 -- id -u | grep -qx 101 && kubectl -n k3-cap exec web80 -- wget -qO- localhost:80 | grep -qx web80"
  check_json "it drops all capabilities and adds back only NET_BIND_SERVICE" "kubectl -n k3-cap get pod web80 -o json" \
    'c=p["spec"]["containers"][0]["securityContext"]["capabilities"]; c["drop"]==["ALL"] and c["add"]==["NET_BIND_SERVICE"]'
  check_json "no privilege escalation, a read-only root file system" "kubectl -n k3-cap get pod web80 -o json" \
    's=p["spec"]["containers"][0]["securityContext"]; s.get("allowPrivilegeEscalation") is False and s.get("readOnlyRootFilesystem") is True'
}
solve_m16() {
  cp_sh "kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata: {name: web80, namespace: k3-cap}
spec:
  securityContext: {runAsUser: 101, runAsGroup: 101}
  containers:
  - name: web
    image: busybox:1.36
    command: [sh, -c, 'mkdir -p /tmp/www && echo web80 > /tmp/www/index.html && exec httpd -f -p 80 -h /tmp/www']
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: {drop: [ALL], add: [NET_BIND_SERVICE]}
    volumeMounts: [{name: tmp, mountPath: /tmp}]
  volumes:
  - name: tmp
    emptyDir: {}
EOF
    kubectl -n k3-cap wait pod web80 --for=condition=Ready --timeout=60s"
}
