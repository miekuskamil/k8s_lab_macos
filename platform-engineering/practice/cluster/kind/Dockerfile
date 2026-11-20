# The practice node image: kind's node image plus every tool the practice tasks use.
# create.sh builds it once, from the cluster folder, as practice-node:<k8s version>; Docker caches it after that.
# kind 0.33.0 publishes v1.37.0 as its newest node image, so the packages lift it to 1.37.1.
ARG KIND_NODE_IMAGE=kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5
FROM ${KIND_NODE_IMAGE}

ARG K8S_VERSION=1.37.1
ARG ETCD_VERSION=3.7.0
ARG TRIVY_VERSION=0.76.1
ARG KUBE_BENCH_VERSION=0.16.0
ARG KUBESEC_VERSION=2.15.0
ARG BOM_VERSION=0.8.0
ARG GVISOR_RELEASE=20261026
ARG FALCO_VERSION=0.45.1
ARG HELM_VERSION=4.3.1

COPY kind/node-image.sh /tmp/node-image.sh
RUN K8S_VERSION=$K8S_VERSION ETCD_VERSION=$ETCD_VERSION TRIVY_VERSION=$TRIVY_VERSION \
    KUBE_BENCH_VERSION=$KUBE_BENCH_VERSION KUBESEC_VERSION=$KUBESEC_VERSION BOM_VERSION=$BOM_VERSION \
    GVISOR_RELEASE=$GVISOR_RELEASE FALCO_VERSION=$FALCO_VERSION HELM_VERSION=$HELM_VERSION \
    bash /tmp/node-image.sh && rm /tmp/node-image.sh

# The image policy back end for module 42; create.sh starts it on the control plane.
COPY image-policy /opt/practice/image-policy
