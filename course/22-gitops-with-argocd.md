# Module 22: GitOps with ArgoCD

> New to a term here, like Application or sync wave? The [glossary](glossary.md) explains every term in this course.

**Before this module:** module 0. No Istio knowledge needed.

The whole lab runs on ArgoCD, and so far you've mostly worked around it. `reset.sh` re-syncs it, and the course warns you not to push in the middle of an exercise. In this module, ArgoCD is the subject. You run your own Git server inside the cluster and deploy an app from it. Then you practise the tasks that come up in every platform team and every GitOps interview:

- drift, where the cluster no longer matches Git
- rollbacks
- ordered deploys with database migrations
- a project that limits what one team may deploy
- one template for many environments

Time: about 60 minutes.

## Concept: the reconcile loop

A change in Git does nothing on its own. ArgoCD fixes that. It works like a thermostat: Git holds the setting you want, and ArgoCD keeps checking the cluster against it and corrects any difference. The diagram shows the loop in four steps:

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

They're independent. In step 5 you'll see an app that's `Synced` and `Degraded` at the same time: the cluster matches Git exactly, and Git describes something broken.

## Concept: what an Application and an AppProject say

An **Application** links one path in one Git repository to one namespace in one cluster, plus a sync policy:

| Setting | What it does |
|---|---|
| `automated` | Sync on its own when Git changes. Without it, ArgoCD only reports `OutOfSync` and waits for you. |
| `prune: true` | Delete resources that disappeared from Git. Without it, a deleted file leaves its resource running. |
| `selfHeal: true` | Undo changes made in the cluster, like a `kubectl edit`. Without it, drift shows as `OutOfSync` and stays. |
| finalizer `resources-finalizer.argocd.argoproj.io` | Deleting the Application also deletes everything it deployed. |

An **AppProject** sets the limits for a group of Applications. It decides three things:

- which repositories they read
- which namespaces they deploy to
- which kinds of resources they create

It's ArgoCD's version of RBAC. A platform team uses it to say "this team deploys its app, and nothing else".

## The bigger picture: why GitOps won

Before GitOps, a CI pipeline ran `kubectl apply` or `helm upgrade` at the end of a build. This approach has three problems:

- The pipeline holds cluster-admin credentials.
- Nobody knows whether the cluster still matches the last deploy.
- A manual hotfix at 3 a.m. stays in place without anyone noticing, until the next deploy overwrites it.

GitOps turns this around. The cluster *pulls* its desired state from Git, and an agent inside the cluster keeps comparing the two. This gives you three things:

- Git becomes the audit log. It records who changed what, when, and who reviewed it.
- A rollback becomes a `git revert`.
- The CI pipeline no longer needs any access to the cluster.

ArgoCD and Flux, both CNCF graduated projects, are the two common agents. Danish and UK job adverts for platform roles name ArgoCD more often than any other deployment tool.

## Why this way

**Why a Git server inside the cluster?** The lab's own ArgoCD reads the course repository on GitHub. Exercises there would mean commits to GitHub. A push to GitHub also resyncs `istio-config`, and that wipes whatever module you're in. Gitea is a small Git server. It gives you a private repository in seconds, and ArgoCD reads it over the cluster network like any other Git host.

**Why a new AppProject instead of the lab's `k8s-lab` project?** `k8s-lab` allows everything, because it deploys Istio, CRDs and cluster-wide RBAC. A team's app deserves the opposite: one repository, its own namespaces, no cluster-scoped resources. Step 7 shows the difference.

**Why Kustomize overlays for dev and prod?** One base holds the app, and each environment changes only what differs, here the number of replicas. ArgoCD renders Kustomize by itself, with no plugin.

**Why `progressDeadlineSeconds: 60` in the Deployment?** A stuck rollout turns `Degraded` only after this deadline, which is 10 minutes by default. One minute keeps step 5 short. Production teams often lower it too, so broken releases show up sooner.

## Do it

### 1. Start a Git server

```bash
kubectl apply -f course/manifests/22-gitea.yaml
kubectl -n course-gitops rollout status deploy/gitea
kubectl -n course-gitops exec deploy/gitea -- gitea admin user create --username lab \
  --password lab-gitops-pass --email lab@example.invalid --admin --must-change-password=false
kubectl -n course-gitops port-forward svc/gitea 3001:3000 >/dev/null 2>&1 &
```

**What you should see.** The last command prints `New user 'lab' has been successfully created!`. Gitea now answers on http://localhost:3001. To browse it, sign in as `lab` with the password `lab-gitops-pass`. The manifest also creates the namespaces `course-gitops-dev` and `course-gitops-prod`. It does this because the project from step 2 won't allow ArgoCD to create namespaces.

### 2. Push an app and let ArgoCD deploy it

Run this from the lab's folder. `C` remembers where it is, for later copy commands.

```bash
C=$PWD
cp -R course/gitops-repo /tmp/podinfo-gitops && cd /tmp/podinfo-gitops
git init -q -b main && git add . && git commit -qm "podinfo, dev and prod"
git push http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
kubectl apply -f course/manifests/22-project.yaml -f course/manifests/22-app-dev.yaml
kubectl -n argocd get app podinfo-dev -w        # Ctrl-C at Synced Healthy
kubectl -n course-gitops-dev get pods
```

The repository holds [podinfo](https://github.com/stefanprodan/podinfo), a tiny web app made for GitOps demos, as a Kustomize base with two overlays, `envs/dev` and `envs/prod`. Gitea creates the repository on the first push.

**What you should see.** The app turns `Synced Healthy` within about 10 seconds, and one `podinfo` pod runs in `course-gitops-dev`. Open ArgoCD (http://localhost:8081, `admin` / `k8s-lab-admin`) and click `podinfo-dev`. You see a tree of the Service, the Deployment, its ReplicaSet and its pod.

### Concept: how ArgoCD spots a difference

ArgoCD compares two sides: the cluster and Git. It learns about changes on each side in a different way. That's why step 3 reacts in seconds and step 4 takes minutes.

| Side | How ArgoCD learns about a change | Typical delay |
|---|---|---|
| Live state, in the cluster | The application-controller watches every resource it manages, like any Kubernetes controller. A change to one of them starts a new comparison. | seconds |
| Desired state, in Git | Git sends nothing by itself. ArgoCD fetches it on each reconcile, every 3 minutes plus some jitter, or at once on a refresh or webhook. | up to about 3 minutes |

ArgoCD compares each rendered manifest with its live object. It checks only the fields your manifests set. The cluster fills in some fields by itself, such as `status`, `uid` or a default from the API server. These fields don't count as drift. So `kubectl scale` makes the app `OutOfSync`, because `replicas` sits in Git. A pod that restarts doesn't make it `OutOfSync`.

A common mistake is to put `replicas` in Git and also attach an HPA, the autoscaler that changes the replica count. With self-heal on, ArgoCD and the HPA then keep undoing each other's changes. Leave the field out of Git, or tell ArgoCD to skip it with `ignoreDifferences`.

### 3. Drift, with and without self-heal

```bash
kubectl -n course-gitops-dev scale deploy/podinfo --replicas=3
sleep 20; kubectl -n argocd get app podinfo-dev
kubectl -n course-gitops-dev get deploy podinfo
kubectl -n argocd patch app podinfo-dev --type merge -p '{"spec":{"syncPolicy":{"automated":{"selfHeal":true}}}}'
kubectl -n course-gitops-dev get deploy podinfo -w     # Ctrl-C when it's back to 1
kubectl -n course-gitops-dev scale deploy/podinfo --replicas=3
kubectl -n course-gitops-dev get deploy podinfo
```

**What you should see.** First the app shows `OutOfSync Healthy`, and the 3 replicas stay. ArgoCD noticed the drift but only reported it. After the patch, the Deployment drops back to 1 replica within 2 seconds. ArgoCD undoes the second `kubectl scale` just as fast. In the test run, only 1 replica was left by the time the next command ran.

### 4. Ship a change through Git

```bash
cd /tmp/podinfo-gitops
sed -i '' 's/hello from git/hello from commit 2/' base/deployment.yaml      # on Linux: sed -i
git commit -qam "new message" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.sync.revision}{"\n"}' -w
```

Wait. Then make a second change, and this time tell ArgoCD to look right away:

```bash
cd /tmp/podinfo-gitops
sed -i '' 's/hello from commit 2/hello from commit 3/' base/deployment.yaml
git commit -qam "message 3" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
kubectl -n course-gitops-dev rollout status deploy/podinfo
kubectl -n course-gitops-dev exec deploy/podinfo -- wget -qO- localhost:9898 | grep message
```

**What you should see.** In the test run, the first commit took 228 seconds to appear. That's because ArgoCD polls Git every 3 minutes, plus some random jitter. With the annotation, the second commit took 1 second. The pod then answers `"message": "hello from commit 3"`. In production, a Git webhook does the same job as the annotation. GitHub or GitLab calls ArgoCD on every push.

### 5. A bad release, and `git revert`

```bash
cd /tmp/podinfo-gitops
sed -i '' 's/podinfo:6.7.1/podinfo:6.7.99/' base/deployment.yaml
git commit -qam "bump podinfo" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get app podinfo-dev -w           # Ctrl-C at Degraded, after about a minute
kubectl -n course-gitops-dev get pods
```

**What you should see.** In the test run, the app showed `Synced Degraded` after 61 seconds. There are two pods:

- The new pod is in `ErrImagePull`, because tag 6.7.99 doesn't exist.
- The old pod is still `Running` and serving traffic.

A rolling update never removes the old pod before the new one is ready, so users noticed nothing. ArgoCD's resource list explains the health status: `Deployment "podinfo" exceeded its progress deadline`.

Roll back the GitOps way:

```bash
cd /tmp/podinfo-gitops
git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
git log --oneline -3
cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get app podinfo-dev
kubectl -n course-gitops-dev get pods
```

**What you should see.** Within seconds the app is `Synced Healthy` and the broken pod is gone. `git log` shows the bad commit and its revert, both with your name. ArgoCD's UI also has a History and Rollback button. It only works with automated sync turned off, and afterwards Git says something different from the cluster. A revert keeps Git the single source of truth.

### 6. Ordered deploys: hooks and waves

```bash
cat course/gitops-extras/migrate-job.yaml course/gitops-extras/config-wave.yaml
cd /tmp/podinfo-gitops
cp "$C"/course/gitops-extras/{migrate-job,config-wave}.yaml base/
printf '  - migrate-job.yaml\n  - config-wave.yaml\n' >> base/kustomization.yaml
git add . && git commit -qm "migration hook and settings" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
for i in $(seq 1 8); do kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase}: {.status.operationState.message}{"\n"}'; sleep 3; done
kubectl -n course-gitops-dev logs job/migrate
```

**What you should see.** The sync status moves through three messages:

1. `Running: waiting for completion of hook batch/Job/migrate`, for about 15 seconds
2. `waiting for healthy state of ...`
3. `Succeeded`

The Job printed `migrating the schema` and `done`. ArgoCD applied the resources in this order:

1. the PreSync hook
2. the ConfigMap in wave `-1`
3. everything in wave 0

This order matters for database migrations. The new app version needs the new schema, so it must not start before the migration finishes. ArgoCD offers two tools for ordering:

- A **hook** runs at a set phase of the sync: PreSync, Sync, PostSync or SyncFail. The migration Job here is a PreSync hook.
- A **wave** orders normal resources. ArgoCD applies one wave, waits until it's healthy, and then moves to the next.

Now make the migration fail:

```bash
cd /tmp/podinfo-gitops
sed -i '' 's/echo done"/echo schema conflict; exit 1"/' base/migrate-job.yaml
sed -i '' 's/hello from commit 3/hello from commit 5/' base/deployment.yaml
git commit -qam "migration that fails" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
sleep 40; kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.message}{"\n"}'
kubectl -n course-gitops-dev get deploy podinfo -o jsonpath='{.spec.template.spec.containers[0].env[0].value}{"\n"}'
```

**What you should see.** The message reads `one or more synchronization tasks completed unsuccessfully. Retrying attempt #...`, and the Deployment still says `hello from commit 3`. The failed migration stopped the release before the new version went out. That's exactly what you want from a schema migration.

Undo it, and watch how long the fix waits:

```bash
cd /tmp/podinfo-gitops && git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main; cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase} retry {.status.operationState.retryCount}{"\n"}' -w
```

**What you should see.** The operation stays `Running` for a few minutes before your revert takes effect. The next step explains why, and how to skip the wait.

### Concept: a sync is an operation with a fixed revision

In short, ArgoCD finishes or gives up on one sync before it starts the next. A sync isn't a loop that always applies the newest commit. Instead, ArgoCD writes an **operation** into the Application's `status.operationState`. The operation records the Git revision to apply and how far the sync got. That revision stays fixed until the operation ends. When an automated sync fails, ArgoCD retries the same operation with the same old commit. It waits longer before each attempt. Your revert lands in Git, but ArgoCD starts no new sync while the old operation still runs. The diagram shows the order. Commit B fails and retries, and commit C waits until the retries run out or you terminate the operation.

![A failing sync operation retries commit B while the revert in commit C waits](../docs/diagrams/chapters/22-sync-operation.svg)

Plain Kubernetes has no such queue. A Deployment controller always works toward the newest spec. With ArgoCD, a failing operation blocks your fix from reaching the cluster. Step 7 shows how to end it.

### 7. Guardrails, and the retry trap

A teammate commits a ClusterRole that reads every resource in the cluster:

```bash
cat course/gitops-extras/sneaky-clusterrole.yaml
cd /tmp/podinfo-gitops
cp "$C"/course/gitops-extras/sneaky-clusterrole.yaml base/
printf '  - sneaky-clusterrole.yaml\n' >> base/kustomization.yaml
git add . && git commit -qm "let podinfo read everything" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
sleep 10
kubectl -n argocd get app podinfo-dev -o jsonpath='{range .status.operationState.syncResult.resources[?(@.kind=="ClusterRole")]}{.message}{"\n"}{end}'
kubectl get clusterrole podinfo-reads-everything
```

**What you should see.** The first command prints `resource rbac.authorization.k8s.io:ClusterRole is not permitted in project team-shop`. The second prints `NotFound` for the ClusterRole. ArgoCD refused the whole sync, so nothing from that commit reached the cluster.

Revert it, and look at the operation:

```bash
cd /tmp/podinfo-gitops && git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main; cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase}: {.status.operationState.message}{"\n"}'
```

**What you should see.** The operation is still `Running` and still shows `Retrying attempt #...` for the *old* commit. An automated sync that fails retries up to 5 times, with a longer pause each time. In the test run, the failing operation kept retrying from 20:48:15 to 20:53:25. A revert pushed in the middle only took effect after that. During an incident, you don't have those 5 minutes. Stop the retries yourself:

```bash
kubectl -n argocd patch app podinfo-dev --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}'
kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.sync.status} {.status.health.status}: {.status.operationState.message}{"\n"}'
```

**What you should see.** Within a second the command prints `Synced Healthy: Operation terminated (retried 2 times).`. With the `argocd` CLI, `argocd app terminate-op podinfo-dev` does the same thing. The UI also has a Terminate button on a running sync.

### 8. One template, many environments

```bash
kubectl -n argocd delete app podinfo-dev
kubectl -n course-gitops-dev get all
kubectl apply -f course/manifests/22-appset.yaml
sleep 20; kubectl -n argocd get app podinfo-dev podinfo-prod
kubectl get deploy -A | grep course-gitops-
kubectl -n argocd get app podinfo-prod -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
```

**What you should see.** Deleting the Application removed its Deployment, Service and pods. The finalizer did that. Next, the ApplicationSet created `podinfo-dev` and `podinfo-prod` from one template. An ApplicationSet is a template that generates Applications. Both were `Synced Healthy` within about 20 seconds. The overlays give dev 1 replica and prod 2. Both Applications carry an owner reference to `ApplicationSet/podinfo`.

Delete one and see what happens, then remove a file from Git:

```bash
kubectl -n argocd delete app podinfo-prod
sleep 20; kubectl -n argocd get app podinfo-prod
cd /tmp/podinfo-gitops
git rm -q base/config-wave.yaml && sed -i '' '/config-wave.yaml/d' base/kustomization.yaml
git commit -qam "drop the settings ConfigMap" && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main
cd -
for a in dev prod; do kubectl -n argocd annotate app podinfo-$a argocd.argoproj.io/refresh=normal --overwrite; done
sleep 25; kubectl get cm -A | grep podinfo-settings
```

**What you should see.** About 20 seconds later, `podinfo-prod` is back and `Healthy`. The ApplicationSet owns it, so it recreates it. `grep` finds no `podinfo-settings` ConfigMap. The file left Git, so `prune: true` deleted the ConfigMap from both namespaces.

A generator is the part of an ApplicationSet that produces the list of Applications. This module uses the list generator, the simplest one. Other generators create Applications from other sources:

- The `git` generator creates one for every folder in a repository.
- The `cluster` generator creates one for every cluster ArgoCD knows.
- The `pullRequest` generator creates one for every open pull request. This gives each PR its own preview environment.

## Investigate

1. Your team turned on `selfHeal`. During an incident, an engineer scales a Deployment from 3 to 10 replicas with `kubectl`, and it drops back to 3 a second later. What are the two right ways to scale up, and which one fits an incident at 3 a.m.?
2. Step 5 showed `Synced` and `Degraded` together. Which alert would you build on ArgoCD's status, and why not alert on `OutOfSync`?
3. A developer asks for a PreSync hook that runs `kubectl delete` on old resources. What's the problem, and what does ArgoCD offer instead?
4. Your ApplicationSet generates 40 Applications from a `git` generator, one per folder. Someone deletes a folder by mistake. What happens, and which setting protects you?

<details>
<summary>Answers</summary>

1. There are two right ways.
   - Change `replicas` in Git and push. This keeps Git the truth. Add a refresh annotation or use a webhook, so the change applies in seconds.
   - Sometimes Git is slow to change, for example because of review rules or a broken pipeline. Then turn off `selfHeal` for that Application first and scale by hand. Afterwards, open a follow-up task to put the number in Git.

   At 3 a.m., the Git path is the right default when a push and a refresh take a minute, because nothing drifts and nothing needs cleaning up later. If pushing to Git is blocked, turning off `selfHeal` and scaling by hand is the faster fix. Then the follow-up task is what keeps Git from overwriting your fix at the next sync.

   Many teams also let an HPA own the replica count and leave `replicas` out of Git altogether. That way autoscaling never fights ArgoCD.
2. Alert on health. Fire the alert when an Application stays `Degraded` or `Progressing` for longer than its rollout normally takes. ArgoCD exports the metric `argocd_app_info` for Prometheus, with `health_status` and `sync_status` labels. `OutOfSync` happens for a few seconds on every push. With `selfHeal` off, it's often intended. So an `OutOfSync` alert is noisy. A short `OutOfSync` is normal, but a long `Degraded` is an outage.
3. The hook needs credentials to delete things. It also deletes outside ArgoCD's view, so nothing tracks what happened. ArgoCD already removes resources that leave Git, with `prune: true`. The annotation `argocd.argoproj.io/sync-options: Prune=false` protects single resources from pruning. Use waves and hooks for ordering, and prune for clean-up.
4. The `git` generator stops producing that Application, so the ApplicationSet deletes it. Because of the resources finalizer, everything in that folder's namespace goes too. Two settings on the ApplicationSet protect you:
   - `syncPolicy.preserveResourcesOnDeletion: true` keeps the workloads when an Application disappears.
   - `applicationsSync: create-update` stops the ApplicationSet from deleting Applications at all.

</details>

## Clean up

```bash
./course/reset.sh
kill %1 2>/dev/null; rm -rf /tmp/podinfo-gitops
```

This deletes:

- the ApplicationSet and its Applications
- the podinfo deployments, through the Applications' finalizers
- the `team-shop` project
- Gitea
- the three `course-gitops` namespaces
