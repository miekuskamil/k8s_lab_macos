"""Course RAG: answers questions about this course from its own Markdown files.

Ingest: split every .md file in DOCS_DIR into chunks at its headings, turn each chunk
into a vector with an Ollama embedding model, and store vectors plus text in Qdrant.
Ask: embed the question, fetch the closest chunks from Qdrant, and give them to a chat
model as the only context it may answer from.

Talks to Qdrant and Ollama over plain HTTP, so every step is visible in the code.
"""

import hashlib
import os
import re
import time
from pathlib import Path

import anthropic
import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://host.docker.internal:11434")
QDRANT_URL = os.getenv("QDRANT_URL", "http://qdrant:6333")
EMBED_MODEL = os.getenv("EMBED_MODEL", "nomic-embed-text")
CHAT_MODEL = os.getenv("CHAT_MODEL", "qwen2.5:3b")
# PROVIDER picks who writes the answers: "ollama" or "anthropic" (Claude). Search always
# uses EMBED_MODEL in Ollama, because Claude has no embedding model.
PROVIDER = os.getenv("PROVIDER", "ollama")
if PROVIDER == "anthropic":
    CHAT_MODEL = os.getenv("ANTHROPIC_MODEL", "claude-opus-5-5")
claude = anthropic.Anthropic(timeout=300, max_retries=1) if PROVIDER == "anthropic" else None
COLLECTION = os.getenv("COLLECTION", "course")
DOCS_DIR = Path(os.getenv("DOCS_DIR", "/docs"))
# Files to leave out of the index, comma-separated. Module 27 quotes its own test
# questions and answers; indexing it would let the test set leak into the data.
EXCLUDE_FILES = {f.strip() for f in os.getenv("EXCLUDE_FILES", "").split(",") if f.strip()}
CHUNK_CHARS = int(os.getenv("CHUNK_CHARS", "1500"))
TOP_K = int(os.getenv("TOP_K", "4"))
# nomic-embed-text was trained with a task prefix on every input: "search_document: "
# for stored text, "search_query: " for questions. Without them, questions and
# passages land in slightly different places, and retrieval gets worse.
# EMBED_PREFIXES=off turns them off, to measure the difference.
USE_PREFIXES = os.getenv("EMBED_PREFIXES", "on") == "on" and "nomic-embed" in EMBED_MODEL
PREFIX = {"document": "search_document: ", "query": "search_query: "}

app = FastAPI(title="course-rag")
http = httpx.Client(timeout=300)


def chunks_of(path: Path) -> list[dict]:
    """Split one Markdown file at its ## and ### headings, then cap each piece's size."""
    text = path.read_text(encoding="utf-8")
    title = text.splitlines()[0].lstrip("# ").strip() if text else path.stem
    pieces, heading, buf = [], title, []
    for line in text.splitlines():
        if re.match(r"^#{2,3} ", line):
            if buf:
                pieces.append((heading, "\n".join(buf)))
            heading, buf = line.lstrip("# ").strip(), []
        buf.append(line)
    if buf:
        pieces.append((heading, "\n".join(buf)))
    out = []
    for heading, body in pieces:
        for i in range(0, len(body), CHUNK_CHARS):
            part = body[i : i + CHUNK_CHARS].strip()
            if len(part) > 80:
                out.append({"file": path.name, "title": title, "heading": heading, "text": part})
    return out


def embed(texts: list[str], kind: str) -> list[list[float]]:
    if USE_PREFIXES:
        texts = [PREFIX[kind] + t for t in texts]
    r = http.post(f"{OLLAMA_URL}/api/embed", json={"model": EMBED_MODEL, "input": texts})
    r.raise_for_status()
    return r.json()["embeddings"]


def point_id(chunk: dict) -> str:
    """Same file and text, same id: ingesting twice overwrites instead of duplicating."""
    digest = hashlib.sha256(f"{chunk['file']}|{chunk['text']}".encode()).hexdigest()
    return f"{digest[:8]}-{digest[8:12]}-{digest[12:16]}-{digest[16:20]}-{digest[20:32]}"


def search(question: str, k: int) -> list[dict]:
    vector = embed([question], "query")[0]
    r = http.post(
        f"{QDRANT_URL}/collections/{COLLECTION}/points/search",
        json={"vector": vector, "limit": k, "with_payload": True},
    )
    if r.status_code == 404:
        raise HTTPException(409, "No collection yet: run POST /ingest first.")
    r.raise_for_status()
    return [{"score": round(p["score"], 3), **p["payload"]} for p in r.json()["result"]]


class Question(BaseModel):
    question: str


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/ingest")
def ingest():
    started = time.monotonic()
    chunks = [c for path in sorted(DOCS_DIR.glob("*.md")) if path.name not in EXCLUDE_FILES for c in chunks_of(path)]
    if not chunks:
        raise HTTPException(400, f"No .md files in {DOCS_DIR}")
    vectors = []
    for i in range(0, len(chunks), 32):
        vectors += embed([c["text"] for c in chunks[i : i + 32]], "document")
    embed_seconds = time.monotonic() - started
    # Recreate the collection: the vector size comes from the embedding model.
    http.delete(f"{QDRANT_URL}/collections/{COLLECTION}")
    http.put(
        f"{QDRANT_URL}/collections/{COLLECTION}",
        json={"vectors": {"size": len(vectors[0]), "distance": "Cosine"}},
    ).raise_for_status()
    points = [{"id": point_id(c), "vector": v, "payload": c} for c, v in zip(chunks, vectors)]
    for i in range(0, len(points), 128):
        http.put(
            f"{QDRANT_URL}/collections/{COLLECTION}/points?wait=true", json={"points": points[i : i + 128]}
        ).raise_for_status()
    return {
        "files": len({c["file"] for c in chunks}),
        "chunks": len(chunks),
        "dimensions": len(vectors[0]),
        "embed_model": EMBED_MODEL,
        "embed_prefixes": USE_PREFIXES,
        "embed_seconds": round(embed_seconds, 1),
        "total_seconds": round(time.monotonic() - started, 1),
    }


@app.get("/search")
def search_only(q: str, k: int = TOP_K):
    return {"question": q, "results": [{k2: r[k2] for k2 in ("score", "file", "heading")} for r in search(q, k)]}


def ask_claude(messages: list[dict]) -> tuple[str, int, int]:
    """Same prompt as the Ollama path: the system message moves to Claude's system field."""
    response = claude.beta.messages.create(
        model=CHAT_MODEL,
        max_tokens=4000,
        system=messages[0]["content"],
        messages=messages[1:],
        output_config={"effort": "low"},
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
    )
    if response.stop_reason == "refusal":
        return "The model declined to answer this question.", response.usage.input_tokens, response.usage.output_tokens
    text = "".join(block.text for block in response.content if block.type == "text")
    return text, response.usage.input_tokens, response.usage.output_tokens


@app.post("/ask")
def ask(body: Question):
    started = time.monotonic()
    hits = search(body.question, TOP_K)
    retrieve_seconds = time.monotonic() - started
    context = "\n\n---\n\n".join(f"[{i + 1}] {h['file']} / {h['heading']}\n{h['text']}" for i, h in enumerate(hits))
    messages = [
        {
            "role": "system",
            "content": "You answer questions about a Kubernetes course. Use only the numbered context. "
            "Cite sources as [1], [2]. If the context doesn't contain the answer, say you don't know.",
        },
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {body.question}"},
    ]
    if PROVIDER == "anthropic":
        answer, input_tokens, output_tokens = ask_claude(messages)
    else:
        r = http.post(
            f"{OLLAMA_URL}/api/chat",
            json={"model": CHAT_MODEL, "messages": messages, "stream": False, "options": {"num_predict": 250, "temperature": 0}},
        )
        r.raise_for_status()
        out = r.json()
        answer, input_tokens, output_tokens = out["message"]["content"], out.get("prompt_eval_count"), out.get("eval_count")
    return {
        "answer": answer,
        "sources": [{"n": i + 1, "score": h["score"], "file": h["file"], "heading": h["heading"]} for i, h in enumerate(hits)],
        "chat_model": CHAT_MODEL,
        "input_tokens": input_tokens,
        "output_tokens": output_tokens,
        "retrieve_seconds": round(retrieve_seconds, 2),
        "total_seconds": round(time.monotonic() - started, 1),
    }
