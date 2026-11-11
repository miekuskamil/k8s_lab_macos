# Architecture

This document describes the system in `k8s_lab_macos`: what runs, how a request travels, where mTLS applies, and how to move the diagrams into draw.io or Excalidraw.

## Goals and constraints

- Run a realistic service mesh, GitOps pipeline and observability stack on one laptop.
- Stay inside the OrbStack VM budget of about 8 GiB RAM and 4 CPUs. The k3d node container shares that VM. Quotas in `manifests/base/02-quotas.yaml` enforce the budget.
- Keep every change reproducible from Git. The only imperative steps are in `scripts/provision.sh`.

## Components

| Layer | Component | Namespace | Role |
|---|---|---|---|
| Entry | Istio Gateway `shop-gateway` (Envoy) | shop-ingress | Accepts HTTP on port 8080, reaches `localhost:8080` through the k3d load balancer |
| Application | `frontend` (Node.js, Express) | shop | Serves the traffic control UI, proxies `/api/*`, generates bursts |
| Application | `backend-v1` (2 pods) and `backend-v2` (1 pod), FastAPI | shop | Orders API, one image, `APP_VERSION` selects the label |
| Data | `redis` | shop | Order storage, password from a Secret |
| Mesh L4 | `ztunnel` DaemonSet, `istio-cni` DaemonSet | istio-system | mTLS, identity, L4 policy, traffic capture on every node |
| Mesh L7 | `waypoint` Gateway (Envoy) | shop | HTTP routing, fault injection, circuit breaking, L7 policy for the backend Services |
| Control plane | `istiod` | istio-system | Issues certificates, pushes config to ztunnel and Envoy |
| GitOps | ArgoCD | argocd | Syncs this repository to the cluster |
| Observability | Prometheus, Grafana, Jaeger | observability | Metrics, dashboards, traces |

## Repository layout

```text
k8s_lab_macos/
├── README.md
├── architecture.md
├── learning.md
├── apps/
│   ├── backend/
│   │   ├── Dockerfile
│   │   ├── .dockerignore
│   │   ├── main.py
│   │   └── requirements.txt
│   └── frontend/
│       ├── Dockerfile
│       ├── .dockerignore
│       ├── package.json
│       ├── package-lock.json
│       ├── server.js
│       └── public/
│           └── index.html
├── helm/
│   ├── argocd-values.yaml
│   ├── istio-base-values.yaml
│   ├── istio-cni-values.yaml
│   ├── istiod-values.yaml
│   ├── kube-prometheus-stack-values.yaml
│   └── ztunnel-values.yaml
├── manifests/
│   ├── argocd/
│   │   ├── project.yaml
│   │   ├── root-app.yaml
│   │   └── apps/
│   │       ├── istio-config.yaml
│   │       ├── kube-prometheus-stack.yaml
│   │       ├── observability-config.yaml
│   │       ├── shop-apps.yaml
│   │       └── shop-base.yaml
│   ├── base/
│   │   ├── 00-namespaces.yaml
│   │   ├── 01-rbac.yaml
│   │   └── 02-quotas.yaml
│   ├── apps/
│   │   ├── backend.yaml
│   │   ├── frontend.yaml
│   │   └── redis.yaml
│   ├── istio/
│   │   ├── backend-route.yaml
│   │   ├── gateway.yaml
│   │   ├── security.yaml
│   │   ├── telemetry.yaml
│   │   └── waypoint.yaml
│   ├── observability/
│   │   ├── grafana-dashboard.yaml
│   │   ├── jaeger.yaml
│   │   └── monitors.yaml
│   └── scenarios/
│       ├── a-canary-httproute.yaml
│       ├── b-fault-injection.yaml
│       └── c-circuit-breaker.yaml
└── scripts/
    ├── port-forward.sh
    ├── provision.sh
    ├── teardown.sh
    └── traffic-test.sh
```

`manifests/scenarios` is not synced by ArgoCD. You apply those files by hand, so the experiments never fight the GitOps controller.

## Traffic flow and mTLS boundaries

The cluster is a k3d cluster named `k8s-lab`. OrbStack provides the Docker engine, k3d runs a k3s node and a load balancer as containers in it, and the pods run inside the k3s node container. OrbStack's built-in Kubernetes is not used, because it has no CNI config directory and `istio-cni` cannot install there.

```mermaid
flowchart LR
  browser["Browser on macOS<br/>localhost:8080"]

  subgraph orb["OrbStack, Docker engine"]
    subgraph k3d["k3d cluster k8s-lab"]
      lb["k3d load balancer<br/>host :8080 to node :8080"]

      subgraph node["k3s node container"]
        subgraph ingress["ns shop-ingress, outside mesh"]
          gw["shop-gateway<br/>Envoy :8080"]
        end

        subgraph shop["ns shop, ambient"]
          fe["frontend<br/>:3000"]
          wp["waypoint Envoy<br/>HBONE :15008"]
          b1["backend-v1 x2<br/>:8000"]
          b2["backend-v2 x1<br/>:8000"]
          redis[("redis<br/>:6379")]
        end

        subgraph sys["ns istio-system"]
          zt["ztunnel<br/>HBONE :15008<br/>metrics :15020"]
          istiod["istiod<br/>xDS :15012"]
        end

        subgraph obs["ns observability, ambient"]
          prom["Prometheus<br/>:9090"]
          graf["Grafana<br/>:3000"]
          jaeger["Jaeger<br/>UI :16686<br/>OTLP :4317, :4318"]
        end

        subgraph gitops["ns argocd"]
          argo["ArgoCD<br/>:8081 by port-forward"]
        end
      end
    end
  end

  github["GitHub<br/>miekuskamil/k8s_lab_macos<br/>branch main"]

  browser -->|"1 HTTP"| lb
  lb -->|"2 TCP :8080"| gw
  gw ==>|"3 HBONE"| zt
  zt -->|"4 deliver"| fe
  fe -->|"5 HTTP :8000, captured"| zt
  zt ==>|"6 HBONE"| wp
  wp ==>|"7 HBONE, 90 v1 / 10 v2"| zt
  zt -->|"8 deliver"| b1
  zt -->|"8 deliver"| b2
  b1 ==>|"9 TCP :6379, L4 mTLS"| redis
  b2 ==>|"9 TCP :6379, L4 mTLS"| redis

  istiod -.->|"certs, config"| zt
  istiod -.->|"xDS"| wp
  istiod -.->|"xDS"| gw
  wp -.->|"OTLP gRPC :4317"| jaeger
  b1 -.->|"OTLP HTTP :4318"| jaeger
  prom -.->|"scrape"| wp
  prom -.->|"scrape"| b1
  graf -.->|"PromQL"| prom
  graf -.->|"trace lookup"| jaeger
  argo -->|"git poll, sync"| github

  linkStyle 2,5,6,9,10 stroke:#1f6feb,stroke-width:4px
  linkStyle 11,12,13,14,15,16,17,18,19 stroke:#8b949e,stroke-width:1.5px,stroke-dasharray:5 4
```

The same diagram as a standalone SVG with trust zones, at `docs/traffic-flow.svg`:

![Traffic flow with trust zones: browser, k3d load balancer, gateway, ztunnel, waypoint, backend, Redis](docs/traffic-flow.svg)

Legend:

- Thick blue arrow: HBONE mTLS tunnel on port 15008, or L4 mTLS for Redis.
- Thin black arrow: plaintext.
- Thin dashed gray arrow: control plane and telemetry (xDS, OTLP, scrapes, queries).
- Numbers: order of hops for one request, from the browser to Redis.

The numbered hops, in order:

1. The browser sends plaintext HTTP to `localhost:8080`. OrbStack publishes the port from the k3d load balancer container.
2. The k3d load balancer forwards the TCP connection to port 8080 on the k3s node, where the `shop-gateway-istio` Service sends it to the gateway pod.
3. The ingress gateway sits outside the mesh. Because the frontend is an ambient workload, the gateway wraps the request in an HBONE tunnel and authenticates with the gateway identity.
4. ztunnel on the node terminates the tunnel and hands the request to the frontend pod. The check for `PeerAuthentication STRICT` happens here.
5. The frontend calls `http://backend.shop.svc.cluster.local:8000`. The CNI redirect sends that connection to ztunnel.
6. The `backend` Service carries `istio.io/use-waypoint: waypoint`, so ztunnel opens an HBONE tunnel to the waypoint and not to a backend pod.
7. The waypoint terminates mTLS, evaluates `AuthorizationPolicy backend-allow-frontend`, applies the HTTPRoute or VirtualService, injects faults, enforces the connection pool, picks a backend, and opens a new HBONE tunnel.
8. ztunnel on the destination node delivers the request to a backend pod over plaintext on the node.
9. The backend connects to Redis. ztunnel upgrades that TCP stream to mTLS and enforces `AuthorizationPolicy redis-allow-backend` using the backend service account identity.

Redis and the frontend have no waypoint, so their traffic stays on the L4 path.

### mTLS boundaries

| Hop | Encrypted | Peer identity checked |
|---|---|---|
| Browser to k3d load balancer to gateway | No | None |
| Gateway to frontend | Yes, HBONE | `shop-ingress` gateway service account |
| Frontend to waypoint | Yes, HBONE | `ns/shop/sa/frontend` |
| Waypoint to backend | Yes, HBONE | `ns/shop/sa/waypoint` |
| Backend to Redis | Yes, HBONE | `ns/shop/sa/backend` |
| Pod to local ztunnel | No, stays inside the node | Node-local only |
| Prometheus to pods | Yes, both namespaces are ambient | `ns/observability/sa/kube-prometheus-stack-prometheus` |

Between a pod and the ztunnel on its own node, traffic is plaintext. That hop never leaves the k3s node container, which is the trust model Istio ambient uses.

## GitOps flow

```mermaid
flowchart TD
  dev["You"] -->|"1 git push to main"| repo["GitHub repository"]

  subgraph k3d["k3d cluster k8s-lab"]
    subgraph argocd["ns argocd"]
      root["Application root<br/>path manifests/argocd/apps"]
    end
    base["shop-base<br/>namespaces, RBAC, quotas"]
    apps["shop-apps<br/>frontend, backend, redis"]
    istio["istio-config<br/>gateway, waypoint, routes<br/>no selfHeal"]
    kps["kube-prometheus-stack<br/>Helm chart plus helm/ values"]
    obs["observability-config<br/>Jaeger, monitors, dashboard"]
    live["live cluster state"]
  end

  root -->|"2 poll repo"| repo
  root -->|"3 create child apps"| base
  root --> apps
  root --> istio
  root --> kps
  root --> obs
  base -->|"4 apply"| live
  apps -->|"4 apply"| live
  istio -->|"4 apply"| live
  kps -->|"4 apply"| live
  obs -->|"4 apply"| live
  live -.->|"5 drift report"| root

  linkStyle 3,4,5,6 stroke:#8b949e,stroke-width:1.5px
  linkStyle 7,8,9,10,11 stroke:#1f6feb,stroke-width:3px
  linkStyle 12 stroke:#8b949e,stroke-width:1.5px,stroke-dasharray:5 4
```

Legend: thick blue arrows apply manifests to the cluster, thin arrows are Git reads and Application creation, the dashed arrow is the drift report. Numbers give the order.

![GitOps flow: push, poll, create child Applications, apply, drift report](docs/gitops-flow.svg)

`provision.sh` installs Istio and ArgoCD itself because both must exist before ArgoCD can sync anything that depends on them. After that, Git is the source of truth for everything in `manifests/`.

## Resource budget

| Namespace | CPU requests | Memory requests | Memory limits |
|---|---|---|---|
| shop | 2 cores max | 2 GiB max | 3 GiB max |
| shop-ingress | 500m max | 512 MiB max | 1 GiB max |
| observability | 1500m max | 2.5 GiB max | 6 GiB max |
| istio-system | no quota | about 400 MiB in practice | set in `helm/*.yaml` |
| argocd | no quota | about 600 MiB in practice | set in `helm/argocd-values.yaml` |

A LimitRange in each quota-controlled namespace gives containers default requests and limits, because a quota rejects pods that declare none.

## Secrets

- `shop/redis-auth` and `observability/grafana-admin` are created by `provision.sh` with `openssl rand`. They are not in Git.
- ArgoCD reads the initial admin password from `argocd/argocd-initial-admin-secret`.
- For a shared environment, replace this with External Secrets Operator or Sealed Secrets. See `learning.md`.

## Import and export with draw.io or Excalidraw

The repo keeps each diagram in three forms. The Mermaid blocks in this file are the source of truth for structure. `docs/traffic-flow.svg` and `docs/gitops-flow.svg` are standalone SVGs with no external fonts, scripts or images. `docs/traffic-flow.excalidraw` is an editable Excalidraw scene of the traffic flow.

### draw.io (diagrams.net)

Import the Mermaid diagram:

1. Copy the contents of a `mermaid` block above, without the code fence.
2. Open https://app.diagrams.net or the desktop app and create a blank diagram.
3. Choose Arrange, Insert, Advanced, Mermaid.
4. Paste the text and select Insert. draw.io converts the diagram into editable shapes.
5. Re-apply the edge styles from the legend (thick blue for mTLS, dashed gray for telemetry), because the import may not keep `linkStyle`. Then move shapes and add the draw.io network icons from the shape library on the left.

Import an SVG: File, Import from, Device, then pick `docs/traffic-flow.svg`. draw.io places it as one image. To edit shapes, use the Mermaid import or the Excalidraw route below.

Export:

1. File, Export as, then PNG, SVG or PDF. Tick "Include a copy of my diagram" on PNG and SVG so you can reopen the file later.
2. File, Save as, then `.drawio` to keep the editable source. Commit it under `docs/` if you want it versioned.
3. Round trip back to Mermaid is not supported. Keep the Mermaid text in this file as the source of truth for structure.

### Excalidraw

Open the editable scene: Menu, Open, then pick `docs/traffic-flow.excalidraw`. Boxes, zones and arrows are separate elements you can move and restyle.

Import a Mermaid diagram:

1. Open https://excalidraw.com.
2. Select the library icon, or press `/`, and choose Mermaid to Excalidraw. In the menu this entry is under More tools.
3. Paste the Mermaid text. The preview updates as you type.
4. Select Insert. The diagram appears as hand-drawn shapes you can edit. Re-apply the edge colors and dashes from the legend, because the converter may not keep `linkStyle`.

Export:

1. Menu, Export image, then PNG or SVG. Enable "Embed scene" to keep the file editable.
2. Menu, Save to, then `.excalidraw` for the editable source. Save over `docs/traffic-flow.excalidraw` to update the repo copy.
3. To share a read-only link, use Menu, Shareable link.

### Command line rendering

```bash
npm install --global @mermaid-js/mermaid-cli
mmdc -i architecture.md -o docs/architecture.svg
```

`mmdc` renders every Mermaid block in a Markdown file and writes one SVG per block with a numeric suffix, such as `architecture-1.svg` and `architecture-2.svg`.

## Known limits

- The k3d cluster has one k3s node, so cross-node HBONE traffic and ztunnel failover are not exercised.
- The waypoint does not accept `EnvoyFilter`, so global rate limiting needs an external rate limit service. The lab limits rate inside the backend.
- Istio VirtualService support on waypoints and the exact metric labels vary between Istio releases. After changing `ISTIO_VERSION`, re-check Scenario B and the dashboard queries.
