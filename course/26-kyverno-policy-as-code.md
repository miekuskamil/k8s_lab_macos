# Module 26: Kyverno, policy as code

> New to a term here, like admission webhook or PolicyException? The [glossary](glossary.md) explains every term in this course.

**Before this module:** module 0. No Istio needed: the policies only touch the module's own namespaces.

RBAC decides *who* may create a Deployment. It says nothing about *what* the Deployment looks like. A team might use an image tagged `latest`, set no memory limit, or run a container as root. In a bank, an auditor asks you to prove that every workload follows the rules, every day. The auditor also wants every exception written down. **Kyverno** does that inside Kubernetes. It does four jobs:

- It checks every object the API server receives.
- It fixes what teams forget.
- It creates the boilerplate every namespace needs.
- It reports on everything already running.

Time: about 50 minutes. Adds about 230 MB of memory while it runs.

## Concept: where Kyverno sits

![Kyverno's mutating and validating webhooks in the API server request path, plus the background and reports controllers](../docs/diagrams/chapters/26-where-kyverno-sits.svg)

The diagram follows one `kubectl apply` or ArgoCD sync:

1. You or ArgoCD send an object to the API server.
2. The API server sends the object to Kyverno's mutating webhook, which adds defaults.
3. The API server sends the changed object to Kyverno's validating webhook, which allows or denies it.
4. The API server stores the allowed object.

An **admission webhook** is a call the API server makes to another program before it stores an object. Kyverno registers itself as one and answers in milliseconds. Think of a security check at an airport gate: every object passes it before it boards.

Two more Kyverno parts work outside of requests, shown with dotted lines:

- The background controller scans objects that already run and creates generated objects.
- The reports controller writes the results into PolicyReports.

## Concept: four things a policy does

| Rule type | Does | In this module |
|---|---|---|
| **validate** | Allows or refuses an object. `Audit` only reports. `Enforce` refuses | memory limits (Audit), image tags (Enforce), owner label (CEL) |
| **mutate** | Changes the object on its way in | add a team label and a default memory limit |
| **generate** | Creates other objects when something appears | quota and default-deny NetworkPolicy for every tenant namespace |
| **verifyImages** | Checks image signatures | not used here, because it needs signed images |

You write policies as Kubernetes YAML patterns, not as code. For example, `image: "*:* & !*:latest"` means "has a tag, and the tag isn't latest".

You write a rule for Pods, but pods usually come from Deployments, Jobs and other controllers. Kyverno's **autogen** feature copies the rule to Deployments, ReplicaSets, Jobs and CronJobs too. That way the error shows up when you apply the Deployment, not later.

## The bigger picture: policy as code

Policies used to live in wiki pages and review checklists. Policy as code puts them in Git, next to everything else, and the cluster enforces them. This gives you three things:

- the same rule for every team
- a review for every policy change, like any other change
- reports that prove the rules hold

The two big tools are:

- **Kyverno**, a CNCF project with policies written in YAML
- **OPA Gatekeeper**, with policies written in the Rego language

Kubernetes itself now has **ValidatingAdmissionPolicy**, a built-in validation feature. You write its rules in CEL, the Common Expression Language, a small language for true-or-false checks. Kyverno 1.18 adds its own CEL-based policy types next to the classic `ClusterPolicy`. You'll write one of each.

Regulated companies care because policies change what they tell an auditor. "We asked teams to set limits" becomes "the cluster refuses workloads without limits, here's the report, and here are the three written exceptions".

## Why this way

**Why Audit before Enforce?** Switching a rule straight to Enforce breaks every team that doesn't comply yet, and often nobody notices. Step 3 shows how. So roll out a rule in four steps:

1. Run the rule in Audit mode.
2. Read the reports.
3. Fix the workloads or grant exceptions.
4. Switch the rule to Enforce.

**Why only one namespace?** A typo in a policy that matches every namespace blocks the whole cluster, including Istio and ArgoCD. Limiting the policies to `course-policy` keeps the lab safe. In production, policies match broadly but exclude system namespaces. Kyverno already excludes its own namespaces by default.

**Why are exceptions only allowed in the `kyverno` namespace?** If teams wrote exceptions in their own namespaces, every rule would have a self-service way out. Here only the platform team may write to `kyverno`, so only the platform team grants exceptions. Each exception is a reviewed object in Git.

**Why one replica?** It's a laptop. In production, the admission controller runs three replicas. If Kyverno is down and its webhook says `failurePolicy: Fail`, the API server refuses changes everywhere. The install warns about this.

## Do it

### 1. Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/ && helm repo update kyverno
cat course/manifests/26-kyverno-values.yaml
helm install kyverno kyverno/kyverno --version 3.8.2 -n kyverno --create-namespace \
  -f course/manifests/26-kyverno-values.yaml --wait
kubectl -n kyverno get pods
kubectl get validatingwebhookconfigurations,mutatingwebhookconfigurations | grep kyverno
kubectl get crd | grep kyverno
```

**What you should see.** In the test run, the install took 21 seconds and printed two warnings:

- One replica means no high availability.
- PolicyExceptions start switched off. The values file turns them on.

Four controllers run: admission, background, cleanup and reports. Kyverno created ten webhook configurations by itself. It also created 20 CRDs, including the classic `clusterpolicies.kyverno.io` and the newer CEL types such as `validatingpolicies.policies.kyverno.io`.

### Concept: two paths to a verdict

Kyverno checks objects at two different moments, and each answers a different question:

| | Admission | Background scan |
|---|---|---|
| When | each create, update or delete request, before the API server stores the object | when a policy appears or changes, and again on a regular interval |
| What it sees | the one object in the request | every matching object already stored |
| With `Enforce` | refuses the request | refuses nothing, only reports |
| With `Audit` | allows it, records the result | reports |

Both paths end in the same place. The reports controller collects the results into one PolicyReport per namespace. In step 2, the `legacy` app already runs before the policy exists. So its failures come from the background scan that starts when you apply the policy. That's why you wait before reading the reports.

Two consequences surprise people. First, `Enforce` never stops pods that already run. It only acts on the next request.

Second, admission sees every object separately, including the objects that controllers create. One Deployment turns into three separate requests through the webhooks:

1. You create the Deployment.
2. The Deployment controller creates a ReplicaSet.
3. The ReplicaSet controller creates the pods.

So when Kyverno refuses a pod, the refusal goes to the ReplicaSet controller, not to you. It shows up only as an event on the ReplicaSet. Step 3 shows it happen.

### 2. Audit an app that breaks the rules

```bash
kubectl apply -f course/manifests/26-namespace.yaml -f course/manifests/26-legacy-app.yaml
cat course/manifests/26-require-limits.yaml
kubectl apply -f course/manifests/26-require-limits.yaml
kubectl get clusterpolicy
kubectl get clusterpolicy require-memory-limits -o jsonpath='{.status.autogen.rules[*].name}{"\n"}'
```

Wait half a minute, then read the reports:

```bash
kubectl -n course-policy get policyreport -o 'custom-columns=KIND:.scope.kind,NAME:.scope.name,PASS:.summary.pass,FAIL:.summary.fail'
kubectl -n course-policy get policyreport -o jsonpath='{range .items[*].results[?(@.result=="fail")]}{.policy}: {.message}{"\n"}{end}' | sort -u
```

**What you should see.** The policy shows `READY True`, and autogen added `autogen-memory-limit` and `autogen-cronjob-memory-limit` next to the rule you wrote. The `legacy` app keeps running, because Audit blocks nothing. The reports list the Deployment, its ReplicaSet and its Pod, each with one failure: `Every container needs resources.limits.memory.` That's the list you'd hand to an auditor, or to the teams.

### 3. Enforce, and see what breaks

```bash
cat course/manifests/26-disallow-latest.yaml
kubectl apply -f course/manifests/26-disallow-latest.yaml
kubectl -n course-policy run t1 --image=nginx:latest
kubectl -n course-policy run t2 --image=nginx
kubectl -n course-policy run t3 --image=nginx:1.27-alpine
```

**What you should see.** `t1` and `t2` get refused with `Use a specific image tag, not latest or none.`, and `t3` gets created. Now the legacy app, which uses `nginx:latest`:

```bash
kubectl -n course-policy rollout restart deploy/legacy
kubectl -n course-policy get deploy,rs,pods
kubectl -n course-policy get events --field-selector reason=FailedCreate
```

**What you should see.** `kubectl` says `deployment.apps/legacy restarted`, and nothing looks wrong. But three things show that the rollout is stuck:

- The Deployment reads `UP-TO-DATE 0`.
- A new ReplicaSet sits at `CURRENT 0`.
- The events say `Error creating: admission webhook "validate.kyverno.svc-fail" denied the request`.

Here is what happened:

1. Kyverno let the Deployment update through. By default, it allows updates to objects that already broke a rule. The setting for this is `allowExistingViolations`.
2. The Deployment controller created a new ReplicaSet.
3. Kyverno refused the new ReplicaSet's pod.

The rollout hangs, and the old pod keeps serving. That's the classic way a new policy breaks a team's next deploy without anyone noticing. It's also the reason to audit first.

### 4. Grant a written exception

```bash
cat course/manifests/26-exception.yaml
kubectl apply -f course/manifests/26-exception.yaml
kubectl -n course-policy rollout status deploy/legacy
kubectl -n course-policy run other --image=nginx:latest
```

**What you should see.** The stuck rollout finishes within seconds of the exception. `other` is still refused, because the exception names only the policy, the rules and the `legacy*` objects. In the reports, the image-tag check for `legacy` now shows as **skip**, not pass. That keeps the exception visible.

Now try the shortcut a team might try. Put the same exception in `course-policy`, for `other*`:

```bash
sed 's/namespace: kyverno/namespace: course-policy/; s/name: legacy-may-use-latest/name: self-service/; s/"legacy\*"/"other*"/' \
  course/manifests/26-exception.yaml | kubectl apply -f -
kubectl -n course-policy run other --image=nginx:latest
kubectl -n course-policy delete policyexception self-service
```

**What you should see.** You get a warning, `PolicyException resource namespace must match the defined namespace`. The object still gets created, but Kyverno ignores it, and `other` stays refused.

### 5. Fill in what teams forget

```bash
cat course/manifests/26-add-defaults.yaml
kubectl apply -f course/manifests/26-add-defaults.yaml
kubectl -n course-policy run plain --image=nginx:1.27-alpine
kubectl -n course-policy get pod plain -o jsonpath='{.metadata.labels}{"\n"}{.spec.containers[0].resources.limits}{"\n"}'
kubectl -n course-policy run owned --image=nginx:1.27-alpine --labels=team=payments
kubectl -n course-policy get pod owned -o jsonpath='{.metadata.labels}{"\n"}'
```

**What you should see.** `plain` got `"team":"unassigned"` and a memory limit of `128Mi` it never asked for. `owned` keeps `"team":"payments"`, because the `+( )` anchor adds a value only when it's missing. Mutation runs before validation, so `plain` also passes the memory-limit rule from step 2.

### 6. Generate the boilerplate for every tenant

```bash
cat course/manifests/26-generate-tenant.yaml
kubectl apply -f course/manifests/26-generate-tenant.yaml
kubectl create namespace course-tenant-a
kubectl label namespace course-tenant-a course-policy/tenant=true
kubectl -n course-tenant-a get resourcequota,networkpolicy
kubectl -n course-tenant-a get networkpolicy default-deny-ingress -o jsonpath='{.metadata.uid}{"\n"}'
kubectl -n course-tenant-a delete networkpolicy default-deny-ingress
kubectl -n course-tenant-a get networkpolicy default-deny-ingress -o jsonpath='{.metadata.uid}{"\n"}'
```

**What you should see.** One second after the label, the namespace has two new objects:

- `tenant-quota`, which allows 10 pods and 2 GiB of memory limits
- `default-deny-ingress`

Delete the NetworkPolicy, and it's back at once, with a new uid. `synchronize: true` makes Kyverno guard what it generated. Its labels, such as `app.kubernetes.io/managed-by: kyverno`, show who owns it.

### 7. The CEL style

```bash
cat course/manifests/26-cel-policy.yaml
kubectl apply -f course/manifests/26-cel-policy.yaml
kubectl get validatingpolicy
kubectl -n course-policy create deployment no-owner --image=nginx:1.27-alpine
kubectl -n course-policy create deployment with-owner --image=nginx:1.27-alpine --dry-run=client -o yaml \
  | kubectl label --local -f - owner=team-shop -o yaml | kubectl apply -f -
```

**What you should see.** The webhook `vpol.validate.kyverno.svc-fail` refuses `no-owner` with `Deployments in course-policy need an owner label.`, and `with-owner` gets created. The rule is one CEL expression, `has(object.metadata.labels) && 'owner' in object.metadata.labels`. Kubernetes' built-in ValidatingAdmissionPolicy uses the same language. Compare it with the YAML pattern in step 3. Patterns read like the object they check. CEL reads like code, and it handles logic that patterns express only clumsily.

## Investigate

1. You switch a widely used policy from Audit to Enforce on Friday afternoon. On Monday, three teams report that their deploys "succeed" but nothing changes. What happened, and what should you have checked first?
2. Kyverno's admission controller crashes. What happens to `kubectl apply` in a namespace it covers, and why do production clusters run three replicas?
3. Why does the mutation policy run before the validation policies, and what does that mean for the memory-limit rule?
4. ArgoCD (module 22) deploys the `legacy` app from Git. After step 3, what does ArgoCD show for it, and where would you see the reason?

<details>
<summary>Answers</summary>

1. The policy refuses their pods, as in step 3. The Deployment update passes, but the new ReplicaSet fails to create pods. The rollout hangs while the old pods keep serving. Before switching, you should have read the PolicyReports from the Audit phase. Every `fail` there becomes a broken deploy under Enforce. Fix those workloads or write exceptions first, and switch on a weekday morning.
2. With the default `failurePolicy: Fail`, the API server gets no answer from the webhook. So it refuses every request the webhook covers. That's why production runs the admission controller with three replicas and a PodDisruptionBudget. It's also why Kyverno excludes its own namespace and system namespaces from its webhooks. That way, Kyverno always keeps the means to repair itself. Setting `failurePolicy: Ignore` keeps the cluster usable, but it lets anything through while Kyverno is down.
3. The API server calls all mutating webhooks before any validating webhook. So validation always sees the final object. Step 5 adds a default memory limit, so a pod without a limit still passes `require-memory-limits`. That's often what you want. Mutation fixes the easy cases, and validation catches the rest.
4. ArgoCD shows the app `Synced`, because the Deployment in the cluster matches Git. Its health shows `Progressing`, then `Degraded` once the progress deadline runs out, because no new pod ever starts. That's the same Synced-and-Degraded pair as in module 22. The reason sits in the ReplicaSet's `FailedCreate` events and in Kyverno's PolicyReports, not in ArgoCD.

</details>

## Clean up

```bash
./course/reset.sh
```

The reset works in this order:

1. It deletes the policies, so nothing blocks the clean-up.
2. It uninstalls Kyverno. The chart's own hook removes the webhooks Kyverno created at runtime, and its CRDs.
3. It deletes the `kyverno`, `course-policy` and `course-tenant-a` namespaces.

In the test run, nothing Kyverno-related was left afterwards.
