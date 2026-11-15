# Module 18: serving models inside the cluster

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 1, 4 and 5, and 17 for the AI basics.

**You need:** the lab running (`./scripts/start.sh` starts or repairs it), and internet access: the module downloads about 900 MB of models, once per run.

Module 17 called a model that ran outside the cluster, but plenty of teams run models inside Kubernetes instead, for privacy, for cost, or because a GPU cluster is what they have. This module puts two small model servers into the lab and shows three problems that make model serving different from serving a normal API:

1. A model server is a heavy workload that starts slowly.
2. Requests differ hugely in cost, and that confuses load balancers.
3. A request names its model in the body, where routers don't look.

The second problem has driven a whole new Kubernetes standard.

Time: about 50 minutes. This is the second of three AI modules. It downloads about 900 MB of models, once per run.

## Concept: a model server is an odd workload

| | A normal web service | A model server |
|---|---|---|
| Container image | tens of MB | hundreds of MB to several GB |
| Data it needs before it starts | none | the model file: 0.4 GB here, 5 to 150 GB in production |
| Time to become ready | seconds | until the model sits in memory: seconds to minutes |
| Cost of one request | about the same for every request | from milliseconds to minutes, depending on prompt and answer length |
| Requests at once | hundreds | a handful per GPU, often one |

The lab runs **llama.cpp**, a fast open-source model server, with two tiny models:

- Qwen2.5 0.5B Instruct (490 MB) runs on two replicas.
- SmolLM2 360M Instruct (390 MB) runs on one replica.

Each replica answers one request at a time (`--parallel 1`) and queues the rest, the way a busy GPU does. llama.cpp speaks the OpenAI-compatible API, `/v1/chat/completions`, which almost every AI tool understands.

## Concept: why LLM load balancing is hard

A normal load balancer assumes that all requests cost about the same, which doesn't hold for language models: "Say hi" takes 30 milliseconds, while "Write a long story" keeps the server busy for 25 seconds. A short question that lands behind a long story waits the full 25 seconds while another replica sits idle, much like a supermarket queue where one customer with a full trolley holds up everyone behind them while the next till stands empty.

The diagram shows this case with ztunnel, which spreads connections without looking at what each one carries:

![ztunnel balances connections, so short questions land on a replica busy with a long story](../docs/diagrams/chapters/18-l4-balancing.svg)

Each balancing method knows a different amount:

| Method | Decides by | Knows about request cost? |
|---|---|---|
| ztunnel (L4) | connection, round robin or random | no |
| Waypoint, Istio's default `LEAST_REQUEST` | number of requests in progress: picks two pods at random, takes the less busy one | a little: it counts requests, not their size |
| Gateway API Inference Extension | the model server's own metrics: queue length, memory cache use | yes |

You'll measure the first two, while the third needs a newer Istio than the lab's.

Predict the results before you measure, from three facts:

- Each replica has one slot (`--parallel 1`), so one request runs and the others wait in that replica's queue.
- `llm-load.sh` opens a new connection for every short question.
- One of the two replicas stays busy with the long story the whole time.

ztunnel picks a pod for each new connection without looking at how busy the pod is, so every short question has about a one-in-two chance of landing behind the long story, and you should expect about 5 of 10 questions to get stuck.

The waypoint looks at every HTTP request and counts the requests it has in progress for each pod. Its `LEAST_REQUEST` method picks two pods at random and takes the less busy one, so it fails only when both random picks hit the busy pod, which happens one in two times one in two, or one time in four. Expect about 2 or 3 of 10 questions to get stuck, and compare these predictions with the test runs in steps 2 and 3.

This is the same difference between layer 4 (L4) and layer 7 (L7) balancing that you know from plain Kubernetes: kube-proxy and ztunnel choose a pod once per connection, while only a proxy that reads HTTP, like the waypoint, sees each request.

## The bigger picture: the Gateway API Inference Extension

A balancer that guesses by counting requests keeps sending short questions behind long ones, so in 2025 the Kubernetes networking group published an extension to the Gateway API for exactly this problem. The extension adds two pieces:

- An **InferencePool** is a group of model server pods.
- An **endpoint picker** is a small service that the gateway asks "which pod should take this request?"

With the extension, each request goes through three steps:

1. The gateway receives a request for the pool and asks the endpoint picker for a pod.
2. The endpoint picker reads each server's metrics, such as the queue length `llamacpp:requests_deferred` from this module.
3. The endpoint picker answers with the pod that will respond fastest, and the gateway sends the request there.

A companion feature reads the model name from the JSON body, so one address serves many models.

Istio supports the extension from version 1.27 onwards, and big serving stacks like llm-d, KServe and NVIDIA Dynamo build on it. The lab's Istio 1.24 predates it, so this module shows the problem the extension solves and the metrics it relies on, not the extension itself.

Autoscaling has the same problem, because CPU use says little about how busy a model server is when a GPU at full load often sits next to a quiet CPU. Teams therefore scale on queue length or tokens per second instead, often with KEDA, an autoscaler that reads those metrics from Prometheus.

## Why this way

**Why llama.cpp and not Ollama, like module 17?** The official Ollama image weighs 2.8 GB, while llama.cpp's server image is 300 MB and publishes the queue metrics this module needs. Both serve the same model files, in the GGUF format.

**Why does an init container download the model?** Model files don't belong in the image, because they're large and teams swap models without rebuilding the image, so an init container fetches the file into a volume before the server starts. Two pods often start at the same time, and to keep them from reading half a file, each pod writes to its own temporary file and renames it when the download finishes. Both pods still download the file, which wastes bandwidth, so production setups pre-load models into a shared cache or use an image volume.

**Why a startup probe on `/health`?** llama.cpp answers `503` on `/health` while it loads the model and `200` once it's ready to serve, and the startup probe waits for that `200`, so Kubernetes never sends traffic to a pod that's still loading.

**Why route by a header, when the request names its model in the body?** HTTP routing in Gateway API and Istio reads headers and paths, never the body, because reading JSON bodies costs time and memory on every request. That's why the Inference Extension needed a separate body-based router.

## Do it

### 1. Deploy the model servers

```console
$ kubectl apply -f platform-engineering/manifests/18-namespace.yaml
namespace/ai created
persistentvolumeclaim/models created
servicemonitor.monitoring.coreos.com/ai-models created

$ kubectl apply -f platform-engineering/manifests/18-llm-qwen.yaml -f platform-engineering/manifests/03-course-client.yaml
deployment.apps/llm-qwen created
service/llm-qwen created
serviceaccount/course-client unchanged
deployment.apps/course-client unchanged

$ kubectl -n ai get pods -w          # Init, then Running 0/1, then 1/1. Ctrl-C when both are 1/1
NAME                        READY   STATUS     RESTARTS   AGE
llm-qwen-67bb5b994f-m9f6d   0/1     Init:0/1   0          8s
llm-qwen-67bb5b994f-s54sk   0/1     Init:0/1   0          8s
llm-qwen-67bb5b994f-s54sk   0/1     PodInitializing   0          21s
llm-qwen-67bb5b994f-m9f6d   0/1     PodInitializing   0          22s
llm-qwen-67bb5b994f-m9f6d   0/1     Running           0          38s
llm-qwen-67bb5b994f-s54sk   0/1     Running           0          38s
llm-qwen-67bb5b994f-m9f6d   0/1     Running           0          45s
llm-qwen-67bb5b994f-m9f6d   1/1     Running           0          45s
llm-qwen-67bb5b994f-s54sk   1/1     Running           0          45s

$ kubectl -n ai logs deploy/llm-qwen -c fetch-model
Found 2 pods, using pod/llm-qwen-67bb5b994f-m9f6d
total 479884
drwxrwxrwx    1 root     root            66 Nov 14 23:36 .
drwxr-xr-x    1 root     root            12 Nov 14 23:36 ..
-rw-r--r--    1 curl_user curl_group 491400032 Nov 14 23:36 qwen2.5-0.5b-instruct-q4_k_m.gguf
```

The `-w` watch keeps printing until you press Ctrl-C, and the transcript shows it up to the moment both pods turned `1/1`.

**What you should see.** Each pod goes through three stages:

1. The `fetch-model` init container downloads the model.
2. The server starts and shows `0/1` while it loads the model into memory.
3. The pod turns `1/1` once the model sits in memory.

Both pods were ready after 39 seconds in one test run and after 45 seconds in another.

Ask a question through the mesh:

```console
$ kubectl -n shop exec deploy/course-client -- curl -s http://llm-qwen.ai.svc.cluster.local:8080/v1/chat/completions \
  -H 'Content-Type: application/json' -d '{"messages":[{"role":"user","content":"What is Kubernetes?"}],"max_tokens":60}'
{"choices":[{"finish_reason":"length","index":0,"message":{"role":"assistant","content":"Kubernetes, short for \"containerized\" or \"containerized\" orchestration, is a platform that enables you to deploy and manage containerized applications, applications that run in containers, or containers that run in containers, on a distributed infrastructure. Kubernetes is a high-level, open-source, scalable,"}}],"created":1794699438,"model":"qwen2.5-0.5b","system_fingerprint":"b11889-d854d98ba","object":"chat.completion","usage":{"completion_tokens":60,"prompt_tokens":33,"total_tokens":93,"prompt_tokens_details":{"cached_tokens":0}},"id":"chatcmpl-ISUzQEZZYj4oXzb7JAtj6WTDU5tndA9u","timings":{"cache_n":0,"prompt_n":33,"prompt_ms":389.149,"prompt_per_token_ms":11.79239393939394,"prompt_per_second":84.80042348817548,"predicted_n":60,"predicted_ms":749.409,"predicted_per_token_ms":12.70184745762712,"predicted_per_second":78.72870488611692}}
```

**What you should see.** JSON with `"model":"qwen2.5-0.5b"`, an answer, and a `timings` block. Compare it with module 17:

| | Module 17: your Mac's GPU | This module: the cluster's CPU |
|---|---|---|
| Model size | 3 billion parameters (`qwen2.5:3b`) | 0.5 billion |
| Hardware | the Mac's GPU | two CPU cores (`--threads 2`, limit `cpu: "2"`) |
| Speed, warm | about 66 tokens per second | about 90 tokens per second |
| Answer quality | mostly right, follows instructions | often vague or slightly wrong |

The cluster's model runs faster without any GPU because it's six times smaller, which is the trade-off every team makes:

- A bigger model gives better answers, but needs more memory and better hardware.
- A small model runs anywhere, but answers worse.

In an earlier test run, a 14-billion-parameter model on the same Mac GPU managed about 13 tokens per second.

### 2. Get stuck behind a long request

```console
$ ./platform-engineering/llm-load.sh
short questions (seconds): 0.1 0.0 0.0 0.1 0.0 25.8 25.4 22.4 21.9 21.5
long generation: 29 s
short questions stuck behind it (over 2 s): 5 of 10
```

The script works in three steps:

1. It starts one long generation (2,000 tokens, about 25 seconds).
2. It sends 10 short questions, half a second apart, all from inside the mesh.
3. It prints how long each short question took.

**What you should see.** Most short questions take 0.0 to 0.1 seconds, while some take about 20 seconds, because they landed on the replica busy with the long story and waited in its queue. In the test runs, 4, 6, 4, 4, 5 and 5 out of 10 got stuck, because ztunnel balances connections and knows nothing about what each request costs.

### 3. Balance per request with a waypoint

```console
$ kubectl apply -f platform-engineering/manifests/18-waypoint.yaml
gateway.gateway.networking.k8s.io/waypoint created

$ kubectl label ns ai istio.io/use-waypoint=waypoint
namespace/ai labeled

$ kubectl -n ai wait --for=condition=Programmed gateway/waypoint
gateway.gateway.networking.k8s.io/waypoint condition met

$ ./platform-engineering/llm-load.sh
short questions (seconds): 0.1 0.0 0.0 0.1 0.0 0.0 0.1 0.1 25.1 23.1
long generation: 29 s
short questions stuck behind it (over 2 s): 2 of 10

$ ./platform-engineering/llm-load.sh
short questions (seconds): 0.0 0.1 0.0 0.0 0.0 0.1 0.1 0.1 0.0 21.9
long generation: 29 s
short questions stuck behind it (over 2 s): 1 of 10

$ ./platform-engineering/llm-load.sh
short questions (seconds): 0.0 0.1 0.1 0.1 0.0 0.0 0.1 23.0 22.5 20.5
long generation: 27 s
short questions stuck behind it (over 2 s): 3 of 10
```

**What you should see.** Fewer stuck questions, but rarely none: the test runs gave 3, 0, 1, 1, 5, 2, 1 and 3 out of 10, an average of 2 against 4.7 before. The waypoint's `LEAST_REQUEST` picks two pods at random and sends the request to the one with fewer requests in progress, and two things keep the number above zero:

- With only two replicas, both random picks sometimes land on the busy pod.
- `LEAST_REQUEST` counts requests, not their size.

To do better, a balancer must read the servers' queues, which is exactly what the Inference Extension's endpoint picker does.

Find the queue yourself. While `llm-load.sh` runs, open Explore in Grafana, pick Prometheus, and run this query:

```text
llamacpp:requests_deferred
```

**What you should see.** One line per pod, labelled `model="qwen"`, where a value above 0 means a question waits in that pod's queue.

### 4. Two models behind one address

```console
$ kubectl apply -f platform-engineering/manifests/18-llm-smol.yaml
deployment.apps/llm-smol created
service/llm-smol created

$ kubectl -n ai rollout status deploy/llm-smol
Waiting for deployment "llm-smol" rollout to finish: 0 of 1 updated replicas are available...
deployment "llm-smol" successfully rolled out

$ kubectl apply -f platform-engineering/manifests/18-route-by-model.yaml
service/llm created
httproute.gateway.networking.k8s.io/llm-by-model created

$ ask() { kubectl -n shop exec deploy/course-client -- curl -s http://llm.ai.svc.cluster.local:8080/v1/chat/completions \
  -H 'Content-Type: application/json' "$@" | grep -o '"model":"[^"]*"'; }
$ ask -d '{"messages":[{"role":"user","content":"Name a colour."}],"max_tokens":12}'
"model":"qwen2.5-0.5b"

$ ask -H 'x-model: smollm2' -d '{"messages":[{"role":"user","content":"Name a colour."}],"max_tokens":12}'
"model":"smollm2-360m"

$ ask -d '{"model":"smollm2-360m","messages":[{"role":"user","content":"Name a colour."}],"max_tokens":12}'
"model":"qwen2.5-0.5b"
```

**What you should see.** `qwen2.5-0.5b`, then `smollm2-360m`, then `qwen2.5-0.5b` again. The third request asked for SmolLM2 in its body, the standard OpenAI way, but the route ignored that, because it reads only headers.

## Investigate

1. You run four replicas instead of two. How would that change the results of step 3, and why?
2. A teammate proposes `loadBalancer: {simple: ROUND_ROBIN}` in a DestinationRule for the model servers, "to be fair". What happens to the stuck questions?
3. Your model servers sit at 30% CPU, but users complain about slow answers. Which metric from this module would you scale on instead, and why does CPU mislead?
4. Why does the second model need its own Deployment, rather than loading both models into one server?

<details>
<summary>Answers</summary>

1. Expect fewer stuck questions, although the test run for this module didn't try it. With four replicas and one busy, both random picks land on the busy pod far less often, 1 in 16 instead of 1 in 4, and in every other case `LEAST_REQUEST` takes the less busy pod. The underlying weakness stays, though, because the balancer still doesn't know a long request from a short one.
2. Expect more questions to get stuck, so try it and count. Round robin sends every other request to the busy replica, whether that replica is free or not, while `LEAST_REQUEST` at least avoids pods that already hold requests.
3. Scale on queue length (`llamacpp:requests_deferred`) or on time spent waiting. A model server spends most of its time on matrix maths, which runs on the GPU, or here on a fixed number of CPU threads, so the CPU number stays flat while requests pile up, whereas the queue shows the users' wait directly.
4. Each llama.cpp process serves one model, and the model fills that process's memory. Separate Deployments also let you scale and update each model on its own, which the route by model in step 4 relies on. Some servers load several models or adapters into one process, with the Inference Extension routing between them, but that setup adds complexity a lab doesn't need.

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

This deletes the `ai` namespace, the models in it and the ServiceMonitor.
