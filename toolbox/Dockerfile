# The lab toolbox: every command-line tool the lab scripts and the course use, at the versions
# the course was tested with. ./lab.sh shell builds it and opens a shell in it, so a machine
# needs only Docker and git. The clusters still run as containers on the host's Docker engine;
# the toolbox reaches that engine through the mounted Docker socket.
FROM debian:13.7-slim

ARG TARGETARCH
ARG KUBECTL_VERSION=1.31.5
ARG HELM_VERSION=4.3.1
ARG K3D_VERSION=5.9.0
ARG KIND_VERSION=0.33.0
ARG ISTIOCTL_VERSION=1.32.0
ARG COMPOSE_VERSION=5.6.1
ARG BUILDX_VERSION=0.38.1
ARG TRIVY_VERSION=0.76.1
ARG COSIGN_VERSION=3.1.4

# Debian's packages are signed, so apt checks them. The scripts call bash, curl 7.84 or newer,
# git, python3, openssl, jq, socat, nc, dig and nslookup, column and shasum; docker-cli runs
# docker build and docker exec against the host's engine, with the newer buildx plugin below.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
      bash bash-completion ca-certificates curl git jq python3 python3-yaml openssl socat \
      netcat-openbsd bind9-dnsutils iputils-ping iproute2 procps psmisc less vim-tiny tree \
      bsdextrautils gettext-base openssh-client perl docker-cli tini \
 && rm -rf /var/lib/apt/lists/*

# Each download is checked against the sha256 its project publishes, for amd64 and arm64.
RUN set -eu; \
    case "$TARGETARCH" in \
      amd64) kubectl=fbecbfd375b3686002c2e81d51c390172f5ffba3d6b47920d55342cb03f557af; \
             helm=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b; \
             k3d=06d8f25bc3a971c4eb29e0ff08429b180402db0f4dec838c9eac427e296800a0; \
             kind=aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d; \
             istioctl=4771175dec92527cd90ddc7edb3b3abcb32ca2f3bc32b31aa31e0b12ad36f897; \
             compose=47737f4236e6d3ccea7291995203f8f018058783b4c3a9469119811a0b5db8c0; carch=x86_64; \
             buildx=e25d5cd675092bb5d1d03632fdc46cdf3fede7b514dc5f023a105e00d3ce5ad4; \
             trivy=c7cbe3137fb8a48a17574bede3dd6beb16742d1e9772929940fc90082c39d9c0; tarch=64bit; \
             cosign=424e2c97d0b45fd7a6b608a87f090f35633f4c23ece5f092d48bba11aaf4bbfa ;; \
      arm64) kubectl=697c8b4239f9e53cba46296e114bcc02c726b5c7a45e1c464804aad56e5c7a86; \
             helm=8cf8f66ecbc252ac8f7f06cca68aba88508ddfde3a6a34feb1678ad1694b4f88; \
             k3d=03cde5cf23e6e8e67de5a039ecf26e5b85aca82fba3e5d13dadf904cd218a250; \
             kind=20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2; \
             istioctl=6ddfad272f4faa34ef5177e568b7473de2b17ac0464668aea93bf8a450fbbc8a; \
             compose=42cfa75f51ad0ccf290bad37899e0038a8c10a0069e85233ecc1d53e3ff1347d; carch=aarch64; \
             buildx=3b83b3731916ba433feccaaa689fe5bcdc81c641d92c8e6c2ea865dfa141c97a; \
             trivy=e174dff2a6dba5e3ae41f8d0537a6324405bd08132497340304c6b20e0f16a1f; tarch=ARM64; \
             cosign=ade83b7aac62e131cacfe96d958948b2150cc9efec46a570a2649b8e27dedad2 ;; \
      *) echo "no toolbox build for architecture $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    tmp="$(mktemp -d)"; cd "$tmp"; \
    get() { curl -fsSL -o "$1" "$2" && echo "$3  $1" | sha256sum -c - >/dev/null; }; \
    get kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/${TARGETARCH}/kubectl" "$kubectl"; \
    get helm.tgz "https://get.helm.sh/helm-v${HELM_VERSION}-linux-${TARGETARCH}.tar.gz" "$helm"; \
    get k3d "https://github.com/k3d-io/k3d/releases/download/v${K3D_VERSION}/k3d-linux-${TARGETARCH}" "$k3d"; \
    get kind "https://github.com/kubernetes-sigs/kind/releases/download/v${KIND_VERSION}/kind-linux-${TARGETARCH}" "$kind"; \
    get istioctl.tgz "https://github.com/istio/istio/releases/download/${ISTIOCTL_VERSION}/istioctl-${ISTIOCTL_VERSION}-linux-${TARGETARCH}.tar.gz" "$istioctl"; \
    # The Docker track (track 0): the compose and buildx plugins, the trivy scanner and cosign.
    get docker-compose "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${carch}" "$compose"; \
    get docker-buildx "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${TARGETARCH}" "$buildx"; \
    get trivy.tgz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${tarch}.tar.gz" "$trivy"; \
    get cosign "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${TARGETARCH}" "$cosign"; \
    tar -xzf helm.tgz "linux-${TARGETARCH}/helm"; tar -xzf istioctl.tgz istioctl; tar -xzf trivy.tgz trivy; \
    install -m 755 kubectl "linux-${TARGETARCH}/helm" istioctl trivy cosign /usr/local/bin/; \
    mkdir -p /usr/local/lib/docker/cli-plugins; install -m 755 docker-compose docker-buildx /usr/local/lib/docker/cli-plugins/; \
    # k3d and kind go to /usr/local/lib/lab; the wrappers below keep the toolbox kubeconfig right.
    mkdir -p /usr/local/lib/lab; install -m 755 k3d kind /usr/local/lib/lab/; \
    cd /; rm -rf "$tmp"; \
    kubectl version --client >/dev/null; helm version >/dev/null; istioctl version --remote=false >/dev/null; \
    docker compose version >/dev/null; docker buildx version >/dev/null; trivy --version >/dev/null; cosign version >/dev/null

COPY entrypoint.sh kube-sync.sh /usr/local/lib/lab/
COPY wrapper.sh /usr/local/bin/k3d
COPY wrapper.sh /usr/local/bin/kind
COPY bashrc.sh /etc/profile.d/lab.sh
RUN chmod 755 /usr/local/lib/lab/*.sh /usr/local/bin/k3d /usr/local/bin/kind \
 && kubectl completion bash > /etc/bash_completion.d/kubectl \
 && helm completion bash > /etc/bash_completion.d/helm \
 && /usr/local/lib/lab/k3d completion bash > /etc/bash_completion.d/k3d \
 && /usr/local/lib/lab/kind completion bash > /etc/bash_completion.d/kind \
 && istioctl completion bash > /etc/bash_completion.d/istioctl \
 && echo '. /etc/profile.d/lab.sh' >> /etc/bash.bashrc

# lab.sh reads LAB_TOOLBOX to know it runs here. Port-forwards listen on every interface, so
# the ports compose.yaml publishes reach them from the host's browser.
ENV LAB_TOOLBOX=1 PF_ADDRESS=0.0.0.0 KUBECONFIG=/home/lab/.kube/config
ENTRYPOINT ["tini", "--", "/usr/local/lib/lab/entrypoint.sh"]
CMD ["sleep", "infinity"]
