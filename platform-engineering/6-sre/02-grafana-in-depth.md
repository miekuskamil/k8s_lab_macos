# Module 6.2: Grafana in depth

> New to a term here, like RED, USE or chained variable? The [glossary](../glossary.md#reliability-engineering) explains every term in this course.

**Before this module:** [module 6.1](01-slis-slos-and-error-budgets.md), for checkout and its SLO rules; step 1 brings both back in one command. No Istio needed. If you took [module 2.2](../2-observability/02-grafana-as-code.md), you loaded one dashboard from a ConfigMap; this module builds a set of three, delivers them through Git and ArgoCD, and adds an alert that only Grafana evaluates.

**You need:** the lab running, `./lab.sh shell` for the commands, and `./lab.sh ui` in a spare terminal for Grafana (http://localhost:3000, `admin` / `k8s-lab-admin`) and ArgoCD (http://localhost:8081).

When checkout pages someone at 3 a.m., that person needs three answers in a few minutes: is the SLO in trouble and how fast, which service is slow or failing, and which pod is out of CPU or memory. Three dashboards answer them in that order, and they only help if they look the same in every environment and survive a Grafana upgrade, so they live as files in Git like any other manifest. In this module you build those three dashboards, deliver them from a Git server through ArgoCD, follow one incident through them, and add a Grafana alert on log lines, which Prometheus never reads.

Time: about 60 minutes. Memory: Gitea and the alert receiver add about 150 MiB on top of module 6.1's apps.

## Concept: three dashboards, three questions

A dashboard that shows everything answers nothing, because the person on call has to know which of forty graphs matters. So each dashboard here answers one question, and links lead from one to the next.

| Dashboard | Question | Method | Built from |
|---|---|---|---|
| **SRE / SLOs** | Is the user hurt, and how fast does the budget burn? | SLO and burn rate | the Sloth rules of module 6.1 |
| **SRE / RED** | Which service is failing or slow? | RED: rate, errors, duration | each app's request histogram |
| **SRE / USE** | Which pod runs out of something? | USE: utilization, saturation, errors | cAdvisor and kube-state-metrics |

RED and USE come from two engineers who looked at the same problem from two ends. Tom Wilkie's **RED method** watches a service from the outside, the way a caller sees it, so it works for any app that counts its requests. Brendan Gregg's **USE method** watches resources from the inside: a pod at 95% of its CPU limit is busy (utilization), a pod that waits for CPU it may not take sits throttled (saturation), and a pod that the kernel killed for memory is broken (errors). RED tells you where it hurts, and USE tells you why.

Every panel uses variables, so one dashboard serves every service. The RED dashboard has `$namespace` and `$app`, and `$app` is a **chained variable**: its query, `label_values(http_request_duration_seconds_count{namespace="$namespace"}, app)`, uses the first variable, so the list shows only the apps of the namespace you picked. The SLO dashboard repeats one row for every SLO you select in `$slo`, a **repeated row**, so a new SLO in Sloth's spec shows up without a change to the dashboard.

## Concept: from a push to a panel

![Dashboards from Git, alerts from the API: a git push reaches Gitea, ArgoCD fetches it and applies three ConfigMaps, Grafana's sidecar loads them; a curl to the provisioning API creates an alert rule that queries Loki and calls a webhook](../../docs/diagrams/chapters/6.2-dashboards-from-git.svg)

A dashboard file travels five steps before it draws, the orange numbers in the picture:

1. You push the dashboards folder to a Git server inside the cluster, Gitea.
2. ArgoCD fetches the repository, every 3 minutes or at once when you ask it to refresh.
3. ArgoCD builds the folder with Kustomize, which wraps each JSON file in a ConfigMap labelled `grafana_dashboard: "1"`, and applies them.
4. The sidecar container in the Grafana pod sees the labelled ConfigMaps and writes their JSON to a folder.
5. Grafana loads that folder as provisioned dashboards, which it refuses to change, because the next sync would overwrite the change.

Alert rules travel a shorter way, the teal numbers. The lab's Grafana has no sidecar for alert rules, so you hand the rule to Grafana's provisioning API with `curl` (1). Grafana evaluates it every 30 seconds against Loki (2), and when it fires, it calls the contact point the rule names, a webhook into `course-sre` (3).

## The bigger picture: dashboards are code, and code has owners

Teams that click dashboards together end up with hundreds of them, half broken, all slightly different between staging and production. The fix that spread through the industry treats dashboards like application code: JSON or a generator language such as Jsonnet or Grafana's Foundation SDK, reviewed in pull requests, delivered by GitOps, and owned by the team that owns the service. Grafana 12 moves the same way with Git sync built in, and the Grafana Operator offers dashboards and alert rules as Kubernetes resources.

Alerting is converging too. Prometheus rules stay the first choice for metrics, because they run next to the data and keep working when Grafana is down, while Grafana-managed rules fill the gaps: logs, traces, SQL, or a cloud API outside Prometheus' reach.

## Why this way

**Why Kustomize instead of writing the ConfigMaps by hand?** The JSON stays a plain `.json` file that diffs cleanly in a review, and Kustomize adds the ConfigMap around it at build time. ArgoCD runs Kustomize by itself, so the repository needs nothing else. `disableNameSuffixHash` keeps the names fixed, so a change updates the ConfigMap instead of adding a new one.

**Why a Git server in the cluster?** ArgoCD's lab applications read the course's GitHub repository, so a change there would mean a commit to GitHub, and every push resyncs the lab. Gitea gives you a private repository in seconds that ArgoCD reaches over the cluster network.

**Why `$__rate_interval` in RED and USE but fixed windows in the SLO panels?** RED and USE show what happens right now at any zoom level, and `$__rate_interval` picks a safe `rate()` window from the scrape interval and the panel's resolution. SLO panels must show the same windows the alerts use, or the graph and the page disagree.

**Why a Loki rule in Grafana and not in Prometheus?** Prometheus never reads logs. A rule on "more than 10 error lines a minute" needs LogQL, so it runs where a Loki data source exists, which is Grafana here. It also catches errors that never reach a metric, such as a log line from a background job.

**Why simplified routing on the rule?** The rule names its contact point in `notification_settings`, so it reaches the webhook without a change to Grafana's notification policy tree, which every team in the organization shares.

## Do it

OUT-62

## Tasks

Each task gives you a goal without the commands. `./lab.sh task setup` prepares it, you solve it in `./lab.sh shell`, and `./lab.sh task check` tells you what still fails. The solution sits under each task, and `./lab.sh task solve` runs it for you.

### Task 6.2.1: fix a dashboard that shows nothing

<!-- norun -->
```console
$ ./lab.sh task setup 6.2.1
TASK-SETUP-6.2.1
```

> A teammate committed the dashboard *Checkout / calls to payments* as the ConfigMap `dashboard-checkout-calls` in `course-sre`. It loads, but its *Result* dropdown stays empty and one panel says *No data*. Fix the ConfigMap so the dropdown lists the call results and every panel draws.

<details>
<summary>Solution</summary>

TASK-SOLUTION-6.2.1

</details>

<!-- norun -->
```console
$ ./lab.sh task check 6.2.1
TASK-CHECK-6.2.1
```

### Task 6.2.2: a Grafana alert on checkout's p95

<!-- norun -->
```console
$ ./lab.sh task setup 6.2.2
TASK-SETUP-6.2.2
```

> In the folder `sre`, create a Grafana-managed alert rule with uid `checkout-p95` that queries the Prometheus data source for checkout's 95th-percentile latency over 5 minutes, from its histogram, fires when it is above 0.25 seconds for 1 minute, and notifies the contact point `sre-webhook` directly.

<details>
<summary>Solution</summary>

TASK-SOLUTION-6.2.2

</details>

<!-- norun -->
```console
$ ./lab.sh task check 6.2.2
TASK-CHECK-6.2.2
```

## Investigate

1. The RED panel of payments showed no errors during the bad release, while checkout's showed 20%. A teammate concludes payments is healthy. Is that safe, and which panel of which dashboard would you check before you agree?
2. A developer edits the RED dashboard in Grafana, gets "Cannot save provisioned dashboard", and asks you to turn provisioning off. What do you suggest instead?
3. The USE dashboard shows the loadgen pod at 500% of its CPU request but only 50% of its limit. Is that pod in trouble, and what does it mean for the node?
4. Your log rule fires once a day for a minute during a nightly batch that logs expected errors. How do you stop the noise without losing real alerts?

<details>
<summary>Answers</summary>

1. Not quite. Payments' own histogram only counts requests that reached payments, so a network problem between the two, or payments refusing connections, shows up as errors in checkout and as fewer requests in payments, not as payments errors. Check checkout's `checkout_payments_calls_total` by result, and payments' request rate on the RED dashboard: a rate that drops while checkout's stays flat means calls are lost on the way. Here checkout's errors came from its own setting, `ERROR_PERCENT`, so payments really was fine.
2. Keep provisioning and change the source: use "Save as" for a scratch copy, export the JSON, commit it to the repository and push. ArgoCD and the sidecar deliver it within a few minutes, and every environment gets the same change. Turning provisioning off brings back the drift that dashboards as code removed.
3. Not in trouble yet. The request is what the scheduler reserved, and the pod uses more than that because the node has idle CPU; the limit is where the kernel starts to throttle. It matters for the node: requests are what the scheduler counts, so pods that use far more than they reserve crowd the node when everyone gets busy at once. Raise the request to what the pod really uses, or lower its work.
4. Narrow the query to what the rule is for, for example exclude the batch job's pod or message with a LogQL filter, or add a mute timing for the batch window in Grafana. Raising the threshold or the `for` duration also works, but it delays real alerts too, so filtering the known noise is the better fix.

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

The reset deletes the `sre-dashboards` Application first, whose finalizer removes the three ConfigMaps, so Grafana drops the dashboards. It then deletes the alert rule, the `SRE` folder and the `sre-webhook` contact point through Grafana's API, because those live only in Grafana's database, and finally the `course-sre` namespace with Gitea, the receiver and the apps.
