---
name: course-module
description: Build or extend a module of this repo's course (platform-engineering/<level>/NN-*.md) the way every existing module is built - installed step by step on the live lab, every step and answer tested, verify.sh checks, reset.sh cleanup, glossary and README updates. Use when asked to add a course module, a lab, an exercise, or a new tool to the course, or to bring an existing module up to standard.
---

# Building a course module

A module is finished only when a learner follows it on a fresh lab and sees exactly what the text promises. So do everything below, and run everything on the live cluster before you write it down.

## 1. Before writing anything

- **Read two finished modules** as the reference for structure and tone: `platform-engineering/2-intermediate/22-gitops-with-argocd.md` (a tool installed and used) and `platform-engineering/2-intermediate/23-prometheus-and-alerting.md` (concepts plus a measured incident).
- **Pick the number, the level and the domain.** The course is one path in four level folders, and each level groups its modules into domains, which the level's `README.md` lists as `##` sections: `1-foundations/` holds the application basics (33 to 37) and the mesh basics, `2-intermediate/` the mesh in practice, platform operations and a secure cluster (38, 39), `3-advanced/` hardening, supply chain, runtime security and platform internals, and `4-ai/` AI workloads. `kernel-and-host/` sits outside the levels and holds module 44, the tasks that need a VM with a kernel of its own. Put the new module under the domain and level that fit, and give it the next free number, 45 at the time of writing, with the `NN-` prefix in its file name, because `verify.sh NN`, `task.sh NN.N` and every "Module NN" reference go by that number. Never renumber a module. Name modules by what they teach, never by an exam: exam names appear only in the course README's note for exam candidates. Modules after 19 must work after `./platform-engineering/reset.sh` with only module 0 behind them. Use their own namespace, `course-<topic>`, and stay out of `shop` unless the module is about the mesh.
- **Pick versions at least two weeks old.** Read release dates from the Helm index (`~/Library/Caches/helm/repository/<repo>-index.yaml`, field `created`). If every release shows the same date, the index was regenerated; pick a release line that's clearly older. Pin the exact chart version everywhere.
- **Check memory.** The user's Mac has 24 GB and the lab uses about 5 GB. Give every new pod requests and limits, and say in the module how much it adds.

## 2. Build it on the lab, step by step

Install the tool the way the learner will: `helm install` with a values file in `platform-engineering/manifests/NN-*.yaml`, or `kubectl apply`. Run every command in the module text, in order, and copy real output into the text. Never write "you should see" from memory.

Things that bit earlier modules, check each:

- **Install back ends before the apps that send to them.** An OpenTelemetry exporter that starts before its Collector backs off for minutes.
- **Read every warning the install prints.** Renamed components, deprecated fields, disabled features (Kyverno's PolicyExceptions are off by default). Fix the values file so the module teaches current names.
- **Memory limits:** watch restarts (`kubectl get pod -o jsonpath='{.status.containerStatuses[0].restartCount}'`). Tempo got OOM-killed at 384 MiB by one query.
- **Things that outlive a namespace delete:** ClusterRoles and bindings from Helm presets, webhooks, CRDs, Grafana data sources and alert rules provisioned into Grafana's database. List them right after the install.
- **Slow propagation:** a new PodMonitor or Alertmanager config reaches Prometheus through a Secret, which took up to four minutes. Tell the learner, and poll in checks.
- **Apps that ignore settings:** the shop's backend image hard-codes `service.name`. Check what really arrives, not what the manifest asks for.

## 3. Write the module

File `platform-engineering/<level>/NN-topic.md`, with these sections in this order. The file sits one folder below `platform-engineering/`, so its links start with `../` for the glossary (`../glossary.md`) and `../../` for the repo (`../../docs/diagrams/chapters/NN-slug.svg`), and a link to a module in another level folder goes through its folder (`../2-intermediate/22-gitops-with-argocd.md`).

1. `# Module NN: title`, the glossary pointer line, and **`**Before this module:**`** with the modules to read first and whether Istio is needed.
2. An opening paragraph: the real-world problem, then what the module does. Then `Time: about N minutes.` and the memory it adds.
3. `## Concept: ...` sections, usually two, each with a diagram (see **Diagrams** below) and often a table.
4. `## The bigger picture: ...`: why the industry does it this way, where it's heading.
5. `## Why this way`: bold questions with short answers, one per design decision in the module.
6. `## Do it`: numbered `### N. step` sections. Each has commands, then **What you should see.** with real output and the numbers measured in the test run ("in the test run, 228 seconds"). Explain surprises; they're the best part.
7. `## Investigate`: four questions, then the answers inside `<details>`. Check every answer against the cluster.
8. `## Clean up`: `./platform-engineering/reset.sh` and what it removes.

**Language:** B2 English, written like a conversation. Follow the unslop rules: no em dashes, no "can/cannot/could", no passive voice, dynamic verbs, varied sentence length. Run this before finishing:

```bash
grep -nE "\b(can|cannot|can't|could)\b|—|–" platform-engineering/*/NN-*.md
grep -nE "\b(is|are|was|were|be|been|being) [a-z]+ed\b" platform-engineering/*/NN-*.md
```

**Explain, don't compress, and connect.** The course follows the ByteByteGo newsletter's style: a good engineer explaining to a colleague, as a story that reasons its way forward. A paragraph that names eight components in four correct sentences teaches nothing, and a run of short disconnected sentences teaches nothing either.

- Problem first, then the mechanism, then the name: say what goes wrong or what is needed, how the fix works, and only then what it's called.
- Write connected paragraphs. Sentences mostly 15 to 25 words, joined by the logic ("because", "so", "which means", "much like"). Avoid runs of sentences under 10 words; aim for fewer than one in five.
- One new term per sentence at most, defined in plain words where it first appears. Explain a technical detail by its effect ("expires after a day, so a stolen one stops working quickly"), not by its label ("short-lived X.509").
- Carry one worked example through a concept (for example the frontend calling the backend), and end the concept with what it means for the next step or module.
- One everyday comparison for each hard idea ("like a passport carries the issuing country's stamp").
- Don't personify components. Plain verbs: "the backend checks the caller", "the proxy rejects the call". Never "the backend wants to know" or "an IP address doesn't answer that question".
- Never describe the page or its styling in the text ("the yellow box", "on a brown card"). Say what the reader gets.
- Numbers only when the text uses them; no trivia. Calculations: intuition first, then a short walk-through in words with round numbers.
- More than about three technical names in a paragraph: cut the ones the point doesn't need.
- A process may still open with a short numbered overview (3 to 7 steps), but the explanation around it is connected prose.
- Walk command output step by step, in the same order as the overview.

Before and after, the target voice:

> Before: "A pod needs a name that other pods trust, and the name must survive restarts. Kubernetes already gives every pod one: its ServiceAccount. A pod uses its ServiceAccount to prove who it is to the API server."
>
> After: "Before the backend serves an order, it should check which workload sent the request. Allowing every caller that reaches port 8000 is too loose for a service that holds customer orders. The pod's IP address is no good as proof of who is calling: pods restart and get new addresses all the time, so the IP the frontend used a minute ago may belong to a different pod now."

**Values differ per run.** Quote real output, but never hard-code an IP or pod name in a command: look it up (`SVCIP=$(kubectl ... -o jsonpath=...)`). Say "in the test run" next to measured numbers.

**Diagrams.** Draw every diagram with the kit in `docs/diagrams/bbg.py`, in a script `docs/diagrams/chapters/make-NN.py` that writes `NN-slug.svg` and `.excalidraw`. Copy the patterns in `docs/diagrams/make-life-of-a-request.py` and `docs/diagrams/chapters/make-02.py`. No mermaid.

A course diagram is a structure diagram, not a chain of boxes. First draw where things run, then draw the flow on top of it:

- Structure: nest the frames the reader knows from Kubernetes. `c.frame(..., kind)` draws `host` (your Mac), `cluster`, `node`, `ns` (a namespace), `pod` and `group` (a dashed set), and `c.band()` draws a shared layer such as the kernel or ztunnel. Put containers inside their pod, iptables chains and eBPF programs inside the kernel band, controllers in the control plane and agents on the node.
- Flow: draw the request or the data on top of that structure with `c.connect(a, b, ...)`, which starts and ends exactly on box edges and runs straight or with right-angle elbows. Use `fa`/`fb` to line two edges up so the arrow runs straight, `via` for a hand-routed path and `mid` for the x or y of a jog.
- Steps: put `c.step()` circles on the flow where order matters, numbered exactly like the numbered list in the prose next to the image. A second numbered list in the same picture gets its own colour (`c.step(..., col=TEAL, ink=WHITE)`) and a key.
- Decisions and failures: `c.diamond()` for a decision, `c.mark(ok=False)` where a check refuses something, a red box for the error the caller gets back.
- Each picture lets the reader point at it and say "the request is here now". If the diagram reads as a left-to-right row of boxes, add the structure it is missing.

Style, which the kit gives you when you use its primitives:

- Light theme on a white page, no frame or shadow around the figure. Pastel fills with one strong accent per kind of thing, thin strokes, rounded corners.
- Colours mean kinds of things: SLATE apps and clients, BLUE proxies (Envoy, ztunnel, waypoint, gateways), PURPLE control plane, GREEN kernel and networking, ORANGE storage, RED security decisions (PINK for admission and crypto), TEAL node agents and DNS.
- Box label: 1 to 3 words. Sub-line: at most 4 short words (an address, a port). Arrow label: at most 4 words. Captions: one short sentence or none. Detail belongs in the prose.
- Canvas about 1600 wide, text at least 15 px, so it stays readable at page width.

Alignment rules:

- Arrows start and end on an edge, never inside a box or in empty space, and run horizontally or vertically.
- Labels never sit on a line, a frame label or another label. Flow labels carry a white halo, and a frame's label moves to the right corner (`right=`) when an arrow crosses its left side.
- Leave at least 40 px between parallel arrows and between boxes, and keep frames free of large empty areas.

Render and look before you embed it. Pad the SVG to a square so Quick Look shows all of it (`qlmanage -t -s 1100 -o <dir> file.svg`), open the PNG, and fix every overlap and misaligned arrow before you commit.

**Define every term.** Add a glossary entry for each new term to `platform-engineering/glossary.md`, under a section for the topic, ending with "Module NN."

## 4. verify.sh

Add `module_NN()` to `platform-engineering/verify.sh`, before the `# Module 21 upgrades k3s` comment. It replays the module from a clean lab and checks each claim the text makes.

- Start with `section "NN: title"` and `baseline`; end with `baseline` and one check that the reset removed everything, including the leftovers from step 2.
- `expect "description" "$actual" 'regex'` for values, `between "description" "$n" min max` for counts. Use ranges, never exact counts or timings.
- **Poll, never sleep and hope.** Write a small loop: `for _ in $(seq 1 36); do v=...; [[ $v =~ ok ]] && break; settle 5; done`.
- A poll on "Succeeded" must check the new revision, not the previous operation's status.
- Start background load with `cmd & pid=$!; disown "$pid"` so bash prints no "Terminated" noise.
- **macOS runs bash 3.2:** escaped quotes inside `"$( ... )"` break. Build queries in a variable first.
- Add the module number to the default list (`modules=(0 1 2 ...)`) only if it's safe to repeat and needs nothing outside the lab (no Ollama, no one-way upgrade).

Run `./platform-engineering/verify.sh NN` until it passes, then run it again from a clean lab.

## 5. reset.sh

Add a cleanup block to `platform-engineering/reset.sh` above the previous module's, commented `# Module NN: ...`.

- `helm uninstall` before deleting the namespace, guarded by `helm status`.
- Delete cluster-scoped leftovers by name, with `--ignore-not-found`.
- Grafana objects are read-only once provisioned and survive their ConfigMap. Remove a data source by replacing its ConfigMap with a `deleteDatasources` file, waiting until Grafana drops it, then deleting the ConfigMap. Remove alert rules and folders through Grafana's API from inside its pod (see module 24's block).
- Every line must succeed when the module was never run.

## 6. Shell traps while building

- The Bash tool runs zsh: a command stored in a variable doesn't word-split. Use a function.
- Text with `${...}` or `$${...}` in a heredoc trips the safety check. Write such files with the Write tool.
- Don't chain `sleep`; poll a condition, or run long jobs in the background.
- The user may run `verify.sh` themselves. Check `ps` for `verify.sh` before touching the cluster.

## 7. Finish

1. `platform-engineering/README.md`: a row under the module's domain in the table of its level, the routes map and the recommended order. Add the module under its domain in its level folder's `README.md` too.

A module with timed tasks on the practice cluster, like 33 to 44, follows the same parts but replaces `verify.sh` with task functions: `setup_D_N`, `check_D_N` and `solve_D_N` in `platform-engineering/practice/apps/tasks/0D.sh` or `practice/security/tasks/0D.sh`, and the module number in the `resolve` and `module_id` functions of `platform-engineering/task.sh`, so that `./platform-engineering/task.sh check NN.N` finds it. A task that needs its own kernel goes into module 44 and the `KERNEL_TASKS` list of `task.sh`.
2. Module 27 loads the README, the glossary, start-here and the lab modules 0 to 32 into one ConfigMap, which holds at most 1 MiB. A new lab module needs its number in that glob, in module 27's step 3 and in `module_27` of `verify.sh`. Check the size after adding a module: `kubectl create configmap x --dry-run=client -o yaml $(printf -- '--from-file=%s ' platform-engineering/{README,glossary,start-here}.md platform-engineering/*/[0-2][0-9]-*.md platform-engineering/*/3[0-2]-*.md) | wc -c`, and update the numbers in module 27's step 3.
3. `README.md` and `docs/lab-guide.md` if the module adds a UI, a port or a credential (the password table).
4. **Never push while a test runs:** a push makes ArgoCD resync `istio-config` and wipes the exercise in progress.
5. Rebuild and run the full check: `./scripts/teardown.sh --yes && ./scripts/provision.sh && ./platform-engineering/verify.sh`. Record the total in `README.md`.
6. Commit with a message that says what the module teaches and the test result, ending with the co-author line.
7. Leave the lab on the baseline: `./platform-engineering/reset.sh`, then `./scripts/port-forward.sh`.
