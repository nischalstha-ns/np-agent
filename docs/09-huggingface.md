# NP — HuggingFace Integration

**Version:** 0.1 (design) · **Status:** Draft · **Last updated:** 2026-10-12

The HF service lets users search, compare, download (resumable + verified),
install, update, and switch GGUF models — all from the Models dashboard.
It is **online-only** and never runs implicitly: every download is user-initiated.

---

## 1. Responsibilities

| Operation | Description |
|-----------|-------------|
| Search | Query `huggingface.co/api/models` filtered to GGUF (`filter=gguf`) + family tags; rank by likes/downloads, recency |
| Recommend | Given device RAM (from perf profile), suggest family + quant fitting the 4 GB budget table (`04-offline-llm.md` §6) |
| Download | Resumable download of a single `*.gguf` file → `/downloaded_models`, with progress events to the downloads dashboard |
| Verify | SHA-256 checksum against the value published in the repo (`*.sha256` sidecar or API metadata); quarantined on mismatch |
| Compare | Side-by-side table: size, quant, params, license, likes, 4 GB fit verdict |
| Install | Move verified file into the active discovery dir, register in `models` table |
| Update | Check for newer revisions of installed models; re-download on user approval |
| Switch | Set active model → triggers `switchModel()` in the LLM service (see `04-offline-llm.md` §4) |

## 2. Search API usage

```
GET https://huggingface.co/api/models?filter=gguf&search=<query>&sort=likes&direction=-1&limit=20
```

- Client: Dart `http` with 30 s timeout; results cached 1 hour in SQLite
  (`hf_cache` table) to spare the API.
- Post-filter in Dart: keep repos whose sibling list contains `*.gguf`
  (fetched via `GET /api/models/{repo}` → `siblings[].rfilename`).
- Quant parsing: regex on filename (`Q4_K_M`, `Q5_K_S`, …); files without a
  recognized quant tag are shown but flagged "unknown quant".
- License surfaced from repo tags (informational; NP does not give legal advice).

## 3. GGUF file selection

For a chosen repo, the UI lists GGUF siblings with:

```
file name · size · quant · fit verdict (✅ fits / ⚠️ tight / ❌ over budget)
```

- **Fit verdict** computed from the budget table: `weights(size) + ctxKV(n_ctx) +
  overhead(600 MB)` vs. device RAM. Default `n_ctx` = 2048 for verdicts.
- Only **one file** per download (no multi-part GGUF in v0.x — repos that
  split weights are flagged "unsupported").
- Recommended default per family shown first (e.g. Qwen 3B → `Q4_K_M`).

## 4. Resumable download

```
GET {repo}/resolve/main/{file}  with  Range: bytes=<existing>- 
→ stream to /downloaded_models/.part/<file>.part
→ progress events (bytes/total, ETA) → downloads dashboard
→ on complete: rename .part → final
```

- **Resume:** on network drop or app restart, `Range` resumes from the `.part`
  size. Up to 5 automatic retries with exponential backoff; then paused state
  the user can resume manually.
- **Interrupts:** pause/cancel buttons; cancel deletes the `.part` file after
  confirmation.
- Downloads never start on metered connections without explicit approval
  (platform network-info check; best-effort).

## 5. SHA-256 verification

1. After download completes, compute SHA-256 over the file (streaming hash,
   ~50 MB/s on target CPU — a 4 GB file takes ~80 s; progress shown).
2. Compare against the published digest: preferred source is a `*.sha256`
   sidecar in the repo; fallback is the `sha256` field in the model's API
   metadata where present.
3. **Match** → install (register in `models`, move to discovery dir).
   **Mismatch / no digest available** → file quarantined to
   `/downloaded_models/.quarantine/`, user warned, model marked `unverified`;
   unverified models can still be loaded only with a Sensitive-tier override.
4. The verified digest is stored in `models.sha256` for future integrity
   re-checks.

## 6. Local model registry

The `models` table (schema in `04-offline-llm.md` §7) is the single source of
truth. HF service upserts on download/install/update; `ModelDiscovery` upserts
on disk scan. Fields track `is_active` (exactly one row), `sha256`, and
`family='stt'` for voice models (whisper/vosk, downloaded the same way).

## 7. Switching the active model

```
User picks model in Models dashboard
  → budget check (projected RAM vs. device; refuse-or-override)
  → LlmService.switchModel(id): unload → load (mmap) → warm-up decode
  → models.is_active updated; audit-logged ('model.switch')
  → old model stays on disk (no auto-delete; user manages storage)
```

Switching is instant from the user's perspective except the warm-up pause
("Warming up…" in chat). If the new model fails to load, NP automatically
falls back to the previous active model and writes a failure record.

## 8. Offline behavior

All HF operations require Online mode. In Offline mode the Models dashboard
shows only installed models; search/download/update buttons are disabled with
the tooltip "Requires internet". The local registry and switching work fully
offline.
