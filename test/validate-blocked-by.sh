#!/usr/bin/env bash
set -uo pipefail

# validate-blocked-by.sh — validate an issue's `## Blocked by` references at
# triage write-time, before applying the `ready-for-agent` label.
#
# Parses the `## Blocked by` section of the given issue body and asserts that
# every `#N` reference is a real, OPEN GitHub issue. An empty or "None" section
# is valid (no dependencies). The aim is to catch typo-references (e.g.
# `#137` when the actual blocker is `#173`) and stale dependencies (an `#N`
# that has since been closed) at triage time rather than later at forge
# pre-flight — moving the integrity check earlier in the cycle.
#
# This validator is consumed by the `/triage` skill: before applying the
# `ready-for-agent` label, triage runs this script against the issue's body
# and refuses to apply the label if it exits non-zero.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   test/validate-blocked-by.sh <ISSUE_NUMBER>            # fetch via gh
#   test/validate-blocked-by.sh --body-file <PATH>        # validate a local body file
#   test/validate-blocked-by.sh --no-github <ISSUE_NUMBER>  # shape-only (skip refs check)
#
# `--body-file <PATH>` reads the issue body from disk instead of calling
# `gh issue view`. Useful for tests (offline-deterministic) and for ad-hoc
# checks against a body draft. In `--body-file` mode the referenced-issues
# check still runs via `gh` unless `--no-github` is also supplied.
#
# Exit codes:
#   0 — `## Blocked by` section is valid (or absent — nothing to validate)
#   1 — one or more validation failures; per-failure messages printed to stderr
#   2 — runtime/usage error (bad arg, unreadable file, gh unavailable when required)
#
# ── GITHUB-SEAM ──────────────────────────────────────────────────────────────
# The `gh issue view <N>` calls below are the only GitHub-specific operations
# in this validator: one to fetch the issue body (when invoked with an issue
# number rather than `--body-file`), and one per referenced `#N` to check
# existence + state. A future VCS-abstraction phase (P4-era WHJ v2 work, per
# `docs/prds/improvements-3a-validation.md` non-goals) will replace these
# calls with an abstraction layer. Until then, this is the seam.
#
# Search for `# GITHUB-SEAM` to find the call sites.
# ────────────────────────────────────────────────────────────────────────────

# ── Argument parsing ─────────────────────────────────────────────────────────
CHECK_GITHUB=1
BODY_FILE=""
ISSUE_NUMBER=""

usage() {
  sed -n '5,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-github)
      CHECK_GITHUB=0
      shift
      ;;
    --body-file)
      if [[ $# -lt 2 ]]; then
        echo "validate-blocked-by: --body-file requires a path argument" >&2
        exit 2
      fi
      BODY_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "validate-blocked-by: unknown option: $1" >&2
      exit 2
      ;;
    *)
      if [[ -n "$ISSUE_NUMBER" ]]; then
        echo "validate-blocked-by: unexpected extra argument: $1" >&2
        exit 2
      fi
      ISSUE_NUMBER="$1"
      shift
      ;;
  esac
done

if [[ -z "$BODY_FILE" && -z "$ISSUE_NUMBER" ]]; then
  echo "validate-blocked-by: must supply either an ISSUE_NUMBER or --body-file <PATH>" >&2
  exit 2
fi

# ── Resolve the body text ────────────────────────────────────────────────────
BODY=""
if [[ -n "$BODY_FILE" ]]; then
  if [[ ! -r "$BODY_FILE" ]]; then
    echo "validate-blocked-by: cannot read body file: $BODY_FILE" >&2
    exit 2
  fi
  BODY="$(cat "$BODY_FILE")"
else
  # Validate ISSUE_NUMBER shape (digits only) before shelling out.
  if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "validate-blocked-by: ISSUE_NUMBER must be a positive integer: $ISSUE_NUMBER" >&2
    exit 2
  fi
  if ! command -v gh >/dev/null 2>&1; then
    echo "validate-blocked-by: gh is required to fetch an issue by number; install gh or use --body-file" >&2
    exit 2
  fi
  # GITHUB-SEAM: fetch the issue body. A future VCS abstraction replaces this.
  if ! BODY="$(gh issue view "$ISSUE_NUMBER" --json body -q .body 2>/dev/null)"; then
    echo "validate-blocked-by: could not fetch issue #$ISSUE_NUMBER (does not exist, or gh auth failed)" >&2
    exit 2
  fi
fi

# ── Extract the `## Blocked by` section ──────────────────────────────────────
# The section runs from the `## Blocked by` heading up to (but not including)
# the next `## ` heading, or to EOF if it's the last section. A body with no
# `## Blocked by` heading at all is treated as "no dependencies" — a valid
# state (zero refs to validate).
SECTION=""
SECTION="$(printf '%s\n' "$BODY" | awk '
  /^## Blocked by[[:space:]]*$/ { in_section = 1; next }
  in_section && /^## / { in_section = 0 }
  in_section { print }
')"

# Strip blank-only lines from both ends (newlines do not count as [[:space:]]
# under macOS BSD sed when processing line-by-line).
SECTION="$(printf '%s\n' "$SECTION" | awk '
  { lines[NR] = $0 }
  END {
    first = 1; last = NR
    while (first <= last && lines[first] ~ /^[[:space:]]*$/) first++
    while (last >= first && lines[last]  ~ /^[[:space:]]*$/) last--
    for (i = first; i <= last; i++) print lines[i]
  }
')"

# ── Empty / "None" handling ──────────────────────────────────────────────────
# An empty section, or a section whose only non-whitespace content is "None"
# (case-insensitive, optionally followed by punctuation/prose like
# "None — can start immediately"), is valid. No refs to check.
if [[ -z "$SECTION" ]]; then
  echo "validate-blocked-by: OK (no ## Blocked by section, or section empty)"
  exit 0
fi

# Compress to a single lowercased line for the "None" check, ignoring surrounding
# punctuation/prose. A section is "None" iff its first word (lowercased) is "none".
FIRST_WORD="$(printf '%s\n' "$SECTION" | awk 'NR==1 {gsub(/^[[:space:]]+/, ""); print tolower($1); exit}')"
if [[ "$FIRST_WORD" == "none" || "$FIRST_WORD" == "none." || "$FIRST_WORD" == "none," ]]; then
  echo "validate-blocked-by: OK (## Blocked by: None)"
  exit 0
fi

# ── Collect every `#N` reference in the section ──────────────────────────────
# Use grep -oE to pull every standalone `#<digits>` token. We do NOT try to
# guard against `#N` inside a code fence inside the Blocked-by section — by
# convention the section is a flat list of references and optional prose
# explanations.
declare -a REFS=()
while IFS= read -r ref; do
  [[ -z "$ref" ]] && continue
  # Strip leading '#'.
  REFS+=("${ref#\#}")
done < <(printf '%s\n' "$SECTION" | grep -oE '#[0-9]+' || true)

if [[ ${#REFS[@]} -eq 0 ]]; then
  # Section has content but no `#N` references — could be free prose (which is
  # also a malformed state worth flagging, but slice #198 covers that for the
  # forge pre-flight). At triage time we treat "no refs" as "no blockers"
  # because the section may legitimately read e.g. "Depends on external work
  # outside this repo." Surface a note but pass.
  echo "validate-blocked-by: OK (no #N references found in ## Blocked by — treated as no dependencies)"
  exit 0
fi

# ── Validate each reference exists and is OPEN ───────────────────────────────
FAIL_COUNT=0

if [[ $CHECK_GITHUB -eq 0 ]]; then
  echo "validate-blocked-by: OK (${#REFS[@]} ref(s) found, GitHub check skipped via --no-github)"
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "validate-blocked-by: gh is required to validate #N references; install gh or pass --no-github" >&2
  exit 2
fi

for n in "${REFS[@]}"; do
  # GITHUB-SEAM: per-reference existence + state check. A future VCS
  # abstraction replaces this.
  state="$(gh issue view "$n" --json state -q .state 2>/dev/null || true)"
  if [[ -z "$state" ]]; then
    echo "validate-blocked-by: FAIL: #$n missing — referenced in ## Blocked by but does not exist on GitHub (typo?)" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi
  if [[ "$state" != "OPEN" ]]; then
    echo "validate-blocked-by: FAIL: #$n closed — referenced in ## Blocked by but is no longer open (stale dependency, state=$state)" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done

if [[ $FAIL_COUNT -eq 0 ]]; then
  echo "validate-blocked-by: OK (${#REFS[@]} ref(s) verified open on GitHub)"
  exit 0
fi

echo "validate-blocked-by: FAIL ($FAIL_COUNT bad reference(s))" >&2
exit 1
