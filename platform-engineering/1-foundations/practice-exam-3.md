# Timed practice exam 3: applications, several objects per task

> New to a term here? The [glossary](../glossary.md#applications-on-kubernetes) explains every term these modules use.

**Before the practice exam:** [practice exam 2](practice-exam-2.md), and the [practice cluster](../practice-cluster.md#the-application-extras) with the application extras.

This practice exam is the hardest of the three, harder than most real exam tasks. Each task asks for several objects that have to fit together, such as a StatefulSet with a claim per pod, three NetworkPolicies for three tiers, or a ClusterRole bound in two namespaces, and a few tasks need a flag that the earlier domains only mention once. It has 16 tasks worth 100 points, with the same 2-hour clock, and 80 points inside the time is a good sign for the exam.

## Rules

1. Start from a clean cluster with `./platform-engineering/practice/app-extras/reset.sh`, then run `./platform-engineering/practice-exam.sh setup 3`. In the test run, the reset took 46 seconds and the setup 57 seconds, most of it for the two Helm releases of task 3.
2. The clock starts when `setup.sh` ends, and `./platform-engineering/practice-exam.sh score 3` prints the minutes since then.
3. Work only on `practice-control-plane`, and use only kubernetes.io/docs, the Kubernetes blog and helm.sh/docs.
4. Don't open the solutions while the timer runs.
5. Score from your Mac with `./platform-engineering/practice-exam.sh score 3`.

Task files sit in `/opt/apps/m3/N` on `practice-control-plane`.

## Tasks

| # | Task | Points | Module |
|---|---|---|---|
| 1 | Image with a build argument | 8 | 33 |
| 2 | Blue-green behind an Ingress | 7 | 02, 05 |
| 3 | Helm: values, failure, rollback | 7 | 34 |
| 4 | StatefulSet with its own volumes | 7 | 01, 05 |
| 5 | Init, sidecar, probes | 7 | 01, 03 |
| 6 | A ClusterRole for custom resources | 6 | 36 |
| 7 | Custom resources by the numbers | 4 | 36 |
| 8 | Three tiers, three policies | 7 | 37 |
| 9 | Quota and LimitRange together | 6 | 36 |
| 10 | One volume, two sources | 6 | 36 |
| 11 | Debug a copy of a crashing pod | 6 | 35 |
| 12 | A history to read | 6 | 34 |
| 13 | Two overlays from one base | 7 | 34 |
| 14 | A Job that cleans up after itself | 5 | 33 |
| 15 | An Ingress with a default backend | 5 | 37 |
| 16 | Port 80 without root | 6 | 36 |

### Task 1: Image with a build argument (8 points)

> `/opt/apps/m3/1/Dockerfile` takes a build argument `VERSION`.
> 1. Build it with `VERSION=2.4.0` as `registry.practice:5000/pricing:2.4.0`, tag the same image also as `registry.practice:5000/pricing:stable`, and push both tags.
> 2. Save the image as an OCI archive to `/opt/apps/m3/1/pricing.tar`.
> 3. In namespace `k3-build`, run Deployment `pricing` with 2 replicas of `pricing:2.4.0` in a container named `pricing`, with an init container `wait-dns` (image `busybox:1.36`) that waits until `nslookup kubernetes.default.svc.cluster.local` succeeds.

<details>
<summary>Solution</summary>

```bash
cd /opt/apps/m3/1
podman build --build-arg VERSION=2.4.0 -t registry.practice:5000/pricing:2.4.0 .
podman tag registry.practice:5000/pricing:2.4.0 registry.practice:5000/pricing:stable
podman push registry.practice:5000/pricing:2.4.0 && podman push registry.practice:5000/pricing:stable
podman save --format oci-archive -o pricing.tar registry.practice:5000/pricing:2.4.0
```

```yaml
    spec:
      initContainers:
      - name: wait-dns
        image: busybox:1.36
        command: [sh, -c, 'until nslookup kubernetes.default.svc.cluster.local; do sleep 2; done']
      containers:
      - name: pricing
        image: registry.practice:5000/pricing:2.4.0
```

The first version of this task waited for `http://registry.practice:5000/v2/` instead, and its pods hung in `Init:0/1` in the test run: the name `registry.practice` lives in the nodes' `/etc/hosts`, which containerd reads, while pods ask the cluster's DNS, which has never heard of it. `podman tag` adds a second name to the same image, so both tags push the same manifest and share its digest. `podman save` writes Docker's archive format by default; `--format oci-archive` writes the OCI layout with an `index.json`.

</details>

### Task 2: Blue-green behind an Ingress (7 points)

> In namespace `k3-bg`, Ingress `app` sends `app.k3.local` to Service `app-blue`, in front of Deployment `app-blue` (labels `app=bgapp`, `color=blue`, answers `blue`). Create Deployment `app-green` (2 pods, `color=green`, answers `green`) with its own Service `app-green`, switch `app.k3.local` to it, and add the host `preview.k3.local` to the same Ingress, pointing at `app-blue`.

<details>
<summary>Solution</summary>

Copy the blue Deployment, change name, label and answer, then expose it:

```bash
k -n k3-bg expose deploy app-green --port=80 --target-port=8080
k -n k3-bg edit ingress app
```

```yaml
  rules:
  - host: app.k3.local
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: app-green, port: {number: 80}}}}
  - host: preview.k3.local
    http:
      paths:
      - {path: /, pathType: Prefix, backend: {service: {name: app-blue, port: {number: 80}}}}
```

Here the switch happens in the Ingress, not in a Service selector, so each color keeps its own Service and both stay reachable.

</details>

### Task 3: Helm: values, failure, rollback (7 points)

> In namespace `k3-helm`:
> 1. Save the user values of revision 2 of release `shop` to `/opt/apps/m3/3/values-rev2.yaml`.
> 2. The latest upgrade of `shop` failed. Roll the release back to revision 2.
> 3. Release `admin` never worked. Remove it.

<details>
<summary>Solution</summary>

```bash
helm -n k3-helm history shop
mkdir -p /opt/apps/m3/3
helm -n k3-helm get values shop --revision 2 > /opt/apps/m3/3/values-rev2.yaml
helm -n k3-helm rollback shop 2 --wait
helm -n k3-helm list --failed
helm -n k3-helm uninstall admin
```

Revision 3 asked for 64Gi of memory per pod, so its new pods stayed `Pending` and `--wait` marked it `failed`. The rollback creates revision 4 with revision 2's manifests and values.

</details>

### Task 4: StatefulSet with its own volumes (7 points)

> The cluster has two PersistentVolumes of class `ckad-local`. In namespace `k3-sts`, create a headless Service `queue` on port 8080 and a StatefulSet `queue` with 2 replicas (image `busybox:1.36`) in which each pod gets its own 1Gi claim named `data`, mounted at `/data`. On its first start, each pod writes its host name to `/data/id`, and it keeps the file across restarts.

<details>
<summary>Solution</summary>

`volumeClaimTemplates` creates one claim per pod, named `TEMPLATE-STATEFULSET-ORDINAL`, so `data-queue-0` and `data-queue-1`:

```yaml
spec:
  serviceName: queue
  replicas: 2
  selector: {matchLabels: {app: queue}}
  template:
    metadata: {labels: {app: queue}}
    spec:
      containers:
      - name: queue
        image: busybox:1.36
        command: [sh, -c, 'test -f /data/id || hostname > /data/id; sleep 1d']
        volumeMounts: [{name: data, mountPath: /data}]
  volumeClaimTemplates:
  - metadata: {name: data}
    spec:
      accessModes: [ReadWriteOnce]
      storageClassName: ckad-local
      resources: {requests: {storage: 1Gi}}
```

A restarted `queue-1` gets the same claim back, and with it the same file, which the check proves by deleting the pod.

</details>

### Task 5: Init, sidecar, probes (7 points)

> In namespace `k3-pod`, create pod `gateway` with three containers, all `busybox:1.36`, sharing an emptyDir at `/conf`:
> 1. Init container `config-gen` writes `mode=gateway` to `/conf/app.conf`.
> 2. Native sidecar `proxy` serves `/conf` with `httpd -f -p 9090 -h /conf`, with a readiness probe GET `/app.conf` on 9090.
> 3. Container `app` runs `sleep 1d`, with a liveness probe that runs `cat /conf/app.conf`.

<details>
<summary>Solution</summary>

```yaml
spec:
  initContainers:
  - name: config-gen
    image: busybox:1.36
    command: [sh, -c, 'echo mode=gateway > /conf/app.conf']
    volumeMounts: [{name: conf, mountPath: /conf}]
  - name: proxy
    image: busybox:1.36
    restartPolicy: Always
    command: [httpd, -f, -p, '9090', -h, /conf]
    readinessProbe:
      httpGet: {path: /app.conf, port: 9090}
    volumeMounts: [{name: conf, mountPath: /conf}]
  containers:
  - name: app
    image: busybox:1.36
    command: [sleep, 1d]
    livenessProbe:
      exec: {command: [cat, /conf/app.conf]}
    volumeMounts: [{name: conf, mountPath: /conf}]
  volumes:
  - name: conf
    emptyDir: {}
```

A native sidecar may have a readiness probe, and the pod is Ready only when the sidecar is too.

</details>

### Task 6: A ClusterRole for custom resources (6 points)

> The cluster has a CRD `certificates.k3.ckad.io`. Create a ClusterRole `ckad-cert-manager` that may get, list, create and update these Certificates, and grant it to ServiceAccount `cert-bot` from namespace `k3-tools`, but only in namespaces `k3-team-a` and `k3-team-b`.

<details>
<summary>Solution</summary>

```bash
k create clusterrole ckad-cert-manager --verb=get,list,create,update --resource=certificates.k3.ckad.io
k -n k3-team-a create rolebinding cert-bot --clusterrole=ckad-cert-manager --serviceaccount=k3-tools:cert-bot
k -n k3-team-b create rolebinding cert-bot --clusterrole=ckad-cert-manager --serviceaccount=k3-tools:cert-bot
k auth can-i create certificates.k3.ckad.io -n k3-team-b --as=system:serviceaccount:k3-tools:cert-bot
```

A RoleBinding that grants a ClusterRole keeps the rights inside the RoleBinding's namespace, so one rule set serves two namespaces without a ClusterRoleBinding. For a custom resource, `--resource` takes `PLURAL.GROUP`.

</details>

### Task 7: Custom resources by the numbers (4 points)

> Create a Certificate `wiki` in namespace `k3-certs` for the domain `wiki.k3.local`, valid for 60 days. Then write the domain of the Certificate with the fewest days, across all namespaces, to `/opt/apps/m3/7/expiring.txt`.

<details>
<summary>Solution</summary>

```yaml
apiVersion: k3.ckad.io/v1
kind: Certificate
metadata: {name: wiki, namespace: k3-certs}
spec: {domain: wiki.k3.local, days: 60}
```

```bash
k get certificates -A --sort-by=.spec.days
k get certificates -A --sort-by=.spec.days -o jsonpath='{.items[0].spec.domain}' > /opt/apps/m3/7/expiring.txt
```

</details>

### Task 8: Three tiers, three policies (7 points)

> Namespace `k3-tiers` runs pods `web` (`tier=web`), `api` (`tier=api`) and `db` (`tier=db`), each behind a Service of the same name, and an `intruder`. Allow exactly this: `web` accepts connections on 8080 from anywhere, `web` reaches `api` on 8080, `api` reaches `db` on 5432, and every pod resolves DNS. Block everything else.

<details>
<summary>Solution</summary>

A namespace-wide default deny for both directions, with DNS allowed, then one policy per tier:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: default-deny, namespace: k3-tiers}
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
  egress:
  - ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: web, namespace: k3-tiers}
spec:
  podSelector: {matchLabels: {tier: web}}
  policyTypes: [Ingress, Egress]
  ingress:
  - ports: [{protocol: TCP, port: 8080}]
  egress:
  - to: [{podSelector: {matchLabels: {tier: api}}}]
    ports: [{protocol: TCP, port: 8080}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api, namespace: k3-tiers}
spec:
  podSelector: {matchLabels: {tier: api}}
  policyTypes: [Ingress, Egress]
  ingress:
  - from: [{podSelector: {matchLabels: {tier: web}}}]
    ports: [{protocol: TCP, port: 8080}]
  egress:
  - to: [{podSelector: {matchLabels: {tier: db}}}]
    ports: [{protocol: TCP, port: 5432}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: db, namespace: k3-tiers}
spec:
  podSelector: {matchLabels: {tier: db}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {tier: api}}}]
    ports: [{protocol: TCP, port: 5432}]
```

An ingress rule with `ports` and no `from` allows that port from any source. A pod in this namespace still needs its own egress rule to use it, which `intruder` doesn't get, so in the test run `intruder` reached nothing at all.

</details>

### Task 9: Quota and LimitRange together (6 points)

> Deployment `indexer` in namespace `k3-limits` should run 4 pods and runs none. Give its container requests and limits for CPU and memory that satisfy both the namespace's ResourceQuota and its LimitRange, without changing either.

<details>
<summary>Solution</summary>

`k -n k3-limits describe quota,limitrange` shows the numbers: at most 600m and 600Mi of requests and 1 CPU and 1Gi of limits for the namespace, and between 50m and 300m CPU and 32Mi and 256Mi memory per container. Four pods with 100m and 64Mi requests and 200m and 128Mi limits fit both.

The trap sits in the LimitRange: it names only `min` and `max`, and a LimitRange without `default` uses its `max` as the default. So each pod without numbers got 300m and 256Mi, two pods filled the 600m quota, and the other two got refused. A plain `set resources` then hangs, as it did in the test run, because the new pods find no room while the old ones hold the whole quota, and the old ones only go once new ones are ready. Scale to 0 first:

```bash
k -n k3-limits scale deploy indexer --replicas=0
k -n k3-limits set resources deploy indexer --requests=cpu=100m,memory=64Mi --limits=cpu=200m,memory=128Mi
k -n k3-limits scale deploy indexer --replicas=4
```

</details>

### Task 10: One volume, two sources (6 points)

> In namespace `k3-proj`, create pod `edge` (image `busybox:1.36`, command `sleep 1d`) with one volume at `/etc/tls` that holds both keys of ConfigMap `tls-settings` and the key `server.key` of Secret `tls-key`, the latter with mode 0400.

<details>
<summary>Solution</summary>

A [projected volume](https://kubernetes.io/docs/concepts/storage/projected-volumes/) merges several sources into one folder:

```yaml
  volumes:
  - name: tls
    projected:
      sources:
      - configMap: {name: tls-settings}
      - secret:
          name: tls-key
          items: [{key: server.key, path: server.key, mode: 0400}]
```

</details>

### Task 11: Debug a copy of a crashing pod (6 points)

> Pod `loader` in namespace `k3-debug` crashes right after it starts. Without changing it, create a copy `loader-debug` whose container `loader` runs `sleep 1d` instead, find which path the app misses, and write that path to `/opt/apps/m3/11/missing.txt`.

<details>
<summary>Solution</summary>

```bash
k -n k3-debug get pod loader -o jsonpath='{.spec.containers[0].args}'
k -n k3-debug debug loader --copy-to=loader-debug --container=loader --image=busybox:1.36 -- sleep 1d
k -n k3-debug exec loader-debug -- ls /etc/loader
mkdir -p /opt/apps/m3/11 && echo /etc/loader/conf > /opt/apps/m3/11/missing.txt
```

`--copy-to` creates a new pod from the old one's spec, with the changes you ask for, so you inspect the same image and volumes while the original stays as it is.

</details>

### Task 12: A history to read (6 points)

> Deployment `portal` in namespace `k3-hist` has three revisions with change causes. Write the revision number of `feature x` to `/opt/apps/m3/12/revision.txt`, then roll the Deployment back to the revision with the cause `nginx 1.28`, and keep at most 2 old ReplicaSets from now on.

<details>
<summary>Solution</summary>

```bash
k -n k3-hist rollout history deploy portal
mkdir -p /opt/apps/m3/12 && echo 3 > /opt/apps/m3/12/revision.txt
k -n k3-hist rollout undo deploy portal --to-revision=2
k -n k3-hist patch deploy portal -p '{"spec":{"revisionHistoryLimit":2}}'
```

Write the number down before the undo, because the undo renumbers revision 2 as 4.

</details>

### Task 13: Two overlays from one base (7 points)

> `/opt/apps/m3/13/base` holds Deployment `search` and a generated ConfigMap `search-config` with `LOG=info`. Without changing the base, create overlays `dev` and `prod` in `/opt/apps/m3/13/overlays/`: dev deploys to `k3-dev` with `LOG=debug`; prod deploys to `k3-prod` with `LOG=warn`, 3 replicas and a memory limit of 128Mi. Apply both.

<details>
<summary>Solution</summary>

```yaml
# overlays/dev/kustomization.yaml
resources:
- ../../base
namespace: k3-dev
configMapGenerator:
- name: search-config
  behavior: merge
  literals:
  - LOG=debug
```

```yaml
# overlays/prod/kustomization.yaml
resources:
- ../../base
namespace: k3-prod
replicas:
- name: search
  count: 3
configMapGenerator:
- name: search-config
  behavior: merge
  literals:
  - LOG=warn
patches:
- patch: |-
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: search
    spec:
      template:
        spec:
          containers:
          - name: search
            resources:
              limits:
                memory: 128Mi
```

`k apply -k overlays/dev` and `k apply -k overlays/prod`.

</details>

### Task 14: A Job that cleans up after itself (5 points)

> In namespace `k3-jobs`, create a Job `thumbnails` that runs 5 pods at once, each printing `thumbnail N done` where N is its own index from 0 to 4, and that deletes itself 120 seconds after it finishes.

<details>
<summary>Solution</summary>

An [Indexed Job](https://kubernetes.io/docs/concepts/workloads/controllers/job/#completion-mode) gives each pod its number in the variable `JOB_COMPLETION_INDEX`:

```yaml
spec:
  completions: 5
  parallelism: 5
  completionMode: Indexed
  ttlSecondsAfterFinished: 120
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: thumb
        image: busybox:1.36
        command: [sh, -c, 'echo thumbnail $JOB_COMPLETION_INDEX done']
```

</details>

### Task 15: An Ingress with a default backend (5 points)

> In namespace `k3-edge`, create Ingress `edge` with class `nginx`: requests for `shop.k3.local` below `/shop` go to Service `shop`, and every other path of that host goes to Service `sorry` as the Ingress's default backend.

<details>
<summary>Solution</summary>

```bash
k -n k3-edge create ingress edge --class=nginx --default-backend=sorry:80 --rule='shop.k3.local/shop*=shop:80'
```

ingress-nginx uses an Ingress's `defaultBackend` for the paths of its hosts that no rule matches. A host that no Ingress names still gets the controller's own 404 page, which the test run showed with `other.k3.local`.

</details>

### Task 16: Port 80 without root (6 points)

> In namespace `k3-cap`, create pod `web80` that runs `httpd` from `busybox:1.36` on port 80, serving a page `web80`, as user 101. Drop every capability except `NET_BIND_SERVICE`, forbid privilege escalation, and make the root file system read-only.

<details>
<summary>Solution</summary>

```yaml
spec:
  securityContext: {runAsUser: 101, runAsGroup: 101}
  containers:
  - name: web
    image: busybox:1.36
    command: [sh, -c, 'mkdir -p /tmp/www && echo web80 > /tmp/www/index.html && exec httpd -f -p 80 -h /tmp/www']
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: {drop: [ALL], add: [NET_BIND_SERVICE]}
    volumeMounts: [{name: tmp, mountPath: /tmp}]
  volumes:
  - name: tmp
    emptyDir: {}
```

busybox's `httpd` binds port 80 as user 101 here, but not because of the capability. In the test run, the process had no effective capabilities at all, `CapEff: 0000000000000000` in `/proc/1/status`, because Linux gives added capabilities to a non-root process only through ambient capabilities, which Kubernetes doesn't set. Port 80 worked anyway, because containerd 2 sets `net.ipv4.ip_unprivileged_port_start=0` in every pod, so any user may bind any port. The `add` still matters for the exam's check, and on a runtime without that setting, the image itself would need the file capability on its binary, set with `setcap` at build time.

</details>

## Scoring

`score.sh` runs two to four checks per task, splits the task's points evenly over them, rounded down, and gives a task points only when its first check, the main change, passes. In the final test run it scored `TOTAL: 0 of 100 points (0%).` after `setup.sh`, and `TOTAL: 100 of 100 points (100%).` after `./platform-engineering/practice-exam.sh solve 3`, which took 59 seconds.

The first run of this practice exam scored 84, and the four lost tasks taught more than the ones that passed. Task 1's init container waited for a name that only the nodes resolve, task 9's quota deadlock needed the scale to 0, task 8's first check passed on an untouched cluster, and task 10's check counted the ServiceAccount token, which Kubernetes also mounts as a projected volume. The text above includes each fix.
