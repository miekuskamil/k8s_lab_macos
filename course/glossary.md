# Glossary

Every Istio resource and term this course uses, in plain words. Each entry says what the thing does, gives a small example where that helps, and names the module that puts it to work. If a module mentions something and you're not sure what it is, look here first.

- [Find the right resource](#find-the-right-resource)
- [The pieces of Istio](#the-pieces-of-istio)
- [Traffic resources](#traffic-resources)
- [Security resources](#security-resources)
- [Observability and operations](#observability-and-operations)
- [Protocols and identity](#protocols-and-identity)
- [Envoy response flags](#envoy-response-flags)
- [Around the mesh](#around-the-mesh)
- [AI on Kubernetes](#ai-on-kubernetes)

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

**Service mesh.** A layer of proxies that sits in the path of every request between your services and handles encryption, identity, routing, retries and measurements, so the application code doesn't have to. Module 1.

**Data plane.** The proxies that touch your traffic: ztunnel, waypoints, sidecars and gateways. If the data plane stops, requests stop.

**Control plane.** The part that only gives orders. In Istio that's istiod. It never sees a request.

**istiod.** Istio's control plane, one Deployment in `istio-system`. It watches the Kubernetes API, turns your Istio and Gateway API resources into proxy configuration, pushes it out over xDS, and acts as the certificate authority that signs every workload's identity. Modules 1, 2, 14.

**Envoy.** The open-source proxy (from Lyft, 2016) that does the HTTP work in Istio: sidecars, waypoints and gateways all run Envoy. Its container image goes by the name `proxyv2`.

**Ambient mode.** Istio's newer data plane design, without sidecars. ztunnel on each node handles L4 for every pod, and waypoints handle L7 only where you deploy them. A namespace joins with the label `istio.io/dataplane-mode: ambient`, and its pods need no restart. The lab's `shop` namespace uses it. Module 1.

**Sidecar mode.** Istio's original design: an Envoy container injected into every pod, which handles both L4 and L7 for that pod. A namespace joins with `istio-injection: enabled` (or `istio.io/rev`), and pods only get the sidecar when they restart. Module 7.

**ztunnel.** "Zero-trust tunnel." A small Rust proxy that runs once per node as a DaemonSet in ambient mode. It holds the certificates of every mesh pod on its node, wraps their traffic in mTLS (HBONE), and enforces L4 rules. It never reads HTTP. Modules 1, 2, 3.

**Waypoint.** An Envoy proxy that handles L7 for a namespace or a service in ambient mode: HTTP routing, L7 authorization, retries, faults, HTTP metrics. You create it as a Gateway with `gatewayClassName: istio-waypoint`, and point traffic at it with the label `istio.io/use-waypoint`. The lab's backend uses one. Modules 1, 3, 4.

**Sidecar.** The Envoy container (`istio-proxy`) inside a pod in sidecar mode, plus the init container `istio-init` that sets up iptables rules to send the pod's traffic through it. Module 7. Don't mix it up with the Sidecar resource below.

**istio-cni.** A node agent (DaemonSet) that sets up traffic redirection inside each mesh pod's network namespace in ambient mode, so the pod's traffic flows through ztunnel. It also answers pods' DNS when DNS capture is on. Modules 2, 12, and troubleshooting problems 15 and 18.

**Ingress gateway.** An Envoy at the edge of the mesh that accepts traffic from outside the cluster. In this lab it's `shop-gateway-istio` in `shop-ingress`, created from a Gateway API Gateway. Modules 4, 11.

**Egress gateway.** An Envoy that all traffic to the outside world passes through, so one place applies rules and logs. In ambient mode a waypoint plays this role. Module 12.

**East-west and north-south.** East-west traffic flows between services inside the cluster (through ztunnel and waypoints). North-south traffic enters or leaves the cluster (through the ingress gateway, or out to the internet). Module 4.

## Traffic resources

**Gateway (Gateway API).** `gateway.networking.k8s.io/v1`. A Kubernetes-standard resource that asks for a proxy with listeners (ports, protocols, TLS certificates). Istio sees it and creates an Envoy Deployment and Service for it. The class decides the role: `istio` makes an ingress gateway, `istio-waypoint` makes a waypoint. Modules 4, 11.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shop-gateway, namespace: shop-ingress}
spec:
  gatewayClassName: istio
  listeners: [{name: http, port: 8080, protocol: HTTP}]
```

**Gateway (Istio API).** `networking.istio.io/v1`. Istio's older resource with the same name. It doesn't create a proxy. It configures ports, hosts and TLS on gateway pods that already exist, picked with a label `selector`. A VirtualService then attaches to it through its `gateways:` field. Many existing Istio setups and the ICA exam use it. Module 16 compares the two.

**GatewayClass.** A Gateway API resource that names an implementation. Istio installs `istio` and `istio-waypoint`.

**HTTPRoute.** Gateway API resource with HTTP routing rules: match on path, headers or method, then send to one or more backends with weights, and optionally rewrite, redirect, time out or retry. `parentRefs` says what it attaches to: a Gateway (ingress) or a Service (mesh traffic, applied by that Service's waypoint). Modules 4, 5, 11.

```yaml
kind: HTTPRoute
spec:
  parentRefs: [{group: "", kind: Service, name: backend}]
  rules:
    - backendRefs:
        - {name: backend-v1, port: 8000, weight: 90}
        - {name: backend-v2, port: 8000, weight: 10}
```

**VirtualService.** Istio's own routing resource, the older counterpart of HTTPRoute. It names one or more `hosts`, then lists HTTP routes with matches, destinations (`host`, `subset`, `weight`), timeouts, retries, **fault injection** and mirroring. Gateway API has no fault injection, so module 5 uses a VirtualService for it. In ambient mode, the waypoint applies it. Modules 5, 7, 16.

```yaml
kind: VirtualService
spec:
  hosts: [backend]
  http:
    - fault: {delay: {percentage: {value: 100}, fixedDelay: 500ms}}
      route: [{destination: {host: backend}}]
```

**DestinationRule.** Rules that apply *after* routing picked a destination: how to talk to it. Load-balancing algorithm, connection pool limits (`connectionPool`, the circuit breaker), ejection of failing pods (`outlierDetection`), TLS towards it (`tls`), and named **subsets** (groups of pods by label, like `v1` and `v2`) that a VirtualService routes to. Modules 5, 12, 15.

```yaml
kind: DestinationRule
spec:
  host: backend
  trafficPolicy:
    connectionPool: {http: {http1MaxPendingRequests: 1, maxRequestsPerConnection: 1}}
  subsets:
    - {name: v1, labels: {version: v1}}
```

**Subset.** A named group of a service's pods, defined in a DestinationRule by labels. VirtualServices route to subsets. HTTPRoutes use one Service per version instead. Module 4.

**ServiceEntry.** Adds a host the mesh doesn't know, usually outside the cluster, to the mesh's service registry, so traffic to it gets names in metrics, routing rules and authorization. `location: MESH_EXTERNAL` marks it as outside, `resolution: DNS` lets Envoy look up its IPs. In ambient mode, it needs a virtual IP and DNS capture to reach a waypoint. Module 12.

**Sidecar (resource).** `networking.istio.io/v1 Sidecar`. Limits what one sidecar proxy knows about (which hosts it may reach) and sets its outbound policy, for example `REGISTRY_ONLY` to block unknown hosts. Sidecar mode only; ambient has no equivalent. Not used in the course, but common in large sidecar installs to cut memory.

**EnvoyFilter.** Patches raw Envoy configuration when no Istio resource covers what you need. Powerful, fragile across upgrades, and not supported on waypoints in Istio 1.24. Module 5 mentions it.

**ReferenceGrant.** Gateway API resource that lets a resource in one namespace point at an object in another, for example a Gateway using a TLS Secret from a different namespace. The owner of the target namespace creates it. Module 11.

**WorkloadEntry.** Registers a single non-Kubernetes machine (a VM) as a mesh workload. Not used in this course.

## Security resources

**PeerAuthentication.** `security.istio.io/v1`. Says whether a workload accepts plain text. `STRICT`: mTLS only. `PERMISSIVE` (the default): mTLS and plain text, so you enroll workloads gradually. `DISABLE`: plain text only. Put it in `istio-system` for the whole mesh, in a namespace for that namespace, or add a `selector` for single workloads. Modules 2, 7.

**AuthorizationPolicy.** Decides whether a request may pass. `action` is `ALLOW`, `DENY`, `CUSTOM` (ask an external service) or `AUDIT`. `rules` match on `from` (source identity: `principals`, `namespaces`, `requestPrincipals`), `to` (operations: ports, methods, paths) and `when` (conditions, such as token claims). Where you attach it decides who enforces it: `selector` (pod labels) makes ztunnel enforce L4 parts, `targetRefs` to a Service, Gateway or ServiceEntry makes that waypoint or gateway enforce L7. Order of evaluation: CUSTOM, then DENY, then ALLOW. Modules 3, 12, 13.

**Principal.** The workload identity an AuthorizationPolicy matches, written without the `spiffe://` prefix: `cluster.local/ns/shop/sa/frontend`. Module 3.

**RequestAuthentication.** Tells a proxy which end-user tokens (JWTs) to trust: issuer, audience and public keys (JWKS). It rejects bad tokens with 401 but lets requests without a token through. An AuthorizationPolicy with `requestPrincipals` makes a token mandatory. Module 13.

**Request principal.** The end-user identity from a checked JWT, written as `<issuer>/<subject>`, for example `https://idp.k8s-lab.local/alice`. Module 13.

## Observability and operations

**Telemetry.** `telemetry.istio.io/v1`. Turns tracing, metrics and access logs on or off and picks providers, for the mesh, a namespace or one proxy. The lab sends traces to Jaeger with it. Module 6.

**istioctl.** Istio's command-line tool. The commands this course uses: `proxy-status` (which proxies use which control plane, and whether their config is current), `ztunnel-config` (what ztunnel knows), `proxy-config` (a sidecar or gateway's Envoy config), `analyze` (finds mistakes in your resources) and `x precheck` (checks a cluster before an upgrade). Module 9 lists them by layer.

**Revision.** A name for one installed control plane, such as `1-25-5`. The original install without a name is `default`. Proxies choose a revision with the label `istio.io/rev`. Module 14.

**Tag (revision tag).** A movable nickname, such as `default` or `stable`, that points at a revision. Move the tag, and every workload labelled with it follows. Module 14.

## Protocols and identity

**L4 and L7.** Layers of the network model. L4 means connections: IP addresses and ports (TCP). L7 means the application protocol, here HTTP: methods, paths, headers, status codes. ztunnel works at L4, waypoints and sidecars at L7.

**mTLS (mutual TLS).** TLS where both sides show a certificate, so each proves its identity to the other, and both encrypt the traffic. Every connection between mesh workloads uses it. Module 2.

**SPIFFE ID.** The identity inside a mesh certificate, written as a URI: `spiffe://cluster.local/ns/shop/sa/frontend`, meaning trust domain, namespace and service account. Module 2.

**Trust domain.** The first part of a SPIFFE ID (`cluster.local` here). Workloads trust certificates from the same trust domain.

**HBONE.** "HTTP-Based Overlay Network Environment". The tunnel ztunnel and waypoints use: one mTLS connection on port 15008 carrying many TCP streams as HTTP/2 CONNECT requests. Module 2.

**xDS.** The family of APIs istiod uses to push configuration to proxies: LDS (listeners), RDS (routes), CDS (clusters, meaning upstream services), EDS (endpoints, meaning pod IPs), SDS (secrets, meaning certificates). ztunnel uses Istio's own WDS and WADS (workloads and addresses). You see these letters in `istioctl proxy-status`. Modules 1, 11.

**SNI (Server Name Indication).** The name a client sends at the start of a TLS handshake, so one IP address serves many sites with different certificates. Module 11.

**TLS termination and origination.** Termination: a proxy ends a TLS session and reads the request inside (the ingress gateway in module 11). Origination: a proxy starts a TLS session on the app's behalf, so the app sends plain HTTP (the waypoint in module 12).

**DNS capture.** In ambient mode, istio-cni redirects a pod's DNS queries to ztunnel, which answers for ServiceEntry hosts with their virtual IP. Module 12.

## Envoy response flags

Envoy writes a short flag into access logs and the `response_flags` metric label when it, rather than your app, caused or shaped the response. The ones this course meets:

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
| `DC` | Downstream connection termination | The caller hung up early |
| `-` | No flag | Envoy passed the response on unchanged |

Modules 5, 6, 8.

## Around the mesh

**Gateway API.** The Kubernetes project's standard API for traffic routing (Gateway, HTTPRoute, GatewayClass, ReferenceGrant), which Istio, Cilium, Envoy Gateway and others implement. Istio recommends it over its own VirtualService and Istio Gateway for new setups, and it's the main API in ambient mode.

**cert-manager.** A Kubernetes controller that issues and renews TLS certificates. **Issuer** and **ClusterIssuer** say who signs; a **Certificate** says what you want; the result lands in a Secret. Module 11.

**JWT and JWKS.** A JSON Web Token carries signed claims about a user. A JSON Web Key Set publishes the public keys that check those signatures. Module 13.

**NetworkPolicy.** Plain Kubernetes resource that allows or blocks connections by pod labels, namespaces and IP ranges, enforced by the node's packet filter, below the mesh. Module 12 uses one to force traffic through the waypoint.

**Kiali.** The Istio console: traffic graph, mTLS status and config checks. **Jaeger**: shows traces. **Prometheus**: stores metrics. **Grafana**: dashboards and queries over Prometheus, Loki and Jaeger. **Loki**: stores logs. Module 6.

## AI on Kubernetes

**LLM (large language model).** A model that reads text and writes text, such as Qwen, Llama or Claude. "14B" in a model name means 14 billion parameters: bigger models answer better and run slower. Modules 17 to 19.

**Ollama.** A tool that downloads open models and serves them over a small HTTP API (`/api/chat`, `/api/tags`, `/api/pull`, `/api/delete`) on port 11434. It has no authentication. Modules 17, 18.

**Token.** The unit a model reads and writes: a piece of a word, about four characters of English. Hosted models bill per token, input and output separately, and token counts belong on every dashboard for AI traffic. Module 17.

**Prompt.** Everything a model receives: instructions (the system prompt), data and the question. Module 17.

**RAG (retrieval-augmented generation).** Fetch real data first, put it into the prompt, then ask the model, so it answers from your data instead of from memory. The shop assistant does this with orders. Module 17.

**GenAI semantic conventions.** OpenTelemetry's standard attribute names for model calls: `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens` and others. Tools like Jaeger and Grafana read them the same way whatever the model. Module 17.

**AI gateway.** A proxy built for model traffic: rate limits counted in tokens, switching between model providers, prompt caching, filtering what goes in and out. Examples: agentgateway, kgateway, Envoy AI Gateway. Module 17.

**Inference.** Running a trained model to get an answer, as opposed to training it. A model server like Ollama or vLLM does inference. Module 18.

**Model server.** The program that loads a model and answers requests over HTTP: Ollama, llama.cpp, vLLM, NVIDIA Triton. Module 18 runs llama.cpp.

**GGUF.** The model file format llama.cpp and Ollama read. One file holds the whole model, often shrunk ("quantised", the `q4_k_m` in a file name) to fit in less memory. Module 18.

**OpenAI-compatible API.** The request format OpenAI made popular, `POST /v1/chat/completions` with the model name in the JSON body. Most model servers and AI tools speak it. Module 18.

**Gateway API Inference Extension.** A Kubernetes standard for routing to model servers. An **InferencePool** groups model server pods, and an **endpoint picker** chooses a pod by the servers' own metrics, such as queue length, instead of round robin. Istio supports it from 1.27. Module 18.

