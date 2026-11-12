# Start here: Istio in one picture

Read this before module 0. It takes about 15 minutes and needs no cluster. By the end you'll know what each Istio resource is for and, just as important, which proxy acts on it. The modules then fill in the details one by one.

![Istio in one picture: the lab's request path, with every Istio resource grouped by the proxy that enforces it](../docs/diagrams/istio-resources.svg)

Want to move boxes around or add your own notes? Open [`docs/diagrams/istio-resources.excalidraw`](../docs/diagrams/istio-resources.excalidraw) at [excalidraw.com](https://excalidraw.com) (menu, Open). `docs/diagrams/make-istio-resources.py` generates both files.

## How to read the picture

Three kinds of things appear in it, and keeping them apart solves most of the confusion around Istio.

1. **Your pods** (grey): the frontend, two backend versions, Redis. They run your code and know nothing about the mesh.
2. **Proxies** (blue): the ingress gateway, the waypoint and ztunnel. They sit in the path of every request and do the actual work: encrypt, route, check, count.
3. **Resources you write** (the coloured notes): YAML that tells the proxies what to do. A resource does nothing by itself. It only counts once a proxy applies it.

istiod at the top connects the two: it reads your resources and sends each proxy the configuration it needs. That's what "control plane" means. It gives orders but never touches a request.

## Follow one request

Walk through the picture with a single call, `GET http://localhost:8080/api/orders`.

1. **The browser reaches the ingress gateway.** The **Gateway** resource opened that port. If you added TLS (module 11), the gateway also ends the HTTPS session here, with the certificate the Gateway points to.
2. **The gateway checks the caller and picks a route.** A **RequestAuthentication** checks the user's token, if one arrives (module 13). An **AuthorizationPolicy** on the gateway decides whether the caller needs a token at all. An **HTTPRoute** says that path `/` belongs to the frontend.
3. **ztunnel carries the request to the frontend.** Every hop between mesh pods travels through ztunnel's mTLS tunnel. **PeerAuthentication** set to `STRICT` makes sure nothing arrives as plain text.
4. **The frontend calls `backend:8000`.** The backend has a waypoint, so ztunnel delivers the call to the waypoint, not straight to a backend pod.
5. **The waypoint reads the HTTP request and applies three kinds of rules.** An **AuthorizationPolicy** decides *whether* the frontend may call this path. An **HTTPRoute** (or a **VirtualService**) decides *where* it goes: 90% to v1, 10% to v2, or by header. A **DestinationRule** decides *how* to talk to the chosen pods: how many connections at once, which pods to skip because they keep failing, whether to use TLS.
6. **ztunnel carries it again, from the waypoint to a backend pod.** A second **AuthorizationPolicy**, this time at L4, lets only the waypoint open that connection, so nobody sneaks around the L7 rules.
7. **On the way out of the mesh**, a **ServiceEntry** gives an outside host like `httpbin.org` a name in the mesh, so the same kinds of rules apply to it (module 12).

All along the way, the proxies report metrics, traces and logs. The **Telemetry** resource sets where traces go and which logs to write (module 6).

## Where, how, and whether

Three resources show up at the waypoint, and people mix them up all the time. One question each:

| Question | Resource | Example |
|---|---|---|
| **Whether** may this caller do this? | AuthorizationPolicy | only `sa/frontend` may call `GET /api/*` |
| **Where** does the request go? | HTTPRoute or VirtualService | 90% to v1, 10% to v2 |
| **How** do we talk to the destination? | DestinationRule | at most 1 pending request; eject a pod after 5 errors |

Inside the proxy, the *whether* check runs before the request goes anywhere. A refused request never reaches a pod, so *where* and *how* only matter for requests that pass.

## Two APIs for the same job

Istio grew its own routing API in 2017. Later, the Kubernetes project wrote a standard one, the Gateway API, and Istio supports both. You'll meet both in real clusters, so learn to read both.

| Job | Gateway API (what this course uses first) | Istio API (older, still everywhere) |
|---|---|---|
| Open a port for outside traffic | `Gateway` (`gateway.networking.k8s.io`), Istio creates the proxy for you | `Gateway` (`networking.istio.io`) on gateway pods you deploy yourself |
| Route requests | `HTTPRoute` | `VirtualService` |
| Split traffic between versions | weights on `backendRefs`, one Service per version | weights on `route` entries, versions as `subsets` in a DestinationRule |
| Inject faults | not available | `VirtualService` with `fault` |
| Connection pool, outlier detection, TLS to a backend | not available | `DestinationRule` (works together with HTTPRoute too) |

Yes, two different resources both carry the name `Gateway`. Check the `apiVersion` line to see which one you're reading. Module 16 builds the same setup with both APIs side by side.

## Ambient mode and sidecar mode in one sentence each

**Ambient** (what the picture shows, and what the lab's `shop` namespace runs): one shared ztunnel per node for encryption and L4, plus a waypoint only for the services that need HTTP features. **Sidecar** (module 7): an Envoy proxy inside every pod that does both. The resources stay the same in both modes; only the proxy that applies them changes.

## Next

- Keep the [glossary](glossary.md) open in a tab. It explains every resource and term in this course, with small examples.
- Then start with [module 0: setup](00-setup.md).
