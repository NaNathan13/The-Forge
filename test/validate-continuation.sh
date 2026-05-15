#!/usr/bin/env bash
set -uo pipefail

# validate-continuation.sh — assert a gen-NNN.md (or temper-continue-<N>.md)
# carries the five mandatory hardened sections from
# templates/continuation-gen.md, in the right order, and that each section has
# non-empty body content beneath its heading.
#
# Why this exists
# ────────────────
# The continuation file is the single point of failure for both clean
# context-limit handoff and crash recovery. Today its format is enforced only
# by prose in the template (templates/continuation-gen.md) and by the prose
# contract in temper/SKILL.md. This validator is the code-level check the
# audit's §B Theme 1 / rec #3 asked for — additive to the prose, not a
# replacement.
#
# Usage
# ─────
#   test/validate-continuation.sh <path-to-gen-NNN.md>
#
# Exit codes
#   0 — file is well-formed
#   1 — file is malformed (one or more rule violations; diagnostics on stderr)
#   2 — usage error (missing arg, unreadable file)
#
# Rules enforced
#   1. All FIVE required `## ` section headings are present, exactly as
#      written in templates/continuation-gen.md.
#   2. The five headings appear in the required order.
#   3. No extra `## ` headings exist between or before them — exactly five
#      h2-sections (so "fewer than 5" or "more than 5 with the right ones
#      misplaced" both fail rule 1/2 anyway, but we also reject extras to
#      keep the schema tight).
#   4. Each section's body is non-empty after stripping HTML comments and
#      whitespace-only lines. (A bare heading with only a `<!-- ... -->`
#      template hint counts as empty — the gen-NNN file is meant to be
#      *filled in* before it's written.)

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat >&2 <<EOF
Usage: $SCRIPT_NAME <path-to-gen-NNN.md>

Asserts the file carries the five hardened continuation sections, in order,
each with a non-empty body. See templates/continuation-gen.md for the schema.
EOF
}

# The five required headings, in canonical order. Keep this list and the
# template in lockstep — if you add a section there, add it here.
REQUIRED_SECTIONS=(
  "## Hard constraints (RESTATED VERBATIM — do not summarize)"
  "## Execution frontier"
  "## Conversation summary"
  "## Next concrete action"
  "## Notes / scratch"
)

# ── Argument handling ───────────────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

FILE="$1"
if [[ ! -f "$FILE" ]]; then
  echo "$SCRIPT_NAME: file not found: $FILE" >&2
  exit 2
fi
if [[ ! -r "$FILE" ]]; then
  echo "$SCRIPT_NAME: file not readable: $FILE" >&2
  exit 2
fi

# ── Pass 1: collect every `## ` heading line and its line number ────────────
# We capture exactly `## ` (h2) headings — h1 (title) and h3+ subheadings are
# ignored. The order and count of h2 headings is what defines section shape.
declare -a HEADINGS=()
declare -a HEADING_LINES=()

# Read the file once to find headings. Use a while-read loop with `IFS=` and
# `-r` so leading whitespace and backslashes are preserved verbatim.
lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
  lineno=$((lineno + 1))
  # Match exactly "## " followed by anything — h2 headings only. Don't match
  # "###" (h3), "##nospace", or any indented heading.
  if [[ "$line" =~ ^"## "(.*)$ ]]; then
    HEADINGS+=("## ${BASH_REMATCH[1]}")
    HEADING_LINES+=("$lineno")
  fi
done < "$FILE"

ERRORS=0
report() {
  echo "$SCRIPT_NAME: $FILE: $*" >&2
  ERRORS=$((ERRORS + 1))
}

# ── Rule 1+2+3: count + identity + order of headings ────────────────────────
EXPECTED_COUNT="${#REQUIRED_SECTIONS[@]}"
ACTUAL_COUNT="${#HEADINGS[@]}"

if [[ "$ACTUAL_COUNT" -ne "$EXPECTED_COUNT" ]]; then
  report "expected $EXPECTED_COUNT '## ' sections, found $ACTUAL_COUNT"
  # List what we did find so the failure is debuggable in one read.
  if [[ "$ACTUAL_COUNT" -gt 0 ]]; then
    echo "  found headings:" >&2
    for h in "${HEADINGS[@]}"; do
      echo "    - $h" >&2
    done
  fi
fi

# Compare position-by-position even on count mismatch, capped at min(actual,
# expected), so the operator sees exactly which slot drifted.
LIMIT="$EXPECTED_COUNT"
if [[ "$ACTUAL_COUNT" -lt "$LIMIT" ]]; then
  LIMIT="$ACTUAL_COUNT"
fi

i=0
while [[ $i -lt $LIMIT ]]; do
  if [[ "${HEADINGS[$i]}" != "${REQUIRED_SECTIONS[$i]}" ]]; then
    report "section $((i + 1)) mismatch"
    echo "    expected: ${REQUIRED_SECTIONS[$i]}" >&2
    echo "    actual:   ${HEADINGS[$i]}" >&2
  fi
  i=$((i + 1))
done

# If counts and identities all aligned, also flag any missing sections by
# scanning required → headings (catches the case where ACTUAL > EXPECTED but
# every required heading is somewhere in the list, just out of order — the
# position check above already caught it, but this gives a clearer "missing
# heading X" message when the heading is genuinely absent).
for req in "${REQUIRED_SECTIONS[@]}"; do
  found=0
  for h in "${HEADINGS[@]}"; do
    if [[ "$h" == "$req" ]]; then
      found=1
      break
    fi
  done
  if [[ $found -eq 0 ]]; then
    report "missing required section: $req"
  fi
done

# ── Rule 4: every section has a non-empty body ──────────────────────────────
# A section body is the lines between its heading and the next `## ` heading
# (or EOF). We consider the body non-empty if, after stripping HTML comments
# (<!-- ... -->) and blank lines, anything remains.
#
# Strategy: read the full file into an array, walk the heading line numbers,
# extract each section's body slice, normalize, and check.
#
# bash 3.2 has no `mapfile`, so use a read loop.
declare -a LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  LINES+=("$line")
done < "$FILE"
TOTAL_LINES="${#LINES[@]}"

# Only check bodies for sections we actually located in the heading list AND
# that match a required heading (so we don't double-report on a misplaced
# section that already failed rule 2).
i=0
while [[ $i -lt "$ACTUAL_COUNT" ]]; do
  heading="${HEADINGS[$i]}"
  start_line="${HEADING_LINES[$i]}"     # 1-based line number of the heading

  # Determine the exclusive end line: either the next heading's line, or
  # EOF + 1 if this is the last heading.
  if [[ $((i + 1)) -lt "$ACTUAL_COUNT" ]]; then
    end_line="${HEADING_LINES[$((i + 1))]}"
  else
    end_line=$((TOTAL_LINES + 1))
  fi

  # Body = lines [start_line+1, end_line-1] (inclusive), 1-based. Convert to
  # 0-based array indices.
  body_start=$start_line              # array index = lineno (1-based) → array idx (0-based) = lineno - 1 + 1 = lineno; we want the line AFTER the heading
  body_end=$((end_line - 2))          # array idx of last body line: (end_line - 1) - 1

  # Strip HTML comments (possibly multi-line) and check for any non-blank
  # remainder. We concatenate body lines first, then run a small awk filter
  # that drops <!-- ... --> blocks (single-line and multi-line) and reports
  # whether any non-whitespace content remains.
  body_text=""
  j=$body_start
  while [[ $j -le $body_end && $j -lt $TOTAL_LINES ]]; do
    body_text+="${LINES[$j]}"$'\n'
    j=$((j + 1))
  done

  # awk pipeline:
  #   1. join all lines into one buffer (RS="\0" → whole-input mode would
  #      need gawk; instead, use a state machine that tracks "in comment").
  #   2. drop characters while inside a <!-- ... --> region, including
  #      multi-line.
  #   3. print whatever survives.
  stripped="$(
    printf '%s' "$body_text" | awk '
      BEGIN { in_comment = 0 }
      {
        line = $0
        out = ""
        i = 1
        while (i <= length(line)) {
          if (in_comment) {
            # Look for end marker "-->"
            end = index(substr(line, i), "-->")
            if (end == 0) { i = length(line) + 1; break }
            in_comment = 0
            i = i + end + 2  # skip past -->
          } else {
            # Look for start marker "<!--"
            start = index(substr(line, i), "<!--")
            if (start == 0) {
              out = out substr(line, i)
              i = length(line) + 1
            } else {
              out = out substr(line, i, start - 1)
              in_comment = 1
              i = i + start + 3  # skip past <!--
            }
          }
        }
        print out
      }
    '
  )"

  # Squash whitespace; if anything non-whitespace remains, the body is
  # non-empty.
  squashed="$(printf '%s' "$stripped" | tr -d '[:space:]')"
  if [[ -z "$squashed" ]]; then
    # Only complain for required sections; if the heading isn't in the
    # required set at all, rule 2 has already flagged it.
    is_required=0
    for req in "${REQUIRED_SECTIONS[@]}"; do
      if [[ "$heading" == "$req" ]]; then
        is_required=1
        break
      fi
    done
    if [[ $is_required -eq 1 ]]; then
      report "section is present but empty: $heading"
    fi
  fi

  i=$((i + 1))
done

if [[ $ERRORS -gt 0 ]]; then
  exit 1
fi

exit 0
