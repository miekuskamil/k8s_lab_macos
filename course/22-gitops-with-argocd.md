# Module 22: GitOps with ArgoCD

> New to a term here, like Application or sync wave? The [glossary](glossary.md) explains every term in this course.

**Before this module:** module 0. No Istio knowledge needed.

The whole lab runs on ArgoCD, and so far you've mostly worked around it: `reset.sh` re-syncs it, and the course warns you not to push mid-exercise. This module turns it into the subject. You run your own Git server inside the cluster, deploy an app from it, and then do the things that come up in every platform team and every GitOps interview: drift, rollbacks, ordered deploys with migrations, a project that fences a team in, and one template for many environments.

Time: about 60 minutes.

## Concept: the reconcile loop

```mermaid
flowchart LR
  dev["You:<br/>git push"] --> git["Git<br/>(desired state)"]
  git -- "poll every 3 min,<br/>or a webhook" --> repo["repo-server<br/>renders the manifests<br/>(Kustomize, Helm)"]
  repo --> ctrl["application-controller<br/>compares desired with live"]
  ctrl -- "sync: kubectl apply" --> k8s["Cluster<br/>(live state)"]
  k8s -- "watch" --> ctrl
```

ArgoCD keeps two questions apart, and its UI shows both for every Application:

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

An **AppProject** decides what a group of Applications may do at all: which repositories they read, which namespaces they deploy to, which kinds of resources they create. It's ArgoCD's version of RBAC, and the place where a platform team says "this team deploys its app, and nothing else".

## The bigger picture: why GitOps won

Before GitOps, a CI pipeline ran `kubectl apply` or `helm upgrade` at the end of a build. That works until it doesn't: the pipeline holds cluster-admin credentials, nobody knows whether the cluster still matches the last deploy, and a manual hotfix at 3 a.m. quietly survives until the next deploy overwrites it.

GitOps turns this around. The cluster *pulls* its desired state from Git, and an agent inside the cluster keeps comparing. Git becomes the audit log (who changed what, when, reviewed by whom), a rollback becomes a `git revert`, and the CI pipeline no longer needs any access to the cluster. ArgoCD and Flux, both CNCF graduated projects, are the two common agents. Danish and UK job adverts for platform roles name ArgoCD more often than any other deployment tool.

## Why this way

**Why a Git server inside the cluster?** The lab's own ArgoCD reads the course repository on GitHub. Exercises there would mean commits to GitHub, and a push resyncs `istio-config`, which wipes whatever module you're in. Gitea gives you a private repository in seconds, and ArgoCD reads it over the cluster network like any other Git host.

**Why a new AppProject instead of the lab's `k8s-lab` project?** `k8s-lab` allows everything, because it deploys Istio, CRDs and cluster-wide RBAC. A team's app deserves the opposite: one repository, its own namespaces, no cluster-scoped resources. Step 7 shows the difference.

**Why Kustomize overlays for dev and prod?** One base holds the app, and each environment changes only what differs, here the number of replicas. ArgoCD renders Kustomize by itself, with no plugin.

**Why `progressDeadlineSeconds: 60` in the Deployment?** A stuck rollout turns `Degraded` only after this deadline, 10 minutes by default. One minute keeps step 5 short. Production teams often lower it too, so broken releases surface faster.

## Do it

### 1. Start a Git server

```bash
kubectl apply -f course/manifests/22-gitea.yaml
kubectl -n course-gitops rollout status deploy/gitea
kubectl -n course-gitops exec deploy/gitea -- gitea admin user create --username lab \
  --password lab-gitops-pass --email lab@example.invalid --admin --must-change-password=false
kubectl -n course-gitops port-forward svc/gitea 3001:3000 >/dev/null 2>&1 &
```

**What you should see.** `New user 'lab' has been successfully created!`. Gitea now answers on http://localhost:3001; sign in as `lab` with `lab-gitops-pass` if you'd like to browse it. The manifest also creates the namespaces `course-gitops-dev` and `course-gitops-prod`, because the project from step 2 won't allow ArgoCD to create namespaces.

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

**What you should see.** `Synced Healthy` within about 10 seconds, and one `podinfo` pod in `course-gitops-dev`. Open ArgoCD (http://localhost:8081, `admin` / `k8s-lab-admin`) and click `podinfo-dev`: a tree of the Service, the Deployment, its ReplicaSet and its pod.

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

**What you should see.** First `OutOfSync Healthy`, and 3 replicas that stay: ArgoCD noticed the drift and only reported it. After the patch, the Deployment drops back to 1 replica within 2 seconds. The second `kubectl scale` gets undone just as fast; in the test run, by the time the next command ran, 1 replica was all that was left.

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

**What you should see.** The first commit took 228 seconds to appear in the test run: ArgoCD polls Git every 3 minutes, plus some random jitter. With the annotation, it took 1 second. The pod then answers `"message": "hello from commit 3"`. In production, a Git webhook does what the annotation does: GitHub or GitLab calls ArgoCD on every push.

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

**What you should see.** `Synced Degraded` after 61 seconds in the test run, and two pods: the new one in `ErrImagePull` (tag 6.7.99 doesn't exist), the old one still `Running` and serving. A rolling update never removes the old pod before the new one is ready, so users noticed nothing. ArgoCD's resource list explains the health: `Deployment "podinfo" exceeded its progress deadline`.

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

**What you should see.** `Synced Healthy` within seconds, the broken pod gone, and the history in `git log`: the bad commit and its revert, both with your name. ArgoCD's UI also has a History and Rollback button, but it only works with automated sync turned off, and it leaves Git saying something different from the cluster. A revert keeps Git the single source of truth.

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

**What you should see.** About 15 seconds of `Running: waiting for completion of hook batch/Job/migrate`, then `waiting for healthy state of ...`, then `Succeeded`. The Job printed `migrating the schema` and `done`. ArgoCD ran the PreSync hook first, then the wave `-1` ConfigMap, then everything in wave 0. A **hook** runs at a phase of the sync (PreSync, Sync, PostSync, SyncFail). A **wave** orders normal resources: ArgoCD applies one wave, waits until it's healthy, then moves to the next.

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

**What you should see.** `one or more synchronization tasks completed unsuccessfully. Retrying attempt #...`, and the Deployment still says `hello from commit 3`. The failed migration stopped the release before the new version went out. That's exactly what you want from a schema migration.

Undo it, and watch how long the fix waits:

```bash
cd /tmp/podinfo-gitops && git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main; cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase} retry {.status.operationState.retryCount}{"\n"}' -w
```

**What you should see.** The operation stays `Running` for a few minutes before your revert takes effect. The next step explains why, and how to skip the wait.

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

**What you should see.** `resource rbac.authorization.k8s.io:ClusterRole is not permitted in project team-shop`, and `NotFound` for the ClusterRole. ArgoCD refused the whole sync, so nothing from that commit reached the cluster.

Revert it, and look at the operation:

```bash
cd /tmp/podinfo-gitops && git revert --no-edit HEAD && git push -q http://lab:lab-gitops-pass@localhost:3001/lab/podinfo-gitops.git main; cd -
kubectl -n argocd annotate app podinfo-dev argocd.argoproj.io/refresh=normal --overwrite
kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.operationState.phase}: {.status.operationState.message}{"\n"}'
```

**What you should see.** Still `Running`, still `Retrying attempt #...`, for the *old* commit. An automated sync that fails retries up to 5 times with growing pauses. In the test run the failing operation kept retrying from 20:48:15 to 20:53:25, and a revert pushed in the middle only took effect after that. During an incident, that's 5 minutes you don't have. Stop the retries yourself:

```bash
kubectl -n argocd patch app podinfo-dev --type merge -p '{"status":{"operationState":{"phase":"Terminating"}}}'
kubectl -n argocd get app podinfo-dev -o jsonpath='{.status.sync.status} {.status.health.status}: {.status.operationState.message}{"\n"}'
```

**What you should see.** `Synced Healthy: Operation terminated (retried 2 times).` within a second. With the `argocd` CLI, the same thing is `argocd app terminate-op podinfo-dev`, and the UI has a Terminate button on a running sync.

### 8. One template, many environments

```bash
kubectl -n argocd delete app podinfo-dev
kubectl -n course-gitops-dev get all
kubectl apply -f course/manifests/22-appset.yaml
sleep 20; kubectl -n argocd get app podinfo-dev podinfo-prod
kubectl get deploy -A | grep course-gitops-
kubectl -n argocd get app podinfo-prod -o jsonpath='{.metadata.ownerReferences[0].kind}/{.metadata.ownerReferences[0].name}{"\n"}'
```

**What you should see.** Deleting the Application removed its Deployment, Service and pods: that's the finalizer. The ApplicationSet then created `podinfo-dev` and `podinfo-prod` from one template, both `Synced Healthy` within about 20 seconds, with 1 replica in dev and 2 in prod from the overlay. Both Applications carry an owner reference to `ApplicationSet/podinfo`.

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

**What you should see.** `podinfo-prod` is back, `Healthy`, about 20 seconds later: the ApplicationSet owns it and recreates it. And `grep` finds no `podinfo-settings` ConfigMap: `prune: true` deleted it from both namespaces, because it left Git.

The list generator is the simplest one. Others create Applications from every folder in a repository (`git` generator), every cluster ArgoCD knows (`cluster`), or every open pull request (`pullRequest`), which gives each PR its own preview environment.

## Investigate

1. Your team turned on `selfHeal`. During an incident, an engineer scales a Deployment from 3 to 10 replicas with `kubectl`, and it drops back to 3 a second later. What are the two right ways to scale up, and which one fits an incident at 3 a.m.?
2. Step 5 showed `Synced` and `Degraded` together. Which alert would you build on ArgoCD's status, and why not alert on `OutOfSync`?
3. A developer asks for a PreSync hook that runs `kubectl delete` on old resources. What's the problem, and what does ArgoCD offer instead?
4. Your ApplicationSet generates 40 Applications from a `git` generator, one per folder. Someone deletes a folder by mistake. What happens, and which setting protects you?

<details>
<summary>Answers</summary>

1. Change `replicas` in Git and push, which keeps Git the truth, with a refresh annotation or a webhook so it applies in seconds. Or, when Git is slow to change (review rules, a broken pipeline), turn off `selfHeal` for that Application first, scale by hand, and open a follow-up to put the number in Git. Many teams also let an HPA own the replica count and leave `replicas` out of Git altogether, so autoscaling never fights ArgoCD.
2. Alert on health: an Application that stays `Degraded` (or `Progressing`) for longer than its rollout normally takes. ArgoCD exports `argocd_app_info` with `health_status` and `sync_status` labels for Prometheus. `OutOfSync` happens on every push for a few seconds, and with `selfHeal` off it's often intended, so it makes a noisy alert. A short `OutOfSync` is normal; a long `Degraded` is an outage.
3. The hook needs credentials to delete things, and it deletes outside ArgoCD's view, so nothing tracks what happened. ArgoCD already removes resources that leave Git, with `prune: true`, and the annotation `argocd.argoproj.io/sync-options: Prune=false` protects single resources from it. For ordering, waves and hooks exist; for clean-up, prune does the job.
4. The `git` generator stops producing that Application, and the ApplicationSet deletes it. With the resources finalizer, everything in that folder's namespace goes too. Set `syncPolicy.preserveResourcesOnDeletion: true` on the ApplicationSet to keep the workloads when an Application disappears, or `applicationsSync: create-update` to stop the ApplicationSet from deleting Applications at all.

</details>

## Clean up

```bash
./course/reset.sh
kill %1 2>/dev/null; rm -rf /tmp/podinfo-gitops
```

This deletes the ApplicationSet and its Applications (and, through their finalizers, the podinfo deployments), the `team-shop` project, Gitea and the three `course-gitops` namespaces.
