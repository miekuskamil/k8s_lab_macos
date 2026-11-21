# Glossary

Every resource and term the course uses, in plain words. Each entry starts with one sentence that says what the thing is for. Then it gives the detail, a small example where that helps, and the module that puts it to work. If a module mentions something and you're not sure what it is, look here first.

- [Find the right resource](#find-the-right-resource)
- [Docker and Compose](#docker-and-compose)
- [The pieces of Istio](#the-pieces-of-istio)
- [Traffic resources](#traffic-resources)
- [Security resources](#security-resources)
- [Observability and operations](#observability-and-operations)
- [Protocols and identity](#protocols-and-identity)
- [Envoy response flags](#envoy-response-flags)
- [Sidecars in depth](#sidecars-in-depth)
- [Debugging Envoy](#debugging-envoy)
- [Installing Istio](#installing-istio)
- [Around the mesh](#around-the-mesh)
- [AI on Kubernetes](#ai-on-kubernetes)
- [Kubernetes operations](#kubernetes-operations)
- [Linux networking under Kubernetes](#linux-networking-under-kubernetes)
- [Outbound traffic and NAT](#outbound-traffic-and-nat)
- [The practice cluster and the security modules](#the-practice-cluster-and-the-security-modules)
- [Applications on Kubernetes](#applications-on-kubernetes)

## Find the right resource

| I want to... | Use | API group | Module |
|---|---|---|---|
| Let traffic into the cluster | Gateway (Gateway API) | `gateway.networking.k8s.io` | 4, 11 |
| Split traffic between versions, match paths or headers | HTTPRoute, or VirtualService | Gateway API, `networking.istio.io` | 4, 16 |
| Inject delays or errors | VirtualService | `networking.istio.io` | 5 |
| Set timeouts and retries | HTTPRoute or VirtualService | both | 5, 15 |
| Limit connections, eject bad pods, set load balancing | DestinationRule | `networking.istio.io` | 5, 15 |
| Call something outside the cluster through the mesh | ServiceEntry | `networking.istio.io` | 12 |
| Require mTLS | PeerAuthentication | `security.istio.io` | 2 |
| Decide who may call what | AuthorizationPolicy | `security.istio.io` | 3, 12, 13 |
| Check end-user tokens (JWT) | RequestAuthentication | `security.istio.io` | 13 |
| Change tracing, metrics or access logs | Telemetry | `telemetry.istio.io` | 6 |

## The pieces of Istio

**Service mesh.** A service mesh is a layer of proxies that handles encryption, identity, routing, retries and measurements for every request between your services. Because the proxies sit in the path of every request, the application code doesn't have to do this work. Module 3.1.

**Data plane.** The data plane is the set of proxies that touch your traffic: ztunnel, waypoints, sidecars and gateways. If the data plane stops, requests stop.

**Control plane.** The control plane is the part of the mesh that only gives orders to the proxies. In Istio, that's istiod. It never sees a request.

**istiod.** istiod is Istio's control plane, one Deployment in `istio-system`, that configures every proxy and signs every workload's identity. It watches the Kubernetes API and turns your Istio and Gateway API resources into proxy configuration. It pushes that configuration out over xDS, and it acts as the certificate authority. Modules 3.1, 3.2, 3.19.

**Envoy.** Envoy is the open-source proxy that does the HTTP work in Istio. Lyft released it in 2016. Sidecars, waypoints and gateways all run Envoy, and its container image goes by the name `proxyv2`.

**Ambient mode.** Ambient mode is Istio's newer data plane design, which works without sidecars. ztunnel on each node handles L4 for every pod, and waypoints handle L7 only where you deploy them. A namespace joins with the label `istio.io/dataplane-mode: ambient`, and its pods need no restart. The lab's `shop` namespace uses it. Module 3.1.

**Sidecar mode.** Sidecar mode is Istio's original design, which adds an Envoy container to every pod to handle both L4 and L7 for that pod. A namespace joins with `istio-injection: enabled` (or `istio.io/rev`). Pods get the sidecar only when they restart. Module 3.9.

**ztunnel.** ztunnel ("zero-trust tunnel") is a small Rust proxy that encrypts and checks the traffic of every mesh pod on its node in ambient mode. It runs once per node, as a DaemonSet. It holds the certificates of every mesh pod on its node, wraps their traffic in mTLS (HBONE), and enforces L4 rules. It never reads HTTP. Modules 3.1, 3.2, 3.3.

**Waypoint.** A waypoint is an Envoy proxy that handles L7 for a namespace or a service in ambient mode. Its jobs include HTTP routing, L7 authorization, retries, faults and HTTP metrics. You create it as a Gateway with `gatewayClassName: istio-waypoint`, and you point traffic at it with the label `istio.io/use-waypoint`. The lab's backend uses one. Modules 3.1, 3.3, 3.4.

**Sidecar.** A sidecar is the Envoy container (`istio-proxy`) that sits inside each pod in sidecar mode and carries all its traffic. An init container, `istio-init`, sets up the iptables rules that send the pod's traffic through it. Modules 3.9 and 3.17. Don't mix it up with the Sidecar resource below.

**istio-cni.** istio-cni is a node agent (DaemonSet) that sends each ambient pod's traffic through ztunnel. It does this by setting up redirect rules inside each mesh pod's network namespace. It also answers pods' DNS when DNS capture is on. Modules 3.2, 3.11, and troubleshooting problems 15 and 18.

**Ingress gateway.** An ingress gateway is an Envoy at the edge of the mesh that accepts traffic from outside the cluster. In this lab, it's `shop-gateway-istio` in `shop-ingress`, created from a Gateway API Gateway. Modules 3.4, 3.10.

**Egress gateway.** An egress gateway is an Envoy that all traffic to the outside world passes through, so one place applies the rules and writes the logs. In ambient mode, a waypoint plays this role. Module 3.11.

**East-west and north-south.** These are names for the two directions of traffic in a cluster. East-west traffic flows between services inside the cluster, through ztunnel and waypoints. North-south traffic enters or leaves the cluster, through the ingress gateway or out to the internet. Module 3.4.

**In-pod redirection.** In-pod redirection is how ambient mode catches a pod's traffic without the traffic leaving the pod. istio-cni adds redirect rules inside each ambient pod's network namespace. ztunnel listens there on ports 15001, 15006, 15008 and 15053, so the pod's traffic reaches ztunnel directly. Modules 3.1 and 3.15.

## Traffic resources

**Gateway (Gateway API).** A Gateway is a Kubernetes-standard resource (`gateway.networking.k8s.io/v1`) that asks for a proxy with listeners, meaning ports, protocols and TLS certificates. Istio sees it and creates an Envoy Deployment and Service for it. The class decides the role. `istio` makes an ingress gateway, and `istio-waypoint` makes a waypoint. Modules 3.4, 3.10.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shop-gateway, namespace: shop-ingress}
spec:
  gatewayClassName: istio
  listeners: [{name: http, port: 8080, protocol: HTTP}]
```

**Gateway (Istio API).** This Gateway is Istio's older resource (`networking.istio.io/v1`) with the same name, which configures gateway pods that already exist. It doesn't create a proxy. It sets ports, hosts and TLS on gateway pods picked with a label `selector`. A VirtualService then attaches to it through its `gateways:` field. Many existing Istio setups and the ICA exam use it. Module 3.14 compares the two.

**GatewayClass.** A GatewayClass is a Gateway API resource that names which implementation runs a Gateway. Istio installs `istio` and `istio-waypoint`.

**HTTPRoute.** An HTTPRoute is a Gateway API resource that holds HTTP routing rules. A rule matches on path, headers or method, then sends to one or more backends with weights. It may also rewrite, redirect, time out or retry. `parentRefs` says what the route attaches to. That is a Gateway for ingress, or a Service for mesh traffic, applied by that Service's waypoint. Modules 3.4, 3.5, 3.10.

```yaml
kind: HTTPRoute
spec:
  parentRefs: [{group: "", kind: Service, name: backend}]
  rules:
    - backendRefs:
        - {name: backend-v1, port: 8000, weight: 90}
        - {name: backend-v2, port: 8000, weight: 10}
```

**VirtualService.** A VirtualService is Istio's own routing resource, the older counterpart of HTTPRoute. It names one or more `hosts`. Then it lists HTTP routes with matches, destinations (`host`, `subset`, `weight`), timeouts, retries, fault injection and mirroring. Gateway API has no fault injection, so module 3.5 uses a VirtualService for it. In ambient mode, the waypoint applies it. Modules 3.5, 3.9, 3.14.

```yaml
kind: VirtualService
spec:
  hosts: [backend]
  http:
    - fault: {delay: {percentage: {value: 100}, fixedDelay: 500ms}}
      route: [{destination: {host: backend}}]
```

**DestinationRule.** A DestinationRule is a resource that says how to talk to a destination *after* routing picked it. It sets these things:

- the load-balancing algorithm
- connection pool limits (`connectionPool`, the circuit breaker)
- ejection of failing pods (`outlierDetection`)
- TLS towards the destination (`tls`)
- named subsets, groups of pods by label such as `v1` and `v2`, that a VirtualService routes to

Modules 3.5, 3.11, 3.13.

```yaml
kind: DestinationRule
spec:
  host: backend
  trafficPolicy:
    connectionPool: {http: {http1MaxPendingRequests: 1, maxRequestsPerConnection: 1}}
  subsets:
    - {name: v1, labels: {version: v1}}
```

**Subset.** A subset is a named group of a service's pods, defined by labels in a DestinationRule. VirtualServices route to subsets. HTTPRoutes use one Service per version instead. Module 3.4.

**ServiceEntry.** A ServiceEntry is a resource that adds a host the mesh doesn't know, usually outside the cluster, to the mesh's service registry. After that, traffic to the host gets names in metrics, routing rules and authorization. `location: MESH_EXTERNAL` marks it as outside, and `resolution: DNS` tells Envoy to look up its IPs. In ambient mode, it needs a virtual IP and DNS capture to reach a waypoint. Module 3.11.

**Sidecar (resource).** The Sidecar resource (`networking.istio.io/v1 Sidecar`) is a resource that limits which hosts one sidecar proxy knows about and may reach. It also sets the outbound policy, for example `REGISTRY_ONLY` to block unknown hosts. It works in sidecar mode only, and ambient has no equivalent. Large sidecar installs use it to cut memory: in module 3.17 it shrank one proxy from 62 clusters to 16 and its Envoy heap by 40%. Module 3.17.

**EnvoyFilter.** An EnvoyFilter is a resource that patches raw Envoy configuration when no Istio resource covers what you need. It is powerful but breaks easily across upgrades, and Istio 1.24 doesn't support it on waypoints. Module 3.5 mentions it.

**ReferenceGrant.** A ReferenceGrant is a Gateway API resource that lets a resource in one namespace point at an object in another. For example, a Gateway may use a TLS Secret from a different namespace. The owner of the target namespace creates it. Module 3.10.

**WorkloadEntry.** A WorkloadEntry is a resource that registers a single non-Kubernetes machine, such as a VM, as a mesh workload. This course doesn't use it.

## Security resources

**PeerAuthentication.** PeerAuthentication (`security.istio.io/v1`) is a resource that says whether a workload accepts plain text. It has three modes:

- `STRICT` accepts mTLS only.
- `PERMISSIVE`, the default, accepts mTLS and plain text, so you enroll workloads gradually.
- `DISABLE` accepts plain text only.

Put it in `istio-system` for the whole mesh, or in a namespace for that namespace. Add a `selector` for single workloads. Modules 3.2, 3.9.

**AuthorizationPolicy.** An AuthorizationPolicy is a resource that decides whether a request may pass. `action` is `ALLOW`, `DENY`, `CUSTOM` (ask an external service) or `AUDIT`. `rules` match on three things:

- `from`, the source identity: `principals`, `namespaces`, `requestPrincipals`
- `to`, the operations: ports, methods, paths
- `when`, extra conditions such as token claims

Where you attach the policy decides who enforces it. A `selector` (pod labels) makes ztunnel enforce the L4 parts. `targetRefs` to a Service, Gateway or ServiceEntry makes that waypoint or gateway enforce L7. Istio evaluates CUSTOM first, then DENY, then ALLOW. Modules 3.3, 3.11, 3.12.

**Principal.** A principal is the workload identity that an AuthorizationPolicy matches, written without the `spiffe://` prefix. Example: `cluster.local/ns/shop/sa/frontend`. Module 3.3.

**RequestAuthentication.** RequestAuthentication is a resource that tells a proxy which end-user tokens (JWTs) to trust. It names the issuer, the audience and the public keys (JWKS). It rejects bad tokens with 401 but lets requests without a token through. An AuthorizationPolicy with `requestPrincipals` makes a token mandatory. Module 3.12.

**Request principal.** A request principal is the end-user identity taken from a checked JWT, written as `<issuer>/<subject>`. Example: `https://idp.k8s-lab.local/alice`. Module 3.12.

## Observability and operations

**Telemetry.** Telemetry (`telemetry.istio.io/v1`) is a resource that turns tracing, metrics and access logs on or off and picks where they go. It applies to the mesh, a namespace or one proxy. The lab sends traces to Jaeger with it. Module 3.6.

**Trace and span.** A trace is the record of one request through every service it touches, and a span is one step inside it. A trace is a tree of spans. Each span records who did the step, when it started and how long it took. All spans of a trace share one trace ID, which travels in the `traceparent` header. Modules 2.4 and 3.6.

**Sampling.** Sampling is keeping only a share of traces, chosen at random when a request enters the mesh. The lab keeps 100%. Production systems often keep 1 to 5%, because storing every trace costs a lot. Module 3.6.

**Access log.** An access log is a file of one line per request, written by a proxy. Each line holds the method, path, status code, response flags, timings and upstream. The lab has it off by default. A Telemetry resource turns it on for the waypoint. Modules 3.3, 3.5, 3.6.

**Reporter.** The reporter is a label on Istio's request metrics that says which proxy recorded them. `source` means the calling side, here the ingress gateway or a client sidecar. The other values are `waypoint` and `destination`, a sidecar on the receiving side. Modules 3.6, 3.9.

**Percentile (p95, p99).** A percentile is the value that a given share of measurements stays under, such as 95% (p95) or 99% (p99). A p95 latency of 200 ms means one request in twenty took longer. Prometheus estimates it from histogram buckets. Buckets are counters of how many requests fell into each time range, 0.5, 1, 5, 10, 25 ms and up for Istio. So the result often lands on a bucket edge. Modules 3.5, 3.6.

**PodMonitor.** A PodMonitor is a prometheus-operator resource that tells Prometheus which pods to scrape, on which port and path. The lab ships PodMonitors for the gateway, the waypoint and ztunnel. Module 3.9 adds one for the sidecars.

**istioctl.** istioctl is Istio's command-line tool for inspecting and checking the mesh. The course uses these commands:

- `proxy-status` shows which proxies use which control plane, and whether their config is current.
- `ztunnel-config` shows what ztunnel knows.
- `proxy-config` shows a sidecar or gateway's Envoy config.
- `analyze` finds mistakes in your resources.
- `x precheck` checks a cluster before an upgrade.

Module 3.8 lists them by layer.

**Revision.** A revision is a name for one installed control plane, such as `1-25-5`. The original install without a name is `default`. Proxies choose a revision with the label `istio.io/rev`. Module 3.19.

**Tag (revision tag).** A revision tag is a movable nickname, such as `default` or `stable`, that points at a revision. Move the tag, and every workload labelled with it follows. Module 3.19.

**Head sampling.** Head sampling is a way of sampling where the first proxy on a request decides once whether to keep its trace. It writes the decision into the `traceparent` header, and every later hop follows that decision. Module 3.6.

## Protocols and identity

**L4 and L7.** L4 and L7 are layers of the network model that a proxy looks at. L4 means connections, that is IP addresses and ports (TCP). L7 means the application protocol, here HTTP, with methods, paths, headers and status codes. ztunnel works at L4. Waypoints and sidecars work at L7.

**mTLS (mutual TLS).** mTLS is a form of TLS where both sides show a certificate, so each proves its identity to the other. Both sides also encrypt the traffic. Every connection between mesh workloads uses it. Module 3.2.

**SPIFFE ID.** A SPIFFE ID is the identity inside a mesh certificate, written as a URI such as `spiffe://cluster.local/ns/shop/sa/frontend`. Its parts are the trust domain, the namespace and the service account. Module 3.2.

**Trust domain.** The trust domain is the first part of a SPIFFE ID (`cluster.local` here). Workloads trust certificates from the same trust domain.

**HBONE.** HBONE ("HTTP-Based Overlay Network Environment") is the encrypted tunnel that ztunnel and waypoints use between pods. It is one mTLS connection on port 15008 that carries many TCP streams as HTTP/2 CONNECT requests. Module 3.2.

**xDS.** xDS is the family of APIs that istiod uses to push configuration to proxies. Each letter names one kind of configuration:

- LDS: listeners
- RDS: routes
- CDS: clusters, meaning upstream services
- EDS: endpoints, meaning pod IPs
- SDS: secrets, meaning certificates

ztunnel uses Istio's own WDS and WADS (workloads and addresses). You see these letters in `istioctl proxy-status`. Modules 3.1, 3.10.

**SNI (Server Name Indication).** SNI is the name a client sends at the start of a TLS handshake, so one IP address serves many sites with different certificates. Module 3.10.

**TLS termination and origination.** These are the two ways a proxy handles TLS for someone else. Termination means a proxy ends a TLS session and reads the request inside, like the ingress gateway in module 3.10. Origination means a proxy starts a TLS session on the app's behalf, so the app sends plain HTTP, like the waypoint in module 3.11.

**X-Forwarded-Client-Cert (XFCC).** XFCC is a header that a sidecar adds to requests it passes to its app, so the app learns who called without touching TLS. It names the caller (`URI=spiffe://...`) and the receiver (`By=...`) from the mTLS handshake. Module 3.9.

**DNS capture.** DNS capture is an ambient-mode feature where istio-cni redirects a pod's DNS queries to ztunnel. ztunnel answers for ServiceEntry hosts with their virtual IP. Module 3.11.

**Subject Alternative Name (SAN).** The SAN is the list of names inside a certificate. A TLS client compares it with the host name it connected to. Istio puts the workload's SPIFFE ID there. Modules 3.10 and 3.15.

**Trust store.** A trust store is the set of CA certificates a client trusts, such as curl's built-in list or a file passed with `--cacert`. A certificate is trusted only if its chain ends at one of them. Module 3.10.

## Envoy response flags

Envoy writes a short flag into access logs and the `response_flags` metric label when Envoy itself, rather than your app, caused or shaped the response. Here are the flags this course meets:

| Flag | Meaning | Typical cause |
|---|---|---|
| `UO` | Upstream overflow | The circuit breaker (`connectionPool`) rejected the request |
| `UF` | Upstream connection failure | The target pod refused or dropped the connection |
| `UH` | No healthy upstream | No ready pods behind the service, or all ejected |
| `URX` | Upstream retry limit exceeded | Retries ran out |
| `UT` | Upstream request timeout | A route timeout fired |
| `DI` | Delay injected | Fault injection added a delay |
| `FI` | Fault injected | Fault injection returned an error |
| `NR` | No route | No route matched the request |
| `NC` | No cluster | The route points at a Service Envoy has no cluster for, for example a misspelled or deleted one (module 3.4) |
| `DC` | Downstream connection termination | The caller hung up early |
| `-` | No flag | Envoy passed the response on unchanged |

Modules 3.4, 3.5, 3.6, 3.7, 3.18. A flag appears in the log of the proxy that hit the problem, so check both sides: in module 3.18, `UF` showed only in the server's sidecar log.

## Sidecars in depth

**Injection webhook.** The injection webhook is the mutating admission webhook in istiod that adds `istio-init` and `istio-proxy` to a new pod. istiod registers four of them, each with its own namespace and pod selectors, for `istio-injection=enabled`, `istio.io/rev`, and pods that opt in themselves. A webhook runs only when a pod is created, so running pods need a restart. Module 3.17.

**sidecar.istio.io/inject.** `sidecar.istio.io/inject` is a pod label that overrides the namespace for one pod: `false` keeps the sidecar out, and `true` asks for one in an unlabelled namespace. As a label, it stops the webhook call itself. The same key as an annotation only works inside istiod, so `istioctl x check-inject` misses it. Module 3.17.

**istioctl x check-inject.** `check-inject` is an istioctl command that reads the injection webhooks' selectors and says whether a pod or Deployment gets a sidecar, and which label decides it. Module 3.17.

**istio-init.** istio-init is the init container that writes the pod's iptables NAT rules and exits before the app starts. It needs the `NET_ADMIN` and `NET_RAW` capabilities. In Istio 1.24, it writes the legacy iptables back end, so `iptables-legacy-save` shows the rules. Modules 3.9 and 3.17.

**Traffic capture.** Traffic capture is how a sidecar pod's connections reach Envoy without the app knowing. NAT rules redirect outgoing TCP to port 15001 and incoming TCP to port 15006. Traffic from user ID 1337, Envoy's own, and a few ports (15008, 15090, 15021, 15020) skip the redirect. Module 3.17.

**istio-validation.** istio-validation is the init container a sidecar pod gets when the Istio CNI plugin writes the redirect rules instead of `istio-init`. It only checks that the rules work, so the pod needs no extra capabilities. istiod uses it when `pilot.cni.enabled` is on. Modules 3.17 and 3.20.

**Exclude annotations.** `traffic.sidecar.istio.io/excludeOutboundPorts`, `excludeInboundPorts` and `excludeOutboundIPRanges` are pod annotations that tell istio-init to leave some traffic alone, so it bypasses Envoy and loses mTLS, routing and metrics. Module 3.17.

**Proxy resource annotations.** `sidecar.istio.io/proxyCPU`, `proxyMemory`, `proxyCPULimit` and `proxyMemoryLimit` are pod annotations that set the injected `istio-proxy` container's requests and limits. The lab's default is 100m CPU and 128Mi memory requested. Module 3.17.

**Outbound traffic policy.** The outbound traffic policy decides what a sidecar does with a destination it doesn't know. `ALLOW_ANY`, the default, passes it on. `REGISTRY_ONLY` blocks it. It lives in mesh config (module 3.20) or in a Sidecar resource (module 3.17).

**PassthroughCluster and BlackHoleCluster.** These are two built-in Envoy clusters for unknown destinations. PassthroughCluster sends the connection on unchanged, with no mTLS, routing or metrics. BlackHoleCluster drops it. Access logs name them in the upstream cluster field. Modules 3.17 and 3.18.

**pilot-agent.** pilot-agent is the process that starts Envoy inside `istio-proxy`, fetches its certificate and relays its config. `pilot-agent request GET <path>` calls Envoy's admin API from inside the pod, for example `config_dump` or `memory`. Module 3.17.

## Debugging Envoy

**Listener (Envoy).** A listener is a socket plus a chain of filters inside Envoy, the first of four lookups for each request. It answers "which port, and how do I read it?" A sidecar has one outbound listener per HTTP port, one per TCP Service IP and port, and the catch-all `virtualOutbound` (15001) and `virtualInbound` (15006). Module 3.18.

**Route (Envoy).** A route is Envoy's table of HTTP rules for one listener port, grouped by virtual host. It picks a cluster by host, path and headers. istiod builds it from Services, VirtualServices and HTTPRoutes. Module 3.18.

**Cluster (Envoy).** A cluster is Envoy's name for a pool of upstream servers with its own load balancing, connection limits and TLS settings. Its name has four fields, such as `outbound|8000|v1|httpbin.course-debug.svc.cluster.local`: direction, port, subset and host. DestinationRules shape it. Module 3.18.

**Endpoint (Envoy).** An endpoint is one member of a cluster, a pod IP and port with a health status. istiod builds endpoints from EndpointSlices and sends them over EDS. Module 3.18.

**xDS sync state.** The xDS sync state is istiod's record of whether a proxy acknowledged the latest config of each kind. `SYNCED` means it did, `STALE` means istiod sent newer config that the proxy hasn't acknowledged yet, and `NOT SENT` means there was nothing to send. `istioctl proxy-status -o json` prints it per kind. Module 3.18.

**Response code detail.** The response code detail is the longer reason after the response flag in an access log line, such as `no_healthy_upstream`, `route_not_found` or `rbac_access_denied_matched_policy[...]`. `via_upstream` means the app sent the response and Envoy only passed it on. Module 3.18.

**istioctl analyze.** `istioctl analyze` is a command that checks Istio resources in the cluster, or in files before you apply them, against known mistakes. Each finding has a code such as `IST0101` (missing host or subset), `IST0109` (two VirtualServices for one host) or `IST0173` (a subset that selects no pod). It exits with code 79 on errors. Modules 3.14 and 3.18.

**istioctl x describe pod.** `istioctl x describe pod` starts from one sidecar pod and lists the Service, DestinationRule, VirtualService and PeerAuthentication that affect it, with warnings such as a route to an unknown subset. It only understands sidecar pods. Modules 3.9 and 3.18.

**Envoy log level.** Envoy has one logger per area, such as `router`, `connection`, `rbac` and `upstream`, each with its own level. `istioctl proxy-config log <pod> --level router:debug` changes a level on the running proxy, and `--reset` sets all of them back to `warning`. Module 3.18.

## Installing Istio

**Install profile.** An install profile is a named set of defaults for `istioctl install` that says which Istio components to turn on and how to size them. `minimal` installs istiod only, `default` adds an ingress gateway, `demo` adds an egress gateway with small requests and access logs, and `ambient` adds istio-cni and ztunnel. Module 3.20.

**IstioOperator.** IstioOperator (`install.istio.io/v1alpha1`) is the file format `istioctl install` reads, with three main sections: `meshConfig`, `components` and `values`. Since Istio 1.24, no operator runs in the cluster and nothing stores the file there, so keep it in Git. Module 3.20.

**meshConfig.** meshConfig is the set of mesh-wide settings that istiod reads from the `istio` ConfigMap and pushes to every proxy, such as `accessLogFile`, `outboundTrafficPolicy` and `defaultConfig`. A change reaches running proxies without a restart. Module 3.20.

**ProxyConfig and holdApplicationUntilProxyStarts.** ProxyConfig is the startup configuration of each proxy, set mesh-wide under `meshConfig.defaultConfig` or per pod with the `proxy.istio.io/config` annotation. Its field `holdApplicationUntilProxyStarts: true` makes the injector put `istio-proxy` first and hold the app until Envoy is ready. Modules 3.9 and 3.20.

**istioctl install.** `istioctl install` merges a profile, IstioOperator files and `--set` flags, renders Istio's Helm charts, applies the result and prunes what the new config drops. Each run describes the whole desired state, so a run without your file resets your settings. Module 3.20.

**istioctl manifest generate and translate.** `manifest generate` prints the YAML `istioctl install` would apply, without touching a cluster. `manifest translate` turns an IstioOperator file into Helm values files, for a move from istioctl to Helm. Module 3.20.

**istioctl uninstall --purge.** `istioctl uninstall --purge` removes every Istio component and the CRDs from a cluster. It leaves the `istio-system` namespace in place. Module 3.20.

**Platform setting and cniBinDir.** `values.global.platform` (for example `k3s`) adjusts paths and defaults for one Kubernetes distribution. On k3d, istio-cni also needs `values.cni.cniBinDir` set to the folder containerd searches, read from the node's containerd config, or new pods fail with `failed to find plugin "istio-cni"`. Modules 3.19 and 3.20.

## Around the mesh

**Gateway API.** Gateway API is the Kubernetes project's standard API for traffic routing. It includes Gateway, HTTPRoute, GatewayClass and ReferenceGrant, and Istio, Cilium, Envoy Gateway and others implement it. Istio recommends it over its own VirtualService and Istio Gateway for new setups. It's the main API in ambient mode.

**cert-manager.** cert-manager is a Kubernetes controller that issues and renews TLS certificates. An Issuer or ClusterIssuer says who signs. A Certificate says what you want, and the result lands in a Secret. Module 3.10.

**JWT and JWKS.** A JWT (JSON Web Token) is a token that carries signed claims about a user. A JWKS (JSON Web Key Set) publishes the public keys that check those signatures. Module 3.12.

**NetworkPolicy.** NetworkPolicy is a plain Kubernetes resource that allows or blocks connections by pod labels, namespaces and IP ranges. The node's packet filter enforces it, below the mesh. Module 3.11 uses one to force traffic through the waypoint.

**Idempotent request and idempotency key.** An idempotent request is a request that has the same effect whether you send it once or twice, like a GET. A POST that creates an order is not idempotent. An idempotency key is a unique ID the client sends with such a request, so the server spots a repeat and skips it. Safe retries depend on this. Module 3.5.

**Loki and LogQL.** Loki is a log store that keeps costs low by indexing only a few labels per stream (namespace, app, pod), not the text. LogQL is its query language:

- `{app="backend"}` picks streams.
- `|= "text"` filters lines.
- `| json` turns JSON fields into labels.
- `count_over_time`, `rate` and `unwrap` turn lines into numbers.

Modules 2.3 and 3.6.

**Log stream.** A log stream is one set of labels in Loki together with every line that carries it, such as `{namespace="course-logs", app="orders"}`. Each new label value starts a new stream, so a label with many values, like an order id, makes the index grow with every line. Module 2.3.

**Alloy.** Alloy is Grafana's collector that runs on every node, tails each container's log file and sends the lines to Loki with labels for the namespace, app and pod. Module 2.3.

**Kiali.** Kiali is the Istio console that shows a traffic graph, mTLS status and config checks. It works next to the other observability tools in the lab:

- Jaeger shows traces.
- Prometheus stores metrics.
- Grafana shows dashboards and runs queries over Prometheus, Loki and Jaeger.
- Loki stores logs.

Module 3.6.

**eBPF.** eBPF is a way to load small programs into the Linux kernel at runtime, after a verifier checks they are safe. Cilium uses them for fast packet handling, policy and tracing. Module 3.21.

**Cilium.** Cilium is a CNI plugin that uses eBPF for pod networking, Service load balancing and network policy. It hands Layer 7 rules to an Envoy per node. Module 3.21.

**Kernel space and user space.** These are the two places where code runs on a Linux machine. The kernel owns network interfaces and the packet filter. Ordinary programs such as Envoy and ztunnel run in user space and reach the network through sockets, which costs copies and context switches. Module 3.21.

## AI on Kubernetes

**LLM (large language model).** An LLM is a model that reads text and writes text, such as Qwen, Llama or Claude. "14B" in a model name means 14 billion parameters. Bigger models answer better and run slower. Modules 5.1 to 5.3.

**Ollama.** Ollama is a tool that downloads open models and serves them over a small HTTP API on port 11434. The API has `/api/chat`, `/api/tags`, `/api/pull` and `/api/delete`. It has no authentication. Modules 5.1, 5.2.

**Token.** A token is the unit a model reads and writes, a piece of a word of about four characters of English. Hosted models bill per token, input and output separately. Token counts belong on every dashboard for AI traffic. Module 5.1.

**Prompt.** A prompt is everything a model receives: instructions (the system prompt), data and the question. Module 5.1.

**RAG (retrieval-augmented generation).** RAG is a method that fetches real data first, puts it into the prompt and then asks the model. That way, the model answers from your data instead of from memory. The shop assistant does this with orders (module 5.1). Module 5.4 builds a full one over the course, with a vector database. Modules 5.1 and 5.4.

**GenAI semantic conventions.** The GenAI semantic conventions are OpenTelemetry's standard attribute names for model calls. Examples are `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens`. Tools like Jaeger and Grafana read them the same way whatever the model. Module 5.1.

**AI gateway.** An AI gateway is a proxy built for model traffic. It counts rate limits in tokens, switches between model providers, caches prompts and filters what goes in and out. Examples are agentgateway, kgateway and Envoy AI Gateway. Module 5.1.

**Inference.** Inference is running a trained model to get an answer, as opposed to training it. A model server like Ollama or vLLM does inference. Module 5.2.

**Model server.** A model server is the program that loads a model and answers requests over HTTP. Examples are Ollama, llama.cpp, vLLM and NVIDIA Triton. Module 5.2 runs llama.cpp.

**GGUF.** GGUF is the model file format that llama.cpp and Ollama read. One file holds the whole model. It is often shrunk ("quantised", the `q4_k_m` in a file name) to fit in less memory. Module 5.2.

**OpenAI-compatible API.** The OpenAI-compatible API is the request format OpenAI made popular, `POST /v1/chat/completions` with the model name in the JSON body. Most model servers and AI tools speak it. Module 5.2.

**Gateway API Inference Extension.** The Gateway API Inference Extension is a Kubernetes standard for routing requests to model servers. An InferencePool groups model server pods. An endpoint picker chooses a pod by the servers' own metrics, such as queue length, instead of round robin. Istio supports it from 1.27. Module 5.2.

**AI agent.** An AI agent is a program that lets a model act. It sends the model a question plus a list of tools. It runs the tool calls the model asks for, feeds back the results, and repeats until the model answers. Module 5.3.

**Tool.** A tool is a function that an agent offers its model, such as "list pods" or "delete a resource". It comes with a description the model reads to decide when to use it. Module 5.3.

**MCP (Model Context Protocol).** MCP is the standard way for agents to reach tools. It uses JSON-RPC over HTTP, with every call sent to one URL (`/mcp`) and the tool name inside the JSON body. A tool server describes its tools and runs them. Module 5.3.

**A2A (Agent2Agent).** A2A is a protocol that lets clients and agents send tasks to an agent and get results back. kagent serves it on its controller, port 8083. Module 5.3.

**kagent.** kagent is a CNCF Sandbox project that runs AI agents on Kubernetes. Agents, models (ModelConfig) and tool servers (RemoteMCPServer) are custom resources. Module 5.3.

**Prompt injection.** Prompt injection is text that reaches a model through data and carries instructions the model may follow. The data might be a log line, a web page or a pod annotation. No model resists it reliably. Module 5.3.

**Excessive agency.** Excessive agency is an agent holding more tools or permissions than its job needs. Then a mistake, a prompt injection or a direct call to its tools does real damage. It is on the OWASP Top 10 for LLM applications. Module 5.3.

**Prefill and decode.** Prefill and decode are the two phases of a model's answer. Prefill reads the whole prompt in one pass. Decode then writes the answer one token at a time, so the output length decides how long the user waits. Module 5.1.

**Tool calling.** Tool calling is a model skill where the model answers with a tool name and JSON arguments instead of text. The agent program runs that call and sends back the result. Module 5.3.

**Confused deputy.** A confused deputy is a program with strong rights that acts for a caller with weak ones. An example is a tool server with wide RBAC rights that answers any agent user. Module 5.3.

## Kubernetes operations

**Cordon, drain, uncordon.** These are the three commands that take a node out of service and bring it back. Cordon marks a node unschedulable. Drain cordons it and evicts its pods one by one, respecting PodDisruptionBudgets, and DaemonSet pods stay. Uncordon makes it schedulable again, but moves nothing back. Module 2.8.

**PodDisruptionBudget (PDB).** A PDB is a rule like "keep at least one `web` pod running" that evictions must respect. It covers voluntary disruptions such as drains and upgrades, not crashes. Module 2.8.

**DaemonSet.** A DaemonSet is a workload that runs one pod on every node, such as ztunnel, istio-cni or a log shipper. Drains leave these pods alone. Module 2.8.

**`ttlSecondsAfterFinished` and `revisionHistoryLimit`.** These are two settings that clean up old objects. The first deletes a finished Job after a delay. The second caps how many old ReplicaSets a Deployment keeps for `kubectl rollout undo` (default 10). Module 2.8.

**ServiceLB (svclb).** ServiceLB is k3s's built-in load balancer, which gives each Service of type LoadBalancer an external IP. It uses the node's IP as that external IP, and it runs a small `svclb-...` pod with a host port that forwards to the Service. kube-proxy also writes a rule for that external IP, and the kernel checks kube-proxy's rules first. So in this lab, kube-proxy DNATs the traffic straight to the gateway pod, and the svclb pod's rule stays unused. Modules 3.1 and 3.15.

**k3s.** k3s is a small Kubernetes distribution in one binary. It brings its own containerd, flannel, and an SQLite or etcd datastore. The lab runs it inside Docker with k3d. Modules 2.8, 2.9.

**k3d.** k3d runs k3s inside Docker, with each k3s node as a container and a small load balancer container in front, so a whole cluster starts in seconds on a laptop. The lab is the k3d cluster `k8s-lab`, and module 3.20 builds a second one to throw away.

**Toolbox.** The toolbox is a container that holds every command-line tool the lab uses, such as kubectl, helm, k3d, kind and istioctl, at the versions the course was tested with. `./lab.sh shell` starts it and opens a shell inside it, so your machine needs only Docker and git. The clusters still run on your own Docker engine, which the toolbox reaches through the Docker socket.

**system-upgrade-controller.** The system-upgrade-controller is a controller that upgrades k3s (and RKE2) nodes from a `Plan` resource. The Plan sets the target version, the node selector, how many nodes at once, and whether to cordon or drain. Module 2.9.

**Certificate rotation and renewal.** These are two ways to keep certificates valid. Rotation replaces a certificate's key, and renewal extends its expiry. k3s renews certificates within 120 days of expiry each time it starts, and `k3s certificate rotate` rotates them. Module 2.9.

**CNI plugin directory.** The CNI plugin directory is the folder where containerd looks for network plugins (`bin_dir` or `bin_dirs` in its config). istio-cni must place its plugin there. The k3s upgrade in module 2.9 moved it. Module 2.9.

**host-local IPAM.** host-local IPAM is flannel's IP address manager, which hands out pod addresses from the node's range. It keeps one lease file per pod address on the node. It frees the address when the CNI chain's DEL runs. Module 2.9.

## GitOps and ArgoCD

**GitOps.** GitOps is a way of running a cluster from Git. Git holds the desired state, and an agent inside the cluster keeps the live state matching it. Changes go through commits, and rollbacks through `git revert`. ArgoCD and Flux are the common agents. Module 2.6.

**Application.** An Application is ArgoCD's resource that links one path in one Git repository to one namespace in one cluster. It also holds a sync policy. Module 2.6.

**AppProject.** An AppProject is an ArgoCD resource that groups Applications and limits what they may do. It sets which repositories, which destination namespaces and which kinds of resources they may use. It is ArgoCD's RBAC for teams. Module 2.6.

**ApplicationSet.** An ApplicationSet is an ArgoCD resource that generates Applications from a template and a generator. A generator is a list, the folders in a repository, the clusters ArgoCD knows, or open pull requests. Module 2.6.

**Sync status and health status.** These are ArgoCD's two separate verdicts on an Application. Sync says whether the cluster matches Git (`Synced`, `OutOfSync`). Health says whether the app works (`Healthy`, `Progressing`, `Degraded`). They're independent, so a broken release is `Synced` and `Degraded`. Module 2.6.

**Drift, self-heal and prune.** Drift is any difference between Git and the cluster, like a manual `kubectl scale`. With `selfHeal`, ArgoCD undoes it. With `prune`, ArgoCD deletes resources that left Git. Module 2.6.

**Sync wave and hook.** These are ArgoCD's two ways to control the order of a sync. A wave (annotation `argocd.argoproj.io/sync-wave`) orders resources. Lower waves go first, and each wave must be healthy before the next. A hook (`argocd.argoproj.io/hook`) runs a resource, usually a Job, at a phase of the sync, such as PreSync for a database migration. Module 2.6.

**Kustomize base and overlay.** These are the two layers Kustomize uses to share manifests between environments. A base holds the shared manifests. An overlay, one per environment, points at the base and changes only what differs, like replicas or an image tag. `kubectl apply -k` and ArgoCD render it without extra tools. Module 2.6.

**Refresh and reconcile.** These are how ArgoCD compares Git with the cluster. ArgoCD reconciles each Application every 3 minutes by default. It fetches Git, renders the manifests and compares them with the cluster. A refresh does the same at once. You trigger it with the `argocd.argoproj.io/refresh` annotation, the UI button or a Git webhook. Module 2.6.

**Sync operation.** A sync operation is one ArgoCD sync attempt, stored in `status.operationState`. It holds a fixed Git revision that stays the same through all its retries. Module 2.6.

## Metrics and alerting

**Counter, gauge and histogram.** These are the three common metric types:

- A counter only goes up, like requests served. It means something through `rate()`.
- A gauge goes up and down, like memory in use.
- A histogram counts observations into buckets, labelled `le` ("less than or equal"). You estimate percentiles from it with `histogram_quantile()`.

Module 2.1.

**`rate()` and `sum by`.** These are the two most common PromQL functions. `rate(x[1m])` turns a counter into a per-second speed over the last minute. `sum by (label)` adds series up and keeps only the labels you name. Module 2.1.

**Recording rule.** A recording rule is a query that Prometheus evaluates on a schedule and stores as a new series. Dashboards and alerts then read a cheap precomputed value. It is named `level:metric:operation`, like `shop:backend_error_ratio:rate5m`. Module 2.1.

**Alerting rule, pending and firing.** An alerting rule is a query that defines "broken". When it returns a result, the alert turns `pending`. After it has held for the rule's `for:` duration, it turns `firing` and goes to Alertmanager. Module 2.1.

**Alertmanager: route, receiver, grouping, silence.** These are the parts of Alertmanager that decide who hears about an alert. A route matches alerts by label and sends them to a receiver, such as Slack, PagerDuty or a webhook. Grouping folds many alerts into one message. A silence mutes matching alerts for a time window without changing the rules. Module 2.1.

**AlertmanagerConfig and PrometheusRule.** These are Prometheus operator resources that let teams keep alerting config next to their apps. A PrometheusRule holds recording and alerting rules. An AlertmanagerConfig holds a team's routes and receivers. The operator merges both into the running configuration. Module 2.1.

**SLI, SLO and error budget.** These are the three numbers behind a reliability target. An SLI (service level indicator) measures what users experience, such as the share of requests without a 5xx. An SLO (service level objective) is the target for it, such as 99%. The error budget is what the target leaves over (1%), the amount of failure you accept. Module 2.1.

**Burn rate.** Burn rate is how fast you spend the error budget. A burn rate of 1 uses it up exactly by the end of the SLO period, and 14.4 uses it 14.4 times faster. Multi-window burn-rate alerts check a long and a short window together. Module 2.1.

**Cardinality.** Cardinality is the number of distinct series a metric produces, where every combination of label values counts once. High-cardinality labels, like user IDs, blow up Prometheus' memory. Module 2.1.

**Time series.** A time series is one metric name with one exact set of labels, holding a timestamped value from every scrape. Change one label value, and you get a new series. Module 2.1.

**Instant vector and range vector.** These are the two shapes of PromQL data. An instant vector holds each series' newest sample. A range vector, such as `[1m]`, holds every sample in a window. `rate()` needs a range vector with at least two samples in it. Module 2.1.

**Head block.** The head block is the newest two hours or so of samples, which Prometheus keeps in memory before it writes them to disk. Module 2.1.

## Grafana

**Provisioned dashboard.** A provisioned dashboard is a dashboard that Grafana loads from a file instead of its database. Grafana refuses to save changes to it, because the next load would overwrite them. You change the file in Git instead. Module 2.2.

**Dashboard sidecar.** The dashboard sidecar is a small container in the Grafana pod that loads dashboards from ConfigMaps. It watches every namespace for ConfigMaps labelled `grafana_dashboard: "1"`. It writes their JSON where Grafana's provisioning picks it up. Module 2.2.

**Panel, variable and threshold.** These are the building blocks of a Grafana dashboard. A panel is one visualisation with its query. A variable is a dropdown that panels use as `$name`, so one dashboard serves many services. A threshold colours a value by where it sits, like red below 99%. Module 2.2.

**Contact point and notification policy.** These are Grafana alerting's versions of Alertmanager receivers and routes. The default contact point sends email to a placeholder address. So new Grafana alerts reach nobody until you change it. Module 2.2.

**Trace-to-logs link (derived field).** A trace-to-logs link is a setting on Grafana data sources that lets you jump between Jaeger and Loki by trace ID. It adds "Logs for this span" in a trace. It also adds "Open trace in Jaeger" next to a `trace_id` in a log line. Modules 3.6 and 2.2.

## OpenTelemetry and Tempo

**OpenTelemetry (OTel) and OTLP.** OpenTelemetry is the CNCF standard for telemetry, so you instrument an app once and then choose back ends freely. It has SDKs for every language, one protocol, and the Collector. The protocol is OTLP, on gRPC port 4317 and HTTP port 4318. Module 2.4.

**OpenTelemetry Collector.** The OpenTelemetry Collector is a service that receives, processes and exports telemetry. Its components are wired together in pipelines:

- receivers take data in
- processors change it
- exporters send data out
- connectors turn one pipeline's output into another's input, such as traces into metrics

It runs as a gateway Deployment, a per-node DaemonSet, or both. Module 2.4.

**Resource and span attributes.** These are the two kinds of labels on telemetry. Resource attributes describe who sent it: service, pod, node, image. Span attributes describe one operation, such as an HTTP status or a database statement. In TraceQL they're `resource.` and `span.`. Module 2.4.

**Semantic conventions.** Semantic conventions are OpenTelemetry's agreed attribute names, like `http.response.status_code`. They change between versions, so older instrumentation may still send `http.status_code`. Module 2.4.

**Grafana Tempo and TraceQL.** Tempo is a trace store that keeps traces cheaply in object storage, without indexing every attribute. TraceQL queries them by attributes, duration and structure. Examples are `{ span.http.status_code >= 500 }`, or `{ A } >> { B }` for spans of B below spans of A. Module 2.4.

**Span metrics.** Span metrics are request rate, errors and duration calculated from spans, here by the Collector's `span_metrics` connector. They give RED metrics to apps that export no metrics of their own. Module 2.4.

**Tail sampling.** Tail sampling is deciding which traces to keep after they're complete, so you keep every error trace and a fraction of the rest. It needs all spans of a trace in one place, which is a job for the Collector. Module 2.4.

**Context propagation and `traceparent`.** Context propagation is passing the trace ID and the parent span ID from service to service, so spans join into one trace. The IDs travel in the W3C `traceparent` header. Modules 3.6 and 2.4.

## Policy as code

**Admission webhook.** An admission webhook is a service that the API server calls before it stores an object, so outside tools add their own checks. Mutating webhooks change the object first. Then validating webhooks allow or refuse it. `failurePolicy: Fail` refuses requests while the webhook is down, and `Ignore` lets them through. Module 2.7.

**Kyverno.** Kyverno is a CNCF policy engine for Kubernetes, configured with YAML policies. A `ClusterPolicy` holds rules that validate (Audit reports, Enforce refuses), mutate, generate or verify images. Kyverno 1.18 adds CEL-based types such as `ValidatingPolicy`. Module 2.7.

**Autogen.** Autogen is a Kyverno feature that copies a rule written for Pods to Deployments, ReplicaSets, Jobs and CronJobs. So a bad Deployment gets refused when you apply it, not when its pods start. Module 2.7.

**PolicyReport.** A PolicyReport is a Kubernetes object that lists which resources pass, fail or skip each policy, per namespace. It is the evidence for an audit. Module 2.7.

**PolicyException.** A PolicyException is a written exception to named policy rules for named resources. In this lab, only the `kyverno` namespace accepts them, so teams don't get to exempt themselves. Module 2.7.

**CEL and ValidatingAdmissionPolicy.** CEL (Common Expression Language) is a small expression language that Kubernetes uses for validation rules. ValidatingAdmissionPolicy is Kubernetes' built-in, webhook-free policy type written in CEL. OPA Gatekeeper is the other common policy engine, with policies in Rego. Module 2.7.

**Background scan.** A background scan is Kyverno's regular re-check of stored objects against its policies. It writes reports and refuses nothing. Module 2.7.

## Retrieval-augmented generation

**Embedding and embedding model.** An embedding is a list of numbers that places a text so that similar meanings land close together. `nomic-embed-text` makes lists of 768 numbers. An embedding model produces them. Vectors from different embedding models aren't comparable. Module 5.4.

**Vector database and cosine similarity.** A vector database is a database that stores embeddings and quickly finds the nearest ones to a new vector. Examples are Qdrant, Weaviate, Milvus, or Postgres with pgvector. Cosine similarity measures closeness, 1 for the same direction and 0 for unrelated. Module 5.4.

**Chunking and top-k.** These are the two settings that decide what text reaches the model in RAG. Chunking splits documents into passages before embedding them, ideally one idea per chunk. Top-k is how many of the nearest chunks go to the model. More chunks mean fewer retrieval misses and more input tokens. Module 5.4.

**Temperature.** Temperature is a setting that controls how random a model's word choice is. At 0, the model always picks the most likely next word, so the same question gets the same answer. Module 5.4.

**Evaluation set.** An evaluation set is a list of questions with known answers and expected sources, like a test suite for a RAG system. You run it after every change to chunking, models or prompts. Module 5.4.

**HNSW.** HNSW is a graph index that lets a vector database find near neighbours approximately, without comparing the query with every stored vector. Module 5.4.

## Continuous profiling

**Profile and pprof.** A profile is a record of where a program spends CPU or allocates memory, as sampled call stacks. pprof is Go's built-in profiler and its file format, served at `/debug/pprof`. Module 2.5.

**Continuous profiling.** Continuous profiling is collecting low-rate profiles from every service all the time, so you look back at a spike instead of reproducing it. People call profiles the fourth signal, after metrics, logs and traces. Module 2.5.

**Flame graph, self and total.** A flame graph is a picture of call stacks as bars, each as wide as its share of samples, one level below its caller. Self counts samples inside the function, and total counts samples anywhere below it. Look for the widest total bar that's your own code. Module 2.5.

**Grafana Pyroscope.** Pyroscope is a continuous profiling database that stores pprof data and shows flame graphs in Grafana. Agents such as Alloy pull profiles from annotated pods, SDKs push them, and eBPF profilers sample whole nodes. Module 2.5.

**alloc_space and inuse_space.** These are two views of a Go memory profile. `alloc_space` counts every byte allocated in a time window, even memory freed right away. `inuse_space` counts what's still held. Module 2.5.

**Sampling profiler.** A sampling profiler is a profiler that records the call stack at fixed intervals instead of tracing every call. Here it samples 100 times a second, which costs little enough to run all the time. Module 2.5.

## How Kubernetes works inside

**Reconcile loop, watch and informer.** The reconcile loop is the cycle every controller runs to make what exists match what should exist. The controller watches the API server for the objects it cares about, compares, and acts to close the gap, over and over. A watch is the open connection that streams those changes. An informer is the client-side cache a controller builds from its watch. Module 3.15.

**Owner reference and garbage collector.** An owner reference is a field that links an object to the one that created it, such as Pod to ReplicaSet to Deployment. When the owner goes, the garbage collector deletes what it owned. Module 3.15.

**Scheduler: filter, score, bind, preemption.** The scheduler is the component that picks a node for each new pod. It works in phases:

1. Filter drops nodes that don't fit, because of resource requests, taints or selectors.
2. Score ranks the rest.
3. Bind writes `spec.nodeName`.

With no node left, preemption may evict lower-priority pods. The scheduler counts requests, never limits. Module 3.15.

**Authentication, authorization, admission.** These are the API server's gates, which every request passes in this order:

1. Authentication asks who you are, using certificates or tokens.
2. Authorization asks whether you may do this, using the Node authorizer and RBAC.
3. Admission asks whether the object should change or be refused, using admission plugins and webhooks.

Members of `system:masters` skip RBAC. Module 3.15.

**etcd and kine.** etcd is the key-value store that holds every Kubernetes object in most clusters, replicated with the Raft protocol. k3s uses kine instead by default. kine speaks the etcd API to the API server and stores the data in SQLite. Modules 2.9 and 3.15.

**CRI, sandbox and CNI.** These are the three pieces that start a pod on a node. The kubelet talks to the container runtime (containerd) through the CRI, the Container Runtime Interface. The runtime first creates a sandbox, a `pause` container that owns the pod's network namespace. Then it runs the CNI (Container Network Interface) plugins, here flannel and then istio-cni, to give the pod an IP and network rules. Module 3.15.

**EndpointSlice.** An EndpointSlice is the list of ready pod IPs behind a Service. kube-proxy, CoreDNS and istiod all read it. Module 3.15.

**DNAT and conntrack.** DNAT (destination network address translation) is a kernel rewrite of a packet's destination address, such as a Service IP to a pod IP. conntrack is the kernel's table of connections and their rewrites, like a notebook of every change it made. With it, replies get the original addresses back. Modules 3.15 and 3.16.

**Watch cache.** The watch cache is the API server's in-memory copy of recent objects and changes. Watchers read from it, so a thousand controllers don't cause a thousand database reads. Module 3.15.

**resourceVersion and optimistic concurrency.** A `resourceVersion` is a version number that every stored object carries, so two writers don't silently overwrite each other. An update must name the version it read. If somebody wrote in between, the API server answers 409 Conflict, and the writer reads again and retries. This pattern is called optimistic concurrency. Module 3.15.

**Lease and leader election.** A Lease is a small object that one copy of a component renews every few seconds to say "I'm in charge". With several copies of the scheduler or controller manager, only the Lease holder acts. Choosing that holder is called leader election. Module 3.15.

**QoS class.** A QoS (quality of service) class is a group that Kubernetes puts each pod in, based on its requests and limits. The classes are Guaranteed (requests equal limits), Burstable (some requests or limits set) and BestEffort (none). When memory runs short, the kubelet evicts BestEffort first and Guaranteed last. Module 3.15.

**Field validation.** Field validation is a setting on a write that tells the API server what to do with fields it doesn't know. With `fieldValidation=Strict`, the API server refuses unknown or duplicate fields instead of dropping them silently. kubectl sends it by default. Module 3.15.

## Linux networking under Kubernetes

**Network namespace.** A network namespace is a separate copy of the network stack, with its own interfaces, addresses, routes and iptables rules. Every pod has one, owned by its `pause` container. Modules 3.15 and 3.16.

**veth pair.** A veth pair is a virtual network cable with two ends. One end is `eth0` inside the pod. The other end sits on the node, plugged into the bridge. Modules 3.15 and 3.16.

**Bridge (cni0).** The bridge is a virtual network switch on the node that connects all the pods on that node. Every pod's veth plugs into it. The bridge holds the pods' gateway address, `10.42.0.1`. Modules 3.15 and 3.16.

**ARP.** ARP (Address Resolution Protocol) is how a machine finds the MAC address for an IP on the same Layer 2 network. The node's `ip neigh` table shows what it learned. Module 3.15.

**MTU and MSS.** These are the two size limits on packets. The MTU (maximum transmission unit) is the largest packet an interface sends, 1450 for pods here. The MSS (maximum segment size) is the largest TCP payload. It equals the MTU minus 40 bytes of IP and TCP headers, 1410 here. Module 3.15.

**VXLAN.** VXLAN is a tunnel that wraps a Layer 2 frame in a UDP packet, like a letter inside an envelope. flannel uses it (device `flannel.1`, port 8472) to carry pod traffic between nodes. Its 50-byte header is why pods get MTU 1450. Module 3.15.

**SNAT and masquerade.** SNAT (source network address translation) is a kernel rewrite of a packet's source address. Masquerade is SNAT to the address of the interface the packet leaves through. kube-proxy masquerades traffic that enters from outside the cluster, so replies come back through the same node. flannel masquerades pod traffic that leaves the cluster, and Docker masquerades it again in the OrbStack VM. Modules 3.15 and 3.16.

**externalTrafficPolicy.** externalTrafficPolicy is a Service setting that decides which nodes accept outside traffic. `Cluster`, the default, lets any node accept the traffic and SNATs it, which hides the client's address. `Local` keeps the client's address, but only sends traffic to pods on the node that received it. Module 3.15.

**Host port.** A host port is a container port bound to the node's own address. The CNI's portmap plugin implements it with a DNAT rule. k3s's svclb pods use one. Module 3.15.

**kube-router.** kube-router is the network policy controller that k3s embeds. It turns NetworkPolicy objects into iptables rules on every node, in the `FORWARD` chain. Modules 3.15 and 3.16.

**Probe source 169.254.7.127.** 169.254.7.127 is the link-local source address that ambient mode gives to the kubelet's health checks. istio-cni rewrites the kubelet's probe traffic to come from it. ztunnel lets that traffic through without mTLS, so health checks work under STRICT mode. Module 3.15.

## Outbound traffic and NAT

**Egress.** Egress is traffic that leaves the cluster, such as a pod calling an API on the internet. Every layer between the pod and the internet rewrites its source address on the way out. Modules 3.11 and 3.16.

**Default route.** The default route is the entry in a routing table that catches every destination no other route matches. A pod's default route points at the bridge, `10.42.0.1`, and the node's points at the Docker network's gateway. Module 3.16.

**Passthrough (ztunnel).** Passthrough is what ztunnel does with a connection to an address the mesh doesn't know. It opens a plain TCP connection to that address and logs only the IP and port, with no identity and no policy. Modules 3.11 and 3.16.

**flannel masquerade.** flannel's masquerade is the `FLANNEL-POSTRTG` chain on each node, whose rule rewrites the source of any packet from the pod network to an address outside it. It turns a pod's address into the node's address, so replies find their way back. Module 3.16.

**--random-fully.** `--random-fully` is an option on a masquerade rule that gives every new connection a random source port. It prevents two connections from racing for the same conntrack entry when pods pick the same port at once. Module 3.16.

**iptables-nft.** iptables-nft is the `iptables` command with the nftables backend: you write iptables rules, and the kernel stores them as nftables. `iptables --version` prints `(nf_tables)` for it. The lab's node and pods use it. Module 3.16.

**Docker embedded DNS.** Docker's embedded DNS is a small DNS server at `127.0.0.11` inside each container on a user-defined network. The k3d node sends DNS for the gateway address there with a DNAT rule, and it forwards outside names to the host. Module 3.16.

**Docker bridge.** A Docker bridge is the Linux bridge that connects the containers of one Docker network, named `br-` plus the first 12 characters of the network ID. It holds the network's gateway address and masquerades traffic that leaves the network. Module 3.16.

**Network proxy (OrbStack).** OrbStack's network proxy is the part of the OrbStack app that carries the VM's connections into macOS. It accepts each connection from the VM and opens a new one with an ordinary macOS socket, so the internet sees your Mac's address. Module 3.16.

**Egress gateway.** An egress gateway is a proxy that a cluster sends chosen outbound traffic through, usually with fixed source addresses. Partners then allow a short list of IPs, and the gateway applies policy and logs every call. Modules 3.11 and 3.16.

**tcpdump.** tcpdump is the standard Linux tool that prints the packets crossing an interface. With `-i any` it shows each packet on every interface it crosses, which reveals each rewrite. Module 3.16.

## The practice cluster and the security modules

These terms come from the [practice cluster](practice-cluster.md) and the security modules 4.1 to 4.7, which run on it. Each entry names the module that uses it.

**kubeadm.** kubeadm is the official tool that turns plain Linux machines into a Kubernetes cluster. `kubeadm init` creates the control plane, `kubeadm join` adds a node, and `kubeadm upgrade` moves the cluster to a newer version. The practice cluster comes from kubeadm. [The practice cluster](practice-cluster.md), module 4.2.

**Static pod.** A static pod is a pod that the kubelet starts from a YAML file in `/etc/kubernetes/manifests`, with no API server involved. kubeadm runs the API server, etcd, the scheduler and the controller manager this way. Edit the file, and the kubelet restarts the pod within seconds. [The practice cluster](practice-cluster.md), modules 4.1, 4.2, 4.4 and 4.6.

**kind.** kind, short for Kubernetes in Docker, builds a cluster whose nodes are Docker containers. Each node container runs systemd, containerd and the kubelet like a small Linux machine, and kubeadm joins the nodes the usual way. The practice cluster's two nodes, `practice-control-plane` and `practice-worker`, are kind nodes. [The practice cluster](practice-cluster.md).

**Node image.** A node image is the container image that every kind node starts from. kind publishes one per Kubernetes version, and the practice cluster builds its own on top of it with every tool the tasks use, so a new cluster needs no downloads beyond the Kubernetes images. [The practice cluster](practice-cluster.md).

**OrbStack machine.** An OrbStack machine is a lightweight Linux system that OrbStack runs on a Mac. It feels like a virtual machine, but every machine shares one Linux kernel. The practice cluster also runs on two OrbStack machines, `cks-cp` and `cks-w1`, as an alternative to kind. [The practice cluster](practice-cluster.md#other-platforms-orbstack-machines-and-your-own-vms).

**Default-deny policy.** A default-deny policy is a NetworkPolicy that selects every pod in a namespace (`podSelector: {}`) and allows nothing, so you open every path on purpose. Smaller policies then add single paths, because NetworkPolicies only ever add to each other. Module 4.1.

**ipBlock.** An ipBlock is the part of a NetworkPolicy rule that matches IP ranges instead of pods, with an optional `except` list of ranges to leave out. Module 4.1.

**Metadata service.** The metadata service is an HTTP endpoint at `169.254.169.254` on cloud virtual machines that hands out the machine's identity and often temporary cloud credentials. Pods reach it by default, so a NetworkPolicy blocks it. Module 4.1.

**CIS Kubernetes Benchmark.** The CIS Kubernetes Benchmark is a checklist from the Center for Internet Security with about 130 settings for the control plane, etcd and the kubelet, each with a reason and a fix. Module 4.1.

**kube-bench.** kube-bench is a tool from Aqua Security that checks a node's running Kubernetes components against the CIS benchmark and prints PASS, FAIL or WARN with a remediation per item. Module 4.1.

**Ingress and Ingress controller.** An Ingress is a Kubernetes object with HTTP routing rules for traffic entering the cluster: hosts and paths to Services, plus TLS certificates. An Ingress controller, such as ingress-nginx, is the proxy that carries the rules out. Without a matching TLS Secret, ingress-nginx serves a fake certificate instead of failing. Module 4.1.

**Checksum (SHA-512).** A checksum is a fingerprint of a file, computed so that changing one byte changes the whole value. Kubernetes publishes a SHA-512 checksum next to every binary on `dl.k8s.io`, and `sha512sum -c` compares a file against it. Module 4.1.

**RBAC: Role, ClusterRole and bindings.** RBAC (role-based access control) is Kubernetes' permission system. A Role lists allowed verbs on resources in one namespace, a ClusterRole does the same cluster-wide, and a RoleBinding or ClusterRoleBinding hands a role to users, groups or service accounts. Rules only add rights. Module 4.2, module 3.15.

**resourceNames.** resourceNames is an RBAC rule field that limits the rule to named objects, such as one Secret. It covers `get`, `update` and `delete` on those objects, never `create`, and not a plain `list`. Module 4.2.

**automountServiceAccountToken.** automountServiceAccountToken is a field on a ServiceAccount or a pod spec that, when `false`, stops the kubelet from mounting an API token into the pod. The pod's setting wins over the account's. Module 4.2.

**Anonymous request and AuthenticationConfiguration.** An anonymous request is one without credentials, which the API server treats as user `system:anonymous`. An AuthenticationConfiguration file, passed with `--authentication-config`, keeps anonymous access only for named paths such as `/livez`. Turning anonymous access off completely makes kubeadm's own probes fail. Module 4.2.

**Version skew.** Version skew is the allowed difference between component versions in one cluster. The kubelet must never be newer than the API server, so upgrades go control plane first, then the workers. Module 4.2.

**NodeRestriction.** NodeRestriction is an admission plugin that limits what a kubelet may change: only its own Node object and the pods bound to it, and no labels with the `node-restriction.kubernetes.io/` prefix. kubeadm turns it on. Module 4.3.

**Attack surface.** The attack surface is everything an attacker might use to get in or move on: listening ports, installed packages, running services and user accounts. Hardening a node means removing what its job doesn't need. Module 4.3.

**Pod Security Standards and Pod Security Admission.** The Pod Security Standards are three fixed levels for how much power a pod may ask for: `privileged`, `baseline` and `restricted`. Pod Security Admission is the built-in admission plugin that applies a level per namespace through the labels `pod-security.kubernetes.io/enforce`, `warn` and `audit`. Enforce refuses new pods only, never running ones. Module 4.4.

**EncryptionConfiguration.** An EncryptionConfiguration is a file that tells the API server to encrypt chosen resources, usually Secrets, before writing them to etcd. It lists providers such as `aescbc` or `secretbox`; the first one encrypts new writes, and `identity` at the end keeps old plain values readable. The flag is `--encryption-provider-config`. Module 4.4.

**RuntimeClass and gVisor.** A RuntimeClass is a cluster object that names a container runtime handler, so a pod picks it with `runtimeClassName`. gVisor is a sandboxed runtime (`runsc`) that answers a container's system calls with its own user-space kernel, so the host kernel sees far fewer of them. Module 4.4.

**Pod-to-pod encryption.** Pod-to-pod encryption means traffic between pods crosses the network encrypted. Istio does it with mTLS between proxies and proves the workload; Cilium does it with WireGuard or IPsec between nodes and proves the node. Module 4.4, modules 3.2 and 3.21.

**CVE.** A CVE (Common Vulnerabilities and Exposures entry) is a public record of one known security bug, with an ID such as `CVE-2024-6387` and a severity from LOW to CRITICAL. Module 4.5.

**trivy.** trivy is Aqua Security's scanner that compares the packages inside an image, a file system or an SBOM with a database of CVEs. It also writes SBOMs. Module 4.5.

**SBOM, SPDX and CycloneDX.** An SBOM (software bill of materials) is a machine-readable list of every package in an image, with versions and licenses. SPDX, from the Linux Foundation, and CycloneDX, from OWASP, are its two main formats. The Kubernetes tool bom writes SPDX. Module 4.5.

**kubesec.** kubesec is a static analysis tool that scores a Kubernetes manifest's security settings without running it. Critical findings such as `privileged` or `hostPID` fail the manifest whatever its points. KubeLinter is a similar tool. Module 4.5.

**ImagePolicyWebhook.** ImagePolicyWebhook is a built-in admission plugin that sends every new pod's image names to an outside service as an `ImageReview` and follows its verdict. Its admission configuration names a kubeconfig for the service and `defaultAllow`, the answer when the service is down. Module 4.5.

**cosign.** cosign is the Sigstore tool that signs container images and verifies those signatures. Admission policies, such as Kyverno's `verifyImages`, then refuse unsigned images. Module 4.5.

**Audit log and audit policy.** The audit log is the API server's record of requests: who did what to which object, and when. The audit policy decides what to record, with the first matching rule winning, at one of four levels: `None`, `Metadata`, `Request` or `RequestResponse`. kubeadm leaves auditing off. Module 4.6.

**System call (syscall).** A system call is a request from a program to the kernel, such as opening a file or starting a process. Everything a container does turns into syscalls, so seccomp filters them and Falco watches them. Module 4.6.

**Falco.** Falco is a CNCF runtime security tool that watches system calls through an eBPF probe and raises an alert when one matches a rule. A rule has a condition, an output with `%` fields, and a priority. Falco reports and never blocks. Module 4.6.

**Immutable container.** An immutable container never changes after it starts, because its root file system is read-only (`readOnlyRootFilesystem: true`). The folders a program must write to get `emptyDir` volumes. Module 4.6.

**seccomp.** seccomp is a Linux kernel feature that filters the system calls a process may make. A profile is a JSON file with a default action and per-syscall actions. Kubernetes loads `Localhost` profiles from `/var/lib/kubelet/seccomp/`, and `RuntimeDefault` uses the container runtime's built-in profile. Module 4.6.

**AppArmor.** AppArmor is a Linux security module that limits which files, capabilities and network access a program gets, through a text profile loaded with `apparmor_parser`. A pod asks for a loaded profile with `securityContext.appArmorProfile`. OrbStack's kernel lacks it, so the AppArmor tasks run on a VM. Modules 4.6 and 4.7.

**Lima VM.** Lima is a macOS tool that runs Linux virtual machines, each with a kernel of its own. The third practice machine, `cks-lima`, is a Lima VM with AppArmor and a one-node kubeadm cluster that runs Cilium. [The VM page](../README.md#the-vm-for-the-kernel-tasks), module 4.7.

**CiliumNetworkPolicy.** A CiliumNetworkPolicy is Cilium's own policy resource. It selects pods with `endpointSelector` and adds what a NetworkPolicy lacks: HTTP rules at layer 7, named peer groups called entities, and deny rules that beat every allow. Modules 4.1 and 4.7.

**Entity (Cilium).** An entity is a named group of peers in a CiliumNetworkPolicy, such as `kube-apiserver`, `world` (everything outside the cluster), `host` or `cluster`. Cilium works out the addresses behind each name itself. Module 4.1.

**endPort.** endPort is a NetworkPolicy port field that, together with a numeric `port`, opens a whole range of ports in one entry. Module 4.1.

**Cipher suite.** A cipher suite is the set of algorithms a TLS connection uses for key exchange, encryption and integrity. The API server picks from `--tls-cipher-suites`, and `--tls-min-version` sets the oldest TLS version it accepts. Module 4.1.

**Kubelet read-only port.** The read-only port is an old unauthenticated HTTP port of the kubelet, 10255, that hands out pod specs to anybody. `readOnlyPort: 0` in the kubelet config file turns it off. Module 4.1.

**Aggregated ClusterRole.** An aggregated ClusterRole collects its rules from every ClusterRole whose labels match its `aggregationRule`. A controller rewrites its rule list, so you extend it by creating a labelled role, and you take a right away by fixing the source role. Module 4.2.

**Bound service account token.** A bound token is a service account token from the TokenRequest API that names an audience and expires. Pods get one through a projected volume, and `kubectl create token` asks for one by hand. Module 4.2.

**Projected volume.** A projected volume is a pod volume that the kubelet fills from several sources, such as a fresh service account token, a ConfigMap or the Downward API, and keeps up to date. Module 4.2.

**Legacy service account token.** A legacy token is a never-expiring service account token stored in a Secret of type `kubernetes.io/service-account-token`. Deleting the Secret invalidates the token. Module 4.2.

**Authorization mode.** The authorization mode is the API server's ordered list of authorizers, set with `--authorization-mode`. kubeadm sets `Node,RBAC`; `AlwaysAllow` lets every authenticated caller do anything. Module 4.2.

**crictl.** crictl is the command line client for a node's container runtime. `crictl ps -a` lists containers, the exited ones too, and `crictl logs` prints a container's output, which is how you debug a static pod while the API server is down. Module 4.2.

**Kernel module blacklist.** A file under `/etc/modprobe.d/` that keeps the kernel from loading a module: `blacklist` stops loading by alias, and `install <module> /bin/false` makes every load fail. Modules 4.3 and 4.7.

**Encryption key rotation.** Key rotation replaces the key that encrypts Secrets in etcd: add the new key first in the list, restart the API server, rewrite every Secret, then remove the old key and restart again. Module 4.4.

**Pod Security exemption.** An exemption switches Pod Security off for named namespaces, users or RuntimeClasses. It lives in the PodSecurity plugin's configuration, next to the cluster-wide defaults for namespaces without labels. Module 4.4.

**WireGuard.** WireGuard is a VPN protocol built into the Linux kernel. Cilium and Calico use it to encrypt pod traffic between nodes. Modules 4.4 and 4.7.

**Image digest.** An image digest is the SHA-256 checksum of an image's manifest, written `image@sha256:...`. Unlike a tag, it always names exactly one build. Module 4.5.

**Falco list, macro and override.** In a Falco rules file, a list names a set of values, a macro names a piece of condition, and a rule combines them. An `override` block in a later file replaces or extends one field of an existing rule, such as its priority. Module 4.6.

**Audit stage.** An audit stage is the point in a request at which the API server writes an audit event: `RequestReceived`, `ResponseStarted`, `ResponseComplete` or `Panic`. Count `ResponseComplete` lines to count requests. Module 4.6.

**Lateral movement.** Lateral movement is an attacker's step from the first place they broke into to the next one, such as from one pod to the database or to the node. Default-deny NetworkPolicies and least privilege make each step harder. Module 4.1.

**CNI agent (Felix).** A CNI agent is the per-node program of a CNI plugin that turns NetworkPolicies into packet filter rules in the node's kernel. Calico's agent is called Felix and writes iptables rules or eBPF programs. A CNI without such an agent, such as flannel alone, stores policies and enforces nothing. Module 4.1.

**Cilium security identity.** A security identity is a number that Cilium gives to every distinct set of pod labels. Its eBPF programs compare identities instead of IP lists, so a policy keeps working when pods move. Modules 4.1 and 4.7.

**SSRF (server-side request forgery).** SSRF is an attack that tricks a server into fetching a URL the attacker chose. Aimed at the cloud metadata service, it hands the node's cloud credentials to the attacker. Module 4.1.

**Link-local address.** A link-local address, such as `169.254.169.254`, only exists on a machine's own network segment and never crosses a router. Clouds serve their metadata service on one. Module 4.1.

**Profiling endpoint.** A profiling endpoint, `/debug/pprof`, serves memory and thread details of a running Go program. The CIS benchmark asks for `--profiling=false` on the API server, controller manager and scheduler, because production never needs it. Module 4.1.

**TLS handshake.** The TLS handshake is the short negotiation at the start of a TLS connection: the client offers versions and cipher suites, the server picks one of each, sends its certificate, and both agree on keys. Module 4.1.

**Downgrade attack.** A downgrade attack makes two sides of a connection settle on an old protocol version or a weak cipher suite, which the attacker then breaks. A minimum TLS version on the server stops it. Module 4.1.

**Mutating and validating admission.** These are the two phases of admission control. Mutating admission controllers run first and may change the object, for example to add defaults. Validating admission controllers run after schema validation and only accept or refuse, so they judge the final object that etcd stores. Reads skip admission. Module 4.2.

**Authorizer and SubjectAccessReview.** An authorizer is one entry in the API server's `--authorization-mode` list: `Node`, `RBAC`, `Webhook`, `ABAC`, `AlwaysAllow` or `AlwaysDeny`. Each answers allow, deny or no opinion, and the first opinion wins. A SubjectAccessReview is the question "may this user do this?" sent as an object, which the kubelet and webhook authorizers use. Module 4.2.

**escalate, bind and impersonate.** These are the three RBAC verbs that unlock other rights. `escalate` lets a subject write a role with rights it lacks, `bind` lets it bind such a role, and `impersonate` lets it act as another user. Treat each as cluster admin. Module 4.2.

**TokenRequest API and token audience.** The TokenRequest API is the API server endpoint that mints a bound service account token on demand, with an expiry and a binding to one pod. The audience (`aud` claim) names the service that should accept the token, so a token minted for Vault fails against the Kubernetes API. Module 4.2.

**Mirror pod.** A mirror pod is the read-only copy of a static pod that the kubelet creates in the API server, so `kubectl get pods` shows it. Deleting or editing the mirror changes nothing: the manifest file on the node is the truth. Module 4.2.

**OIDC authentication.** OIDC (OpenID Connect) is a login standard that lets the API server trust tokens from a company identity provider. People then log in with their company account, and lose access when the company removes it. Module 4.2.

**Backdoor.** A backdoor is a hidden way back into a machine that an attacker leaves behind, such as a renamed binary started by a systemd unit. `/proc/<pid>/exe` shows the real file behind a process, whatever it calls itself. Module 4.3.

**Least privilege and defence in depth.** Least privilege means each user, program and credential gets only the rights its job needs. Defence in depth means several independent layers of protection, so one failure doesn't decide the outcome. Module 4.3.

**super-admin.conf and system:masters.** `system:masters` is a group that skips authorization entirely. kubeadm puts it only in `super-admin.conf`, and gives `admin.conf` a group with a normal ClusterRoleBinding instead. Both files stay on the control plane, readable by root only. Module 4.3.

**Linux capability.** A capability is one slice of root's power, such as `NET_ADMIN` (change network settings), `SYS_ADMIN` (mount and much more) or `NET_BIND_SERVICE` (listen below port 1024). `capabilities.drop: [ALL]` takes every slice away from a container. Module 4.4.

**securityContext and no_new_privs.** The securityContext is the part of a pod or container spec that sets its user, capabilities, privilege escalation, read-only root and seccomp profile. `allowPrivilegeEscalation: false` sets the kernel flag `no_new_privs`, so no child process gains rights, not even through a setuid binary such as `sudo`. Module 4.4.

**Namespaces and cgroups (Linux).** Linux namespaces give a process its own view of processes, network, mounts and host name. cgroups limit its CPU and memory. Together they make a container, but every container still shares the node's kernel. Module 4.4.

**Envelope encryption (KMS provider).** Envelope encryption encrypts data with a data encryption key (DEK) and encrypts that DEK with a key encryption key (KEK) held in an outside key service. The `kms` provider of an EncryptionConfiguration works this way, so the master key never sits on the control plane node. Module 4.4.

**Container escape.** A container escape is an attack that breaks out of a container's fences onto the node, usually through a kernel bug, a privileged pod or a `hostPath` mount. Module 4.4.

**gVisor Sentry and Kata Containers.** The Sentry is gVisor's user-space kernel: it answers a sandboxed container's syscalls itself and calls the host kernel with only a small set. Kata Containers takes the other route and runs each pod in a lightweight virtual machine with its own kernel. Module 4.4.

**Software supply chain.** The software supply chain is everything that touches code on its way from a developer's editor to a running pod: base images, packages, libraries, build systems and registries. Module 4.5.

**Image layer.** An image layer is one tar archive of files that a Dockerfile instruction added or changed. The runtime stacks the layers into one file system. A file deleted in a later layer still ships in the earlier one. Module 4.5.

**Distroless image and multi-stage build.** A distroless image holds only an app's runtime and libraries, with no shell, package manager or tools. A multi-stage build compiles in one stage and copies only the finished program into a minimal last stage, so build tools never ship. Module 4.5.

**Fixable and unfixable vulnerability.** A fixable finding has a newer package version that closes the bug, so a rebuild removes it. An unfixable one has no fix yet. `trivy --ignore-unfixed` hides the second kind. Module 4.5.

**Static analysis.** Static analysis checks a file without running it, such as kubesec or KubeLinter on a manifest, or hadolint on a Dockerfile. It runs earliest in the supply chain, where a fix is cheapest. Module 4.5.

**Fail closed and fail open.** These describe what a check does when it breaks. Fail closed refuses everything until the check works again. Fail open lets everything through. ImagePolicyWebhook's `defaultAllow: false` fails closed. Module 4.5.

**Keyless signing and transparency log.** Keyless signing with cosign uses a short-lived certificate tied to an identity, such as a CI login, instead of a long-lived key. The signature goes to a public transparency log, an append-only record anybody checks later. Module 4.5.

**Provenance and SLSA.** Provenance is a verifiable record of where an artifact came from and how it was built. SLSA (Supply-chain Levels for Software Artifacts) is a framework that grades how trustworthy that record is. Module 4.5.

**Prevention and detection.** Prevention blocks an action before it happens, as seccomp and AppArmor do. Detection notices an action and reports it, as Falco and audit logs do. Prevention needs you to know what to forbid; detection tolerates surprises but acts after the fact. Module 4.6.

**seccomp action.** A seccomp action is what the kernel does with a matching syscall: `SCMP_ACT_ALLOW` runs it, `SCMP_ACT_ERRNO` fails it with an error, `SCMP_ACT_KILL_PROCESS` kills the process, and `SCMP_ACT_LOG` runs and logs it. Without a profile, a pod runs `Unconfined` unless the kubelet sets `seccompDefault: true`. Module 4.6.

**AppArmor enforce and complain mode.** In enforce mode, an AppArmor profile blocks what its rules deny and logs it. In complain mode, it blocks nothing and only logs, which teams use to learn what an app does before they enforce. Module 4.6.

**Audit level and audit backend.** An audit level (`None`, `Metadata`, `Request`, `RequestResponse`) says how much of a request the API server records. The first policy rule that matches sets it. An audit backend writes the events: the log backend to a file, the webhook backend to an outside service. Module 4.6.

**Falco driver, priority and output.** Falco's driver is the kernel part that collects syscall events: the modern eBPF probe, an older eBPF probe, or a kernel module. A rule's priority ranges from `EMERGENCY` down to `DEBUG`. Outputs send alerts to standard output, a file, syslog, a program or HTTP, and Falcosidekick forwards them further. Module 4.6.

**Assume breach and SIEM.** Assume breach is the stance of planning as if an attacker is already inside, so you focus on limiting and seeing them. A SIEM (security information and event management system) is the central store where teams collect audit logs and alerts off the nodes. Module 4.6.

## Applications on Kubernetes

These terms come from the application modules 1.2 to 1.6, grouped by the module that introduces each one. The security terms, such as static pod or Pod Security Standards, sit in [the section above](#the-practice-cluster-and-the-security-modules).

### Images and workloads (module 1.2)

#### Image

A packed, read-only file system with a program and everything it needs, plus settings such as the command to start and the user to run as. A node fetches an image by name and starts containers from it, so the same image runs the same way on every node.

#### Dockerfile

A text file with build instructions, one per line, such as `FROM`, `COPY`, `RUN` and `CMD`. A build tool like podman or Docker reads it and turns it into an image.

#### Layer

The file system changes of one Dockerfile instruction, saved as one archive. An image is a stack of layers, and images that share a base share its layers, so a registry stores and a node downloads each layer only once.

#### Registry

A server that stores images and hands them out by name, such as Docker Hub or the practice cluster's `registry.practice:5000`. The host part of an image name says which registry holds it.

#### Tag

The part of an image name after the colon, such as `v1` in `greeter:v1`, which names one version of a repository. A tag is movable, so `latest` today may point at a different image tomorrow.

#### podman

A container tool with the same commands as Docker, such as `podman build`, `podman push` and `podman save`, that needs no background service. The practice cluster runs it on `practice-control-plane`.

#### Pod template

The pod spec inside a workload object, under `spec.template`, from which its controller creates every pod. Changing the template of a Deployment starts a rollout.

#### Job

A workload that runs pods until a set number of them finish with exit code 0, then stops. It retries failed pods up to its `backoffLimit`.

#### CronJob

A workload that creates a Job on a schedule written in cron syntax, such as `*/30 * * * *` for every half hour.

#### emptyDir

A volume that starts empty when the pod lands on a node and lives exactly as long as the pod. Containers of one pod share files through it.

#### Init container

A container in the pod's `initContainers` list that runs to completion before the app containers start. The kubelet runs init containers one at a time, in order.

#### Native sidecar

An init container with `restartPolicy: Always`. It starts before the app containers, keeps running for the pod's whole life, and stops after them, so it suits log shippers and proxies, also in Jobs. Stable since Kubernetes 1.33.

#### PersistentVolume

A piece of storage that the cluster knows about, such as a disk, a share or a node folder, with a size and access modes. It belongs to the whole cluster, not to a namespace.

#### PersistentVolumeClaim

A namespace's request for storage of a size, an access mode and a StorageClass. The control plane binds it to a matching PersistentVolume, and a pod mounts the claim, never the volume directly.

#### Access mode

How nodes may mount a volume: `ReadWriteOnce` lets one node write, `ReadOnlyMany` lets many nodes read, and `ReadWriteMany` lets many nodes write.

#### StorageClass

A named kind of storage, such as fast or cheap, that a claim asks for. With a provisioner, the cluster creates a matching PersistentVolume on demand; without one, the class name only has to match a volume you created.

#### Toleration

A pod setting that lets the pod run on a node with a matching taint. The control plane node's taint `node-role.kubernetes.io/control-plane:NoSchedule` keeps pods away unless they tolerate it.

### Deployments and packages (module 1.3)

#### ReplicaSet

The object that keeps a number of identical pods running. A Deployment creates one ReplicaSet per version of its pod template and moves pods between them.

#### Rolling update

A Deployment's default way to change versions: it starts new pods and stops old ones in small steps, set by `maxSurge` and `maxUnavailable`, so some pods serve requests throughout.

#### Blue-green deployment

A release pattern with two complete versions running side by side, where one change to the Service's selector moves all traffic from the old version, blue, to the new one, green.

#### Canary release

A release pattern that sends a small share of the traffic to the new version first. With plain Kubernetes, the share follows the pod counts behind one Service.

#### Helm

A package manager for Kubernetes that installs charts, fills their templates with values, and keeps a numbered history of every installation.

#### Helm chart

A package for Helm: a folder of manifest templates and a `values.yaml` file with defaults.

#### Helm release

One installation of a chart in a namespace, under a name. Every install, upgrade and rollback adds a revision, which Helm stores as a Secret in that namespace.

#### Chart repository

A server that hands out charts, added with `helm repo add`. An OCI registry, the same kind that stores images, also serves charts, addressed as `oci://host/path/chart`.

#### Kustomize base

A folder of plain manifests with a `kustomization.yaml` that lists them, which overlays build on. Kustomize is built into `kubectl`.

#### Kustomize overlay

A folder whose `kustomization.yaml` points at a base and lists changes for one environment, such as a namespace, a name prefix, labels, replica counts, image tags and patches. `kubectl apply -k` applies the result.

### Health and debugging (module 1.4)

#### Probe

A test the kubelet runs against a container on a schedule: an HTTP request, a TCP connection, a command, or a gRPC health call.

#### Readiness probe

A probe that decides whether a pod gets requests. A failure takes the pod out of its Services' endpoints without restarting anything.

#### Liveness probe

A probe that decides whether a container still works. After `failureThreshold` failures in a row, the kubelet kills the container and starts it again.

#### Startup probe

A probe for slow-starting apps. Until it succeeds once, the kubelet runs no liveness or readiness probe on the container.

#### EndpointSlice

The list of ready pod addresses and ports behind a Service, which the control plane keeps current. kube-proxy and ingress controllers read it to know where to send traffic.

#### Event

A short record that a component writes about an object, such as a failed schedule, an image pull or a probe failure. `kubectl describe` and `kubectl events` show them, and the API server keeps them for one hour.

#### metrics-server

A cluster add-on that collects CPU and memory use from every kubelet and serves it through the API, which `kubectl top` reads.

#### Distroless image

An image with only the app and its libraries, without a shell or tools, which makes it small and leaves an attacker little to use.

#### Ephemeral container

A temporary container that `kubectl debug` adds to a running pod, with an image you choose. With `--target`, it shares the process namespace of one container, so it sees that container's processes.

### Configuration and security (module 1.5)

#### ConfigMap

An object that holds settings as keys and values, either short strings or whole files, which pods read as environment variables or as files in a volume.

#### Secret

An object like a ConfigMap for passwords, tokens and keys. Its values sit in base64 and are not encrypted unless the cluster turns on encryption at rest.

#### base64

An encoding that writes any bytes as plain letters and digits, so binary data fits into YAML and JSON. Anyone reverses it with `base64 -d`, so it hides nothing.

#### QoS class

The kubelet's ranking of a pod from its requests and limits: `Guaranteed`, `Burstable` or `BestEffort`. When a node runs out of memory, `BestEffort` pods go first and `Guaranteed` pods last.

#### LimitRange

A namespace object that fills in default requests and limits for containers that name none, and refuses containers outside a minimum and maximum.

#### ResourceQuota

A namespace object that caps the totals of a namespace, such as the sum of CPU requests or the number of pods, and refuses new objects past those totals.

#### ServiceAccount

An identity for programs in pods. The kubelet mounts a short-lived token for the pod's ServiceAccount, which the pod sends to the API server to prove who it is.

#### RBAC

Role-based access control: the API server's way to decide what an identity may do, from Roles that list allowed verbs on resources and bindings that grant them.

#### Role

A list of rules, each allowing some verbs on some resources, valid inside one namespace. A ClusterRole is the same for the whole cluster.

#### RoleBinding

The object that gives a Role, or a ClusterRole, to users, groups or ServiceAccounts, inside the RoleBinding's namespace. A ClusterRoleBinding does it for the whole cluster.

#### Admission controller

A step in the API server, after authentication and authorization, that inspects and may change or refuse an object before it gets stored. LimitRange, ResourceQuota and Pod Security Admission all work this way.

#### Pod Security Admission

The built-in admission controller that refuses pods which break a namespace's Pod Security level, `baseline` or `restricted`, set with the label `pod-security.kubernetes.io/enforce`.

#### Security context

The part of a pod or container spec that sets the process's user, group, capabilities, privilege escalation and file system access.

#### CustomResourceDefinition

An object that adds a new resource type to the API server, with a name, a group, versions and a schema, so `kubectl` handles it like a built-in type.

#### Custom resource

An object of a type that a CustomResourceDefinition added, such as a `Backup`. On its own it only stores data.

#### Operator

A controller, running in a pod, that watches custom resources of its type and makes the cluster match them, for example by running a backup for every `Backup` object.

### Networking (module 1.6)

#### Service

A stable virtual IP address and DNS name in front of a set of pods, picked by label. kube-proxy on every node forwards connections to one of the ready pods.

#### StatefulSet

A workload whose pods get fixed names, `db-0` and `db-1`, a fixed start order, and their own storage. With a headless Service, each pod also gets its own DNS name.

#### Ingress controller

A reverse proxy in the cluster, such as ingress-nginx, that reads Ingress objects and routes HTTP requests to Services by host name and path.

#### Ingress

An object with HTTP routing rules, host and path to Service and port, for the ingress controller whose class it names in `ingressClassName`.

#### NetworkPolicy

A firewall rule for pods: it selects pods by label and lists the peers and ports that may reach them, or that they may reach. The network plugin enforces it.

## Docker and Compose

**Container.** A container is an ordinary process on the Docker host that runs with its own namespaces and a cgroup, so it sees a private view of the system and uses only what its limits allow. All containers share the host's one kernel. Module 0.1.

**Namespace.** A namespace gives a process its own private copy of one kind of resource: process IDs (`pid`), network interfaces (`net`), mounts (`mnt`), the hostname (`uts`) or user IDs (`user`). Docker creates all but the user namespace for every container by default. Modules 0.1 and 0.5.

**cgroup.** A control group caps what a set of processes may use, such as memory, CPU time or the number of processes, and the kernel enforces the cap. `--memory`, `--cpus` and `--pids-limit` write the container's cgroup files. Modules 0.1 and 0.6.

**Docker host.** The Docker host is the Linux machine whose kernel runs the containers. On a Mac it's OrbStack's Linux VM, on Linux the machine itself; the toolbox reaches it through the Docker socket. Module 0.1.

**dockerd, containerd and runc.** dockerd serves the Docker API, containerd manages container lifecycles, and runc creates the namespaces and the cgroup and starts the process, then exits. Module 0.1.

**Image and layer.** An image is an ordered list of read-only layers, each a set of file changes named by the hash of its content, plus settings such as the command and the ports. Containers share an image's layers. Modules 0.1 and 0.2.

**Writable layer.** The writable layer is the thin layer on top of the image that belongs to one container. Files the container changes land there by copy-on-write, and the layer disappears with the container. `docker diff` lists it. Module 0.1.

**PID 1 and --init.** The first process of a PID namespace ignores signals it has no handler for, so a plain `sleep` as PID 1 ignores the SIGTERM of `docker stop` and dies by SIGKILL ten seconds later. `--init` starts a tiny init as PID 1 that passes signals on. Module 0.1.

**Exit codes 137 and 143.** An exit code above 128 means a signal ended the container: 137 is 128 plus 9, SIGKILL, often from the out-of-memory killer or a stop timeout, and 143 is 128 plus 15, SIGTERM. Modules 0.1 and 0.7.

**Dockerfile.** A Dockerfile is the recipe for an image: a base image after `FROM`, then steps such as `COPY` and `RUN`, each making one layer, and settings such as `USER`, `ENTRYPOINT` and `HEALTHCHECK`. Module 0.2.

**Build context.** The build context is the folder that `docker build` sends to the builder; `COPY` reads only from it, and `.dockerignore` keeps files out of it. Module 0.2.

**Build cache.** BuildKit reuses a step's layer when the step's instruction, the layer below and the checksums of the files it copies match an earlier build. The first changed step and every step after it run again. Module 0.2.

**Multi-stage build.** A multi-stage build has several `FROM` stages; only the last becomes the image, and `COPY --from=<stage>` takes files across. It keeps compilers and sources out of the image you ship. Module 0.2.

**scratch.** `scratch` is the empty image, with no files at all, the base for a static binary. Module 0.2.

**Tag and digest.** A tag such as `hits:1.0.0` is a movable name for an image; a digest, `sha256:` and 64 hex characters, is the hash of the image's manifest and always means the same bytes. Modules 0.2 and 0.8.

**Registry.** A registry stores images by repository, tag and digest. The track runs `registry:3.1.2` as `course-registry` on `localhost:5555`. Modules 0.2, 0.6 and 0.8.

**Docker Compose.** Compose describes a set of containers, their networks and volumes in `compose.yaml` and creates, starts, scales and removes them as one project. Module 0.3.

**Compose project.** A project is one running copy of a Compose file, named by `name:` or the folder. Its containers, networks and volumes carry the project's name and label. Module 0.3.

**Service.** A service is one entry under `services:` in a Compose file; Compose runs it as one or more containers that share its name in DNS. Module 0.3.

**Healthcheck.** A healthcheck is a command Docker runs inside a container every few seconds; three failures in a row mark the container `unhealthy`. Docker records the result and changes nothing else. Modules 0.2, 0.3 and 0.7.

**depends_on and service_healthy.** `depends_on` orders a project's start, and `condition: service_healthy` makes Compose wait until the dependency's healthcheck passes before it starts the dependent service. Module 0.3.

**Profile.** A profile keeps a Compose service out of the default start; `--profile <name>` includes it. Module 0.3.

**.env file.** Compose reads `.env` next to `compose.yaml` and fills `${VARIABLE}` from it; a variable set in the shell wins. Modules 0.3 and 0.8.

**Named volume.** A named volume is storage that Docker manages under `/var/lib/docker/volumes` and that outlives every container using it. An empty volume gets the image's files and their owners on its first mount. Module 0.4.

**Bind mount.** A bind mount shows a path of the Docker host inside a container, both ways. The engine resolves the path on the Docker host, not where the `docker` command runs. Module 0.4.

**tmpfs mount.** A tmpfs mount is memory of the Docker host shown as a folder, with an optional size limit; its content disappears when the container stops. Modules 0.4 and 0.6.

**Bridge network.** A Docker bridge network is a Linux bridge on the Docker host, `docker0` for the default network and `br-` plus 12 characters of the network ID for others, with the network's gateway address on it. Module 0.5.

**veth pair (Docker).** A veth pair is a virtual cable with two ends: one is a container's `eth0`, the other plugs into the bridge on the Docker host. `/sys/class/net/eth0/iflink` inside the container names the host end's interface number. Module 0.5.

**Embedded DNS (127.0.0.11).** On a network you create, Docker's DNS server answers container and service names. NAT rules inside each container's namespace send port 53 on `127.0.0.11` to a socket of dockerd there. Modules 0.3 and 0.5.

**Masquerade and conntrack (Docker).** Masquerade rewrites a packet's source to the address of the interface it leaves through; Docker adds one rule per network for traffic that leaves the host. conntrack, the kernel's connection table, remembers each rewrite and undoes it on the reply. Module 0.5.

**DNAT and the userland proxy.** A published port becomes a DNAT rule that rewrites the destination to the container's address and port, plus a filter rule that accepts it. The userland proxy, `docker-proxy` on Linux and OrbStack's agent on a Mac, carries connections to the port from the host itself. Module 0.5.

**Network isolation (raw drop rule).** Docker 29 on Linux drops packets for a container that arrive through any bridge other than its own, with a rule in the `raw` table. OrbStack switches that isolation off on a Mac. Module 0.5.

**Internal network.** An internal Docker network has no masquerade and no published ports, so its containers reach each other and nothing outside. Module 0.8.

**Debug image (course/nettools).** The track's debug image holds `ip`, `iptables`, `nft`, `tcpdump`, `conntrack`, `nsenter` and `capsh`. Run with `--privileged --net=host --pid=host`, it works on the Docker host's network and processes, the same on a Mac and on Linux. Modules 0.5 to 0.7.

**Capability.** A capability is one piece of root's power, such as `CAP_CHOWN` or `CAP_NET_RAW`. Docker gives a container 14 by default; `--cap-drop ALL` removes them and `--cap-add` puts single ones back. Module 0.6.

**seccomp.** seccomp filters system calls. Docker's default profile blocks about 50 rare and risky calls, such as creating a user namespace without `CAP_SYS_ADMIN`; a JSON profile of your own blocks the calls you list. Module 0.6.

**AppArmor and SELinux.** These Linux security modules add a profile per container on hosts that run them, such as `docker-default` on Ubuntu. OrbStack's kernel on a Mac runs without one. Module 0.6.

**no-new-privileges.** `no-new-privileges` stops every process in a container from gaining rights through a setuid or setcap program. Modules 0.6 and 0.8.

**User namespace and rootless.** A user namespace maps user IDs, so root inside maps to an unprivileged user outside. Rootless Docker and `userns-remap` use it on Linux; by default, root in a container is root on the host. Modules 0.1 and 0.6.

**Read-only root filesystem.** `--read-only` turns the container's writable layer off; a tmpfs or a volume gives the app the few writable places it needs. Modules 0.6 and 0.8.

**OOM kill.** When a container exceeds its memory limit, the kernel's out-of-memory killer ends a process in it; Docker records `OOMKilled=true` and exit code 137. Modules 0.6 and 0.7.

**Trivy.** Trivy scans an image's packages and the libraries inside its binaries against a vulnerability database; `--exit-code 1` with `--severity` turns it into a gate. Modules 0.6 and 0.8.

**cosign.** cosign signs an image's digest with a private key and stores the signature in the registry; `cosign verify` checks it with the public key. A signature covers a digest, never a tag. Modules 0.6 and 0.8.

**Compose secret.** A Compose secret reaches a container as a read-only file under `/run/secrets`, so it never shows in `docker inspect` the way an environment variable does. Module 0.6.

**docker events.** `docker events` streams what Docker did to its objects, such as `create`, `start`, `die`, `kill` and health changes, with times. Module 0.7.

**Debug container.** A debug container joins a target's namespaces with `--network container:<name>` and `--pid container:<name>` and brings its own tools, so you look inside an image without a shell. Module 0.7.

**YAML anchor.** An anchor, `&name`, marks a block in a YAML file, and `<<: *name` merges it into another block, so a Compose file states shared settings once. Module 0.8.
