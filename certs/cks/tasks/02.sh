# Domain 02, cluster hardening. Functions for task.sh: setup_2_N, check_2_N, solve_2_N.

SA_REPORTER=system:serviceaccount:finance:reporter

# ---- Task 1: trim an over-broad Role -------------------------------------------------
setup_2_1() {
  oncp <<'EOF'
kubectl create ns finance --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n finance get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n finance create sa reporter 2>/dev/null
kubectl -n finance create secret generic report-key --from-literal=key=r3p0rt 2>/dev/null
kubectl -n finance create secret generic db-password --from-literal=password=s3cr3t 2>/dev/null
kubectl -n finance delete role,rolebinding --all >/dev/null
kubectl -n finance create role reporter-role --verb='*' --resource='*'
kubectl -n finance create rolebinding reporter-binding --role=reporter-role --serviceaccount=finance:reporter
EOF
}
can() { k auth can-i "$@" --as="$SA_REPORTER" -n finance; }
cannot() { ! can "$@"; }
check_2_1() {
  check "reporter lists pods" can list pods
  check "reporter watches pods" can watch pods
  check "reporter does not delete pods" cannot delete pods
  check "reporter does not create deployments" cannot create deployments.apps
  check "reporter gets the Secret report-key" can get secret/report-key
  check "reporter does not get the Secret db-password" cannot get secret/db-password
  check "reporter does not list Secrets" cannot list secrets
}
solve_2_1() {
  oncp <<'EOF'
kubectl -n finance create role reporter-role --verb=get,list,watch --resource=pods --dry-run=client -o yaml | kubectl replace -f -
kubectl -n finance create role secret-reader --verb=get --resource=secrets --resource-name=report-key
kubectl -n finance create rolebinding secret-reader --role=secret-reader --serviceaccount=finance:reporter
EOF
}

# ---- Task 2: service account tokens --------------------------------------------------
setup_2_2() {
  oncp <<'EOF'
kubectl create ns payments --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n payments get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n payments create deploy checkout --image=nginx:1.27-alpine 2>/dev/null
kubectl -n payments rollout status deploy checkout --timeout=120s
EOF
}
check_2_2() {
  check_cp "ServiceAccount default in payments has automountServiceAccountToken: false" \
    "kubectl -n payments get sa default -o jsonpath='{.automountServiceAccountToken}' | grep -qx false"
  check_cp "ServiceAccount checkout exists, also without automount" \
    "kubectl -n payments get sa checkout -o jsonpath='{.automountServiceAccountToken}' | grep -qx false"
  check_cp "Deployment checkout runs as ServiceAccount checkout" \
    "kubectl -n payments get deploy checkout -o jsonpath='{.spec.template.spec.serviceAccountName}' | grep -qx checkout"
  check_cp "the running pod has no API token mounted" \
    "kubectl -n payments rollout status deploy checkout --timeout=60s && p=\$(kubectl -n payments get pod -l app=checkout -o name | head -1) && ! kubectl -n payments exec \$p -- ls /var/run/secrets/kubernetes.io/serviceaccount/token"
}
solve_2_2() {
  oncp <<'EOF'
kubectl -n payments patch sa default -p '{"automountServiceAccountToken": false}'
kubectl -n payments create sa checkout 2>/dev/null
kubectl -n payments patch sa checkout -p '{"automountServiceAccountToken": false}'
kubectl -n payments set serviceaccount deploy checkout checkout
kubectl -n payments rollout status deploy checkout --timeout=120s
EOF
}

# ---- Task 3: restrict anonymous access to the API ------------------------------------
setup_2_3() {
  oncp <<'EOF'
kubectl create clusterrolebinding anonymous-view --clusterrole=view --user=system:anonymous 2>/dev/null
IP=$(hostname -I | cut -d' ' -f1)
curl -sk -o /dev/null -w "anonymous list of pods: %{http_code}\n" https://$IP:6443/api/v1/namespaces/default/pods
EOF
}
check_2_3() {
  check_cp "ClusterRoleBinding anonymous-view is gone" "! kubectl get clusterrolebinding anonymous-view"
  check_cp "an anonymous request for pods gets 401" \
    "curl -sk -o /dev/null -w '%{http_code}' https://\$(hostname -I | cut -d' ' -f1):6443/api/v1/namespaces/default/pods | grep -qx 401"
  check_cp "an anonymous request for /livez still gets 200" \
    "curl -sk -o /dev/null -w '%{http_code}' https://\$(hostname -I | cut -d' ' -f1):6443/livez | grep -qx 200"
  check_cp "the API server uses --authentication-config" \
    "grep -q -- '--authentication-config=' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check_cp "the API server pod is Ready" \
    "kubectl -n kube-system wait pod -l component=kube-apiserver --for=condition=Ready --timeout=60s"
}
solve_2_3() {
  oncp <<'EOF'
kubectl delete clusterrolebinding anonymous-view
mkdir -p /etc/kubernetes/auth
cat > /etc/kubernetes/auth/auth-config.yaml <<'YAML'
apiVersion: apiserver.config.k8s.io/v1
kind: AuthenticationConfiguration
anonymous:
  enabled: true
  conditions:
  - path: /livez
  - path: /readyz
  - path: /healthz
YAML
cp /etc/kubernetes/manifests/kube-apiserver.yaml /root/kube-apiserver.yaml.bak
EOF
  set_flag kube-apiserver --authentication-config /etc/kubernetes/auth/auth-config.yaml
  apiserver_mount auth-config /etc/kubernetes/auth
  sleep 5
  wait_api
}

# ---- Task 4: upgrade the cluster with kubeadm ----------------------------------------
setup_2_4() {
  k get nodes
  echo "  the cluster must run v1.37.1 for this task; ./certs/cks/cluster/reset.sh puts it back there"
}
check_2_4() {
  check_cp "cks-cp kubelet reports v1.37.2" "kubectl get node cks-cp -o jsonpath='{.status.nodeInfo.kubeletVersion}' | grep -qx v1.37.2"
  check_cp "cks-w1 kubelet reports v1.37.2" "kubectl get node cks-w1 -o jsonpath='{.status.nodeInfo.kubeletVersion}' | grep -qx v1.37.2"
  check_cp "the API server runs image v1.37.2" \
    "kubectl -n kube-system get pod -l component=kube-apiserver -o jsonpath='{.items[0].spec.containers[0].image}' | grep -q ':v1.37.2\$'"
  check_cp "both nodes are schedulable" "! kubectl get nodes -o jsonpath='{.items[*].spec.unschedulable}' | grep -q true"
  check_w1 "kubeadm, kubelet and kubectl stay on hold on cks-w1" "apt-mark showhold | grep -c -E '^(kubeadm|kubelet|kubectl)\$' | grep -qx 3"
}
solve_2_4() {
  oncp <<'EOF'
set -e
apt-mark unhold kubeadm >/dev/null
apt-get install -y -qq kubeadm=1.37.2-1.1 >/dev/null
apt-mark hold kubeadm >/dev/null
kubeadm upgrade plan v1.37.2 | grep -E 'kube-apiserver|You can now apply' | head -3
kubeadm upgrade apply v1.37.2 -y 2>&1 | tail -2
kubectl drain cks-cp --ignore-daemonsets --delete-emptydir-data
apt-mark unhold kubelet kubectl >/dev/null
apt-get install -y -qq kubelet=1.37.2-1.1 kubectl=1.37.2-1.1 >/dev/null
apt-mark hold kubelet kubectl >/dev/null
systemctl daemon-reload && systemctl restart kubelet
for i in $(seq 1 60); do kubectl uncordon cks-cp 2>/dev/null && break; sleep 2; done
kubectl drain cks-w1 --ignore-daemonsets --delete-emptydir-data --force
EOF
  onw1 <<'EOF'
set -e
apt-mark unhold kubeadm kubelet kubectl >/dev/null
apt-get install -y -qq kubeadm=1.37.2-1.1 >/dev/null
kubeadm upgrade node 2>&1 | tail -1
apt-get install -y -qq kubelet=1.37.2-1.1 kubectl=1.37.2-1.1 >/dev/null
apt-mark hold kubeadm kubelet kubectl >/dev/null
systemctl daemon-reload && systemctl restart kubelet
EOF
  oncp <<'EOF'
kubectl uncordon cks-w1
kubectl wait node --all --for=condition=Ready --timeout=120s
kubectl get nodes
EOF
}

# ---- Task 5: aggregated ClusterRoles -----------------------------------------------------
setup_2_5() {
  oncp <<'EOF'
kubectl create ns monitoring --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n monitoring get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n monitoring create sa prom 2>/dev/null
kubectl delete clusterrole monitoring-endpoints --ignore-not-found >/dev/null
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-reader
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.cks.io/aggregate-to-monitoring: "true"
rules: []
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-pods
  labels:
    rbac.cks.io/aggregate-to-monitoring: "true"
rules:
- apiGroups: [""]
  resources: [pods]
  verbs: [get, list, watch]
- apiGroups: [""]
  resources: [pods/exec]
  verbs: [create]
YAML
kubectl create clusterrolebinding prom --clusterrole=monitoring-reader --serviceaccount=monitoring:prom 2>/dev/null
sleep 2
kubectl get clusterrole monitoring-reader -o jsonpath='{range .rules[*]}  {.resources} {.verbs}{"\n"}{end}'
EOF
}
as_prom() { k auth can-i "$@" --as=system:serviceaccount:monitoring:prom; }
check_2_5() {
  check_cp "ClusterRole monitoring-endpoints carries the aggregation label" \
    "kubectl get clusterrole monitoring-endpoints -o jsonpath='{.metadata.labels.rbac\.cks\.io/aggregate-to-monitoring}' | grep -qx true"
  check "prom lists endpoints in every namespace" as_prom list endpoints -A
  check "prom watches services in every namespace" as_prom watch services -A
  check "prom still lists pods" as_prom list pods -A
  check "prom may no longer exec into pods" bash -c "! orb -m $CKS_CP -u root kubectl auth can-i create pods/exec -A --as=system:serviceaccount:monitoring:prom"
  check_cp "monitoring-reader still aggregates, with no rules of its own written by hand" \
    "kubectl get clusterrole monitoring-reader -o jsonpath='{.aggregationRule.clusterRoleSelectors[0].matchLabels}' | grep -q aggregate-to-monitoring"
}
solve_2_5() {
  oncp <<'EOF'
kubectl apply -f - <<'YAML'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-endpoints
  labels:
    rbac.cks.io/aggregate-to-monitoring: "true"
rules:
- apiGroups: [""]
  resources: [endpoints, services]
  verbs: [get, list, watch]
YAML
kubectl patch clusterrole monitoring-pods --type=json -p='[{"op":"remove","path":"/rules/1"}]'
sleep 2
kubectl get clusterrole monitoring-reader -o jsonpath='{range .rules[*]}{.resources} {.verbs}{"\n"}{end}'
EOF
}

# ---- Task 6: who may read the Secrets? --------------------------------------------------
setup_2_6() {
  oncp <<'EOF'
kubectl create ns apps --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n apps get sa default >/dev/null 2>&1 && break; sleep 1; done
for sa in builder deployer viewer cleaner; do kubectl -n apps create sa $sa 2>/dev/null; done
kubectl -n apps create role builder --verb=get,list,create --resource=configmaps,jobs.batch 2>/dev/null
kubectl -n apps create rolebinding builder --role=builder --serviceaccount=apps:builder 2>/dev/null
kubectl -n apps create role deployer --verb=get,list,create,update,patch --resource=deployments.apps 2>/dev/null
kubectl -n apps create rolebinding deployer --role=deployer --serviceaccount=apps:deployer 2>/dev/null
kubectl -n apps create role viewer --verb=get,list,watch --resource=pods,services 2>/dev/null
kubectl -n apps create rolebinding viewer --role=viewer --serviceaccount=apps:viewer 2>/dev/null
kubectl create clusterrole log-cleanup --verb=get,list,delete --resource=secrets,events 2>/dev/null
kubectl create clusterrolebinding log-cleanup --clusterrole=log-cleanup --serviceaccount=apps:cleaner 2>/dev/null
mkdir -p /root/cks && rm -f /root/cks/secret-reader.txt /root/cks/viewer-perms.txt
EOF
}
check_2_6() {
  check_cp "/root/cks/secret-reader.txt names cleaner" "grep -qx cleaner /root/cks/secret-reader.txt"
  check "cleaner may no longer read Secrets in kube-system" \
    bash -c "! orb -m $CKS_CP -u root kubectl auth can-i get secrets -n kube-system --as=system:serviceaccount:apps:cleaner"
  check_cp "ServiceAccount cleaner still exists" "kubectl -n apps get sa cleaner"
  check "deployer keeps its rights" k auth can-i create deployments.apps -n apps --as=system:serviceaccount:apps:deployer
  check_cp "/root/cks/viewer-perms.txt holds viewer's can-i list" \
    "grep -E '^pods +\[\] +\[\] +\[get list watch\]' /root/cks/viewer-perms.txt && grep -q '^services ' /root/cks/viewer-perms.txt"
}
solve_2_6() {
  oncp <<'EOF'
for sa in builder deployer viewer cleaner; do
  echo "$sa: $(kubectl auth can-i get secrets -n kube-system --as=system:serviceaccount:apps:$sa)"
done
echo cleaner > /root/cks/secret-reader.txt
kubectl get clusterrolebinding -o wide | grep apps/cleaner
kubectl delete clusterrolebinding log-cleanup
kubectl auth can-i --list -n apps --as=system:serviceaccount:apps:viewer > /root/cks/viewer-perms.txt
cat /root/cks/viewer-perms.txt
EOF
}

# ---- Task 7: a bound token for another audience ------------------------------------------
setup_2_7() {
  oncp <<'EOF'
kubectl create ns vault-client --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n vault-client get sa default >/dev/null 2>&1 && break; sleep 1; done
kubectl -n vault-client create sa vault-auth 2>/dev/null
kubectl -n vault-client delete pod client --ignore-not-found --now >/dev/null
mkdir -p /root/cks && rm -f /root/cks/vault-token.txt
EOF
}
# Prints the claims of a JWT read from stdin as JSON.
JWT_CLAIMS='import base64,json,sys; p=sys.stdin.read().strip().split(".")[1]; p+="="*(-len(p)%4); print(json.dumps(json.loads(base64.urlsafe_b64decode(p))))'
check_2_7() {
  check_cp "/root/cks/vault-token.txt is a token for vault-auth with audience vault, valid 2 hours" \
    "python3 -c '$JWT_CLAIMS' < /root/cks/vault-token.txt | python3 -c 'import json,sys; c=json.load(sys.stdin); sys.exit(0 if c[\"aud\"]==[\"vault\"] and c[\"exp\"]-c[\"iat\"]==7200 and c[\"sub\"]==\"system:serviceaccount:vault-client:vault-auth\" else 1)'"
  check_cp "pod client runs as vault-auth without the default token" \
    "kubectl -n vault-client get pod client -o jsonpath='{.spec.serviceAccountName}/{.spec.automountServiceAccountToken}' | grep -qx vault-auth/false && kubectl -n vault-client wait pod client --for=condition=Ready --timeout=60s && ! kubectl -n vault-client exec client -- ls /var/run/secrets/kubernetes.io/serviceaccount/token"
  check_cp "a projected token with audience vault and 3600 seconds sits at /var/run/secrets/vault/token" \
    "kubectl -n vault-client exec client -- cat /var/run/secrets/vault/token | python3 -c '$JWT_CLAIMS' | python3 -c 'import json,sys; c=json.load(sys.stdin); sys.exit(0 if c[\"aud\"]==[\"vault\"] and c[\"exp\"]-c[\"iat\"]==3600 else 1)'"
}
solve_2_7() {
  oncp <<'EOF'
kubectl -n vault-client create token vault-auth --audience=vault --duration=2h > /root/cks/vault-token.txt
kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata: {name: client, namespace: vault-client}
spec:
  serviceAccountName: vault-auth
  automountServiceAccountToken: false
  containers:
  - name: client
    image: busybox:1.36
    command: [sleep, 1d]
    volumeMounts:
    - {name: vault-token, mountPath: /var/run/secrets/vault, readOnly: true}
  volumes:
  - name: vault-token
    projected:
      sources:
      - serviceAccountToken:
          audience: vault
          expirationSeconds: 3600
          path: token
YAML
kubectl -n vault-client wait pod client --for=condition=Ready --timeout=90s
EOF
}

# ---- Task 8: clean up legacy token Secrets -----------------------------------------------
setup_2_8() {
  oncp <<'EOF'
kubectl create ns legacy --dry-run=client -o yaml | kubectl apply -f - >/dev/null
for i in $(seq 1 30); do kubectl -n legacy get sa default >/dev/null 2>&1 && break; sleep 1; done
for sa in old-ci old-batch; do
  kubectl -n legacy create sa $sa 2>/dev/null
  kubectl apply -f - <<YAML
apiVersion: v1
kind: Secret
metadata:
  name: $sa-token
  namespace: legacy
  annotations: {kubernetes.io/service-account.name: $sa}
type: kubernetes.io/service-account-token
YAML
done
kubectl -n legacy create secret generic app-config --from-literal=mode=prod 2>/dev/null
for i in $(seq 1 30); do kubectl -n legacy get secret old-ci-token -o jsonpath='{.data.token}' | grep -q . && break; sleep 1; done
# Keep a copy of one old token where the check finds it, then use it once.
mkdir -p /opt/cks-check && kubectl -n legacy get secret old-ci-token -o jsonpath='{.data.token}' | base64 -d > /opt/cks-check/legacy-token
IP=$(hostname -I | cut -d' ' -f1)
echo "  old-ci's legacy token against the API: $(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat /opt/cks-check/legacy-token)" https://$IP:6443/api)"
sleep 2
kubectl -n legacy get secret old-ci-token -o jsonpath='  label legacy-token-last-used: {.metadata.labels.kubernetes\.io/legacy-token-last-used}{"\n"}'
EOF
}
check_2_8() {
  check_cp "no Secret of type kubernetes.io/service-account-token is left in legacy" \
    "kubectl -n legacy get secrets --field-selector type=kubernetes.io/service-account-token --no-headers 2>&1 | grep -q 'No resources found'"
  # The API server caches token lookups for a few seconds, so poll.
  check_cp "old-ci's old token no longer authenticates (401)" \
    "for i in \$(seq 1 30); do curl -sk -o /dev/null -w '%{http_code}' -H \"Authorization: Bearer \$(cat /opt/cks-check/legacy-token)\" https://\$(hostname -I | cut -d' ' -f1):6443/api | grep -qx 401 && exit 0; sleep 2; done; exit 1"
  check_cp "both ServiceAccounts and Secret app-config still exist" \
    "kubectl -n legacy get sa old-ci old-batch && kubectl -n legacy get secret app-config"
}
solve_2_8() {
  oncp <<'EOF'
kubectl get secrets -A --field-selector type=kubernetes.io/service-account-token
kubectl -n legacy delete secret --field-selector type=kubernetes.io/service-account-token
IP=$(hostname -I | cut -d' ' -f1); s=$(date +%s)
for i in $(seq 1 60); do [ "$(curl -sk -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $(cat /opt/cks-check/legacy-token)" https://$IP:6443/api)" = 401 ] && break; sleep 1; done
echo "the old token got 401 after $(( $(date +%s) - s )) seconds"
EOF
}

# ---- Task 9: repair the API server -------------------------------------------------------
setup_2_9() {
  oncp <<'EOF'
f=/etc/kubernetes/manifests/kube-apiserver.yaml
cp $f /root/kube-apiserver.yaml.before-2.9
kubectl delete pod -n default pull-test --ignore-not-found --now >/dev/null 2>&1
sed -i -e 's/--enable-admission-plugins=NodeRestriction$/--enable-admission-plugins=NodeRestriction,AlwaysPullImage/' \
       -e 's|--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt|--etcd-cafile=/etc/kubernetes/pki/etcd/ca.cert|' $f
echo "  a colleague edited the API server manifest at $(date +%H:%M:%S)"
EOF
  sleep 20
}
check_2_9() {
  local f=/etc/kubernetes/manifests/kube-apiserver.yaml
  check_cp "the API server answers and its pod is Ready" \
    "kubectl get --raw=/readyz && kubectl -n kube-system wait pod -l component=kube-apiserver --for=condition=Ready --timeout=30s"
  check_cp "the admission plugins are NodeRestriction and AlwaysPullImages" \
    "grep -q -- '--enable-admission-plugins=NodeRestriction,AlwaysPullImages\$' $f"
  check_cp "--etcd-cafile points to the etcd CA" "grep -q -- '--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt\$' $f"
  check_cp "AlwaysPullImages sets imagePullPolicy Always on a new pod" \
    "kubectl run pull-test --image=busybox:1.36 --image-pull-policy=IfNotPresent --dry-run=server -o jsonpath='{.spec.containers[0].imagePullPolicy}' -- sleep 1 | grep -qx Always"
}
solve_2_9() {
  oncp <<'EOF'
f=/etc/kubernetes/manifests/kube-apiserver.yaml
crictl ps -a --name kube-apiserver | head -3
for c in $(crictl ps -a --name kube-apiserver -q | head -1); do crictl logs $c 2>&1 | tail -2; done
sed -i -e 's/AlwaysPullImage$/AlwaysPullImages/' -e 's|etcd/ca.cert$|etcd/ca.crt|' $f
EOF
  sleep 5; wait_api; wait_static kube-apiserver
}

# ---- Task 10: repair etcd ------------------------------------------------------------------
setup_2_10() {
  oncp <<'EOF'
kubectl -n default create configmap cks-canary --from-literal=alive=yes 2>/dev/null
f=/etc/kubernetes/manifests/etcd.yaml
cp $f /root/etcd.yaml.before-2.10
sed -i -e 's|--cert-file=/etc/kubernetes/pki/etcd/server.crt|--cert-file=/etc/kubernetes/pki/etcd/server.cert|' \
       -e 's|--listen-client-urls=https://127.0.0.1:2379,|--listen-client-urls=https://127.0.0.1:2378,|' $f
echo "  someone edited etcd's manifest at $(date +%H:%M:%S)"
EOF
  sleep 20
}
check_2_10() {
  local f=/etc/kubernetes/manifests/etcd.yaml
  check_cp "the API server answers again" "kubectl get --raw=/readyz"
  check_cp "etcd uses its server certificate" "grep -q -- '--cert-file=/etc/kubernetes/pki/etcd/server.crt\$' $f"
  check_cp "etcd listens for clients on 127.0.0.1:2379" "ss -tln | grep -q '127.0.0.1:2379 '"
  check_cp "the cluster's data survived: ConfigMap cks-canary still exists" "kubectl -n default get configmap cks-canary"
  check_cp "the etcd pod is Ready" "kubectl -n kube-system wait pod -l component=etcd --for=condition=Ready --timeout=30s"
}
solve_2_10() {
  oncp <<'EOF'
f=/etc/kubernetes/manifests/etcd.yaml
for c in $(crictl ps -a --name etcd -q | head -1); do crictl logs $c 2>&1 | tail -1; done
sed -i -e 's|etcd/server.cert$|etcd/server.crt|' -e 's|https://127.0.0.1:2378,|https://127.0.0.1:2379,|' $f
EOF
  sleep 5; wait_api; wait_static etcd
}

# ---- Task 11: no pods for a new Deployment --------------------------------------------------
setup_2_11() {
  oncp <<'EOF'
cp /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.before-2.11
cp /etc/kubernetes/manifests/kube-controller-manager.yaml /root/kube-controller-manager.yaml.before-2.11
sed -i 's|--kubeconfig=/etc/kubernetes/scheduler.conf|--kubeconfig=/etc/kubernetes/scheduler.config|' /etc/kubernetes/manifests/kube-scheduler.yaml
sed -i 's|--cluster-signing-key-file=|--cluster-signing-keyfile=|' /etc/kubernetes/manifests/kube-controller-manager.yaml
sleep 25
kubectl -n default delete deploy canary --ignore-not-found >/dev/null
kubectl -n default create deploy canary --image=nginx:1.27-alpine
EOF
}
check_2_11() {
  check_cp "kube-scheduler runs and is Ready" "kubectl -n kube-system wait pod kube-scheduler-cks-cp --for=condition=Ready --timeout=30s"
  check_cp "kube-controller-manager runs and is Ready" "kubectl -n kube-system wait pod kube-controller-manager-cks-cp --for=condition=Ready --timeout=30s"
  check_cp "Deployment canary has a ready pod" "kubectl -n default rollout status deploy canary --timeout=90s"
  check_cp "the manifests use scheduler.conf and --cluster-signing-key-file" \
    "grep -q -- '--kubeconfig=/etc/kubernetes/scheduler.conf\$' /etc/kubernetes/manifests/kube-scheduler.yaml && grep -q -- '--cluster-signing-key-file=' /etc/kubernetes/manifests/kube-controller-manager.yaml"
}
solve_2_11() {
  oncp <<'EOF'
kubectl -n kube-system get pods -l tier=control-plane
for n in kube-scheduler kube-controller-manager; do c=$(crictl ps -a --name $n -q | head -1); crictl logs $c 2>&1 | tail -1; done
sed -i 's|scheduler.config$|scheduler.conf|' /etc/kubernetes/manifests/kube-scheduler.yaml
sed -i 's|--cluster-signing-keyfile=|--cluster-signing-key-file=|' /etc/kubernetes/manifests/kube-controller-manager.yaml
EOF
  sleep 5; wait_static kube-scheduler; wait_static kube-controller-manager
  k -n default rollout status deploy canary --timeout=120s
}

# ---- Task 12: an API server that allows everything ------------------------------------------
setup_2_12() {
  oncp <<'EOF'
f=/etc/kubernetes/manifests/kube-apiserver.yaml
cp $f /root/kube-apiserver.yaml.before-2.12
sed -i 's/--authorization-mode=Node,RBAC$/--authorization-mode=AlwaysAllow/' $f
EOF
  sleep 5; wait_api
  cp_sh 'for i in $(seq 1 60); do kubectl auth can-i list secrets -A --as=system:serviceaccount:default:default 2>/dev/null | grep -qx yes && break; sleep 2; done
    echo "  may the default ServiceAccount list every Secret? $(kubectl auth can-i list secrets -A --as=system:serviceaccount:default:default)"'
}
check_2_12() {
  check_cp "the API server uses --authorization-mode=Node,RBAC" \
    "grep -q -- '--authorization-mode=Node,RBAC\$' /etc/kubernetes/manifests/kube-apiserver.yaml"
  check_cp "an anonymous request for kube-system Secrets gets 403" \
    "curl -sk -o /dev/null -w '%{http_code}' https://\$(hostname -I | cut -d' ' -f1):6443/api/v1/namespaces/kube-system/secrets | grep -qx 403"
  check "the default ServiceAccount may not list Secrets" \
    bash -c "! orb -m $CKS_CP -u root kubectl auth can-i list secrets -A --as=system:serviceaccount:default:default"
  check_cp "the nodes stay Ready" "kubectl wait node --all --for=condition=Ready --timeout=60s"
}
solve_2_12() {
  cp_sh "sed -i 's/--authorization-mode=AlwaysAllow\$/--authorization-mode=Node,RBAC/' /etc/kubernetes/manifests/kube-apiserver.yaml"
  sleep 5; wait_api; wait_static kube-apiserver
}
