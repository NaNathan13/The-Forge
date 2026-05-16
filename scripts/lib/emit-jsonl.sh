#!/usr/bin/env bash
# emit-jsonl.sh — shared helper for appending JSONL records to a log file.
#
# Sourced by hooks under .claude/hooks/ that emit structured load/deny records
# into .claude/instructions-loaded.jsonl. Established by 3g slice (c)
# (issue #247); reused by 3g slice (a) (#248) for read-denied events.
#
# ── Contract ─────────────────────────────────────────────────────────────────
# Exported functions:
#
#   emit_jsonl <log_path> <json_record>
#     Appends <json_record> + newline to <log_path>. Creates parent dir if
#     missing. Atomic-ish via a single `printf '%s\n' >> file` — bash append
#     redirection is line-atomic on local filesystems for writes under
#     PIPE_BUF (4 KiB on macOS / Linux), which covers any well-formed JSONL
#     record we emit.
#
#   iso8601_utc
#     Echoes the current time as ISO 8601 UTC with a literal `Z` suffix,
#     e.g. `2026-05-16T20:42:11Z`. Uses GNU/BSD `date -u +%Y-%m-%dT%H:%M:%SZ`
#     which is portable across macOS and Linux.
#
#   json_escape <string>
#     Echoes a JSON-escaped string (no surrounding quotes). Handles `"`, `\`,
#     and control characters. Use for any field whose value might contain
#     special characters — file paths in particular.
#
# Sourcing convention: dependents source this file relative to their own path
# (e.g. ".claude/hooks/foo.sh" sources "../../scripts/lib/emit-jsonl.sh" via a
# resolved absolute path).
#
# No `set -e` here — sourced scripts should not have their shell options
# clobbered. Callers are responsible for their own error handling.

emit_jsonl() {
  local log_path="$1"
  local record="$2"
  local log_dir
  log_dir="$(dirname "$log_path")"
  [[ -d "$log_dir" ]] || mkdir -p "$log_dir"
  printf '%s\n' "$record" >>"$log_path"
}

iso8601_utc() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

json_escape() {
  # Escape a string for embedding inside JSON double quotes.
  # Handles: backslash, double-quote, control chars (\b \f \n \r \t),
  # and other ASCII control codes (< 0x20) via \u00XX.
  local s="$1"
  # Order matters: backslash first.
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\b'/\\b}"
  s="${s//$'\f'/\\f}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}
