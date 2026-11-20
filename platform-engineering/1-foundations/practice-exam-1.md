# Timed practice exam 1: applications, one topic per task

> New to a term here? The [glossary](../glossary.md#applications-on-kubernetes) explains every term these modules use.

**Before the practice exam:** modules 33 to 37, or the confidence to skip them, and the [practice cluster](../practice-cluster.md#the-application-extras) with the application extras. This is the first of three practice exams, and [practice exam 2](practice-exam-2.md) and [practice exam 3](practice-exam-3.md) get harder.

The real exam gives you 2 hours for 15 to 20 tasks, and this practice exam gives you 2 hours for 16 tasks worth 100 points, one topic per task, spread over modules 33 to 37 by their size. A script checks the cluster's state afterwards and gives partial credit, the way the exam does.

## Rules

1. Start from a clean cluster with `./platform-engineering/practice/app-extras/reset.sh`, then run `./platform-engineering/practice-exam.sh setup 1`. In the test run, the reset took 45 seconds and the setup 27 seconds, because the nodes already had the images; on a new cluster the first run also downloads them.
2. The clock starts when `setup.sh` ends, because it writes the start time, and `score.sh` prints the minutes since then and flags a run over 120 minutes.
3. Work only on `cks-cp`, in a root shell from `orb -m cks-cp` and `sudo -i`, and use only the documentation the exam allows: kubernetes.io/docs, the Kubernetes blog and helm.sh/docs.
4. Don't open the solutions while the timer runs, because the score only means something when you worked without them.
5. When time is up, score from your Mac with `./platform-engineering/practice-exam.sh score 1`, or score single tasks with `./platform-engineering/practice-exam.sh score 1 4 9`.

Task files sit in `/opt/ckad/m1/N` on `cks-cp`, where N is the task's number. Every task names its namespace, and the namespaces already exist.

## Tasks

| # | Task | Points | Module |
|---|---|---|---|
| 1 | Build, push and run an image | 8 | 33 |
| 2 | A log sidecar | 6 | 33 |
| 3 | A nightly CronJob | 5 | 33 |
| 4 | Update, then roll back | 6 | 34 |
| 5 | A quarter of the traffic | 6 | 34 |
| 6 | A Helm release | 6 | 34 |
| 7 | A Kustomize overlay | 6 | 34 |
| 8 | Probes for an API | 6 | 35 |
| 9 | Why the pod crashes | 5 | 35 |
| 10 | The hungriest pod | 4 | 35 |
| 11 | ConfigMap and Secret | 8 | 36 |
| 12 | Defaults and requests | 6 | 36 |
| 13 | A ServiceAccount that reads ConfigMaps | 8 | 36 |
| 14 | Run as a normal user | 6 | 36 |
| 15 | Service and Ingress | 8 | 37 |
| 16 | Only the frontend reaches the API | 6 | 37 |

### Task 1: Build, push and run an image (8 points)

> `/opt/ckad/m1/1` holds a Dockerfile. Build it as `registry.ckad:5000/ticker:1.0`, push it, and also save it to `/opt/ckad/m1/1/ticker.tar`. Then run it as Deployment `ticker` with 2 replicas in namespace `k1-build`.

<details>
<summary>Solution</summary>

```bash
cd /opt/ckad/m1/1
podman build -t registry.ckad:5000/ticker:1.0 .
podman push registry.ckad:5000/ticker:1.0
podman save -o ticker.tar registry.ckad:5000/ticker:1.0
k -n k1-build create deploy ticker --image=registry.ckad:5000/ticker:1.0 --replicas=2
k -n k1-build logs deploy/ticker
```

The image's `WORKDIR /app` makes `ticker.sh` a path relative to `/app`, which is why `CMD ["sh", "ticker.sh"]` works.

</details>

### Task 2: A log sidecar (6 points)

> `/opt/ckad/m1/2/audit.yaml` describes pod `audit` in namespace `k1-pods`, whose container `app` writes to `/var/log/audit.log`. Add a native sidecar `log-tail` (image `busybox:1.36`) that runs `tail -F /var/log/audit.log`, with an emptyDir volume shared by both containers at `/var/log`, and create the pod.

<details>
<summary>Solution</summary>

```yaml
spec:
  initContainers:
  - name: log-tail
    image: busybox:1.36
    restartPolicy: Always
    command: ["sh", "-c", "tail -F /var/log/audit.log"]
    volumeMounts:
    - {name: logs, mountPath: /var/log}
  containers:
  - name: app
    ...
    volumeMounts:
    - {name: logs, mountPath: /var/log}
  volumes:
  - name: logs
    emptyDir: {}
```

Then `k apply -f /opt/ckad/m1/2/audit.yaml` and `k -n k1-pods logs audit -c log-tail`.

</details>

### Task 3: A nightly CronJob (5 points)

> In namespace `k1-batch`, create a CronJob `report` (image `busybox:1.36`, command `sh -c 'echo report done'`) that runs at 01:30 every day, keeps 1 successful and 1 failed Job, retries a failed run at most twice, and never restarts a pod in place. Then run it once now as Job `report-now`.

<details>
<summary>Solution</summary>

```bash
k -n k1-batch create cronjob report --image=busybox:1.36 --schedule='30 1 * * *' $do -- sh -c 'echo report done' > cj.yaml
```

Add to `cj.yaml`:

```yaml
spec:
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: Never
```

```bash
k apply -f cj.yaml
k -n k1-batch create job report-now --from=cronjob/report
```

`restartPolicy: Never` is what "never restarts a pod in place" means: a failed run gets a new pod, counted against `backoffLimit`.

</details>

### Task 4: Update, then roll back (6 points)

> Deployment `store` in namespace `k1-roll` runs `nginx:1.27-alpine`. Update it to `nginx:1.28-alpine` with the change cause `image 1.28`, save its rollout history to `/opt/ckad/m1/4/history.txt`, then roll it back to the previous version.

<details>
<summary>Solution</summary>

```bash
k -n k1-roll set image deploy/store nginx=nginx:1.28-alpine
k -n k1-roll annotate deploy store kubernetes.io/change-cause='image 1.28'
k -n k1-roll rollout status deploy store
mkdir -p /opt/ckad/m1/4
k -n k1-roll rollout history deploy store > /opt/ckad/m1/4/history.txt
k -n k1-roll rollout undo deploy store
```

The undo turns revision 1 into revision 3, which the check looks for.

</details>

### Task 5: A quarter of the traffic (6 points)

> In namespace `k1-canary`, Service `checkout` selects `app=checkout` and sends traffic to Deployment `checkout-v1` (3 pods that answer `v1`). Add Deployment `checkout-v2` with labels `app=checkout` and `version=v2`, whose pods answer `v2`, so that it gets about a quarter of the requests.

<details>
<summary>Solution</summary>

Copy `checkout-v1` with `k -n k1-canary get deploy checkout-v1 -o yaml`, rename it to `checkout-v2`, set `replicas: 1`, change `version: v1` to `version: v2` in the selector and the template, and `echo v1` to `echo v2` in the command. Three v1 pods and one v2 pod give v2 a quarter of the endpoints.

</details>

### Task 6: A Helm release (6 points)

> In namespace `k1-helm`, install chart `oci://registry.ckad:5000/charts/webapp` version 0.2.0 as release `catalog`, with the values in `/opt/ckad/m1/6/values.yaml` and, on top, `image.pullPolicy=Always`.

<details>
<summary>Solution</summary>

```bash
helm -n k1-helm install catalog oci://registry.ckad:5000/charts/webapp --version 0.2.0 --plain-http \
  -f /opt/ckad/m1/6/values.yaml --set image.pullPolicy=Always
helm -n k1-helm get values catalog
```

`--set` wins over `-f` when both name the same key, and `helm get values` shows the merged user values.

</details>

### Task 7: A Kustomize overlay (6 points)

> `/opt/ckad/m1/7/base` holds Deployment `frontend`. Create an overlay in `/opt/ckad/m1/7/overlays/qa` that deploys it to namespace `k1-kust` as `qa-frontend` with 2 replicas, the label `stage=qa` on the pods, and a generated ConfigMap `frontend-settings` with `STAGE=qa` that the container reads with `envFrom`. Apply it.

<details>
<summary>Solution</summary>

```yaml
resources:
- ../../base
namespace: k1-kust
namePrefix: qa-
labels:
- pairs:
    stage: qa
  includeTemplates: true
replicas:
- name: frontend
  count: 2
configMapGenerator:
- name: frontend-settings
  literals:
  - STAGE=qa
patches:
- patch: |-
    - op: add
      path: /spec/template/spec/containers/0/envFrom
      value:
      - configMapRef:
          name: frontend-settings
  target:
    kind: Deployment
    name: frontend
```

`k apply -k /opt/ckad/m1/7/overlays/qa`. Kustomize rewrites the reference `frontend-settings` to the generated name with prefix and hash, such as `qa-frontend-settings-6k2h8f9c4t`.

</details>

### Task 8: Probes for an API (6 points)

> Deployment `api` in namespace `k1-probe` serves files on port 8080 from `/www`. Add a readiness probe, HTTP GET `/ready` on 8080, first after 3 seconds and then every 4, and a liveness probe that runs `test -f /www/live` every 15 seconds.

<details>
<summary>Solution</summary>

```yaml
        readinessProbe:
          httpGet: {path: /ready, port: 8080}
          initialDelaySeconds: 3
          periodSeconds: 4
        livenessProbe:
          exec:
            command: ["test", "-f", "/www/live"]
          periodSeconds: 15
```

Add both with `k -n k1-probe edit deploy api` under the container, then `k -n k1-probe rollout status deploy api`.

</details>

### Task 9: Why the pod crashes (5 points)

> In namespace `k1-logs`, one Deployment's pod keeps crashing. Write its error line, the one that starts with `ERROR`, to `/opt/ckad/m1/9/error.txt`, and the exit code of its last crash to `/opt/ckad/m1/9/exit-code.txt`.

<details>
<summary>Solution</summary>

```bash
k -n k1-logs get pods
mkdir -p /opt/ckad/m1/9
k -n k1-logs logs deploy/importer --previous | grep ERROR > /opt/ckad/m1/9/error.txt
k -n k1-logs get pod -l app=importer -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.exitCode}' > /opt/ckad/m1/9/exit-code.txt
```

`k describe pod` shows the same exit code under `Last State: Terminated`. When the pod sits in `Error`, use `k logs` without `--previous`, as [module 35](35-observing-and-debugging-applications.md#concept-logs-events-and-metrics) explains.

</details>

### Task 10: The hungriest pod (4 points)

> Write the name of the pod in namespace `k1-top` that uses the most memory into `/opt/ckad/m1/10/pod.txt`.

<details>
<summary>Solution</summary>

```bash
k -n k1-top top pod --sort-by=memory
mkdir -p /opt/ckad/m1/10 && echo large > /opt/ckad/m1/10/pod.txt
```

Each pod writes a file into an emptyDir with `medium: Memory`, and memory-backed files count as the container's memory, so `large` shows about 96Mi.

</details>

### Task 11: ConfigMap and Secret (8 points)

> In namespace `k1-config`, create ConfigMap `shop-config` with `SHOP_MODE=live` and Secret `shop-api` with `key=abc-123`. Create pod `shop` (image `busybox:1.36`, command `sleep 1d`) that gets `SHOP_MODE` as an environment variable and the Secret as files in `/run/secrets/shop`, not as a variable.

<details>
<summary>Solution</summary>

```bash
k -n k1-config create cm shop-config --from-literal=SHOP_MODE=live
k -n k1-config create secret generic shop-api --from-literal=key=abc-123
```

```yaml
spec:
  containers:
  - name: shop
    image: busybox:1.36
    command: [sleep, 1d]
    env:
    - name: SHOP_MODE
      valueFrom: {configMapKeyRef: {name: shop-config, key: SHOP_MODE}}
    volumeMounts:
    - {name: api, mountPath: /run/secrets/shop, readOnly: true}
  volumes:
  - name: api
    secret: {secretName: shop-api}
```

</details>

### Task 12: Defaults and requests (6 points)

> In namespace `k1-res`, create a LimitRange `mem-defaults` that gives every container a default memory limit of 256Mi and a default memory request of 128Mi. Then give Deployment `cache` a CPU request of 250m and a CPU limit of 500m, so that its new pod gets both its CPU numbers and the memory defaults.

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: LimitRange
metadata: {name: mem-defaults, namespace: k1-res}
spec:
  limits:
  - type: Container
    default: {memory: 256Mi}
    defaultRequest: {memory: 128Mi}
```

```bash
k apply -f lr.yaml
k -n k1-res set resources deploy cache --requests=cpu=250m --limits=cpu=500m
```

The LimitRange first, because the defaults only reach pods created after it, and the `set resources` creates the new pod.

</details>

### Task 13: A ServiceAccount that reads ConfigMaps (8 points)

> In namespace `k1-rbac`, create a ServiceAccount `config-reader`, a Role `config-reader` that may get, list and watch ConfigMaps, and a RoleBinding `config-reader` that grants it. Make Deployment `config-sync` run as that ServiceAccount.

<details>
<summary>Solution</summary>

```bash
k -n k1-rbac create sa config-reader
k -n k1-rbac create role config-reader --verb=get,list,watch --resource=configmaps
k -n k1-rbac create rolebinding config-reader --role=config-reader --serviceaccount=k1-rbac:config-reader
k -n k1-rbac set serviceaccount deploy config-sync config-reader
k auth can-i watch configmaps -n k1-rbac --as=system:serviceaccount:k1-rbac:config-reader
```

</details>

### Task 14: Run as a normal user (6 points)

> Deployment `worker` in namespace `k1-sec` runs as root. Make it run as user 2000 and group 2000, refuse to start as root, forbid privilege escalation and drop every capability. It writes to `/tmp`, which must keep working.

<details>
<summary>Solution</summary>

```yaml
    spec:
      securityContext:
        runAsUser: 2000
        runAsGroup: 2000
        runAsNonRoot: true
      containers:
      - name: busybox
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

`/tmp` in busybox is writable for every user, so the container needs no volume here, as long as the root file system stays writable.

</details>

### Task 15: Service and Ingress (8 points)

> In namespace `k1-web`, expose Deployment `docs`, whose pods listen on 8080, as a ClusterIP Service `docs` on port 80, and create an Ingress `docs` with class `nginx` that sends every path of `docs.k1.local` to it.

<details>
<summary>Solution</summary>

```bash
k -n k1-web expose deploy docs --port=80 --target-port=8080
k -n k1-web create ingress docs --class=nginx --rule='docs.k1.local/*=docs:80'
curl -s -H 'Host: docs.k1.local' http://$(k get node cks-w1 -o jsonpath='{.status.addresses[0].address}'):30080/
```

</details>

### Task 16: Only the frontend reaches the API (6 points)

> In namespace `k1-np`, create a NetworkPolicy `api-ingress` so that pod `api` (label `app=api`) accepts connections on port 8080 only from pods labelled `tier=frontend`. Leave the other pods' traffic as it is.

<details>
<summary>Solution</summary>

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: api-ingress, namespace: k1-np}
spec:
  podSelector: {matchLabels: {app: api}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {tier: frontend}}}]
    ports: [{protocol: TCP, port: 8080}]
```

A default deny for the whole namespace would also stop `batch` from reaching `frontend`, which the task says to leave alone, and the check tests that.

</details>

## Scoring

`score.sh` runs two to four checks per task and splits the task's points evenly over them, rounded down, then prints each check, the points per task and the total. A task scores only when its first check, the main change, passes, so checks such as "the key is not an environment variable" earn nothing on an untouched cluster, where they pass by themselves.

In the test run, on a cluster fresh from `reset.sh` and `setup.sh`, the score was `TOTAL: 0 of 100 points (0%).` After `./platform-engineering/practice-exam.sh solve 1`, which applies every solution above and took 62 seconds, it was `TOTAL: 100 of 100 points (100%).` The first full run scored 95, because the reference solution of task 9 read the log with `--previous` while the pod sat in `Error`, the trap that [module 35](35-observing-and-debugging-applications.md#concept-logs-events-and-metrics) describes; the solution now reads both logs, and the fixed task scored 5 of 5.
