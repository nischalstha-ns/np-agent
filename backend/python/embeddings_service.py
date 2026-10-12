"""NP agent — local embedding service.

A small, REAL, working embedding server with zero network access and no
model downloads. Vectors are produced by a deterministic hashing trick
(signed random projection over character n-grams), so:

  * the same text always yields the same vector,
  * similar texts yield similar vectors (cosine),
  * everything runs offline on-device.

This is a stand-in for a real embedding model (e.g. a GGUF encoder run
through the Rust backend). It is good enough for ranking / recall over the
``memory_items`` table while the native encoder is being integrated.

Run:  python embeddings_service.py [--host 127.0.0.1] [--port 8765]

Endpoints (stdlib http.server only):
  POST /embed       {"text": "..."}            -> {"embedding": [float, ...]}
  POST /similarity  {"a": "...", "b": "..."}  -> {"similarity": float}
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import List

import numpy as np

DIM = 256  # embedding dimension; keep in sync with Flutter memory layer config
_TOKEN_RE = re.compile(r"[a-z0-9]+")


class EmbeddingService:
    """Deterministic hashing-based text embedder (offline, no downloads)."""

    def __init__(self, dim: int = DIM) -> None:
        self.dim = dim

    @staticmethod
    def _ngrams(text: str) -> List[str]:
        tokens = _TOKEN_RE.findall(text.lower())
        grams: List[str] = []
        for tok in tokens:
            padded = f"^{tok}$"
            grams.extend(padded[i : i + 3] for i in range(len(padded) - 2))
        return grams or ["<empty>"]

    def _signed_index(self, gram: str) -> tuple[int, float]:
        digest = hashlib.sha256(gram.encode("utf-8")).digest()
        idx = int.from_bytes(digest[:4], "little") % self.dim
        sign = 1.0 if digest[4] & 1 else -1.0
        return idx, sign

    def embed(self, text: str) -> List[float]:
        """Map text -> deterministic unit-norm float vector of length dim."""
        vec = np.zeros(self.dim, dtype=np.float64)
        for gram in self._ngrams(text):
            idx, sign = self._signed_index(gram)
            vec[idx] += sign
        norm = float(np.linalg.norm(vec))
        if norm > 0:
            vec /= norm
        return vec.tolist()

    def batch_embed(self, texts: List[str]) -> List[List[float]]:
        return [self.embed(t) for t in texts]


def cosine_similarity(a: List[float], b: List[float]) -> float:
    """Cosine similarity in [-1, 1]; returns 0.0 for zero/empty vectors."""
    if not a or not b or len(a) != len(b):
        return 0.0
    va, vb = np.asarray(a, dtype=np.float64), np.asarray(b, dtype=np.float64)
    denom = float(np.linalg.norm(va) * np.linalg.norm(vb))
    if denom == 0.0 or not math.isfinite(denom):
        return 0.0
    return float(np.dot(va, vb) / denom)


_SERVICE = EmbeddingService()


class _Handler(BaseHTTPRequestHandler):
    server_version = "NPEmbed/0.1"

    def _send_json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict:
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            data = json.loads(raw.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            data = None
        return data if isinstance(data, dict) else {}

    def do_POST(self) -> None:  # noqa: N802 (http.server convention)
        data = self._read_json()
        if self.path == "/embed":
            text = data.get("text", "")
            if not isinstance(text, str):
                self._send_json({"error": "'text' must be a string"}, 400)
                return
            self._send_json({"embedding": _SERVICE.embed(text), "dim": DIM})
        elif self.path == "/similarity":
            a, b = data.get("a", ""), data.get("b", "")
            if not isinstance(a, str) or not isinstance(b, str):
                self._send_json({"error": "'a' and 'b' must be strings"}, 400)
                return
            sim = cosine_similarity(_SERVICE.embed(a), _SERVICE.embed(b))
            self._send_json({"similarity": sim})
        else:
            self._send_json({"error": "unknown endpoint"}, 404)

    def log_message(self, fmt: str, *args) -> None:  # quieter logs
        print(f"[np-embed] {self.address_string()} {fmt % args}")


def serve(host: str = "127.0.0.1", port: int = 8765) -> None:
    httpd = HTTPServer((host, port), _Handler)
    print(f"[np-embed] serving on http://{host}:{port} (Ctrl-C to stop)")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\n[np-embed] stopped")


def main() -> None:
    parser = argparse.ArgumentParser(description="NP local embedding service")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument(
        "--demo",
        action="store_true",
        help="print a quick offline embed/similarity demo instead of serving",
    )
    args = parser.parse_args()

    if args.demo:
        svc = EmbeddingService()
        a = svc.embed("remind me to buy milk tomorrow")
        b = svc.embed("remind me to buy milk tomorrow")
        c = svc.embed("quantum field theory lecture notes")
        print("dim:", len(a), "| self-similarity:", cosine_similarity(a, b))
        print("cross-topic similarity:", round(cosine_similarity(a, c), 4))
        return
    serve(args.host, args.port)


if __name__ == "__main__":
    main()
