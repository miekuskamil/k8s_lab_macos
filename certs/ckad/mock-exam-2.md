# CKAD mock exam 2

> New to a term here? The [CKAD glossary](glossary.md) explains every term this track uses.

**Before the mock exam:** [mock exam 1](mock-exam.md) and a review of every point you lost there, and the [practice cluster](README.md#the-practice-cluster) with the CKAD extras.

Most tasks in this mock start from something broken: a pod that never schedules, a Service without endpoints, an Ingress that answers 503, a Helm release in the `failed` state. That matches the exam, where a good share of the tasks hand you a working cluster with one wrong field somewhere, and the skill is to find that field quickly from events, logs and `describe`. The last task builds a whole chain from an image to an Ingress. It has 16 tasks worth 100 points, with the same 2-hour clock.

## Rules

1. Start from a clean cluster with `./certs/ckad/cluster/reset.sh`, then run `MOCK=2 ./certs/ckad/mock-exam/setup.sh`. SETUP_TIME
2. The clock starts when `setup.sh` ends, and `MOCK=2 ./certs/ckad/mock-exam/score.sh` prints the minutes since then.
3. Work only on `cks-cp`, and use only kubernetes.io/docs, the Kubernetes blog and helm.sh/docs.
4. Don't open the solutions while the timer runs.
5. Score from your Mac with `MOCK=2 ./certs/ckad/mock-exam/score.sh`, or single tasks with `MOCK=2 ./certs/ckad/mock-exam/score.sh 4 9`.

Task files sit in `/opt/ckad/m2/N` on `cks-cp`. A task that says "fix" means: change as little as possible, and leave everything the task doesn't mention as it is.

## Tasks

| # | Task | Points | Domain |
|---|---|---|---|
| 1 | Pending pods | 5 | 03 |
| 2 | A container that exits | 6 | 03 |
| 3 | A Service with no endpoints | 6 | 05 |
| 4 | Ingress answers 503 | 6 | 05 |
| 5 | Refused by Pod Security | 7 | 04 |
| 6 | Refused by a quota | 6 | 04 |
| 7 | A Helm upgrade gone wrong | 7 | 02 |
| 8 | An overlay that won't build | 6 | 02 |
| 9 | Old API versions | 5 | 03 |
| 10 | Forbidden in the logs | 7 | 04 |
| 11 | A liveness probe that kills | 6 | 03 |
| 12 | A Job that never ends | 6 | 01 |
| 13 | Blocked by a default deny | 6 | 05 |
| 14 | A Dockerfile that won't build | 7 | 01 |
| 15 | CreateContainerConfigError | 6 | 04 |
| 16 | From image to Ingress | 8 | 01, 02, 05 |

### Task 1: Pending pods (5 points)

> The pods of Deployment `render` in namespace `k2-sched` stay `Pending`. Fix the Deployment so both pods run on `cks-w1`, each requesting 64Mi of memory.

<details>
<summary>Solution</summary>

`k -n k2-sched events --types=Warning` names the node selector first: `kubernetes.io/hostname: cks-w2` matches no node. After that fix, the next event names `Insufficient memory`, because the request says `64Gi`. Fix both in one edit:

```bash
k -n k2-sched edit deploy render    # nodeSelector: kubernetes.io/hostname: cks-w1, requests.memory: 64Mi
k -n k2-sched get pods -o wide
```

</details>

### Task 2: A container that exits (6 points)

> The pod of Deployment `poller` in namespace `k2-crash` restarts over and over. Write the reason the kubelet gives for its last termination, with the exit code, to `/opt/ckad/m2/2/reason.txt`. Then change its command so that it prints `polling` every 10 seconds forever.

<details>
<summary>Solution</summary>

```bash
k -n k2-crash describe pod -l app=poller | grep -A3 'Last State'
mkdir -p /opt/ckad/m2/2
k -n k2-crash get pod -l app=poller -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason} exit code {.items[0].status.containerStatuses[0].lastState.terminated.exitCode}' > /opt/ckad/m2/2/reason.txt
```

The reason is `Completed` with exit code 0: nothing failed, the command simply ended, and a Deployment's pods always restart. The fix is a loop:

```yaml
        command: ["sh", "-c", "while true; do echo polling; sleep 10; done"]
```

</details>

### Task 3: A Service with no endpoints (6 points)

> Pod `client` in namespace `k2-svc` gets no answer from `http://orders`. Fix Service `orders` so that it reaches both pods of Deployment `orders`. Don't change the Deployment.

<details>
<summary>Solution</summary>

```bash
k -n k2-svc get endpointslice -l kubernetes.io/service-name=orders
k -n k2-svc get pods --show-labels
k -n k2-svc get deploy orders -o jsonpath='{.spec.template.spec.containers[0].command}'
k -n k2-svc patch svc orders -p '{"spec":{"selector":{"app":"orders","tier":"api"},"ports":[{"port":80,"targetPort":9000}]}}'
```

The pods carry `tier=api`, not `tier=backend`, and their web server listens on 9000, which the command shows.

</details>

### Task 4: Ingress answers 503 (6 points)

> `curl -H 'Host: wiki.k2.local' http://<cks-w1>:30080/` should return the wiki from Deployment `wiki` in namespace `k2-ing`. Fix Ingress `wiki` so it does, and keep Service `wiki` as it is.

<details>
<summary>Solution</summary>

`k -n k2-ing describe ingress wiki` shows the backend `wiki-svc:80` with no endpoints: neither the name nor the port exists. The Service is `wiki` on port 8888:

```bash
k -n k2-ing patch ingress wiki --type=json -p '[{"op":"replace","path":"/spec/rules/0/http/paths/0/backend/service","value":{"name":"wiki","port":{"number":8888}}}]'
```

</details>

### Task 5: Refused by Pod Security (7 points)

> Deployment `metrics` in namespace `k2-psa` has no pods. Make both its pods run without changing the namespace's labels. The app writes `/data/metrics.log`, which must keep working.

<details>
<summary>Solution</summary>

The ReplicaSet's `FailedCreate` event lists the four fields the `restricted` level wants. The pods then also need a non-root user and a writable `/data`, because a non-root user may not create a folder in `/`:

```yaml
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        seccompProfile: {type: RuntimeDefault}
      volumes:
      - name: data
        emptyDir: {}
      containers:
      - name: busybox
        volumeMounts:
        - {name: data, mountPath: /data}
        securityContext:
          allowPrivilegeEscalation: false
          capabilities: {drop: ["ALL"]}
```

</details>

### Task 6: Refused by a quota (6 points)

> Deployment `search` in namespace `k2-quota` should run 4 pods and runs none. Create a LimitRange `defaults` that gives every container default requests and limits for CPU and memory, small enough that all 4 pods fit the quota, and get the pods running. Don't change the quota or the Deployment's spec.

<details>
<summary>Solution</summary>

```yaml
apiVersion: v1
kind: LimitRange
metadata: {name: defaults, namespace: k2-quota}
spec:
  limits:
  - type: Container
    default: {cpu: 200m, memory: 128Mi}
    defaultRequest: {cpu: 100m, memory: 64Mi}
```

```bash
k apply -f lr.yaml
k -n k2-quota rollout restart deploy search
```

The ReplicaSet retries on its own with growing pauses, and the restart only speeds that up. Four pods use 400m of CPU requests, exactly the quota.

</details>

### Task 7: A Helm upgrade gone wrong (7 points)

> The last upgrade of release `portal` in namespace `k2-helm`, to chart `webapp` 0.2.0, failed. Write the number of the failed revision to `/opt/ckad/m2/7/failed.txt`. Then upgrade the release again to chart 0.2.0 with the chart's own image and 2 replicas, so that the newest revision is deployed.

<details>
<summary>Solution</summary>

```bash
helm -n k2-helm history portal
helm -n k2-helm get values portal --revision 2
mkdir -p /opt/ckad/m2/7 && echo 2 > /opt/ckad/m2/7/failed.txt
helm -n k2-helm upgrade portal oci://registry.ckad:5000/charts/webapp --version 0.2.0 --plain-http --set replicaCount=2
k -n k2-helm rollout status deploy portal-webapp
```

Revision 2 set `image.repository=docker.io/library/ngnix`, a typo. An upgrade without `--reuse-values` starts from the chart's defaults, which drops the typo, so `replicaCount` must come back with `--set`. Leave `--wait` out here: in the test run, the broken revision had kept the Deployment stuck for more than 10 minutes, so it carried the condition `ProgressDeadlineExceeded`, and Helm 4's `--wait` read that as a failure at once and marked the good upgrade `failed` as well. `kubectl rollout status` waits for the new pods instead.

</details>

### Task 8: An overlay that won't build (6 points)

> `kubectl apply -k /opt/ckad/m2/8/overlays/live` fails. Fix the overlay so it deploys the base into namespace `k2-kust` with the suffix `-live` and 2 replicas.

<details>
<summary>Solution</summary>

Two lines are wrong: `resources` points at `../base`, which doesn't exist from `overlays/live`, and `replicas` names `gateway-live`, while Kustomize matches the base's name `gateway` before it adds the suffix:

```yaml
resources:
- ../../base
namespace: k2-kust
nameSuffix: -live
replicas:
- name: gateway
  count: 2
```

</details>

### Task 9: Old API versions (5 points)

> `/opt/ckad/m2/9/old.yaml` holds a CronJob and an Ingress for namespace `k2-api` in API versions that no longer exist. Write a working version to `/opt/ckad/m2/9/new.yaml`, with the Ingress using class `nginx` and `pathType: Prefix`, and apply it.

<details>
<summary>Solution</summary>

The CronJob only needs `batch/v1`. The Ingress needs `networking.k8s.io/v1`, a `pathType` on every path, and the new backend form:

```yaml
        backend:
          service:
            name: rotate
            port:
              number: 80
```

`k explain ingress.spec.rules.http.paths.backend` shows the fields.

</details>

### Task 10: Forbidden in the logs (7 points)

> Pod `scaler` in namespace `k2-ops` reads the scale of Deployment `billing` in namespace `k2-apps` every 5 seconds, and its log shows errors. Give its ServiceAccount the rights to get and update the scale of Deployments in `k2-apps`, and nothing more.

<details>
<summary>Solution</summary>

The scale is a subresource, so the rule names `deployments/scale`, and the Role and RoleBinding go into `k2-apps`:

```bash
k -n k2-apps create role scaler --verb=get,update,patch --resource=deployments/scale
k -n k2-apps create rolebinding scaler --role=scaler --serviceaccount=k2-ops:scaler
k auth can-i update deployments --subresource=scale -n k2-apps --as=system:serviceaccount:k2-ops:scaler
```

</details>

### Task 11: A liveness probe that kills (6 points)

> The pod of Deployment `slowstart` in namespace `k2-probe` needs about 25 seconds to start, and its liveness probe kills it first. Add a startup probe on `/` port 8080 that gives it at least 40 seconds, and leave the liveness probe as it is.

<details>
<summary>Solution</summary>

```yaml
        startupProbe:
          httpGet: {path: /, port: 8080}
          periodSeconds: 5
          failureThreshold: 12
```

12 tries 5 seconds apart give it 60 seconds. The liveness probe only starts once the startup probe has succeeded.

</details>

### Task 12: A Job that never ends (6 points)

> Job `migrate` in namespace `k2-job` expects a file `/config/schema.sql`. Create a ConfigMap `schema` whose `schema.sql` holds two statements, one per line, `CREATE TABLE a (id int);` and `CREATE TABLE b (id int);`, mount it at `/config`, and limit the retries to 4. The Job must complete.

<details>
<summary>Solution</summary>

A Job's pod template stays fixed after creation, so save the Job, delete it, edit the file and create it again:

```bash
printf 'CREATE TABLE a (id int);\nCREATE TABLE b (id int);\n' > schema.sql
k -n k2-job create cm schema --from-file=schema.sql
k -n k2-job get job migrate -o yaml > job.yaml
k -n k2-job delete job migrate
```

In `job.yaml`, delete `status`, `metadata.uid`, `resourceVersion`, the `selector` and the template's generated labels, set `backoffLimit: 4`, and add the volume and its mount, then `k apply -f job.yaml`.

</details>

### Task 13: Blocked by a default deny (6 points)

> Namespace `k2-net` has a NetworkPolicy `default-deny` for all traffic in both directions, which must stay. Add policies so that pod `storefront` reaches `http://inventory`, the Service of pod `inventory` on 8080, and nothing else changes.

<details>
<summary>Solution</summary>

Both ends need a rule, and the client needs DNS too:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: storefront-egress, namespace: k2-net}
spec:
  podSelector: {matchLabels: {app: storefront}}
  policyTypes: [Egress]
  egress:
  - to: [{podSelector: {matchLabels: {app: inventory}}}]
    ports: [{protocol: TCP, port: 8080}]
  - ports: [{protocol: UDP, port: 53}, {protocol: TCP, port: 53}]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: {name: inventory-ingress, namespace: k2-net}
spec:
  podSelector: {matchLabels: {app: inventory}}
  policyTypes: [Ingress]
  ingress:
  - from: [{podSelector: {matchLabels: {app: storefront}}}]
    ports: [{protocol: TCP, port: 8080}]
```

</details>

### Task 14: A Dockerfile that won't build (7 points)

> `podman build` fails on `/opt/ckad/m2/14/Dockerfile`. Fix it, build and push `registry.ckad:5000/label:v2`, and roll Deployment `label` in namespace `k2-image` out to that image.

<details>
<summary>Solution</summary>

The build stops at `COPY src/serve.sh`, because the script lives in `app/`:

```bash
cd /opt/ckad/m2/14
sed -i 's|COPY src/serve.sh|COPY app/serve.sh|' Dockerfile
podman build -t registry.ckad:5000/label:v2 . && podman push registry.ckad:5000/label:v2
k -n k2-image set image deploy/label label=registry.ckad:5000/label:v2
```

</details>

### Task 15: CreateContainerConfigError (6 points)

> The pod of Deployment `mailer` in namespace `k2-cfg` shows `CreateContainerConfigError`. Fix the Deployment so that it logs `sending as mailer via smtp.k2.local`, using the Secret `smtp` and the ConfigMap `mail-settings` that exist. Don't change them.

<details>
<summary>Solution</summary>

`k -n k2-cfg describe pod -l app=mailer` names the first missing reference: Secret `smtp-credentials`. `k -n k2-cfg get secret smtp -o yaml` and `k -n k2-cfg get cm mail-settings -o yaml` show the real keys:

```yaml
        env:
        - name: SMTP_USER
          valueFrom: {secretKeyRef: {name: smtp, key: username}}
        - name: SMTP_HOST
          valueFrom: {configMapKeyRef: {name: mail-settings, key: SMTP_HOST}}
```

Keys are case-sensitive, so `smtp_host` misses `SMTP_HOST`.

</details>

### Task 16: From image to Ingress (8 points)

> Build `/opt/ckad/m2/16/Dockerfile` as `registry.ckad:5000/status:1` and push it. In namespace `k2-chain`, run it as Deployment `status` with 2 replicas and a readiness probe on `/` port 8080, expose it as Service `status` on port 80, and publish it through an Ingress with class `nginx` for `status.k2.local`.

<details>
<summary>Solution</summary>

```bash
cd /opt/ckad/m2/16
podman build -t registry.ckad:5000/status:1 . && podman push registry.ckad:5000/status:1
k -n k2-chain create deploy status --image=registry.ckad:5000/status:1 --replicas=2 --port=8080 $do > status.yaml
# add under the container: readinessProbe: {httpGet: {path: /, port: 8080}}
k apply -f status.yaml
k -n k2-chain expose deploy status --port=80 --target-port=8080
k -n k2-chain create ingress status --class=nginx --rule='status.k2.local/*=status:80'
```

</details>

## Scoring

SCORING
