# Module 17: an LLM as a mesh service

> New to a term here, like VirtualService or waypoint? The [glossary](glossary.md) explains every Istio resource and term in this course.

**Before this module:** modules 3, 5, 6 and 12.

**You need:** the lab running (`./scripts/start.sh` starts or repairs it), Ollama with `qwen2.5:3b`, and the assistant image `k8s-lab/assistant:1.1.0`. [What you need](#what-you-need) below has the details. Step 5 uses Jaeger, so keep `./scripts/port-forward.sh` running in a spare terminal.

AI features are the fastest-growing kind of traffic on Kubernetes right now. Most of them follow one pattern:

1. A normal service gathers some data.
2. It sends the data to a language model, together with a question.
3. It returns the model's answer.

This module adds exactly that to the shop: an **assistant** that answers questions about orders. The model runs in Ollama on your own machine. Then you use the mesh the way platform teams handle AI traffic in production. You give the assistant an identity, lock down what it may call, watch its calls, and size its timeouts.

Time: about 50 minutes. This is the first of three AI modules. While the model answers, it uses about 2.4 GB of extra memory on your Mac.

## What you need

- [Ollama](https://ollama.com) running on your machine with `qwen2.5:3b`. Install the model with `ollama pull qwen2.5:3b` (1.9 GB on disk). The module's numbers come from this model.
- Enough memory. The lab uses about 5 GB, and `qwen2.5:3b` adds about 2.4 GB while it answers. The whole test run peaked at 16.5 GB on a 24 GB Mac. A 14-billion-parameter model gives better answers but needs about 9 GB, which doesn't fit next to the lab on 24 GB. Ollama unloads a model after 5 idle minutes and gives the memory back.
- The assistant image `k8s-lab/assistant:1.1.0`. `./scripts/provision.sh` builds it and loads it into the cluster. If your lab is older than 13 November 2026, run `./scripts/provision.sh` once before this module. Otherwise the assistant pod stops at `ImagePullBackOff`. Check with `docker exec k3d-k8s-lab-server-0 crictl images | grep assistant`.
- Another Ollama model, or Claude through the Anthropic API, also works. [Choosing the model for the AI modules](../docs/ai-models.md) shows how to switch.
- macOS with OrbStack or Docker Desktop. Both let containers reach your machine under the name `host.docker.internal`.

### On Linux and WSL (Ubuntu 24.04)

Plain Docker Engine on Linux doesn't answer the name `host.docker.internal`, and Ollama on Linux listens only on `127.0.0.1` by default. The pods then never reach the model. Two steps fix both: make Ollama listen on every interface, and add the name to the cluster's DNS. [Running the lab on Linux and WSL2](../docs/linux-and-wsl.md#the-ai-modules-17-18-19-and-27) has the commands and a check. With Docker Desktop on WSL2, the name already works and you only need Ollama for Windows.

## Concept: what the assistant does

![One question to the assistant: orders from the backend, then an answer from Ollama, both checked by the waypoint](../docs/diagrams/chapters/17-assistant-flow.svg)

The diagram follows one question from your terminal to the model and back:

1. You send a question with `curl` to `POST /api/ask` on the ingress gateway.
2. The gateway routes the request to the assistant.
3. The assistant asks the backend for 10 recent orders, through the waypoint. This takes about 5 ms.
4. The assistant sends the orders and your question to Ollama on your Mac, again through the waypoint.
5. Ollama returns the answer and the token counts after about 1 to 10 seconds.
6. The assistant returns the answer, the tokens, the seconds and a `trace_id` to you.

The pattern has a name: retrieval-augmented generation, or RAG. The model knows nothing about your shop. So the assistant fetches real data first and puts it into the prompt, the text it sends to the model. The model then answers from that data, not from what it remembers of the internet.

## Concept: why LLM traffic is different

Put the numbers from this module next to the rest of the shop:

| | A normal API call | A model call |
|---|---|---|
| Duration | milliseconds | seconds, sometimes minutes |
| Cost | close to nothing | real money, counted in tokens |
| Retry if it fails? | usually harmless | doubles the cost and the wait |
| What to measure | requests, errors, latency | the same, plus tokens in and out |
| What leaks if someone reads it | an order list | whatever went into the prompt |

**Tokens** are the units a model reads and writes. A token is a piece of a word, roughly four characters of English. Every hosted model bills by tokens, with separate prices for input and output. On your own GPU, tokens are what the GPU spends its time on. So token counts belong next to latency on every dashboard.

## Concept: how a model writes an answer

One model call goes through up to three phases. Once you know them, every timing in this module makes sense:

| Phase | What happens | What drives its time |
|---|---|---|
| Load | Ollama reads the model file from disk into memory | Only on the first call, or after 5 idle minutes. It's the gap between 1.34 and 0.34 seconds in step 2 |
| Prefill | The model reads the whole prompt in one pass | The number of input tokens, but each one is cheap |
| Decode | The model writes the answer one token at a time. Every new token needs a full pass through the model | The number of output tokens, times the time per token |

The length of the answer decides how long the user waits. At about 66 tokens per second, the 20 output tokens in step 2 take about 0.3 seconds. That is most of the 0.34 seconds you'll measure. This is why the assistant caps the answer length with `max_tokens`. It also explains why a timeout during decode hurts so much: it throws away every token written so far.

The input side decides the bill. A model keeps no memory between calls. So the assistant sends the order data and the question again with every request. You pay for those input tokens every time, even when the question repeats.

## The bigger picture: AI gateways

As AI traffic grew, a new kind of product appeared: the AI gateway. An AI gateway sits between apps and models, like a toll booth on the only road to the model. Examples are agentgateway, kgateway and Envoy AI Gateway. They add features that a classic proxy lacks:

- rate limits counted in tokens instead of requests
- switching between model providers
- caching repeated prompts
- filtering what goes into a prompt and what comes out

Underneath, most of them do what you'll do in this module with plain Istio:

- They put the model behind a proxy.
- They give each caller an identity.
- They decide who may call which endpoint.
- They record every call.

Recent Istio releases add more AI-specific features on top. One is LLM-aware load balancing through the Gateway API Inference Extension (module 18). Another is agentgateway running as a waypoint. The lab's Istio 1.24 is older than these features, but the basics carry over.

There's also a security problem. Ollama, like many model servers, has **no authentication at all**. Anyone who reaches its port may chat with it, download new models, or delete existing ones. Inside a cluster, "anyone who reaches its port" means every pod. That's the first thing this module fixes.

## Why this way

**Why call Ollama on your Mac instead of running it in the cluster?** Your Mac's GPU runs `qwen2.5:3b` at about 66 tokens per second. It also runs a 14B model, if you have the memory. The lab's Kubernetes node is a Linux VM with no access to the GPU. Only tiny models run at a usable speed there. Module 18 runs one there anyway, to show the difference. Calling an outside model is also the most common real setup. In production, that model is usually a hosted API from OpenAI, Anthropic or Google, reached through egress, the mesh's exit for outbound traffic.

**Why does the assistant need its own AuthorizationPolicy for the backend?** Module 3's policy allows only `sa/frontend`. The assistant runs as `sa/assistant`, which is a different identity. So the backend refuses it until you add a rule. That is deny-by-default working as intended. A new AI feature doesn't quietly gain access to your data.

**Why put Ollama behind a ServiceEntry?** The reason is the same as in module 12. Without a ServiceEntry, the mesh sees an IP address and nothing more. A ServiceEntry gives that outside address a name, like a contact entry for a phone number. With it, every model call has a name in metrics, logs and traces, and the waypoint applies rules to it.

**Why no retries on model calls?** A retry repeats the whole generation. The user waits twice as long, and you pay for the tokens twice. If a model call fails, return the error fast and let the user decide.

**Why does the timeout matter so much?** An LLM call that hangs ties up a GPU. A timeout that's too long wastes GPU time. A timeout that's too short throws away work in progress. Step 6 shows what happens at the moment a timeout fires.

## Do it

### 1. Deploy the assistant

```console
$ kubectl apply -f platform-engineering/manifests/17-assistant.yaml
serviceaccount/assistant created
deployment.apps/assistant created
service/assistant created
httproute.gateway.networking.k8s.io/assistant created

$ kubectl -n shop set env deploy/assistant OLLAMA_MODEL=qwen2.5:3b
$ kubectl -n shop rollout status deploy/assistant
deployment "assistant" successfully rolled out

$ curl -s http://localhost:8080/api/model; echo
{"model":"qwen2.5:3b","ollama":"http://host.docker.internal:11434","max_tokens":120}
```

**What you should see.** `{"model":"qwen2.5:3b","ollama":"http://host.docker.internal:11434","max_tokens":120}`. The output shows the model, the Ollama URL, and a cap on answer length. On a Mac with more memory, set any other model from `ollama list` by name. If you get `no healthy upstream` right after the rollout, wait a few seconds. The gateway hasn't received the new pod's address yet.

### 2. Ask a question, and meet a 403

```console
$ ask() { curl -s -m 180 -X POST http://localhost:8080/api/ask -H 'Content-Type: application/json' -d "{\"question\":\"$1\"}"; echo; }
$ ask "How many orders are there?"
{"error":"backend call failed: Client error '403 Forbidden' for url 'http://backend.shop.svc.cluster.local:8000/api/orders?limit=10'\nFor more information check: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/403","trace_id":"b040ff903391cb8940f41ade522f3250"}
```

**What you should see.** You get an error: `backend call failed: Client error '403 Forbidden'`. The assistant asked the backend for orders, and the backend's waypoint refused `sa/assistant`. Allow the assistant, for `GET /api/orders` only:

```console
$ kubectl apply -f platform-engineering/manifests/17-allow-assistant.yaml
authorizationpolicy.security.istio.io/backend-allow-assistant created

$ ask "How many orders are there, and what was ordered?"
{"answer":"There are 5 orders. The items ordered are verify, find-me, book, life, and book.","model":"qwen2.5:3b","input_tokens":390,"output_tokens":23,"model_seconds":0.46,"orders_seen":5,"trace_id":"9511b1c3b479aff17a13a4c8b5c1a670"}
```

**What you should see.** You get a real answer, plus three numbers: `input_tokens`, `output_tokens` and `model_seconds`. In the test runs for this module, the call used 197 to 390 input tokens and 20 to 25 output tokens. The count grows with the number of orders in Redis. A first call took 1.34 to 2.54 seconds, because Ollama loaded the model into memory. With the model loaded, the same question took 0.34 to 0.46 seconds.

Read the answers critically. When asked which item was ordered most, the model replied that "book" was. It added: "There is no item named verify in the order data". In fact, one order was for `verify`. A small model contradicts its own context now and then. Module 27 looks at that problem in depth.

### 3. See what the mesh knows about the model

```console
$ kubectl -n istio-system logs ds/ztunnel --since=5m | grep 'src.workload="assistant' | grep 11434 | tail -1
2026-11-14T23:34:47.698315Z	info	access	connection complete	src.addr=10.42.0.67:37346 src.workload="assistant-788d9f78bb-nfx4c" src.namespace="shop" dst.addr=0.250.250.254:11434 direction="outbound" bytes_sent=1364 bytes_recv=497 duration="453ms"
```

**What you should see.** You see `dst.addr=` followed by an IP and port 11434, something like `0.250.250.254:11434`. The log shows no name. Now register Ollama with the mesh:

```console
$ kubectl apply -f platform-engineering/manifests/17-ollama-serviceentry.yaml
serviceentry.networking.istio.io/ollama created

$ kubectl -n shop rollout restart deploy/assistant && kubectl -n shop rollout status deploy/assistant
deployment.apps/assistant restarted
Waiting for deployment "assistant" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "assistant" rollout to finish: 1 old replicas are pending termination...
deployment "assistant" successfully rolled out

$ ask "Which item was ordered most?"
{"answer":"The item \"book\" was ordered most, with a total of 2 orders.","model":"qwen2.5:3b","input_tokens":385,"output_tokens":18,"model_seconds":0.4,"orders_seen":5,"trace_id":"12633631edb0833d9a29765d62441c8f"}

$ kubectl -n istio-system logs ds/ztunnel --since=1m | grep 'src.workload="assistant' | grep host.docker | tail -1
2026-11-14T23:35:14.951831Z	info	access	connection complete	src.addr=10.42.0.68:47994 src.workload="assistant-55f74d448-tbt4x" src.namespace="shop" src.identity="spiffe://cluster.local/ns/shop/sa/assistant" dst.addr=10.42.0.211:15008 dst.hbone_addr=240.240.0.11:11434 dst.service="host.docker.internal" dst.workload="waypoint-b9b76876f-f7cpq" dst.namespace="shop" dst.identity="spiffe://cluster.local/ns/shop/sa/waypoint" direction="outbound" bytes_sent=1344 bytes_recv=594 duration="396ms"
```

**What you should see.** You see `dst.service="host.docker.internal"` and `dst.workload="waypoint-..."`. Model calls now pass through the waypoint, under a name. You restarted the assistant so that it gets a fresh pod. The new pod resolves the name to the ServiceEntry's virtual IP, as in module 12.

### 4. Protect Ollama's admin API

Ollama listens for more than chat requests:

- `/api/tags` lists your models.
- `/api/pull` downloads new ones.
- `/api/delete` removes them.

Allow only the assistant, and only chat and read-only calls:

```console
$ kubectl apply -f platform-engineering/manifests/17-ollama-policy.yaml -f platform-engineering/manifests/03-course-client.yaml
authorizationpolicy.security.istio.io/ollama-chat-only created
serviceaccount/course-client unchanged
deployment.apps/course-client unchanged

$ kubectl -n shop rollout status deploy/course-client
deployment "course-client" successfully rolled out

$ kubectl -n shop exec deploy/course-client -- curl -s -o /dev/null -w "list models -> %{http_code}\n" http://host.docker.internal:11434/api/tags
list models -> 403

$ kubectl -n shop exec deploy/course-client -- curl -s -o /dev/null -w "delete a model -> %{http_code}\n" \
  -X DELETE -d '{"model":"lab-model-that-does-not-exist"}' http://host.docker.internal:11434/api/delete
delete a model -> 403

$ ask "How many orders are there?"
{"answer":"There are 5 orders in the recent order data.","model":"qwen2.5:3b","input_tokens":385,"output_tokens":12,"model_seconds":0.32,"orders_seen":5,"trace_id":"d3de7ec7c54d74050c01f5e0cec20d3b"}
```

**What you should see.** The course client gets `403` for both calls, and the assistant gets a normal answer. The delete call uses a model name that doesn't exist, so nothing would break even without the policy. Don't test this with a real model name.

### 5. Read the model call in a trace

The `trace_id` field in each answer points to the full trace. Open Jaeger (http://localhost:16686), paste the ID into the search box at the top, and look at the spans.

**What you should see.** The spans look about like this one from the test run:

| Span | Time |
|---|---|
| ingress gateway to assistant | 247 ms |
| assistant: `GET` the orders, through the waypoint, to the backend and Redis | 5 ms |
| assistant: `chat qwen2.5:3b` | 233 ms |
| waypoint: `host.docker.internal:11434` | 230 ms |

Click the `chat ...` span. Its tags follow the OpenTelemetry conventions for generative AI: `gen_ai.system`, `gen_ai.request.model`, `gen_ai.usage.input_tokens`, `gen_ai.usage.output_tokens`. Almost the whole request time goes to the model. The rest of the shop barely shows up.

Prometheus counts the tokens too. In Grafana, open Explore, pick Prometheus, and run this query:

```text
sum by (type) (assistant_llm_tokens_total)
```

**What you should see.** You see far more input tokens than output tokens: 1,152 against 55 in the test run. The order data in every prompt costs much more than the short answers.

### 6. Watch a timeout cut a model call off

```console
$ kubectl apply -f platform-engineering/manifests/17-llm-timeout.yaml
httproute.gateway.networking.k8s.io/ollama-timeout created

$ ask "How many orders are there?"
{"error":"model call failed: Server error '504 Gateway Timeout' for url 'http://host.docker.internal:11434/api/chat'\nFor more information check: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/504","trace_id":"fe8bffb976aeeda0e3b415676daa8d5e"}
```

**What you should see.** You get `model call failed: Server error '504 Gateway Timeout'` after a tenth of a second. The route allows 100 ms, and even a two-word answer took more than twice that in step 5. So the route timeout on the waypoint fired before the model finished. If you run Homebrew's Ollama on a Mac, look at its log:

```console
$ tail -n 5 /opt/homebrew/var/log/ollama.log
slot print_timing: id  0 | task 102 |       total time =     191.48 ms /    23 tokens
slot print_timing: id  0 | task 102 |    graphs reused =         98
slot      release: id  0 | task 102 | stop processing: n_tokens = 396, truncated = 0
srv  update_slots: all slots are idle
[GIN] 2026/11/14 - 23:35:24 | 200 |  318.795042ms |       127.0.0.1 | POST     "/api/chat"
```

In the test run, the log showed the call ending with status `500` after 3 seconds. That run used a 3-second timeout. Next, the log showed `srv stop: cancel task`. When the waypoint closed the connection, Ollama stopped generating. Not every model server does that. A server that keeps going after the client left burns GPU time for nobody. In the run above, the answer needed only about 0.3 seconds. Ollama finished it and logged `200`, although the waypoint had given up after 100 ms.

## Investigate

1. A teammate suggests `retries: {attempts: 3}` for model calls "because models sometimes fail". What does that cost, in time and in tokens, when the model is slow rather than broken?
2. Step 5 showed far more input tokens than output tokens. Name two ways to cut the input side.
3. Without the policy from step 4, what does Ollama let a compromised pod anywhere in the `shop` namespace do?
4. Your company switches from Ollama to a hosted model API that charges per token. Which parts of this module stay exactly the same, and which change?

<details>
<summary>Answers</summary>

1. Each retry starts the generation again from the beginning. A slow model that runs into a timeout gets three more chances to run into the same timeout. So the user waits up to four times longer, and you pay for every partial answer the model produced. Retries help with failures that happen fast, like a refused connection. They don't help with slow generations.
2. There are three ways:
   - Send less data. Fetch fewer orders (`limit` in the backend call), or only the fields the question needs.
   - Pick the data smartly. First search for the orders that match the question. A real RAG system does this with a vector database, a store that finds text by meaning.
   - Cache answers to repeated questions. A cached answer skips the model entirely.
3. Ollama checks nothing, so the pod gets four powers:
   - It lists your models.
   - It chats with them as much as it likes, on your GPU.
   - It downloads huge new models until your disk fills up.
   - It deletes the models you have.

   The waypoint rule is the only lock. That's why the rule allows named identities and named endpoints rather than "the namespace".
4. The identity, the policies, the ServiceEntry pattern, the traces and the token metrics all stay. Three things change:
   - The ServiceEntry gets a public host name and port 443, with TLS origination as in module 12.
   - An API key enters the picture. The key belongs in a Secret, not in the image.
   - Timeouts and token counts start to matter for the bill, not just for the GPU.

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

This removes the assistant, its route and policies, the ServiceEntry and the timeout. Ollama on your machine keeps running.
