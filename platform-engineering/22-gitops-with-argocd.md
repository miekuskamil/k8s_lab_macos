# Module 22: GitOps with ArgoCD

> New to a term here, like Application or sync wave? The [glossary](glossary.md) explains every term in this course.

**Before this module:** module 0. No Istio knowledge needed.

**You need:** the lab running (`./scripts/start.sh` starts or repairs it), `git`, and `./scripts/port-forward.sh` running in a spare terminal for the ArgoCD UI (http://localhost:8081). The lab's own Git server on http://localhost:3001 comes with the lab.

The whole lab runs on ArgoCD, and so far you've mostly worked around it, because `reset.sh` re-syncs it and the course warns you not to push in the middle of an exercise. In this module ArgoCD becomes the subject: you run your own Git server inside the cluster, deploy an app from it, and practise the tasks that come up in every platform team and every GitOps interview:

- drift, where the cluster no longer matches Git
- rollbacks
- ordered deploys with database migrations
- a project that limits what one team may deploy
- one template for many environments

Time: about 60 minutes.

## Concept: the reconcile loop

A change in Git does nothing on its own, and ArgoCD fixes that. It works like a thermostat: Git holds the setting you want, and ArgoCD keeps checking the cluster against it and corrects any difference, in a loop of four steps:

1. You push a commit to Git, which holds the desired state.
2. The repo-server fetches the commit and renders the manifests with Kustomize or Helm. It checks Git every 3 minutes, or at once on a webhook.
3. The application-controller compares the rendered manifests with the live state in the cluster.
4. When the two differ, the application-controller syncs, which means it runs the equivalent of `kubectl apply`.

The application-controller also watches the cluster, so it notices changes made there too.

![ArgoCD reconcile loop: git push, repo-server renders, application-controller compares and syncs](../docs/diagrams/chapters/22-reconcile-loop.svg)

For every Application, ArgoCD answers two separate questions, and its UI shows both:

| Status | Question | Values |
|---|---|---|
| **Sync** | Does the cluster match Git? | `Synced`, `OutOfSync` |
| **Health** | Does the app work? | `Healthy`, `Progressing`, `Degraded`, `Missing` |

The two are independent, so in step 5 you'll see an app that's `Synced` and `Degraded` at the same time, because the cluster matches Git exactly and Git describes something broken.

## Concept: what an Application and an AppProject say

An **Application** links one path in one Git repository to one namespace in one cluster, plus a sync policy:

| Setting | What it does |
|---|---|
| `automated` | Sync on its own when Git changes. Without it, ArgoCD only reports `OutOfSync` and waits for you. |
| `prune: true` | Delete resources that disappeared from Git. Without it, a deleted file leaves its resource running. |
| `selfHeal: true` | Undo changes made in the cluster, like a `kubectl edit`. Without it, drift shows as `OutOfSync` and stays. |
| finalizer `resources-finalizer.argocd.argoproj.io` | Deleting the Application also deletes everything it deployed. |

An **AppProject** sets the limits for a group of Applications by deciding three things:

- which repositories they read
- which namespaces they deploy to
- which kinds of resources they create

It's ArgoCD's version of RBAC, which a platform team uses to say "this team deploys its app, and nothing else".

## The bigger picture: why GitOps won

Before GitOps, a CI pipeline ran `kubectl apply` or `helm upgrade` at the end of a build, which has three problems:

- The pipeline holds cluster-admin credentials.
- Nobody knows whether the cluster still matches the last deploy.
- A manual hotfix at 3 a.m. stays in place without anyone noticing, until the next deploy overwrites it.

GitOps turns this around, because the cluster *pulls* its desired state from Git and an agent inside the cluster keeps comparing the two. This gives you three things:

- Git becomes the audit log, recording who changed what, when, and who reviewed it.
- A rollback becomes a `git revert`.
- The CI pipeline no longer needs any access to the cluster.

ArgoCD and Flux, both CNCF graduated projects, are the two common agents, and Danish and UK job adverts for platform roles name ArgoCD more often than any other deployment tool.

## Why this way

**Why a Git server inside the cluster?** The lab's own ArgoCD reads the course repository on GitHub, so exercises there would mean commits to GitHub, and a push to GitHub also resyncs `istio-config`, which wipes whatever module you're in. Gitea is a small Git server that gives you a private repository in seconds, and ArgoCD reads it over the cluster network like any other Git host.

**Why a new AppProject instead of the lab's `k8s-lab` project?** `k8s-lab` allows everything, because it deploys Istio, CRDs and cluster-wide RBAC, while a team's app deserves the opposite: one repository, its own namespaces, no cluster-scoped resources. Step 7 shows the difference.

**Why Kustomize overlays for dev and prod?** One base holds the app, and each environment changes only what differs, here the number of replicas, and ArgoCD renders Kustomize by itself, with no plugin.

**Why `progressDeadlineSeconds: 60` in the Deployment?** A stuck rollout turns `Degraded` only after this deadline, which is 10 minutes by default, so one minute keeps step 5 short. Production teams often lower it too, so broken releases show up sooner.

## Do it

### 1. Start a Git server

```console
$ kubectl apply -f platform-engineering/manifests/22-gitea.yaml
namespace/course-gitops created
namespace/course-gitops-dev created
namespace/course-gitops-prod created
deployment.apps/gitea created
service/gitea created

$ kubectl -n course-gitops rollout status deploy/gitea
Waiting for deployment "gitea" rollout to finish: 0 of 1 updated replicas are available...
deployment "gitea" successfully rolled out

$ kubectl -n course-gitops exec deploy/gitea -- gitea admin user create --username lab \
  --password lab-gitops-pass --email lab@example.invalid --admin --must-change-password=false
New user 'lab' has been successfully created!

$ kubectl -n course-gitops port-forward svc/gitea 3001:3000 >/dev/null 2>&1 &
```

**What you should see.** The last command prints `New user 'lab' has been successfully created!`, and Gitea now answers on http://localhost:3001, where you sign in as `lab` with the password `lab-gitops-pass` to browse it. The manifest also creates the namespaces `course-gitops-dev` and `course-gitops-prod`, because the project from step 2 won't allow ArgoCD to create namespaces.

### 2. Push an app and let ArgoCD deploy it

Run this from the lab's folder, where `C` remembers the location for later copy commands.

```console
$ C=$PWD
$ cp -R platform-engineering/gitops-repo /tmp/podinfo-gitops && cd /tmp/podinfo-gitops
$ git init -q -b main && git add . && git commit -qm "podinfo, dev and prod"
$ git push http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
Enumerating objects: 11, done.
Counting objects: 100% (11/11), done.
Delta compression using up to 15 threads
Compressing objects: 100% (7/7), done.
Writing objects: 100% (11/11), 1.19 KiB | 1.19 MiB/s, done.
Total 11 (delta 0), reused 0 (delta 0), pack-reused 0 (from 0)
remote: . Processing 1 references
remote: Processed 1 references in total
To http://localhost:3001/lab/podinfo-gitops.git
 * [new branch]      main -> main

$ cd -
/Users/you/k8s_lab_macos

$ kubectl apply -f platform-engineering/manifests/22-project.yaml -f platform-engineering/manifests/22-app-dev.yaml
appproject.argoproj.io/team-shop created
Warning: metadata.finalizers: "resources-finalizer.argocd.argoproj.io": prefer a domain-qualified finalizer name to avoid accidental conflicts with other finalizer writers
application.argoproj.io/podinfo-dev created

$ kubectl -n argocd get app podinfo-dev -w        # Ctrl-C at Synced Healthy
NAME          SYNC STATUS   HEALTH STATUS
podinfo-dev   Synced        Healthy

$ kubectl -n course-gitops-dev get pods
NAME                     READY   STATUS    RESTARTS   AGE
podinfo-6cff6cdd-n9nrs   1/1     Running   0          9s
```

The `-w` watch keeps running until you press Ctrl-C, and the transcript shows it up to `Synced Healthy`.

The repository holds [podinfo](https://github.com/stefanprodan/podinfo), a tiny web app made for GitOps demos, as a Kustomize base with two overlays, `envs/dev` and `envs/prod`, and Gitea creates the repository on the first push.

**What you should see.** The app turns `Synced Healthy` within about 10 seconds, with one `podinfo` pod running in `course-gitops-dev`. Open ArgoCD (http://localhost:8081, `admin` / `k8s-lab-admin`) and click `podinfo-dev`, and you see a tree of the Service, the Deployment, its ReplicaSet and its pod.

### Concept: how ArgoCD spots a difference

ArgoCD compares the cluster with Git, but it learns about changes on each side in a different way, which is why step 3 reacts in seconds and step 4 takes minutes:

| Side | How ArgoCD learns about a change | Typical delay |
|---|---|---|
| Live state, in the cluster | The application-controller watches every resource it manages, like any Kubernetes controller. A change to one of them starts a new comparison. | seconds |
| Desired state, in Git | Git sends nothing by itself. ArgoCD fetches it on each reconcile, every 3 minutes plus some jitter, or at once on a refresh or webhook. | up to about 3 minutes |

ArgoCD compares each rendered manifest with its live object and checks only the fields your manifests set, so fields the cluster fills in by itself, such as `status`, `uid` or a default from the API server, don't count as drift. That's why `kubectl scale` makes the app `OutOfSync`, because `replicas` sits in Git, while a pod that restarts doesn't.

A common mistake puts `replicas` in Git and also attaches an HPA, the autoscaler that changes the replica count, so with self-heal on, ArgoCD and the HPA keep undoing each other's changes. Leave the field out of Git, or tell ArgoCD to skip it with `ignoreDifferences`.

### 3. Drift, with and without self-heal

```console
$ kubectl -n course-gitops-dev scale deploy/podinfo --replicas=3
deployment.apps/podinfo scaled

$ sleep 20; kubectl -n argocd get app podinfo-dev
NAME          SYNC STATUS   HEALTH STATUS
podinfo-dev   OutOfSync     Healthy

$ kubectl -n course-gitops-dev get deploy podinfo
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
podinfo   3/3     3            3           38s

$ kubectl -n argocd patch app podinfo-dev --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
application.argoproj.io/podinfo-dev patched

$ kubectl -n course-gitops-dev get deploy podinfo -w     # Ctrl-C when it's back to 1
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
podinfo   1/1     1            1           46s

$ kubectl -n course-gitops-dev scale deploy/podinfo --replicas=3
deployment.apps/podinfo scaled

$ kubectl -n course-gitops-dev get deploy podinfo
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
podinfo   1/1     1            1           56s
```

The `-w` watch keeps running until you press Ctrl-C, and the transcript shows it until the Deployment was back to 1 replica.

**What you should see.** First the app shows `OutOfSync Healthy` and the 3 replicas stay, because ArgoCD noticed the drift but only reported it. After the patch, the Deployment drops back to 1 replica within 2 seconds, and ArgoCD undoes the second `kubectl scale` just as fast, so in the test run only 1 replica was left by the time the next command ran.

### 4. Ship a change through Git

```console
$ cd /tmp/podinfo-gitops
$ sed -i.bak 's/hello from git/hello from commit 2/' base/deployment.yaml
$ git commit -qam "new message" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
remote: . Processing 1 references
remote: Processed 1 references in total

$ cd -
/Users/you/k8s_lab_macos

$ kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.sync.revision}{"\n"}' -w
fdfebead6040fa5222c9ed4903650ae981e4c358
fdfebead6040fa5222c9ed4903650ae981e4c358
0bea22f49baffa173b568d9892093b2b148ee2b8
0bea22f49baffa173b568d9892093b2b148ee2b8
...
```

The `-w` watch keeps running until you press Ctrl-C, and the transcript shows it until the new commit appeared.

`sed -i.bak` edits the file in place on both macOS and Linux and keeps the old version as `deployment.yaml.bak`, while `git commit -a` commits only files Git already tracks, so the `.bak` files stay out of the repository.

Wait, then make a second change, and this time tell ArgoCD to look right away:

```console
$ cd /tmp/podinfo-gitops
$ sed -i.bak 's/hello from commit 2/hello from commit 3/' base/deployment.yaml
$ git commit -qam "message 3" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
remote: . Processing 1 references
remote: Processed 1 references in total

$ cd -
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ kubectl -n course-gitops-dev rollout status deploy/podinfo
deployment "podinfo" successfully rolled out

$ kubectl -n course-gitops-dev exec deploy/podinfo -- wget -qO- localhost:9898 | grep message
  "message": "hello from commit 3",
```

**What you should see.** In the test run the first commit took 228 seconds to appear, because ArgoCD polls Git every 3 minutes plus some random jitter, while with the annotation the second commit took 1 second and the pod then answers `"message": "hello from commit 3"`. In production a Git webhook does the same job as the annotation, because GitHub or GitLab calls ArgoCD on every push.

### 5. A bad release, and `git revert`

```console
$ cd /tmp/podinfo-gitops
$ sed -i.bak 's/podinfo:6.7.1/podinfo:6.7.99/' base/deployment.yaml
$ git commit -qam "bump podinfo" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
remote: . Processing 1 references
remote: Processed 1 references in total

$ cd -
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ kubectl -n argocd get app podinfo-dev -w           # Ctrl-C at Degraded, after about a minute
NAME          SYNC STATUS   HEALTH STATUS
podinfo-dev   Synced        Progressing
podinfo-dev   Synced        Degraded

$ kubectl -n course-gitops-dev get pods
NAME                       READY   STATUS             RESTARTS   AGE
podinfo-545b74bb5-n2hl8    0/1     ImagePullBackOff   0          64s
podinfo-7f68644c46-9ctxr   1/1     Running            0          72s
```

The `-w` watch keeps running until you press Ctrl-C, and the transcript shows it up to `Degraded`.

**What you should see.** In the test runs the app showed `Synced Degraded` after 56 to 61 seconds, with two pods:

- The new pod sits in `ErrImagePull` or `ImagePullBackOff`, because tag 6.7.99 doesn't exist.
- The old pod stays `Running` and serves traffic.

A rolling update never removes the old pod before the new one turns ready, so users noticed nothing, and ArgoCD's resource list explains the health status: `Deployment "podinfo" exceeded its progress deadline`.

Roll back the GitOps way:

```console
$ cd /tmp/podinfo-gitops
$ git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
[main e0a5717] Revert "bump podinfo"
 1 file changed, 1 insertion(+), 1 deletion(-)
remote: . Processing 1 references
remote: Processed 1 references in total

$ git log --oneline -3
e0a5717 (HEAD -> main) Revert "bump podinfo"
32948fb bump podinfo
6dc4465 message 3

$ cd -
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ kubectl -n argocd get app podinfo-dev
NAME          SYNC STATUS   HEALTH STATUS
podinfo-dev   Synced        Healthy

$ kubectl -n course-gitops-dev get pods
NAME                       READY   STATUS    RESTARTS   AGE
podinfo-7f68644c46-9ctxr   1/1     Running   0          80s
```

**What you should see.** Within seconds the app turns `Synced Healthy` and the broken pod goes away, while `git log` shows the bad commit and its revert, both with your name. ArgoCD's UI also has a History and Rollback button, but it works only with automated sync turned off, and afterwards Git says something different from the cluster, whereas a revert keeps Git the single source of truth.

### 6. Ordered deploys: hooks and waves

```console
$ cat platform-engineering/gitops-extras/migrate-job.yaml platform-engineering/gitops-extras/config-wave.yaml
# A PreSync hook: ArgoCD runs this Job before it applies anything else, and waits for it.
# A failing hook stops the sync, which is what you want from a database migration.
apiVersion: batch/v1
kind: Job
metadata:
  name: migrate
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: busybox:1.36
          command: ["sh", "-c", "echo migrating the schema; sleep 10; echo done"]
# Sync wave -1: ArgoCD applies this before the Deployment (wave 0) and waits until it's healthy.
apiVersion: v1
kind: ConfigMap
metadata:
  name: podinfo-settings
  annotations:
    argocd.argoproj.io/sync-wave: "-1"
data:
  feature: "orders-v2"

$ cd /tmp/podinfo-gitops
$ cp "$C"/platform-engineering/gitops-extras/{migrate-job,config-wave}.yaml base/
$ printf '  - migrate-job.yaml\n  - config-wave.yaml\n' >> base/kustomization.yaml
$ git add . && git commit -qm "migration hook and settings" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
remote: . Processing 1 references
remote: Processed 1 references in total

$ cd -
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ for i in $(seq 1 8); do kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase}: {.status.operationState.message}{"\n"}'; sleep 3; done
Running: waiting for completion of hook batch/Job/migrate
Running: waiting for completion of hook batch/Job/migrate
Running: waiting for completion of hook batch/Job/migrate
Succeeded: successfully synced (all tasks run)
Succeeded: successfully synced (all tasks run)
Succeeded: successfully synced (all tasks run)
Succeeded: successfully synced (all tasks run)
Succeeded: successfully synced (all tasks run)

$ kubectl -n course-gitops-dev logs job/migrate
migrating the schema
done
```

**What you should see.** The sync status moves through three messages:

1. `Running: waiting for completion of hook batch/Job/migrate`, for about 15 seconds
2. `waiting for healthy state of ...`
3. `Succeeded`

The Job printed `migrating the schema` and `done`, and ArgoCD applied the resources in this order:

1. the PreSync hook
2. the ConfigMap in wave `-1`
3. everything in wave 0

This order matters for database migrations, because the new app version needs the new schema and so must not start before the migration finishes. ArgoCD offers two tools for ordering:

- A **hook** runs at a set phase of the sync: PreSync, Sync, PostSync or SyncFail. The migration Job here is a PreSync hook.
- A **wave** orders normal resources: ArgoCD applies one wave, waits until it turns healthy, and then moves to the next.

Now make the migration fail:

```console
$ cd /tmp/podinfo-gitops
$ sed -i.bak 's/echo done"/echo schema conflict; exit 1"/' base/migrate-job.yaml
$ sed -i.bak 's/hello from commit 3/hello from commit 5/' base/deployment.yaml
$ git commit -qam "migration that fails" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
remote: . Processing 1 references
remote: Processed 1 references in total

$ cd -
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ sleep 40; kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.message}{"\n"}'
one or more synchronization tasks completed unsuccessfully. Retrying attempt #2 at 10:26AM.

$ kubectl -n course-gitops-dev get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].env[0].value}{"\n"}'
hello from commit 3
```

**What you should see.** The message reads `one or more synchronization tasks completed unsuccessfully. Retrying attempt #...`, while the Deployment still says `hello from commit 3`, because the failed migration stopped the release before the new version went out, which is exactly what you want from a schema migration.

Undo it, and watch how long the fix waits:

```console
$ cd /tmp/podinfo-gitops && git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main; cd -
[main 9c7004c] Revert "migration that fails"
 2 files changed, 2 insertions(+), 2 deletions(-)
remote: . Processing 1 references
remote: Processed 1 references in total
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase} retry {.status.operationState.retryCount}{"\n"}' -w
Running retry 2
Running retry 3
```

The `-w` watch keeps running until you press Ctrl-C, and the transcript shows its first 30 seconds.

**What you should see.** The operation stays `Running` for a few minutes before your revert takes effect, and the next section explains why and how to skip the wait.

### Concept: a sync is an operation with a fixed revision

ArgoCD finishes or gives up on one sync before it starts the next, because a sync isn't a loop that always applies the newest commit. Instead, ArgoCD writes an **operation** into the Application's `status.operationState`, recording the Git revision to apply and how far the sync got, and that revision stays fixed until the operation ends. When an automated sync fails, ArgoCD retries the same operation with the same old commit and waits longer before each attempt, so your revert lands in Git while ArgoCD starts no new sync. In the diagram, commit B fails and retries, and commit C waits until the retries run out or you terminate the operation.

![A failing sync operation retries commit B while the revert in commit C waits](../docs/diagrams/chapters/22-sync-operation.svg)

Plain Kubernetes has no such queue, because a Deployment controller always works toward the newest spec, while with ArgoCD a failing operation blocks your fix from reaching the cluster. Step 7 shows how to end it.

### 7. Guardrails, and the retry trap

A teammate commits a ClusterRole that reads every resource in the cluster:

```console
$ cat platform-engineering/gitops-extras/sneaky-clusterrole.yaml
# Someone on the team commits this. The AppProject allows no cluster-scoped resources.
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: podinfo-reads-everything
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["get", "list"]

$ cd /tmp/podinfo-gitops
$ cp "$C"/platform-engineering/gitops-extras/sneaky-clusterrole.yaml base/
$ printf '  - sneaky-clusterrole.yaml\n' >> base/kustomization.yaml
$ git add . && git commit -qm "let podinfo read everything" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
remote: . Processing 1 references
remote: Processed 1 references in total

$ cd -
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ sleep 10
$ kubectl -n argocd get app podinfo-dev -o jsonpath='{range .status.operationState.syncResult.resources[?(@.kind=="ClusterRole")]}{.message}{"\n"}{end}'
resource rbac.authorization.k8s.io:ClusterRole is not permitted in project team-shop

$ kubectl get clusterrole podinfo-reads-everything
Error from server (NotFound): clusterroles.rbac.authorization.k8s.io "podinfo-reads-everything" not found
```

**What you should see.** The first command prints `resource rbac.authorization.k8s.io:ClusterRole is not permitted in project team-shop`, and the second prints `NotFound` for the ClusterRole, because ArgoCD refused the whole sync, so nothing from that commit reached the cluster.

Revert it, and look at the operation:

```console
$ cd /tmp/podinfo-gitops && git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main; cd -
[main d3a79ac] Revert "let podinfo read everything"
 3 files changed, 28 deletions(-)
 delete mode 100644 base/migrate-job.yaml.bak
 delete mode 100644 base/sneaky-clusterrole.yaml
remote: . Processing 1 references
remote: Processed 1 references in total
/Users/you/k8s_lab_macos

$ kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
application.argoproj.io/podinfo-dev annotated

$ kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase}: {.status.operationState.message}{"\n"}'
Running: one or more synchronization tasks are not valid. Retrying attempt #2 at 10:32AM.
```

**What you should see.** The operation still shows `Running` and `Retrying attempt #...` for the *old* commit, because an automated sync that fails retries up to 5 times, with a longer pause each time. In the test run the failing operation kept retrying from 20:48:15 to 20:53:25, and a revert pushed in the middle took effect only after that. During an incident you don't have those 5 minutes, so stop the retries yourself:

```console
$ kubectl -n argocd patch app podinfo-dev --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}'
application.argoproj.io/podinfo-dev patched

$ kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.sync.status} {.status.health.status}: {.status.operationState.message}{"\n"}'
Synced Healthy: Operation terminated (retried 2 times).
```

**What you should see.** Within a second the command prints `Synced Healthy: Operation terminated (retried 2 times).`. With the `argocd` CLI, `argocd app terminate-op podinfo-dev` does the same thing, and the UI also has a Terminate button on a running sync.

### 8. One template, many environments

```console
$ kubectl -n argocd delete app podinfo-dev
application.argoproj.io "podinfo-dev" deleted

$ kubectl -n course-gitops-dev get all
No resources found in course-gitops-dev namespace.

$ kubectl apply -f platform-engineering/manifests/22-appset.yaml
applicationset.argoproj.io/podinfo created

$ sleep 20; kubectl -n argocd get app podinfo-dev podinfo-prod
NAME           SYNC STATUS   HEALTH STATUS
podinfo-dev    Synced        Healthy
podinfo-prod   Synced        Healthy

$ kubectl get deploy -A | grep course-gitops-
course-gitops-dev    podinfo                                    1/1     1            1           13s
course-gitops-prod   podinfo                                    2/2     2            2           13s

$ kubectl -n argocd get app podinfo-prod -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
ApplicationSet/podinfo
```

**What you should see.** Deleting the Application removed its Deployment, Service and pods, because of the finalizer. Next, the ApplicationSet, a template that generates Applications, created `podinfo-dev` and `podinfo-prod`, which were both `Synced Healthy` within about 20 seconds. The overlays give dev 1 replica and prod 2, and both Applications carry an owner reference to `ApplicationSet/podinfo`.

Delete one and see what happens, then remove a file from Git:

```console
$ kubectl -n argocd delete app podinfo-prod
application.argoproj.io "podinfo-prod" deleted

$ sleep 20; kubectl -n argocd get app podinfo-prod
NAME           SYNC STATUS   HEALTH STATUS
podinfo-prod   Synced        Healthy

$ cd /tmp/podinfo-gitops
$ git rm -q base/config-wave.yaml && sed -i.bak '/config-wave.yaml/d' base/kustomization.yaml
$ git commit -qam "drop the settings ConfigMap" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
remote: . Processing 1 references
remote: Processed 1 references in total

$ cd -
/Users/you/k8s_lab_macos

$ for a in dev prod; do kubectl -n argocd annotate app podinfo-$a argocd.argoproj.io/refresh=normal --overwrite; done
application.argoproj.io/podinfo-dev annotated
application.argoproj.io/podinfo-prod annotated

$ sleep 25; kubectl get cm -A | grep podinfo-settings
```

**What you should see.** About 20 seconds later `podinfo-prod` is back and `Healthy`, because the ApplicationSet owns it and so recreates it. `grep` finds no `podinfo-settings` ConfigMap, because the file left Git and `prune: true` deleted the ConfigMap from both namespaces.

A generator is the part of an ApplicationSet that produces the list of Applications. This module uses the list generator, the simplest one, while other generators create Applications from other sources:

- The `git` generator creates one for every folder in a repository.
- The `cluster` generator creates one for every cluster ArgoCD knows.
- The `pullRequest` generator creates one for every open pull request, which gives each PR its own preview environment.

## Investigate

1. Your team turned on `selfHeal`. During an incident, an engineer scales a Deployment from 3 to 10 replicas with `kubectl`, and it drops back to 3 a second later. What are the two right ways to scale up, and which one fits an incident at 3 a.m.?
2. Step 5 showed `Synced` and `Degraded` together. Which alert would you build on ArgoCD's status, and why not alert on `OutOfSync`?
3. A developer asks for a PreSync hook that runs `kubectl delete` on old resources. What's the problem, and what does ArgoCD offer instead?
4. Your ApplicationSet generates 40 Applications from a `git` generator, one per folder. Someone deletes a folder by mistake. What happens, and which setting protects you?

<details>
<summary>Answers</summary>

1. There are two right ways.
   - Change `replicas` in Git and push, which keeps Git the truth, and add a refresh annotation or use a webhook so the change applies in seconds.
   - When Git is slow to change, for example because of review rules or a broken pipeline, turn off `selfHeal` for that Application first and scale by hand, then open a follow-up task to put the number in Git.

   At 3 a.m. the Git path is the right default when a push and a refresh take a minute, because nothing drifts and nothing needs cleaning up later. If pushing to Git is blocked, turning off `selfHeal` and scaling by hand is the faster fix, and the follow-up task keeps Git from overwriting your fix at the next sync.

   Many teams also let an HPA own the replica count and leave `replicas` out of Git altogether, so autoscaling never fights ArgoCD.
2. Alert on health, firing when an Application stays `Degraded` or `Progressing` for longer than its rollout normally takes. ArgoCD exports the metric `argocd_app_info` for Prometheus, with `health_status` and `sync_status` labels. `OutOfSync` happens for a few seconds on every push, and with `selfHeal` off it's often intended, so an `OutOfSync` alert is noisy: a short `OutOfSync` is normal, while a long `Degraded` is an outage.
3. The hook needs credentials to delete things, and it deletes outside ArgoCD's view, so nothing tracks what happened. ArgoCD already removes resources that leave Git, with `prune: true`, and the annotation `argocd.argoproj.io/sync-options: Prune=false` protects single resources from pruning. Use waves and hooks for ordering, and prune for clean-up.
4. The `git` generator stops producing that Application, so the ApplicationSet deletes it, and because of the resources finalizer, everything in that folder's namespace goes too. Two settings on the ApplicationSet protect you:
   - `syncPolicy.preserveResourcesOnDeletion: true` keeps the workloads when an Application disappears.
   - `applicationsSync: create-update` stops the ApplicationSet from deleting Applications at all.

</details>

## Clean up

```console
$ ./platform-engineering/reset.sh
Removing course rules from the shop namespace
Applying the baseline Istio config from manifests/istio
Turning off the backend experiment settings
Asking ArgoCD to sync istio-config from Git
Done. Baseline: 100% of backend traffic to v1, no faults, no extra rules.

$ kill %1 2>/dev/null; rm -rf /tmp/podinfo-gitops
```

This deletes:

- the ApplicationSet and its Applications
- the podinfo deployments, through the Applications' finalizers
- the `team-shop` project
- Gitea
- the three `course-gitops` namespaces
