#!/usr/bin/env bash
set -uo pipefail

# validate-sentinel.sh — assert that a single line is a valid worker sentinel.
#
# After sub-phase 4b's pipeline rename, two skills emit sentinels with the same
# JSON shape — only the prefix differs:
#
#     FORGE:RESULT <json-object>   — emitted by /forge (the builder)
#     TEMPER:RESULT <json-object>  — emitted by /temper (the review skill)
#
# the overseer parses the matching line to decide what to do next. Today the
# schema is enforced only by prose in `.claude/skills/forge/SKILL.md`,
# `.claude/skills/temper/SKILL.md`, and `docs/shared/pipeline.md`.
# This validator is the code-level check those documents asked for — a thin
# `jq`-driven shape test that catches malformed sentinels at write time (in
# tests, fixtures, and future CI hooks) rather than at the orchestrator at
# 3 a.m.
#
# The validator specifically guards the friction-text field where an
# un-escaped quote silently breaks the entire forge run: a bad friction string
# fails JSON parsing here, loudly, instead of corrupting the sentinel
# downstream.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#
#   test/validate-sentinel.sh <file>      # read the line from <file>
#   echo "TEMPER:RESULT {...}" | test/validate-sentinel.sh   # read from stdin
#
# Exit codes:
#   0 — the input is a valid TEMPER:RESULT sentinel
#   1 — the input is invalid; a one-line reason is printed to stderr
#   2 — usage / runner error (missing jq, file not found, etc.)
#
# The validator accepts the full sentinel line (with the `TEMPER:RESULT `
# prefix, as it would appear in real temper output) and also a bare JSON object
# (the line with the prefix already stripped, as Forge sees it after parsing).
# Either is valid input — the prefix is optional. Anything else is rejected.
#
# ── Schema ───────────────────────────────────────────────────────────────────
#
# Required on every emission:
#   status    — "success" | "continue" | "needs_human" | "fail"
#   issue     — integer
#   branch    — string or null
#   pr        — integer or null
#   tokens    — null (always; Forge fills this in post-run)
#   friction  — string or null
#
# Status-specific extras:
#   status=="continue"     → continuation_file (string)
#   status=="needs_human"  → reason (string)
#   status=="fail"         → reason (string)
#   status=="success"      → no extras
#
# Optional protocol version (since v1):
#   v         — integer (currently 1). Absent is accepted as a back-compat
#               case for one release — a sentinel without `v` is treated as
#               legacy (pre-version-field) and still validates. A future
#               sub-phase will make `v` required and pin the accepted values.
#
# See `docs/shared/pipeline.md` §"Sentinel protocol" for the canonical schema
# and `.claude/skills/temper/SKILL.md` §"Emit the result sentinel" for the
# emission rules.

# Two sentinel prefixes share the same schema after the 4b rename:
#   FORGE:RESULT — emitted by /forge (the builder), build outcome.
#   TEMPER:RESULT — emitted by /temper (the review skill), review outcome.
# Both carry an identical JSON object shape; this validator accepts either
# prefix. The build sentinel (FORGE:RESULT) is checked first because it is the
# load-bearing one the overseer parses for every shipped slice.
PREFIX_FORGE="FORGE:RESULT "
PREFIX_TEMPER="TEMPER:RESULT "

die() {
  # die <exit-code> <message...>
  local rc="$1"; shift
  echo "validate-sentinel: $*" >&2
  exit "$rc"
}

# jq is the only external dependency. Fail loud if it is missing.
if ! command -v jq >/dev/null 2>&1; then
  die 2 "jq is required but not found on PATH"
fi

# ── Read input ───────────────────────────────────────────────────────────────
#
# Either a file path arg or stdin. We must read the full input *before* the
# single-line check so multi-line input is rejected (not silently truncated).
if [[ $# -gt 1 ]]; then
  die 2 "usage: validate-sentinel.sh [<file>]"
fi

if [[ $# -eq 1 ]]; then
  src="$1"
  if [[ ! -f "$src" ]]; then
    die 2 "file not found: $src"
  fi
  input="$(cat -- "$src")"
else
  # Read entire stdin. `cat` preserves the byte content; we check shape next.
  input="$(cat)"
fi

# ── Empty input ──────────────────────────────────────────────────────────────
if [[ -z "$input" ]]; then
  die 1 "empty input"
fi

# ── Exactly one line ─────────────────────────────────────────────────────────
#
# A trailing newline is fine — that is how every well-behaved POSIX line is
# terminated and how `echo` produces lines. What is NOT fine is two or more
# *content* lines: that means the caller passed a multi-line blob (e.g. an
# entire temper transcript), which would break Forge's "scan for the last
# `TEMPER:RESULT ` line" contract by ambiguity.
#
# Strip exactly one trailing newline (if any), then reject if any newline
# remains.
stripped="${input%$'\n'}"
if [[ "$stripped" == *$'\n'* ]]; then
  die 1 "input is multi-line — sentinel must be exactly one line"
fi

line="$stripped"

# ── Strip the optional `TEMPER:RESULT ` prefix ───────────────────────────────
#
# Accept both the wire form (prefix present, as temper emits) and the
# post-parse form (prefix stripped, as Forge handles it).
if [[ "$line" == "$PREFIX_FORGE"* ]]; then
  json="${line#"$PREFIX_FORGE"}"
elif [[ "$line" == "$PREFIX_TEMPER"* ]]; then
  json="${line#"$PREFIX_TEMPER"}"
else
  json="$line"
fi

if [[ -z "$json" ]]; then
  die 1 "no JSON payload after FORGE:RESULT / TEMPER:RESULT prefix"
fi

# ── JSON parse ───────────────────────────────────────────────────────────────
#
# `jq -e` exits 1 on a `false`/`null` result; we only care about parse failure,
# so check the parse explicitly. Any parse error here is exactly the class of
# silent breakage this validator exists to catch — an un-escaped quote in the
# friction field, a stray comma, a single-quoted string, etc.
if ! echo "$json" | jq -e . >/dev/null 2>&1; then
  die 1 "JSON parse failed"
fi

# Must be a JSON object (not an array, string, number, bool, or null).
top_type="$(echo "$json" | jq -r 'type')"
if [[ "$top_type" != "object" ]]; then
  die 1 "JSON payload is a $top_type, expected object"
fi

# ── Required fields ──────────────────────────────────────────────────────────
#
# `has` checks key presence (so an explicit `null` counts as present, which is
# the correct behaviour for `branch`/`pr`/`tokens`/`friction`).
for key in status issue branch pr tokens friction; do
  has="$(echo "$json" | jq -r --arg k "$key" 'has($k)')"
  if [[ "$has" != "true" ]]; then
    die 1 "missing required field: $key"
  fi
done

# ── Field types ──────────────────────────────────────────────────────────────

# status — must be one of the four recognised values
status="$(echo "$json" | jq -r '.status')"
case "$status" in
  success|continue|needs_human|fail) ;;
  *) die 1 "invalid status: $status (expected one of: success, continue, needs_human, fail)" ;;
esac

# issue — must be a number, and an integer
issue_type="$(echo "$json" | jq -r '.issue | type')"
if [[ "$issue_type" != "number" ]]; then
  die 1 "field 'issue' must be an integer, got $issue_type"
fi
# Reject floats — `jq` reports both as type "number" but we want integers only.
is_int="$(echo "$json" | jq -r '.issue | (. == (. | floor))')"
if [[ "$is_int" != "true" ]]; then
  die 1 "field 'issue' must be an integer (no decimal component)"
fi

# branch — string or null
branch_type="$(echo "$json" | jq -r '.branch | type')"
if [[ "$branch_type" != "string" && "$branch_type" != "null" ]]; then
  die 1 "field 'branch' must be a string or null, got $branch_type"
fi

# pr — integer or null
pr_type="$(echo "$json" | jq -r '.pr | type')"
if [[ "$pr_type" != "number" && "$pr_type" != "null" ]]; then
  die 1 "field 'pr' must be an integer or null, got $pr_type"
fi
if [[ "$pr_type" == "number" ]]; then
  is_int="$(echo "$json" | jq -r '.pr | (. == (. | floor))')"
  if [[ "$is_int" != "true" ]]; then
    die 1 "field 'pr' must be an integer (no decimal component)"
  fi
fi

# tokens — must be null (temper never sets a value; Forge backfills it)
tokens_type="$(echo "$json" | jq -r '.tokens | type')"
if [[ "$tokens_type" != "null" ]]; then
  die 1 "field 'tokens' must be null from temper (Forge backfills it), got $tokens_type"
fi

# friction — string or null. This is the field most prone to silent breakage:
# the JSON parse above is what catches an un-escaped quote here.
friction_type="$(echo "$json" | jq -r '.friction | type')"
if [[ "$friction_type" != "string" && "$friction_type" != "null" ]]; then
  die 1 "field 'friction' must be a string or null, got $friction_type"
fi

# ── Optional protocol version `v` (since v1) ─────────────────────────────────
#
# The protocol gained a `"v": 1` version field so future schema bumps can be
# non-breaking. For one back-compat release the field is OPTIONAL:
#   - absent  → accepted (legacy sentinel from a pre-version-field temper)
#   - present → must be the integer 1
# A future sub-phase will make this required and pin a richer set of accepted
# values once we ship a v2 transition.
has_v="$(echo "$json" | jq -r 'has("v")')"
if [[ "$has_v" == "true" ]]; then
  v_type="$(echo "$json" | jq -r '.v | type')"
  if [[ "$v_type" != "number" ]]; then
    die 1 "field 'v' must be an integer, got $v_type"
  fi
  is_int="$(echo "$json" | jq -r '.v | (. == (. | floor))')"
  if [[ "$is_int" != "true" ]]; then
    die 1 "field 'v' must be an integer (no decimal component)"
  fi
  v_value="$(echo "$json" | jq -r '.v')"
  if [[ "$v_value" != "1" ]]; then
    die 1 "field 'v' must be 1 (the only currently-defined protocol version), got $v_value"
  fi
fi

# ── Status-specific extras ───────────────────────────────────────────────────

case "$status" in
  success)
    # No required extras. (Extra unknown keys are tolerated so future schema
    # versions stay back-compat — `validate-skills.sh` and a future `"v":N`
    # field will tighten this.)
    ;;
  continue)
    has="$(echo "$json" | jq -r 'has("continuation_file")')"
    if [[ "$has" != "true" ]]; then
      die 1 "status=continue requires field: continuation_file"
    fi
    cf_type="$(echo "$json" | jq -r '.continuation_file | type')"
    if [[ "$cf_type" != "string" ]]; then
      die 1 "field 'continuation_file' must be a string, got $cf_type"
    fi
    cf_value="$(echo "$json" | jq -r '.continuation_file')"
    if [[ -z "$cf_value" ]]; then
      die 1 "field 'continuation_file' must be non-empty"
    fi
    ;;
  needs_human|fail)
    has="$(echo "$json" | jq -r 'has("reason")')"
    if [[ "$has" != "true" ]]; then
      die 1 "status=$status requires field: reason"
    fi
    reason_type="$(echo "$json" | jq -r '.reason | type')"
    if [[ "$reason_type" != "string" ]]; then
      die 1 "field 'reason' must be a string, got $reason_type"
    fi
    reason_value="$(echo "$json" | jq -r '.reason')"
    if [[ -z "$reason_value" ]]; then
      die 1 "field 'reason' must be non-empty"
    fi
    ;;
esac

exit 0
