#!/usr/bin/env bash
set -uo pipefail

# validate-mc.sh — validate `MISSION-CONTROL.md` row markers + issue references
#                  (flat-ledger shape).
#
# Walks `MISSION-CONTROL.md` under the given root (default: the repo root inferred
# from this script's location) and asserts the embedded HTML-comment row markers
# are well-formed and internally consistent:
#
#   1. Every `<!-- mc:open=N,N,N -->` marker carries a list of strictly-ascending
#      positive integers, comma-joined, with no spaces, no leading/trailing
#      commas. `mc:none` markers must carry no list.
#   2. Every issue number listed in any `mc:open=` marker exists on GitHub — i.e.
#      `gh issue view <N>` returns 0. Can be skipped with `--no-github` for
#      offline runs or environments without `gh` authentication.
#   3. No issue number appears in two rows across the whole document.
#   4. Only the two legal tag shapes (`mc:none`, `mc:open=...`) are present —
#      legacy `mc:done=...` markers from the old phase-progress shape are no
#      longer permitted (shipped work disappears from the flat ledger).
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   test/validate-mc.sh                       # validate this repo (with GH check)
#   test/validate-mc.sh --no-github           # skip the gh issue view step
#   test/validate-mc.sh /path/to/other/repo   # validate elsewhere
#   test/validate-mc.sh --no-github /path/... # combine
#
# Exit codes:
#   0 — MISSION-CONTROL.md OK (or absent — nothing to validate)
#   1 — one or more validation failures; per-failure messages printed to stderr
#   2 — runtime/usage error (bad arg, unreadable root, gh unavailable when required)
#
# ── GITHUB-SEAM ──────────────────────────────────────────────────────────────
# The `gh issue view <N>` call below is the only GitHub-specific operation.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CHECK_GITHUB=1
ROOT=""

for arg in "$@"; do
  case "$arg" in
    --no-github)
      CHECK_GITHUB=0
      ;;
    -h|--help)
      sed -n '3,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "validate-mc.sh: unknown option: $arg" >&2
      exit 2
      ;;
    *)
      if [[ -n "$ROOT" ]]; then
        echo "validate-mc.sh: unexpected extra positional arg: $arg" >&2
        exit 2
      fi
      ROOT="$arg"
      ;;
  esac
done
ROOT="${ROOT:-$DEFAULT_ROOT}"

if [[ ! -d "$ROOT" ]]; then
  echo "validate-mc.sh: root not found or not a directory: $ROOT" >&2
  exit 2
fi

MC_FILE="$ROOT/MISSION-CONTROL.md"
if [[ ! -f "$MC_FILE" ]]; then
  echo "validate-mc: OK (no MISSION-CONTROL.md to validate)"
  exit 0
fi

if [[ $CHECK_GITHUB -eq 1 ]] && ! command -v gh >/dev/null 2>&1; then
  echo "validate-mc.sh: gh CLI is required for the issue-existence check (or pass --no-github)" >&2
  exit 2
fi

FAIL_COUNT=0
declare -a OPEN_NUMS=()
declare -a OPEN_NUMS_LINES=()
declare -a ALL_NUMS=()
declare -a ALL_NUMS_LINES=()

report_fail() {
  echo "FAIL $1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Validate a comma-joined integer list.
REASON=""
validate_int_list() {
  local list="$1"
  REASON=""
  if [[ -z "$list" ]]; then
    REASON="empty list"
    return 1
  fi
  if [[ "$list" == *" "* || "$list" == *$'\t'* ]]; then
    REASON="whitespace in list"
    return 1
  fi
  if [[ "$list" == ,* || "$list" == *, ]]; then
    REASON="leading or trailing comma"
    return 1
  fi
  if [[ "$list" == *,,* ]]; then
    REASON="empty token (double comma)"
    return 1
  fi
  local prev=-1 tok
  IFS=',' read -ra _toks <<< "$list"
  for tok in "${_toks[@]}"; do
    if ! [[ "$tok" =~ ^[1-9][0-9]*$ ]]; then
      REASON="non-positive-integer token: '$tok'"
      return 1
    fi
    if (( tok <= prev )); then
      REASON="list not strictly ascending (saw $tok after $prev)"
      return 1
    fi
    prev="$tok"
  done
  return 0
}

# Preprocess: elide multi-line HTML comment blocks. Real markers are single-
# line balanced `<!-- mc:... -->` spans; multi-line `<!-- ... -->` blocks (the
# Legend's documentation block) carry example markers that must not be parsed.

PREPROC_FILE="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$PREPROC_FILE'" EXIT

awk '
  BEGIN { in_block = 0 }
  {
    line = $0
    trimmed = line
    sub(/^[[:space:]]+/, "", trimmed)
    sub(/[[:space:]]+$/, "", trimmed)

    if (in_block) {
      if (trimmed == "-->") {
        in_block = 0
      }
      print ""
      next
    }
    if (trimmed == "<!--") {
      in_block = 1
      print ""
      next
    }
    print line
  }
' "$MC_FILE" > "$PREPROC_FILE"

# strip_backticks <line> → echoes the line with every `...` span removed.
strip_backticks() {
  local s="$1" out="" before after
  while [[ "$s" == *'`'*'`'* ]]; do
    before="${s%%'`'*}"
    after="${s#*'`'}"
    after="${after#*'`'}"
    out+="$before"
    s="$after"
  done
  out+="$s"
  printf '%s' "$out"
}

line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))

  stripped="$(strip_backticks "$line")"
  [[ "$stripped" != *"<!-- mc:"*"-->"* ]] && continue

  rest="$stripped"
  while [[ "$rest" == *"<!-- mc:"* ]]; do
    rest="${rest#*<!-- }"
    marker="${rest%%-->*}"
    marker="${marker%"${marker##*[![:space:]]}"}"
    rest="${rest#*-->}"

    case "$marker" in
      mc:none)
        ;;
      mc:none=*)
        report_fail "$MC_FILE:$line_no: mc:none must not carry a list (got '$marker')"
        ;;
      mc:open=*)
        list="${marker#*=}"
        if ! validate_int_list "$list"; then
          report_fail "$MC_FILE:$line_no: mc:open list malformed — $REASON (got '$list')"
        else
          IFS=',' read -ra _toks <<< "$list"
          for tok in "${_toks[@]}"; do
            ALL_NUMS+=("$tok")
            ALL_NUMS_LINES+=("$line_no")
            OPEN_NUMS+=("$tok")
            OPEN_NUMS_LINES+=("$line_no")
          done
        fi
        ;;
      mc:done=*)
        report_fail "$MC_FILE:$line_no: mc:done is no longer permitted in the flat-ledger MC (shipped work leaves the ledger); got '$marker'"
        ;;
      mc:*)
        report_fail "$MC_FILE:$line_no: unknown mc:* tag (got '$marker')"
        ;;
    esac
  done
done < "$PREPROC_FILE"

# ── Dedup check ──────────────────────────────────────────────────────────────
total_nums=${#ALL_NUMS[@]}
if [[ $total_nums -gt 1 ]]; then
  tmp_pairs="$(mktemp)"
  for ((i = 0; i < total_nums; i++)); do
    printf '%s %s\n' "${ALL_NUMS[$i]}" "${ALL_NUMS_LINES[$i]}"
  done | sort -n -k1,1 -k2,2 > "$tmp_pairs"

  prev_num=""
  prev_line=""
  while IFS=' ' read -r n l; do
    if [[ "$n" == "$prev_num" ]]; then
      report_fail "$MC_FILE: issue #$n appears in multiple rows (lines $prev_line and $l)"
    fi
    prev_num="$n"
    prev_line="$l"
  done < "$tmp_pairs"
  rm -f "$tmp_pairs"
fi

# ── GitHub existence check (the seam) ────────────────────────────────────────
if [[ $CHECK_GITHUB -eq 1 && ${#OPEN_NUMS[@]} -gt 0 ]]; then
  for ((i = 0; i < ${#OPEN_NUMS[@]}; i++)); do
    n="${OPEN_NUMS[$i]}"
    l="${OPEN_NUMS_LINES[$i]}"
    # GITHUB-SEAM
    if ! gh issue view "$n" >/dev/null 2>&1; then
      report_fail "$MC_FILE:$l: mc:open issue #$n does not exist on GitHub (or gh auth failed)"
    fi
  done
fi

# ── Result ───────────────────────────────────────────────────────────────────
if [[ $FAIL_COUNT -eq 0 ]]; then
  total_open=${#OPEN_NUMS[@]}
  total_all=${#ALL_NUMS[@]}
  if [[ $CHECK_GITHUB -eq 1 ]]; then
    echo "validate-mc: OK ($total_all issue refs across rows, $total_open open verified on GitHub)"
  else
    echo "validate-mc: OK ($total_all issue refs across rows, GitHub check skipped)"
  fi
  exit 0
else
  echo "validate-mc: FAIL ($FAIL_COUNT issue(s))" >&2
  exit 1
fi
