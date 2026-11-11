"use strict";

const path = require("node:path");
const express = require("express");
const client = require("prom-client");

const PORT = Number(process.env.PORT || 3000);
const BACKEND_URL = (process.env.BACKEND_URL || "http://backend.shop.svc.cluster.local:8000").replace(/\/$/, "");
const REQUEST_TIMEOUT_MS = Number(process.env.REQUEST_TIMEOUT_MS || 5000);
const MAX_BURST = Number(process.env.MAX_BURST || 500);
const MAX_CONCURRENCY = Number(process.env.MAX_CONCURRENCY || 100);
const ALLOWED_BURST_PATHS = ["/api/orders", "/api/version", "/api/slow?ms=300"];

// Headers that carry trace context and request identity to the backend.
const PROPAGATED_HEADERS = [
  "traceparent",
  "tracestate",
  "baggage",
  "x-request-id",
  "x-b3-traceid",
  "x-b3-spanid",
  "x-b3-parentspanid",
  "x-b3-sampled",
  "x-b3-flags",
  "b3",
];

function log(level, message, fields = {}) {
  process.stdout.write(
    JSON.stringify({
      timestamp: new Date().toISOString(),
      level,
      service: "frontend",
      message,
      ...fields,
    }) + "\n"
  );
}

client.collectDefaultMetrics();
const httpRequests = new client.Counter({
  name: "frontend_http_requests_total",
  help: "HTTP requests handled by the frontend",
  labelNames: ["method", "route", "status"],
});
const upstreamDuration = new client.Histogram({
  name: "frontend_upstream_duration_seconds",
  help: "Latency of calls from the frontend to the backend",
  labelNames: ["status"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

const app = express();
app.disable("x-powered-by");
app.use(express.json({ limit: "16kb" }));

app.use((req, res, next) => {
  res.on("finish", () => {
    const route = req.route ? req.baseUrl + req.route.path : req.baseUrl || "static";
    httpRequests.inc({ method: req.method, route, status: String(res.statusCode) });
  });
  next();
});

function forwardHeaders(req) {
  const headers = {};
  for (const name of PROPAGATED_HEADERS) {
    if (req.headers[name]) headers[name] = req.headers[name];
  }
  return headers;
}

async function callBackend(pathAndQuery, { method = "GET", body, headers = {} } = {}) {
  const started = process.hrtime.bigint();
  let status = "error";
  try {
    const response = await fetch(`${BACKEND_URL}${pathAndQuery}`, {
      method,
      headers: { "content-type": "application/json", ...headers },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    status = String(response.status);
    const text = await response.text();
    return {
      status: response.status,
      contentType: response.headers.get("content-type") || "application/json",
      version: response.headers.get("x-app-version") || "unknown",
      servedBy: response.headers.get("x-served-by") || "unknown",
      text,
    };
  } catch (err) {
    return { status: 0, contentType: "application/json", version: "unknown", servedBy: "unknown", text: JSON.stringify({ error: err.name }) };
  } finally {
    const seconds = Number(process.hrtime.bigint() - started) / 1e9;
    upstreamDuration.observe({ status }, seconds);
  }
}

app.get("/healthz", (_req, res) => res.json({ status: "ok" }));
app.get("/readyz", (_req, res) => res.json({ status: "ready" }));

app.get("/metrics", async (_req, res) => {
  res.set("content-type", client.register.contentType);
  res.end(await client.register.metrics());
});

app.get("/config", (_req, res) => {
  res.json({ backend: BACKEND_URL, maxBurst: MAX_BURST, maxConcurrency: MAX_CONCURRENCY, burstPaths: ALLOWED_BURST_PATHS });
});

// Transparent proxy for the browser. Every call to /api/* goes to the backend.
app.use("/api", async (req, res) => {
  const result = await callBackend(`/api${req.url}`, {
    method: req.method,
    body: ["POST", "PUT", "PATCH"].includes(req.method) ? req.body : undefined,
    headers: forwardHeaders(req),
  });
  if (result.status === 0) {
    log("error", "backend unreachable", { path: req.originalUrl });
    return res.status(502).json({ error: "backend unreachable or timed out" });
  }
  res.status(result.status).set("content-type", result.contentType).set("x-app-version", result.version).set("x-served-by", result.servedBy).send(result.text);
});

function percentile(sorted, p) {
  if (sorted.length === 0) return 0;
  const index = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[index];
}

// Server-side load generator. The browser asks for N requests at a given concurrency.
app.post("/burst", async (req, res) => {
  const targetPath = ALLOWED_BURST_PATHS.includes(req.body?.path) ? req.body.path : "/api/orders";
  const count = Math.max(1, Math.min(Number(req.body?.count) || 50, MAX_BURST));
  const concurrency = Math.max(1, Math.min(Number(req.body?.concurrency) || 5, MAX_CONCURRENCY));

  const statuses = {};
  const versions = {};
  const latencies = [];
  let next = 0;
  const started = Date.now();

  async function worker() {
    while (next < count) {
      next += 1;
      const t0 = process.hrtime.bigint();
      const result = await callBackend(targetPath, { headers: forwardHeaders(req) });
      latencies.push(Number(process.hrtime.bigint() - t0) / 1e6);
      const key = result.status === 0 ? "timeout/error" : String(result.status);
      statuses[key] = (statuses[key] || 0) + 1;
      versions[result.version] = (versions[result.version] || 0) + 1;
    }
  }

  await Promise.all(Array.from({ length: concurrency }, worker));
  latencies.sort((a, b) => a - b);
  const total = latencies.reduce((sum, v) => sum + v, 0);
  log("info", "burst finished", { path: targetPath, count, concurrency, statuses, versions });
  res.json({
    path: targetPath,
    count,
    concurrency,
    durationMs: Date.now() - started,
    statuses,
    versions,
    latencyMs: {
      avg: Math.round(total / latencies.length),
      p50: Math.round(percentile(latencies, 50)),
      p95: Math.round(percentile(latencies, 95)),
      max: Math.round(latencies[latencies.length - 1]),
    },
  });
});

app.use(express.static(path.join(__dirname, "public"), { maxAge: "5m" }));

const server = app.listen(PORT, "0.0.0.0", () => {
  log("info", "frontend listening", { port: PORT, backend: BACKEND_URL });
});

function shutdown(signal) {
  log("info", "shutting down", { signal });
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 8000).unref();
}
process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
