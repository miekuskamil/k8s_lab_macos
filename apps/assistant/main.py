"""Shop assistant for the k8s_lab_macos AI lessons.

Answers questions about the shop's orders. It fetches recent orders from the
backend, then asks a language model. PROVIDER picks where the model runs:
"ollama" (the default, any model Ollama serves) or "anthropic" (Claude, through
the official Anthropic SDK and an API key in ANTHROPIC_API_KEY). Every call to the model
gets an OpenTelemetry span with the GenAI attributes (model, input and output
tokens), and Prometheus metrics count tokens and model latency.
"""

import json
import logging
import os
import socket
import sys
import time

import anthropic
import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.trace import SpanKind, Status, StatusCode
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field
from starlette.responses import Response

POD_NAME = os.getenv("HOSTNAME", socket.gethostname())
PROVIDER = os.getenv("PROVIDER", "ollama")
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://host.docker.internal:11434").rstrip("/")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:3b")
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "120"))
# Claude thinks before it answers, and thinking counts against max_tokens, so it gets
# a bigger budget than the small local model. The system prompt keeps answers short.
ANTHROPIC_MODEL = os.getenv("ANTHROPIC_MODEL", "claude-opus-5-5")
ANTHROPIC_MAX_TOKENS = int(os.getenv("ANTHROPIC_MAX_TOKENS", "4000"))
ANTHROPIC_EFFORT = os.getenv("ANTHROPIC_EFFORT", "low")
LLM_TIMEOUT_S = float(os.getenv("LLM_TIMEOUT_S", "120"))
BACKEND_URL = os.getenv("BACKEND_URL", "http://backend.shop.svc.cluster.local:8000").rstrip("/")
UNTRACED_PATHS = ("/healthz", "/readyz", "/metrics")

SYSTEM_PROMPT = (
    "You are the assistant of a small online shop. Answer in at most three short sentences. "
    "Use only the order data you are given. If the data does not answer the question, say so."
)


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": "assistant",
            "pod": POD_NAME,
        }
        span_context = trace.get_current_span().get_span_context()
        if span_context.is_valid:
            payload["trace_id"] = format(span_context.trace_id, "032x")
        payload.update(getattr(record, "fields", {}) or {})
        return json.dumps(payload, separators=(",", ":"))


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logging.getLogger("uvicorn.access").disabled = True
logging.getLogger("httpx").setLevel(logging.WARNING)
logging.getLogger("httpx2").setLevel(logging.WARNING)  # the Anthropic SDK's HTTP client
log = logging.getLogger("assistant")

provider = TracerProvider(resource=Resource.create({"service.name": "assistant", "service.instance.id": POD_NAME}))
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("assistant")
HTTPXClientInstrumentor().instrument()

TOKENS = Counter("assistant_llm_tokens_total", "Tokens processed by the model", ["model", "type"])
LLM_SECONDS = Histogram("assistant_llm_request_seconds", "Time the model took to answer", ["model"],
                        buckets=(0.5, 1, 2, 5, 10, 20, 30, 60, 120))
ASKS = Counter("assistant_requests_total", "Questions answered, by outcome", ["outcome"])

# The SDK reads ANTHROPIC_API_KEY, and ANTHROPIC_BASE_URL when the mesh originates TLS.
claude = anthropic.AsyncAnthropic(timeout=LLM_TIMEOUT_S, max_retries=1) if PROVIDER == "anthropic" else None
MODEL = ANTHROPIC_MODEL if PROVIDER == "anthropic" else OLLAMA_MODEL

app = FastAPI(title="shop-assistant")


class Question(BaseModel):
    question: str = Field(min_length=1, max_length=500)


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz() -> dict:
    return {"status": "ready"}


@app.get("/metrics")
async def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/model")
async def model() -> dict:
    if PROVIDER == "anthropic":
        return {"provider": "anthropic", "model": ANTHROPIC_MODEL, "url": str(claude.base_url),
                "max_tokens": ANTHROPIC_MAX_TOKENS, "effort": ANTHROPIC_EFFORT}
    return {"model": OLLAMA_MODEL, "ollama": OLLAMA_URL, "max_tokens": MAX_TOKENS}


async def fetch_orders(client: httpx.AsyncClient) -> list:
    response = await client.get(f"{BACKEND_URL}/api/orders", params={"limit": 10}, timeout=5)
    response.raise_for_status()
    return response.json().get("orders", [])


def record(span, model: str, elapsed: float, input_tokens: int, output_tokens: int) -> None:
    span.set_attribute("gen_ai.response.model", model)
    span.set_attribute("gen_ai.usage.input_tokens", input_tokens)
    span.set_attribute("gen_ai.usage.output_tokens", output_tokens)
    LLM_SECONDS.labels(MODEL).observe(elapsed)
    TOKENS.labels(MODEL, "input").inc(input_tokens)
    TOKENS.labels(MODEL, "output").inc(output_tokens)


async def ask_claude(question: str, orders: list) -> dict:
    with tracer.start_as_current_span(f"chat {ANTHROPIC_MODEL}", kind=SpanKind.CLIENT) as span:
        span.set_attribute("gen_ai.operation.name", "chat")
        span.set_attribute("gen_ai.system", "anthropic")
        span.set_attribute("gen_ai.request.model", ANTHROPIC_MODEL)
        span.set_attribute("gen_ai.request.max_tokens", ANTHROPIC_MAX_TOKENS)
        started = time.perf_counter()
        # fallbacks="default" lets the API retry on another model if a safety classifier declines.
        response = await claude.beta.messages.create(
            model=ANTHROPIC_MODEL,
            max_tokens=ANTHROPIC_MAX_TOKENS,
            system=SYSTEM_PROMPT,
            messages=[{"role": "user", "content": f"Recent orders: {json.dumps(orders)}\n\nQuestion: {question}"}],
            output_config={"effort": ANTHROPIC_EFFORT},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
        elapsed = time.perf_counter() - started
        if response.stop_reason == "refusal":
            answer = "The model declined to answer this question."
        else:
            answer = "".join(block.text for block in response.content if block.type == "text").strip()
        record(span, response.model, elapsed, response.usage.input_tokens, response.usage.output_tokens)
        return {
            "answer": answer,
            "model": response.model,
            "input_tokens": response.usage.input_tokens,
            "output_tokens": response.usage.output_tokens,
            "model_seconds": round(elapsed, 2),
        }


async def ask_model(client: httpx.AsyncClient, question: str, orders: list) -> dict:
    if PROVIDER == "anthropic":
        return await ask_claude(question, orders)
    body = {
        "model": OLLAMA_MODEL,
        "stream": False,
        "options": {"num_predict": MAX_TOKENS},
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Recent orders: {json.dumps(orders)}\n\nQuestion: {question}"},
        ],
    }
    # Span names and attributes follow the OpenTelemetry semantic conventions for GenAI.
    with tracer.start_as_current_span(f"chat {OLLAMA_MODEL}", kind=SpanKind.CLIENT) as span:
        span.set_attribute("gen_ai.operation.name", "chat")
        span.set_attribute("gen_ai.system", "ollama")
        span.set_attribute("gen_ai.request.model", OLLAMA_MODEL)
        span.set_attribute("gen_ai.request.max_tokens", MAX_TOKENS)
        started = time.perf_counter()
        response = await client.post(f"{OLLAMA_URL}/api/chat", json=body, timeout=LLM_TIMEOUT_S)
        elapsed = time.perf_counter() - started
        response.raise_for_status()
        data = response.json()
        input_tokens = int(data.get("prompt_eval_count", 0))
        output_tokens = int(data.get("eval_count", 0))
        record(span, data.get("model", OLLAMA_MODEL), elapsed, input_tokens, output_tokens)
        return {
            "answer": data.get("message", {}).get("content", "").strip(),
            "model": data.get("model", OLLAMA_MODEL),
            "input_tokens": input_tokens,
            "output_tokens": output_tokens,
            "model_seconds": round(elapsed, 2),
        }


@app.post("/api/ask")
async def ask(question: Question, request: Request):
    trace_id = format(trace.get_current_span().get_span_context().trace_id, "032x")
    async with httpx.AsyncClient() as client:
        try:
            orders = await fetch_orders(client)
        except httpx.HTTPError as exc:
            ASKS.labels("backend_error").inc()
            log.error("backend call failed", extra={"fields": {"error": str(exc)}})
            return JSONResponse({"error": f"backend call failed: {exc}", "trace_id": trace_id}, status_code=502)
        try:
            result = await ask_model(client, question.question, orders)
        except (httpx.TimeoutException, anthropic.APITimeoutError):
            ASKS.labels("model_timeout").inc()
            trace.get_current_span().set_status(Status(StatusCode.ERROR, "model timeout"))
            return JSONResponse({"error": "the model did not answer in time", "trace_id": trace_id}, status_code=504)
        except (httpx.HTTPError, anthropic.APIError) as exc:
            ASKS.labels("model_error").inc()
            log.error("model call failed", extra={"fields": {"error": str(exc)}})
            return JSONResponse({"error": f"model call failed: {exc}", "trace_id": trace_id}, status_code=502)
    ASKS.labels("ok").inc()
    log.info("question answered", extra={"fields": {k: v for k, v in result.items() if k != "answer"}})
    return {**result, "orders_seen": len(orders), "trace_id": trace_id}


# Instrument last, so the tracing middleware wraps everything above.
FastAPIInstrumentor.instrument_app(app, excluded_urls=",".join(p.lstrip("/") for p in UNTRACED_PATHS))
