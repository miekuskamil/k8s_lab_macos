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
- [Kubernetes operations](#kubernetes-operations)

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

**In-pod redirection.** How ambient mode catches traffic: istio-cni adds redirect rules inside each ambient pod's network namespace, and ztunnel listens there on ports 15001, 15006, 15008 and 15053, so the pod's traffic reaches ztunnel without leaving the pod. Modules 1 and 29.

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

**Trace and span.** A trace follows one request through every service it touches. It's a tree of spans, and each span records one step: who did it, when it started, how long it took. All spans of a trace share one trace id, which travels in the `traceparent` header. Module 6.

**Sampling.** Keeping only a share of traces, chosen at random when a request enters the mesh. The lab keeps 100%. Production systems often keep 1 to 5%, because storing every trace costs a lot. Module 6.

**Access log.** One line per request, written by a proxy: method, path, status code, response flags, timings, upstream. Off by default in the lab; a Telemetry resource turns it on for the waypoint. Modules 3, 5, 6.

**Reporter.** The label on Istio's request metrics that says which proxy recorded them: `source` (the calling side, here the ingress gateway or a client sidecar), `waypoint`, or `destination` (a sidecar on the receiving side). Modules 6, 7.

**Percentile (p95, p99).** The value that 95% (or 99%) of measurements stay under. p95 latency of 200 ms means one request in twenty took longer. Prometheus estimates it from histogram buckets, counters of how many requests fell into each time range (0.5, 1, 5, 10, 25 ms and up for Istio), so the result often lands on a bucket edge. Modules 5, 6.

**PodMonitor.** A prometheus-operator resource that tells Prometheus which pods to scrape, on which port and path. The lab ships PodMonitors for the gateway, the waypoint and ztunnel. Module 7 adds one for the sidecars.

**istioctl.** Istio's command-line tool. The commands this course uses: `proxy-status` (which proxies use which control plane, and whether their config is current), `ztunnel-config` (what ztunnel knows), `proxy-config` (a sidecar or gateway's Envoy config), `analyze` (finds mistakes in your resources) and `x precheck` (checks a cluster before an upgrade). Module 9 lists them by layer.

**Revision.** A name for one installed control plane, such as `1-25-5`. The original install without a name is `default`. Proxies choose a revision with the label `istio.io/rev`. Module 14.

**Tag (revision tag).** A movable nickname, such as `default` or `stable`, that points at a revision. Move the tag, and every workload labelled with it follows. Module 14.

**Head sampling.** The first proxy on a request decides once whether to keep its trace and writes the decision into the `traceparent` header; every later hop follows that decision. Module 6.

## Protocols and identity

**L4 and L7.** Layers of the network model. L4 means connections: IP addresses and ports (TCP). L7 means the application protocol, here HTTP: methods, paths, headers, status codes. ztunnel works at L4, waypoints and sidecars at L7.

**mTLS (mutual TLS).** TLS where both sides show a certificate, so each proves its identity to the other, and both encrypt the traffic. Every connection between mesh workloads uses it. Module 2.

**SPIFFE ID.** The identity inside a mesh certificate, written as a URI: `spiffe://cluster.local/ns/shop/sa/frontend`, meaning trust domain, namespace and service account. Module 2.

**Trust domain.** The first part of a SPIFFE ID (`cluster.local` here). Workloads trust certificates from the same trust domain.

**HBONE.** "HTTP-Based Overlay Network Environment". The tunnel ztunnel and waypoints use: one mTLS connection on port 15008 carrying many TCP streams as HTTP/2 CONNECT requests. Module 2.

**xDS.** The family of APIs istiod uses to push configuration to proxies: LDS (listeners), RDS (routes), CDS (clusters, meaning upstream services), EDS (endpoints, meaning pod IPs), SDS (secrets, meaning certificates). ztunnel uses Istio's own WDS and WADS (workloads and addresses). You see these letters in `istioctl proxy-status`. Modules 1, 11.

**SNI (Server Name Indication).** The name a client sends at the start of a TLS handshake, so one IP address serves many sites with different certificates. Module 11.

**TLS termination and origination.** Termination: a proxy ends a TLS session and reads the request inside (the ingress gateway in module 11). Origination: a proxy starts a TLS session on the app's behalf, so the app sends plain HTTP (the waypoint in module 12).

**X-Forwarded-Client-Cert (XFCC).** A header a sidecar adds to requests it passes to its app. It names the caller (`URI=spiffe://...`) and the receiver (`By=...`) from the mTLS handshake, so the app learns who called without touching TLS. Module 7.

**DNS capture.** In ambient mode, istio-cni redirects a pod's DNS queries to ztunnel, which answers for ServiceEntry hosts with their virtual IP. Module 12.

**Subject Alternative Name (SAN).** The list of names inside a certificate. A TLS client compares it with the host name it connected to; Istio puts the workload's SPIFFE ID there. Modules 11 and 29.

**Trust store.** The set of CA certificates a client trusts, such as curl's built-in list or a file passed with `--cacert`. A certificate is trusted only if its chain ends at one of them. Module 11.

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
| `NC` | No cluster | The route points at a Service Envoy has no cluster for, for example a misspelled or deleted one (module 4) |
| `DC` | Downstream connection termination | The caller hung up early |
| `-` | No flag | Envoy passed the response on unchanged |

Modules 4, 5, 6, 8.

## Around the mesh

**Gateway API.** The Kubernetes project's standard API for traffic routing (Gateway, HTTPRoute, GatewayClass, ReferenceGrant), which Istio, Cilium, Envoy Gateway and others implement. Istio recommends it over its own VirtualService and Istio Gateway for new setups, and it's the main API in ambient mode.

**cert-manager.** A Kubernetes controller that issues and renews TLS certificates. **Issuer** and **ClusterIssuer** say who signs; a **Certificate** says what you want; the result lands in a Secret. Module 11.

**JWT and JWKS.** A JSON Web Token carries signed claims about a user. A JSON Web Key Set publishes the public keys that check those signatures. Module 13.

**NetworkPolicy.** Plain Kubernetes resource that allows or blocks connections by pod labels, namespaces and IP ranges, enforced by the node's packet filter, below the mesh. Module 12 uses one to force traffic through the waypoint.

**Idempotent request and idempotency key.** A request is idempotent when sending it twice has the same effect as sending it once, like a GET. A POST that creates an order is not. An idempotency key is a unique id the client sends with such a request, so the server spots a repeat and skips it. Safe retries depend on this. Module 5.

**Loki and LogQL.** Loki stores logs and indexes only a few labels per stream (namespace, app, pod), not the text, which keeps it cheap. LogQL queries it: `{app="backend"}` picks streams, `|= "text"` filters lines, `| json` turns JSON fields into labels, and `count_over_time`, `rate` and `unwrap` turn lines into numbers. Module 6.

**Kiali.** The Istio console: traffic graph, mTLS status and config checks. **Jaeger**: shows traces. **Prometheus**: stores metrics. **Grafana**: dashboards and queries over Prometheus, Loki and Jaeger. **Loki**: stores logs. Module 6.

**eBPF.** Small programs that Linux loads into the kernel at runtime, after a verifier checks they are safe. Cilium uses them for fast packet handling, policy and tracing. Module 10.

**Cilium.** A CNI plugin that uses eBPF for pod networking, Service load balancing and network policy, and hands Layer 7 rules to an Envoy per node. Module 10.

**Kernel space and user space.** The kernel owns network interfaces and the packet filter. Ordinary programs such as Envoy and ztunnel run in user space and reach the network through sockets, which costs copies and context switches. Module 10.

## AI on Kubernetes

**LLM (large language model).** A model that reads text and writes text, such as Qwen, Llama or Claude. "14B" in a model name means 14 billion parameters: bigger models answer better and run slower. Modules 17 to 19.

**Ollama.** A tool that downloads open models and serves them over a small HTTP API (`/api/chat`, `/api/tags`, `/api/pull`, `/api/delete`) on port 11434. It has no authentication. Modules 17, 18.

**Token.** The unit a model reads and writes: a piece of a word, about four characters of English. Hosted models bill per token, input and output separately, and token counts belong on every dashboard for AI traffic. Module 17.

**Prompt.** Everything a model receives: instructions (the system prompt), data and the question. Module 17.

**RAG (retrieval-augmented generation).** Fetch real data first, put it into the prompt, then ask the model, so it answers from your data instead of from memory. The shop assistant does this with orders (module 17); module 27 builds a full one over the course, with a vector database. Modules 17 and 27.

**GenAI semantic conventions.** OpenTelemetry's standard attribute names for model calls: `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens` and others. Tools like Jaeger and Grafana read them the same way whatever the model. Module 17.

**AI gateway.** A proxy built for model traffic: rate limits counted in tokens, switching between model providers, prompt caching, filtering what goes in and out. Examples: agentgateway, kgateway, Envoy AI Gateway. Module 17.

**Inference.** Running a trained model to get an answer, as opposed to training it. A model server like Ollama or vLLM does inference. Module 18.

**Model server.** The program that loads a model and answers requests over HTTP: Ollama, llama.cpp, vLLM, NVIDIA Triton. Module 18 runs llama.cpp.

**GGUF.** The model file format llama.cpp and Ollama read. One file holds the whole model, often shrunk ("quantised", the `q4_k_m` in a file name) to fit in less memory. Module 18.

**OpenAI-compatible API.** The request format OpenAI made popular, `POST /v1/chat/completions` with the model name in the JSON body. Most model servers and AI tools speak it. Module 18.

**Gateway API Inference Extension.** A Kubernetes standard for routing to model servers. An **InferencePool** groups model server pods, and an **endpoint picker** chooses a pod by the servers' own metrics, such as queue length, instead of round robin. Istio supports it from 1.27. Module 18.

**AI agent.** A program that lets a model act: it sends the model a question plus a list of tools, runs the tool calls the model asks for, feeds back the results, and repeats until the model answers. Module 19.

**Tool.** A function an agent offers its model, such as "list pods" or "delete a resource", with a description the model reads to decide when to use it. Module 19.

**MCP (Model Context Protocol).** The standard way for agents to reach tools: JSON-RPC over HTTP, every call to one URL (`/mcp`), the tool name inside the JSON body. A tool server describes its tools and runs them. Module 19.

**A2A (Agent2Agent).** A protocol for clients and agents to send tasks to an agent and get results back. kagent serves it on its controller, port 8083. Module 19.

**kagent.** A CNCF Sandbox project that runs AI agents on Kubernetes. Agents, models (ModelConfig) and tool servers (RemoteMCPServer) are custom resources. Module 19.

**Prompt injection.** Text that reaches a model through data, like a log line, a web page or a pod annotation, and carries instructions the model may follow. No model resists it reliably. Module 19.

**Excessive agency.** An agent holding more tools or permissions than its job needs, so a mistake, a prompt injection or a direct call to its tools does real damage. On the OWASP Top 10 for LLM applications. Module 19.

**Prefill and decode.** The two phases of a model's answer. Prefill reads the whole prompt in one pass; decode then writes the answer one token at a time, so output length decides how long the user waits. Module 17.

**Tool calling.** A model trained for it answers with a tool name and JSON arguments instead of text, and the agent program runs that call and sends back the result. Module 19.

**Confused deputy.** A program with strong rights that acts for a caller with weak ones, such as a tool server with wide RBAC rights answering any agent user. Module 19.

## Kubernetes operations

**Cordon, drain, uncordon.** Cordon marks a node unschedulable. Drain cordons it and evicts its pods, one by one, respecting PodDisruptionBudgets; DaemonSet pods stay. Uncordon makes it schedulable again, but moves nothing back. Module 20.

**PodDisruptionBudget (PDB).** A rule like "keep at least one `web` pod running" that evictions must respect. Covers voluntary disruptions such as drains and upgrades, not crashes. Module 20.

**DaemonSet.** A workload with one pod on every node, such as ztunnel, istio-cni or a log shipper. Drains leave them alone. Module 20.

**`ttlSecondsAfterFinished` and `revisionHistoryLimit`.** The first deletes a finished Job after a delay. The second caps how many old ReplicaSets a Deployment keeps for `kubectl rollout undo` (default 10). Module 20.

**ServiceLB (svclb).** k3s's built-in load balancer. For each Service of type LoadBalancer it gives the Service the node's IP as its external IP and runs a small `svclb-...` pod with a host port that forwards to the Service. kube-proxy also writes a rule for that external IP, and the kernel checks kube-proxy's rules first, so in this lab kube-proxy DNATs the traffic straight to the gateway pod and the svclb pod's rule stays unused. Modules 1 and 29.

**k3s.** A small Kubernetes distribution in one binary, with its own containerd, flannel and an SQLite or etcd datastore. The lab runs it inside Docker with k3d. Modules 20, 21.

**system-upgrade-controller.** A controller that upgrades k3s (and RKE2) nodes from a `Plan` resource: target version, node selector, how many nodes at once, whether to cordon or drain. Module 21.

**Certificate rotation and renewal.** Rotation replaces a certificate's key; renewal extends its expiry. k3s renews certificates within 120 days of expiry each time it starts; `k3s certificate rotate` rotates. Module 21.

**CNI plugin directory.** The folder containerd searches for network plugins (`bin_dir` or `bin_dirs` in its config). istio-cni must place its plugin there; the k3s upgrade in module 21 moved it. Module 21.

**host-local IPAM.** flannel's IP address manager. It keeps one lease file per pod address on the node and frees it when the CNI chain's DEL runs. Module 21.

## GitOps and ArgoCD

**GitOps.** Running a cluster from Git: Git holds the desired state, and an agent inside the cluster keeps the live state matching it. Changes go through commits, and rollbacks through `git revert`. ArgoCD and Flux are the common agents. Module 22.

**Application.** ArgoCD's resource that links one path in one Git repository to one namespace in one cluster, with a sync policy. Module 22.

**AppProject.** Groups Applications and limits what they may do: which repositories, which destination namespaces, which kinds of resources. ArgoCD's RBAC for teams. Module 22.

**ApplicationSet.** Generates Applications from a template and a generator, such as a list, the folders in a repository, the clusters ArgoCD knows, or open pull requests. Module 22.

**Sync status and health status.** Sync says whether the cluster matches Git (`Synced`, `OutOfSync`). Health says whether the app works (`Healthy`, `Progressing`, `Degraded`). They're independent: a broken release is `Synced` and `Degraded`. Module 22.

**Drift, self-heal and prune.** Drift is any difference between Git and the cluster, like a manual `kubectl scale`. With `selfHeal`, ArgoCD undoes it. With `prune`, it deletes resources that left Git. Module 22.

**Sync wave and hook.** A wave (annotation `argocd.argoproj.io/sync-wave`) orders resources: lower waves go first, and each wave must be healthy before the next. A hook (`argocd.argoproj.io/hook`) runs a resource, usually a Job, at a phase of the sync, such as PreSync for a database migration. Module 22.

**Kustomize base and overlay.** A base holds shared manifests. An overlay, one per environment, points at the base and changes only what differs, like replicas or an image tag. `kubectl apply -k` and ArgoCD render it without extra tools. Module 22.

**Refresh and reconcile.** ArgoCD reconciles each Application every 3 minutes by default: it fetches Git, renders the manifests and compares them with the cluster. A refresh (the `argocd.argoproj.io/refresh` annotation, the UI button or a Git webhook) does it at once. Module 22.

**Sync operation.** One ArgoCD sync attempt, stored in `status.operationState`. It holds a fixed Git revision that stays the same through all its retries. Module 22.

## Metrics and alerting

**Counter, gauge and histogram.** The three common metric types. A counter only goes up (requests served) and means something through `rate()`. A gauge goes up and down (memory in use). A histogram counts observations into buckets, labelled `le` ("less than or equal"), so you estimate percentiles with `histogram_quantile()`. Module 23.

**`rate()` and `sum by`.** `rate(x[1m])` turns a counter into a per-second speed over the last minute. `sum by (label)` adds series up and keeps only the labels you name. Module 23.

**Recording rule.** A query Prometheus evaluates on a schedule and stores as a new series, so dashboards and alerts read a cheap precomputed value. Named `level:metric:operation`, like `shop:backend_error_ratio:rate5m`. Module 23.

**Alerting rule, pending and firing.** A query that defines "broken". When it returns a result, the alert turns `pending`; after it has held for the rule's `for:` duration, it turns `firing` and goes to Alertmanager. Module 23.

**Alertmanager: route, receiver, grouping, silence.** A route matches alerts by label and sends them to a receiver (Slack, PagerDuty, a webhook). Grouping folds many alerts into one message. A silence mutes matching alerts for a time window without changing the rules. Module 23.

**AlertmanagerConfig and PrometheusRule.** Prometheus operator resources. A PrometheusRule holds recording and alerting rules; an AlertmanagerConfig holds a team's routes and receivers. The operator merges both into the running configuration, so teams keep them next to their apps. Module 23.

**SLI, SLO and error budget.** An SLI measures what users experience (the share of requests without a 5xx). An SLO is the target for it (99%). The error budget is what the target leaves over (1%), the amount of failure you accept. Module 23.

**Burn rate.** How fast you spend the error budget. A burn rate of 1 uses it up exactly by the end of the SLO period; 14.4 uses it 14.4 times faster. Multi-window burn-rate alerts check a long and a short window together. Module 23.

**Cardinality.** The number of distinct series a metric produces: every combination of label values counts once. High-cardinality labels, like user ids, blow up Prometheus' memory. Module 23.

**Time series.** One metric name with one exact set of labels, holding a timestamped value from every scrape. Change one label value and you get a new series. Module 23.

**Instant vector and range vector.** An instant vector holds each series' newest sample. A range vector, such as `[1m]`, holds every sample in a window; `rate()` needs one, with at least two samples in it. Module 23.

**Head block.** The newest two hours or so of samples, which Prometheus keeps in memory before it writes them to disk. Module 23.

## Grafana

**Provisioned dashboard.** A dashboard Grafana loads from a file instead of its database. Grafana refuses to save changes to it, because the next load would overwrite them; you change the file in Git instead. Module 24.

**Dashboard sidecar.** A small container in the Grafana pod that watches for ConfigMaps labelled `grafana_dashboard: "1"`, in every namespace, and writes their JSON where Grafana's provisioning picks it up. Module 24.

**Panel, variable and threshold.** A panel is one visualisation with its query. A variable is a dropdown that panels use as `$name`, so one dashboard serves many services. A threshold colours a value by where it sits, like red below 99%. Module 24.

**Contact point and notification policy.** Grafana alerting's version of Alertmanager receivers and routes. The default contact point sends email to a placeholder address, so new Grafana alerts reach nobody until you change it. Module 24.

**Trace-to-logs link (derived field).** Settings on Grafana data sources that turn a trace id into a jump between Jaeger and Loki: "Logs for this span" in a trace, and "Open trace in Jaeger" next to a `trace_id` in a log line. Modules 6 and 24.

## OpenTelemetry and Tempo

**OpenTelemetry (OTel) and OTLP.** The CNCF standard for telemetry: SDKs for every language, one protocol (OTLP, on gRPC port 4317 and HTTP port 4318) and the Collector. Instrument once, then choose back ends freely. Module 25.

**OpenTelemetry Collector.** A service that receives, processes and exports telemetry. Its components are **receivers** (data in), **processors** (change it), **exporters** (data out) and **connectors** (turn one pipeline's output into another's input, such as traces into metrics), wired together in pipelines. Runs as a gateway Deployment, a per-node DaemonSet, or both. Module 25.

**Resource and span attributes.** Resource attributes describe who sent the telemetry: service, pod, node, image. Span attributes describe one operation: HTTP status, database statement. In TraceQL they're `resource.` and `span.`. Module 25.

**Semantic conventions.** OpenTelemetry's agreed attribute names, like `http.response.status_code`. They change between versions, so older instrumentation may still send `http.status_code`. Module 25.

**Grafana Tempo and TraceQL.** Tempo stores traces cheaply in object storage, without indexing every attribute. TraceQL queries them by attributes, duration and structure: `{ span.http.status_code >= 500 }`, or `{ A } >> { B }` for spans of B below spans of A. Module 25.

**Span metrics.** Request rate, errors and duration calculated from spans, here by the Collector's `span_metrics` connector. They give RED metrics to apps that export no metrics of their own. Module 25.

**Tail sampling.** Deciding which traces to keep after they're complete, so you keep every error trace and a fraction of the rest. Needs all spans of a trace in one place, which is a job for the Collector. Module 25.

**Context propagation and `traceparent`.** Passing the trace ID and the parent span ID from service to service, in the W3C `traceparent` header, so spans join into one trace. Modules 6 and 25.

## Policy as code

**Admission webhook.** A service the API server calls before it stores an object. Mutating webhooks change the object, then validating webhooks allow or refuse it. `failurePolicy: Fail` refuses requests while the webhook is down; `Ignore` lets them through. Module 26.

**Kyverno.** A CNCF policy engine for Kubernetes, configured with YAML policies. A `ClusterPolicy` holds rules that **validate** (Audit reports, Enforce refuses), **mutate**, **generate** or **verify images**. Kyverno 1.18 adds CEL-based types such as `ValidatingPolicy`. Module 26.

**Autogen.** Kyverno copies a rule written for Pods to Deployments, ReplicaSets, Jobs and CronJobs, so a bad Deployment gets refused when you apply it, not when its pods start. Module 26.

**PolicyReport.** A Kubernetes object listing which resources pass, fail or skip each policy, per namespace. The evidence for an audit. Module 26.

**PolicyException.** A written exception to named policy rules for named resources. In this lab only the `kyverno` namespace accepts them, so teams don't get to exempt themselves. Module 26.

**CEL and ValidatingAdmissionPolicy.** CEL (Common Expression Language) is a small expression language Kubernetes uses for validation rules. ValidatingAdmissionPolicy is Kubernetes' built-in, webhook-free policy type written in CEL. OPA Gatekeeper is the other common policy engine, with policies in Rego. Module 26.

**Background scan.** Kyverno's regular re-check of stored objects against its policies. It writes reports and refuses nothing. Module 26.

## Retrieval-augmented generation

**Embedding and embedding model.** An embedding is a list of numbers (768 for `nomic-embed-text`) that places a text so that similar meanings land close together. An embedding model produces them. Vectors from different embedding models aren't comparable. Module 27.

**Vector database and cosine similarity.** A database that stores embeddings and finds the nearest ones to a new vector quickly, such as Qdrant, Weaviate, Milvus, or Postgres with pgvector. Cosine similarity measures closeness: 1 for the same direction, 0 for unrelated. Module 27.

**Chunking and top-k.** Chunking splits documents into passages before embedding them, ideally one idea per chunk. Top-k is how many of the nearest chunks go to the model: more chunks mean fewer retrieval misses and more input tokens. Module 27.

**Temperature.** How random a model's word choice is. At 0 it always picks the most likely next word, so the same question gets the same answer. Module 27.

**Evaluation set.** Questions with known answers and expected sources, run after every change to chunking, models or prompts, like a test suite for a RAG system. Module 27.

**HNSW.** A graph index that lets a vector database find near neighbours approximately, without comparing the query with every stored vector. Module 27.

## Continuous profiling

**Profile and pprof.** A profile records where a program spends CPU or allocates memory, as sampled call stacks. pprof is Go's built-in profiler and its file format, served at `/debug/pprof`. Module 28.

**Continuous profiling.** Collecting low-rate profiles from every service all the time, so you look back at a spike instead of reproducing it. People call profiles the fourth signal, after metrics, logs and traces. Module 28.

**Flame graph, self and total.** A flame graph draws call stacks as bars, each as wide as its share of samples, one level below its caller. Self counts samples inside the function; total counts samples anywhere below it. Look for the widest total bar that's your own code. Module 28.

**Grafana Pyroscope.** A continuous profiling database that stores pprof data and shows flame graphs in Grafana. Agents such as Alloy pull profiles from annotated pods, SDKs push them, and eBPF profilers sample whole nodes. Module 28.

**alloc_space and inuse_space.** Go memory profiles. `alloc_space` counts every byte allocated in a time window, even memory freed right away; `inuse_space` counts what's still held. Module 28.

**Sampling profiler.** A profiler that records the call stack at fixed intervals (100 times a second here) instead of tracing every call, so it costs little enough to run all the time. Module 28.

## How Kubernetes works inside

**Reconcile loop, watch and informer.** Every controller watches the API server for the objects it cares about, compares what exists with what should exist, and acts to close the gap, over and over. An informer is the client-side cache a controller builds from its watch. Module 29.

**Owner reference and garbage collector.** A field that links an object to the one that created it: Pod to ReplicaSet to Deployment. When the owner goes, the garbage collector deletes what it owned. Module 29.

**Scheduler: filter, score, bind, preemption.** The scheduler picks a node for each new pod. Filter drops nodes that don't fit (resource requests, taints, selectors), score ranks the rest, bind writes `spec.nodeName`. With no node left, preemption may evict lower-priority pods. It counts requests, never limits. Module 29.

**Authentication, authorization, admission.** The API server's gates, in order: who are you (certificates, tokens), may you do this (the Node authorizer and RBAC), and should the object change or be refused (admission plugins and webhooks). Members of `system:masters` skip RBAC. Module 29.

**etcd and kine.** etcd is the key-value store that holds every Kubernetes object in most clusters, replicated with the Raft protocol. k3s uses kine instead by default: it speaks the etcd API to the API server and stores the data in SQLite. Modules 21 and 29.

**CRI, sandbox and CNI.** The kubelet talks to the container runtime (containerd) through the Container Runtime Interface. The runtime first creates a sandbox, a `pause` container that owns the pod's network namespace, then runs the CNI plugins (here flannel, then istio-cni) to give it an IP and network rules. Module 29.

**EndpointSlice.** The list of ready pod IPs behind a Service. kube-proxy, CoreDNS and istiod all read it. Module 29.

**DNAT and conntrack.** DNAT rewrites a packet's destination address, such as a Service IP to a pod IP. conntrack is the kernel's table of connections and their rewrites, so replies get the original addresses back. Module 29.

**Watch cache.** The API server's in-memory copy of recent objects and changes. Watchers read from it, so a thousand controllers don't mean a thousand database reads. Module 29.

**resourceVersion and optimistic concurrency.** Every stored object carries a `resourceVersion`. An update must name the version it read; if somebody wrote in between, the API server answers 409 Conflict and the writer reads again and retries. Module 29.

**Lease and leader election.** A Lease is a small object that one copy of a component renews every few seconds to say "I'm in charge". With several copies of the scheduler or controller manager, only the Lease holder acts. Module 29.

**QoS class.** Kubernetes sorts pods by their requests and limits: Guaranteed (requests equal limits), Burstable (some requests or limits set), BestEffort (none). Under memory pressure, the kubelet evicts BestEffort first and Guaranteed last. Module 29.

**Field validation.** `fieldValidation=Strict` on a write asks the API server to refuse unknown or duplicate fields instead of dropping them silently. kubectl sends it by default. Module 29.

## Linux networking under Kubernetes

**Network namespace.** A separate copy of the network stack: its own interfaces, addresses, routes and iptables rules. Every pod has one, owned by its `pause` container. Module 29.

**veth pair.** A virtual cable with two ends. One end is `eth0` inside the pod; the other sits on the node, plugged into the bridge. Module 29.

**Bridge (cni0).** A virtual Layer 2 switch on the node. Every pod's veth plugs into it, and the bridge holds the pods' gateway address, `10.42.0.1`. Module 29.

**ARP.** How a machine finds the MAC address for an IP on the same Layer 2 network. The node's `ip neigh` table shows what it learned. Module 29.

**MTU and MSS.** The MTU is the largest packet an interface sends (1450 for pods here). The MSS is the largest TCP payload, the MTU minus 40 bytes of IP and TCP headers (1410 here). Module 29.

**VXLAN.** A tunnel that wraps a Layer 2 frame in a UDP packet. flannel uses it (device `flannel.1`, port 8472) to carry pod traffic between nodes; its 50-byte header is why pods get MTU 1450. Module 29.

**SNAT and masquerade.** SNAT rewrites a packet's source address. Masquerade is SNAT to the address of the interface the packet leaves through. kube-proxy masquerades traffic that enters from outside the cluster, so replies come back through the same node. Module 29.

**externalTrafficPolicy.** A Service setting. `Cluster` (the default) lets any node accept the traffic and SNATs it, which hides the client's address. `Local` keeps the client's address but only sends traffic to pods on the node that received it. Module 29.

**Host port.** A container port bound to the node's own address, implemented by the CNI's portmap plugin with a DNAT rule. k3s's svclb pods use one. Module 29.

**kube-router.** The network policy controller k3s embeds. It turns NetworkPolicy objects into iptables rules on every node. Module 29.

**Probe source 169.254.7.127.** In ambient mode, istio-cni rewrites the kubelet's probe traffic to this link-local address, and ztunnel lets it through without mTLS, so health checks work under STRICT mode. Module 29.
