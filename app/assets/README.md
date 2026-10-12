# Assets

## Why there are no model files here

GGUF model files (often 2–8 GB each) are **not** bundled as Flutter assets:
APK/IPA asset limits and app-store size constraints make that impractical.

Instead, `OfflineLlmProvider` discovers models at runtime by scanning the
on-device directories `/models`, `/gguf`, and `/downloaded_models`
(see `AppConfig.modelDirs`). The `HuggingFaceClient` in `lib/hf/` downloads
models into those directories with resume + sha256 verification.

## What lives here

- `prompts/` — small text assets such as system prompts. Safe to bundle.
