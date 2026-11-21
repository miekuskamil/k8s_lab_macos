#!/usr/bin/env bash
# The practice cluster on kind: two kubeadm nodes that run as Docker containers, plus a local
# image registry container next to them. create.sh, reset.sh and destroy.sh call this script
# when PRACTICE_PLATFORM is kind, the default; ./lab.sh practice up|reset|down calls those.
#   kind.sh create    builds the node image once, then the cluster, Calico, the registry and ingress-nginx
#   kind.sh reset     deletes the cluster and builds it again from the same image (the registry stays)
#   kind.sh destroy   deletes the cluster and the registry; the node image stays in Docker's cache
# Safe to run again: create skips what already exists.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CLUSTER_DIR="$(cd "$HERE/.." && pwd)"
. "$CLUSTER_DIR/platform.sh"

KIND_VERSION="${KIND_VERSION:-0.33.0}"
K8S_VERSION="${K8S_VERSION:-1.37.1}"
CALICO_VERSION="${CALICO_VERSION:-3.32.3}"
INGRESS_NGINX_VERSION="${INGRESS_NGINX_VERSION:-1.15.1}"
REGISTRY_IMAGE="${REGISTRY_IMAGE:-registry:3.1.2}"
NODE_IMAGE="${PRACTICE_NODE_IMAGE:-practice-node:v$K8S_VERSION}"
NAME="$PRACTICE_KIND_NAME"
REGISTRY_CONTAINER=practice-registry
# kind writes the cluster's kubeconfig here instead of into ~/.kube/config, so your current
# kubectl context (the k3d lab, for example) stays as it is.
KUBECONFIG_FILE="${PRACTICE_KUBECONFIG:-$HOME/.kube/practice-kind.yaml}"

say() { printf '\n=== %s\n' "$*"; }

# kind itself: the one on your PATH, or a pinned copy that this script downloads once.
kind_bin() {
  if command -v kind >/dev/null 2>&1; then command -v kind; return; fi
  local os arch sum dest="$HERE/.bin/kind-v$KIND_VERSION"
  if [ ! -x "$dest" ]; then
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"; [ "$arch" = x86_64 ] && arch=amd64; [ "$arch" = aarch64 ] && arch=arm64
    case "$os-$arch" in
      darwin-arm64) sum=0c8c7dbe5e23594a198b786c4bc13dacc101fa6196b0cb0b23a1ca44e61f4b4f ;;
      darwin-amd64) sum=5a99f26f57246dc9319dd294803313197a0f34d33c525b3ea8b655db5916ece0 ;;
      linux-amd64)  sum=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d ;;
      linux-arm64)  sum=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2 ;;
      *) echo "no kind download for $os-$arch: install kind $KIND_VERSION yourself" >&2; exit 1 ;;
    esac
    echo "downloading kind $KIND_VERSION to $dest" >&2
    mkdir -p "$HERE/.bin"
    curl -fsSL -o "$dest.tmp" "https://github.com/kubernetes-sigs/kind/releases/download/v$KIND_VERSION/kind-$os-$arch"
    if [ "$(shasum -a 256 "$dest.tmp" | awk '{print $1}')" != "$sum" ]; then
      rm -f "$dest.tmp"; echo "the kind download failed its checksum" >&2; exit 1
    fi
    chmod 755 "$dest.tmp" && mv "$dest.tmp" "$dest"
  fi
  echo "$dest"
}

cluster_exists() { "$KIND" get clusters 2>/dev/null | grep -qx "$NAME"; }

create() {
  docker info >/dev/null 2>&1 || { echo "Docker is not running: start OrbStack or Docker Desktop first"; exit 1; }
  KIND="$(kind_bin)"

  say "1/6 node image $NODE_IMAGE"
  # The first build downloads the tools once (about 1 GB) and takes a few minutes. After that,
  # Docker's build cache answers in seconds and rebuilds only what changed in the Dockerfile.
  docker build -q -t "$NODE_IMAGE" --build-arg K8S_VERSION="$K8S_VERSION" -f "$HERE/Dockerfile" "$CLUSTER_DIR"

  say "2/6 kind cluster $NAME: $CP and $W1"
  if cluster_exists; then
    docker start "$CP" "$W1" >/dev/null
    echo "already exists"
  else
    mkdir -p "$(dirname "$KUBECONFIG_FILE")"
    sed "s|__IMAGE__|$NODE_IMAGE|" "$HERE/cluster.yaml" \
      | "$KIND" create cluster --config - --kubeconfig "$KUBECONFIG_FILE"
  fi
  # kubectl works for root on the control plane, like on an exam node.
  on "$CP" 'mkdir -p /root/.kube && cp /etc/kubernetes/admin.conf /root/.kube/config'

  say "3/6 Calico $CALICO_VERSION (enforces NetworkPolicy)"
  on "$CP" "curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml \
    | sed -e 's|# - name: CALICO_IPV4POOL_CIDR|- name: CALICO_IPV4POOL_CIDR|' -e 's|#   value: \"192.168.0.0/16\"|  value: \"10.244.0.0/16\"|' \
    | kubectl apply -f - >/dev/null && kubectl -n kube-system rollout status ds/calico-node --timeout=300s"
  on "$CP" "kubectl wait node --all --for=condition=Ready --timeout=300s >/dev/null"
  # kind adds a default StorageClass that a kubeadm cluster lacks; the storage tasks expect none.
  on "$CP" "kubectl delete storageclass standard --ignore-not-found >/dev/null; kubectl delete ns local-path-storage --ignore-not-found --wait=false >/dev/null"

  say "4/6 node services: gVisor and Falco on $W1, the image policy back end on $CP"
  on "$W1" "grep -q 'runtimes.runsc\]' /etc/containerd/config.toml || {
      printf '\n[plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runsc]\n  runtime_type = \"io.containerd.runsc.v1\"\n' >> /etc/containerd/config.toml
      systemctl restart containerd; }
    systemctl enable --now falco-modern-bpf >/dev/null 2>&1 || true
    echo \"$W1: runsc \$(runsc --version | awk 'NR==1{print \$3}'), falco service \$(systemctl is-active falco-modern-bpf)\""
  # gVisor belongs to the worker only, as on the other platforms (module 4.4, task 9 relies on it).
  on "$CP" "rm -rf /usr/local/bin/runsc /usr/local/bin/containerd-shim-runsc-v1 /usr/local/bin/gvisor-bin
    bash /opt/practice/image-policy/install.sh"

  say "5/6 registry $PRACTICE_REGISTRY (container $REGISTRY_CONTAINER on the kind network)"
  if ! docker container inspect "$REGISTRY_CONTAINER" >/dev/null 2>&1; then
    # The name registry.practice reaches the container from both nodes and from every pod.
    docker create --restart=always --name "$REGISTRY_CONTAINER" --network kind \
      --network-alias "${PRACTICE_REGISTRY%:*}" "$REGISTRY_IMAGE" >/dev/null
    docker cp "$HERE/registry.yml" "$REGISTRY_CONTAINER:/etc/distribution/config.yml"
    docker start "$REGISTRY_CONTAINER" >/dev/null
  else
    docker start "$REGISTRY_CONTAINER" >/dev/null
    docker network connect --alias "${PRACTICE_REGISTRY%:*}" kind "$REGISTRY_CONTAINER" 2>/dev/null || true
  fi
  on "$CP" "for i in \$(seq 1 20); do curl -fsS http://$PRACTICE_REGISTRY/v2/ >/dev/null 2>&1 && break; sleep 1; done
    curl -fsS http://$PRACTICE_REGISTRY/v2/_catalog"

  say "6/6 ingress-nginx $INGRESS_NGINX_VERSION on NodePorts 30080 and 30443"
  # The project was retired in March 2026, but the Ingress API it serves is the same one the exam asks about.
  on "$CP" "curl -fsSL https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v${INGRESS_NGINX_VERSION}/deploy/static/provider/baremetal/deploy.yaml \
    | kubectl apply -f - >/dev/null
    kubectl -n ingress-nginx patch svc ingress-nginx-controller --type=json -p='[
      {\"op\":\"replace\",\"path\":\"/spec/ports/0/nodePort\",\"value\":30080},
      {\"op\":\"replace\",\"path\":\"/spec/ports/1/nodePort\",\"value\":30443}]' >/dev/null
    kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s"

  say "ready"
  on "$CP" "kubectl get nodes -o wide"
  cat <<EOF

Work on the control plane the way the exam does, from a shell on the node:
  ./lab.sh practice shell            # then: kubectl get nodes
  ./lab.sh practice shell worker     # for node tasks on the worker
From a toolbox shell (./lab.sh shell): kubectl --context kind-$NAME get nodes
EOF
  [[ "${LAB_TOOLBOX:-}" == 1 ]] || echo "Without the toolbox, with kubectl installed: KUBECONFIG=$KUBECONFIG_FILE kubectl get nodes"
}

delete_cluster() {
  KIND="$(kind_bin)"
  if cluster_exists; then "$KIND" delete cluster --name "$NAME" --kubeconfig "$KUBECONFIG_FILE"; else echo "no kind cluster named $NAME"; fi
}

case "${1:-}" in
  create) create ;;
  reset)
    delete_cluster
    # The registry keeps running, and the application reset empties it.
    create ;;
  destroy)
    delete_cluster
    if docker container inspect "$REGISTRY_CONTAINER" >/dev/null 2>&1; then
      docker rm -f "$REGISTRY_CONTAINER" >/dev/null && echo "deleted the registry container $REGISTRY_CONTAINER"
    fi
    echo "the node image $NODE_IMAGE stays in Docker's cache; docker rmi $NODE_IMAGE removes it" ;;
  *) sed -n '2,8p' "$0"; exit 1 ;;
esac
