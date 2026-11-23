# Module 6.5: Backup and disaster recovery

> New to a term here, like RPO, restore drill or backup hook? The [glossary](../glossary.md#reliability-engineering) explains every term in this course.

**Before this module:** [module 6.1](01-slis-slos-and-error-budgets.md), for the idea that reliability is a number you agree on; this module needs none of its apps. No Istio needed.

**You need:** the lab running and `./lab.sh shell` for the commands.

Sooner or later someone deletes the wrong namespace, a volume dies with its node, or an upgrade corrupts a database, and then two numbers decide how bad the day gets: how much data the team loses, and how long the service stays down. A backup that nobody ever restored answers neither, because the first restore is where most backups turn out broken. This module runs a PostgreSQL database with the CloudNativePG operator, backs up its whole namespace with Velero into an object store inside the cluster, proves the backup in a restore drill next to the running database, and then deletes the namespace and brings it back.

Time: about 50 minutes. Memory: the object store, the operator, Velero and the database add about 600 MiB, and SeaweedFS takes up to 768 MiB while a backup uploads; the reset removes all of them.

## Concept: two kinds of state, two numbers

A namespace holds two kinds of state, and a backup has to carry both. The first kind is the Kubernetes objects: the CloudNativePG `Cluster`, its Secrets with the database passwords, its Services and the claim for its volume. The second kind is the data on the volume itself, the files PostgreSQL writes, which no object describes. Restore the objects without the data and you get an empty database with the right name; restore the data without the objects and nothing mounts it.

Two numbers describe what a restore costs, and the team agrees on both before it chooses a tool:

| Number | Question it answers | Set by | In this module |
|---|---|---|---|
| **RPO**, recovery point objective | How much data may we lose? | how often backups run | everything written after the backup is gone, step 5 shows 20 orders |
| **RTO**, recovery time objective | How long may the restore take? | the restore's speed, and practice | about a minute in the test run, step 6 |

A nightly backup gives an RPO of up to 24 hours, which suits a catalogue but not a shop's orders, so production databases add continuous archiving of the database's write-ahead log, which brings the RPO down to seconds. This module stays with Velero's namespace backups, which suit most stateless and lightly stateful apps, and names the database-native route where it matters.

## Concept: what Velero copies, and where

![Two kinds of state, one backup: you start a backup, the Velero server runs a CHECKPOINT hook in the postgres pod, writes every object of the namespace to the bucket as JSON, and the node agent reads the volume's files from the node's disk and uploads them in chunks to SeaweedFS](../../docs/diagrams/chapters/6.5-backup-and-restore.svg)

The lab's volumes come from k3s's local-path provisioner, a folder on the node's disk with no snapshot API, so Velero copies files instead of taking snapshots. A backup runs these steps, the numbers in the picture:

1. You start the backup with Velero's command line, which lives inside the Velero pod, so `kubectl exec` runs it and you install nothing.
2. The **velero server** runs the backup hook in the database pod first: `CHECKPOINT` makes PostgreSQL write every change from memory to its data files, so the copy needs less repair later.
3. The server lists every object in the namespace and writes each one to the bucket as JSON.
4. The **node agent**, a DaemonSet with access to the node's pod volumes, reads the files of the volume `pgdata`.
5. It uploads them with Kopia, which splits files into chunks and stores each chunk once, so the next backup sends only what changed.

A restore runs the same way backwards: the server recreates the objects, adds a small init container to the restored pod that waits, and the node agent writes the files back into the new volume before PostgreSQL starts.

The bucket lives in **SeaweedFS**, an object store with the same S3 API as AWS, in its own namespace. MinIO, the usual choice for labs, no longer publishes its server images, and Velero only needs the S3 API.

## The bigger picture: backups are a restore you have not tried yet

Every outage report about lost data says the same thing in different words: the backups ran, but nobody had restored one. So teams that take recovery seriously schedule restores, not only backups: a weekly drill restores the latest backup into a new namespace or cluster, checks the data, and records how long it took, which is the measured RTO. The **restore drill** in step 5 is the small version of that.

For databases the industry moved to two layers. A tool like Velero carries the Kubernetes objects and the volumes of ordinary apps, while the database operator, such as CloudNativePG with its Barman plugin, streams base backups and the write-ahead log to object storage for point-in-time recovery. The two meet in the same bucket, and the drill tests both.

## Why this way

**Why a file system backup and not a volume snapshot?** Snapshots are faster and consistent to the millisecond, but they need a CSI driver that supports them, and k3s's local-path volumes have none. File system backup works on any volume the node agent reaches through the node, which is also what many on-premises clusters run.

**Why the CHECKPOINT hook, if PostgreSQL recovers anyway?** A copy of a running database's files is crash-consistent at best: PostgreSQL treats the restore like a power cut and replays its write-ahead log. The checkpoint just before the copy keeps that replay short. For guaranteed consistency, production uses the database's own backup or a snapshot taken in one instant.

**Why the object store in its own namespace?** The drill in step 6 deletes `course-dr`. A bucket inside that namespace would vanish with it, which is the lab's version of keeping the backups on the server that burns. Real backups go further: another cluster, region or cloud account.

**Why run `velero` through `kubectl exec`?** The toolbox has no Velero binary, and the server image ships one, so a shell variable that names the server pod is enough. The chart's Deployment selector also matches the node agent's pods, which is why the commands look the pod up by its `name=velero` label instead of using `deploy/velero`.

## Do it

### 1. An object store for the backups

```console
$ kubectl apply -f platform-engineering/manifests/6.5-object-store.yaml
namespace/course-backup created
secret/s3-config created
deployment.apps/seaweedfs created
service/seaweedfs created

$ kubectl -n course-backup rollout status deploy/seaweedfs --timeout=300s
Waiting for deployment "seaweedfs" rollout to finish: 0 of 1 updated replicas are available...
deployment "seaweedfs" successfully rolled out

$ kubectl -n course-backup exec deploy/seaweedfs -- sh -c 'echo "s3.bucket.create -name velero" | weed shell'
create bucket under /buckets
created bucket velero
```

**What you should see.** SeaweedFS runs its master, volume server, filer and S3 gateway in one process, and `weed shell`, its admin console, creates the bucket `velero`. Velero never creates buckets by itself, which is why this step exists. The Secret holds the one identity Velero signs its S3 requests with.

### 2. Install CloudNativePG and Velero

```console
$ helm repo add cnpg https://cloudnative-pg.github.io/charts
"cnpg" has been added to your repositories

$ helm repo add vmware-tanzu https://vmware-tanzu.github.io/helm-charts
"vmware-tanzu" has been added to your repositories

$ helm install cnpg cnpg/cloudnative-pg --version 0.29.1 -n cnpg-system --create-namespace -f platform-engineering/manifests/6.5-cnpg-values.yaml --wait
NAME: cnpg
LAST DEPLOYED: Sun Nov 22 01:11:55 2026
NAMESPACE: cnpg-system
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
...

$ helm install velero vmware-tanzu/velero --version 12.2.2 -n velero --create-namespace -f platform-engineering/manifests/6.5-velero-values.yaml --wait
NAME: velero
LAST DEPLOYED: Sun Nov 22 01:12:02 2026
NAMESPACE: velero
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
...

$ kubectl -n velero get pods
NAME                      READY   STATUS    RESTARTS   AGE
node-agent-62j8m          1/1     Running   0          31s
velero-7bf757957b-v8ghn   1/1     Running   0          31s

$ kubectl -n velero get backupstoragelocation
NAME      PHASE       LAST VALIDATED   AGE   DEFAULT
default   Available   29s              31s   true
```

Both installs print notes after `...`, a sample cluster and a link to download the Velero client, which the next step does without.

**What you should see.** Two Velero pods: the server, and the node agent, one per node. The backup location turns `Available` once the server has listed the bucket with the credentials from the values file, so if it stays `Unavailable`, check the bucket name, the URL and the keys first. In `6.5-velero-values.yaml`, an init container copies the AWS plugin into the server, because Velero's core only knows how to talk to plugins, and `s3ForcePathStyle` tells it to address the bucket as a path, which SeaweedFS needs.

### 3. A database with orders in it

```console
$ kubectl apply -f platform-engineering/manifests/6.5-orders-db.yaml
namespace/course-dr created
cluster.postgresql.cnpg.io/orders-db created

$ kubectl -n course-dr wait --for=condition=Ready cluster/orders-db --timeout=300s
cluster.postgresql.cnpg.io/orders-db condition met

$ kubectl -n course-dr get cluster,pods,pvc
NAME                                   AGE   INSTANCES   READY   STATUS                     PRIMARY
cluster.postgresql.cnpg.io/orders-db   19s   1           1       Cluster in healthy state   orders-db-1

NAME              READY   STATUS    RESTARTS   AGE
pod/orders-db-1   1/1     Running   0          11s

NAME                                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/orders-db-1   Bound    pvc-9caa21c4-7fa7-4c81-ae48-a1493b1e6a0b   1Gi        RWO            local-path     <unset>                 19s

$ kubectl -n course-dr exec orders-db-1 -c postgres -- psql -U postgres -d orders -c "CREATE TABLE orders (id serial PRIMARY KEY, item text, placed timestamptz DEFAULT now()); INSERT INTO orders (item) SELECT 'book-' || g FROM generate_series(1, 500) g;"
CREATE TABLE
INSERT 0 500

$ kubectl -n course-dr exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc "SELECT count(*) FROM orders"
500
```

**What you should see.** The operator turns the short `Cluster` resource into a pod, a 1 GiB volume, three Services (`-rw` for the primary, `-ro` and `-r` for reads) and Secrets with the passwords, and reports `Cluster in healthy state` within about 20 seconds. The table now holds 500 orders, the data this module protects.

### 4. Back up the namespace

The `velero` command lives in the server's image, so a variable that names the server pod is all you need. Look it up by its label, because the chart's `deploy/velero` selector also matches the node agent's pod.

```console
$ V=$(kubectl -n velero get pod -l name=velero -o name)

$ echo $V
pod/velero-7bf757957b-v8ghn

$ kubectl -n velero exec $V -c velero -- /velero backup create orders-1 --include-namespaces course-dr --default-volumes-to-fs-backup --wait
Backup request "orders-1" submitted successfully.
Waiting for backup to complete. You may safely press ctrl-c to stop waiting - your backup will continue in the background.
.....................
Backup completed with status: Completed. You may check for more information using the commands `velero backup describe orders-1` and `velero backup logs orders-1`.

$ kubectl -n velero exec $V -c velero -- /velero backup describe orders-1 --details --colorized=false | grep -E -A3 '^Phase|^Total items|Pod Volume Backups|^HooksAttempted|^HooksFailed'
Phase:  Completed


Namespaces:
--
Total items to be backed up:  53
Items backed up:              53

Resource List:
--
  Pod Volume Backups - kopia:
    Completed:
      course-dr/orders-db-1: pgdata (size: 64847534, incremental size: 64847534), scratch-data (size: 61083124, incremental size: 61083124), shm (size: 1080552, incremental size: 1080552)

HooksAttempted:  1
HooksFailed:     0

$ kubectl -n course-backup exec deploy/seaweedfs -- sh -c 'echo "fs.ls /buckets/velero" | weed shell'
backups
kopia
```

**What you should see.** The backup completed in about 20 seconds with 53 objects, from the Cluster resource down to the Secrets and Services, and the hook ran once without failing. Kopia copied three volumes of the pod: `pgdata`, about 65 MB of database files, and two scratch volumes the operator mounts. The bucket now has two folders, `backups` with the objects as JSON and `kopia` with the volume chunks, the two kinds of state from the first concept.

### 5. A restore drill, next to the running database

Orders keep arriving after every backup. Add 20, then restore the backup into a new namespace while the original keeps running:

```console
$ kubectl -n course-dr exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc "INSERT INTO orders (item) SELECT 'late-' || g FROM generate_series(1, 20) g; SELECT count(*) FROM orders"
INSERT 0 20
520

$ kubectl -n velero exec $V -c velero -- /velero restore create drill-1 --from-backup orders-1 --namespace-mappings course-dr:course-dr-drill --wait
Restore request "drill-1" submitted successfully.
Waiting for restore to complete. You may safely press ctrl-c to stop waiting - your restore will continue in the background.
...................
Restore completed with status: Completed. You may check for more information using the commands `velero restore describe drill-1` and `velero restore logs drill-1`.

$ kubectl -n course-dr-drill wait --for=condition=Ready cluster/orders-db --timeout=300s
cluster.postgresql.cnpg.io/orders-db condition met

$ kubectl -n course-dr-drill exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc "SELECT count(*), max(item) FROM orders"
500|book-99

$ kubectl -n course-dr exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc "SELECT count(*) FROM orders"
520

$ kubectl delete namespace course-dr-drill
namespace "course-dr-drill" deleted
```

**What you should see.** The drill database holds 500 orders and no `late-` ones (`max(item)` compares text, so `book-99` sorts last), while the original still holds 520. The backup works, and the 20 orders written after it are exactly the data a restore would lose: that gap is the RPO. `--namespace-mappings` is what makes a drill safe, because every object lands in `course-dr-drill` and nothing touches the running database.

### 6. The disaster: delete the namespace, then restore it

```console
$ date +%T
01:14:00

$ kubectl delete namespace course-dr
namespace "course-dr" deleted

$ kubectl get pvc -A | grep course-dr
No resources found

$ date +%T
01:14:10

$ kubectl -n velero exec $V -c velero -- /velero restore create orders-restore-1 --from-backup orders-1 --wait
Restore request "orders-restore-1" submitted successfully.
Waiting for restore to complete. You may safely press ctrl-c to stop waiting - your restore will continue in the background.
...................
Restore completed with status: Completed. You may check for more information using the commands `velero restore describe orders-restore-1` and `velero restore logs orders-restore-1`.

$ kubectl -n course-dr wait --for=condition=Ready cluster/orders-db --timeout=300s
cluster.postgresql.cnpg.io/orders-db condition met

$ date +%T
01:14:44

$ kubectl -n course-dr get cluster,pods
NAME                                   AGE   INSTANCES   READY   STATUS                     PRIMARY
cluster.postgresql.cnpg.io/orders-db   33s   1           1       Cluster in healthy state   orders-db-1

NAME              READY   STATUS    RESTARTS   AGE
pod/orders-db-1   1/1     Running   0          11s

$ kubectl -n course-dr exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc "SELECT count(*) FROM orders"
500

$ kubectl -n course-dr get events --sort-by=.lastTimestamp | grep -E 'restore-wait|Killing|Created container postgres' | tail -4
30s         Normal   Started                 pod/orders-db-1                         Started container restore-wait
14s         Normal   Created                 pod/orders-db-1                         Created container postgres
12s         Normal   Killing                 pod/orders-db-1                         Stopping container postgres
10s         Normal   Created                 pod/orders-db-1                         Created container postgres
```

**What you should see.** Deleting the namespace took the database, its volume and its claim with it, so no PVC is left anywhere. From the start of the restore to a healthy cluster took 34 seconds in the test run, the RTO of this small database, and the table holds the 500 orders of the backup. The events show the restore in order: Velero's `restore-wait` init container held the pod while the node agent wrote the files back, PostgreSQL started on them, and then the operator replaced the pod Velero had restored with one of its own, which found the same data on the volume.

## Tasks

Each task gives you a goal without the commands. `./lab.sh task setup` prepares it, you solve it in `./lab.sh shell`, and `./lab.sh task check` tells you what still fails. The solution sits under each task, and `./lab.sh task solve` runs it for you.

### Task 6.5.1: a nightly backup schedule

<!-- norun -->
```console
$ ./lab.sh task setup 6.5.1
== setup task 6.5.1
Installing the object store, CloudNativePG and Velero, if missing (about 3 minutes)
Velero runs and the orders database lives in course-dr. No schedule named orders-nightly exists.
```

> Create a Velero schedule named `orders-nightly` that backs up only the namespace `course-dr` every day at 02:00, copies its volumes with the file system backup, and keeps each backup for 7 days.

<details>
<summary>Solution</summary>

`velero schedule create` writes a Schedule resource, which Velero turns into a Backup at every cron time. `--ttl` sets how long each backup lives before Velero deletes it from the bucket.

<!-- norun -->
```console
$ kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero -o name)" -c velero -- /velero schedule create orders-nightly --schedule="0 2 * * *" --include-namespaces course-dr --ttl 168h --default-volumes-to-fs-backup
Schedule "orders-nightly" created successfully.
$ kubectl -n velero get schedules.velero.io orders-nightly
NAME             STATUS    SCHEDULE    LASTBACKUP   AGE   PAUSED
orders-nightly   Enabled   0 2 * * *                0s
```

</details>

<!-- norun -->
```console
$ ./lab.sh task check 6.5.1
== check task 6.5.1
  PASS  Schedule velero/orders-nightly exists
  PASS  it runs every day at 02:00
  PASS  it backs up only course-dr
  PASS  it keeps each backup for 7 days
  PASS  it copies volumes with the file system backup
  PASS  Velero accepted it (phase Enabled)
== task 6.5.1: 6 passed, 0 failed
```

### Task 6.5.2: a restore drill, and what it misses

<!-- norun -->
```console
$ ./lab.sh task setup 6.5.2
== setup task 6.5.2
Installing the object store, CloudNativePG and Velero, if missing (about 3 minutes)
The backup task-6-5-2 holds 600 orders. 7 more arrived after it.
Prove the backup works: restore it into course-dr-drill without touching course-dr (task 6.5.2).
```

> The backup `task-6-5-2` was taken a moment ago, and 7 more orders arrived after it. Restore it into the namespace `course-dr-drill` while `course-dr` keeps running untouched, and check that the drill database holds exactly the orders of the backup.

<details>
<summary>Solution</summary>

`--namespace-mappings` sends every object of the backup to the new namespace, so the drill never touches the running database. The drill holds the 600 orders of the backup; the 7 later ones are the data a real restore would lose.

<!-- norun -->
```console
$ kubectl -n velero exec "$(kubectl -n velero get pod -l name=velero -o name)" -c velero -- /velero restore create --from-backup task-6-5-2 --namespace-mappings course-dr:course-dr-drill --wait
Restore request "task-6-5-2-20261122012229" submitted successfully.
Waiting for restore to complete. You may safely press ctrl-c to stop waiting - your restore will continue in the background.
...................
Restore completed with status: Completed. You may check for more information using the commands `velero restore describe task-6-5-2-20261122012229` and `velero restore logs task-6-5-2-20261122012229`.
$ kubectl -n course-dr-drill wait --for=condition=Ready cluster/orders-db --timeout=300s
cluster.postgresql.cnpg.io/orders-db condition met
$ kubectl -n course-dr-drill exec orders-db-1 -c postgres -- psql -U postgres -d orders -tAc 'SELECT count(*) FROM orders'
600
```

</details>

<!-- norun -->
```console
$ ./lab.sh task check 6.5.2
== check task 6.5.2
  PASS  a restore from task-6-5-2 completed
  PASS  the drill database in course-dr-drill is healthy
  PASS  it holds the 600 orders of the backup (got 600)
  PASS  the original in course-dr still holds all 607 orders (got 607)
== task 6.5.2: 4 passed, 0 failed
```

## Investigate

1. In step 5 the drill copy held 500 orders and the original 520. What would you change so a deleted namespace loses at most 5 minutes of orders?
2. After the restore in step 6, CloudNativePG replaced the pod Velero had restored. Why, and is that a problem?
3. The backup holds the database's passwords in its Secrets. What does that mean for who may read the bucket?
4. Your team runs the restore drill once a quarter. What would you add so you learn about a broken backup within a day?

<details>
<summary>Answers</summary>

1. More frequent namespace backups don't scale down to minutes. Use the database's own continuous archiving: CloudNativePG's Barman plugin streams the write-ahead log to the bucket every few seconds or minutes, and a recovery replays it to any point in time. Velero then keeps carrying the Kubernetes objects.
2. Velero restored the pod as it was, with an owner reference to the old Cluster object's id, and an init container that waited for the files. The operator saw a pod it had not created for the new Cluster and replaced it with its own, which mounted the restored volume and found the data. Not a problem: the data lives on the volume, and the operator owns the pods.
3. The bucket holds everything needed to impersonate the app: passwords, certificates and service account tokens. Treat it like the secrets themselves: separate credentials for writing and restoring, encryption at rest, and no read access for the people who only need the app.
4. Automate the drill: a scheduled job that restores the latest backup into a scratch namespace, runs a query that checks the row count or the newest timestamp, records the duration, deletes the namespace, and alerts when any step fails. Velero's own metrics also show failed backups, which a Prometheus rule turns into a ticket.

</details>

## Clean up

```console
$ ./platform-engineering/reset.sh
Removing course rules from the shop namespace
Applying the baseline Istio config from manifests/istio
Turning off the backend experiment settings
Asking ArgoCD to sync istio-config from Git
Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules.
```

The reset deletes Velero's restores while Velero still runs, because each carries a finalizer that only Velero removes, then uninstalls Velero and CloudNativePG, deletes the namespaces `course-dr`, `course-dr-drill`, `course-backup`, `velero` and `cnpg-system`, and the CRDs that Helm leaves behind. The database's volume goes with its claim.
