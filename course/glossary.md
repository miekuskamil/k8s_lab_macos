# Glossary

Every Istio resource and term this course uses, in plain words. Each entry starts with one sentence that says what the thing is for. Then it gives the detail, a small example where that helps, and the module that puts it to work. If a module mentions something and you're not sure what it is, look here first.

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
- [CKS exam track](#cks-exam-track)

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

**Service mesh.** A service mesh is a layer of proxies that handles encryption, identity, routing, retries and measurements for every request between your services. Because the proxies sit in the path of every request, the application code doesn't have to do this work. Module 1.

**Data plane.** The data plane is the set of proxies that touch your traffic: ztunnel, waypoints, sidecars and gateways. If the data plane stops, requests stop.

**Control plane.** The control plane is the part of the mesh that only gives orders to the proxies. In Istio, that's istiod. It never sees a request.

**istiod.** istiod is Istio's control plane, one Deployment in `istio-system`, that configures every proxy and signs every workload's identity. It watches the Kubernetes API and turns your Istio and Gateway API resources into proxy configuration. It pushes that configuration out over xDS, and it acts as the certificate authority. Modules 1, 2, 14.

**Envoy.** Envoy is the open-source proxy that does the HTTP work in Istio. Lyft released it in 2016. Sidecars, waypoints and gateways all run Envoy, and its container image goes by the name `proxyv2`.

**Ambient mode.** Ambient mode is Istio's newer data plane design, which works without sidecars. ztunnel on each node handles L4 for every pod, and waypoints handle L7 only where you deploy them. A namespace joins with the label `istio.io/dataplane-mode: ambient`, and its pods need no restart. The lab's `shop` namespace uses it. Module 1.

**Sidecar mode.** Sidecar mode is Istio's original design, which adds an Envoy container to every pod to handle both L4 and L7 for that pod. A namespace joins with `istio-injection: enabled` (or `istio.io/rev`). Pods get the sidecar only when they restart. Module 7.

**ztunnel.** ztunnel ("zero-trust tunnel") is a small Rust proxy that encrypts and checks the traffic of every mesh pod on its node in ambient mode. It runs once per node, as a DaemonSet. It holds the certificates of every mesh pod on its node, wraps their traffic in mTLS (HBONE), and enforces L4 rules. It never reads HTTP. Modules 1, 2, 3.

**Waypoint.** A waypoint is an Envoy proxy that handles L7 for a namespace or a service in ambient mode. Its jobs include HTTP routing, L7 authorization, retries, faults and HTTP metrics. You create it as a Gateway with `gatewayClassName: istio-waypoint`, and you point traffic at it with the label `istio.io/use-waypoint`. The lab's backend uses one. Modules 1, 3, 4.

**Sidecar.** A sidecar is the Envoy container (`istio-proxy`) that sits inside each pod in sidecar mode and carries all its traffic. An init container, `istio-init`, sets up the iptables rules that send the pod's traffic through it. Module 7. Don't mix it up with the Sidecar resource below.

**istio-cni.** istio-cni is a node agent (DaemonSet) that sends each ambient pod's traffic through ztunnel. It does this by setting up redirect rules inside each mesh pod's network namespace. It also answers pods' DNS when DNS capture is on. Modules 2, 12, and troubleshooting problems 15 and 18.

**Ingress gateway.** An ingress gateway is an Envoy at the edge of the mesh that accepts traffic from outside the cluster. In this lab, it's `shop-gateway-istio` in `shop-ingress`, created from a Gateway API Gateway. Modules 4, 11.

**Egress gateway.** An egress gateway is an Envoy that all traffic to the outside world passes through, so one place applies the rules and writes the logs. In ambient mode, a waypoint plays this role. Module 12.

**East-west and north-south.** These are names for the two directions of traffic in a cluster. East-west traffic flows between services inside the cluster, through ztunnel and waypoints. North-south traffic enters or leaves the cluster, through the ingress gateway or out to the internet. Module 4.

**In-pod redirection.** In-pod redirection is how ambient mode catches a pod's traffic without the traffic leaving the pod. istio-cni adds redirect rules inside each ambient pod's network namespace. ztunnel listens there on ports 15001, 15006, 15008 and 15053, so the pod's traffic reaches ztunnel directly. Modules 1 and 29.

## Traffic resources

**Gateway (Gateway API).** A Gateway is a Kubernetes-standard resource (`gateway.networking.k8s.io/v1`) that asks for a proxy with listeners, meaning ports, protocols and TLS certificates. Istio sees it and creates an Envoy Deployment and Service for it. The class decides the role. `istio` makes an ingress gateway, and `istio-waypoint` makes a waypoint. Modules 4, 11.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: {name: shop-gateway, namespace: shop-ingress}
spec:
  gatewayClassName: istio
  listeners: [{name: http, port: 8080, protocol: HTTP}]
```

**Gateway (Istio API).** This Gateway is Istio's older resource (`networking.istio.io/v1`) with the same name, which configures gateway pods that already exist. It doesn't create a proxy. It sets ports, hosts and TLS on gateway pods picked with a label `selector`. A VirtualService then attaches to it through its `gateways:` field. Many existing Istio setups and the ICA exam use it. Module 16 compares the two.

**GatewayClass.** A GatewayClass is a Gateway API resource that names which implementation runs a Gateway. Istio installs `istio` and `istio-waypoint`.

**HTTPRoute.** An HTTPRoute is a Gateway API resource that holds HTTP routing rules. A rule matches on path, headers or method, then sends to one or more backends with weights. It may also rewrite, redirect, time out or retry. `parentRefs` says what the route attaches to. That is a Gateway for ingress, or a Service for mesh traffic, applied by that Service's waypoint. Modules 4, 5, 11.

```yaml
kind: HTTPRoute
spec:
  parentRefs: [{group: "", kind: Service, name: backend}]
  rules:
    - backendRefs:
        - {name: backend-v1, port: 8000, weight: 90}
        - {name: backend-v2, port: 8000, weight: 10}
```

**VirtualService.** A VirtualService is Istio's own routing resource, the older counterpart of HTTPRoute. It names one or more `hosts`. Then it lists HTTP routes with matches, destinations (`host`, `subset`, `weight`), timeouts, retries, fault injection and mirroring. Gateway API has no fault injection, so module 5 uses a VirtualService for it. In ambient mode, the waypoint applies it. Modules 5, 7, 16.

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

Modules 5, 12, 15.

```yaml
kind: DestinationRule
spec:
  host: backend
  trafficPolicy:
    connectionPool: {http: {http1MaxPendingRequests: 1, maxRequestsPerConnection: 1}}
  subsets:
    - {name: v1, labels: {version: v1}}
```

**Subset.** A subset is a named group of a service's pods, defined by labels in a DestinationRule. VirtualServices route to subsets. HTTPRoutes use one Service per version instead. Module 4.

**ServiceEntry.** A ServiceEntry is a resource that adds a host the mesh doesn't know, usually outside the cluster, to the mesh's service registry. After that, traffic to the host gets names in metrics, routing rules and authorization. `location: MESH_EXTERNAL` marks it as outside, and `resolution: DNS` tells Envoy to look up its IPs. In ambient mode, it needs a virtual IP and DNS capture to reach a waypoint. Module 12.

**Sidecar (resource).** The Sidecar resource (`networking.istio.io/v1 Sidecar`) is a resource that limits which hosts one sidecar proxy knows about and may reach. It also sets the outbound policy, for example `REGISTRY_ONLY` to block unknown hosts. It works in sidecar mode only, and ambient has no equivalent. The course doesn't use it, but large sidecar installs often use it to cut memory.

**EnvoyFilter.** An EnvoyFilter is a resource that patches raw Envoy configuration when no Istio resource covers what you need. It is powerful but breaks easily across upgrades, and Istio 1.24 doesn't support it on waypoints. Module 5 mentions it.

**ReferenceGrant.** A ReferenceGrant is a Gateway API resource that lets a resource in one namespace point at an object in another. For example, a Gateway may use a TLS Secret from a different namespace. The owner of the target namespace creates it. Module 11.

**WorkloadEntry.** A WorkloadEntry is a resource that registers a single non-Kubernetes machine, such as a VM, as a mesh workload. This course doesn't use it.

## Security resources

**PeerAuthentication.** PeerAuthentication (`security.istio.io/v1`) is a resource that says whether a workload accepts plain text. It has three modes:

- `STRICT` accepts mTLS only.
- `PERMISSIVE`, the default, accepts mTLS and plain text, so you enroll workloads gradually.
- `DISABLE` accepts plain text only.

Put it in `istio-system` for the whole mesh, or in a namespace for that namespace. Add a `selector` for single workloads. Modules 2, 7.

**AuthorizationPolicy.** An AuthorizationPolicy is a resource that decides whether a request may pass. `action` is `ALLOW`, `DENY`, `CUSTOM` (ask an external service) or `AUDIT`. `rules` match on three things:

- `from`, the source identity: `principals`, `namespaces`, `requestPrincipals`
- `to`, the operations: ports, methods, paths
- `when`, extra conditions such as token claims

Where you attach the policy decides who enforces it. A `selector` (pod labels) makes ztunnel enforce the L4 parts. `targetRefs` to a Service, Gateway or ServiceEntry makes that waypoint or gateway enforce L7. Istio evaluates CUSTOM first, then DENY, then ALLOW. Modules 3, 12, 13.

**Principal.** A principal is the workload identity that an AuthorizationPolicy matches, written without the `spiffe://` prefix. Example: `cluster.local/ns/shop/sa/frontend`. Module 3.

**RequestAuthentication.** RequestAuthentication is a resource that tells a proxy which end-user tokens (JWTs) to trust. It names the issuer, the audience and the public keys (JWKS). It rejects bad tokens with 401 but lets requests without a token through. An AuthorizationPolicy with `requestPrincipals` makes a token mandatory. Module 13.

**Request principal.** A request principal is the end-user identity taken from a checked JWT, written as `<issuer>/<subject>`. Example: `https://idp.k8s-lab.local/alice`. Module 13.

## Observability and operations

**Telemetry.** Telemetry (`telemetry.istio.io/v1`) is a resource that turns tracing, metrics and access logs on or off and picks where they go. It applies to the mesh, a namespace or one proxy. The lab sends traces to Jaeger with it. Module 6.

**Trace and span.** A trace is the record of one request through every service it touches, and a span is one step inside it. A trace is a tree of spans. Each span records who did the step, when it started and how long it took. All spans of a trace share one trace ID, which travels in the `traceparent` header. Module 6.

**Sampling.** Sampling is keeping only a share of traces, chosen at random when a request enters the mesh. The lab keeps 100%. Production systems often keep 1 to 5%, because storing every trace costs a lot. Module 6.

**Access log.** An access log is a file of one line per request, written by a proxy. Each line holds the method, path, status code, response flags, timings and upstream. The lab has it off by default. A Telemetry resource turns it on for the waypoint. Modules 3, 5, 6.

**Reporter.** The reporter is a label on Istio's request metrics that says which proxy recorded them. `source` means the calling side, here the ingress gateway or a client sidecar. The other values are `waypoint` and `destination`, a sidecar on the receiving side. Modules 6, 7.

**Percentile (p95, p99).** A percentile is the value that a given share of measurements stays under, such as 95% (p95) or 99% (p99). A p95 latency of 200 ms means one request in twenty took longer. Prometheus estimates it from histogram buckets. Buckets are counters of how many requests fell into each time range, 0.5, 1, 5, 10, 25 ms and up for Istio. So the result often lands on a bucket edge. Modules 5, 6.

**PodMonitor.** A PodMonitor is a prometheus-operator resource that tells Prometheus which pods to scrape, on which port and path. The lab ships PodMonitors for the gateway, the waypoint and ztunnel. Module 7 adds one for the sidecars.

**istioctl.** istioctl is Istio's command-line tool for inspecting and checking the mesh. The course uses these commands:

- `proxy-status` shows which proxies use which control plane, and whether their config is current.
- `ztunnel-config` shows what ztunnel knows.
- `proxy-config` shows a sidecar or gateway's Envoy config.
- `analyze` finds mistakes in your resources.
- `x precheck` checks a cluster before an upgrade.

Module 9 lists them by layer.

**Revision.** A revision is a name for one installed control plane, such as `1-25-5`. The original install without a name is `default`. Proxies choose a revision with the label `istio.io/rev`. Module 14.

**Tag (revision tag).** A revision tag is a movable nickname, such as `default` or `stable`, that points at a revision. Move the tag, and every workload labelled with it follows. Module 14.

**Head sampling.** Head sampling is a way of sampling where the first proxy on a request decides once whether to keep its trace. It writes the decision into the `traceparent` header, and every later hop follows that decision. Module 6.

## Protocols and identity

**L4 and L7.** L4 and L7 are layers of the network model that a proxy looks at. L4 means connections, that is IP addresses and ports (TCP). L7 means the application protocol, here HTTP, with methods, paths, headers and status codes. ztunnel works at L4. Waypoints and sidecars work at L7.

**mTLS (mutual TLS).** mTLS is a form of TLS where both sides show a certificate, so each proves its identity to the other. Both sides also encrypt the traffic. Every connection between mesh workloads uses it. Module 2.

**SPIFFE ID.** A SPIFFE ID is the identity inside a mesh certificate, written as a URI such as `spiffe://cluster.local/ns/shop/sa/frontend`. Its parts are the trust domain, the namespace and the service account. Module 2.

**Trust domain.** The trust domain is the first part of a SPIFFE ID (`cluster.local` here). Workloads trust certificates from the same trust domain.

**HBONE.** HBONE ("HTTP-Based Overlay Network Environment") is the encrypted tunnel that ztunnel and waypoints use between pods. It is one mTLS connection on port 15008 that carries many TCP streams as HTTP/2 CONNECT requests. Module 2.

**xDS.** xDS is the family of APIs that istiod uses to push configuration to proxies. Each letter names one kind of configuration:

- LDS: listeners
- RDS: routes
- CDS: clusters, meaning upstream services
- EDS: endpoints, meaning pod IPs
- SDS: secrets, meaning certificates

ztunnel uses Istio's own WDS and WADS (workloads and addresses). You see these letters in `istioctl proxy-status`. Modules 1, 11.

**SNI (Server Name Indication).** SNI is the name a client sends at the start of a TLS handshake, so one IP address serves many sites with different certificates. Module 11.

**TLS termination and origination.** These are the two ways a proxy handles TLS for someone else. Termination means a proxy ends a TLS session and reads the request inside, like the ingress gateway in module 11. Origination means a proxy starts a TLS session on the app's behalf, so the app sends plain HTTP, like the waypoint in module 12.

**X-Forwarded-Client-Cert (XFCC).** XFCC is a header that a sidecar adds to requests it passes to its app, so the app learns who called without touching TLS. It names the caller (`URI=spiffe://...`) and the receiver (`By=...`) from the mTLS handshake. Module 7.

**DNS capture.** DNS capture is an ambient-mode feature where istio-cni redirects a pod's DNS queries to ztunnel. ztunnel answers for ServiceEntry hosts with their virtual IP. Module 12.

**Subject Alternative Name (SAN).** The SAN is the list of names inside a certificate. A TLS client compares it with the host name it connected to. Istio puts the workload's SPIFFE ID there. Modules 11 and 29.

**Trust store.** A trust store is the set of CA certificates a client trusts, such as curl's built-in list or a file passed with `--cacert`. A certificate is trusted only if its chain ends at one of them. Module 11.

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
| `NC` | No cluster | The route points at a Service Envoy has no cluster for, for example a misspelled or deleted one (module 4) |
| `DC` | Downstream connection termination | The caller hung up early |
| `-` | No flag | Envoy passed the response on unchanged |

Modules 4, 5, 6, 8.

## Around the mesh

**Gateway API.** Gateway API is the Kubernetes project's standard API for traffic routing. It includes Gateway, HTTPRoute, GatewayClass and ReferenceGrant, and Istio, Cilium, Envoy Gateway and others implement it. Istio recommends it over its own VirtualService and Istio Gateway for new setups. It's the main API in ambient mode.

**cert-manager.** cert-manager is a Kubernetes controller that issues and renews TLS certificates. An Issuer or ClusterIssuer says who signs. A Certificate says what you want, and the result lands in a Secret. Module 11.

**JWT and JWKS.** A JWT (JSON Web Token) is a token that carries signed claims about a user. A JWKS (JSON Web Key Set) publishes the public keys that check those signatures. Module 13.

**NetworkPolicy.** NetworkPolicy is a plain Kubernetes resource that allows or blocks connections by pod labels, namespaces and IP ranges. The node's packet filter enforces it, below the mesh. Module 12 uses one to force traffic through the waypoint.

**Idempotent request and idempotency key.** An idempotent request is a request that has the same effect whether you send it once or twice, like a GET. A POST that creates an order is not idempotent. An idempotency key is a unique ID the client sends with such a request, so the server spots a repeat and skips it. Safe retries depend on this. Module 5.

**Loki and LogQL.** Loki is a log store that keeps costs low by indexing only a few labels per stream (namespace, app, pod), not the text. LogQL is its query language:

- `{app="backend"}` picks streams.
- `|= "text"` filters lines.
- `| json` turns JSON fields into labels.
- `count_over_time`, `rate` and `unwrap` turn lines into numbers.

Module 6.

**Kiali.** Kiali is the Istio console that shows a traffic graph, mTLS status and config checks. It works next to the other observability tools in the lab:

- Jaeger shows traces.
- Prometheus stores metrics.
- Grafana shows dashboards and runs queries over Prometheus, Loki and Jaeger.
- Loki stores logs.

Module 6.

**eBPF.** eBPF is a way to load small programs into the Linux kernel at runtime, after a verifier checks they are safe. Cilium uses them for fast packet handling, policy and tracing. Module 10.

**Cilium.** Cilium is a CNI plugin that uses eBPF for pod networking, Service load balancing and network policy. It hands Layer 7 rules to an Envoy per node. Module 10.

**Kernel space and user space.** These are the two places where code runs on a Linux machine. The kernel owns network interfaces and the packet filter. Ordinary programs such as Envoy and ztunnel run in user space and reach the network through sockets, which costs copies and context switches. Module 10.

## AI on Kubernetes

**LLM (large language model).** An LLM is a model that reads text and writes text, such as Qwen, Llama or Claude. "14B" in a model name means 14 billion parameters. Bigger models answer better and run slower. Modules 17 to 19.

**Ollama.** Ollama is a tool that downloads open models and serves them over a small HTTP API on port 11434. The API has `/api/chat`, `/api/tags`, `/api/pull` and `/api/delete`. It has no authentication. Modules 17, 18.

**Token.** A token is the unit a model reads and writes, a piece of a word of about four characters of English. Hosted models bill per token, input and output separately. Token counts belong on every dashboard for AI traffic. Module 17.

**Prompt.** A prompt is everything a model receives: instructions (the system prompt), data and the question. Module 17.

**RAG (retrieval-augmented generation).** RAG is a method that fetches real data first, puts it into the prompt and then asks the model. That way, the model answers from your data instead of from memory. The shop assistant does this with orders (module 17). Module 27 builds a full one over the course, with a vector database. Modules 17 and 27.

**GenAI semantic conventions.** The GenAI semantic conventions are OpenTelemetry's standard attribute names for model calls. Examples are `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens` and `gen_ai.usage.output_tokens`. Tools like Jaeger and Grafana read them the same way whatever the model. Module 17.

**AI gateway.** An AI gateway is a proxy built for model traffic. It counts rate limits in tokens, switches between model providers, caches prompts and filters what goes in and out. Examples are agentgateway, kgateway and Envoy AI Gateway. Module 17.

**Inference.** Inference is running a trained model to get an answer, as opposed to training it. A model server like Ollama or vLLM does inference. Module 18.

**Model server.** A model server is the program that loads a model and answers requests over HTTP. Examples are Ollama, llama.cpp, vLLM and NVIDIA Triton. Module 18 runs llama.cpp.

**GGUF.** GGUF is the model file format that llama.cpp and Ollama read. One file holds the whole model. It is often shrunk ("quantised", the `q4_k_m` in a file name) to fit in less memory. Module 18.

**OpenAI-compatible API.** The OpenAI-compatible API is the request format OpenAI made popular, `POST /v1/chat/completions` with the model name in the JSON body. Most model servers and AI tools speak it. Module 18.

**Gateway API Inference Extension.** The Gateway API Inference Extension is a Kubernetes standard for routing requests to model servers. An InferencePool groups model server pods. An endpoint picker chooses a pod by the servers' own metrics, such as queue length, instead of round robin. Istio supports it from 1.27. Module 18.

**AI agent.** An AI agent is a program that lets a model act. It sends the model a question plus a list of tools. It runs the tool calls the model asks for, feeds back the results, and repeats until the model answers. Module 19.

**Tool.** A tool is a function that an agent offers its model, such as "list pods" or "delete a resource". It comes with a description the model reads to decide when to use it. Module 19.

**MCP (Model Context Protocol).** MCP is the standard way for agents to reach tools. It uses JSON-RPC over HTTP, with every call sent to one URL (`/mcp`) and the tool name inside the JSON body. A tool server describes its tools and runs them. Module 19.

**A2A (Agent2Agent).** A2A is a protocol that lets clients and agents send tasks to an agent and get results back. kagent serves it on its controller, port 8083. Module 19.

**kagent.** kagent is a CNCF Sandbox project that runs AI agents on Kubernetes. Agents, models (ModelConfig) and tool servers (RemoteMCPServer) are custom resources. Module 19.

**Prompt injection.** Prompt injection is text that reaches a model through data and carries instructions the model may follow. The data might be a log line, a web page or a pod annotation. No model resists it reliably. Module 19.

**Excessive agency.** Excessive agency is an agent holding more tools or permissions than its job needs. Then a mistake, a prompt injection or a direct call to its tools does real damage. It is on the OWASP Top 10 for LLM applications. Module 19.

**Prefill and decode.** Prefill and decode are the two phases of a model's answer. Prefill reads the whole prompt in one pass. Decode then writes the answer one token at a time, so the output length decides how long the user waits. Module 17.

**Tool calling.** Tool calling is a model skill where the model answers with a tool name and JSON arguments instead of text. The agent program runs that call and sends back the result. Module 19.

**Confused deputy.** A confused deputy is a program with strong rights that acts for a caller with weak ones. An example is a tool server with wide RBAC rights that answers any agent user. Module 19.

## Kubernetes operations

**Cordon, drain, uncordon.** These are the three commands that take a node out of service and bring it back. Cordon marks a node unschedulable. Drain cordons it and evicts its pods one by one, respecting PodDisruptionBudgets, and DaemonSet pods stay. Uncordon makes it schedulable again, but moves nothing back. Module 20.

**PodDisruptionBudget (PDB).** A PDB is a rule like "keep at least one `web` pod running" that evictions must respect. It covers voluntary disruptions such as drains and upgrades, not crashes. Module 20.

**DaemonSet.** A DaemonSet is a workload that runs one pod on every node, such as ztunnel, istio-cni or a log shipper. Drains leave these pods alone. Module 20.

**`ttlSecondsAfterFinished` and `revisionHistoryLimit`.** These are two settings that clean up old objects. The first deletes a finished Job after a delay. The second caps how many old ReplicaSets a Deployment keeps for `kubectl rollout undo` (default 10). Module 20.

**ServiceLB (svclb).** ServiceLB is k3s's built-in load balancer, which gives each Service of type LoadBalancer an external IP. It uses the node's IP as that external IP, and it runs a small `svclb-...` pod with a host port that forwards to the Service. kube-proxy also writes a rule for that external IP, and the kernel checks kube-proxy's rules first. So in this lab, kube-proxy DNATs the traffic straight to the gateway pod, and the svclb pod's rule stays unused. Modules 1 and 29.

**k3s.** k3s is a small Kubernetes distribution in one binary. It brings its own containerd, flannel, and an SQLite or etcd datastore. The lab runs it inside Docker with k3d. Modules 20, 21.

**system-upgrade-controller.** The system-upgrade-controller is a controller that upgrades k3s (and RKE2) nodes from a `Plan` resource. The Plan sets the target version, the node selector, how many nodes at once, and whether to cordon or drain. Module 21.

**Certificate rotation and renewal.** These are two ways to keep certificates valid. Rotation replaces a certificate's key, and renewal extends its expiry. k3s renews certificates within 120 days of expiry each time it starts, and `k3s certificate rotate` rotates them. Module 21.

**CNI plugin directory.** The CNI plugin directory is the folder where containerd looks for network plugins (`bin_dir` or `bin_dirs` in its config). istio-cni must place its plugin there. The k3s upgrade in module 21 moved it. Module 21.

**host-local IPAM.** host-local IPAM is flannel's IP address manager, which hands out pod addresses from the node's range. It keeps one lease file per pod address on the node. It frees the address when the CNI chain's DEL runs. Module 21.

## GitOps and ArgoCD

**GitOps.** GitOps is a way of running a cluster from Git. Git holds the desired state, and an agent inside the cluster keeps the live state matching it. Changes go through commits, and rollbacks through `git revert`. ArgoCD and Flux are the common agents. Module 22.

**Application.** An Application is ArgoCD's resource that links one path in one Git repository to one namespace in one cluster. It also holds a sync policy. Module 22.

**AppProject.** An AppProject is an ArgoCD resource that groups Applications and limits what they may do. It sets which repositories, which destination namespaces and which kinds of resources they may use. It is ArgoCD's RBAC for teams. Module 22.

**ApplicationSet.** An ApplicationSet is an ArgoCD resource that generates Applications from a template and a generator. A generator is a list, the folders in a repository, the clusters ArgoCD knows, or open pull requests. Module 22.

**Sync status and health status.** These are ArgoCD's two separate verdicts on an Application. Sync says whether the cluster matches Git (`Synced`, `OutOfSync`). Health says whether the app works (`Healthy`, `Progressing`, `Degraded`). They're independent, so a broken release is `Synced` and `Degraded`. Module 22.

**Drift, self-heal and prune.** Drift is any difference between Git and the cluster, like a manual `kubectl scale`. With `selfHeal`, ArgoCD undoes it. With `prune`, ArgoCD deletes resources that left Git. Module 22.

**Sync wave and hook.** These are ArgoCD's two ways to control the order of a sync. A wave (annotation `argocd.argoproj.io/sync-wave`) orders resources. Lower waves go first, and each wave must be healthy before the next. A hook (`argocd.argoproj.io/hook`) runs a resource, usually a Job, at a phase of the sync, such as PreSync for a database migration. Module 22.

**Kustomize base and overlay.** These are the two layers Kustomize uses to share manifests between environments. A base holds the shared manifests. An overlay, one per environment, points at the base and changes only what differs, like replicas or an image tag. `kubectl apply -k` and ArgoCD render it without extra tools. Module 22.

**Refresh and reconcile.** These are how ArgoCD compares Git with the cluster. ArgoCD reconciles each Application every 3 minutes by default. It fetches Git, renders the manifests and compares them with the cluster. A refresh does the same at once. You trigger it with the `argocd.argoproj.io/refresh` annotation, the UI button or a Git webhook. Module 22.

**Sync operation.** A sync operation is one ArgoCD sync attempt, stored in `status.operationState`. It holds a fixed Git revision that stays the same through all its retries. Module 22.

## Metrics and alerting

**Counter, gauge and histogram.** These are the three common metric types:

- A counter only goes up, like requests served. It means something through `rate()`.
- A gauge goes up and down, like memory in use.
- A histogram counts observations into buckets, labelled `le` ("less than or equal"). You estimate percentiles from it with `histogram_quantile()`.

Module 23.

**`rate()` and `sum by`.** These are the two most common PromQL functions. `rate(x[1m])` turns a counter into a per-second speed over the last minute. `sum by (label)` adds series up and keeps only the labels you name. Module 23.

**Recording rule.** A recording rule is a query that Prometheus evaluates on a schedule and stores as a new series. Dashboards and alerts then read a cheap precomputed value. It is named `level:metric:operation`, like `shop:backend_error_ratio:rate5m`. Module 23.

**Alerting rule, pending and firing.** An alerting rule is a query that defines "broken". When it returns a result, the alert turns `pending`. After it has held for the rule's `for:` duration, it turns `firing` and goes to Alertmanager. Module 23.

**Alertmanager: route, receiver, grouping, silence.** These are the parts of Alertmanager that decide who hears about an alert. A route matches alerts by label and sends them to a receiver, such as Slack, PagerDuty or a webhook. Grouping folds many alerts into one message. A silence mutes matching alerts for a time window without changing the rules. Module 23.

**AlertmanagerConfig and PrometheusRule.** These are Prometheus operator resources that let teams keep alerting config next to their apps. A PrometheusRule holds recording and alerting rules. An AlertmanagerConfig holds a team's routes and receivers. The operator merges both into the running configuration. Module 23.

**SLI, SLO and error budget.** These are the three numbers behind a reliability target. An SLI (service level indicator) measures what users experience, such as the share of requests without a 5xx. An SLO (service level objective) is the target for it, such as 99%. The error budget is what the target leaves over (1%), the amount of failure you accept. Module 23.

**Burn rate.** Burn rate is how fast you spend the error budget. A burn rate of 1 uses it up exactly by the end of the SLO period, and 14.4 uses it 14.4 times faster. Multi-window burn-rate alerts check a long and a short window together. Module 23.

**Cardinality.** Cardinality is the number of distinct series a metric produces, where every combination of label values counts once. High-cardinality labels, like user IDs, blow up Prometheus' memory. Module 23.

**Time series.** A time series is one metric name with one exact set of labels, holding a timestamped value from every scrape. Change one label value, and you get a new series. Module 23.

**Instant vector and range vector.** These are the two shapes of PromQL data. An instant vector holds each series' newest sample. A range vector, such as `[1m]`, holds every sample in a window. `rate()` needs a range vector with at least two samples in it. Module 23.

**Head block.** The head block is the newest two hours or so of samples, which Prometheus keeps in memory before it writes them to disk. Module 23.

## Grafana

**Provisioned dashboard.** A provisioned dashboard is a dashboard that Grafana loads from a file instead of its database. Grafana refuses to save changes to it, because the next load would overwrite them. You change the file in Git instead. Module 24.

**Dashboard sidecar.** The dashboard sidecar is a small container in the Grafana pod that loads dashboards from ConfigMaps. It watches every namespace for ConfigMaps labelled `grafana_dashboard: "1"`. It writes their JSON where Grafana's provisioning picks it up. Module 24.

**Panel, variable and threshold.** These are the building blocks of a Grafana dashboard. A panel is one visualisation with its query. A variable is a dropdown that panels use as `$name`, so one dashboard serves many services. A threshold colours a value by where it sits, like red below 99%. Module 24.

**Contact point and notification policy.** These are Grafana alerting's versions of Alertmanager receivers and routes. The default contact point sends email to a placeholder address. So new Grafana alerts reach nobody until you change it. Module 24.

**Trace-to-logs link (derived field).** A trace-to-logs link is a setting on Grafana data sources that lets you jump between Jaeger and Loki by trace ID. It adds "Logs for this span" in a trace. It also adds "Open trace in Jaeger" next to a `trace_id` in a log line. Modules 6 and 24.

## OpenTelemetry and Tempo

**OpenTelemetry (OTel) and OTLP.** OpenTelemetry is the CNCF standard for telemetry, so you instrument an app once and then choose back ends freely. It has SDKs for every language, one protocol, and the Collector. The protocol is OTLP, on gRPC port 4317 and HTTP port 4318. Module 25.

**OpenTelemetry Collector.** The OpenTelemetry Collector is a service that receives, processes and exports telemetry. Its components are wired together in pipelines:

- receivers take data in
- processors change it
- exporters send data out
- connectors turn one pipeline's output into another's input, such as traces into metrics

It runs as a gateway Deployment, a per-node DaemonSet, or both. Module 25.

**Resource and span attributes.** These are the two kinds of labels on telemetry. Resource attributes describe who sent it: service, pod, node, image. Span attributes describe one operation, such as an HTTP status or a database statement. In TraceQL they're `resource.` and `span.`. Module 25.

**Semantic conventions.** Semantic conventions are OpenTelemetry's agreed attribute names, like `http.response.status_code`. They change between versions, so older instrumentation may still send `http.status_code`. Module 25.

**Grafana Tempo and TraceQL.** Tempo is a trace store that keeps traces cheaply in object storage, without indexing every attribute. TraceQL queries them by attributes, duration and structure. Examples are `{ span.http.status_code >= 500 }`, or `{ A } >> { B }` for spans of B below spans of A. Module 25.

**Span metrics.** Span metrics are request rate, errors and duration calculated from spans, here by the Collector's `span_metrics` connector. They give RED metrics to apps that export no metrics of their own. Module 25.

**Tail sampling.** Tail sampling is deciding which traces to keep after they're complete, so you keep every error trace and a fraction of the rest. It needs all spans of a trace in one place, which is a job for the Collector. Module 25.

**Context propagation and `traceparent`.** Context propagation is passing the trace ID and the parent span ID from service to service, so spans join into one trace. The IDs travel in the W3C `traceparent` header. Modules 6 and 25.

## Policy as code

**Admission webhook.** An admission webhook is a service that the API server calls before it stores an object, so outside tools add their own checks. Mutating webhooks change the object first. Then validating webhooks allow or refuse it. `failurePolicy: Fail` refuses requests while the webhook is down, and `Ignore` lets them through. Module 26.

**Kyverno.** Kyverno is a CNCF policy engine for Kubernetes, configured with YAML policies. A `ClusterPolicy` holds rules that validate (Audit reports, Enforce refuses), mutate, generate or verify images. Kyverno 1.18 adds CEL-based types such as `ValidatingPolicy`. Module 26.

**Autogen.** Autogen is a Kyverno feature that copies a rule written for Pods to Deployments, ReplicaSets, Jobs and CronJobs. So a bad Deployment gets refused when you apply it, not when its pods start. Module 26.

**PolicyReport.** A PolicyReport is a Kubernetes object that lists which resources pass, fail or skip each policy, per namespace. It is the evidence for an audit. Module 26.

**PolicyException.** A PolicyException is a written exception to named policy rules for named resources. In this lab, only the `kyverno` namespace accepts them, so teams don't get to exempt themselves. Module 26.

**CEL and ValidatingAdmissionPolicy.** CEL (Common Expression Language) is a small expression language that Kubernetes uses for validation rules. ValidatingAdmissionPolicy is Kubernetes' built-in, webhook-free policy type written in CEL. OPA Gatekeeper is the other common policy engine, with policies in Rego. Module 26.

**Background scan.** A background scan is Kyverno's regular re-check of stored objects against its policies. It writes reports and refuses nothing. Module 26.

## Retrieval-augmented generation

**Embedding and embedding model.** An embedding is a list of numbers that places a text so that similar meanings land close together. `nomic-embed-text` makes lists of 768 numbers. An embedding model produces them. Vectors from different embedding models aren't comparable. Module 27.

**Vector database and cosine similarity.** A vector database is a database that stores embeddings and quickly finds the nearest ones to a new vector. Examples are Qdrant, Weaviate, Milvus, or Postgres with pgvector. Cosine similarity measures closeness, 1 for the same direction and 0 for unrelated. Module 27.

**Chunking and top-k.** These are the two settings that decide what text reaches the model in RAG. Chunking splits documents into passages before embedding them, ideally one idea per chunk. Top-k is how many of the nearest chunks go to the model. More chunks mean fewer retrieval misses and more input tokens. Module 27.

**Temperature.** Temperature is a setting that controls how random a model's word choice is. At 0, the model always picks the most likely next word, so the same question gets the same answer. Module 27.

**Evaluation set.** An evaluation set is a list of questions with known answers and expected sources, like a test suite for a RAG system. You run it after every change to chunking, models or prompts. Module 27.

**HNSW.** HNSW is a graph index that lets a vector database find near neighbours approximately, without comparing the query with every stored vector. Module 27.

## Continuous profiling

**Profile and pprof.** A profile is a record of where a program spends CPU or allocates memory, as sampled call stacks. pprof is Go's built-in profiler and its file format, served at `/debug/pprof`. Module 28.

**Continuous profiling.** Continuous profiling is collecting low-rate profiles from every service all the time, so you look back at a spike instead of reproducing it. People call profiles the fourth signal, after metrics, logs and traces. Module 28.

**Flame graph, self and total.** A flame graph is a picture of call stacks as bars, each as wide as its share of samples, one level below its caller. Self counts samples inside the function, and total counts samples anywhere below it. Look for the widest total bar that's your own code. Module 28.

**Grafana Pyroscope.** Pyroscope is a continuous profiling database that stores pprof data and shows flame graphs in Grafana. Agents such as Alloy pull profiles from annotated pods, SDKs push them, and eBPF profilers sample whole nodes. Module 28.

**alloc_space and inuse_space.** These are two views of a Go memory profile. `alloc_space` counts every byte allocated in a time window, even memory freed right away. `inuse_space` counts what's still held. Module 28.

**Sampling profiler.** A sampling profiler is a profiler that records the call stack at fixed intervals instead of tracing every call. Here it samples 100 times a second, which costs little enough to run all the time. Module 28.

## How Kubernetes works inside

**Reconcile loop, watch and informer.** The reconcile loop is the cycle every controller runs to make what exists match what should exist. The controller watches the API server for the objects it cares about, compares, and acts to close the gap, over and over. A watch is the open connection that streams those changes. An informer is the client-side cache a controller builds from its watch. Module 29.

**Owner reference and garbage collector.** An owner reference is a field that links an object to the one that created it, such as Pod to ReplicaSet to Deployment. When the owner goes, the garbage collector deletes what it owned. Module 29.

**Scheduler: filter, score, bind, preemption.** The scheduler is the component that picks a node for each new pod. It works in phases:

1. Filter drops nodes that don't fit, because of resource requests, taints or selectors.
2. Score ranks the rest.
3. Bind writes `spec.nodeName`.

With no node left, preemption may evict lower-priority pods. The scheduler counts requests, never limits. Module 29.

**Authentication, authorization, admission.** These are the API server's gates, which every request passes in this order:

1. Authentication asks who you are, using certificates or tokens.
2. Authorization asks whether you may do this, using the Node authorizer and RBAC.
3. Admission asks whether the object should change or be refused, using admission plugins and webhooks.

Members of `system:masters` skip RBAC. Module 29.

**etcd and kine.** etcd is the key-value store that holds every Kubernetes object in most clusters, replicated with the Raft protocol. k3s uses kine instead by default. kine speaks the etcd API to the API server and stores the data in SQLite. Modules 21 and 29.

**CRI, sandbox and CNI.** These are the three pieces that start a pod on a node. The kubelet talks to the container runtime (containerd) through the CRI, the Container Runtime Interface. The runtime first creates a sandbox, a `pause` container that owns the pod's network namespace. Then it runs the CNI (Container Network Interface) plugins, here flannel and then istio-cni, to give the pod an IP and network rules. Module 29.

**EndpointSlice.** An EndpointSlice is the list of ready pod IPs behind a Service. kube-proxy, CoreDNS and istiod all read it. Module 29.

**DNAT and conntrack.** DNAT (destination network address translation) is a kernel rewrite of a packet's destination address, such as a Service IP to a pod IP. conntrack is the kernel's table of connections and their rewrites, like a notebook of every change it made. With it, replies get the original addresses back. Module 29.

**Watch cache.** The watch cache is the API server's in-memory copy of recent objects and changes. Watchers read from it, so a thousand controllers don't cause a thousand database reads. Module 29.

**resourceVersion and optimistic concurrency.** A `resourceVersion` is a version number that every stored object carries, so two writers don't silently overwrite each other. An update must name the version it read. If somebody wrote in between, the API server answers 409 Conflict, and the writer reads again and retries. This pattern is called optimistic concurrency. Module 29.

**Lease and leader election.** A Lease is a small object that one copy of a component renews every few seconds to say "I'm in charge". With several copies of the scheduler or controller manager, only the Lease holder acts. Choosing that holder is called leader election. Module 29.

**QoS class.** A QoS (quality of service) class is a group that Kubernetes puts each pod in, based on its requests and limits. The classes are Guaranteed (requests equal limits), Burstable (some requests or limits set) and BestEffort (none). When memory runs short, the kubelet evicts BestEffort first and Guaranteed last. Module 29.

**Field validation.** Field validation is a setting on a write that tells the API server what to do with fields it doesn't know. With `fieldValidation=Strict`, the API server refuses unknown or duplicate fields instead of dropping them silently. kubectl sends it by default. Module 29.

## Linux networking under Kubernetes

**Network namespace.** A network namespace is a separate copy of the network stack, with its own interfaces, addresses, routes and iptables rules. Every pod has one, owned by its `pause` container. Module 29.

**veth pair.** A veth pair is a virtual network cable with two ends. One end is `eth0` inside the pod. The other end sits on the node, plugged into the bridge. Module 29.

**Bridge (cni0).** The bridge is a virtual network switch on the node that connects all the pods on that node. Every pod's veth plugs into it. The bridge holds the pods' gateway address, `10.42.0.1`. Module 29.

**ARP.** ARP (Address Resolution Protocol) is how a machine finds the MAC address for an IP on the same Layer 2 network. The node's `ip neigh` table shows what it learned. Module 29.

**MTU and MSS.** These are the two size limits on packets. The MTU (maximum transmission unit) is the largest packet an interface sends, 1450 for pods here. The MSS (maximum segment size) is the largest TCP payload. It equals the MTU minus 40 bytes of IP and TCP headers, 1410 here. Module 29.

**VXLAN.** VXLAN is a tunnel that wraps a Layer 2 frame in a UDP packet, like a letter inside an envelope. flannel uses it (device `flannel.1`, port 8472) to carry pod traffic between nodes. Its 50-byte header is why pods get MTU 1450. Module 29.

**SNAT and masquerade.** SNAT (source network address translation) is a kernel rewrite of a packet's source address. Masquerade is SNAT to the address of the interface the packet leaves through. kube-proxy masquerades traffic that enters from outside the cluster, so replies come back through the same node. Module 29.

**externalTrafficPolicy.** externalTrafficPolicy is a Service setting that decides which nodes accept outside traffic. `Cluster`, the default, lets any node accept the traffic and SNATs it, which hides the client's address. `Local` keeps the client's address, but only sends traffic to pods on the node that received it. Module 29.

**Host port.** A host port is a container port bound to the node's own address. The CNI's portmap plugin implements it with a DNAT rule. k3s's svclb pods use one. Module 29.

**kube-router.** kube-router is the network policy controller that k3s embeds. It turns NetworkPolicy objects into iptables rules on every node. Module 29.

**Probe source 169.254.7.127.** 169.254.7.127 is the link-local source address that ambient mode gives to the kubelet's health checks. istio-cni rewrites the kubelet's probe traffic to come from it. ztunnel lets that traffic through without mTLS, so health checks work under STRICT mode. Module 29.

## CKS exam track

These terms come from the [CKS track](../certs/cks/README.md) in `certs/cks/`. Each entry names the domain file that uses it.

**kubeadm.** kubeadm is the official tool that turns plain Linux machines into a Kubernetes cluster. `kubeadm init` creates the control plane, `kubeadm join` adds a node, and `kubeadm upgrade` moves the cluster to a newer version. The CKS exam clusters come from kubeadm. [certs/README](../certs/README.md), CKS 02.

**Static pod.** A static pod is a pod that the kubelet starts from a YAML file in `/etc/kubernetes/manifests`, with no API server involved. kubeadm runs the API server, etcd, the scheduler and the controller manager this way. Edit the file, and the kubelet restarts the pod within seconds. [certs/README](../certs/README.md), CKS 01, 02, 04, 06.

**OrbStack machine.** An OrbStack machine is a lightweight Linux system that OrbStack runs on a Mac. It feels like a virtual machine, but every machine shares one Linux kernel. The CKS track's two nodes, `cks-cp` and `cks-w1`, are OrbStack machines. [certs/README](../certs/README.md).

**Default-deny policy.** A default-deny policy is a NetworkPolicy that selects every pod in a namespace (`podSelector: {}`) and allows nothing, so you open every path on purpose. Smaller policies then add single paths, because NetworkPolicies only ever add to each other. CKS 01.

**ipBlock.** An ipBlock is the part of a NetworkPolicy rule that matches IP ranges instead of pods, with an optional `except` list of ranges to leave out. CKS 01.

**Metadata service.** The metadata service is an HTTP endpoint at `169.254.169.254` on cloud virtual machines that hands out the machine's identity and often temporary cloud credentials. Pods reach it by default, so a NetworkPolicy blocks it. CKS 01.

**CIS Kubernetes Benchmark.** The CIS Kubernetes Benchmark is a checklist from the Center for Internet Security with about 130 settings for the control plane, etcd and the kubelet, each with a reason and a fix. CKS 01.

**kube-bench.** kube-bench is a tool from Aqua Security that checks a node's running Kubernetes components against the CIS benchmark and prints PASS, FAIL or WARN with a remediation per item. CKS 01.

**Ingress and Ingress controller.** An Ingress is a Kubernetes object with HTTP routing rules for traffic entering the cluster: hosts and paths to Services, plus TLS certificates. An Ingress controller, such as ingress-nginx, is the proxy that carries the rules out. Without a matching TLS Secret, ingress-nginx serves a fake certificate instead of failing. CKS 01.

**Checksum (SHA-512).** A checksum is a fingerprint of a file, computed so that changing one byte changes the whole value. Kubernetes publishes a SHA-512 checksum next to every binary on `dl.k8s.io`, and `sha512sum -c` compares a file against it. CKS 01.

