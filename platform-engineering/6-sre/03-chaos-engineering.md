# Module 6.3: Chaos engineering with Chaos Mesh

> New to a term here, like steady state or blast radius? The [glossary](../glossary.md#reliability-engineering) explains every term in this course.

**Before this module:** [module 6.1](01-slis-slos-and-error-budgets.md) for the SLOs, and [module 6.2](02-grafana-in-depth.md) for the SLO dashboard; step 1 brings both back. No Istio needed: every fault here works on plain pods.

**You need:** the lab running, `./lab.sh shell` for the commands, and `./lab.sh ui` in a spare terminal for Grafana (http://localhost:3000) and Prometheus (http://localhost:9090).

Every team believes its service survives a lost pod or a slow dependency, until the first real outage shows which beliefs were wrong, at 3 a.m. and with customers watching. Chaos engineering moves that discovery to a time you choose: you write down what should happen, break one small thing on purpose, and compare the numbers with your guess. This module installs Chaos Mesh, runs three experiments against checkout's dependency, payments, and watches each one on the SLO dashboard, which is where the cost of a fault shows up.

Time: about 50 minutes. Memory: Chaos Mesh adds about 150 MiB, and the reset removes it.

## Concept: an experiment, not an accident

A fault you inject teaches you something only when you know what you expected. So each experiment here follows the same four steps, which Netflix's chaos team wrote down after years of breaking production on purpose:

1. **Describe the steady state** in numbers the users feel, here checkout's two SLIs: no 5xx and no order slower than 250 ms over 5 minutes.
2. **Write a hypothesis**, such as "with two payments replicas, losing one pod every 30 seconds costs less than 1% of orders".
3. **Inject one fault** with a small **blast radius**: one service, a few minutes, and a way to stop it at once.
4. **Compare** the SLIs with the hypothesis, and fix what surprised you.

| Experiment | Fault | Hypothesis | What it tests |
|---|---|---|---|
| pod kill | one payments pod killed every 30 s | under 1% errors | replicas, readiness, how fast endpoints update |
| latency | +300 ms on every packet payments sends | the latency SLO pages, availability holds | timeouts and the latency SLO |
| partition | checkout and payments lose contact | the availability SLO pages within minutes | what a dependency outage costs |

## Concept: how a fault lands in a pod

![How a fault lands in a pod: you apply a NetworkChaos, the controller-manager tells the chaos-daemon on the node, the daemon enters the payments pod's network namespace and adds a delay with tc, checkout's orders get slower, and Prometheus turns that into a latency page](../../docs/diagrams/chapters/6.3-how-a-fault-lands.svg)

Chaos Mesh changes nothing in your Deployments. A fault is a custom resource, and two components carry it into the pod, as the numbers show:

1. You apply an experiment, such as a NetworkChaos with `action: delay`, in the namespace of the pods it targets.
2. The **controller-manager** watches those resources, picks the pods that match the selector, and sends the fault to the **chaos-daemon** on each pod's node.
3. The daemon runs privileged on the node, so it enters the pod's network namespace and adds a rule there: `tc netem` for a delay or packet loss, `iptables` drops for a partition. A pod kill skips the daemon, because the controller deletes the pod through the API.
4. Every call from checkout to payments now waits for the delay, inside the pod's own network stack, so the app needs no change and notices nothing but slowness.
5. checkout's own timer measures the slower orders, and the latency SLO from module 6.1 burns.

Deleting the experiment, or reaching its `duration`, makes the controller undo the rule, which is the abort button every experiment needs.

## The bigger picture: from game days to continuous chaos

Netflix started with Chaos Monkey in 2011, a program that killed random production servers during office hours, so engineers built services that shrugged it off. Today most teams start smaller: a game day in staging, with the team watching dashboards while one person injects faults. Mature teams then automate the experiments and run them in CI or on a schedule, with the SLO as the stop condition, so an experiment aborts itself when the budget burns too fast.

Chaos Mesh and LitmusChaos are the two CNCF projects for Kubernetes, and the cloud providers offer managed fault injection for their own services. The tools differ, but the discipline stays the same: a written hypothesis, a small blast radius, and a number that decides.

## Why this way

**Why break payments and not checkout?** checkout is where users arrive and where checkout measures the SLIs, so faults in its dependency show how far a problem travels and what checkout's timeout does with it, which is the question most incidents ask.

**Why a 1-second timeout in checkout?** Without a timeout, a partition would hold every checkout thread until the client gave up, and checkout would fail for every caller, not only for orders. The timeout turns a hang into a fast `504` and a clear error in the log, which is why step 5 shows exactly 1-second orders.

**Why `mode: all` with a selector, and a `duration` on every experiment?** The selector and mode set the blast radius: here every payments pod, and nothing else. The `duration` is a dead man's switch: if you forget the experiment or lose your terminal, Chaos Mesh ends it by itself.

**Why the latency SLO pages but the availability SLO stays quiet in step 4?** 300 ms of extra delay is slow, not broken: every order still succeeds, just above the 250 ms threshold. Two separate SLOs tell you which kind of trouble you have.

## Do it

OUT-63

## Tasks

Each task gives you a goal without the commands. `./lab.sh task setup` prepares it, you solve it in `./lab.sh shell`, and `./lab.sh task check` tells you what still fails. The solution sits under each task, and `./lab.sh task solve` runs it for you.

### Task 6.3.1: slow down only checkout's calls to payments

<!-- norun -->
```console
$ ./lab.sh task setup 6.3.1
TASK-SETUP-6.3.1
```

> Create a NetworkChaos named `checkout-to-payments-delay` in `course-sre` that adds 200 ms to the packets checkout sends to payments, and to nothing else: the client must still reach payments directly as fast as before.

<details>
<summary>Solution</summary>

TASK-SOLUTION-6.3.1

</details>

<!-- norun -->
```console
$ ./lab.sh task check 6.3.1
TASK-CHECK-6.3.1
```

### Task 6.3.2: find the experiment nobody stopped

<!-- norun -->
```console
$ ./lab.sh task setup 6.3.2
TASK-SETUP-6.3.2
```

> Orders started to fail, and nobody changed checkout or payments. Find the cause and make 20 orders in a row succeed again, without changing either Deployment.

<details>
<summary>Solution</summary>

TASK-SOLUTION-6.3.2

</details>

<!-- norun -->
```console
$ ./lab.sh task check 6.3.2
TASK-CHECK-6.3.2
```

## Investigate

1. In step 3, a handful of orders failed even though one payments pod was always ready. Where do those errors come from, and what would remove them?
2. The partition in step 5 turned into 504s after exactly one second. What would users see if checkout had no timeout, and what if its timeout were 30 seconds?
3. A teammate wants to run the latency experiment in production every night. What must be true before you agree?
4. The latency fault in step 4 delayed every packet payments sends, including its answers to the client's direct health checks. How would you scope a fault to only the calls checkout makes?

<details>
<summary>Answers</summary>

1. From the gap between a pod's death and the moment checkout stops picking it. The Service's endpoints drop a killed pod within a second or two, but calls already on their way, and connections opened just before, hit a pod that is gone and fail with a refused connection, which checkout turns into a 502. A retry in checkout for idempotent calls, or a `preStop` delay so pods leave the endpoints before they stop, would remove most of them.
2. Without a timeout, every order would hang until the client's own timeout, here 3 seconds in `loadgen`, and checkout would hold a thread per waiting order, so a slow dependency would exhaust checkout itself. With 30 seconds the same happens, only slower to notice. A good timeout is a little above the dependency's normal p99, so it cuts hangs without cutting slow but healthy calls.
3. The SLO as an automatic stop condition (abort when the burn rate passes a threshold), a blast radius the budget affords, an owner on call who knows it runs, and evidence from staging that the service survives it. The experiment also needs a budget: if the night run spends 2% of the error budget each time, it uses 60% a month.
4. Put the fault on checkout's side and limit it with a `target` and `direction: to`, so only packets from checkout to payments' pods get the delay. Task 6.3.1 does exactly that, and its check proves that the client still reaches payments fast.

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

The reset deletes every experiment first, while Chaos Mesh still runs, because experiments carry finalizers that only the controller removes, and the controller undoes each fault on the way. Then it uninstalls the release, deletes the `chaos-mesh` namespace and the 23 CRDs that Helm leaves behind, and finally `course-sre`.
