#!/usr/bin/env bash
set -uo pipefail

# read-human-only-guard.sh — `PreToolUse` Read hook handler (3g slice (a), #248;
# ask-semantics swap in 4a, #258).
#
# Wired in .claude/settings.json on the PreToolUse event with matcher "Read".
# Fires before every Read tool dispatch. Scans the target file's line 1 for
# the audience banner (`^> \*\*Audience:\*\* humans only`) and, on match,
# returns `permissionDecision: "ask"` so the harness surfaces a permission
# prompt the operator can approve (interactive) or which auto-denies in
# autonomous mode.
#
# Defense-in-depth context (see ADR-0004 + its 2026-05-17 amendment):
#   1. `permissions.ask` in .claude/settings.json statically prompts for the
#      three known human-only paths (docs/how-the-forge-works.md,
#      docs/audit/**, docs/vision/**). Harness-enforced, fail-closed in
#      `dontAsk` (autonomous) mode even if this hook breaks.
#   2. This hook dynamically prompts on any *other* file that carries the
#      banner on line 1 — protects future banner-tagged files under
#      arbitrary paths.
#
# ── Scan strictness: line 1 only ─────────────────────────────────────────────
# `head -n 1` only. A banner buried on line 5 is NOT protected. This is
# intentional: fail-loud on banner-authorship discipline error rather than
# silently extending tolerance for buried banners.
#
# ── Output protocol ──────────────────────────────────────────────────────────
# On allow: exit 0 with no stdout (the Read proceeds as normal).
# On ask:   emit JSON to stdout shaped as
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#                          "permissionDecision":"ask",
#                          "permissionDecisionReason":"..."}}
# and exit 0. Claude Code's hook protocol consumes the structured output and
# routes the tool call through a permission prompt with the provided reason.
# In `dontAsk` (autonomous) mode the harness auto-denies ask-rules without
# prompting — the autonomous safety guarantee from ADR-0004 is preserved
# through the harness, not through this script.
#
# ── Ask side-effect: JSONL log ───────────────────────────────────────────────
# On every ask fire, append one record to .claude/instructions-loaded.jsonl:
#   {"v":1,"type":"read_ask_prompted","ts":"<ISO 8601 UTC Z>",
#    "file":"<abs path>","reason":"banner_line_1"}
# Same log file slice (c) writes to; `type` discriminator distinguishes events.
# Historical `read_denied` records from before the 4a swap are not rewritten —
# downstream consumers handle both event types. Uses the shared emit_jsonl()
# helper from scripts/lib/emit-jsonl.sh.
#
# ── Failure mode ─────────────────────────────────────────────────────────────
# Hook failures must NEVER block a non-human-only Read. On any internal error
# (missing jq, unparseable payload, helper missing), the script exits 0
# silently so the Read proceeds. Allow-by-default is the safe failure for a
# guard: false negatives (a banner-tagged file slips through) are recoverable
# via the static ask list; false positives (a normal file is blocked) would
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

# The prompt reason surfaced to Claude/the operator. Prompt-friendly framing
# (the 4a swap reworded this from a denial message to an approval-prompt).
ASK_REASON="This file is marked Audience: humans only (banner on line 1). Approve only if you specifically need Claude to read it; otherwise decline. See CLAUDE.md § Context loading."

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
# surface its own missing-file error. We only prompt when we can prove the
# banner is present on line 1.
[[ -r "$file_path" ]] || exit 0

# Scan line 1 only. `head -n 1` is intentional — see strictness note above.
line1="$(head -n 1 "$file_path" 2>/dev/null || true)"

if [[ ! "$line1" =~ $BANNER_RE ]]; then
  # Not a human-only file (or banner not on line 1). Allow.
  exit 0
fi

# Banner matched — return ask and append a JSONL record.

# Source the helper. If it fails to source, still ask — we have enough to
# emit the structured-output decision, just no log line.
log_ok=1
# shellcheck source=../../scripts/lib/emit-jsonl.sh
if source "$HELPER" 2>/dev/null; then
  ts="$(iso8601_utc)"
  file_escaped="$(json_escape "$file_path")"
  record=$(printf '{"v":1,"type":"read_ask_prompted","ts":"%s","file":"%s","reason":"banner_line_1"}' \
    "$ts" "$file_escaped")
  emit_jsonl "$LOG_FILE" "$record" 2>/dev/null || log_ok=0
else
  log_ok=0
fi

# Emit the structured ask decision. Use jq -n to ensure a well-formed
# JSON object regardless of any special characters in ASK_REASON.
jq -nc \
  --arg reason "$ASK_REASON" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse",
                         permissionDecision: "ask",
                         permissionDecisionReason: $reason}}'

exit 0
