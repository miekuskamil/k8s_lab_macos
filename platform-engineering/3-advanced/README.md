# Level 3: Advanced

These modules harden a cluster from its nodes to its supply chain, catch attacks at runtime, and open up the internals of the mesh and the platform tools, in four domains. The security modules run on the [practice cluster](../practice-cluster.md) as timed tasks and follow modules 38 and 39 of [level 2](../2-intermediate/README.md). The internals modules run on the k3d lab, so take them once the [foundations](../1-foundations/README.md) feel familiar.

## Hardening nodes and workloads

- [Module 40: Hardening nodes](40-hardening-nodes.md)
- [Module 41: Hardening workloads](41-hardening-workloads.md)

## Supply chain security

- [Module 42: Supply chain security](42-supply-chain-security.md)

## Runtime security and auditing

- [Module 43: Runtime security and auditing](43-runtime-security-and-auditing.md)

The kernel module task of module 40, the WireGuard task of module 41 and the AppArmor tasks of module 43 run on a VM, so they sit in [module 44](../kernel-and-host/README.md). Take each one after the module it comes from.

## Platform internals

Modules 14 and 21 upgrade the lab one way, so you rebuild it afterwards. Module 32 runs on its own throwaway cluster and never touches the lab's Istio.

- [Module 10: eBPF and Cilium](10-ebpf-and-cilium.md)
- [Module 14: Upgrading Istio](14-upgrading-istio.md)
- [Module 21: k3s certificates, backups, upgrades](21-k3s-lifecycle.md)
- [Module 25: OpenTelemetry Collector and Tempo](25-opentelemetry-and-tempo.md)
- [Module 28: Continuous profiling with Pyroscope](28-continuous-profiling.md)
- [Module 30: Sidecar mode in depth](30-sidecar-in-depth.md)
- [Module 31: Debugging Envoy with istioctl](31-debugging-envoy.md)
- [Module 32: Installing Istio with istioctl](32-installing-istio.md)
- [Module 45: The life of an outbound request](45-life-of-an-outbound-request.md)

## Timed practice exams

- [Timed practice exam 4: security, one topic per task](practice-exam-4.md)
- [Timed practice exam 5: security, when topics collide](practice-exam-5.md)
- [Timed practice exam 6: security, a broken control plane](practice-exam-6.md)

Each exam covers modules 38 to 43 with a 2-hour clock and runs on a freshly reset practice cluster: `./platform-engineering/practice-exam.sh setup 4` starts exam 4. Exams 5 and 6 also use the Lima VM from [module 44](../kernel-and-host/README.md).

The [course overview](../README.md) shows the routes through all four levels and the recommended order.
