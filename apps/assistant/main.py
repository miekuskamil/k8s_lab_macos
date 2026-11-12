"""Shop assistant for the k8s_lab_macos AI lessons.

Answers questions about the shop's orders. It fetches recent orders from the
backend, then asks a language model served by Ollama. Every call to the model
gets an OpenTelemetry span with the GenAI attributes (model, input and output
tokens), and Prometheus metrics count tokens and model latency.
"""

import json
import logging
import os
import socket
import sys
import time

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
OLLAMA_URL = os.getenv("OLLAMA_URL", "http://host.docker.internal:11434").rstrip("/")
OLLAMA_MODEL = os.getenv("OLLAMA_MODEL", "qwen2.5:3b")
MAX_TOKENS = int(os.getenv("MAX_TOKENS", "120"))
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
    return {"model": OLLAMA_MODEL, "ollama": OLLAMA_URL, "max_tokens": MAX_TOKENS}


async def fetch_orders(client: httpx.AsyncClient) -> list:
    response = await client.get(f"{BACKEND_URL}/api/orders", params={"limit": 10}, timeout=5)
    response.raise_for_status()
    return response.json().get("orders", [])


async def ask_model(client: httpx.AsyncClient, question: str, orders: list) -> dict:
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
        span.set_attribute("gen_ai.response.model", data.get("model", OLLAMA_MODEL))
        span.set_attribute("gen_ai.usage.input_tokens", input_tokens)
        span.set_attribute("gen_ai.usage.output_tokens", output_tokens)
        LLM_SECONDS.labels(OLLAMA_MODEL).observe(elapsed)
        TOKENS.labels(OLLAMA_MODEL, "input").inc(input_tokens)
        TOKENS.labels(OLLAMA_MODEL, "output").inc(output_tokens)
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
        except httpx.TimeoutException:
            ASKS.labels("model_timeout").inc()
            trace.get_current_span().set_status(Status(StatusCode.ERROR, "model timeout"))
            return JSONResponse({"error": "the model did not answer in time", "trace_id": trace_id}, status_code=504)
        except httpx.HTTPError as exc:
            ASKS.labels("model_error").inc()
            log.error("model call failed", extra={"fields": {"error": str(exc)}})
            return JSONResponse({"error": f"model call failed: {exc}", "trace_id": trace_id}, status_code=502)
    ASKS.labels("ok").inc()
    log.info("question answered", extra={"fields": {k: v for k, v in result.items() if k != "answer"}})
    return {**result, "orders_seen": len(orders), "trace_id": trace_id}


# Instrument last, so the tracing middleware wraps everything above.
FastAPIInstrumentor.instrument_app(app, excluded_urls=",".join(p.lstrip("/") for p in UNTRACED_PATHS))
