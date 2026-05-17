#!/usr/bin/env bash
# validate-prd-terms.sh — validate a PRD's `## Terms used` section against CONTEXT.md.
#
# Usage:
#   scripts/validate-prd-terms.sh <prd-path> [context-path]
#
# Defaults:
#   <context-path> defaults to CONTEXT.md in the current working directory.
#
# What it does:
#   1. Parses the PRD's `## Terms used` section — every list-item line of the
#      shape `- **<term>**: <anything>` is treated as a declared term.
#   2. For each declared term, decides canon vs non-canon by reading the entry:
#      a non-canon entry contains the literal token `non-canon` somewhere in the
#      body text (case-insensitive). Anything else is canon.
#   3. For each canon term, greps CONTEXT.md for a header of the shape
#      `**<term>**:` (the canonical glossary-entry marker — same shape every
#      term in CONTEXT.md uses). Non-canon terms are not checked against
#      CONTEXT.md (they are by definition not in the glossary).
#   4. Prints one line per undefined canon term to stdout, of the shape:
#         undefined: <term>
#      and exits non-zero if any undefined terms were found.
#   5. Prints `ok: N canon, M non-canon` and exits 0 when every canon term
#      resolves and no malformed input was hit.
#
# Exit codes:
#   0  — every declared canon term resolves in CONTEXT.md (or zero terms declared).
#   1  — one or more declared canon terms are undefined in CONTEXT.md.
#   2  — usage error (missing args, file not readable) or no `## Terms used`
#        section found in the PRD.
#
# This is a CALLABLE HELPER, not a CI gate. The /inscribe hard gate runs the
# same logic inline and prompts the operator. CI does NOT run this script —
# see ADR-0008 §Rejected alternatives for why glossary-lint is deferred.

set -uo pipefail

PRD_PATH="${1:-}"
CONTEXT_PATH="${2:-CONTEXT.md}"

if [[ -z "$PRD_PATH" ]]; then
  echo "usage: validate-prd-terms.sh <prd-path> [context-path]" >&2
  exit 2
fi

if [[ ! -r "$PRD_PATH" ]]; then
  echo "error: cannot read PRD: $PRD_PATH" >&2
  exit 2
fi

if [[ ! -r "$CONTEXT_PATH" ]]; then
  echo "error: cannot read CONTEXT.md: $CONTEXT_PATH" >&2
  exit 2
fi

# Extract the `## Terms used` section body — lines after the header until
# the next `## ` heading (or EOF). awk is the right tool here.
section="$(awk '
  /^## Terms used[[:space:]]*$/ { inside = 1; next }
  inside && /^## / { inside = 0 }
  inside { print }
' "$PRD_PATH")"

if [[ -z "$section" ]]; then
  echo "error: no '## Terms used' section found in $PRD_PATH" >&2
  exit 2
fi

# Parse each declared term line. Format: `- **<term>**: <body>`.
# We allow trailing whitespace + arbitrary body content.
canon_count=0
non_canon_count=0
undefined_count=0

while IFS= read -r line; do
  # Skip empty lines and non-list lines.
  [[ -z "$line" ]] && continue
  [[ "$line" =~ ^[[:space:]]*-[[:space:]]+\*\*([^*]+)\*\*:(.*)$ ]] || continue

  term="${BASH_REMATCH[1]}"
  body="${BASH_REMATCH[2]}"

  # Trim whitespace from term.
  term="${term#"${term%%[![:space:]]*}"}"
  term="${term%"${term##*[![:space:]]}"}"

  # Decide canon vs non-canon — case-insensitive match on `non-canon` in body.
  # (Lowercase via `tr` for bash 3.2 portability — macOS ships bash 3.2.)
  body_lower="$(printf '%s' "$body" | tr '[:upper:]' '[:lower:]')"
  if [[ "$body_lower" == *"non-canon"* ]]; then
    non_canon_count=$((non_canon_count + 1))
    continue
  fi

  canon_count=$((canon_count + 1))

  # Grep CONTEXT.md for the term header. Pattern: `**<term>**:`.
  # Use fgrep-style fixed-string search to avoid having to escape term content.
  if ! grep -F -- "**${term}**:" "$CONTEXT_PATH" >/dev/null 2>&1; then
    echo "undefined: $term"
    undefined_count=$((undefined_count + 1))
  fi
done <<< "$section"

if [[ "$undefined_count" -gt 0 ]]; then
  echo "fail: $undefined_count undefined canon term(s) ($canon_count canon, $non_canon_count non-canon)" >&2
  exit 1
fi

echo "ok: $canon_count canon, $non_canon_count non-canon"
exit 0
