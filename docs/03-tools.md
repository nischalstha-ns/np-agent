# NP — Tool Framework & Tool Specifications

**Version:** 0.1 (design) · **Status:** Draft · **Last updated:** 2026-10-12

NP ships 16 tools. Every tool implements the same 6-layer contract, is
registered in a central `ToolRegistry`, and is invoked only through the
`tool_agent` → `safety_agent` → execution → `verification_agent` path.

---

## 1. The 6-layer Tool contract

```dart
abstract class Tool {
  // Layer 1 — Description: name, human summary, when to use / not use.
  ToolDescription get description;

  // Layer 2 — Input schema: JSON Schema for arguments (validated before run).
  JsonSchema get inputSchema;

  // Layer 3 — Output schema: JSON Schema for results (validated after run).
  JsonSchema get outputSchema;

  // Layer 4 — Permission layer: tier + consent rules (see 07-security.md).
  PermissionTier get permission;   // open | confirm | sensitive | blocked_offline...

  // Layer 5 — Execution layer: the actual work. Sandboxed where required.
  Future<ToolOutput> execute(ToolInput input, ExecutionCtx ctx);

  // Layer 6 — Verification layer: how verification_agent checks the result.
  VerificationSpec get verification;
}
```

| Layer | Purpose | Enforced by |
|-------|---------|-------------|
| 1. Description | Lets planner/reasoning choose the right tool; shown in UI | ToolRegistry listing |
| 2. Input schema | Reject malformed calls before anything runs | `tool_agent` |
| 3. Output schema | Reject unexpected results before they reach the LLM | `verification_agent` |
| 4. Permission | Tier per tool + per-operation; consent prompts | `safety_agent` |
| 5. Execution | Sandboxed implementation, timeouts, streaming progress | Tool impl |
| 6. Verification | Assertions: exit codes, checksums, content checks | `verification_agent` |

`ToolOutput` is uniform:

```dart
class ToolOutput {
  final bool ok;
  final Map<String, dynamic> data;   // must validate against outputSchema
  final String? error;               // scrubbed, no secrets
  final int latencyMs;
  final List<String> artifacts;      // file paths produced, if any
}
```

## 2. ToolRegistry design

```dart
class ToolRegistry {
  final Map<String, Tool> _tools;
  void register(Tool t);                 // duplicates throw
  Tool resolve(String name);             // throws UnknownTool
  List<ToolDescription> describeFor(Mode mode);
  // describeFor filters: online-only tools hidden in Offline mode,
  // and each description carries its permission tier so the planner
  // can prefer low-friction tools.
}
```

- Registration happens at startup; third-party tools are **not** supported in
  v0.x (fixed set of 16).
- `describeFor(mode)` returns the tool catalog injected into the planner and
  reasoning prompts — this is how Offline mode hides `browser`, `research`,
  and HF-backed operations.
- Every call is logged to `tool_usage` (args hashed post-scrub) and the audit
  log (see `07-security.md`).

## 3. The 16 tools

Permission tiers: **Open** (runs freely) · **Confirm** (one-tap consent for
noteworthy ops) · **Sensitive** (explicit approval + audit) · **System**
(reserved for automation_agent internals, user-visible in logs).

### 3.1 `file` — local filesystem operations

| | |
|---|---|
| **Description** | Read, write, append, move, copy, delete, list, and stat files under allowed roots. The backbone tool. |
| **Input** | `{op: read\|write\|append\|move\|copy\|delete\|list\|stat, path: string, content?: string, dest?: string}` |
| **Output** | `{ok, content?: string, listing?: string[], stat?: object}` |
| **Permission** | Open for read/list/stat inside workspace; **Confirm** for write/append; **Sensitive** for delete or writes outside workspace roots |
| **Execution** | Sandboxed to allowed roots (`~/`, project dirs); symlink resolution enforced; 10 MB read cap with pagination |
| **Verification** | Post-write: re-read + sha256 compare; post-delete: stat confirms absence |

### 3.2 `browser` — web browsing (online only)

| | |
|---|---|
| **Description** | Fetch page text, follow links, fill forms, click. Used for lookup tasks the user requests. |
| **Input** | `{op: fetch\|click\|fill\|screenshot, url?: string, selector?: string, text?: string}` |
| **Output** | `{ok, title?, text?, links?: string[], screenshotPath?}` |
| **Permission** | **Confirm** per domain (first visit); **Sensitive** for form fills with personal data |
| **Execution** | Headless Chromium pool; per-domain cookie jars; no credential autofill except via OS keyring with consent |
| **Verification** | HTTP status asserted; fetched text non-empty; screenshot file exists |

### 3.3 `code` — code execution & repo operations

| | |
|---|---|
| **Description** | Run code snippets and scripts (Python, Dart, JS, shell), run tests, manage git repos. |
| **Input** | `{op: run\|test\|git, lang?: string, code?: string, scriptPath?: string, args?: string[], gitArgs?: string[]}` |
| **Output** | `{ok, stdout, stderr, exitCode, artifacts?: string[]}` |
| **Permission** | **Confirm** for run/test; **Sensitive** for `git push` or network egress from scripts |
| **Execution** | Sandboxed subprocess: CPU/memory limits, 120 s timeout, no network unless Sensitive-approved |
| **Verification** | Exit code 0 asserted for `run`; test summary parsed; artifacts exist |

### 3.4 `image` — image generation & editing

| | |
|---|---|
| **Description** | Generate images from prompts (local diffusion when available, else online provider) and basic edits (crop, resize, annotate). |
| **Input** | `{op: generate\|edit, prompt?: string, inputPath?: string, edit?: object, outPath: string}` |
| **Output** | `{ok, outPath, width, height}` |
| **Permission** | **Confirm** (compute cost); **Sensitive** never — no personal imagery without explicit prompt |
| **Execution** | Local pipeline preferred; online fallback only in Online mode with consent |
| **Verification** | Output file exists, valid image header, dimensions match request |

### 3.5 `video` — video generation & processing

| | |
|---|---|
| **Description** | Short video generation (online provider) and local processing: trim, transcode, extract frames via ffmpeg. |
| **Input** | `{op: generate\|trim\|transcode\|frames, inputPath?: string, prompt?: string, spec: object, outPath: string}` |
| **Output** | `{ok, outPath, durationSec?, frames?: string[]}` |
| **Permission** | **Confirm**; **Sensitive** for generation (cost + content policy) |
| **Execution** | ffmpeg locally for processing; generation requires Online mode |
| **Verification** | Container probe (ffprobe) validates duration/codec; frames extracted count matches |

### 3.6 `audio` — audio transcription, synthesis helpers & processing

| | |
|---|---|
| **Description** | Transcribe audio files (whisper.cpp offline), convert formats, trim, normalize. (Live voice I/O belongs to `speech_agent`; see `05-voice.md`.) |
| **Input** | `{op: transcribe\|convert\|trim, inputPath: string, outPath?: string, lang?: string}` |
| **Output** | `{ok, transcript?, outPath?, durationSec?}` |
| **Permission** | Open for convert/trim; **Confirm** for transcribe (CPU cost) |
| **Execution** | whisper.cpp binary via FFI/subprocess; ffmpeg for processing |
| **Verification** | Transcript non-empty; output audio probes valid |

### 3.7 `calendar` — calendar read/write

| | |
|---|---|
| **Description** | List, create, update, delete events. Online provider sync when available; local cache otherwise. |
| **Input** | `{op: list\|create\|update\|delete, from?: string, to?: string, event?: object, eventId?: string}` |
| **Output** | `{ok, events?: object[], event?: object}` |
| **Permission** | Open for list; **Confirm** for create/update; **Sensitive** for delete |
| **Execution** | Provider API (online) or local cache (offline, read-only + queued writes) |
| **Verification** | Created/updated event re-fetched and field-compared; deleted event confirmed absent |

### 3.8 `email` — email read, draft, send

| | |
|---|---|
| **Description** | Search inbox, read threads, draft and send mail. |
| **Input** | `{op: search\|read\|draft\|send, query?: string, threadId?: string, to?: string[], subject?: string, body?: string}` |
| **Output** | `{ok, messages?: object[], draftId?, sentId?}` |
| **Permission** | Open for search/read; **Confirm** for draft; **Sensitive** for send (always explicit) |
| **Execution** | Provider API via OAuth tokens from OS keyring; drafts never auto-send |
| **Verification** | Sent mail confirmed via provider message ID; draft saved confirmed by ID |

### 3.9 `task` — task/todo management

| | |
|---|---|
| **Description** | NP's internal task list: create, update, complete, list. Backs multi-step plans visible in the dashboard. |
| **Input** | `{op: create\|update\|complete\|list, task?: object, taskId?: string, status?: string}` |
| **Output** | `{ok, tasks?: object[], task?: object}` |
| **Permission** | Open |
| **Execution** | SQLite `tasks` table (see below); instant, offline |
| **Verification** | Row re-read after mutation |

### 3.10 `pdf` — PDF reading & creation

| | |
|---|---|
| **Description** | Extract text/tables from PDFs; create PDFs from markdown/HTML. |
| **Input** | `{op: extract\|create, inputPath?: string, markdown?: string, outPath?: string, pages?: string}` |
| **Output** | `{ok, text?, tables?, outPath?, pageCount?}` |
| **Permission** | Open |
| **Execution** | Local parsers (no network); creation via headless HTML→PDF |
| **Verification** | Extracted text non-empty; created PDF opens and page count matches |

### 3.11 `document` — office document handling

| | |
|---|---|
| **Description** | Read/write Word, Excel, PowerPoint, OpenDocument, RTF, EPUB. |
| **Input** | `{op: read\|write, path: string, sheet?: string, outPath?: string, content?: object}` |
| **Output** | `{ok, text?, sheets?: string[], outPath?}` |
| **Permission** | Open for read; **Confirm** for write |
| **Execution** | Local conversion libraries; no macros executed on read |
| **Verification** | Written document re-opened and spot-checked |

### 3.12 `terminal` — shell command execution

| | |
|---|---|
| **Description** | Run shell commands with streaming output. Distinct from `code`: arbitrary binaries, pipes, system queries. |
| **Input** | `{command: string, cwd?: string, timeoutSec?: number (default 120), stream?: boolean}` |
| **Output** | `{ok, stdout, stderr, exitCode}` |
| **Permission** | **Confirm** always (first use per session per command-pattern); **Sensitive** for package installs, `sudo`, network egress |
| **Execution** | Sandboxed shell; denylist (`rm -rf /`, fork bombs, etc.); streaming lines to UI |
| **Verification** | Exit code checked against step expectation; output non-empty when expected |

### 3.13 `database` — local database queries

| | |
|---|---|
| **Description** | Query NP's own SQLite databases and user-connected local DB files (read/write with care). |
| **Input** | `{op: query\|exec, dbPath?: string (default np.db), sql: string}` |
| **Output** | `{ok, rows?: object[], rowsAffected?}` |
| **Permission** | Open for SELECT on np.db; **Confirm** for SELECT on external DBs; **Sensitive** for INSERT/UPDATE/DELETE/DDL |
| **Execution** | Parameterized queries only; statement allowlist per op |
| **Verification** | Row/column shape matches expectation; write ops re-queried |

### 3.14 `automation` — desktop & app automation

| | |
|---|---|
| **Description** | Drive the OS: launch/focus/close apps, window management, mouse/keyboard injection, clipboard, screenshots. Backed by `automation_agent` + per-OS adapters (see `06-desktop-control.md`). |
| **Input** | `{op: launch\|focus\|close\|key\|type\|click\|screenshot\|clipboard, target?: string, x?: number, y?: number, text?: string}` |
| **Output** | `{ok, windowId?, screenshotPath?, clipboardText?}` |
| **Permission** | **Confirm** for launch/focus/screenshot; **Sensitive** for input injection (key/type/click) and clipboard write |
| **Execution** | Per-OS adapter (WinAPI, X11/Wayland, Cocoa, Android Accessibility) |
| **Verification** | Window handle validated post-op; screenshot file exists; typed text verified via clipboard round-trip where possible |

### 3.15 `research` — deep research (online)

| | |
|---|---|
| **Description** | Multi-step web research: plan queries, fetch sources, synthesize a cited brief. Online only. |
| **Input** | `{query: string, depth?: 1\|2\|3 (default 2), maxSources?: number (default 8)}` |
| **Output** | `{ok, brief: string, sources: [{title, url, snippet}]}` |
| **Permission** | **Confirm** (network + time cost) |
| **Execution** | Orchestrated `browser` fetches + LLM synthesis; respects robots.txt |
| **Verification** | ≥1 source cited per claim section; all URLs fetched with 200 |

### 3.16 `memory` — direct memory operations (meta-tool)

| | |
|---|---|
| **Description** | Explicit read/write/forget across the 7 memory layers. The pipeline calls this implicitly via `memory_agent`; the tool exists for user-directed memory edits ("forget X"). |
| **Input** | `{op: recall\|remember\|forget\|profile, layer?: string, query?: string, content?: string, key?: string}` |
| **Output** | `{ok, items?: object[], forgotten?: number}` |
| **Permission** | Open for recall/remember; **Sensitive** for forget (destructive) |
| **Execution** | Direct `memory_items` access through MemoryService |
| **Verification** | Post-forget: query returns zero rows for the key |

Supporting table:

```sql
CREATE TABLE tasks (
  id TEXT PRIMARY KEY,           -- uuid
  title TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open',  -- open | doing | done | blocked
  project_id INTEGER REFERENCES projects(id),
  detail TEXT DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
```

## 4. Cross-cutting rules

1. **No tool calls tools.** Composition happens in the planner (multi-step plans), never by nesting tool execution.
2. **Secrets scrubbing** happens at the permission layer boundary: args are canonicalized and hashed *after* secret fields are redacted (see `07-security.md`).
3. **Timeouts:** default 120 s per execution; streaming tools (`terminal`, `code`, `research`) emit progress events.
4. **Offline filtering:** `browser`, `research`, and any op requiring network return `blocked_offline` instead of executing; the planner must have an offline alternative.
