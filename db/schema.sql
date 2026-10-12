-- ============================================================================
-- NP Agent — SQLite schema
-- Project "NP": hybrid Offline+Online AI Operating System Agent
-- Data layer owned by the backend/DB team. Flutter frontend consumes this
-- schema via its memory layer (see app/lib/memory). Column names here MUST
-- match what the Flutter code expects — do not rename without a joint review.
--
-- Conventions:
--   * Timestamps are TEXT in ISO-8601 UTC (e.g. '2026-10-12T12:47:00Z')
--     unless the column is *_ms / *_bytes (INTEGER).
--   * Booleans are INTEGER (0 = false, 1 = true).
--   * Status strings are TEXT with documented allowed values.
--   * Foreign keys use ON DELETE CASCADE where the child row is meaningless
--     without its parent (results, failures, rules).
-- ============================================================================

PRAGMA foreign_keys = ON;

-- ----------------------------------------------------------------------------
-- schema_version — migration tracking. The Flutter DatabaseHelper asserts the
-- version on open and runs upgrade steps from migrations/<n>.sql if behind.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS schema_version (
    version     INTEGER PRIMARY KEY,                 -- current schema version
    applied_at  TEXT NOT NULL DEFAULT (datetime('now')) -- when it was applied
);

-- ----------------------------------------------------------------------------
-- tasks — the unit of work an agent (local or cloud) executes.
-- status: pending | running | succeeded | failed | cancelled
-- agent:  name of the agent that ran/is running it ('memory_agent',
--         'tool_agent', 'planner', 'cloud_fallback', ...)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tasks (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    title       TEXT NOT NULL,
    description TEXT,
    status      TEXT NOT NULL DEFAULT 'pending',
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now')),
    agent       TEXT
);

-- ----------------------------------------------------------------------------
-- task_results — one row per completed task execution (a retried task may have
-- several rows; the latest is authoritative).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS task_results (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id     INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    success     INTEGER NOT NULL DEFAULT 0,          -- 0/1
    output      TEXT,                                -- agent's final output
    duration_ms INTEGER,                             -- wall-clock execution time
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ----------------------------------------------------------------------------
-- failures — structured failure records for tasks that did not succeed.
-- Used by the failure-learning loop that writes failure_rules.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS failures (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    task_id     INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    cause       TEXT NOT NULL,                       -- short machine-readable cause
    context     TEXT,                                -- free-text / JSON context
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ----------------------------------------------------------------------------
-- failure_rules — learned remediation rules distilled from failures.
-- active=1 rules are consulted by the planner before retrying a task.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS failure_rules (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    failure_id  INTEGER REFERENCES failures(id) ON DELETE CASCADE,
    rule        TEXT NOT NULL,                       -- what to do instead
    applies_when TEXT,                               -- condition description
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    active      INTEGER NOT NULL DEFAULT 1           -- 0/1
);

-- ----------------------------------------------------------------------------
-- memory_items — the core memory store shared by all agents.
-- layer: short_term | long_term | semantic | user_profile | tool_usage |
--        project | skill
-- embedding: raw float32 vector blob (little-endian, dim = model-specific;
--        see models table). NULL when the item was stored without embedding.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS memory_items (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    layer       TEXT NOT NULL CHECK (layer IN (
                    'short_term','long_term','semantic','user_profile',
                    'tool_usage','project','skill')),
    key         TEXT NOT NULL,
    content     TEXT NOT NULL,
    embedding   BLOB,
    importance  REAL NOT NULL DEFAULT 0.5,           -- 0.0 .. 1.0 decay weight
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ----------------------------------------------------------------------------
-- user_profile — durable key/value facts about the user (name, locale,
-- preferences...). Mirrors memory_items(layer='user_profile') but is the
-- fast lookup the Flutter profile service reads first.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_profile (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    key         TEXT NOT NULL UNIQUE,
    value       TEXT,
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ----------------------------------------------------------------------------
-- tool_usage — aggregate statistics per tool, used for routing decisions
-- (prefer fast, reliable tools).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tool_usage (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_name       TEXT NOT NULL UNIQUE,
    call_count      INTEGER NOT NULL DEFAULT 0,
    last_used       TEXT,
    avg_duration_ms REAL
);

-- ----------------------------------------------------------------------------
-- projects — named workspaces / projects the agent operates on.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS projects (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,
    description TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ----------------------------------------------------------------------------
-- skills — capability plugins the agent can invoke. enabled=0 keeps the row
-- but excludes it from the planner's tool list.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS skills (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL UNIQUE,
    description TEXT,
    version     TEXT NOT NULL DEFAULT '0.1.0',
    enabled     INTEGER NOT NULL DEFAULT 1           -- 0/1
);

-- ----------------------------------------------------------------------------
-- models — locally available GGUF models for the offline llama.cpp backend.
-- family is constrained to the mobile-friendly families NP ships presets for.
-- active: only one row should be active=1 at a time (enforced in app code).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS models (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    name        TEXT NOT NULL,                       -- display name
    family      TEXT NOT NULL CHECK (family IN (
                    'TinyLlama','Gemma','Phi','Qwen','DeepSeek','SmolLM')),
    quant       TEXT,                                -- e.g. 'Q4_K_M'
    path        TEXT NOT NULL UNIQUE,                -- on-device file path
    size_bytes  INTEGER,
    sha256      TEXT,                                -- integrity check after download
    active      INTEGER NOT NULL DEFAULT 0,          -- 0/1
    downloaded_at TEXT
);

-- ----------------------------------------------------------------------------
-- downloads — resumable model/asset downloads managed by the download manager.
-- status: queued | downloading | paused | completed | failed
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS downloads (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    url         TEXT NOT NULL,
    dest_path   TEXT NOT NULL,
    bytes_done  INTEGER NOT NULL DEFAULT 0,
    bytes_total INTEGER,                             -- NULL if unknown
    status      TEXT NOT NULL DEFAULT 'queued',
    started_at  TEXT,
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- ============================================================================
-- Indexes (hot query paths used by the Flutter memory/tools layers)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_memory_items_layer ON memory_items(layer);
CREATE INDEX IF NOT EXISTS idx_memory_items_key  ON memory_items(key);
CREATE INDEX IF NOT EXISTS idx_tasks_status      ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_tool_usage_name   ON tool_usage(tool_name);
CREATE INDEX IF NOT EXISTS idx_models_active     ON models(active);
-- Supporting indexes for cascade lookups and common joins:
CREATE INDEX IF NOT EXISTS idx_task_results_task ON task_results(task_id);
CREATE INDEX IF NOT EXISTS idx_failures_task     ON failures(task_id);
CREATE INDEX IF NOT EXISTS idx_failure_rules_failure ON failure_rules(failure_id);
CREATE INDEX IF NOT EXISTS idx_memory_items_layer_key ON memory_items(layer, key);

-- ============================================================================
-- Seed data
-- ============================================================================
INSERT OR IGNORE INTO schema_version (version) VALUES (1);

-- Default skills shipped with NP:
INSERT OR IGNORE INTO skills (name, description, version, enabled) VALUES
    ('web_search',   'Online web search fallback when offline knowledge is stale', '0.1.0', 1),
    ('file_tools',   'Read/write/list files inside the agent workspace sandbox',   '0.1.0', 1),
    ('shell_exec',   'Run allow-listed shell commands on device',                  '0.1.0', 1),
    ('reminder',     'Schedule local reminders and cron-style nudges',             '0.1.0', 1),
    ('voice_io',     'Speech-to-text and text-to-speech for hands-free use',       '0.1.0', 0);

-- user_profile defaults (Flutter profile service upserts over these):
INSERT OR IGNORE INTO user_profile (key, value) VALUES
    ('display_name', ''),
    ('locale',       'en'),
    ('timezone',     'UTC'),
    ('offline_mode', 'auto');
