# NP — Offline LLM (GGUF via llama.cpp)

**Version:** 0.1 (design) · **Status:** Draft · **Last updated:** 2026-10-12

NP's offline brain is a quantized GGUF model executed through llama.cpp,
bound to Dart with `dart:ffi`. This document covers the loader design, the FFI
surface, streaming, lifecycle, quantization choices, and the 4 GB RAM budget.

---

## 1. Architecture

```mermaid
flowchart TB
    subgraph Dart
        LS[LlmService]
        LD[ModelDiscovery]
        LQ[QuantGuide]
    end
    subgraph FFI
        LB[llama_bindings.dart<br/>dart:ffi signatures]
    end
    subgraph Native
        LC[libllama.so / llama.dll / libllama.dylib<br/>llama.cpp shared library]
        WH[whisper.cpp — STT]
    end
    subgraph Disk
        M1[/models]
        M2[/gguf]
        M3[/downloaded_models]
    end

    LS --> LB --> LC
    LD --> M1 & M2 & M3
    LD --> LS
    LS -.->|token callbacks| UI[Flutter UI stream]
```

- **One native library** (`libllama`) is loaded once per process; model weights
  are loaded/unloaded dynamically as contexts.
- whisper.cpp is a separate native lib with its own tiny FFI surface
  (see `05-voice.md`); it shares the GGUF discovery dirs for STT models.

## 2. Model discovery

`ModelDiscovery` scans, in order, `/models`, `/gguf`, `/downloaded_models`
(under the NP data dir; user-configurable extra dirs):

1. Enumerate `*.gguf` files recursively (max depth 3).
2. Parse GGUF metadata (via `llama_model_meta_val_str`: `general.name`,
   `general.size_label`, quantization inferred from file).
3. Build a `ModelCard {id, path, name, params, quant, sizeBytes, sha256?}`.
4. Persist to SQLite `models` table (see §7); the HF service upserts rows on
   download (see `09-huggingface.md`).

Missing dirs are created on first run. Non-GGUF files are ignored.

## 3. llama.cpp integration via dart:ffi

We bind the **C API** (`llama.h`), not the C++ internals. The binding file
`lib/native/llama_bindings.dart` declares:

```dart
// ---- Lifecycle ----
typedef _llama_init_native = Void Function();
typedef _llama_init_dart = void Function();
void llama_backend_init();

typedef _llama_model_load_native = Pointer<Opaque> Function(Pointer<Utf8> path, Pointer<Opaque> params);
typedef _llama_model_load_dart = Pointer<Opaque> Function(Pointer<Utf8> path, Pointer<Opaque> params);
Pointer<Opaque> llama_model_load_from_file(String path, ModelParams params);

typedef _llama_model_free_native = Void Function(Pointer<Opaque> model);
typedef _llama_model_free_dart = void Function(Pointer<Opaque> model);
void llama_model_free(Pointer<Opaque> model);

// ---- Context ----
Pointer<Opaque> llama_new_context_with_model(Pointer<Opaque> model, ContextParams params);
void llama_free(Pointer<Opaque> ctx);
// ContextParams: n_ctx, n_threads, n_threads_batch, offload_kqv=false (CPU-only)

// ---- Tokenization ----
int llama_tokenize(Pointer<Opaque> model, Pointer<Utf8> text, int textLen,
    Pointer<Int32> tokens, int nTokensMax, bool addBos, bool special);
int llama_token_to_piece(Pointer<Opaque> model, int token, Pointer<Utf8> buf, int len);

// ---- Batched decode (the hot loop) ----
Pointer<Opaque> llama_batch_init(int nTokens, int embd, int nSeqMax);
bool llama_decode(Pointer<Opaque> ctx, Pointer<Opaque> batch);
int llama_sampler_sample(Pointer<Opaque> sampler, Pointer<Opaque> ctx, int idx);

// ---- Sampler chain (temp/top-k/top-p/min-p/repeat penalty) ----
Pointer<Opaque> llama_sampler_chain_init(Pointer<Opaque> chainParams);
void llama_sampler_chain_add(Pointer<Opaque> chain, Pointer<Opaque> sampler);

// ---- Streaming generation (Dart-side driver) ----
// Dart runs llama_decode in an Isolate; each sampled token is converted with
// llama_token_to_piece and pushed to a StreamController<String> —
// the "streaming token callback" the UI subscribes to.
```

### 3.1 Generation driver (Dart isolate)

```
prompt → tokenize → llama_batch_add(tokens) → loop:
    llama_decode(ctx, batch)
    token = sampler_sample(...)
    piece = token_to_piece(token) → yield to Stream
    break on EOS or maxTokens
    batch = single next token
```

- The decode loop runs in a dedicated `Isolate` so the UI thread never blocks.
- Cancellation: `unloadModel()` / new prompt sets an atomic flag checked each
  iteration; the isolate exits cleanly and frees the batch.
- `n_threads` defaults to `Platform.numberOfProcessors - 1` (min 2), capped at 8.

## 4. Dynamic load / unload & lazy weight loading

| Operation | Behavior |
|-----------|----------|
| `loadModel(path)` | `llama_model_load_from_file` with mmap enabled; weights are **memory-mapped, not copied** — the OS pages them in on demand (this is the "lazy weight loading": first-token latency pays the page-in cost, steady-state stays within budget). |
| `unloadModel()` | `llama_free(ctx)` + `llama_model_free(model)`; releases mmap + KV cache. |
| `switchModel(id)` | unload current → load new → warm-up (decode a short "OK" prompt to page in hot weights) → ready. |
| Idle policy | If no generation for `idleUnloadSec` (default 600 s) and RAM pressure is high, `np_core` unloads the model automatically; next prompt reloads transparently. |
| VRAM | None — CPU-only target. `n_gpu_layers = 0` always in v0.x. |

## 5. Quantization guide (Q2_K … Q5_K)

llama.cpp K-quants trade perplexity for size. Guidance for the 4 GB target:

| Quant | Bits/weight ≈ | Quality | Use when |
|-------|---------------|---------|----------|
| Q2_K | ~2.5 | Noticeable degradation; short answers OK | TinyLlama/SmolLM on very weak hardware |
| Q3_K_M | ~3.5 | Good for chat, weak at reasoning | 7–8B models when Q4 doesn't fit |
| Q4_K_M | ~4.5 | **Recommended default** — near-fp16 quality | 7–8B models on the 4 GB target |
| Q4_K_S | ~4.0 | Slightly below Q4_K_M | Tight budgets |
| Q5_K_M | ~5.5 | Best sub-6-bit quality | ≤3B models, or machines with >4 GB |

**Supported model families** (GGUF): TinyLlama, Gemma, Phi, Qwen, DeepSeek,
SmolLM. The HF service filters searches to `*.gguf` files and surfaces the
quant in the file name.

**Recommendation matrix:**

| Device RAM | Model size | Suggested quant |
|------------|-----------|-----------------|
| 4 GB (target) | 1–3B | Q5_K_M or Q4_K_M |
| 4 GB (target) | 7–8B | Q4_K_M (see budget table — tight, works with small context) |
| 8 GB+ | 7–8B | Q5_K_M |
| 8 GB+ | 13B | Q4_K_M |

## 6. 4 GB RAM budget table

Assumptions: CPU-only, fp32 KV cache at 16-bit equivalent (llama.cpp default
`q8_0` KV), overhead = runtime + embeddings + app baseline ≈ 600 MB.
`total ≈ weights + ctxKV + overhead`. **Must stay ≤ ~3.4 GB** to leave room
for the OS on a 4 GB machine.

| Model | Quant | Weights | n_ctx=2048 KV | n_ctx=4096 KV | Overhead | Total (2k ctx) | Fits 4 GB? |
|-------|-------|---------|---------------|---------------|----------|----------------|------------|
| SmolLM 1.7B | Q5_K_M | ~1.2 GB | ~0.3 GB | ~0.5 GB | 0.6 GB | **~2.1 GB** | ✅ comfortable |
| TinyLlama 1.1B | Q5_K_M | ~0.8 GB | ~0.2 GB | ~0.4 GB | 0.6 GB | **~1.6 GB** | ✅ comfortable |
| Qwen 3B | Q4_K_M | ~1.8 GB | ~0.4 GB | ~0.7 GB | 0.6 GB | **~2.8 GB** | ✅ |
| Phi 3.8B | Q4_K_M | ~2.3 GB | ~0.5 GB | ~0.9 GB | 0.6 GB | **~3.4 GB** | ⚠️ borderline — use n_ctx 2048 |
| Gemma 7B | Q4_K_M | ~4.1 GB | ~0.8 GB | ~1.3 GB | 0.6 GB | **~5.5 GB** | ❌ — use Q3_K_M (~3.4 GB weights) or 2k ctx |
| Qwen 7B | Q4_K_M | ~4.0 GB | ~0.7 GB | ~1.2 GB | 0.6 GB | **~5.3 GB** | ❌ — needs Q3_K_M / smaller ctx |
| DeepSeek 7B | Q4_K_M | ~4.1 GB | ~0.8 GB | ~1.3 GB | 0.6 GB | **~5.5 GB** | ❌ — needs Q3_K_M |
| Qwen 7B | Q3_K_M | ~3.4 GB | ~0.7 GB | ~1.2 GB | 0.6 GB | **~4.7 GB** | ⚠️ — 2k ctx + idle unload; tight |

> **Design rule:** the out-of-box default model is a **~3B Q4_K_M** model
> (≈2.8 GB total at 2k context) — comfortably inside budget with headroom for
> voice + tools. 7B models are supported but flagged "tight" in the Models
> dashboard with automatic `n_ctx=2048` and aggressive idle-unload.

KV cache scales linearly with `n_ctx`; the Models dashboard shows a live
estimate (`weights + ctxKV + overhead`) before the user switches models, and
refuses loads projected over budget unless the user overrides.

## 7. Supporting schema

```sql
CREATE TABLE models (
  id         TEXT PRIMARY KEY,      -- uuid or hf repo+file
  name       TEXT NOT NULL,
  path       TEXT NOT NULL UNIQUE,
  family     TEXT,                  -- qwen | gemma | phi | ...
  params     TEXT,                  -- '3B', '7B'
  quant      TEXT,                  -- 'Q4_K_M'
  size_bytes INTEGER NOT NULL,
  sha256     TEXT,                  -- filled after HF verify
  is_active  INTEGER NOT NULL DEFAULT 0,
  discovered_at INTEGER NOT NULL
);
```

## 8. Failure modes

| Failure | Handling |
|---------|----------|
| Corrupt GGUF (load fails) | Mark model `broken` in registry; suggest re-download with resume |
| OOM during load | Catch, unload, suggest smaller quant; write failure record |
| Slow first token (page-in) | Show "warming up…" progress; pre-warm on switch |
| Sampler degeneration (repetition) | Repeat-penalty + min-p defaults; verification_agent flags degenerate outputs |
