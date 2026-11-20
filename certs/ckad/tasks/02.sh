# Domain 02, application deployment. Functions for task.sh: setup_2_N, check_2_N, solve_2_N.

CHARTS=oci://registry.ckad:5000/charts

# Build the chart "webapp" at a version and push it to the local registry: push_chart 0.1.0 1.27-alpine
# It is "helm create" with nginx as the image, so every version runs a real web server.
push_chart() {
  cp_sh "set -e; d=\$(mktemp -d); cd \$d; helm create webapp >/dev/null
    sed -i 's/^version: .*/version: $1/; s/^appVersion: .*/appVersion: \"$2\"/' webapp/Chart.yaml
    sed -i 's|repository: nginx|repository: docker.io/library/nginx|' webapp/values.yaml
    helm package webapp >/dev/null && helm push webapp-$1.tgz $CHARTS --plain-http >/dev/null 2>&1; rm -rf \$d"
}
charts_ready() {
  need_extras || return 1
  cp_sh "helm show chart $CHARTS/webapp --version 0.2.0 --plain-http >/dev/null 2>&1" || { push_chart 0.1.0 1.27-alpine; push_chart 0.2.0 1.28-alpine; }
}

# A small web server that answers with one word, for the blue-green and canary tasks:
# echo_deploy ns name word replicas labels...
echo_deploy() {
  local ns="$1" name="$2" word="$3" n="$4"; shift 4
  local labels="" l
  for l in "$@"; do labels="$labels        ${l%%=*}: ${l#*=}
"; done
  cp_sh "kubectl apply -f - >/dev/null" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  namespace: $ns
spec:
  replicas: $n
  selector:
    matchLabels:
$(printf '%s' "$labels" | sed 's/^        /      /')
  template:
    metadata:
      labels:
$labels    spec:
      containers:
      - name: web
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www && echo $word > /www/index.html && exec httpd -f -p 8080 -h /www"]
        ports:
        - containerPort: 8080
EOF
}

# ---- Task 1: roll back a broken update --------------------------------------------------
setup_2_1() {
  ns_fresh rollout
  cp_sh 'set -e
    kubectl -n rollout create deploy web --image=nginx:1.27-alpine --replicas=3 >/dev/null
    kubectl -n rollout rollout status deploy web --timeout=120s >/dev/null
    kubectl -n rollout set image deploy/web nginx=nginx:1.28-alpine >/dev/null
    kubectl -n rollout rollout status deploy web --timeout=120s >/dev/null
    kubectl -n rollout set image deploy/web nginx=nginx:1.28-alpien >/dev/null
    sleep 8; kubectl -n rollout get pods'
}
check_2_1() {
  check_cp "Deployment web runs nginx:1.28-alpine again" \
    "kubectl -n rollout get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qx nginx:1.28-alpine"
  check_cp "all 3 replicas are ready and up to date" \
    "kubectl -n rollout rollout status deploy web --timeout=90s && kubectl -n rollout get deploy web -o jsonpath='{.status.updatedReplicas}/{.status.readyReplicas}' | grep -qx 3/3"
  check_json "the strategy is maxSurge 1, maxUnavailable 0" "kubectl -n rollout get deploy web -o json" \
    'r=p["spec"]["strategy"]["rollingUpdate"]; str(r["maxSurge"])=="1" and str(r["maxUnavailable"])=="0"'
  check_cp "the change-cause says 'rollback to 1.28-alpine'" \
    "kubectl -n rollout rollout history deploy web | grep -q 'rollback to 1.28-alpine'"
}
solve_2_1() {
  shown <<'EOF'
k -n rollout get pods
k -n rollout rollout history deploy web
k -n rollout rollout history deploy web --revision=2 | grep Image
k -n rollout rollout undo deploy web --to-revision=2
k -n rollout patch deploy web -p '{"spec":{"strategy":{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0}}}}'
k -n rollout annotate deploy web kubernetes.io/change-cause='rollback to 1.28-alpine'
k -n rollout rollout status deploy web
k -n rollout rollout history deploy web
EOF
}

# ---- Task 2: Recreate instead of a rolling update ------------------------------------------
setup_2_2() {
  ns_fresh strategy
  cp_sh 'kubectl -n strategy create deploy worker --image=busybox:1.36 --replicas=2 -- sleep 1d >/dev/null
    kubectl -n strategy rollout status deploy worker --timeout=120s'
}
check_2_2() {
  check_json "Deployment worker uses the Recreate strategy" "kubectl -n strategy get deploy worker -o json" \
    'p["spec"]["strategy"]=={"type":"Recreate"}'
  check_json "4 replicas, 2 old ReplicaSets kept, a pod counts as available after 5 seconds" "kubectl -n strategy get deploy worker -o json" \
    's=p["spec"]; s["replicas"]==4 and s["revisionHistoryLimit"]==2 and s["minReadySeconds"]==5'
  check_json "the container has the variable VERSION=2" "kubectl -n strategy get deploy worker -o json" \
    '{"name":"VERSION","value":"2"} in p["spec"]["template"]["spec"]["containers"][0].get("env",[])'
  check_cp "4 pods are available" "kubectl -n strategy rollout status deploy worker --timeout=120s && kubectl -n strategy get deploy worker -o jsonpath='{.status.availableReplicas}' | grep -qx 4"
}
solve_2_2() {
  shown <<'EOF'
k -n strategy patch deploy worker -p '{"spec":{"strategy":{"type":"Recreate","rollingUpdate":null},"replicas":4,"revisionHistoryLimit":2,"minReadySeconds":5}}'
k -n strategy set env deploy/worker VERSION=2
k -n strategy get pods
k -n strategy rollout status deploy worker
EOF
}

# ---- Task 3: blue-green -----------------------------------------------------------------------
setup_2_3() {
  ns_fresh bluegreen
  echo_deploy bluegreen shop-blue blue 3 app=shop version=blue
  cp_sh 'kubectl -n bluegreen apply -f - >/dev/null <<EOF
apiVersion: v1
kind: Service
metadata: {name: shop, namespace: bluegreen}
spec:
  selector: {app: shop, version: blue}
  ports: [{port: 80, targetPort: 8080}]
EOF
    kubectl -n bluegreen run client --image=busybox:1.36 -- sleep 1d >/dev/null
    kubectl -n bluegreen rollout status deploy shop-blue --timeout=120s >/dev/null
    kubectl -n bluegreen wait pod client --for=condition=Ready --timeout=120s >/dev/null
    kubectl -n bluegreen get deploy,svc'
}
check_2_3() {
  check_cp "Service shop answers 'green' on every call" \
    "for i in 1 2 3 4 5 6; do kubectl -n bluegreen exec client -- wget -qO- -T 2 http://shop | grep -qx green || exit 1; done"
  check_cp "Deployment shop-green has 3 ready pods labelled version=green" \
    "kubectl -n bluegreen get deploy shop-green -o jsonpath='{.status.readyReplicas} {.spec.template.metadata.labels.version}' | grep -qx '3 green'"
  check_cp "Deployment shop-blue still exists, scaled to 0" \
    "kubectl -n bluegreen get deploy shop-blue -o jsonpath='{.spec.replicas}' | grep -qx 0"
}
solve_2_3() {
  cp_sh "mkdir -p /opt/ckad/2.3"
  cp_sh "kubectl -n bluegreen get deploy shop-blue -o json | python3 -c '
import json,sys
d=json.load(sys.stdin); m=d[\"metadata\"]
d[\"metadata\"]={\"name\":\"shop-green\",\"namespace\":m[\"namespace\"]}
d.pop(\"status\",None)
s=d[\"spec\"]; s[\"selector\"][\"matchLabels\"][\"version\"]=\"green\"; s[\"template\"][\"metadata\"][\"labels\"][\"version\"]=\"green\"
c=s[\"template\"][\"spec\"][\"containers\"][0]; c[\"command\"][2]=c[\"command\"][2].replace(\"echo blue\",\"echo green\")
print(json.dumps(d))' | kubectl create -f - --dry-run=client -o yaml | grep -v -E '^  (creationTimestamp|generation|resourceVersion|uid):|deployment.kubernetes.io/revision' > /opt/ckad/2.3/green.yaml"
  shown <<'EOF'
grep -n -E 'name: shop|version|echo' /opt/ckad/2.3/green.yaml
k apply -f /opt/ckad/2.3/green.yaml
k -n bluegreen rollout status deploy shop-green
k -n bluegreen patch svc shop -p '{"spec":{"selector":{"version":"green"}}}'
k -n bluegreen exec client -- wget -qO- http://shop
k -n bluegreen scale deploy shop-blue --replicas=0
k -n bluegreen get deploy
EOF
}

# ---- Task 4: a canary with a fifth of the traffic ------------------------------------------------
setup_2_4() {
  ns_fresh canary
  echo_deploy canary front-v1 v1 4 app=front track=stable
  cp_sh 'kubectl -n canary expose deploy front-v1 --name=front --port=80 --target-port=8080 --selector=app=front >/dev/null
    kubectl -n canary run client --image=busybox:1.36 -- sleep 1d >/dev/null
    kubectl -n canary rollout status deploy front-v1 --timeout=120s >/dev/null
    kubectl -n canary wait pod client --for=condition=Ready --timeout=120s >/dev/null
    kubectl -n canary get deploy,svc -o wide'
}
check_2_4() {
  check_cp "Deployment front-v2 has 1 ready pod labelled app=front, track=canary" \
    "kubectl -n canary get deploy front-v2 -o jsonpath='{.status.readyReplicas} {.spec.template.metadata.labels.app} {.spec.template.metadata.labels.track}' | grep -qx '1 front canary'"
  check_cp "front-v1 keeps 4 ready pods" "kubectl -n canary get deploy front-v1 -o jsonpath='{.status.readyReplicas}' | grep -qx 4"
  check_cp "Service front sends traffic to all 5 pods" \
    "kubectl -n canary get endpointslice -l kubernetes.io/service-name=front -o jsonpath='{.items[*].endpoints[*].addresses[0]}' | wc -w | grep -qx 5"
  check_cp "40 calls to front get answers from both v1 and v2" \
    "out=\$(for i in \$(seq 1 40); do kubectl -n canary exec client -- wget -qO- -T 2 http://front; done); echo \"\$out\" | grep -qx v1 && echo \"\$out\" | grep -qx v2"
}
solve_2_4() {
  cp_sh "mkdir -p /opt/ckad/2.4 && kubectl -n canary get deploy front-v1 -o json | python3 -c '
import json,sys
d=json.load(sys.stdin); m=d[\"metadata\"]
d[\"metadata\"]={\"name\":\"front-v2\",\"namespace\":m[\"namespace\"]}
d.pop(\"status\",None)
s=d[\"spec\"]; s[\"replicas\"]=1; s[\"selector\"][\"matchLabels\"][\"track\"]=\"canary\"; s[\"template\"][\"metadata\"][\"labels\"][\"track\"]=\"canary\"
c=s[\"template\"][\"spec\"][\"containers\"][0]; c[\"command\"][2]=c[\"command\"][2].replace(\"echo v1\",\"echo v2\")
print(json.dumps(d))' | kubectl create -f - --dry-run=client -o yaml | grep -v -E '^  (creationTimestamp|generation|resourceVersion|uid):|deployment.kubernetes.io/revision' > /opt/ckad/2.4/canary.yaml"
  shown <<'EOF'
k -n canary get svc front -o jsonpath='{.spec.selector}{"\n"}'
grep -n -E 'name: front|replicas|track|echo' /opt/ckad/2.4/canary.yaml
k apply -f /opt/ckad/2.4/canary.yaml
k -n canary rollout status deploy front-v2
k -n canary get pods -l app=front -L track
for i in $(seq 1 20); do k -n canary exec client -- wget -qO- http://front; done | sort | uniq -c
EOF
}

# ---- Task 5: install a Helm chart from a registry ----------------------------------------------------
setup_2_5() {
  charts_ready || return 1
  ns_fresh helm-shop
  cp_sh "helm show chart $CHARTS/webapp --version 0.1.0 --plain-http | head -6"
}
check_2_5() {
  check_cp "release shop in helm-shop is deployed from chart webapp 0.1.0" \
    "helm -n helm-shop list -o json | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin) if x[\"name\"]==\"shop\"]; sys.exit(0 if r and r[0][\"status\"]==\"deployed\" and r[0][\"chart\"]==\"webapp-0.1.0\" else 1)'"
  check_cp "its Deployment has 2 ready replicas" "kubectl -n helm-shop get deploy shop-webapp -o jsonpath='{.status.readyReplicas}' | grep -qx 2"
  check_cp "its Service is a NodePort" "kubectl -n helm-shop get svc shop-webapp -o jsonpath='{.spec.type}' | grep -qx NodePort"
}
solve_2_5() {
  shown <<'EOF'
helm show values oci://registry.ckad:5000/charts/webapp --version 0.1.0 --plain-http 2>/dev/null | grep -E '^replicaCount|^  type:|^  port:'
helm -n helm-shop install shop oci://registry.ckad:5000/charts/webapp --version 0.1.0 --plain-http --set replicaCount=2 --set service.type=NodePort
helm -n helm-shop list
k -n helm-shop rollout status deploy shop-webapp
k -n helm-shop get deploy,svc
EOF
}

# ---- Task 6: roll a release back, then upgrade it ----------------------------------------------------
setup_2_6() {
  charts_ready || return 1
  ns_fresh helm-blog
  cp_sh "helm -n helm-blog install blog $CHARTS/webapp --version 0.1.0 --plain-http --wait --timeout 120s >/dev/null 2>&1
    helm -n helm-blog upgrade blog $CHARTS/webapp --version 0.1.0 --plain-http --set image.tag=1.27-alpne >/dev/null 2>&1
    sleep 5; kubectl -n helm-blog get pods"
}
check_2_6() {
  check_cp "the latest revision of blog is deployed from chart webapp 0.2.0" \
    "helm -n helm-blog history blog -o json | python3 -c 'import json,sys; h=json.load(sys.stdin)[-1]; sys.exit(0 if h[\"status\"]==\"deployed\" and h[\"chart\"]==\"webapp-0.2.0\" else 1)'"
  check_cp "Deployment blog-webapp has 3 ready replicas" "kubectl -n helm-blog rollout status deploy blog-webapp --timeout=90s && kubectl -n helm-blog get deploy blog-webapp -o jsonpath='{.status.readyReplicas}' | grep -qx 3"
  check_cp "no image tag 1.27-alpne is left" "! kubectl -n helm-blog get deploy blog-webapp -o yaml | grep -q 1.27-alpne"
  check_cp "the history shows a rollback to revision 1" "helm -n helm-blog history blog | grep -q 'Rollback to 1'"
}
solve_2_6() {
  shown <<'EOF'
helm -n helm-blog history blog
helm -n helm-blog get values blog --revision 2
helm -n helm-blog rollback blog 1
helm -n helm-blog upgrade blog oci://registry.ckad:5000/charts/webapp --version 0.2.0 --plain-http --reuse-values --set replicaCount=3
k -n helm-blog rollout status deploy blog-webapp
helm -n helm-blog history blog
EOF
}

# ---- Task 7: Helm housekeeping --------------------------------------------------------------------
setup_2_7() {
  charts_ready || return 1
  ns_fresh helm-ops
  put_file /opt/ckad/2.7/values.yaml <<'EOF'
replicaCount: 2
podLabels:
  team: observability
resources:
  requests:
    cpu: 20m
    memory: 32Mi
EOF
  cp_sh "helm -n helm-ops install old-api $CHARTS/webapp --version 0.1.0 --plain-http >/dev/null 2>&1
    helm -n helm-ops install reports $CHARTS/webapp --version 0.1.0 --plain-http >/dev/null 2>&1
    helm -n helm-ops install cache $CHARTS/webapp --version 0.1.0 --plain-http --set image.tag=no-such-tag --wait --timeout 15s >/dev/null 2>&1
    helm -n helm-ops list"
}
check_2_7() {
  check_cp "release old-api is gone" "! helm -n helm-ops status old-api"
  check_cp "no release in helm-ops is in the failed state" "[ -z \"\$(helm -n helm-ops list --failed -q)\" ] && ! helm -n helm-ops status cache"
  check_cp "release metrics-ui is deployed from chart webapp 0.2.0" "helm -n helm-ops list -o json | grep -q '\"name\":\"metrics-ui\".*\"chart\":\"webapp-0.2.0\"'"
  check_json "metrics-ui runs 2 pods labelled team=observability that request 20m CPU" "kubectl -n helm-ops get deploy metrics-ui-webapp -o json" \
    't=p["spec"]["template"]; p["status"].get("readyReplicas")==2 and t["metadata"]["labels"].get("team")=="observability" and t["spec"]["containers"][0]["resources"]["requests"]["cpu"]=="20m"'
  check_cp "release reports still runs" "helm -n helm-ops status reports | grep -q 'STATUS: deployed'"
}
solve_2_7() {
  shown <<'EOF'
helm -n helm-ops list
helm -n helm-ops uninstall old-api
helm -n helm-ops list --failed
helm -n helm-ops uninstall cache
helm -n helm-ops install metrics-ui oci://registry.ckad:5000/charts/webapp --version 0.2.0 --plain-http -f /opt/ckad/2.7/values.yaml
k -n helm-ops rollout status deploy metrics-ui-webapp
helm -n helm-ops list
EOF
}

# ---- Task 8: a Kustomize overlay for production ---------------------------------------------------------
setup_2_8() {
  ns_fresh kust-prod
  cp_sh 'rm -rf /opt/ckad/2.8'
  put_file /opt/ckad/2.8/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: nginx
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
EOF
  put_file /opt/ckad/2.8/base/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  selector:
    app: web
  ports:
  - port: 80
EOF
  put_file /opt/ckad/2.8/base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
- service.yaml
EOF
  cp_sh 'find /opt/ckad/2.8 -type f'
}
check_2_8() {
  check_cp "Deployment prod-web runs in kust-prod with 3 ready replicas" \
    "kubectl -n kust-prod rollout status deploy prod-web --timeout=90s && kubectl -n kust-prod get deploy prod-web -o jsonpath='{.status.readyReplicas}' | grep -qx 3"
  check_cp "it runs nginx:1.28-alpine" "kubectl -n kust-prod get deploy prod-web -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -qx nginx:1.28-alpine"
  check_cp "the Deployment, its pods and Service prod-web carry env=prod" \
    "kubectl -n kust-prod get deploy prod-web -o jsonpath='{.metadata.labels.env}{.spec.template.metadata.labels.env}' | grep -qx prodprod && kubectl -n kust-prod get svc prod-web -o jsonpath='{.metadata.labels.env}' | grep -qx prod"
  check_cp "the overlay lives in /opt/ckad/2.8/overlays/prod and the base is unchanged" \
    "test -f /opt/ckad/2.8/overlays/prod/kustomization.yaml && grep -q 'replicas: 1' /opt/ckad/2.8/base/deployment.yaml && grep -q 'nginx:1.27-alpine' /opt/ckad/2.8/base/deployment.yaml"
}
solve_2_8() {
  put_file /opt/ckad/2.8/overlays/prod/kustomization.yaml <<'EOF'
resources:
- ../../base
namespace: kust-prod
namePrefix: prod-
labels:
- pairs:
    env: prod
  includeTemplates: true
replicas:
- name: web
  count: 3
images:
- name: nginx
  newTag: 1.28-alpine
EOF
  shown <<'EOF'
cd /opt/ckad/2.8/overlays/prod
k kustomize . | grep -E 'name:|namespace:|env:|replicas:|image:'
k apply -k .
k -n kust-prod rollout status deploy prod-web
k -n kust-prod get deploy,svc --show-labels
EOF
}

# ---- Task 9: repair a Kustomize overlay ---------------------------------------------------------------
setup_2_9() {
  ns_fresh kust-staging
  cp_sh 'rm -rf /opt/ckad/2.9'
  put_file /opt/ckad/2.9/base/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: busybox:1.36
        command: ["sh", "-c", "echo mode=$MODE; sleep 1d"]
        envFrom:
        - configMapRef:
            name: api-config
EOF
  put_file /opt/ckad/2.9/base/kustomization.yaml <<'EOF'
resources:
- deployment.yaml
configMapGenerator:
- name: api-config
  literals:
  - MODE=dev
EOF
  put_file /opt/ckad/2.9/overlays/staging/kustomization.yaml <<'EOF'
resources:
- ../../base
namespace: kust-staging
namePrefix: staging-
configMapGenerator:
- name: api-config
  literals:
  - MODE=staging
patches:
- path: limits.yaml
EOF
  put_file /opt/ckad/2.9/overlays/staging/limits.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  template:
    spec:
      containers:
      - name: api
        resources:
          limits:
            cpu: 100m
            memory: 64Mi
EOF
  cp_sh 'cd /opt/ckad/2.9/overlays/staging && kubectl kustomize . 2>&1 | tail -2'
}
check_2_9() {
  check_cp "Deployment staging-api in kust-staging has a limit of 64Mi memory" \
    "kubectl -n kust-staging get deploy staging-api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' | grep -qx 64Mi"
  check_cp "its pod logs mode=staging" \
    "kubectl -n kust-staging rollout status deploy staging-api --timeout=90s && for i in \$(seq 1 10); do kubectl -n kust-staging logs deploy/staging-api 2>/dev/null | grep -qx mode=staging && exit 0; sleep 2; done; exit 1"
  check_cp "/opt/ckad/2.9/staging.yaml holds the rendered overlay" \
    "grep -q 'name: staging-api' /opt/ckad/2.9/staging.yaml && grep -q 'MODE: staging' /opt/ckad/2.9/staging.yaml"
}
solve_2_9() {
  shown <<'EOF'
cd /opt/ckad/2.9/overlays/staging
k kustomize .
sed -i 's/name: api-server/name: api/' limits.yaml
sed -i '/^configMapGenerator:/,/MODE=staging/s/  literals:/  behavior: merge\n  literals:/' kustomization.yaml
cat kustomization.yaml
k kustomize . > /opt/ckad/2.9/staging.yaml
grep -E 'MODE|name: staging|memory' /opt/ckad/2.9/staging.yaml
k apply -k .
k -n kust-staging rollout status deploy staging-api
k -n kust-staging logs deploy/staging-api
EOF
}

# ---- Task 10: three changes, one new revision -------------------------------------------------------------
setup_2_10() {
  ns_fresh paused
  cp_sh 'kubectl -n paused create deploy api --image=nginx:1.27-alpine --replicas=2 >/dev/null
    kubectl -n paused rollout status deploy api --timeout=120s >/dev/null
    kubectl -n paused get rs'
}
check_2_10() {
  check_json "Deployment api: nginx:1.28-alpine, TIER=backend, memory limit 128Mi" "kubectl -n paused get deploy api -o json" \
    'c=p["spec"]["template"]["spec"]["containers"][0]; c["image"]=="nginx:1.28-alpine" and {"name":"TIER","value":"backend"} in c.get("env",[]) and c["resources"]["limits"]["memory"]=="128Mi"'
  check_cp "the three changes made exactly one new ReplicaSet (revision 2)" \
    "[ \$(kubectl -n paused get rs --no-headers | wc -l) = 2 ] && kubectl -n paused get deploy api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' | grep -qx 2"
  check_cp "the rollout is resumed and both pods are ready" \
    "! kubectl -n paused get deploy api -o jsonpath='{.spec.paused}' | grep -q true && kubectl -n paused rollout status deploy api --timeout=90s"
  check_cp "the change-cause of revision 2 is 'nginx 1.28, tier and limit'" \
    "kubectl -n paused rollout history deploy api | grep -q '^2 .*nginx 1.28, tier and limit'"
}
solve_2_10() {
  shown <<'EOF'
k -n paused rollout pause deploy api
k -n paused set image deploy/api nginx=nginx:1.28-alpine
k -n paused set env deploy/api TIER=backend
k -n paused set resources deploy/api --limits=memory=128Mi
k -n paused annotate deploy api kubernetes.io/change-cause='nginx 1.28, tier and limit'
k -n paused get rs
k -n paused rollout resume deploy api
k -n paused rollout status deploy api
k -n paused rollout history deploy api
k -n paused get rs
EOF
}
