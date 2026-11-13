---
name: course-module
description: Build or extend a module of this repo's course (course/NN-*.md) the way every existing module is built - installed step by step on the live lab, every step and answer tested, verify.sh checks, reset.sh cleanup, glossary and README updates. Use when asked to add a course module, a lab, an exercise, or a new tool to the course, or to bring an existing module up to standard.
---

# Building a course module

A module is finished only when a learner follows it on a fresh lab and sees exactly what the text promises. So do everything below, and run everything on the live cluster before you write it down.

## 1. Before writing anything

- **Read two finished modules** as the reference for structure and tone: `course/22-gitops-with-argocd.md` (a tool installed and used) and `course/23-prometheus-and-alerting.md` (concepts plus a measured incident).
- **Pick the number and the prerequisites.** Modules after 19 must work after `./course/reset.sh` with only module 0 behind them. Use their own namespace, `course-<topic>`, and stay out of `shop` unless the module is about the mesh.
- **Pick versions at least two weeks old.** Read release dates from the Helm index (`~/Library/Caches/helm/repository/<repo>-index.yaml`, field `created`). If every release shows the same date, the index was regenerated; pick a release line that's clearly older. Pin the exact chart version everywhere.
- **Check memory.** The user's Mac has 24 GB and the lab uses about 5 GB. Give every new pod requests and limits, and say in the module how much it adds.

## 2. Build it on the lab, step by step

Install the tool the way the learner will: `helm install` with a values file in `course/manifests/NN-*.yaml`, or `kubectl apply`. Run every command in the module text, in order, and copy real output into the text. Never write "you should see" from memory.

Things that bit earlier modules, check each:

- **Install back ends before the apps that send to them.** An OpenTelemetry exporter that starts before its Collector backs off for minutes.
- **Read every warning the install prints.** Renamed components, deprecated fields, disabled features (Kyverno's PolicyExceptions are off by default). Fix the values file so the module teaches current names.
- **Memory limits:** watch restarts (`kubectl get pod -o jsonpath='{.status.containerStatuses[0].restartCount}'`). Tempo got OOM-killed at 384 MiB by one query.
- **Things that outlive a namespace delete:** ClusterRoles and bindings from Helm presets, webhooks, CRDs, Grafana data sources and alert rules provisioned into Grafana's database. List them right after the install.
- **Slow propagation:** a new PodMonitor or Alertmanager config reaches Prometheus through a Secret, which took up to four minutes. Tell the learner, and poll in checks.
- **Apps that ignore settings:** the shop's backend image hard-codes `service.name`. Check what really arrives, not what the manifest asks for.

## 3. Write the module

File `course/NN-topic.md`, with these sections in this order:

1. `# Module NN: title`, the glossary pointer line, and **`**Before this module:**`** with the modules to read first and whether Istio is needed.
2. An opening paragraph: the real-world problem, then what the module does. Then `Time: about N minutes.` and the memory it adds.
3. `## Concept: ...` sections, usually two, each with a diagram (see **Diagrams** below) and often a table.
4. `## The bigger picture: ...`: why the industry does it this way, where it's heading.
5. `## Why this way`: bold questions with short answers, one per design decision in the module.
6. `## Do it`: numbered `### N. step` sections. Each has commands, then **What you should see.** with real output and the numbers measured in the test run ("in the test run, 228 seconds"). Explain surprises; they're the best part.
7. `## Investigate`: four questions, then the answers inside `<details>`. Check every answer against the cluster.
8. `## Clean up`: `./course/reset.sh` and what it removes.

**Language:** B2 English, written like a conversation. Follow the unslop rules: no em dashes, no "can/cannot/could", no passive voice, dynamic verbs, varied sentence length. Run this before finishing:

```bash
grep -nE "\b(can|cannot|can't|could)\b|—|–" course/NN-*.md
grep -nE "\b(is|are|was|were|be|been|being) [a-z]+ed\b" course/NN-*.md
```

**Explain, don't compress.** The course follows the ByteByteGo newsletter's style. A paragraph that names eight components in four correct sentences teaches nothing.

- Problem first, then the name: say what goes wrong or what is needed, then the tool that fixes it.
- A process opens with a short numbered overview (3 to 7 steps, one actor and one action each), then goes deeper step by step.
- One idea per sentence, no fragments, at most one new term per sentence. Define a term in plain words where it first appears ("X is a ... that ...").
- More than about three technical names in a paragraph: cut the ones the point doesn't need, or give each its own sentence.
- Give the why as a purpose clause ("so the reply finds its way back"), and one everyday comparison for each hard idea.
- Walk command output step by step, in the same order as the overview.

**Values differ per run.** Quote real output, but never hard-code an IP or pod name in a command: look it up (`SVCIP=$(kubectl ... -o jsonpath=...)`). Say "in the test run" next to measured numbers.

**Diagrams.** Draw every diagram with the kit in `docs/diagrams/bbg.py`, in a script `docs/diagrams/chapters/make-NN.py` that writes `NN-slug.svg` and `.excalidraw`. Copy the patterns in `docs/diagrams/make-life-of-a-request.py`. No mermaid.

- Box label: 1 to 3 words. Sub-line: at most 4 short words (an address, a port). Arrow label: at most 4 words. Captions: one short sentence or none. Detail belongs in the prose.
- Circled step numbers only where order matters, and they match the numbered steps in the text.
- Colours mean kinds of things: SLATE apps, BLUE proxies, PURPLE control plane, GREEN kernel and networking, ORANGE storage, RED or PINK security decisions, TEAL node agents and DNS.
- Render and look before you embed it. Pad the SVG to a square so Quick Look shows all of it, then open the PNG.

**Define every term.** Add a glossary entry for each new term to `course/glossary.md`, under a section for the topic, ending with "Module NN."

## 4. verify.sh

Add `module_NN()` to `course/verify.sh`, before the `# Module 21 upgrades k3s` comment. It replays the module from a clean lab and checks each claim the text makes.

- Start with `section "NN: title"` and `baseline`; end with `baseline` and one check that the reset removed everything, including the leftovers from step 2.
- `expect "description" "$actual" 'regex'` for values, `between "description" "$n" min max` for counts. Use ranges, never exact counts or timings.
- **Poll, never sleep and hope.** Write a small loop: `for _ in $(seq 1 36); do v=...; [[ $v =~ ok ]] && break; settle 5; done`.
- A poll on "Succeeded" must check the new revision, not the previous operation's status.
- Start background load with `cmd & pid=$!; disown "$pid"` so bash prints no "Terminated" noise.
- **macOS runs bash 3.2:** escaped quotes inside `"$( ... )"` break. Build queries in a variable first.
- Add the module number to the default list (`modules=(0 1 2 ...)`) only if it's safe to repeat and needs nothing outside the lab (no Ollama, no one-way upgrade).

Run `./course/verify.sh NN` until it passes, then run it again from a clean lab.

## 5. reset.sh

Add a cleanup block to `course/reset.sh` above the previous module's, commented `# Module NN: ...`.

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

1. `course/README.md`: a table row, the routes map and the recommended order.
2. `README.md` and `docs/lab-guide.md` if the module adds a UI, a port or a credential (the password table).
3. **Never push while a test runs:** a push makes ArgoCD resync `istio-config` and wipes the exercise in progress.
4. Rebuild and run the full check: `./scripts/teardown.sh --yes && ./scripts/provision.sh && ./course/verify.sh`. Record the total in `README.md`.
5. Commit with a message that says what the module teaches and the test result, ending with the co-author line.
6. Leave the lab on the baseline: `./course/reset.sh`, then `./scripts/port-forward.sh`.
