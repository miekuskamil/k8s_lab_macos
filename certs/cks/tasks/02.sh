# Domain 02, cluster hardening. Functions for task.sh: setup_2_N, check_2_N, solve_2_N.

SA_REPORTER=system:serviceaccount:finance:reporter

# ---- Task 1: trim an over-broad Role -------------------------------------------------
setup_2_1() {
  oncp <<'EOF'
kubectl create ns finance --dry-run=client -o yaml | kubectl apply -f - >/dev/null
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
