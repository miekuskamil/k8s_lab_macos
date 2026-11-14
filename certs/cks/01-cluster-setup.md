# CKS 01: Cluster setup (15%)

> New to a term here, like CIS benchmark or ipBlock? The [glossary](../../course/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) running. The course's [module 3](../../course/03-authorization.md#concept-authorizationpolicy-compared-with-networkpolicy) compares NetworkPolicy with Istio's rules, and [module 11](../../course/11-edge-tls.md) explains certificates and trust. Read those first if NetworkPolicy or TLS feel shaky.

A fresh kubeadm cluster lets every pod reach every other pod, exposes profiling data about its own internals, and trusts whatever binaries you copy onto the nodes. This domain closes those doors before any workload arrives. It has five tasks and takes about 40 minutes, including the theory.

## Theory: what "set up securely" means here

The exam's cluster setup domain covers five checks. Each one answers a different question:

| Question | Tool | Task |
|---|---|---|
| Which pods may talk to which? | NetworkPolicy | 1 |
| May a pod reach the cloud's metadata service? | NetworkPolicy with `ipBlock` | 2 |
| Do the control plane flags follow the industry baseline? | kube-bench | 3 |
| Does the Ingress serve real TLS? | Ingress with a `tls` section | 4 |
| Are the binaries on the node the ones Kubernetes released? | `sha512sum` | 5 |

### NetworkPolicy: allow lists for pods

Kubernetes connects every pod to every other pod by default. That's convenient, and it means one compromised pod reaches the database, the API server and the node. A **NetworkPolicy** is an allow list for pod traffic. The CNI plugin, Calico here, turns it into packet filter rules on each node.

Three rules decide what a NetworkPolicy does:

1. A pod that no policy selects accepts everything. Kubernetes isolates a pod only once a policy selects it.
2. Once a policy selects a pod for a direction (`Ingress` or `Egress`), that direction allows only what some policy lists.
3. Policies only add. Two policies that select the same pod allow the union of their lists. No policy subtracts.

So the usual pattern has two layers. A **default-deny** policy selects every pod (`podSelector: {}`) and lists nothing. Then small policies open single paths. Think of a building where every door starts locked, and each policy hands out one key.

Egress needs one extra path that people forget: DNS. A pod with default-deny egress fails to resolve `api` long before it fails to connect to it. So every egress allow list includes UDP and TCP port 53 to CoreDNS in `kube-system`.

### Node metadata

Cloud virtual machines answer HTTP on `169.254.169.254`, the **metadata service**. It hands out the machine's identity, and often temporary cloud credentials. Every pod on the node reaches that address by default. An attacker inside a pod asks it for the node's cloud credentials and leaves the cluster with them. An egress NetworkPolicy with an `ipBlock` and an `except` list closes that path for pods. OrbStack has no metadata service, so in this lab you build the policy and prove that other traffic still flows.

### The CIS benchmark and kube-bench

The **CIS Kubernetes Benchmark** is a checklist from the Center for Internet Security. It lists about 130 settings for the API server, etcd, the scheduler, the controller manager and the kubelet, each with a reason and a fix. **kube-bench** is a tool from Aqua Security that reads the running processes and files on a node and checks them against that list. It prints `[PASS]`, `[FAIL]` or `[WARN]` per item, then a remediation for each failure.

kube-bench reads the flags of the running processes, so a fix shows up only after the kubelet restarts the static pod. That's why the solution waits for the API server before it runs kube-bench again.

### Ingress with TLS

An **Ingress** is a set of HTTP routing rules for traffic entering the cluster: host names and paths to Services. An Ingress controller, ingress-nginx here, carries them out. TLS needs two objects:

1. A Secret of type `kubernetes.io/tls` that holds the certificate and its private key.
2. A `tls` section in the Ingress that names the host and that Secret.

When the Secret is missing or the names don't match, ingress-nginx doesn't fail. It serves its own "Kubernetes Ingress Controller Fake Certificate" and carries on. So a check that only looks at the HTTP status code misses the mistake. Look at the certificate's subject.

### Verifying binaries

A kubelet binary from a random mirror might carry a backdoor. Kubernetes publishes a SHA-512 checksum next to every binary on `dl.k8s.io`. A checksum is a fingerprint of a file: change one byte, and the fingerprint changes completely. Compare the two before you run anything.

## Task 1: Default-deny and one allowed path

**Time budget:** 7 minutes. **Host:** `cks-cp`.

Prepare it from your Mac:

```bash
./certs/cks/task.sh setup 1.1
```

> Namespace `team-app` runs three pods: `frontend` (label `app=frontend`), `api` (`app=api`, port 80) and `db` (`app=db`, port 80), each with a Service of the same name.
>
> 1. Create a NetworkPolicy `default-deny` that blocks all ingress and all egress for every pod in `team-app`.
> 2. Allow `frontend` to reach `api` on TCP port 80, and nothing else. `frontend` must still resolve Service names.
> 3. `db` must not reach `api`.

Useful commands:

```bash
k -n team-app get pods --show-labels
k -n kube-system get pods -l k8s-app=kube-dns --show-labels
k explain networkpolicy.spec.egress.to
k -n team-app exec frontend -- wget -qO- -T 3 http://api
```

<details>
<summary>Solution</summary>

Three policies: the deny, an ingress rule on `api`, and an egress rule on `frontend` that also opens DNS.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: team-app
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
  namespace: team-app
spec:
  podSelector:
    matchLabels: {app: api}
  policyTypes: [Ingress]
  ingress:
  - from:
    - podSelector:
        matchLabels: {app: frontend}
    ports:
    - {protocol: TCP, port: 80}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: team-app
spec:
  podSelector:
    matchLabels: {app: frontend}
  policyTypes: [Egress]
  egress:
  - to:
    - podSelector:
        matchLabels: {app: api}
    ports:
    - {protocol: TCP, port: 80}
  - to:
    - namespaceSelector:
        matchLabels: {kubernetes.io/metadata.name: kube-system}
      podSelector:
        matchLabels: {k8s-app: kube-dns}
    ports:
    - {protocol: UDP, port: 53}
    - {protocol: TCP, port: 53}
```

Save it as `np.yaml` with `vim np.yaml` and run `k apply -f np.yaml`.

Two details decide whether it works:

- The `namespaceSelector` and the `podSelector` of the DNS rule sit in **one** list item, so both must match: CoreDNS pods in `kube-system`. As two separate items (a dash before each), the rule would allow every pod in `kube-system` or any pod labelled `k8s-app=kube-dns` in `team-app`.
- The port is the pod's port, not the Service's. Calico checks packets after kube-proxy has translated the Service address to a pod address. Here both are 80.

</details>

Check it:

```bash
./certs/cks/task.sh check 1.1
```

In the test run, the check failed three of four items before the solution and passed all four after it:

```
  PASS  NetworkPolicy default-deny selects every pod, Ingress and Egress
  PASS  frontend reaches api on port 80, by name
  PASS  frontend does not reach db
  PASS  db does not reach api
```

## Task 2: Block the node metadata endpoint

**Time budget:** 4 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 1.2
```

> Pods in namespace `batch` must not reach the node metadata service at `169.254.169.254`. All other egress stays allowed. Create a NetworkPolicy named `deny-metadata`.

<details>
<summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-metadata
  namespace: batch
spec:
  podSelector: {}
  policyTypes: [Egress]
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except: [169.254.169.254/32]
```

The policy selects every pod for egress, so egress becomes an allow list. The list holds the whole IPv4 range minus one address. DNS keeps working, because CoreDNS's pod IP sits inside `0.0.0.0/0`.

</details>

```bash
./certs/cks/task.sh check 1.2
```

In the test run, the worker pod reached the API server's port both before and after the policy. The check reads the policy's structure for the block itself, because OrbStack has no metadata service to refuse:

```
  PASS  NetworkPolicy deny-metadata exists and selects every pod
  PASS  it allows 0.0.0.0/0 except 169.254.169.254/32
  PASS  the worker still resolves names and reaches the API server
```

## Task 3: Fix CIS findings with kube-bench

**Time budget:** 8 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 1.3     # seeds nothing: a fresh kubeadm cluster fails these checks already
```

> Run kube-bench against the control plane node `cks-cp` and fix these findings: 1.2.15, 1.3.2 and 1.4.1 (profiling on the API server, controller manager and scheduler), and 4.1.9 (the kubelet's config file permissions). The control plane must keep running.

Start by reading the report:

```bash
kube-bench run --targets master | grep -E '^\[FAIL\]|checks (PASS|FAIL|WARN)'
kube-bench run --targets master --check 1.2.15     # one check, with its remediation
kube-bench run --targets node --check 4.1.9
```

On a fresh cluster, the test run printed 39 passes, 10 failures and 11 warnings for the master target. The failures were profiling on all three components, four audit log flags, etcd's data directory owner, `--kubelet-certificate-authority` and `--service-account-extend-token-expiration`. Audit logging comes in [domain 06](06-monitoring-logging-runtime-security.md#task-1-turn-on-audit-logging).

<details>
<summary>Solution</summary>

Each profiling fix is one flag in a static pod manifest. Back the files up outside the manifests folder, because the kubelet starts every file inside it, backups included:

```bash
cp /etc/kubernetes/manifests/kube-{apiserver,controller-manager,scheduler}.yaml /root/
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Add one line under the command, in each of the three files:

```yaml
  - command:
    - kube-apiserver
    - --profiling=false
```

Then fix the kubelet's config file and wait for the control plane:

```bash
chmod 600 /var/lib/kubelet/config.yaml
watch crictl ps                                        # the three containers restart
k -n kube-system get pods -l tier=control-plane
kube-bench run --targets master,node --check 1.2.15,1.3.2,1.4.1,4.1.9
```

In the test run, the three pods came back in under a minute, and kube-bench then printed `[PASS]` for all four checks.

</details>

```bash
./certs/cks/task.sh check 1.3
```

```
  PASS  kube-bench 1.2.15 passes
  PASS  kube-bench 1.3.2 passes
  PASS  kube-bench 1.4.1 passes
  PASS  kube-bench 4.1.9 passes
  PASS  every control plane pod runs
```

## Task 4: An Ingress with TLS

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 1.4
```

> Namespace `web` runs Deployment `shop` behind Service `shop` on port 80. A certificate and key for `shop.cks.local` wait in `/root/cks/shop.crt` and `/root/cks/shop.key`.
>
> 1. Store them in a TLS Secret named `shop-tls` in `web`.
> 2. Create an Ingress `shop` with class `nginx` that serves `https://shop.cks.local/` from Service `shop` with that certificate.
> 3. Plain HTTP must redirect to HTTPS.

The ingress controller listens on NodePort 30443 for HTTPS and 30080 for HTTP, on both nodes.

<details>
<summary>Solution</summary>

Two imperative commands do it:

```bash
k -n web create secret tls shop-tls --cert=/root/cks/shop.crt --key=/root/cks/shop.key
k -n web create ingress shop --class=nginx --rule="shop.cks.local/*=shop:80,tls=shop-tls"
```

The `tls=shop-tls` part of `--rule` writes the Ingress's `tls` section. ingress-nginx redirects HTTP to HTTPS by itself for every host that has TLS, with status 308, so step 3 needs nothing extra.

Test it from the node. `--resolve` makes curl send the right host name to an IP address without touching DNS:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' --resolve shop.cks.local:30443:127.0.0.1 https://shop.cks.local:30443/
echo | openssl s_client -connect 127.0.0.1:30443 -servername shop.cks.local 2>/dev/null | openssl x509 -noout -subject
curl -s -o /dev/null -w '%{http_code}\n' --resolve shop.cks.local:30080:127.0.0.1 http://shop.cks.local:30080/
```

In the test run, these printed `200`, `subject=CN = shop.cks.local` and `308`. The controller reloaded nginx about 3 seconds after the Ingress appeared.

</details>

```bash
./certs/cks/task.sh check 1.4
```

```
  PASS  Secret shop-tls has type kubernetes.io/tls
  PASS  HTTPS on shop.cks.local:30443 answers 200
  PASS  the certificate served is CN=shop.cks.local, not the controller's fake one
  PASS  plain HTTP redirects to HTTPS (308)
```

## Task 5: Verify a platform binary

**Time budget:** 3 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 1.5
```

> `/opt/cks/bin` holds `kubectl` and `kube-proxy`, both claiming to be Kubernetes v1.37.1 for linux/arm64. Delete every binary that doesn't match the official release.

<details>
<summary>Solution</summary>

The checksum file on `dl.k8s.io` holds only the hash, so add the file name for `sha512sum -c`:

```bash
cd /opt/cks/bin
for b in kubectl kube-proxy; do
  echo "$(curl -fsSL https://dl.k8s.io/release/v1.37.1/bin/linux/arm64/$b.sha512) $b" | sha512sum -c || rm -f "$b"
done
```

In the test run:

```
kubectl: OK
kube-proxy: FAILED
sha512sum: WARNING: 1 computed checksum did NOT match
```

The setup had appended three bytes to `kube-proxy`. In the exam, the task often gives the expected hash in the text instead. Then compare by eye: `sha512sum kube-proxy` and look at the first and last few characters.

</details>

```bash
./certs/cks/task.sh check 1.5
```

```
  PASS  the tampered kube-proxy is gone
  PASS  kubectl stays, and matches the official v1.37.1 sha512
```

## Clean up

Tasks 1, 2, 4 and 5 leave only namespaces and files. Task 3 changed three static pods. To start the next domain from a fresh cluster:

```bash
./certs/cks/cluster/reset.sh
```
