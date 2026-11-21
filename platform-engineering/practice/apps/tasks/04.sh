# Domain 04, application environment, configuration and security.
# Functions for task.sh: setup_4_N, check_4_N, solve_4_N.

# ---- Task 1: a ConfigMap from a file and a literal ------------------------------------------
setup_4_1() {
  ns_fresh config
  put_file /opt/apps/4.1/app.properties <<'EOF'
shop.currency=EUR
shop.page-size=20
shop.cache=on
EOF
  cp_sh 'cat /opt/apps/4.1/app.properties'
}
check_4_1() {
  check_json "ConfigMap app-config has the keys app.properties and LOG_LEVEL=debug" "kubectl -n config get cm app-config -o json" \
    'd=p["data"]; "shop.currency=EUR" in d.get("app.properties","") and d.get("LOG_LEVEL")=="debug"'
  check_cp "pod app has LOG_LEVEL=debug in its environment" "kubectl -n config exec app -- printenv LOG_LEVEL | grep -qx debug"
  check_cp "pod app reads /etc/app/app.properties" "kubectl -n config exec app -- cat /etc/app/app.properties | grep -q shop.page-size=20"
}
solve_4_1() {
  put_file /opt/apps/4.1/pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: config
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "1d"]
    env:
    - name: LOG_LEVEL
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: LOG_LEVEL
    volumeMounts:
    - name: config
      mountPath: /etc/app
  volumes:
  - name: config
    configMap:
      name: app-config
EOF
  shown <<'EOF'
k -n config create cm app-config --from-file=/opt/apps/4.1/app.properties --from-literal=LOG_LEVEL=debug
k apply -f /opt/apps/4.1/pod.yaml
k -n config wait pod app --for=condition=Ready
k -n config exec app -- printenv LOG_LEVEL
k -n config exec app -- ls /etc/app
EOF
}

# ---- Task 2: a Secret as an environment variable and as a file ----------------------------------
setup_4_2() { ns_fresh secrets; }
check_4_2() {
  check_json "Secret db-credentials holds user=admin and password=S3cr3t-pw" "kubectl -n secrets get secret db-credentials -o json" \
    'import base64; d=p["data"]; base64.b64decode(d["user"])==b"admin" and base64.b64decode(d["password"])==b"S3cr3t-pw"'
  check_cp "pod db-client has DB_USER=admin from the Secret" "kubectl -n secrets get pod db-client -o jsonpath='{.spec.containers[0].env[?(@.name==\"DB_USER\")].valueFrom.secretKeyRef.name}' | grep -qx db-credentials && kubectl -n secrets exec db-client -- printenv DB_USER | grep -qx admin"
  check_cp "the password is a file /etc/db/password, mode 400" "kubectl -n secrets exec db-client -- stat -L -c %a /etc/db/password | grep -qx 400 && kubectl -n secrets exec db-client -- cat /etc/db/password | grep -qx S3cr3t-pw"
  check_cp "the password is not in the environment" "! kubectl -n secrets exec db-client -- env | grep -q S3cr3t-pw"
}
solve_4_2() {
  put_file /opt/apps/4.2/pod.yaml <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: db-client
  namespace: secrets
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "1d"]
    env:
    - name: DB_USER
      valueFrom:
        secretKeyRef:
          name: db-credentials
          key: user
    volumeMounts:
    - name: creds
      mountPath: /etc/db
      readOnly: true
  volumes:
  - name: creds
    secret:
      secretName: db-credentials
      defaultMode: 0400
      items:
      - key: password
        path: password
EOF
  shown <<'EOF'
k -n secrets create secret generic db-credentials --from-literal=user=admin --from-literal=password=S3cr3t-pw
k apply -f /opt/apps/4.2/pod.yaml
k -n secrets wait pod db-client --for=condition=Ready
k -n secrets exec db-client -- printenv DB_USER
k -n secrets exec db-client -- ls -lL /etc/db
EOF
}

# ---- Task 3: new configuration in an immutable ConfigMap --------------------------------------------
setup_4_3() {
  ns_fresh config-roll
  cp_sh "kubectl -n config-roll create cm web-config --from-literal=COLOR=red >/dev/null
    kubectl -n config-roll create deploy web --image=busybox:1.36 --replicas=2 -- sh -c 'while true; do echo color=\$COLOR; sleep 5; done' >/dev/null
    kubectl -n config-roll set env deploy/web --from=configmap/web-config >/dev/null
    kubectl -n config-roll rollout status deploy web --timeout=120s >/dev/null
    kubectl -n config-roll get cm,deploy"
}
check_4_3() {
  check_json "ConfigMap web-config-v2 holds COLOR=green and is immutable" "kubectl -n config-roll get cm web-config-v2 -o json" \
    'p["data"]=={"COLOR":"green"} and p.get("immutable") is True'
  check_cp "Deployment web reads COLOR from web-config-v2" \
    "kubectl -n config-roll get deploy web -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name==\"COLOR\")].valueFrom.configMapKeyRef.name}' | grep -qx web-config-v2"
  check_cp "every pod of web logs color=green" \
    "kubectl -n config-roll rollout status deploy web --timeout=90s && for i in \$(seq 1 30); do n=\$(kubectl -n config-roll logs -l app=web --tail=1 2>/dev/null | grep -c color=green); [ \"\$n\" = 2 ] && [ \$(kubectl -n config-roll get pods -l app=web --no-headers | wc -l) = 2 ] && exit 0; sleep 2; done; exit 1"
  check_cp "web-config still holds COLOR=red" "kubectl -n config-roll get cm web-config -o jsonpath='{.data.COLOR}' | grep -qx red"
}
solve_4_3() {
  shown <<'EOF'
k -n config-roll create cm web-config-v2 --from-literal=COLOR=green $do > /opt/apps/4.3-cm.yaml
echo 'immutable: true' >> /opt/apps/4.3-cm.yaml
k apply -f /opt/apps/4.3-cm.yaml
k -n config-roll set env deploy/web --keys=COLOR --from=configmap/web-config-v2
k -n config-roll rollout status deploy web
EOF
  settled config-roll web 2
  shown <<'EOF'
k -n config-roll logs -l app=web --tail=1
k -n config-roll patch cm web-config-v2 -p '{"data":{"COLOR":"blue"}}'
EOF
}

# ---- Task 4: a Deployment that a quota keeps from starting --------------------------------------------
setup_4_4() {
  ns_fresh quota-team
  cp_sh "kubectl -n quota-team create quota compute --hard=requests.cpu=500m,requests.memory=512Mi,limits.cpu=1,limits.memory=1Gi >/dev/null
    kubectl -n quota-team create deploy worker --image=busybox:1.36 --replicas=3 -- sleep 1d >/dev/null
    sleep 3; kubectl -n quota-team get deploy worker"
}
check_4_4() {
  check_json "worker's container requests 100m CPU and 64Mi, limited to 200m and 128Mi" "kubectl -n quota-team get deploy worker -o json" \
    'r=p["spec"]["template"]["spec"]["containers"][0]["resources"]; r=={"requests":{"cpu":"100m","memory":"64Mi"},"limits":{"cpu":"200m","memory":"128Mi"}}'
  check_cp "all 3 replicas are ready" "kubectl -n quota-team rollout status deploy worker --timeout=90s && kubectl -n quota-team get deploy worker -o jsonpath='{.status.readyReplicas}' | grep -qx 3"
  check_cp "the quota is unchanged" "kubectl -n quota-team get quota compute -o jsonpath='{.spec.hard.requests\.cpu}' | grep -qx 500m"
}
solve_4_4() {
  shown <<'EOF'
k -n quota-team get deploy worker
k -n quota-team events --types=Warning | tail -1
k -n quota-team describe quota compute
k -n quota-team set resources deploy worker --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi
k -n quota-team rollout status deploy worker
k -n quota-team describe quota compute | tail -5
EOF
}

# ---- Task 5: defaults for every container with a LimitRange ---------------------------------------------
setup_4_5() { ns_fresh limits; }
check_4_5() {
  check_json "LimitRange container-defaults: default 200m/128Mi, default request 50m/64Mi, max memory 256Mi" "kubectl -n limits get limitrange container-defaults -o json" \
    'l=[x for x in p["spec"]["limits"] if x["type"]=="Container"][0]; l["default"]=={"cpu":"200m","memory":"128Mi"} and l["defaultRequest"]=={"cpu":"50m","memory":"64Mi"} and l["max"]["memory"]=="256Mi"'
  check_json "pod plain got the defaults although its spec names none" "kubectl -n limits get pod plain -o json" \
    'r=p["spec"]["containers"][0]["resources"]; r=={"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"50m","memory":"64Mi"}}'
  check_cp "a pod that asks for 512Mi is refused" "! kubectl -n limits run big --image=busybox:1.36 --dry-run=server --overrides='{\"spec\":{\"containers\":[{\"name\":\"big\",\"image\":\"busybox:1.36\",\"resources\":{\"limits\":{\"memory\":\"512Mi\"}}}]}}' -- sleep 1"
}
solve_4_5() {
  put_file /opt/apps/4.5/limitrange.yaml <<'EOF'
apiVersion: v1
kind: LimitRange
metadata:
  name: container-defaults
  namespace: limits
spec:
  limits:
  - type: Container
    default:
      cpu: 200m
      memory: 128Mi
    defaultRequest:
      cpu: 50m
      memory: 64Mi
    max:
      memory: 256Mi
EOF
  shown <<'EOF'
k apply -f /opt/apps/4.5/limitrange.yaml
k -n limits run plain --image=busybox:1.36 -- sleep 1d
k -n limits get pod plain -o jsonpath='{.spec.containers[0].resources}{"\n"}'
k -n limits describe limitrange container-defaults
EOF
}

# ---- Task 6: a ResourceQuota for a team ---------------------------------------------------------------------
setup_4_6() {
  ns_fresh team-a
  cp_sh 'rm -rf /opt/apps/4.6; mkdir -p /opt/apps/4.6
    kubectl -n team-a create deploy filler --image=busybox:1.36 --replicas=2 -- sleep 1d >/dev/null
    kubectl -n team-a set resources deploy filler --requests=cpu=50m,memory=32Mi --limits=cpu=100m,memory=64Mi >/dev/null
    kubectl -n team-a rollout status deploy filler --timeout=120s'
  settled team-a filler 2
}
check_4_6() {
  check_json "ResourceQuota team-a-quota: 5 pods, 1 CPU and 1Gi requested, 2 CPU and 2Gi limits, 4 Services" "kubectl -n team-a get quota team-a-quota -o json" \
    'h=p["spec"]["hard"]; h=={"pods":"5","requests.cpu":"1","requests.memory":"1Gi","limits.cpu":"2","limits.memory":"2Gi","services":"4"}'
  check_cp "Deployment filler asks for 6 replicas and runs 5" \
    "for i in \$(seq 1 30); do kubectl -n team-a get deploy filler -o jsonpath='{.spec.replicas} {.status.readyReplicas}' | grep -qx '6 5' && exit 0; sleep 2; done; exit 1"
  check_cp "/opt/apps/4.6/reason.txt holds the quota's refusal" "grep -q 'exceeded quota: team-a-quota' /opt/apps/4.6/reason.txt"
}
solve_4_6() {
  shown <<'EOF'
k -n team-a create quota team-a-quota --hard=pods=5,requests.cpu=1,requests.memory=1Gi,limits.cpu=2,limits.memory=2Gi,services=4
k -n team-a scale deploy filler --replicas=6
k -n team-a get deploy filler
k -n team-a events --types=Warning | grep 'exceeded quota' | tail -1 > /opt/apps/4.6/reason.txt
cat /opt/apps/4.6/reason.txt
k -n team-a describe quota team-a-quota
EOF
}

# ---- Task 7: ServiceAccounts and their tokens -------------------------------------------------------------
setup_4_7() {
  ns_fresh sa-apps
  cp_sh 'rm -rf /opt/apps/4.7; mkdir -p /opt/apps/4.7; kubectl config delete-user ckad-reporter >/dev/null 2>&1
    kubectl -n sa-apps create deploy reporter --image=busybox:1.36 -- sleep 1d >/dev/null
    kubectl -n sa-apps create deploy static-site --image=nginx:1.27-alpine >/dev/null
    kubectl -n sa-apps rollout status deploy reporter --timeout=120s >/dev/null
    kubectl -n sa-apps rollout status deploy static-site --timeout=120s >/dev/null
    kubectl -n sa-apps get deploy,sa'
}
check_4_7() {
  check_cp "Deployment reporter runs as ServiceAccount reporter" \
    "kubectl -n sa-apps get deploy reporter -o jsonpath='{.spec.template.spec.serviceAccountName}' | grep -qx reporter && kubectl -n sa-apps rollout status deploy reporter --timeout=60s"
  check_cp "the reporter pod's token names system:serviceaccount:sa-apps:reporter" \
    "kubectl -n sa-apps exec deploy/reporter -- cat /var/run/secrets/kubernetes.io/serviceaccount/token | cut -d. -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | grep -q 'system:serviceaccount:sa-apps:reporter'"
  check_cp "static-site's pods mount no token" \
    "kubectl -n sa-apps rollout status deploy static-site --timeout=60s && ! kubectl -n sa-apps exec deploy/static-site -- ls /var/run/secrets/kubernetes.io/serviceaccount/token"
  # A TokenReview asks the API server whose token this is.
  check_cp "/opt/apps/4.7/token.txt authenticates as reporter" \
    "printf '{\"apiVersion\":\"authentication.k8s.io/v1\",\"kind\":\"TokenReview\",\"spec\":{\"token\":\"%s\"}}' \$(cat /opt/apps/4.7/token.txt) | kubectl create -f - -o jsonpath='{.status.user.username}' | grep -qx system:serviceaccount:sa-apps:reporter"
  check_cp "the kubeconfig has a user ckad-reporter with that token" \
    "kubectl --user=ckad-reporter auth whoami -o jsonpath='{.status.userInfo.username}' | grep -qx system:serviceaccount:sa-apps:reporter"
}
solve_4_7() {
  shown <<'EOF'
k -n sa-apps create sa reporter
k -n sa-apps set serviceaccount deploy reporter reporter
k -n sa-apps patch deploy static-site -p '{"spec":{"template":{"spec":{"automountServiceAccountToken":false}}}}'
k -n sa-apps create token reporter --duration=2h > /opt/apps/4.7/token.txt
k config set-credentials ckad-reporter --token=$(cat /opt/apps/4.7/token.txt)
k --user=ckad-reporter auth whoami
k --user=ckad-reporter -n sa-apps get pods
k -n sa-apps rollout status deploy reporter
k -n sa-apps rollout status deploy static-site
EOF
  settled sa-apps static-site 1
  shown <<'EOF'
k -n sa-apps exec deploy/static-site -- ls /var/run/secrets/kubernetes.io/serviceaccount
EOF
}

# ---- Task 8: a Role for a CI pipeline -------------------------------------------------------------------------
setup_4_8() { ns_fresh ci; }
SA_CI=system:serviceaccount:ci:deployer
check_4_8() {
  check_cp "deployer may create, update and patch deployments in ci" \
    "for v in create update patch get list watch; do kubectl auth can-i \$v deployments -n ci --as=$SA_CI | grep -qx yes || exit 1; done"
  check_cp "deployer may get and list pods and read pod logs in ci" \
    "kubectl auth can-i list pods -n ci --as=$SA_CI && kubectl auth can-i get pods/log -n ci --as=$SA_CI"
  check_cp "deployer may not delete deployments or read Secrets" \
    "! kubectl auth can-i delete deployments -n ci --as=$SA_CI && ! kubectl auth can-i get secrets -n ci --as=$SA_CI"
  check_cp "deployer has no rights in default" "! kubectl auth can-i list deployments -n default --as=$SA_CI"
}
solve_4_8() {
  shown <<'EOF'
k -n ci create sa deployer
k -n ci create role deployer --verb=get,list,watch,create,update,patch --resource=deployments
k -n ci get role deployer -o yaml | grep -A12 '^rules'
EOF
  cp_sh "kubectl -n ci patch role deployer --type=json -p='[{\"op\":\"add\",\"path\":\"/rules/-\",\"value\":{\"apiGroups\":[\"\"],\"resources\":[\"pods\",\"pods/log\"],\"verbs\":[\"get\",\"list\"]}}]' >/dev/null"
  shown <<'EOF'
k -n ci create rolebinding deployer --role=deployer --serviceaccount=ci:deployer
k auth can-i patch deployments -n ci --as=system:serviceaccount:ci:deployer
k auth can-i get pods/log -n ci --as=system:serviceaccount:ci:deployer
k auth can-i delete deployments -n ci --as=system:serviceaccount:ci:deployer
EOF
}

# ---- Task 9: the logs say 403 -----------------------------------------------------------------------------------
setup_4_9() {
  ns_fresh observer shop-front
  cp_sh "kubectl -n shop-front create deploy cart --image=busybox:1.36 --replicas=2 -- sleep 1d >/dev/null
    kubectl -n observer create sa watcher >/dev/null
    kubectl apply -f - >/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: watcher
  namespace: observer
spec:
  serviceAccountName: watcher
  containers:
  - name: watcher
    image: busybox:1.36
    command:
    - sh
    - -c
    - |
      T=/var/run/secrets/kubernetes.io/serviceaccount/token
      while true; do
        if wget -qO /tmp/pods --no-check-certificate --header \"Authorization: Bearer \$(cat \$T)\" https://kubernetes.default.svc/api/v1/namespaces/shop-front/pods 2>/tmp/err; then
          echo \"\$(date +%T) listed \$(grep -o '\"phase\": *\"Running\"' /tmp/pods | wc -l) running pods in shop-front\"
        else
          echo \"\$(date +%T) \$(cat /tmp/err)\"
        fi
        sleep 5
      done
EOF
    kubectl -n observer wait pod watcher --for=condition=Ready --timeout=90s >/dev/null; sleep 6
    kubectl -n observer logs watcher --tail=1"
}
check_4_9() {
  check_cp "watcher may list pods in shop-front" "kubectl auth can-i list pods -n shop-front --as=system:serviceaccount:observer:watcher"
  check_cp "watcher may not list pods in other namespaces, or delete them" \
    "! kubectl auth can-i list pods -n default --as=system:serviceaccount:observer:watcher && ! kubectl auth can-i list pods -A --as=system:serviceaccount:observer:watcher && ! kubectl auth can-i delete pods -n shop-front --as=system:serviceaccount:observer:watcher"
  check_cp "the watcher's log shows 2 running pods" "for i in \$(seq 1 10); do kubectl -n observer logs watcher --tail=1 | grep -q 'listed 2 running pods' && exit 0; sleep 2; done; exit 1"
}
solve_4_9() {
  shown <<'EOF'
k -n observer logs watcher --tail=2
k -n shop-front create role pod-reader --verb=get,list --resource=pods
k -n shop-front create rolebinding watcher-reads-pods --role=pod-reader --serviceaccount=observer:watcher
sleep 6
k -n observer logs watcher --tail=1
EOF
}

# ---- Task 10: a security context, field by field -----------------------------------------------------------
setup_4_10() {
  ns_fresh secure
  cp_sh "kubectl -n secure create deploy api --image=busybox:1.36 -- sh -c 'while true; do date > /tmp/heartbeat; sleep 5; done' >/dev/null
    kubectl -n secure rollout status deploy api --timeout=120s >/dev/null
    kubectl -n secure exec deploy/api -- id"
}
check_4_10() {
  check_cp "the process runs as uid 1000, gid 3000, with group 2000" \
    "kubectl -n secure rollout status deploy api --timeout=90s && kubectl -n secure exec deploy/api -- id | grep -q 'uid=1000 gid=3000 groups=2000'"
  check_json "no privilege escalation, every capability dropped, root file system read-only" "kubectl -n secure get deploy api -o json" \
    's=p["spec"]["template"]["spec"]["containers"][0]["securityContext"]; s.get("allowPrivilegeEscalation") is False and s["capabilities"]["drop"]==["ALL"] and s.get("readOnlyRootFilesystem") is True'
  check_cp "the app still writes /tmp/heartbeat, and nothing else is writable" \
    "kubectl -n secure exec deploy/api -- sh -c 'sleep 6; test -s /tmp/heartbeat && ! touch /etc/x 2>/dev/null && ! touch /x 2>/dev/null'"
}
solve_4_10() {
  put_file /opt/apps/4.10/patch.yaml <<'EOF'
spec:
  template:
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 3000
        fsGroup: 2000
      containers:
      - name: busybox
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
        volumeMounts:
        - name: tmp
          mountPath: /tmp
      volumes:
      - name: tmp
        emptyDir: {}
EOF
  shown <<'EOF'
k -n secure patch deploy api --patch-file /opt/apps/4.10/patch.yaml
k -n secure rollout status deploy api
EOF
  settled secure api 1
  shown <<'EOF'
k -n secure exec deploy/api -- id
k -n secure exec deploy/api -- touch /etc/x
k -n secure exec deploy/api -- ls -ln /tmp
EOF
}

# ---- Task 11: use a CustomResourceDefinition --------------------------------------------------------------------
setup_4_11() {
  cp_sh 'kubectl delete crd backups.ckad.io --ignore-not-found >/dev/null; rm -rf /opt/apps/4.11; mkdir -p /opt/apps/4.11'
  ns_fresh crd-demo crd-other
  cp_sh "kubectl apply -f - >/dev/null" <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backups.ckad.io
spec:
  group: ckad.io
  scope: Namespaced
  names:
    plural: backups
    singular: backup
    kind: Backup
    shortNames: [bk]
  versions:
  - name: v1
    served: true
    storage: true
    additionalPrinterColumns:
    - {name: Schedule, type: string, jsonPath: .spec.schedule}
    - {name: Target, type: string, jsonPath: .spec.target}
    - {name: Keep, type: integer, jsonPath: .spec.retentionDays}
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            required: [schedule, target]
            properties:
              schedule:
                type: string
                description: When the backup runs, in cron syntax.
              target:
                type: string
                description: The database the backup copies.
              retentionDays:
                type: integer
                minimum: 1
                maximum: 30
                description: How many days a backup is kept.
EOF
  cp_sh "kubectl wait crd backups.ckad.io --for=condition=Established --timeout=60s >/dev/null
    kubectl apply -f - >/dev/null <<'EOF'
apiVersion: ckad.io/v1
kind: Backup
metadata: {name: weekly, namespace: crd-other}
spec: {schedule: '0 3 * * 0', target: orders-db, retentionDays: 30}
EOF
    kubectl get crd | grep ckad"
}
check_4_11() {
  check_json "Backup nightly in crd-demo: 0 2 * * *, target postgres, kept 7 days" "kubectl -n crd-demo get backup nightly -o json" \
    'p["spec"]=={"schedule":"0 2 * * *","target":"postgres","retentionDays":7}'
  check_cp "/opt/apps/4.11/backups.txt lists the Backups of every namespace" \
    "grep -q weekly /opt/apps/4.11/backups.txt && grep -q nightly /opt/apps/4.11/backups.txt"
  check_cp "/opt/apps/4.11/max-retention.txt holds the largest retentionDays allowed" "grep -qx 30 /opt/apps/4.11/max-retention.txt"
}
solve_4_11() {
  put_file /opt/apps/4.11/nightly.yaml <<'EOF'
apiVersion: ckad.io/v1
kind: Backup
metadata:
  name: nightly
  namespace: crd-demo
spec:
  schedule: "0 2 * * *"
  target: postgres
  retentionDays: 7
EOF
  shown <<'EOF'
k api-resources --api-group=ckad.io
k explain backup.spec
k get crd backups.ckad.io -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.retentionDays}{"\n"}'
echo 30 > /opt/apps/4.11/max-retention.txt
k apply -f /opt/apps/4.11/nightly.yaml
k get backups -A > /opt/apps/4.11/backups.txt
cat /opt/apps/4.11/backups.txt
EOF
}

# ---- Task 12: a namespace that enforces the restricted standard ----------------------------------------------------
setup_4_12() {
  ns_fresh restricted-apps
  cp_sh "kubectl label ns restricted-apps pod-security.kubernetes.io/enforce=restricted --overwrite >/dev/null
    kubectl -n restricted-apps create deploy web --image=busybox:1.36 --port=8080 -- sh -c 'mkdir -p /tmp/www && echo hello > /tmp/www/index.html && exec httpd -f -p 8080 -h /tmp/www' >/dev/null
    sleep 3; kubectl -n restricted-apps get deploy web"
}
check_4_12() {
  check_cp "Deployment web has a ready pod" "kubectl -n restricted-apps rollout status deploy web --timeout=90s && kubectl -n restricted-apps get deploy web -o jsonpath='{.status.readyReplicas}' | grep -qx 1"
  check_cp "the namespace still enforces restricted" "kubectl get ns restricted-apps -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' | grep -qx restricted"
  check_cp "the pod answers on port 8080" "kubectl -n restricted-apps exec deploy/web -- wget -qO- http://localhost:8080 | grep -qx hello"
}
solve_4_12() {
  put_file /opt/apps/4.12/patch.yaml <<'EOF'
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: busybox
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
EOF
  shown <<'EOF'
k -n restricted-apps get deploy web
k -n restricted-apps describe rs -l app=web | grep FailedCreate | tail -1
k -n restricted-apps patch deploy web --patch-file /opt/apps/4.12/patch.yaml
k -n restricted-apps rollout status deploy web
k -n restricted-apps exec deploy/web -- wget -qO- http://localhost:8080
EOF
}
