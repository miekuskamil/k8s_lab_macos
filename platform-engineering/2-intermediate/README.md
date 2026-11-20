# Level 2: Intermediate

These modules take Istio further, add the everyday tools of a platform team, and start securing a cluster, in three domains. The mesh and platform modules run on the k3d lab, while the security modules run on the [practice cluster](../practice-cluster.md) as timed tasks. Each module lists the modules and tools it needs at the top.

## Mesh in practice

The mesh modules build on the [service mesh basics](../1-foundations/README.md#service-mesh-basics).

- [Module 7: Sidecar mode](07-sidecar-mode.md)
- [Module 11: TLS at the edge](11-edge-tls.md)
- [Module 12: Egress](12-egress.md)
- [Module 13: JWT](13-jwt.md)
- [Module 15: Outlier detection and retries](15-outlier-detection-and-retries.md)
- [Module 16: The Istio API](16-istio-api.md)

## Platform operations

The platform modules need only module 0, though 23 builds on module 6 and 24 on 23.

- [Module 20: Nodes, drains and cleanup](20-nodes-and-cleanup.md)
- [Module 22: GitOps with ArgoCD](22-gitops-with-argocd.md)
- [Module 23: Prometheus and alerting](23-prometheus-and-alerting.md)
- [Module 24: Grafana as code](24-grafana-as-code.md)
- [Module 26: Kyverno, policy as code](26-kyverno-policy-as-code.md)

## Building a secure cluster: setup and hardening

The security modules start from a fresh kubeadm cluster and close the doors its defaults leave open. Module 36 introduces RBAC and security contexts, so it makes a good warm-up. The three Cilium tasks of module 38 run on a VM and sit in [module 44](../kernel-and-host/README.md).

- [Module 38: Setting up a secure cluster](38-setting-up-a-secure-cluster.md)
- [Module 39: Hardening access to the API](39-hardening-access-to-the-api.md)

The [course overview](../README.md) shows the routes through all four levels and the recommended order.
