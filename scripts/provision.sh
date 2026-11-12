#!/usr/bin/env bash
# Provision the k8s_lab_macos reference architecture on macOS or Linux.
# A k3d cluster runs on the local Docker engine (OrbStack on macOS, Docker Engine on Linux). OrbStack's built-in
# Kubernetes cluster has no CNI config directory for Istio CNI to chain onto, so ambient
# mode cannot start there. k3d uses k3s with flannel, which Istio ambient supports.
# Safe to run repeatedly. Every step checks current state or uses an upsert command.
#
# Usage: ./scripts/provision.sh
# Optional environment overrides:
#   ISTIO_VERSION, GATEWAY_API_VERSION, ARGOCD_CHART_VERSION, SYNC_TIMEOUT_SECONDS,
#   SKIP_IMAGE_BUILD=1, ISTIO_PLATFORM (for example "k3s", detected when unset)

set -euo pipefail

REPO_URL="https://github.com/miekuskamil/k8s_lab_macos"
REPO_BRANCH="main"
ISTIO_VERSION="${ISTIO_VERSION:-1.24.2}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.2.1}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-7.7.11}"
SYNC_TIMEOUT_SECONDS="${SYNC_TIMEOUT_SECONDS:-900}"
CLUSTER_NAME="${CLUSTER_NAME:-k8s-lab}"
# Istio 1.24 supports Kubernetes 1.28 to 1.31, and ArgoCD 7.7 does not know newer API schemas.
K3S_IMAGE="${K3S_IMAGE:-rancher/k3s:v1.31.5-k3s1}"
KUBE_CONTEXT="k3d-${CLUSTER_NAME}"
IMAGE_TAG="1.0.2"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; RESET=""
fi

step() { printf '\n%s==> %s%s\n' "$BOLD" "$*" "$RESET"; }
ok()   { printf '%s ok%s  %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%swarn%s  %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%sfail%s  %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

check_prerequisites() {
  step "Checking prerequisites"
  local missing=0
  for cmd in kubectl helm k3d git docker curl; do
    if command -v "$cmd" >/dev/null 2>&1; then
      ok "$cmd found at $(command -v "$cmd")"
    else
      warn "$cmd is not installed"
      missing=1
    fi
  done
  if [[ "$missing" -eq 1 ]]; then
    die "Install the missing tools first. See README.md, section \"What you need\"."
  fi

  # The traffic scripts read response headers with curl -w '%header{...}', added in curl 7.84.
  local curl_version
  curl_version="$(curl --version | awk 'NR==1 {print $2}')"
  if ! printf '%s\n%s\n' "7.84.0" "$curl_version" | sort -V -C; then
    die "curl $curl_version is too old. The lab scripts need curl 7.84 or newer (Ubuntu 22.04 ships 7.81)."
  fi
  ok "curl $curl_version is new enough"

  if [[ "$(uname -s)" == "Linux" ]]; then
    # k3s, Istio and the monitoring stack each open inotify watchers. The kernel default
    # of 128 instances per user runs out and pods fail with "too many open files".
    local instances
    instances="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"
    if (( instances < 512 )); then
      die "fs.inotify.max_user_instances is ${instances}. Raise it first: sudo sysctl -w fs.inotify.max_user_instances=512 fs.inotify.max_user_watches=524288"
    fi
    ok "inotify limits are high enough (${instances} instances)"
  fi
}

ensure_docker() {
  step "Checking the container engine"
  if command -v orb >/dev/null 2>&1 && ! orb status >/dev/null 2>&1; then
    warn "OrbStack is not running, starting it"
    orb start
  fi
  docker info >/dev/null 2>&1 || die "The Docker engine does not answer. Start OrbStack or Docker. On Linux, check that your user is in the docker group."
  ok "Docker answers: $(docker info --format '{{.OperatingSystem}}, {{.NCPU}} CPUs, {{.MemTotal}}' | awk -F', ' '{printf "%s, %s, %.1f GiB", $1, $2, $3/1073741824}')"
}

ensure_cluster() {
  step "Checking the k3d cluster ${CLUSTER_NAME}"
  if k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$CLUSTER_NAME"; then
    ok "k3d cluster $CLUSTER_NAME already exists"
    "$ROOT_DIR/scripts/start.sh" --quiet
  else
    k3d cluster create "$CLUSTER_NAME" \
      --image "$K3S_IMAGE" \
      --servers 1 --agents 0 \
      --port "8080:8080@loadbalancer" \
      --k3s-arg "--disable=traefik@server:0" \
      --wait --timeout 180s >/dev/null
    ok "k3d cluster $CLUSTER_NAME created, host port 8080 maps to the cluster load balancer"
  fi
  kubectl config use-context "$KUBE_CONTEXT" >/dev/null
  kubectl wait --for=condition=Ready node --all --timeout=120s >/dev/null
  ok "context $KUBE_CONTEXT is ready: $(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')"
}

check_repository() {
  step "Checking the Git repository that ArgoCD will sync"
  if ! git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    die "$ROOT_DIR is not a Git working tree. Clone $REPO_URL and run the script from the clone."
  fi
  if ! git ls-remote --exit-code "$REPO_URL" "refs/heads/$REPO_BRANCH" >/dev/null 2>&1; then
    die "Cannot read branch $REPO_BRANCH of $REPO_URL. ArgoCD needs a public repo, or you must add repository credentials to ArgoCD."
  fi
  ok "$REPO_URL ($REPO_BRANCH) is reachable"
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    warn "You have uncommitted changes. ArgoCD syncs the pushed state of $REPO_BRANCH, not your working tree."
  fi
  if [[ -n "$(git -C "$ROOT_DIR" log "origin/$REPO_BRANCH..HEAD" --oneline 2>/dev/null || true)" ]]; then
    warn "You have local commits that are not pushed to origin/$REPO_BRANCH."
  fi
}

build_images() {
  step "Building application images and loading them into the cluster"
  if [[ "${SKIP_IMAGE_BUILD:-0}" == "1" ]]; then
    warn "SKIP_IMAGE_BUILD=1, skipping the build"
  else
    docker build --quiet -t "k8s-lab/backend:${IMAGE_TAG}" "$ROOT_DIR/apps/backend" >/dev/null
    ok "built k8s-lab/backend:${IMAGE_TAG}"
    docker build --quiet -t "k8s-lab/frontend:${IMAGE_TAG}" "$ROOT_DIR/apps/frontend" >/dev/null
    ok "built k8s-lab/frontend:${IMAGE_TAG}"
  fi
  k3d image import "k8s-lab/backend:${IMAGE_TAG}" "k8s-lab/frontend:${IMAGE_TAG}" -c "$CLUSTER_NAME" >/dev/null
  ok "images imported into k3d cluster $CLUSTER_NAME, no registry needed"
}

install_gateway_api_crds() {
  step "Installing Gateway API CRDs ${GATEWAY_API_VERSION}"
  if kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; then
    ok "Gateway API CRDs already present"
    return
  fi
  kubectl apply --server-side -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml" >/dev/null
  ok "Gateway API CRDs installed"
}

detect_platform_args() {
  PLATFORM_ARGS=()
  CNI_EXTRA_ARGS=()
  local platform="${ISTIO_PLATFORM:-}"
  if [[ -z "$platform" ]]; then
    local kubelet_version
    kubelet_version="$(kubectl get nodes -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}')"
    if [[ "$kubelet_version" == *k3s* ]]; then
      platform="k3s"
    fi
  fi
  if [[ -n "$platform" ]]; then
    PLATFORM_ARGS=(--set "global.platform=${platform}")
    if [[ "$platform" == "k3s" ]]; then
      # The CNI plugin directory differs between k3s versions, and the istio-cni binary must
      # land in the directory containerd searches. Read it from the node's containerd config.
      local bin_dir=""
      bin_dir="$(docker exec "k3d-${CLUSTER_NAME}-server-0" \
        sed -n 's/^[[:space:]]*bin_dir = "\(.*\)"/\1/p' /var/lib/rancher/k3s/agent/etc/containerd/config.toml 2>/dev/null | head -1 || true)"
      bin_dir="${bin_dir:-/var/lib/rancher/k3s/data/cni}"
      CNI_EXTRA_ARGS=(--set "cni.cniBinDir=${bin_dir}")
      ok "containerd searches ${bin_dir} for CNI plugins"
    fi
    ok "Using Istio platform profile: ${platform}"
  fi
}

install_istio_ambient() {
  step "Installing Istio ${ISTIO_VERSION} in ambient mode with Helm"
  helm repo add istio https://istio-release.storage.googleapis.com/charts --force-update >/dev/null
  helm repo update istio >/dev/null
  detect_platform_args

  # Helm 4 applies charts server-side. istiod edits a field of the validating webhook that
  # istio-base also sets, so upgrades need --force-conflicts. Helm 3 has no such flag.
  local base_args=()
  if helm upgrade --help 2>/dev/null | grep -q -- "--force-conflicts"; then
    base_args=(--force-conflicts)
  fi
  # The same flag applies to every Istio chart below.
  helm upgrade --install istio-base istio/base \
    --namespace istio-system --create-namespace \
    --version "$ISTIO_VERSION" \
    -f "$ROOT_DIR/helm/istio-base-values.yaml" \
    ${base_args[@]+"${base_args[@]}"} --wait >/dev/null
  ok "istio-base"

  helm upgrade --install istiod istio/istiod \
    --namespace istio-system \
    --version "$ISTIO_VERSION" \
    -f "$ROOT_DIR/helm/istiod-values.yaml" \
    ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} \
    ${base_args[@]+"${base_args[@]}"} --wait --timeout 5m >/dev/null
  ok "istiod (control plane)"

  helm upgrade --install istio-cni istio/cni \
    --namespace istio-system \
    --version "$ISTIO_VERSION" \
    -f "$ROOT_DIR/helm/istio-cni-values.yaml" \
    ${PLATFORM_ARGS[@]+"${PLATFORM_ARGS[@]}"} \
    ${CNI_EXTRA_ARGS[@]+"${CNI_EXTRA_ARGS[@]}"} \
    ${base_args[@]+"${base_args[@]}"} --wait --timeout 5m >/dev/null
  ok "istio-cni (traffic redirection)"

  helm upgrade --install ztunnel istio/ztunnel \
    --namespace istio-system \
    --version "$ISTIO_VERSION" \
    -f "$ROOT_DIR/helm/ztunnel-values.yaml" \
    ${base_args[@]+"${base_args[@]}"} --wait --timeout 5m >/dev/null
  ok "ztunnel (node proxy)"
}

create_namespaces_and_secrets() {
  step "Creating namespaces and the default lab credentials"
  # ArgoCD manages both files later through shop-base. Applying them here lets pods
  # that need the Secrets start on their first try.
  kubectl apply -f "$ROOT_DIR/manifests/base/00-namespaces.yaml" \
                -f "$ROOT_DIR/manifests/base/03-lab-credentials.yaml" >/dev/null
  ok "namespaces shop, shop-ingress, observability"
  ok "secrets shop/redis-auth and observability/grafana-admin (defaults from Git)"
}

install_argocd() {
  step "Installing ArgoCD chart ${ARGOCD_CHART_VERSION}"
  helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
  helm repo update argo >/dev/null
  helm upgrade --install argocd argo/argo-cd \
    --namespace argocd --create-namespace \
    --version "$ARGOCD_CHART_VERSION" \
    -f "$ROOT_DIR/helm/argocd-values.yaml" --wait --timeout 8m >/dev/null
  ok "ArgoCD is running"
}

bootstrap_gitops() {
  step "Registering the root Application"
  kubectl apply -f "$ROOT_DIR/manifests/argocd/project.yaml" >/dev/null
  kubectl apply -f "$ROOT_DIR/manifests/argocd/root-app.yaml" >/dev/null
  ok "AppProject k8s-lab and Application root applied, ArgoCD now syncs $REPO_URL@$REPO_BRANCH"
}

app_table() {
  kubectl -n argocd get applications.argoproj.io \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}' 2>/dev/null
}

wait_for_sync() {
  step "Waiting for ArgoCD applications to become Synced and Healthy (timeout ${SYNC_TIMEOUT_SECONDS}s)"
  local deadline=$((SECONDS + SYNC_TIMEOUT_SECONDS))
  # One Application per file in manifests/argocd/apps, plus the root Application.
  local expected
  expected=$(( $(find "$ROOT_DIR/manifests/argocd/apps" -name '*.yaml' | wc -l) + 1 ))
  while (( SECONDS < deadline )); do
    local table total good
    table="$(app_table || true)"
    total="$(printf '%s\n' "$table" | grep -c . || true)"
    good="$(printf '%s\n' "$table" | awk -F'\t' '$2=="Synced" && $3=="Healthy"' | grep -c . || true)"
    printf '  %s of %s applications ready (%s found)\r' "$good" "$expected" "$total"
    if (( total >= expected && good >= expected )); then
      printf '\n'
      ok "all applications are Synced and Healthy"
      return 0
    fi
    sleep 10
  done
  printf '\n'
  warn "Timed out. Current state:"
  app_table | column -t -s $'\t' >&2 || true
  warn "Inspect with: kubectl -n argocd get applications, then kubectl -n argocd describe application <name>"
  return 1
}

health_checks() {
  step "Health checks"
  local failed=0
  check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else warn "$label"; failed=1; fi
  }
  check "istiod available" kubectl -n istio-system wait --for=condition=Available deploy/istiod --timeout=30s
  check "ztunnel ready on every node" kubectl -n istio-system rollout status ds/ztunnel --timeout=30s
  check "istio-cni ready on every node" kubectl -n istio-system rollout status ds/istio-cni-node --timeout=30s
  check "waypoint Gateway programmed" kubectl -n shop wait --for=condition=Programmed gateway/waypoint --timeout=60s
  check "ingress Gateway programmed" kubectl -n shop-ingress wait --for=condition=Programmed gateway/shop-gateway --timeout=60s
  check "redis ready" kubectl -n shop rollout status deploy/redis --timeout=60s
  check "backend-v1 ready" kubectl -n shop rollout status deploy/backend-v1 --timeout=60s
  check "backend-v2 ready" kubectl -n shop rollout status deploy/backend-v2 --timeout=60s
  check "frontend ready" kubectl -n shop rollout status deploy/frontend --timeout=60s
  check "prometheus ready" kubectl -n observability wait --for=condition=Ready pod -l app.kubernetes.io/name=prometheus --timeout=60s
  check "grafana ready" kubectl -n observability wait --for=condition=Ready pod -l app.kubernetes.io/name=grafana --timeout=60s
  check "jaeger ready" kubectl -n observability rollout status deploy/jaeger --timeout=60s
  check "loki ready" kubectl -n observability rollout status statefulset/loki --timeout=120s
  check "alloy ready" kubectl -n observability rollout status deploy/alloy --timeout=120s
  check "kiali ready" kubectl -n istio-system rollout status deploy/kiali --timeout=120s
  check "headlamp ready" kubectl -n headlamp rollout status deploy/headlamp --timeout=120s
  local tries=0
  until curl -fsS --max-time 5 http://localhost:8080/healthz >/dev/null 2>&1 || (( tries >= 24 )); do
    tries=$((tries + 1))
    sleep 5
  done
  if curl -fsS --max-time 5 http://localhost:8080/healthz >/dev/null 2>&1; then
    ok "http://localhost:8080/healthz answers through the ingress gateway"
  else
    warn "localhost:8080 did not answer within 2 minutes. Check: kubectl -n shop-ingress get pods"
    failed=1
  fi
  return "$failed"
}

print_summary() {
  step "Access"
  cat <<SUMMARY

Shop UI via the ingress gateway   http://localhost:8080

Run ./scripts/port-forward.sh to open these local ports:
  ArgoCD      http://localhost:8081    user admin, password k8s-lab-admin
  Grafana     http://localhost:3000    user admin, password k8s-lab-admin
  Prometheus  http://localhost:9090    no login
  Jaeger      http://localhost:16686   no login
  Kiali       http://localhost:20001   no login (anonymous, lab only)
  Headlamp    http://localhost:4466    token from the command below (cluster-admin, lab only)

Headlamp login token:
  kubectl -n headlamp get secret headlamp-admin -o jsonpath='{.data.token}' | base64 -d

Redis has no local port. Its password is k8s-lab-redis.
These are lab defaults stored in Git. See README.md, section "Open it".

Cluster ports
  ingress gateway 8080, frontend 3000, backend 8000, redis 6379,
  HBONE tunnel 15008, ztunnel metrics 15020, istiod xDS 15012, istiod metrics 15014

Next steps
  ./scripts/traffic-test.sh 200                 send 200 requests and print the version split
  kubectl apply -f manifests/scenarios/a-canary-httproute.yaml
  see docs/lab-guide.md for scenarios B and C, and course/README.md for the Istio course

SUMMARY
}

main() {
  check_prerequisites
  ensure_docker
  ensure_cluster
  check_repository
  build_images
  install_gateway_api_crds
  install_istio_ambient
  create_namespaces_and_secrets
  install_argocd
  bootstrap_gitops
  local sync_status=0
  wait_for_sync || sync_status=$?
  local health_status=0
  health_checks || health_status=$?
  print_summary
  if (( sync_status != 0 || health_status != 0 )); then
    exit 1
  fi
}

main "$@"
