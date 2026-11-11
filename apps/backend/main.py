"""Orders backend for the k8s_lab_macos reference architecture.

FastAPI service with JSON logs, OpenTelemetry tracing (W3C trace context),
Prometheus metrics, a Redis store and an optional in-process rate limiter.
"""

import asyncio
import json
import logging
import os
import socket
import sys
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone

import redis.asyncio as redis
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import JSONResponse
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.redis import RedisInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest
from pydantic import BaseModel, Field

APP_VERSION = os.getenv("APP_VERSION", "v1")
POD_NAME = os.getenv("HOSTNAME", socket.gethostname())
REDIS_HOST = os.getenv("REDIS_HOST", "redis")
# Not REDIS_PORT: Kubernetes injects REDIS_PORT=tcp://<ip>:6379 for a Service named redis.
REDIS_PORT = int(os.getenv("REDIS_PORT_NUMBER", "6379"))
REDIS_PASSWORD = os.getenv("REDIS_PASSWORD") or None
OTEL_ENABLED = os.getenv("OTEL_ENABLED", "true").lower() == "true"
RATE_LIMIT_RPS = float(os.getenv("RATE_LIMIT_RPS", "0"))
EXTRA_LATENCY_MS = int(os.getenv("EXTRA_LATENCY_MS", "0"))
LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
UNTRACED_PATHS = ("/healthz", "/readyz", "/metrics")


class JsonFormatter(logging.Formatter):
    """Format every log record as one JSON object with trace identifiers."""

    def format(self, record: logging.LogRecord) -> str:
        span_context = trace.get_current_span().get_span_context()
        payload = {
            "timestamp": datetime.fromtimestamp(record.created, tz=timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "service": "backend",
            "version": APP_VERSION,
            "pod": POD_NAME,
        }
        if span_context.is_valid:
            payload["trace_id"] = format(span_context.trace_id, "032x")
            payload["span_id"] = format(span_context.span_id, "016x")
        extra = getattr(record, "fields", None)
        if extra:
            payload.update(extra)
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, separators=(",", ":"))


def configure_logging() -> logging.Logger:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers = [handler]
    root.setLevel(LOG_LEVEL)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logging.getLogger(name).handlers = []
        logging.getLogger(name).propagate = True
    logging.getLogger("uvicorn.access").disabled = True
    return logging.getLogger("backend")


log = configure_logging()


class DropProbeSpans(BatchSpanProcessor):
    """Skip root-level Redis PING spans. The readiness probe produces one every 5 seconds."""

    def on_end(self, span) -> None:
        if span.parent is None and span.name == "PING":
            return
        super().on_end(span)


def configure_tracing() -> None:
    resource = Resource.create(
        {
            "service.name": "backend",
            "service.version": APP_VERSION,
            "service.instance.id": POD_NAME,
        }
    )
    provider = TracerProvider(resource=resource)
    provider.add_span_processor(DropProbeSpans(OTLPSpanExporter()))
    trace.set_tracer_provider(provider)
    RedisInstrumentor().instrument()


class TokenBucket:
    """Token bucket limiter. A rate of zero disables limiting."""

    def __init__(self, rate: float) -> None:
        self.rate = rate
        self.capacity = max(rate, 1.0)
        self.tokens = self.capacity
        self.updated = time.monotonic()

    def allow(self) -> bool:
        if self.rate <= 0:
            return True
        now = time.monotonic()
        self.tokens = min(self.capacity, self.tokens + (now - self.updated) * self.rate)
        self.updated = now
        if self.tokens >= 1.0:
            self.tokens -= 1.0
            return True
        return False


limiter = TokenBucket(RATE_LIMIT_RPS)

REQUESTS = Counter(
    "backend_http_requests_total",
    "HTTP requests handled by the backend",
    ["method", "path", "status", "version"],
)
LATENCY = Histogram(
    "backend_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path", "version"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)
ORDERS_CREATED = Counter("backend_orders_created_total", "Orders created", ["version"])
RATE_LIMITED = Counter("backend_rate_limited_total", "Requests rejected by the limiter", ["version"])


class OrderIn(BaseModel):
    item: str = Field(min_length=1, max_length=64)
    quantity: int = Field(default=1, ge=1, le=100)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.redis = redis.Redis(
        host=REDIS_HOST,
        port=REDIS_PORT,
        password=REDIS_PASSWORD,
        decode_responses=True,
        socket_connect_timeout=2,
        socket_timeout=2,
    )
    log.info(
        "backend starting",
        extra={"fields": {"redis": f"{REDIS_HOST}:{REDIS_PORT}", "rate_limit_rps": RATE_LIMIT_RPS}},
    )
    yield
    await app.state.redis.aclose()


app = FastAPI(title="orders-backend", version=APP_VERSION, lifespan=lifespan)

if OTEL_ENABLED:
    configure_tracing()
    FastAPIInstrumentor.instrument_app(app, excluded_urls=",".join(p.lstrip("/") for p in UNTRACED_PATHS))


@app.middleware("http")
async def observe(request: Request, call_next):
    started = time.perf_counter()
    path = request.url.path
    if path.startswith("/api/") and not limiter.allow():
        RATE_LIMITED.labels(APP_VERSION).inc()
        response: Response = JSONResponse({"error": "rate limit exceeded"}, status_code=429)
    else:
        if EXTRA_LATENCY_MS and path.startswith("/api/"):
            await asyncio.sleep(EXTRA_LATENCY_MS / 1000)
        response = await call_next(request)
    elapsed = time.perf_counter() - started
    route = request.scope.get("route")
    label = route.path if route else "unmatched"
    response.headers["x-app-version"] = APP_VERSION
    response.headers["x-served-by"] = POD_NAME
    if path not in UNTRACED_PATHS:
        REQUESTS.labels(request.method, label, str(response.status_code), APP_VERSION).inc()
        LATENCY.labels(request.method, label, APP_VERSION).observe(elapsed)
        log.info(
            "request handled",
            extra={
                "fields": {
                    "method": request.method,
                    "path": path,
                    "status": response.status_code,
                    "duration_ms": round(elapsed * 1000, 2),
                    "request_id": request.headers.get("x-request-id"),
                }
            },
        )
    return response


@app.get("/healthz")
async def healthz() -> dict:
    return {"status": "ok"}


@app.get("/readyz")
async def readyz(request: Request) -> dict:
    try:
        await request.app.state.redis.ping()
    except Exception as exc:
        log.error("redis not ready", extra={"fields": {"error": str(exc)}})
        raise HTTPException(status_code=503, detail="redis unavailable") from exc
    return {"status": "ready"}


@app.get("/metrics")
async def metrics() -> Response:
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/api/version")
async def version() -> dict:
    return {"version": APP_VERSION, "pod": POD_NAME}


@app.get("/api/orders")
async def list_orders(request: Request, limit: int = 10) -> dict:
    limit = max(1, min(limit, 50))
    client: redis.Redis = request.app.state.redis
    try:
        ids = await client.lrange("orders", 0, limit - 1)
        pipe = client.pipeline()
        for order_id in ids:
            pipe.hgetall(f"order:{order_id}")
        orders = await pipe.execute()
    except redis.RedisError as exc:
        log.error("redis read failed", extra={"fields": {"error": str(exc)}})
        raise HTTPException(status_code=503, detail="storage unavailable") from exc
    return {"version": APP_VERSION, "pod": POD_NAME, "count": len(orders), "orders": orders}


@app.post("/api/orders", status_code=201)
async def create_order(order: OrderIn, request: Request) -> dict:
    client: redis.Redis = request.app.state.redis
    try:
        order_id = await client.incr("order:seq")
        record = {
            "id": str(order_id),
            "item": order.item,
            "quantity": str(order.quantity),
            "created_at": datetime.now(timezone.utc).isoformat(),
            "created_by": APP_VERSION,
        }
        pipe = client.pipeline()
        pipe.hset(f"order:{order_id}", mapping=record)
        pipe.lpush("orders", order_id)
        pipe.ltrim("orders", 0, 99)
        await pipe.execute()
    except redis.RedisError as exc:
        log.error("redis write failed", extra={"fields": {"error": str(exc)}})
        raise HTTPException(status_code=503, detail="storage unavailable") from exc
    ORDERS_CREATED.labels(APP_VERSION).inc()
    return {"version": APP_VERSION, "order": record}


@app.get("/api/orders/{order_id}")
async def get_order(order_id: int, request: Request) -> dict:
    record = await request.app.state.redis.hgetall(f"order:{order_id}")
    if not record:
        raise HTTPException(status_code=404, detail="order not found")
    return {"version": APP_VERSION, "order": record}


@app.get("/api/slow")
async def slow(ms: int = 200) -> dict:
    """Hold a connection open. Use it to trigger the connection pool limits."""
    ms = max(0, min(ms, 10000))
    await asyncio.sleep(ms / 1000)
    return {"version": APP_VERSION, "pod": POD_NAME, "slept_ms": ms}
