# NP — Roadmap (MVP → v1.0)

**Version:** 0.1 (design) · **Status:** Draft · **Last updated:** 2026-10-12

---

## 1. Phases & milestones

### Phase 0 — Foundations (MVP core)
*Goal: an offline agent that chats, remembers, and uses tools on one desktop OS.*

- [ ] Flutter shell: chat window + floating bubble (Windows + Linux first)
- [ ] `np_core` pipeline skeleton with all 11 agents stubbed; fixed pipeline order enforced
- [ ] llama.cpp `dart:ffi` bindings: load, tokenize, decode loop, streaming callbacks
- [ ] Model discovery (`/models`, `/gguf`, `/downloaded_models`) + 3B Q4_K_M default model
- [ ] SQLite `np.db`: `memory_items`, `user_profile`, `tool_usage`, `projects`, `skills`, `failure_records`, `tasks`, `audit_log`, `models`
- [ ] Local embeddings + cosine retrieval; retrieval-before-generation wired into pipeline
- [ ] ToolRegistry + first 6 tools: `file`, `terminal`, `code`, `task`, `memory`, `pdf`
- [ ] Permission tiers (Open/Confirm/Sensitive) + basic consent chips; audit logging
- **Exit criteria:** offline chat with memory + file/terminal tools works end-to-end on a 4 GB machine.

### Phase 1 — Voice & remaining tools (MVP complete)
- [ ] `speech_agent`: "Hey NP" wake-word, whisper.cpp STT, Piper TTS, barge-in, voice overlay
- [ ] Remaining tools: `browser`, `image`, `video`, `audio`, `calendar`, `email`, `document`, `database`, `automation`, `research`
- [ ] `verification_agent` + `learning_agent`: failure records, prevention rules, rule compiler
- [ ] Dashboards: tools, memory (+ rules tab), performance, agent panel
- [ ] Wayland portal support + macOS adapter for desktop control
- **Exit criteria (MVP):** voice-driven offline agent; all 16 tools; learning loop demonstrably reduces repeat failures.

### Phase 2 — Models & polish (v1.0-beta)
- [ ] HF service: search/recommend/download (resume + sha256)/compare/install/update/switch + downloads & models dashboards
- [ ] Android app + Accessibility-service automation adapter
- [ ] Sandboxing hardening: subprocess caps, browser quarantine, secret scrubber v2 (3-point)
- [ ] Idle-unload RAM policy, lazy weight loading verified against the 4 GB budget table
- [ ] Settings: permissions manager, offline-only toggle, voice selection
- **Exit criteria:** installable on Windows/Linux/macOS/Android; HF model swap in < 2 min on broadband.

### Phase 3 — v1.0 release
- [ ] Security audit of the threat model (`07-security.md` §6); fuzz tool-input schemas
- [ ] Performance pass: cold-start time, first-token latency, STT/TTS latency vs. budgets
- [ ] Onboarding: first-run model download wizard, permission grants walkthrough
- [ ] Documentation site from these docs + user guide
- **Exit criteria:** tagged v1.0, signed builds, published checksums.

### Post-v1.0 (not committed)
Custom wake-word phrases · multi-part GGUF · on-device fine-tuning/LoRA ·
server/multi-user mode · plugin API for third-party tools · iOS support.

## 2. Production implementation plan

| Workstream | Owner (agent) | Depends on |
|------------|---------------|------------|
| Pipeline & agent contracts | np_core, planner, reasoning | Phase 0 start |
| llama.cpp FFI + LLM service | (service layer) | Phase 0 start |
| Memory service + embeddings | memory_agent | Phase 0, parallel with FFI |
| Tool framework + batch 1 tools | tool_agent, safety_agent | Phase 0 after pipeline skeleton |
| Voice stack | speech_agent | Phase 1 |
| Desktop control adapters | automation_agent | Phase 1 (Linux/macOS), Phase 2 (Android) |
| Learning & verification | learning_agent, verification_agent | Phase 1 |
| HF integration | (service layer) | Phase 2 |
| UI dashboards | (presentation) | Throughout, Phase-gated |

**Build order principle:** pipeline skeleton → one vertical slice (chat +
one tool end-to-end) → broaden tools → voice → models → harden. Never build
two unintegrated subsystems in parallel without a contract test between them.

## 3. Assumptions

Reasonable simplifications made while writing these design docs — revisit
before implementation where flagged:

1. **Single-user, single-device.** No accounts, no sync, no conflict resolution.
   Memory DB is one SQLite file; online features are per-user OAuth.
2. **No on-device training.** "Learning" = rules + memory + prompt context,
   never gradient updates (explicit non-goal).
3. **CPU-only, 4 GB floor.** No GPU offload in v0.x (`n_gpu_layers = 0`);
   7B models are "tight" and 3B Q4_K_M is the default.
4. **Fixed 16-tool set.** No third-party plugin API in v0.x; composition is
   planner-driven, tools never call tools.
5. **llama.cpp C API stability.** The FFI surface assumes `llama.h`'s
   load/context/batch/sampler API shape; pin a llama.cpp release and re-verify
   bindings on upgrade.
6. **Embedding model ships with NP** (~80 MB quantized) and vectors are
   model-pinned; changing it requires background re-embedding.
7. **Wayland limitations accepted.** No global window control under Wayland;
   portals + consent dialogs are the design, not a workaround.
8. **macOS via platform channels, not pure FFI.** Cocoa automation goes
   through Swift; WinAPI/X11 go through `dart:ffi`.
9. **English-first voice.** "Hey NP" spotter + one Piper voice + whisper
   tiny/base English; multilingual is post-v1.0.
10. **SHA-256 sidecars may not exist** for every HF repo — unverified models
    load only with explicit Sensitive-tier override.
11. **Consent UX is blocking and synchronous** from the pipeline's view;
    async approvals (e.g. phone confirmation) are out of scope.
12. **Audit log retention 180 days**, then pruned — a product decision, not a
    legal one; adjust per jurisdiction before v1.0.

## 4. Implementation status — what is REAL vs MOCK (2026-10-12)

The scaffold was hardened so that everything below actually runs. Honest
accounting, per the `REAL:`/`MOCK:` doc-comment convention now enforced on
every public API in `app/lib`:

### REAL (pure-Dart, works today in `dart run` and in Flutter)
- **All 16 tools** implement the 6-layer contract with real logic:
  `file` (dart:io + path-traversal guard confined to allowed roots, copy/move
  included), `terminal` (real `Process.run` + timeout + working dir; denies
  `rm -rf /`, `mkfs`, fork bombs…), `code` (real `dart analyze`/`dart format`
  subprocesses + heuristic analysis + regex symbols), `browser` (real HTTP via
  `package:http`; `page` extracts title/text/links), `research` (real
  DuckDuckGo-HTML + Wikipedia-API multi-source search with graceful offline
  fallback), `database` (read-only wrapper over the app's `MemoryStore`),
  `task` (CRUD over the `tasks` table), `calendar`/`email` (local JSON stores
  under `~/.np`; email "send" only queues to a local outbox — no SMTP),
  `pdf` (pure-Dart BT/ET + Tj/TJ text extraction), `document` (real
  .txt/.md/.json/.csv read/write), `image`/`video`/`audio` (real file-size and
  PNG/JPEG header probing), `automation` (delegates to `AutomationAgent`,
  every step re-passes the safety gate), `memory` (meta-tool over the store).
- **Memory**: `MemoryStore` (sqflite) plus `InMemoryMemoryStore`
  (Maps/Lists, full API parity) for pure-Dart runs and tests.
- **LLM routing**: real `OfflineLlmProvider` (GGUF discovery + load) when a
  `.gguf` file is on disk, else configured online provider, else
  `MockStreamingProvider` (word-by-word streaming, intent-based replies).
- **Method-channel contracts** (`lib/native/channels.dart`): one clean
  interface per native capability (microphone, STT, TTS, wake-word,
  OS control, llama.cpp) with channel names + method shapes; real
  `MethodChannel` transport in `method_channel_transport.dart`
  (Flutter builds only).
- **Pure-Dart PNG synthesis** for mock screenshots (stored-block DEFLATE +
  Adler-32/CRC-32, no zlib dependency).

### MOCK (simulated; clearly labeled, never mistaken for real)
- Microphone capture, whisper.cpp/Vosk STT, Piper TTS, wake-word engine,
  WinAPI/X11/Cocoa/Android desktop control, llama.cpp inference — each has a
  `Mock*` implementation (`lib/native/mock_channels.dart`, `lib/voice/*_mock.dart`,
  `lib/vision/*_mock.dart`, `lib/control/mock_desktop.dart`) wired by
  `NpCore.initialize(useMocks: true)` (the default).
- `MockOcr`/`MockScreenUnderstanding` return canned results marked simulated.
- Media *transforms* (resize/convert/transcode/synthesize) fail honestly with
  "transform requires native codec" unless a `MediaEngineChannel` is attached
  (the mock engine copies + sidecars instead of real pixel work).
- `Null*` fallbacks remain for unattached engines (they report unavailability
  instead of hallucinating).

### Still missing (not started)
- Real native plugins (whisper.cpp, Piper, openWakeWord, WinAPI/X11/CGEvent/
  Accessibility bridges, llama.cpp shared library build).
- Cloud calendar/email accounts (local JSON stores only), SMTP sending.
- Real image/video/audio generation or transcoding codecs.
- Encrypted/exotic PDFs (best-effort text extraction only).

### Platform support (updated 2026-10-12)
- **Target platforms: Windows, Linux, Android, macOS** (all `dart:io` platforms).
  `flutter analyze` is clean and `flutter test` passes 162/162 on these.
- **Web is NOT a target platform.** `flutter build web` fails because the
  agent is inherently an OS-control agent: `dart:io` (processes, filesystem,
  sockets) and `dart:ffi` (llama.cpp) do not exist on web. Making the tools
  web-safe would mean stubbing the very capabilities that define the product,
  so this is an explicit non-goal. The Flutter UI itself (`lib/ui`) is written
  web-clean (conditional imports where `dart:io` was needed).
- **UI status**: the premium Material 3 dark-glassmorphism shell IS built
  (`lib/ui/`: chat with streaming reveal, floating bubble, voice overlay,
  5-tab dashboard, model manager). `main.dart` launches it; `--cli` keeps the
  console entry point.

### Retired assumptions
- Assumption 5 (llama.cpp C API stability) still holds for the FFI typedefs,
  but inference now has a defined mock fallback instead of a hard error.
- The design doc's tool schemas (`03-tools.md` §3) describe *intent*; the
  shipped tools use action-based schemas documented in code — see the
  implementation-status table added to `03-tools.md` §3.
