# Choosing the model for the AI modules

The AI modules (17, 18, 19 and 27) use [Ollama](https://ollama.com) with `qwen2.5:3b` by default. Ollama runs models on your own machine, for free and offline, and the course's measured numbers come from that setup. You aren't tied to it. This page shows the choices:

1. One settings file, `lab.env`, for any provider: Ollama, any server that speaks the OpenAI API, or Claude.
2. Any other model that Ollama serves, switched by hand.
3. Claude, through the Anthropic API, with the mesh setup for module 17.

## Settings in lab.env

The shop assistant (module 17) and the RAG app (module 27) read four settings. `LLM_PROVIDER` picks the API they speak, and `LLM_URL`, `LLM_MODEL` and `LLM_API_KEY` say where the model runs, which model answers and which key pays for it. You write them once in `lab.env`, and `./lab.sh ai` copies them into the cluster.

The `openai` provider matters most, because most model servers and hosted providers speak the OpenAI chat completions API: Ollama's own `/v1` endpoint, vLLM, LM Studio, OpenAI, Grok, Gemini, Groq and OpenRouter. The `ollama` provider speaks Ollama's native API, and `anthropic` uses the Anthropic SDK.

1. Copy the example and edit it. Git ignores `lab.env`, so a key in it stays on your machine.
   ```bash
   cp lab.env.example lab.env
   ```
   For Ollama on your machine through its OpenAI-compatible endpoint, `lab.env` holds three lines. Pods reach your machine as `host.docker.internal`, never as `localhost`:
   ```bash
   LLM_PROVIDER=openai
   LLM_URL=http://host.docker.internal:11434/v1
   LLM_MODEL=qwen2.5:3b
   ```

2. Store the settings in the cluster:
   ```bash
   ./lab.sh ai
   ```
   The command writes the ConfigMap `llm-settings`, and the Secret `llm-api-key` when you set a key, into each of the namespaces `shop` and `course-rag` that exists. Both apps load them through `envFrom`, and the command restarts an app that already runs, because a pod reads its environment only when it starts. `./lab.sh up` and `./lab.sh start` run it too, and module 27 creates `course-rag` later, so run `./lab.sh ai` again after module 27's deploy step.

3. Check the switch once module 17 has deployed the assistant: `curl -s localhost:8080/api/model` then shows the provider, model and URL the assistant uses. Before module 17 the path returns 404, because no assistant runs yet.

The settings in `lab.env` win over the per-app variables further down this page, such as `OLLAMA_MODEL`. Delete `lab.env`, or leave `LLM_PROVIDER` empty, and run `./lab.sh ai` to go back to the defaults.

Module 27 also needs an embedding model for its search. With `LLM_PROVIDER=openai`, the RAG app asks the same server's `/embeddings` endpoint for `nomic-embed-text`. A provider without that model needs `EMBED_PROVIDER=ollama` and `EMBED_URL=http://host.docker.internal:11434`, so search stays in Ollama while another model writes the answers. Keep the embedding model the same once you ingest, because a different model means running the ingest step again.

kagent (module 19) keeps its own model settings in its Helm release. For an OpenAI-compatible server, add these flags to module 19's `helm install kagent` command, with the key in the Secret `kagent-openai` under `OPENAI_API_KEY` (any value works for Ollama):

```bash
helm install kagent ... --set providers.default=openAI --set providers.openAI.model=qwen2.5:3b \
  --set providers.openAI.config.baseUrl=http://host.docker.internal:11434/v1
```

### Ollama in a container

A machine without Ollama runs it as a container next to the clusters:

```bash
./lab.sh ollama
```

The command starts the `ollama` service from `compose.yaml` and pulls `qwen2.5:3b` and `nomic-embed-text`, about 2.2 GB, into a Docker volume. It listens on port 11434 of your machine, where pods find it as `host.docker.internal:11434`, so the course commands work unchanged. It runs on the CPU, because containers on a Mac get no GPU, so it suits a Linux machine or a test more than daily work on a Mac. In the test run on an Apple silicon Mac, the assistant's first answer took 42 seconds instead of under one, and module 27's ingest of the whole course took about 15 minutes instead of under one. When something else holds port 11434, set `LAB_OLLAMA_PORT` in `lab.env` and use that port in `LLM_URL`. On Linux, also set `LAB_OLLAMA_BIND=0.0.0.0`, because pods reach the host there through the Docker network's gateway, not through its loopback.

## Another Ollama model, by hand

Each app reads the model name from an environment variable. Pull the model, then point the app at it:

```bash
ollama pull llama3.2:3b
kubectl -n shop set env deploy/assistant OLLAMA_MODEL=llama3.2:3b          # module 17
kubectl -n course-rag set env deploy/rag CHAT_MODEL=llama3.2:3b             # module 27
helm upgrade kagent ... --set providers.ollama.model=llama3.2:3b            # module 19, same flags as the install
```

After module 17, check the switch with `curl -s localhost:8080/api/model`. Memory is the limit. A model needs roughly its download size plus 30% while it answers, on top of the lab's 5 GB. Models that call tools well matter most for module 19, because kagent's agents work by calling tools. Module 27's search model, `nomic-embed-text`, stays the same: the index was built with it, and a different embedding model means re-running the ingest step.

## Claude through the Anthropic API

The shop assistant (module 17) and the RAG app (module 27) both have a `PROVIDER` setting. With `PROVIDER=anthropic`, they send the question to Claude through the official Anthropic Python SDK. kagent (module 19) supports Anthropic natively.

The `PROVIDER` setting arrived with the images `assistant:1.1.0` and `rag:1.2.0`, and the `LLM_*` settings and the `openai` provider with `assistant:1.2.0` and `rag:1.3.0`. If your lab is older than 21 November 2026, run `./lab.sh up` once to build the new assistant image. Module 27 builds its own image in its steps.

Some things work differently from Ollama:

- **Cost.** Every call costs money. The default model, `claude-opus-5-5`, costs $4 per million input tokens and $20 per million output tokens, and thinking counts as output. A question to the assistant carries the 10 most recent orders, so expect around one cent per answer. The `input_tokens` and `output_tokens` fields in each reply show the real numbers. Set `ANTHROPIC_MODEL=claude-haiku-5-5` for the cheapest model.
- **Thinking.** Current Claude models think before they answer, and the thinking counts against `max_tokens`. The apps therefore give Claude a budget of 4,000 tokens instead of Ollama's 120 and 250, and ask for `effort: low`, because short questions about orders don't need deep reasoning. The system prompt still keeps the visible answer to three sentences.
- **Search stays in Ollama.** Anthropic offers no embedding model. In module 27, `nomic-embed-text` in Ollama still turns the text into vectors. Only the final answer comes from Claude.
- **Encrypted traffic.** Ollama speaks plain HTTP, so the waypoint reads every request. The Anthropic API only accepts HTTPS. The setup below uses TLS origination from [module 12](../platform-engineering/2-intermediate/12-egress.md#concept-tls-origination): the assistant sends plain HTTP inside the mesh, and the waypoint opens the HTTPS connection. The waypoint then still sees the method and path of every call, so metrics and policies keep working.
- **Declined answers.** A safety system sometimes declines a request. The apps ask the API to retry on another model in that case (`fallbacks: "default"`), and they show "The model declined to answer this question." when no model answers.

### 1. Store the API key

Create a key at [platform.claude.com](https://platform.claude.com). Keep it out of Git and out of your shell history:

```bash
read -rs ANTHROPIC_API_KEY      # paste the key, then press Enter; nothing is shown
kubectl -n shop create secret generic anthropic --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
```

### 2. Module 17: the assistant

Do module 17 up to its ServiceEntry step first, so the assistant and the shop waypoint exist. Then add Anthropic's API to the mesh, allow only the assistant to call it, and switch the assistant over:

```bash
kubectl apply -f platform-engineering/manifests/17-claude-serviceentry.yaml -f platform-engineering/manifests/17-claude-policy.yaml
kubectl -n shop set env deploy/assistant --from=secret/anthropic
kubectl -n shop set env deploy/assistant PROVIDER=anthropic ANTHROPIC_BASE_URL=http://api.anthropic.com
kubectl -n shop rollout status deploy/assistant
curl -s localhost:8080/api/model
curl -s -X POST localhost:8080/api/ask -H 'content-type: application/json' -d '{"question":"Which orders are still pending?"}'
```

`ANTHROPIC_BASE_URL=http://api.anthropic.com` is the TLS origination step. It looks wrong at first, because the key travels in plain HTTP. It only does so inside the mesh, where ztunnel wraps every connection in mTLS, and the waypoint sends it on to Anthropic over HTTPS.

Check that the rule holds. A request from any other workload gets a 403 from the waypoint, before it reaches Anthropic:

```bash
kubectl -n shop exec deploy/course-client -- curl -s -o /dev/null -w '%{http_code}\n' -X POST http://api.anthropic.com/v1/messages
```

To go back to Ollama: `kubectl -n shop set env deploy/assistant PROVIDER=ollama`.

### 3. Module 19: kagent

kagent reads the key from its own Secret. Install kagent as module 19 shows, and add these flags to the `helm install kagent` command:

```bash
kubectl -n kagent create secret generic kagent-anthropic --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
helm install kagent ... --set providers.default=anthropic --set providers.anthropic.model=claude-opus-5-5
```

Claude calls tools far more reliably than a 3-billion-parameter model, so module 19's agents finish more of their tasks.

### 4. Module 27: RAG

The RAG app calls Claude over HTTPS directly. The `course-rag` namespace sits outside the shop waypoint, so no ServiceEntry is involved:

```bash
kubectl -n course-rag create secret generic anthropic --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"
kubectl -n course-rag set env deploy/rag --from=secret/anthropic
kubectl -n course-rag set env deploy/rag PROVIDER=anthropic
```

The answers in module 27's text came from `qwen2.5:3b`. Claude answers the same questions with the same retrieved sections, so the retrieval lessons still hold: when search returns the wrong sections, a better model still gives a confident wrong answer.

## What was tested

The Ollama path is the course default. With the new app images, `./platform-engineering/verify.sh 17 27` passed every check.

The `lab.env` settings were tested from the toolbox on a fresh lab, with Ollama 0.32.13 and `qwen2.5:3b` throughout. With no `lab.env`, `./lab.sh test 17 27` passed 21 of 21 checks. With `LLM_PROVIDER=openai` and Ollama's `/v1` endpoint, the same run passed 21 of 21 once module 17's AuthorizationPolicy also allowed `/v1/chat/completions`, and `/api/model` reported the `openai` provider. Against the `ollama` service in a container, the assistant answered, `./lab.sh test 27` passed 11 of 11 checks, and the RAG app also ingested, searched and answered through the service's `/v1` API. The Claude path was tested without an API key:

- Both apps ran against a stand-in server that recorded each request. The SDK sent `POST /v1/messages` with the model, the system prompt, `effort: low` and the fallback setting, and the apps read the answer and the token counts from the reply.
- In the cluster, the request went from the assistant through the waypoint to `api.anthropic.com` over HTTPS. With a fake key, Anthropic answered `401 authentication_error`, which shows the route and the TLS origination work. A pod with another service account got `403` from the waypoint, before its request left the cluster. The policy matches `/v1/messages` even though the SDK adds `?beta=true`, because Istio leaves the query string out of path matching.
- `helm template` with the flags above renders a kagent ModelConfig for Anthropic.

A real answer from Claude needs a key and wasn't part of the test run.
