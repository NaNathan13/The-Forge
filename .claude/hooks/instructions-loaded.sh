#!/usr/bin/env bash
set -uo pipefail

# instructions-loaded.sh — `InstructionsLoaded` hook handler (3g slice (c), #247).
#
# Wired in .claude/settings.json on the InstructionsLoaded event. Claude Code
# fires this hook every time it loads a memory file (CLAUDE.md and
# .claude/rules/*.md) into a session — including the initial session-start
# load, path-glob-matched rule loads, and trigger-file loads.
#
# Per-invocation, this handler reads the payload JSON from stdin, derives `ts`
# (ISO 8601 UTC with `Z` suffix) and `bytes` (`wc -c` on the loaded file), and
# appends exactly one JSONL line to `.claude/instructions-loaded.jsonl`. The
# log is the observability surface a future token-waste audit will read
# (originally scoped as sub-phase 3h, deferred 2026-05-16 pending real-session
# data — see docs/design/improvements-overview.md §"Extension batch").
#
# ── Schema (sentinel-protocol shape, `v:1` + `type` discriminator) ───────────
# {
#   "v": 1,
#   "type": "instructions_loaded",
#   "ts": "<ISO 8601 UTC Z>",
#   "file": "<abs path>",
#   "bytes": <integer>,
#   "memory_type": "Project" | "User" | "Local" | ...,
#   "load_reason": "session_start" | "path_glob_match" | ...,
#   "globs": [...],
#   "trigger_file_path": "<path>" | null,
#   "parent_file_path": "<path>" | null
# }
#
# The `type` discriminator is forward-compatible: slice (a) (#248) will emit
# `type:"read_denied"` records to the same file.
#
# ── Known gap: SKILL.md loads NOT covered ────────────────────────────────────
# `InstructionsLoaded` fires for CLAUDE.md and `.claude/rules/*.md` only.
# Skill-load observability needs a different mechanism (likely `PreToolUse` on
# the `Skill` tool) and is out of scope for 3g — carry-forward to whichever
# phase revives the deferred token-waste audit.
#
# ── Known gap: no log rotation ───────────────────────────────────────────────
# `.claude/instructions-loaded.jsonl` accumulates without rotation. If the
# future audit finds the file unwieldy, rotation lands as a follow-up slice
# at that time.
#
# ── Failure mode ─────────────────────────────────────────────────────────────
# Hook failures must NEVER block instruction loading. On any error (missing
# `jq`, unparseable payload, write failure), this script exits 0 silently so
# Claude Code's load proceeds normally. Observability is best-effort.

# Resolve repo root via this script's path so we can source the shared helper
# regardless of the harness's working directory.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/scripts/lib/emit-jsonl.sh"
LOG_FILE="$REPO_ROOT/.claude/instructions-loaded.jsonl"

# Source helper or bail silently. Hooks must never block loads.
# shellcheck source=../../scripts/lib/emit-jsonl.sh
if ! source "$HELPER" 2>/dev/null; then
  exit 0
fi

# Read payload from stdin. If empty, bail silently.
payload="$(cat 2>/dev/null || true)"
[[ -n "$payload" ]] || exit 0

# Require jq for reliable JSON parsing. If unavailable, no observability — but
# do not block the load.
command -v jq >/dev/null 2>&1 || exit 0

# Extract fields from the payload. `// empty` keeps absent fields as empty
# strings (we then coalesce to JSON null below). `globs` is an array — emit it
# verbatim as compact JSON, defaulting to `[]`.
file_path="$(printf '%s' "$payload" | jq -r '.file_path // empty' 2>/dev/null || true)"
memory_type="$(printf '%s' "$payload" | jq -r '.memory_type // empty' 2>/dev/null || true)"
load_reason="$(printf '%s' "$payload" | jq -r '.load_reason // empty' 2>/dev/null || true)"
globs_json="$(printf '%s' "$payload" | jq -c '.globs // []' 2>/dev/null || echo '[]')"
trigger_file_path="$(printf '%s' "$payload" | jq -r '.trigger_file_path // empty' 2>/dev/null || true)"
parent_file_path="$(printf '%s' "$payload" | jq -r '.parent_file_path // empty' 2>/dev/null || true)"

# Compute bytes if we have a readable file_path; else 0.
bytes=0
if [[ -n "$file_path" && -r "$file_path" ]]; then
  # `wc -c` output has leading whitespace on some platforms — trim it.
  bytes="$(wc -c <"$file_path" 2>/dev/null | tr -d ' \t\n' || echo 0)"
  [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
fi

ts="$(iso8601_utc)"

# Build JSON-quoted fields. Empty optional strings serialize as JSON null.
quote_or_null() {
  if [[ -z "$1" ]]; then
    printf 'null'
  else
    printf '"%s"' "$(json_escape "$1")"
  fi
}

file_json="$(quote_or_null "$file_path")"
memory_type_json="$(quote_or_null "$memory_type")"
load_reason_json="$(quote_or_null "$load_reason")"
trigger_json="$(quote_or_null "$trigger_file_path")"
parent_json="$(quote_or_null "$parent_file_path")"

record=$(printf '{"v":1,"type":"instructions_loaded","ts":"%s","file":%s,"bytes":%s,"memory_type":%s,"load_reason":%s,"globs":%s,"trigger_file_path":%s,"parent_file_path":%s}' \
  "$ts" \
  "$file_json" \
  "$bytes" \
  "$memory_type_json" \
  "$load_reason_json" \
  "$globs_json" \
  "$trigger_json" \
  "$parent_json")

emit_jsonl "$LOG_FILE" "$record" 2>/dev/null || true

exit 0
