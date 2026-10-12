# NP — hybrid Offline+Online AI Operating System Agent

Flutter project scaffold (`app/`, package name `np`). Hand-written, no
`flutter create`, no dependency resolution performed.

## Layout

- `app/lib/main.dart` — console-style bootstrap: DI → `NpCore.initialize()`
  → banner → handles a prompt passed as CLI args.
- `app/lib/core/` — `config.dart` (model dirs `/models /gguf
  /downloaded_models`, constants), `result.dart` (`Result<T>`/`NpError`),
  `di.dart` (service-locator DI).
- `app/lib/agents/` — `agent.dart` (base), `pipeline.dart` (the real
  orchestrator: Input → planner → reasoning → memory → tool selection →
  execution → verification → learning → Response, with per-stage timing and
  failure records), `np_core.dart` (wiring facade), plus planner, reasoning,
  memory, tool, vision, speech, learning, verification, safety, automation
  agents.
- `app/lib/memory/` — `memory_store.dart` (sqflite, all 9 tables, real CRUD),
  `embeddings.dart` (offline hashing embeddings + cosine), `retrieval.dart`
  (similarity + recency + importance scoring), and 7 typed layer wrappers.
- `app/lib/tools/` — six-layer `Tool` contract, permission-checked
  `ToolRegistry`, real `file`/`terminal`/`browser`/`code` tools, and
  interface-consistent stubs (media + productivity) that throw
  `UnimplementedError` with clear messages.
- `app/lib/llm/` — provider contract, `llama_bindings.dart` (dart:ffi
  signatures for llama.cpp), offline GGUF provider (model discovery +
  quant parsing work without the native engine), OpenAI-compatible online
  provider, and the offline/online `router.dart`.
- `app/lib/voice/` `app/lib/vision/` — contracts (wake word, STT/TTS with
  barge-in controller, OCR, screen understanding); native engines needed.
- `app/lib/control/` — abstract `DesktopControl` + Windows/Linux/macOS/
  Android subclasses (capability matrix in docs; actions need native plugins).
- `app/lib/hf/` — HuggingFace client: model search, GGUF listing, resumable
  downloads with sha256 verification, `ModelRegistry`, zip extraction.
- `app/lib/ui/` — `ChatBubble`, `ChatWindowController` (wired to `NpCore`),
  dashboard panels (tool/memory/download/model/performance/agent) over live
  state streams. No Material widgets shipped — state layer only.

## Honest boundaries

Works fully offline where marked real (tools, memory, retrieval, pipeline,
planning, model discovery). Needs native plugins/accounts where marked:
llama.cpp engine for GGUF inference, whisper.cpp/Vosk + Piper for
voice, ML Kit/Tesseract for OCR, OS plugins for desktop control, and API
keys/accounts for online LLM, email, calendar, and research tools.

## Run (once Flutter/Dart SDK is available)

```sh
cd app
flutter pub get
dart run lib/main.dart "list files in /tmp"
```
