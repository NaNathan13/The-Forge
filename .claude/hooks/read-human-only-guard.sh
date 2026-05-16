#!/usr/bin/env bash
set -uo pipefail

# read-human-only-guard.sh — `PreToolUse` Read hook handler (3g slice (a), #248).
#
# Wired in .claude/settings.json on the PreToolUse event with matcher "Read".
# Fires before every Read tool dispatch. Scans the target file's line 1 for
# the audience banner (`^> \*\*Audience:\*\* humans only`) and, on match,
# denies the Read with a terse + redirecting reason.
#
# Defense-in-depth context (see ADR-0004):
#   1. `permissions.deny` in .claude/settings.json statically denies the three
#      known human-only paths (docs/how-the-forge-works.md, docs/audit/**,
#      docs/vision/**). Harness-enforced, fail-closed even if this hook breaks.
#   2. This hook dynamically denies any *other* file that carries the banner
#      on line 1 — protects future banner-tagged files under arbitrary paths.
#
# ── Scan strictness: line 1 only ─────────────────────────────────────────────
# `head -n 1` only. A banner buried on line 5 is NOT protected. This is
# intentional: fail-loud on banner-authorship discipline error rather than
# silently extending tolerance for buried banners.
#
# ── Output protocol ──────────────────────────────────────────────────────────
# On allow: exit 0 with no stdout (the Read proceeds as normal).
# On deny:  emit JSON to stdout shaped as
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#                          "permissionDecision":"deny",
#                          "permissionDecisionReason":"..."}}
# and exit 0. Claude Code's hook protocol consumes the structured output and
# blocks the tool call with the provided reason.
#
# ── Denial side-effect: JSONL log ────────────────────────────────────────────
# On every denial, append one record to .claude/instructions-loaded.jsonl:
#   {"v":1,"type":"read_denied","ts":"<ISO 8601 UTC Z>",
#    "file":"<abs path>","reason":"banner_line_1"}
# Same log file slice (c) writes to; `type` discriminator distinguishes events.
# Uses the shared emit_jsonl() helper from scripts/lib/emit-jsonl.sh.
#
# ── Failure mode ─────────────────────────────────────────────────────────────
# Hook failures must NEVER block a non-human-only Read. On any internal error
# (missing jq, unparseable payload, helper missing), the script exits 0
# silently so the Read proceeds. Allow-by-default is the safe failure for a
# guard: false negatives (a banner-tagged file slips through) are recoverable
# via the static deny list; false positives (a normal file is blocked) would
# break the worker's ability to read its own files.

# Resolve repo root via this script's path so the helper sources regardless of
# the harness's working directory.
HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HOOK_DIR/../.." && pwd)"
HELPER="$REPO_ROOT/scripts/lib/emit-jsonl.sh"
LOG_FILE="$REPO_ROOT/.claude/instructions-loaded.jsonl"

# The banner regex. Anchored to start-of-line; matches the canonical form
# used across every human-only file as of 2026-05-16.
BANNER_RE='^> \*\*Audience:\*\* humans only'

# The denial reason surfaced to Claude.
DENY_REASON="Denied — file is human-only (banner on line 1). See CLAUDE.md § Context loading for what to load instead."

# Read payload from stdin. If empty, allow (we can't scan what we can't see).
payload="$(cat 2>/dev/null || true)"
[[ -n "$payload" ]] || exit 0

# Require jq for reliable JSON parsing. If unavailable, allow — best-effort.
command -v jq >/dev/null 2>&1 || exit 0

# Extract the Read tool's file_path. PreToolUse payload shape:
#   {"tool_name":"Read","tool_input":{"file_path":"..."},...}
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[[ -n "$file_path" ]] || exit 0

# If the file doesn't exist or isn't readable, allow — let the Read tool
# surface its own missing-file error. We only deny when we can prove the
# banner is present on line 1.
[[ -r "$file_path" ]] || exit 0

# Scan line 1 only. `head -n 1` is intentional — see strictness note above.
line1="$(head -n 1 "$file_path" 2>/dev/null || true)"

if [[ ! "$line1" =~ $BANNER_RE ]]; then
  # Not a human-only file (or banner not on line 1). Allow.
  exit 0
fi

# Banner matched — deny the Read and append a JSONL record.

# Source the helper. If it fails to source, still deny — we have enough to
# emit the structured-output denial, just no log line.
log_ok=1
# shellcheck source=../../scripts/lib/emit-jsonl.sh
if source "$HELPER" 2>/dev/null; then
  ts="$(iso8601_utc)"
  file_escaped="$(json_escape "$file_path")"
  record=$(printf '{"v":1,"type":"read_denied","ts":"%s","file":"%s","reason":"banner_line_1"}' \
    "$ts" "$file_escaped")
  emit_jsonl "$LOG_FILE" "$record" 2>/dev/null || log_ok=0
else
  log_ok=0
fi

# Emit the structured denial decision. Use jq -n to ensure a well-formed
# JSON object regardless of any special characters in DENY_REASON.
jq -nc \
  --arg reason "$DENY_REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse",
                         permissionDecision: "deny",
                         permissionDecisionReason: $reason}}'

exit 0
