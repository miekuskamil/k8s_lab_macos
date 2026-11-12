# Module 11: TLS at the edge

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

So far the shop speaks plain HTTP on `localhost:8080`. Inside the mesh that's fine, because ztunnel wraps every hop in mTLS. But the first hop, from your browser to the ingress gateway, travels unencrypted. In this module you give the gateway an HTTPS listener, let cert-manager issue and renew its certificate, and send every HTTP visitor over to HTTPS.

Time: about 45 minutes.

## Concept: two kinds of TLS in one request

One request now passes through two separate TLS sessions, and each one uses a different certificate authority.

```mermaid
flowchart LR
  b["browser or curl"]
  g["ingress gateway<br/>Envoy in shop-ingress"]
  f["frontend pod"]
  b == "HTTPS on :8443<br/>certificate from the lab CA<br/>(cert-manager)" ==> g
  g == "HBONE mTLS<br/>certificates from istiod" ==> f
```

| | Edge TLS (this module) | Mesh mTLS (module 2) |
|---|---|---|
| Who connects | Any client, usually a browser | Only workloads inside the mesh |
| Who proves its identity | Only the server | Both sides |
| Who signs the certificate | A CA the client trusts: Let's Encrypt, a company CA, or here the lab CA | istiod, a CA only the mesh trusts |
| Name in the certificate | A DNS name, like `shop.local` | A SPIFFE ID, like `spiffe://cluster.local/ns/shop/sa/frontend` |
| Who manages it | You, with cert-manager | istiod, fully automatic |

The gateway ends (terminates) the browser's TLS session, reads the HTTP request, picks a route and opens a fresh mTLS connection into the mesh. The frontend never sees the edge certificate.

## Concept: how cert-manager works

cert-manager turns certificates into ordinary Kubernetes resources. You describe the certificate you want, and a controller makes it happen and keeps it fresh.

```mermaid
flowchart LR
  ci["ClusterIssuer lab-ca<br/>who signs"]
  c["Certificate shop-tls<br/>what you want: names, lifetime"]
  cm["cert-manager controller"]
  s["Secret shop-tls<br/>tls.crt and tls.key"]
  gw["Gateway listener<br/>certificateRefs: shop-tls"]
  c --> cm
  ci --> cm
  cm -- "creates, then renews<br/>before expiry" --> s
  gw -- "reads" --> s
```

Three resources do the work:

- An **Issuer** or **ClusterIssuer** says who signs. In real life that's usually Let's Encrypt through the ACME protocol, or a company CA. Let's Encrypt needs a public DNS name, which a laptop lab lacks, so the lab runs its own CA: `lab-ca`, backed by a self-signed root that cert-manager created during provisioning.
- A **Certificate** says what you want: DNS names, lifetime, when to renew, key type.
- A **Secret** of type `kubernetes.io/tls` holds the result. cert-manager writes it, and the gateway reads it.

You never touch the Secret yourself. Delete it, and cert-manager simply issues a new one.

## The bigger picture: why certificates break production

Ask any operations team about their worst outages, and an expired certificate shows up on the list sooner or later. Big names have gone down this way: whole mobile networks, cloud consoles, payment systems. The pattern always looks the same. Someone created the certificate by hand two years ago, set a reminder, then changed jobs. Nobody owned the renewal, and one morning every client started refusing the connection.

The industry answer is to make certificates short-lived and renew them automatically, so renewal happens so often that nobody forgets it. Let's Encrypt issues certificates for 90 days. The browser makers and certificate authorities went further: in 2025 they voted to cut the maximum lifetime of public certificates step by step, down to 47 days by 2029. At that pace, renewing by hand stops being an option. A tool like cert-manager stops being nice to have and becomes the only sane way.

That's also why this module's certificate lives for 90 days and renews 30 days early. You set the policy once, and from then on nobody thinks about it.

## Why this way

**Why end TLS at the gateway, and not pass it through to the frontend?** The gateway has to read the HTTP request to route it: the path, the host, the headers. With the traffic still encrypted, it sees nothing but bytes. Istio supports passthrough (`mode: Passthrough`) for apps that must hold their own keys, but then the gateway only routes by the server name and loses every HTTP feature.

**Why does the Secret live in `shop-ingress`?** A Gateway reads certificates from its own namespace by default. To use a Secret from another namespace, the owner of that namespace has to allow it with a `ReferenceGrant`. That rule stops a team from pointing its gateway at another team's private key.

**Why does the gateway pick up a new certificate without a restart?** Istio hands certificates to Envoy over SDS, the Secret Discovery Service, part of the same xDS protocol from module 1. istiod watches the Secret, and when cert-manager rewrites it, istiod pushes the new certificate to Envoy. Open connections keep their old session; new ones get the new certificate.

**Why a 301 redirect and not just turning HTTP off?** People type `localhost:8080` or follow old links. A redirect sends them to the right place instead of showing an error. Production sites add HSTS on top, a header that tells the browser to use HTTPS on its own next time.

## Do it

You need port 8443 on your machine. Clusters that `provision.sh` built after this module arrived publish it already. For an older cluster, add it once (k3d rebuilds its load balancer, and the cluster keeps running):

```bash
docker port k3d-k8s-lab-serverlb | grep 8443 || k3d cluster edit k8s-lab --port-add 8443:8443@loadbalancer
```

### 1. Meet the lab CA

```bash
kubectl get clusterissuer
kubectl -n cert-manager get certificate lab-root-ca
```

**What you should see.** Two issuers, `selfsigned` and `lab-ca`, both `READY True`, and the root CA certificate `READY True`. Save the root's public certificate. curl needs it in a moment to trust the gateway:

```bash
kubectl -n cert-manager get secret lab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/lab-ca.crt
```

### 2. Ask for a certificate

```bash
kubectl apply -f course/manifests/11-certificate.yaml
kubectl -n shop-ingress get certificate shop-tls -w      # wait for READY True, then Ctrl-C
kubectl -n shop-ingress get secret shop-tls -o jsonpath='{.data.tls\.crt}' | base64 -d \
  | openssl x509 -noout -issuer -ext subjectAltName -dates
```

**What you should see.** The issuer `CN=k8s-lab root CA`, the names `shop.local` and `localhost`, and dates 90 days apart. It took cert-manager a second or two.

### 3. Open an HTTPS listener

```bash
kubectl apply -f course/manifests/11-gateway-https.yaml
kubectl -n shop-ingress get gateway shop-gateway
curl --cacert /tmp/lab-ca.crt https://localhost:8443/api/version
curl https://localhost:8443/api/version
```

**What you should see.** The first curl returns the version JSON. The second fails with `SSL certificate problem: unable to get local issuer certificate`: curl doesn't know the lab CA, so it refuses the connection. Your browser behaves the same way and shows a warning page. That's TLS doing its job.

Now look at the handshake itself:

```bash
openssl s_client -connect 127.0.0.1:8443 -servername shop.local -CAfile /tmp/lab-ca.crt </dev/null 2>/dev/null \
  | grep -E "subject=|issuer=|Verify return code"
```

`-servername` sets SNI, the name the client asks for during the handshake. One gateway serves many sites from one IP address, and SNI tells it which certificate to present.

### 4. Send HTTP visitors to HTTPS

```bash
kubectl apply -f course/manifests/11-redirect.yaml
curl -sI http://localhost:8080/api/orders | grep -iE "^HTTP|^location"
curl -sL --cacert /tmp/lab-ca.crt -o /dev/null -w "%{http_code} %{url_effective}\n" http://localhost:8080/api/orders
```

**What you should see.** `HTTP/1.1 301 Moved Permanently` with `location: https://localhost:8443/api/orders`, then `200` once curl follows it. The redirect route answers on the `http` listener by itself. The request never reaches the frontend.

### 5. Renew the certificate with no downtime

Note the certificate's serial number, throw the Secret away and watch cert-manager replace it:

```bash
serial() { openssl s_client -connect 127.0.0.1:8443 -servername localhost </dev/null 2>/dev/null | openssl x509 -noout -serial; }
serial
kubectl -n shop-ingress get pods          # note RESTARTS
kubectl -n shop-ingress delete secret shop-tls
sleep 5; serial
kubectl -n shop-ingress get pods          # RESTARTS has not changed
```

**What you should see.** A new serial number within a few seconds, and the gateway pod untouched. A real renewal works the same way: cert-manager writes a new Secret 30 days before expiry, and SDS carries it into Envoy.

## Investigate

1. Which certificate does the frontend see when a request arrives through HTTPS?
2. Delete both the Certificate and the Secret (`kubectl -n shop-ingress delete certificate,secret shop-tls`). What does the Gateway report for the `https` listener, and what happens to `https://localhost:8443`? Re-apply step 2 afterwards.
3. In Grafana, open Explore with Prometheus and run `sum by (response_code, destination_service) (istio_requests_total{source_workload="shop-gateway-istio"})` after you call `http://localhost:8080` a few times. Wait 30 seconds for Prometheus to scrape. Do the 301 responses show up, and which service do they name?
4. Why does the certificate in step 2 list `localhost` as well as `shop.local`?

<details>
<summary>Answers</summary>

1. None of the edge certificates. The gateway ends the browser's TLS session. Towards the frontend it opens an HBONE mTLS connection with its own mesh identity, `spiffe://cluster.local/ns/shop-ingress/sa/shop-gateway-istio`. Send one HTTPS request, then check the ztunnel log: `kubectl -n istio-system logs ds/ztunnel --since=1m | grep shop-gateway | grep frontend | tail -1`. The `src.identity` field holds that SPIFFE ID.
2. The listener's `ResolvedRefs` condition turns `False` with the reason `InvalidCertificateRef`, because the Secret no longer exists. The gateway stops offering a certificate, and `curl` fails during the handshake. The `http` listener on 8080 keeps answering (with the redirect, if you applied step 4): one broken listener doesn't take down the others.
3. They do, but with `destination_service="unknown"`. The gateway answered those requests itself, so no backend took part, and the metric has no service to name. The 200s from HTTPS requests carry `destination_service="frontend.shop.svc.cluster.local"`. That "unknown" label is worth remembering: in a real incident, a jump in `unknown` responses from a gateway often means a route matched nothing, or a redirect or direct response answered instead of your service.
4. A certificate only covers the names listed in it. curl and your browser connect to `localhost:8443`, so without `localhost` in the list, the name check fails even though the lab CA signed the certificate.

</details>

## Clean up

```bash
./course/reset.sh
```

This removes the redirect, the HTTPS listener, the Certificate and its Secret. The lab CA and cert-manager stay, because they belong to the lab.
