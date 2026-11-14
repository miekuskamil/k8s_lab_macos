# CKS 05: Supply chain security (20%)

> New to a term here, like SBOM or ImagePolicyWebhook? The [glossary](../../platform-engineering/glossary.md#cks-exam-track) explains every term this track uses.

**Before this domain:** the [practice cluster](../README.md#the-practice-cluster) running. The course's [module 26](../../platform-engineering/26-kyverno-policy-as-code.md) explains admission webhooks, which task 5 configures by hand.

Most of the code in a container image came from someone else: a base image, system packages, language libraries. A vulnerable or poisoned piece anywhere in that chain ends up running in your cluster with your permissions. This domain checks the chain at each step, from the Dockerfile to the API server's front door. It has ten tasks and takes about 1 hour 40 minutes.

## The domain in one table

Each task checks the chain at one point:

| Question | Tool | Task |
|---|---|---|
| Does the image carry more than the app needs? | a smaller base image, a non-root `USER` | 1 |
| Which images hold known vulnerabilities? | trivy | 2, 9 |
| What exactly is inside an image? | an SBOM from bom or trivy | 3, 10 |
| Does the manifest ask for dangerous settings? | kubesec | 4 |
| Does the cluster run only images from trusted registries? | ImagePolicyWebhook | 5, 6, 7 |
| Does the cluster run exactly the build you checked? | an image digest | 8 |

## Concept: the supply chain, from source to running pod

Most of the code in a container image came from someone else: a base image, system packages, language libraries, build tools. Your own code is often the smallest part. A **software supply chain** is everything that touches the code on its way from a developer's editor to a running pod. A vulnerable or poisoned piece anywhere in that chain ends up running in your cluster with your permissions.

Attackers know this. Breaking into one popular library or one build system reaches thousands of victims at once, which is cheaper than attacking each of them. Defenders answer with a check at each step.

![Supply chain checks: kubesec on the Dockerfile and manifests, trivy and bom at build, cosign at the registry, ImagePolicyWebhook at admission, Falco on the node](../../docs/diagrams/chapters/cks-supply-chain.svg)

An image travels through five places before it runs, and each place has its own check:

1. The Dockerfile and the Kubernetes manifest. A small base image and a non-root user shrink what an attacker finds. **kubesec** reads the manifest and scores its security settings.
2. The build. **trivy** lists known vulnerabilities in the image, and an **SBOM** lists everything inside it.
3. The registry. A signature, made with a tool such as cosign, proves who built the image.
4. The API server. An admission check refuses images from registries you don't trust.
5. The node. Falco watches what the container does, which is [domain 06](06-monitoring-logging-runtime-security.md#task-2-catch-a-shell-with-falco).

No single check is enough. trivy only knows vulnerabilities somebody already found. A signature proves where an image came from, not that it's safe. The admission check is the only one the cluster enforces by itself. Think of food safety: the farm, the factory, the truck and the shop each check something different, and a scandal usually means one of them skipped its check.

## Concept: image layers and small images

A container image is a stack of **layers**. Each instruction in a Dockerfile that changes files, such as `RUN apt-get install` or `COPY`, adds one layer: a tar archive of the files it added or changed. At run time, the container runtime stacks the layers into one file system, with a thin writable layer on top. Two images that share a base share its layers, which saves disk and download time.

Layers explain two facts that matter for security:

1. Everything in every layer ships with the image. A file that a later layer deletes still sits in the earlier layer, and anybody who pulls the image extracts it. A password copied in and deleted two lines later is still in the image.
2. Every package in any layer counts. Scanners read the package lists of the whole stack, and so do attackers.

Every package is code an attacker might use. `curl` and `wget` download tools. A shell runs commands. A package manager installs more. Each one also brings its own CVEs, so a smaller image means fewer findings and fewer emergency rebuilds. The test run built the same three-line Python app twice:

| Base | Extra packages | Runs as | Size |
|---|---|---|---|
| `ubuntu:latest` | python3, curl, wget, netcat, vim | root | 425 MB |
| `python:3.13-alpine` | none | `nobody` (65534) | 74.4 MB |

Three habits get you most of the way:

1. Pin the base image to a tag or digest, because `latest` changes under you.
2. Pick a minimal variant: `-alpine`, `-slim`, or a **distroless** image. A distroless image holds the app's runtime and its libraries, and no shell, no package manager and no tools.
3. End with a `USER` that isn't root.

A **multi-stage build** helps with the second habit. The first stage has compilers and build tools. The last stage copies only the finished program into a minimal base, so the build tools never ship.

**What this stops.** A small image stops an attacker who gets in from finding download tools, a shell or a package manager, and it stops most of the CVE findings that come with packages the app never uses.

**Exam traps.** Alpine still ships `wget` and `apk` through BusyBox, which the test run confirmed. Only a distroless image removes those. And the exam often wants several fixes in one Dockerfile: the pinned base, the removed packages, and the `USER` line.

## Concept: vulnerability scanning

A **CVE** (Common Vulnerabilities and Exposures entry) is a public record of one known security bug, with an ID such as `CVE-2024-6387` and a severity. The severity usually comes from a CVSS score, a number from 0 to 10, grouped into `LOW`, `MEDIUM`, `HIGH` and `CRITICAL`.

**trivy** is a scanner from Aqua Security. It works in four steps:

1. It downloads its vulnerability database the first time it runs, which took about 30 seconds in the test run. The database merges advisories from Linux distributions, from language ecosystems and from the national CVE database.
2. It unpacks the image and reads the package lists inside: the operating system packages and the language libraries.
3. It compares each package version with the database.
4. It prints each finding with its severity, the installed version, and the fixed version when one exists.

The last column matters. A **fixable** finding has a newer package version that closes the bug, so a rebuild removes it. An **unfixable** finding has no fix yet, so the only choices are to accept it, change the base image or drop the package. `--ignore-unfixed` hides the second kind, which suits a CI gate that must not fail on something nobody repairs.

| Image | CRITICAL findings in the test run |
|---|---|
| `nginx:1.19.0` | 44 |
| `redis:6.0.5` | 22 |
| `nginx:1.27-alpine` | 3 |
| `busybox:1.36` | 0 |
| `registry.k8s.io/pause:3.10` | 0 |

**What this stops.** Scanning stops images with known, published bugs from reaching production unnoticed. Attackers read the same CVE lists.

**Exam traps.** The numbers grow over time without any change to the image, because researchers keep finding bugs in old code. An exam task usually says "delete the pods whose image has CRITICAL vulnerabilities". Scan each distinct image once, not each pod, and use `--severity CRITICAL` to keep the output short. `trivy image` prints nothing for a target without findings, so an empty `Total` line means clean.

## Concept: tags move, digests don't

A tag such as `nginx:1.27-alpine` is a name that the image's owner moves to a new build whenever they like. Two nodes that pull the same tag a week apart may run different code. A **digest** is the SHA-256 checksum of the image's manifest, written `nginx@sha256:6564...`. Change one byte of the image, and the digest changes. So an image named by digest always means exactly one build, and a registry that got broken into has no way to swap it silently.

The digest of the image a pod runs sits in the pod's status, in `containerStatuses[].imageID`. `crictl inspecti <image>` on the node shows it too, as `repoDigests`. Task 8 pins a Deployment to one.

**What this stops.** A digest stops a moved tag, or a tampered registry, from changing what runs in the cluster. It also makes the scan meaningful: a digest proves that what runs is what trivy saw, which a tag never proves.

**Exam traps.** With both a tag and a digest in the image name, the runtime ignores the tag. In task 8, both `nginx@sha256:...` and `nginx:1.27-alpine@sha256:...` worked.

## Concept: SBOMs, the list of ingredients

A scan answers "what's wrong today". It doesn't answer "where do we use library X", which is the first question on the day a big new CVE lands. Rescanning every image in every registry takes hours.

An **SBOM** (software bill of materials) is a machine-readable list of every package in an image, with versions and licenses. It works like the list of ingredients on food packaging. When a new CVE arrives, a team with SBOMs searches files instead of rescanning images. Two formats dominate:

1. **SPDX**, from the Linux Foundation, also an ISO standard.
2. **CycloneDX**, from OWASP, built for security use.

The exam allows the docs of **bom**, a Kubernetes SIG tool that writes SPDX. trivy writes both formats, and also scans an SBOM file directly with `trivy sbom`.

**What this stops.** An SBOM stops the slow, blind search on the day of a new CVE. It also documents what you shipped, which customers and regulators increasingly ask for.

**Exam traps.** Tools count differently. In task 3, bom listed 266 packages and trivy 172 components for the same image, because bom also lists every Go module inside the Kubernetes binaries. In task 10, scanning three SBOM files took under a second each and needed no registry: `app-2.cdx.json` showed `Total: 44 (CRITICAL: 44)`.

## Concept: static analysis of manifests

**Static analysis** reads a file without running it. kubesec reads a Kubernetes manifest. It gives points for good settings, such as `readOnlyRootFilesystem` or resource limits, and marks dangerous ones as critical, such as `privileged` or `hostPID`. KubeLinter, also named in the curriculum, works the same way with a different rule set. Tools such as hadolint do the same for Dockerfiles.

Static analysis runs earliest in the chain, in the editor or the pull request, where a fix costs a minute. The same mistake found by admission costs a failed deployment, and found by Falco costs an incident.

**What this stops.** It stops dangerous settings from leaving the developer's machine, before any cluster sees them.

**Exam traps.** A pod with any critical finding fails, whatever its points. In task 4, the setup's manifest scored `-39` with `Privileged` and `HostPID`, and the fixed one scored 10.

## Concept: admission, the cluster's front door

Every check so far runs outside the cluster: in CI, on a laptop, in a registry. The cluster trusts none of them by default. A developer who skips CI, or an attacker with `create pods` rights, deploys whatever image they like. Admission control, the step of [domain 02's request chain](02-cluster-hardening.md#concept-one-request-six-steps) that reads the object, is the only check the cluster enforces on itself.

### Allowing only approved registries

Two ways to restrict images come up in the exam:

1. **ImagePolicyWebhook**, a built-in admission plugin. For every new pod, the API server POSTs an `ImageReview` with the image names to an outside service, and that service answers allowed or denied.
2. A policy engine such as Kyverno, or a ValidatingAdmissionPolicy, which the course's [module 26](../../platform-engineering/26-kyverno-policy-as-code.md) covers. These read the whole pod and express rules such as "images only from `registry.example.com`" as cluster objects.

![The API server sends an ImageReview to the policy back end and gets a verdict. When the back end doesn't answer, defaultAllow decides between failing closed and failing open](../../docs/diagrams/chapters/cks-image-policy.svg)

The ImagePolicyWebhook flow has four steps:

1. A client creates a pod.
2. At admission, the API server sends an `ImageReview` with the pod's images to the back end.
3. The back end answers with a verdict: allowed, or denied with a reason. The API server caches the answer for `allowTTL` or `denyTTL` seconds.
4. If the back end doesn't answer, `defaultAllow` decides.

ImagePolicyWebhook needs three files, and the exam usually hands you the last two half-filled:

1. The API server flags `--enable-admission-plugins=...,ImagePolicyWebhook` and `--admission-control-config-file=<file>`.
2. The admission configuration, an `AdmissionConfiguration` that points to a kubeconfig and sets the TTLs, the retry backoff and `defaultAllow`.
3. That kubeconfig, whose `cluster.server` is the webhook's URL and whose `certificate-authority` checks the webhook's certificate.

### Fail closed or fail open

Every admission webhook faces the same question: what happens when the referee doesn't show up? **Fail closed** means refuse everything until the check works again. **Fail open** means let everything through. `defaultAllow: false` fails closed, and `defaultAllow: true` fails open.

Failing closed is the safe choice for a security rule, and it's why the webhook needs high availability in production. The test run stopped the back end with `defaultAllow: false`, and every new pod failed: `Post "https://localhost:8443/review?timeout=30s": dial tcp [::1]:8443: connect: connection refused`. Failing open keeps deployments flowing during an outage, and quietly switches the rule off.

When the webhook goes wrong, the symptoms depend on which file is wrong:

| Fault | What you see |
|---|---|
| a path in the admission configuration or the API server flag that doesn't exist, or isn't mounted | the API server exits at start; `crictl logs` names the file |
| the webhook kubeconfig's `certificate-authority` doesn't sign the back end's certificate | the API server runs, and every new pod fails with an `x509` error, because the call fails and `defaultAllow: false` refuses |
| the back end is down, with `defaultAllow: true` | everything works, including images the policy forbids. Nobody notices |

The practice cluster runs a small back end on `cks-cp` at `https://localhost:8443/review`, from `certs/cks/cluster/image-policy/`. It allows images from the prefixes in `/etc/image-policy/allowed-registries`, refuses `latest` and untagged images, and logs each verdict to `journalctl -u image-policy`.

**What this stops.** An admission rule stops images from unknown registries, and `latest` tags, from running in the cluster, whoever deploys them and whatever CI they skipped.

**Exam traps.** The last row of the fault table is the dangerous one, and task 7 sets it up. A webhook that fails open looks healthy until somebody checks it with an image it should refuse. In the test run, `quay.io/evil/miner:1` got `pod/probe created` while the back end was down. A missing volume mount is the most common reason the API server doesn't come back: the test run's log said `couldn't init admission plugin "ImagePolicyWebhook": stat /etc/kubernetes/policy-webhook/kubeconfig.yaml: no such file or directory`.

## Concept: signatures

A registry rule says where an image comes from. It doesn't prove who built it. An attacker who steals a CI token pushes a poisoned image to your own trusted registry, and the rule lets it in.

A **signature** ties an image digest to the key or identity that built it. Signing works in three steps:

1. The build system signs the image's digest with a private key, after the scans pass.
2. The signature goes to the registry, stored next to the image.
3. At admission, a policy checks the signature with the matching public key, and refuses images without a valid one.

**cosign**, from the Sigstore project, does steps 1 and 2. It signs with a key pair (`cosign sign --key cosign.key <image>@<digest>`, then `cosign verify --key cosign.pub <image>`) or keyless. Keyless signing uses a short-lived certificate tied to an identity, such as the CI system's login, and writes the signature to a public transparency log, an append-only record that anybody checks later. Kubernetes signs its own release binaries this way. Kyverno's `verifyImages` rule or the Sigstore policy controller does step 3.

Sign the digest, not the tag. A tag moves, so a signature on a tag says nothing about the build that runs tomorrow.

The practice cluster doesn't run a signing flow, because it needs a registry you push to. Know the commands and the order.

**What this stops.** A signature check stops images that your build system never produced, even when they sit in your own registry under a familiar name.

## The bigger picture: trust nothing you didn't check

The supply chain controls answer three different questions. kubesec, small images and scanning ask "is this image any good?". Signatures and digests ask "is this the image we checked?". Admission asks "is the cluster willing to run it?". Each question needs its own tool, because each one fails in its own way.

The industry calls the goal **provenance**: a verifiable record of where every artifact came from and what happened to it on the way. Frameworks such as SLSA describe levels of that, from "a script runs the build" up to "the build runs on a hardened service that signs a record of every input". Real platform teams usually wire it like this: CI builds from a minimal base, scans, writes an SBOM, signs the digest and pushes. A policy engine in every cluster then admits only signed images from the company registry, pinned by digest. Scans keep running on the registry after release, because new CVEs appear for old images every week.

## Why this way

**Why scan at build time and at run time?** A build-time scan sees the image once. The CVE database changes every day, so the same image gets new findings after it shipped. Task 9 scans what the cluster runs today for exactly that reason.

**Why does admission call a webhook instead of reading a list?** Image rules change often and differ per company: registries, tags, signatures, scan results. A webhook keeps that logic outside the API server, where a team updates it without restarting the control plane.

**Why fail closed?** A security rule that switches itself off during an outage protects nothing during the outage, which is exactly when attackers like to act. Failing closed turns a broken check into a visible problem that somebody fixes.

**Why digests when signatures exist?** A signature check runs at admission. The digest makes sure the node then pulls the exact build that passed, and not whatever the tag points to by the time the pull happens.

## Task 1: Shrink a Dockerfile

**Time budget:** 4 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.1
```

> Fix `/root/cks/app/Dockerfile`:
>
> 1. Use `python:3.13-alpine` as the base image.
> 2. Install nothing besides what the base image brings.
> 3. Run the app as user `65534`, not root.
>
> Don't build the image.

<details>
<summary>Solution</summary>

```dockerfile
FROM python:3.13-alpine
COPY app.py /app/app.py
USER 65534
CMD ["python3", "/app/app.py"]
```

The alpine image already has `python3`, so the `RUN` line goes. The `USER root` line goes too, replaced by `USER 65534`. Exam tasks often hide a second `USER root` lower in the file. The last one wins, so read to the end.

</details>

```bash
./certs/cks/task.sh check 5.1
```

```
  PASS  the base image has an explicit tag, not latest
  PASS  the base image is a slim, alpine or distroless variant
  PASS  no RUN line installs curl, wget, netcat or vim
  PASS  the last USER is neither root nor 0
```

## Task 2: Find and remove vulnerable images

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.2
```

> Namespace `scan` runs three pods. Use trivy to find the pods whose image has at least one CRITICAL vulnerability, and delete those pods. Leave the others running.

<details>
<summary>Solution</summary>

List the images, then scan each one:

```bash
k -n scan get pods -o custom-columns=POD:.metadata.name,IMAGE:.spec.containers[0].image
trivy image --severity CRITICAL --quiet nginx:1.19.0 | grep Total
trivy image --severity CRITICAL --quiet redis:6.0.5 | grep Total
trivy image --severity CRITICAL --quiet busybox:1.36 | grep Total
k -n scan delete pod web cache
```

`--quiet` hides the progress bars, and the `Total` line gives the count per target. In the test run, trivy reported 44 CRITICAL findings for `nginx:1.19.0`, 22 for `redis:6.0.5` and none for `busybox:1.36`.

</details>

```bash
./certs/cks/task.sh check 5.2
```

```
  PASS  pod web (nginx:1.19.0, CRITICAL findings) is gone
  PASS  pod cache (redis:6.0.5, CRITICAL findings) is gone
  PASS  pod tools (busybox:1.36, no CRITICAL findings) still runs
```

## Task 3: Write an SBOM

**Time budget:** 5 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.3
```

> For the image `registry.k8s.io/kube-proxy:v1.37.1`:
>
> 1. Write an SPDX JSON SBOM with bom to `/root/cks/kube-proxy.spdx.json`.
> 2. Write a CycloneDX SBOM with trivy to `/root/cks/kube-proxy.cdx.json`.
> 3. Write the version of the package `iptables`, as the SPDX SBOM lists it, to `/root/cks/iptables-version.txt`.

<details>
<summary>Solution</summary>

```bash
cd /root/cks
bom generate --image registry.k8s.io/kube-proxy:v1.37.1 --format json --output kube-proxy.spdx.json
trivy image --format cyclonedx --output kube-proxy.cdx.json registry.k8s.io/kube-proxy:v1.37.1
grep -A3 '"name": "iptables"' kube-proxy.spdx.json | grep -m1 versionInfo
echo 1.8.9-2 > iptables-version.txt
```

bom 0.8.0 writes JSON by default, and `--format tag-value` gives the older text format. Older bom versions defaulted to tag-value, so pass `--format json` anyway. In the test run, bom took 4 seconds and listed 266 packages, trivy listed 172 components, and `iptables` had version `1.8.9-2`. The two tools count differently: bom also lists every Go module inside the Kubernetes binaries.

An SBOM is also something trivy scans later, without the image: `trivy sbom kube-proxy.cdx.json`.

</details>

```bash
./certs/cks/task.sh check 5.3
```

```
  PASS  /root/cks/kube-proxy.spdx.json is SPDX JSON for kube-proxy v1.37.1
  PASS  /root/cks/kube-proxy.cdx.json is a CycloneDX SBOM
  PASS  /root/cks/iptables-version.txt holds the iptables version from the SBOM
```

## Task 4: Static analysis with kubesec

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.4
```

The setup prints kubesec's verdict on the manifest. In the test run: `score -39 critical ['Privileged', 'HostPID']`.

> Fix `/root/cks/report.yaml` so that kubesec reports no critical issue and a score of 8 or more. Then create the pod. It must run.

<details>
<summary>Solution</summary>

```bash
kubesec scan /root/cks/report.yaml | less
```

The `advise` list names the settings that give points. Remove `hostPID` and `privileged`, then add enough of the advice:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: report
  namespace: reports
spec:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    seccompProfile: {type: RuntimeDefault}
  containers:
  - name: report
    image: busybox:1.36
    command: [sleep, 1d]
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: {drop: [ALL]}
    resources:
      requests: {cpu: 10m, memory: 16Mi}
      limits: {cpu: 100m, memory: 32Mi}
```

```bash
kubesec scan /root/cks/report.yaml | grep -E '"score"|"message"'
k apply -f /root/cks/report.yaml
```

In the test run, the score went from -39 to 10. The `sleep` command writes nothing, so `readOnlyRootFilesystem` doesn't stop it.

</details>

```bash
./certs/cks/task.sh check 5.4
```

```
  PASS  kubesec finds no critical issue and scores 8 or more
  PASS  pod report runs in namespace reports
  PASS  the running pod has no hostPID and is not privileged
```

## Task 5: Allow only approved registries

**Time budget:** 10 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.5
```

> An image policy back end runs at `https://localhost:8443/review`. The kubeconfig to reach it is `/etc/kubernetes/policy-webhook/kubeconfig.yaml`.
>
> 1. Write an admission configuration at `/etc/kubernetes/admission/admission-config.yaml` for the ImagePolicyWebhook plugin, with that kubeconfig, TTLs of 50 seconds, a retry backoff of 500 ms, and pods refused when the back end doesn't answer.
> 2. Enable the plugin in the API server.
> 3. Prove that the API server refuses `nginx:latest`.

<details>
<summary>Solution</summary>

The admission configuration comes from the "Using admission controllers" page of the Kubernetes docs:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: ImagePolicyWebhook
  configuration:
    imagePolicy:
      kubeConfigFile: /etc/kubernetes/policy-webhook/kubeconfig.yaml
      allowTTL: 50
      denyTTL: 50
      retryBackoff: 500
      defaultAllow: false
```

In the API server manifest, after a backup:

```yaml
    - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
    - --admission-control-config-file=/etc/kubernetes/admission/admission-config.yaml
```

The API server reads two folders it doesn't mount yet: `/etc/kubernetes/admission` and `/etc/kubernetes/policy-webhook`. Add a `volumeMount` and a `hostPath` volume for each, as in [02, task 3](02-cluster-hardening.md#task-3-restrict-anonymous-access-to-the-api). Forgetting one is the most common reason the API server doesn't come back. The test run left out the `policy-webhook` mount, and `crictl logs` on the exited container said: `couldn't init admission plugin "ImagePolicyWebhook": stat /etc/kubernetes/policy-webhook/kubeconfig.yaml: no such file or directory`.

When the API server answers again:

```bash
k run t1 --image=nginx:latest --dry-run=server
k run t2 --image=busybox:1.36 --dry-run=server -- sleep 1
journalctl -u image-policy -n 5
```

In the test run, the first command failed with `image policy webhook backend denied one or more images: image docker.io/library/nginx:latest has no tag or uses latest`, and the second printed `pod/t2 created (server dry run)`. The back end expands short names the way container runtimes do, so `busybox:1.36` counts as `docker.io/library/busybox:1.36`.

</details>

```bash
./certs/cks/task.sh check 5.5
```

```
  PASS  the API server enables ImagePolicyWebhook
  PASS  the admission configuration sets defaultAllow: false
  PASS  a pod with busybox:1.36 is admitted
  PASS  a pod with nginx:latest is refused
  PASS  a pod from quay.io/evil is refused
```

## Task 6: The webhook's files are wrong

**Time budget:** 8 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.6
```

> Somebody changed the ImagePolicyWebhook configuration, and the API server doesn't come back. Repair it. The plugin stays enabled, pods stay refused when the back end doesn't answer, and the back end at `https://localhost:8443/review` decides again which images run. Its CA certificate is `/etc/kubernetes/policy-webhook/ca.crt`.

<details>
<summary>Solution</summary>

`kubectl` fails, so read the API server's last words:

```bash
crictl ps -a --name kube-apiserver
crictl logs <id of the newest exited container>
```

In the test run, it said:

```
"command failed" err="failed to apply admission: couldn't init admission plugin \"ImagePolicyWebhook\": stat /etc/kubernetes/webhook/kubeconfig.yaml: no such file or directory"
```

`ls /etc/kubernetes/policy-webhook/` shows the real kubeconfig. Fix `kubeConfigFile` in `/etc/kubernetes/admission/admission-config.yaml`. The API server starts, but every new pod now fails:

```
Error from server (Forbidden): pods "x509" is forbidden: Post "https://localhost:8443/review?timeout=30s": tls: failed to verify certificate: x509: certificate signed by unknown authority
```

The kubeconfig's `certificate-authority` points to the cluster's CA, `/etc/kubernetes/pki/ca.crt`, which never signed the back end's certificate. Set it to `/etc/kubernetes/policy-webhook/ca.crt`. The API server reads the kubeconfig only at start, and the manifest didn't change, so restart it the way [04, task 5](04-minimize-microservice-vulnerabilities.md#task-5-rotate-the-encryption-key) does: move the manifest out of the folder and back. Then test:

```bash
k run t --image=quay.io/evil/miner:1 --dry-run=server
```

In the test run, that printed `image policy webhook backend denied one or more images: image quay.io/evil/miner:1 is not from an allowed registry`. The refusal now comes from the back end's policy, not from a broken connection.

</details>

```bash
./certs/cks/task.sh check 5.6
```

```
  PASS  the API server answers
  PASS  ImagePolicyWebhook stays enabled, with defaultAllow: false
  PASS  a pod with busybox:1.36 is admitted
  PASS  a pod from quay.io/evil is refused by the back end
```

## Task 7: The back end is down and nobody noticed

**Time budget:** 6 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.7
```

The setup shows the hole. In the test run: `quay.io/evil/miner:1 today: pod/probe created (server dry run)`.

> The cluster admits images from any registry again. Make the API server refuse new pods whenever the image policy back end doesn't answer. Then bring the back end back, so that it starts at boot too, and approved images run again.

<details>
<summary>Solution</summary>

Two things are wrong, and both have to change:

```bash
grep defaultAllow /etc/kubernetes/admission/admission-config.yaml     # defaultAllow: true
systemctl status image-policy                                         # inactive, disabled
journalctl -u image-policy -n 2
```

```bash
sed -i 's/defaultAllow: true/defaultAllow: false/' /etc/kubernetes/admission/admission-config.yaml
systemctl enable --now image-policy
```

Restart the API server by moving its manifest out and back, as in task 6, and test both sides:

```bash
k run ok --image=busybox:1.36 --dry-run=server -- sleep 1         # created
k run bad --image=quay.io/evil/miner:1 --dry-run=server           # denied
```

`enable --now` does both halves: `--now` starts the service, `enable` makes it start at boot. Fix only `defaultAllow`, and the cluster refuses every new pod, approved or not, until somebody starts the back end. In the test run, the fix took 36 seconds, most of it the API server restart.

</details>

```bash
./certs/cks/task.sh check 5.7
```

```
  PASS  the admission configuration sets defaultAllow: false
  PASS  the image-policy service runs and starts at boot
  PASS  a pod with busybox:1.36 is admitted
  PASS  a pod from quay.io/evil is refused
```

## Task 8: Pin an image by digest

**Time budget:** 4 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.8
```

> Deployment `web` in namespace `pinned` runs `nginx:1.27-alpine`. Change it to name the exact image it runs now by its digest, so that a moved tag never changes what runs.

<details>
<summary>Solution</summary>

Read the digest from the running pod, then set it:

```bash
k -n pinned get pod -l app=web -o jsonpath='{.items[0].status.containerStatuses[0].imageID}'; echo
k -n pinned set image deploy/web nginx=nginx@sha256:<the digest>
k -n pinned rollout status deploy web
```

In the test run, the imageID was `docker.io/library/nginx@sha256:65645c7bb6a0661892a8b03b89d0743208a18dd2f3f17a54ef4b76fb8e2f2a10`. `nginx` in `set image` is the container's name, which `kubectl create deployment` took from the image. Both `nginx@sha256:...` and `nginx:1.27-alpine@sha256:...` work. With both a tag and a digest, the runtime ignores the tag.

</details>

```bash
./certs/cks/task.sh check 5.8
```

```
  PASS  Deployment web names its image by a sha256 digest
  PASS  the digest is the one nginx:1.27-alpine had on the node
  PASS  the Deployment has a ready pod
```

## Task 9: Scan what the cluster runs

**Time budget:** 7 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.9
```

> Namespaces `prod-a` and `prod-b` run four Deployments. Find every image among them that has at least one CRITICAL vulnerability, and write those image names, one per line, to `/root/cks/critical-images.txt`. Scale the Deployments that use them to 0 replicas. Leave the others alone.

<details>
<summary>Solution</summary>

List the images per Deployment, then scan each distinct image once:

```bash
k get deploy -n prod-a -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image
k get deploy -n prod-b -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image
for img in nginx:1.19.0 busybox:1.36 redis:6.0.5 registry.k8s.io/pause:3.10; do
  echo "$img $(trivy image --quiet --severity CRITICAL $img | grep -m1 Total)"
done
printf 'nginx:1.19.0\nredis:6.0.5\n' > /root/cks/critical-images.txt
k -n prod-a scale deploy web --replicas=0
k -n prod-b scale deploy cache --replicas=0
```

In the test run, trivy found 44 CRITICAL findings in `nginx:1.19.0`, 22 in `redis:6.0.5`, and none in `busybox:1.36` or `pause:3.10`. The check runs trivy itself, so it still agrees with you when the database grows. `trivy image` prints nothing for a target without findings, which is why the `Total` line stays empty for the clean images.

</details>

```bash
./certs/cks/task.sh check 5.9
```

```
  PASS  /root/cks/critical-images.txt lists exactly the images with CRITICAL findings
  PASS  the Deployments running those images are scaled to 0
  PASS  the Deployments with clean images keep their replica
```

## Task 10: Which SBOM carries the risk?

**Time budget:** 4 minutes. **Host:** `cks-cp`.

```bash
./certs/cks/task.sh setup 5.10
```

> `/root/cks/sboms/` holds three CycloneDX SBOMs from the build system. Without pulling any image, find the SBOMs that list a package with at least one CRITICAL vulnerability. Write their file names, one per line, to `/root/cks/risky-sboms.txt`.

<details>
<summary>Solution</summary>

`trivy sbom` reads the package list from the file and checks it against the database:

```bash
cd /root/cks/sboms
for f in app-*.cdx.json; do echo "$f: $(trivy sbom --quiet --severity CRITICAL $f | grep -m1 Total)"; done
echo app-2.cdx.json > /root/cks/risky-sboms.txt
```

In the test run, `app-2.cdx.json` showed `Total: 44 (CRITICAL: 44)`, and the other two printed nothing. That's the point of an SBOM: the scan took under a second per file and needed no registry. `--exit-code 1` makes trivy fail when it finds something, which suits a loop or a CI step.

</details>

```bash
./certs/cks/task.sh check 5.10
```

```
  PASS  /root/cks/risky-sboms.txt names exactly the SBOMs with CRITICAL findings
```

## Clean up

Tasks 5 to 7 leave the webhook on, and every later pod passes through it. Tasks 6 and 7 start from task 5's result and apply its solution when the webhook is off. Run `./certs/cks/cluster/reset.sh` before the next domain.
