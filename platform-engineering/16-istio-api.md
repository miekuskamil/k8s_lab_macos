# Module 16: the Istio API, Gateway and VirtualService

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 4 and 5.

**You need:** the lab running (`./scripts/start.sh` starts or repairs it), `helm`, and internet access for Istio's gateway chart.

Most of this course routes traffic with the Gateway API, the Kubernetes standard made of Gateway and HTTPRoute resources, but Istio had its own routing API for years before that standard existed. Huge numbers of clusters, blog posts and Helm charts still use the older Istio API, and so does the Istio Certified Associate exam. This module builds two things from module 4 again the Istio way, an ingress gateway and a canary, so that by the end you read both styles and translate between them.

Time: about 40 minutes.

## Concept: the same jobs, different shapes

![Gateway API and Istio API resources side by side](../docs/diagrams/chapters/16-two-apis.svg)

Both APIs create a gateway, attach routes and split traffic between versions. On the left, the Gateway API's Gateway creates the proxy and the HTTPRoute sends traffic to one Service per version. On the right, a Helm chart creates the proxy, the Istio Gateway configures it, and the VirtualService sends traffic to subsets that a DestinationRule defines.

Three differences stand out:

| | Gateway API | Istio API |
|---|---|---|
| Who creates the gateway proxy | Istio, from the Gateway resource | You, with the `istio/gateway` Helm chart. The Gateway only configures it |
| How routes attach | The route names its parent in `parentRefs` | The VirtualService names its Gateway in `gateways`. Without that field, it applies inside the mesh |
| How versions are named | One Service per version | Subsets: named groups of one Service's pods, picked by labels in a DestinationRule |

## Concept: how a VirtualService finds its traffic

The two APIs pick the traffic they control in different ways. An HTTPRoute attaches to a named object, a Gateway or a Service in its `parentRefs` field, while a VirtualService attaches to a host name. `hosts: [backend.shop.svc.cluster.local]` means "every request addressed to this name", from any client in the mesh, much like a rule for every letter sent to one address, no matter who posts it.

The `gateways` field then says where the rules run:

- If you list a gateway, the rules run on that gateway's pods.
- If you leave the field out, the rules run inside the mesh, which in ambient mode means the waypoint of the backend Service.

istiod reads all three resources, Gateway, VirtualService and DestinationRule, and turns them into Envoy config, the same way it turned HTTPRoutes into config in module 4. The diagram follows one request from step 3:

![The waypoint splits traffic for host backend 90/10 between subsets v1 and v2](../docs/diagrams/chapters/16-virtualservice-canary.svg)

For a canary, Istio needs a way to say "the v1 pods" and "the v2 pods" while both versions sit behind one Service, and a subset does that job by filtering the Service's endpoints, the list of pod addresses behind it:

1. The `backend` Service selects pods with the label `app: backend`, so its list holds the pods of both versions.
2. The DestinationRule narrows that list with a second label, `version`.
3. Envoy treats each subset as its own group of pods.

The result looks exactly like module 4, where `backend-v1` and `backend-v2` were two separate Services, and only the way you name the groups differs.

One consequence matters for step 3: a VirtualService that names a subset needs a DestinationRule that defines it, because otherwise the subset matches no pods and requests fail, like a letter to a mailing list that nobody created.

## The bigger picture: why two APIs exist

Istio launched in 2017, before Kubernetes had any good answer for routing, because the old Ingress resource understood only hosts and paths. So every project invented its own routing resource, such as Istio's VirtualService, Contour's HTTPProxy and Traefik's IngressRoute, and a team that switched tools had to rewrite all its routes.

The Kubernetes networking group answered with the Gateway API, which reached version 1.0 in 2023 and splits the work by role: platform teams own the Gateway, with its ports and certificates, and application teams own their routes. Istio, Cilium, Envoy Gateway, NGINX and others all implement it, so your routes move with you when you change tools.

Istio now recommends the Gateway API for new setups, and ambient mode builds on it. The Istio API isn't going away soon, though, because it still covers features the standard lacks, like fault injection and the retries from module 15, and because a huge amount of existing config uses it, so in practice you'll read both every week.

## Why this way

**Why does Istio's Gateway need a separate Deployment?** It came from the sidecar era, when gateways were plain Envoy pods that platform teams ran and scaled themselves. The Gateway resource tells those pods which ports and hosts to accept, and its `selector` picks the pods by label, the way a Service picks pods.

**Why `--skip-schema-validation` in the install command?** The Istio 1.24 `gateway` chart carries a values schema, a file that lists the settings the chart accepts, and Helm 4 reads it more strictly than Helm 3 did, so it rejects the chart's own defaults. The flag tells Helm to skip that check, and with Helm 3 you leave it out.

**Why do subsets live in a DestinationRule?** The VirtualService decides *where* a request goes, while the DestinationRule describes *what* the destinations are and *how* to talk to them. Subsets describe the destinations, so they sit next to connection pools and TLS settings, and the split also lets one DestinationRule serve many VirtualServices.

**Why does the header test call the backend from the course client, not through the gateway?** The waypoint matches headers on the request it receives, but the frontend forwards only tracing headers when it calls the backend, so a header you send to the gateway stops at the frontend. Real apps that use header routing therefore have to pass the header along, just like `traceparent` in module 6.

## Do it

### 1. Deploy a classic ingress gateway

```console
$ helm repo update istio
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "istio" chart repository
Update Complete. ⎈Happy Helming!⎈

$ helm install istio-ingress istio/gateway -n istio-ingress --create-namespace \
  --version 1.24.2 --skip-schema-validation --set service.type=ClusterIP --wait
NAME: istio-ingress
LAST DEPLOYED: Sat Nov 14 23:17:16 2026
NAMESPACE: istio-ingress
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
"istio-ingress" successfully installed!

To learn more about the release, try:
  $ helm status istio-ingress -n istio-ingress
  $ helm get all istio-ingress -n istio-ingress

Next steps:
  * Deploy an HTTP Gateway: https://istio.io/latest/docs/tasks/traffic-management/ingress/ingress-control/
  * Deploy an HTTPS Gateway: https://istio.io/latest/docs/tasks/traffic-management/ingress/secure-ingress/

$ kubectl -n istio-ingress get pods -l istio=ingress -o jsonpath='{.items[0].spec.containers[0].image}{"\n"}'
docker.io/istio/proxyv2:1.24.2-distroless
```

**What you should see.** `docker.io/istio/proxyv2:1.24.2-distroless`, because the chart deployed a plain pod and Istio's injector filled in the Envoy image. The `ClusterIP` setting keeps the gateway off your machine's ports, because the lab's own gateway already uses 8080.

### 2. Route outside traffic with a Gateway and a VirtualService

```console
$ kubectl apply -f platform-engineering/manifests/16-istio-gateway.yaml -f platform-engineering/manifests/16-ingress-virtualservice.yaml
gateway.networking.istio.io/shop-classic created
virtualservice.networking.istio.io/shop-classic-ingress created

$ kubectl -n istio-ingress port-forward svc/istio-ingress 9080:80 &
Forwarding from 127.0.0.1:9080 -> 80
Forwarding from [::1]:9080 -> 80

$ curl -s http://localhost:9080/api/version; echo
{"version":"v1","pod":"backend-v1-54c86bf9b-xqdkd"}
```

The port-forward runs in the background and prints `Handling connection for 9080` for each request, mixed into the output of later commands, and the transcripts in this module leave those lines out.

**What you should see.** The backend's version JSON, this time through the classic gateway on port 9080. Open both manifests to see how they split the work:

- The Gateway says "accept HTTP on port 80 for any host".
- The VirtualService says "for traffic arriving at that Gateway, send everything to the frontend".

### 3. Build the canary with subsets

```console
$ kubectl -n shop delete httproute backend-route
httproute.gateway.networking.k8s.io "backend-route" deleted

$ kubectl apply -f platform-engineering/manifests/16-subsets.yaml -f platform-engineering/manifests/16-canary-virtualservice.yaml
destinationrule.networking.istio.io/backend-subsets created
virtualservice.networking.istio.io/backend-canary created

$ for i in $(seq 1 200); do curl -s -o /dev/null -w "%header{x-app-version}\n" http://localhost:9080/api/orders; done | sort | uniq -c
 174 v1
  26 v2
```

**What you should see.** About 180 `v1` and 20 `v2`, 174 and 26 in the test run for this module. You deleted the HTTPRoute first because an HTTPRoute and a VirtualService for the same host would compete, and Istio doesn't define which one wins.

### 4. Send testers to v2 with a header

```console
$ kubectl apply -f platform-engineering/manifests/03-course-client.yaml -f platform-engineering/manifests/03-allow-course-client.yaml
serviceaccount/course-client unchanged
deployment.apps/course-client unchanged
authorizationpolicy.security.istio.io/backend-allow-course-client created

$ kubectl -n shop rollout status deploy/course-client
deployment "course-client" successfully rolled out

$ kubectl -n shop exec deploy/course-client -- sh -c \
  'for i in $(seq 1 20); do curl -s -o /dev/null -w "%header{x-app-version}\n" -H "x-version: v2" http://backend:8000/api/version; done' | sort | uniq -c
  20 v2
```

**What you should see.** `20 v2`, because the first rule in the VirtualService matched the header. Run the command again without `-H "x-version: v2"`, and the 90/10 split returns. This step uses `GET /api/version` because module 3's policy lets the course client call only that path.

### 5. Translate one into the other

Put the two styles next to each other. Module 4's split:

```yaml
kind: HTTPRoute
spec:
  parentRefs: [{group: "", kind: Service, name: backend}]
  rules:
    - backendRefs:
        - {name: backend-v1, port: 8000, weight: 90}
        - {name: backend-v2, port: 8000, weight: 10}
```

This module's split:

```yaml
kind: VirtualService
spec:
  hosts: [backend.shop.svc.cluster.local]
  http:
    - route:
        - {destination: {host: backend.shop.svc.cluster.local, subset: v1}, weight: 90}
        - {destination: {host: backend.shop.svc.cluster.local, subset: v2}, weight: 10}
```

Both do the same job in two shapes: the HTTPRoute uses `parentRefs` where the VirtualService uses `hosts`, and one Service per version where the VirtualService uses subsets.

## Investigate

1. Remove the `gateways:` field from `16-ingress-virtualservice.yaml` in your head. Where would that VirtualService apply then?
2. Delete the DestinationRule `backend-subsets` while the canary VirtualService stays. What happens to the shop, and which command tells you why?
3. Your company runs 300 VirtualServices. Should you convert them all to HTTPRoutes next quarter?

<details>
<summary>Answers</summary>

1. It would apply inside the mesh, as if `gateways: [mesh]` were set, so it would try to route traffic sent to the host `*` between mesh workloads, which makes little sense. Leave `gateways` out only for VirtualServices meant for traffic between services, like the canary in step 3.
2. Every request to the backend gets a `503`, because the VirtualService routes to subsets that no longer exist. `istioctl analyze -n shop` explains the problem straight away with `Error [IST0101] ... Referenced host+subset in destinationrule not found: "backend.shop.svc.cluster.local+v1"`, so run `istioctl analyze` whenever routing breaks after a change, because it catches most of these mistakes before you go hunting in logs.
3. Probably not in one go, because both APIs work and VirtualServices still cover features HTTPRoute lacks, like fault injection. A common plan has three parts:
   - Write new routes as HTTPRoutes.
   - Convert old VirtualServices when you touch them anyway.
   - Keep VirtualServices where they need Istio-only features.

</details>

## Clean up

```console
$ kill %1 2>/dev/null       # the port-forward from step 2
$ ./platform-engineering/reset.sh
Removing course rules from the shop namespace
Applying the baseline Istio config from manifests/istio
Turning off the backend experiment settings
Asking ArgoCD to sync istio-config from Git
Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules.
```

This deletes the `istio-ingress` namespace with the classic gateway, the VirtualService and the DestinationRule, and restores the HTTPRoute.
