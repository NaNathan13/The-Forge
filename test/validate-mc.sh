#!/usr/bin/env bash
set -uo pipefail

# validate-mc.sh — validate `MISSION-CONTROL.md` row markers + issue references
#                  + sub-phase table column shape.
#
# Walks `MISSION-CONTROL.md` under the given root (default: the repo root inferred
# from this script's location) and asserts the embedded HTML-comment row markers
# are well-formed and internally consistent:
#
#   1. Every `<!-- mc:open=N,N,N -->` / `<!-- mc:done=N,N,N -->` marker carries a
#      list of sorted integers, comma-joined, with no spaces, no leading/trailing
#      commas. `mc:none` markers must carry no list.
#   2. Every issue number listed in any `mc:open=` marker exists on GitHub — i.e.
#      `gh issue view <N>` returns 0. This is the *GitHub-specific seam* (see the
#      GITHUB-SEAM section below) and can be skipped with `--no-github` for
#      offline runs or environments without `gh` authentication.
#   3. No issue number appears in two rows across the whole document
#      (deduplication: an issue belongs to exactly one sub-phase).
#   4. Every sub-phase table (any markdown table whose header starts with
#      `| # | Sub-phase |`) has the expected column sequence
#      `# | Sub-phase | Status | Blocked by | PRD | Issues`. Stub rows
#      (`⏳ queued` / `⏳ scope-TBD` with `<!-- mc:none -->`) are valid as long as
#      they satisfy this shape.
#   5. Every `🚧 in-progress` row whose `Blocked by` cell is not `—` must
#      reference one or more sub-phase IDs that actually exist somewhere in MC
#      (an ID is a cell-text like `3a`, `3b`, `3a, 3b`).
#
# This validator is wired into CI (`.github/workflows/validate-mc.yml`) so silent
# MC drift becomes a failed check on every PR and every push to `main`.
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
# The `gh issue view <N>` call below is the only GitHub-specific operation in
# this validator. A future VCS-abstraction phase (P4-era WHJ v2 work, per
# `docs/prds/improvements-3a-validation.md` non-goals) will replace this call
# with an abstraction layer. Until then, this is the seam.
#
# Search for `# GITHUB-SEAM` to find the call site.
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

CHECK_GITHUB=1
ROOT=""

# ── Argument parsing ─────────────────────────────────────────────────────────
for arg in "$@"; do
  case "$arg" in
    --no-github)
      CHECK_GITHUB=0
      ;;
    -h|--help)
      sed -n '3,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
  # No MC file → nothing to validate. Treat as success (consistent with
  # validate-skills.sh's behaviour for missing trees).
  echo "validate-mc: OK (no MISSION-CONTROL.md to validate)"
  exit 0
fi

if [[ $CHECK_GITHUB -eq 1 ]] && ! command -v gh >/dev/null 2>&1; then
  echo "validate-mc.sh: gh CLI is required for the issue-existence check (or pass --no-github)" >&2
  exit 2
fi

# ── Collect markers ──────────────────────────────────────────────────────────
# We parse each `<!-- mc:... -->` marker out of MC_FILE one at a time, tagging
# each with its line number so failure messages can point at the source line.
#
# Three legal forms:
#   <!-- mc:none -->
#   <!-- mc:open=N,N,N -->
#   <!-- mc:done=N,N,N -->
#
# We also explicitly catch the common malformations: spaces in the list, a
# trailing comma, unsorted integers, a list on `mc:none`, an unknown `mc:*`
# tag, or a `mc:open=` / `mc:done=` with an empty list.

FAIL_COUNT=0
declare -a OPEN_NUMS=()
declare -a OPEN_NUMS_LINES=()
declare -a ALL_NUMS=()
declare -a ALL_NUMS_LINES=()

report_fail() {
  echo "FAIL $1" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

# Validate a comma-joined integer list. Echoes the list back (unchanged) on
# success and returns 0. On failure, returns non-zero with a message in $REASON.
# Rules: non-empty, no whitespace anywhere, no leading/trailing comma, every
# token is a positive integer with no leading zeros (except literal "0" which
# is itself rejected — issue numbers are >= 1), strictly ascending order.
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
    # Ascending order — strict (no duplicates within a single marker).
    if (( tok <= prev )); then
      REASON="list not strictly ascending (saw $tok after $prev)"
      return 1
    fi
    prev="$tok"
  done
  return 0
}

# Scan the file line by line. We only look at lines containing an `mc:`
# marker — they are HTML comments embedded in the table rows, so each marker
# is on a single line.
#
# Two classes of false-positive must be filtered out before we extract
# markers:
#
#   1. Multi-line HTML comment blocks. The `## 🪐 Phase progress` block uses a
#      large `<!-- ... -->` comment to document the marker grammar; the
#      example tokens (`<!-- mc:open=N,N -->`) sit *inside* that outer comment
#      and are not real markers. We track a simple `in_comment_block` flag —
#      a line whose first `<!--` is not closed by a later `-->` on the same
#      line opens a block; a line with a `-->` closes it. Real markers are
#      single-line balanced comments, so they never flip the flag.
#
#   2. Backtick-wrapped marker shapes. The legend block at the bottom writes
#      the marker grammar inline with single backticks. We strip every
#      single-backtick span before extracting markers so the documentation
#      reads naturally but is not parsed as real markers.

# strip_backticks <line> → echoes the line with every `...` span removed.
# Greedy left-to-right: find the next opening backtick, find its closer, drop
# both. If a backtick is unmatched on the line, leave it as-is (no real marker
# on the line will be inside such a tail).
strip_backticks() {
  local s="$1" out="" before after
  while [[ "$s" == *'`'*'`'* ]]; do
    before="${s%%'`'*}"
    after="${s#*'`'}"   # everything after the first backtick
    after="${after#*'`'}" # everything after the second backtick
    out+="$before"
    s="$after"
  done
  out+="$s"
  printf '%s' "$out"
}

# Preprocess MC_FILE to elide every HTML comment whose *opening* `<!--` does
# not have a matching `-->` on the same line. These are the multi-line
# documentation blocks (e.g. the `## 🪐 Phase progress` legend), and any
# `<!-- mc:... -->` strings *inside* them are documentation, not real markers.
#
# Real markers are single-line balanced comments (`<!-- mc:open=N,N -->` on one
# line), so single-line `<!-- ... -->` spans are left intact.
#
# Implementation: an awk pass that drops every line from a lone-open `<!--`
# through the next `-->` (inclusive) — preserving original line numbering by
# emitting blank lines in their place so subsequent failure messages still
# reference the source line.

PREPROC_FILE="$(mktemp)"
# shellcheck disable=SC2064
trap "rm -f '$PREPROC_FILE'" EXIT

awk '
  BEGIN { in_block = 0 }
  {
    line = $0
    # Trim leading/trailing whitespace for the block-boundary detector. Block
    # boundaries are stand-alone `<!--` and `-->` lines (the documentation
    # legend uses this style); table-row markers are balanced on one line and
    # never appear as a bare delimiter, so we will not mistake them.
    trimmed = line
    sub(/^[[:space:]]+/, "", trimmed)
    sub(/[[:space:]]+$/, "", trimmed)

    if (in_block) {
      if (trimmed == "-->") {
        in_block = 0
      }
      print ""   # placeholder so line numbers stay aligned with source
      next
    }
    # Open block: a stand-alone `<!--` line (the legend pattern). Anything
    # else (including a fully balanced `<!-- ... -->` on one line) passes
    # through to the marker scanner.
    if (trimmed == "<!--") {
      in_block = 1
      print ""
      next
    }
    print line
  }
' "$MC_FILE" > "$PREPROC_FILE"

line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))

  # Skip lines without a marker. After backtick-stripping (which removes the
  # legend block's quoted examples like `<!-- mc:open=N,N -->`), if no
  # `<!-- mc:...-->` remains, move on.
  stripped="$(strip_backticks "$line")"
  [[ "$stripped" != *"<!-- mc:"*"-->"* ]] && continue

  # Extract every `<!-- mc:... -->` marker on this line. There is normally one
  # per line, but the parser does not assume that.
  rest="$stripped"
  while [[ "$rest" == *"<!-- mc:"* ]]; do
    rest="${rest#*<!-- }"
    marker="${rest%%-->*}"
    # Strip the trailing space that lives between the payload and `-->`.
    marker="${marker%"${marker##*[![:space:]]}"}"
    # Advance past this marker so the next loop iteration sees the next one.
    rest="${rest#*-->}"

    case "$marker" in
      mc:none)
        # Well-formed empty marker. Nothing to add.
        ;;
      mc:none=*)
        report_fail "$MC_FILE:$line_no: mc:none must not carry a list (got '$marker')"
        ;;
      mc:open=*|mc:done=*)
        kind="${marker%%=*}"           # mc:open or mc:done
        list="${marker#*=}"
        if ! validate_int_list "$list"; then
          report_fail "$MC_FILE:$line_no: $kind list malformed — $REASON (got '$list')"
        else
          # Collect numbers for cross-row dedup + GH existence check.
          IFS=',' read -ra _toks <<< "$list"
          for tok in "${_toks[@]}"; do
            ALL_NUMS+=("$tok")
            ALL_NUMS_LINES+=("$line_no")
            if [[ "$kind" == "mc:open" ]]; then
              OPEN_NUMS+=("$tok")
              OPEN_NUMS_LINES+=("$line_no")
            fi
          done
        fi
        ;;
      mc:*)
        report_fail "$MC_FILE:$line_no: unknown mc:* tag (got '$marker')"
        ;;
    esac
  done
done < "$PREPROC_FILE"

# ── Sub-phase table column-shape + in-progress Blocked-by checks ─────────────
# Scan the preprocessed file for sub-phase tables. A sub-phase table is any
# markdown table whose header row starts with `| # | Sub-phase |`. This
# distinguishes it from the Architectural-items table (header `| # | Item |`)
# and any future non-sub-phase tables.
#
# Required header column sequence (after trimming whitespace around each cell):
#
#     # | Sub-phase | Status | Blocked by | PRD | Issues
#
# For each data row of every sub-phase table, also collect the sub-phase ID
# from column 1 (e.g. `3a`, `4a`) into ALL_SUBPHASE_IDS. This is the universe
# against which `Blocked by` references are validated below.
#
# Then for each `🚧 in-progress` data row whose Blocked-by cell is not `—`,
# split the cell by `,`, trim, and verify each ID is in ALL_SUBPHASE_IDS.

EXPECTED_COLS=("#" "Sub-phase" "Status" "Blocked by" "PRD" "Issues")

# split_table_row <line>
# Splits a markdown table row by `|`, trims whitespace around each cell, and
# stores the result in the global CELLS array (length in #CELLS[@]). The
# leading and trailing pipes are dropped. Lines that are not table rows (no
# leading `|`) leave CELLS empty.
#
# Uses a global rather than echoing one cell per line because some cell values
# legitimately contain newlines from cell-text quirks (they shouldn't in MC,
# but defending against future surprises is cheap), and `mapfile` is not
# available on the bash 3.2 that ships with macOS.
split_table_row() {
  CELLS=()
  local line="$1"
  [[ "$line" != \|* ]] && return 0
  local trimmed="${line#|}"     # drop leading pipe
  trimmed="${trimmed%|}"        # drop trailing pipe (the row always ends `|`)
  local IFS='|'
  read -ra _split_cells <<< "$trimmed"
  local cell
  for cell in "${_split_cells[@]}"; do
    cell="${cell#"${cell%%[![:space:]]*}"}"
    cell="${cell%"${cell##*[![:space:]]}"}"
    CELLS+=("$cell")
  done
}

declare -a ALL_SUBPHASE_IDS=()
declare -a INPROGRESS_REFS=()        # parallel arrays: ID-list + line
declare -a INPROGRESS_REFS_LINES=()

in_subphase_table=0
saw_header_sep=0
table_start_line=0

line_no=0
while IFS= read -r line; do
  line_no=$((line_no + 1))

  if [[ $in_subphase_table -eq 0 ]]; then
    # Detect a sub-phase table header: a row whose first two cells are `#` and
    # `Sub-phase`. Validate the rest of the header columns immediately.
    if [[ "$line" == \|* ]]; then
      split_table_row "$line"
      if [[ ${#CELLS[@]} -ge 2 && "${CELLS[0]}" == "#" && "${CELLS[1]}" == "Sub-phase" ]]; then
        in_subphase_table=1
        saw_header_sep=0
        table_start_line=$line_no
        # Verify the full column sequence.
        ok=1
        if [[ ${#CELLS[@]} -ne ${#EXPECTED_COLS[@]} ]]; then
          ok=0
        else
          for ((i = 0; i < ${#EXPECTED_COLS[@]}; i++)); do
            if [[ "${CELLS[$i]}" != "${EXPECTED_COLS[$i]}" ]]; then
              ok=0
              break
            fi
          done
        fi
        if [[ $ok -eq 0 ]]; then
          report_fail "$MC_FILE:$line_no: sub-phase table header must be exactly '| ${EXPECTED_COLS[0]} | ${EXPECTED_COLS[1]} | ${EXPECTED_COLS[2]} | ${EXPECTED_COLS[3]} | ${EXPECTED_COLS[4]} | ${EXPECTED_COLS[5]} |' (got '${CELLS[*]}')"
        fi
      fi
    fi
    continue
  fi

  # Inside a sub-phase table. The first non-empty row after the header should
  # be the markdown separator row (`| --- | --- | ... |`). After that, data
  # rows continue until we hit a non-table line.
  if [[ "$line" != \|* ]]; then
    # Table ended — blank line or new heading.
    in_subphase_table=0
    saw_header_sep=0
    continue
  fi

  if [[ $saw_header_sep -eq 0 ]]; then
    # Separator row — accept any `| --- | --- | ... |` shape and move on. We
    # do not strictly validate it; the existing markdown rendering checks
    # there.
    saw_header_sep=1
    continue
  fi

  # Data row. Pull cells.
  split_table_row "$line"
  if [[ ${#CELLS[@]} -lt ${#EXPECTED_COLS[@]} ]]; then
    report_fail "$MC_FILE:$line_no: sub-phase table row has ${#CELLS[@]} cells, expected at least ${#EXPECTED_COLS[@]}"
    continue
  fi
  sp_id="${CELLS[0]}"
  sp_status="${CELLS[2]}"
  sp_blocked="${CELLS[3]}"

  # Record the sub-phase ID for cross-row reference checks.
  if [[ -n "$sp_id" ]]; then
    ALL_SUBPHASE_IDS+=("$sp_id")
  fi

  # In-progress + non-`—` Blocked-by → collect for the existence check.
  # The status cell contains emoji + text (e.g. `🚧 in-progress`); a substring
  # match keeps this resilient to surrounding whitespace or trailing notes.
  if [[ "$sp_status" == *"in-progress"* && "$sp_blocked" != "—" ]]; then
    INPROGRESS_REFS+=("$sp_blocked")
    INPROGRESS_REFS_LINES+=("$line_no")
  fi
done < "$PREPROC_FILE"

# Validate in-progress Blocked-by references.
if [[ ${#INPROGRESS_REFS[@]} -gt 0 ]]; then
  for ((i = 0; i < ${#INPROGRESS_REFS[@]}; i++)); do
    refs="${INPROGRESS_REFS[$i]}"
    refs_line="${INPROGRESS_REFS_LINES[$i]}"
    IFS=',' read -ra _refs <<< "$refs"
    for raw_ref in "${_refs[@]}"; do
      ref="${raw_ref#"${raw_ref%%[![:space:]]*}"}"
      ref="${ref%"${ref##*[![:space:]]}"}"
      [[ -z "$ref" ]] && continue
      found=0
      for sp in "${ALL_SUBPHASE_IDS[@]}"; do
        if [[ "$sp" == "$ref" ]]; then
          found=1
          break
        fi
      done
      if [[ $found -eq 0 ]]; then
        report_fail "$MC_FILE:$refs_line: 🚧 in-progress row references unknown sub-phase ID '$ref' in Blocked by"
      fi
    done
  done
fi

# ── Dedup check ──────────────────────────────────────────────────────────────
# Every issue number across all rows must be unique. We sort and walk the
# parallel arrays so the error message can point at the second occurrence.
total_nums=${#ALL_NUMS[@]}
if [[ $total_nums -gt 1 ]]; then
  # Build "num line" pairs, sort numerically by the first field, then walk for
  # adjacent duplicates.
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
# Every issue in any `mc:open=` row must be a real GitHub issue. We skip this
# entirely under --no-github (e.g. offline test harness) or if the marker
# parsing already failed (no point hammering GH if MC_FILE is broken).
#
# We DO NOT check `mc:done=` numbers — a closed/deleted issue is still legal
# for a done row (it's a historical record), and the call cost adds up.
if [[ $CHECK_GITHUB -eq 1 && ${#OPEN_NUMS[@]} -gt 0 ]]; then
  for ((i = 0; i < ${#OPEN_NUMS[@]}; i++)); do
    n="${OPEN_NUMS[$i]}"
    l="${OPEN_NUMS_LINES[$i]}"
    # GITHUB-SEAM: this `gh issue view` invocation is the single point of
    # GitHub coupling in this validator. A future VCS abstraction replaces it.
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
