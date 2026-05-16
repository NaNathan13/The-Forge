#!/usr/bin/env bash
set -uo pipefail

# reconcile-mc.sh — full MISSION-CONTROL.md close-out (reconcile + commit + push).
#
# Sole writer of MC. Invoked by:
#
#   1. `/seal` step 5 + step 7 — folded into a single call (sub-phase 3f / #238).
#   2. Operators on demand — for out-of-band merges, human-closed issues, or
#      anywhere MC has drifted from GitHub state without a /seal run.
#
# ── What it does ─────────────────────────────────────────────────────────────
# Reads `MISSION-CONTROL.md` and:
#
#   1. Identifies every row with an `<!-- mc:open=N,N -->` marker.
#   2. Queries `gh issue view N --json state -q .state` for each issue. Rows
#      whose full `mc:open` set is CLOSED are "shipped".
#   3. Advances shipped rows in place:
#        - status emoji `🚧 in-progress` → `✅ shipped`
#        - marker `<!-- mc:open=N,N -->` → `<!-- mc:done=N,N -->`
#        - `Blocked by` cell → `—` (matches the 6-column schema policy that
#          shipped rows carry `—`)
#   4. Recomputes phase progress bars by piping `scripts/derive-progress.sh`
#      output back into each `### <phase>` header line.
#   5. Recomputes the "Telemetry — right now" banner: **Phase** (most recent
#      in-flight or queued sub-phase's phase) + **In flight** (count of
#      `🚧 in-progress` rows; `—` when 0).
#   6. Recomputes the "Recommended next prompt" using the priority order
#      previously baked into /seal step 5f.
#   7. Shows `git diff MISSION-CONTROL.md` on stdout.
#   8. If the diff is non-empty: `git add MISSION-CONTROL.md` + commit + push.
#      Commit message: `chore(mc): reconcile YYYY-MM-DD — <summary>`.
#
# ── MC schema ────────────────────────────────────────────────────────────────
# Targets the 6-column schema (issue #236):
#   `# | Sub-phase | Status | Blocked by | PRD | Issues`
# `Blocked by` is column 4 (0-indexed 4 once the leading empty cell from the
# leading `|` is included in `IFS='|' read -ra`).
#
# Tables under `## 🛸 Architectural items` use a different header (`| # | Item |`)
# and are NOT touched.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — success (whether or not a commit was produced)
#   1 — runtime error (gh failure, malformed MC, etc.)
#   2 — usage error (bad arg)
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   scripts/reconcile-mc.sh              # reconcile this repo's MC, commit + push
#   scripts/reconcile-mc.sh --dry-run    # show diff; do not commit/push
#
# The `--dry-run` flag is read by `/seal` only for human-confirm flows; the
# default (no flag) matches the documented contract — full close-out.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MC_FILE="$REPO_ROOT/MISSION-CONTROL.md"
DERIVE_PROGRESS="$SCRIPT_DIR/derive-progress.sh"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '3,56p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    *)
      echo "reconcile-mc.sh: unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

if [[ ! -f "$MC_FILE" ]]; then
  echo "reconcile-mc.sh: MISSION-CONTROL.md not found at $MC_FILE" >&2
  exit 1
fi
if [[ ! -x "$DERIVE_PROGRESS" ]]; then
  echo "reconcile-mc.sh: derive-progress.sh not found or not executable at $DERIVE_PROGRESS" >&2
  exit 1
fi

# ── Phase 1: identify shipped-now rows ───────────────────────────────────────
# Read MC line-by-line. For each line carrying `<!-- mc:open=N,N -->`, extract
# the issue list. Query each issue's state. If ALL are CLOSED, mark the line
# index as "advance".

# Read MC into an array.
declare -a MC_LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  MC_LINES+=("$line")
done < "$MC_FILE"

# Cache issue states across rows so we don't re-query the same N if it appears
# twice (defensive — shouldn't happen but cheap insurance). Uses parallel
# arrays instead of `declare -A` so this works on macOS bash 3.2 (the project's
# baseline — see scripts/derive-progress.sh for the same restriction).
ISSUE_CACHE_KEYS=()
ISSUE_CACHE_VALS=()

# _cache_lookup <key>  — echoes the cached value or empty string.
_cache_lookup() {
  local k="$1" i
  for ((i = 0; i < ${#ISSUE_CACHE_KEYS[@]}; i++)); do
    if [[ "${ISSUE_CACHE_KEYS[$i]}" == "$k" ]]; then
      printf '%s' "${ISSUE_CACHE_VALS[$i]}"
      return 0
    fi
  done
  return 1
}

# _cache_set <key> <value>
_cache_set() {
  ISSUE_CACHE_KEYS+=("$1")
  ISSUE_CACHE_VALS+=("$2")
}

# is_issue_closed <N>  — sets exit 0 if closed, 1 otherwise. Caches the result.
is_issue_closed() {
  local n="$1" st
  if st="$(_cache_lookup "$n")"; then
    :
  else
    if ! st="$(gh issue view "$n" --json state -q .state 2>/dev/null)"; then
      echo "reconcile-mc.sh: gh issue view $n failed" >&2
      _cache_set "$n" "UNKNOWN"
      return 1
    fi
    _cache_set "$n" "$st"
  fi
  [[ "$st" == "CLOSED" ]]
}

# all_closed <comma-separated-N-list>  — returns 0 iff every listed issue CLOSED.
all_closed() {
  local list="$1" n
  IFS=',' read -ra arr <<< "$list"
  for n in "${arr[@]}"; do
    n="${n// /}"  # strip whitespace
    [[ -z "$n" ]] && continue
    is_issue_closed "$n" || return 1
  done
  return 0
}

# transform_row <line>  — applied to lines whose mc:open set is all-closed.
# Performs: status emoji, marker, Blocked-by → —. Leaves all other cells intact.
transform_row() {
  local s="$1"
  # 1. Status emoji: any leading whitespace-then-🚧 in-progress in a status cell.
  #    The status cell is the third pipe-delimited field. Use awk so we operate
  #    only on that cell.
  # 2. Blocked by cell: 4th pipe-delimited field → ` — `.
  # 3. Marker: mc:open=... → mc:done=...
  #
  # Done via awk with field separator `|`. The row's leading `|` produces an
  # empty $1; $2=#, $3=Sub-phase, $4=Status, $5=Blocked by, $6=PRD, $7=Issues.
  # awk script must NOT contain literal apostrophes — the script is bash-
  # single-quoted, so an embedded `'` closes the quote. Keep awk comments
  # apostrophe-free.
  s="$(printf '%s' "$s" | awk -F'|' -v OFS='|' '
    {
      if (NF >= 7) {
        # Status cell: replace in-progress glyph with shipped glyph,
        # canonicalizing the whole cell to padded form.
        cell = $4
        # Canonicalize cell to ` shipped ` (single-space padded) when the
        # in-progress glyph is present anywhere inside it.
        if (match(cell, /🚧[^|]*/)) {
          $4 = " ✅ shipped "
        }
        # Blocked by: replace with ` — ` (single-space padded).
        $5 = " — "
      }
      print
    }
  ')"
  # Marker: do this after awk, on the whole line — markers live inside the
  # last cell so the awk transform above did not touch them.
  s="${s//<!-- mc:open=/<!-- mc:done=}"
  printf '%s' "$s"
}

# Iterate MC_LINES; if a line is a data row containing `mc:open=`, decide if
# the full set is CLOSED, and if so, replace the line in place.
ROWS_ADVANCED=0
for i in "${!MC_LINES[@]}"; do
  line="${MC_LINES[$i]}"
  # Cheap early-out: only data rows with markers are candidates.
  [[ "$line" == *"<!-- mc:open="* ]] || continue
  # Extract the N,N list between `mc:open=` and ` -->`.
  ids="${line#*<!-- mc:open=}"
  ids="${ids%% -->*}"
  if all_closed "$ids"; then
    MC_LINES[$i]="$(transform_row "$line")"
    ROWS_ADVANCED=$((ROWS_ADVANCED + 1))
  fi
done

# Write the in-memory MC back to disk so subsequent steps (derive-progress,
# banner recompute) see the advanced state.
{
  for line in "${MC_LINES[@]}"; do
    printf '%s\n' "$line"
  done
} > "$MC_FILE.tmp" && mv "$MC_FILE.tmp" "$MC_FILE"

# ── Phase 2: recompute phase progress bars ───────────────────────────────────
# Pipe derive-progress.sh's output back into MC, replacing each `### <phase>`
# header line. The script's output is one canonical `### <phase> <bar> N/M`
# per phase; we splice them in by matching the phase name prefix.

# Capture derive-progress output regardless of its exit code (exit 1 just means
# "drift" — that's exactly what we're about to fix).
declare -a DERIVED_HEADERS=()
while IFS= read -r dh || [[ -n "$dh" ]]; do
  [[ -z "$dh" ]] && continue
  DERIVED_HEADERS+=("$dh")
done < <(bash "$DERIVE_PROGRESS" "$REPO_ROOT" 2>/dev/null)

# Build a map: phase name (the text after `### `, before the trailing bar) →
# canonical header line. Parallel arrays for macOS bash 3.2 compatibility.
PHASE_KEYS=()
PHASE_VALS=()
for dh in "${DERIVED_HEADERS[@]}"; do
  # Strip leading `### ` then the trailing ` <bar> N/M`.
  rest="${dh#"### "}"
  # Pattern from derive-progress: strip trailing ` ▓...░... N/M`.
  name="$(printf '%s' "$rest" | sed -E 's/[[:space:]]+[▓░]*[[:space:]]*[0-9]+\/([0-9]+|\?)[[:space:]]*$//')"
  PHASE_KEYS+=("$name")
  PHASE_VALS+=("$dh")
done

# phase_canonical <name>  — echoes the canonical `### <phase> <bar> N/M` for
# `<name>` if present, empty string otherwise.
phase_canonical() {
  local k="$1" i
  for ((i = 0; i < ${#PHASE_KEYS[@]}; i++)); do
    if [[ "${PHASE_KEYS[$i]}" == "$k" ]]; then
      printf '%s' "${PHASE_VALS[$i]}"
      return 0
    fi
  done
  return 1
}

# Re-read MC (just-written) and replace `### ` lines under `## 🪐 Phase progress`.
declare -a NEW_LINES=()
in_phase_progress=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "## "* ]]; then
    in_phase_progress=0
    [[ "$line" == "## 🪐 Phase progress"* ]] && in_phase_progress=1
    NEW_LINES+=("$line")
    continue
  fi
  if (( in_phase_progress )) && [[ "$line" == "### "* ]]; then
    rest="${line#"### "}"
    name="$(printf '%s' "$rest" | sed -E 's/[[:space:]]+[▓░]*[[:space:]]*[0-9]+\/([0-9]+|\?)[[:space:]]*$//')"
    if canon="$(phase_canonical "$name")"; then
      NEW_LINES+=("$canon")
    else
      NEW_LINES+=("$line")
    fi
    continue
  fi
  NEW_LINES+=("$line")
done < "$MC_FILE"

{
  for line in "${NEW_LINES[@]}"; do
    printf '%s\n' "$line"
  done
} > "$MC_FILE.tmp" && mv "$MC_FILE.tmp" "$MC_FILE"

# ── Phase 3: recompute Telemetry banner ──────────────────────────────────────
# Scan the (just-updated) MC for:
#   - In-flight count: rows whose status cell starts with 🚧 in-progress
#   - Most recent in-flight or queued phase: take the LAST `### <phase>` whose
#     table contains a row with 🚧 in-progress or ⏳ queued. Fall back to the
#     LAST phase containing any 📝 prd-ready row. Final fallback: the last
#     phase in MC.

CUR_PHASE=""
LAST_FLIGHT_PHASE=""
LAST_QUEUED_PHASE=""
LAST_PRD_PHASE=""
LAST_PHASE=""
IN_FLIGHT_COUNT=0
in_phase_progress=0
while IFS= read -r line || [[ -n "$line" ]]; do
  if [[ "$line" == "## "* ]]; then
    in_phase_progress=0
    [[ "$line" == "## 🪐 Phase progress"* ]] && in_phase_progress=1
    continue
  fi
  (( in_phase_progress )) || continue
  if [[ "$line" == "### "* ]]; then
    rest="${line#"### "}"
    name="$(printf '%s' "$rest" | sed -E 's/[[:space:]]+[▓░]*[[:space:]]*[0-9]+\/([0-9]+|\?)[[:space:]]*$//')"
    CUR_PHASE="$name"
    LAST_PHASE="$name"
    continue
  fi
  # Status detection on data rows. Use the same parse as derive-progress.
  if [[ "$line" == "|"* ]]; then
    IFS='|' read -ra cells <<< "$line"
    if (( ${#cells[@]} >= 4 )); then
      status="${cells[3]}"
      status="${status#"${status%%[![:space:]]*}"}"
      status="${status%"${status##*[![:space:]]}"}"
      case "$status" in
        "🚧"*)
          IN_FLIGHT_COUNT=$((IN_FLIGHT_COUNT + 1))
          LAST_FLIGHT_PHASE="$CUR_PHASE"
          ;;
        "⏳"*)
          LAST_QUEUED_PHASE="$CUR_PHASE"
          ;;
        "📝"*)
          LAST_PRD_PHASE="$CUR_PHASE"
          ;;
      esac
    fi
  fi
done < "$MC_FILE"

# Phase priority: in-flight > queued > prd-ready > last phase.
if [[ -n "$LAST_FLIGHT_PHASE" ]]; then
  TELEMETRY_PHASE="$LAST_FLIGHT_PHASE"
elif [[ -n "$LAST_QUEUED_PHASE" ]]; then
  TELEMETRY_PHASE="$LAST_QUEUED_PHASE"
elif [[ -n "$LAST_PRD_PHASE" ]]; then
  TELEMETRY_PHASE="$LAST_PRD_PHASE"
else
  TELEMETRY_PHASE="$LAST_PHASE"
fi

# Look up TELEMETRY_PHASE's canonical header (with bar) — that's what goes
# into `**Phase:**`.
if ! TELEMETRY_PHASE_HEADER="$(phase_canonical "$TELEMETRY_PHASE")"; then
  TELEMETRY_PHASE_HEADER="### $TELEMETRY_PHASE"
fi
# Strip the leading `### ` to get the banner-form `<name> <bar> N/M`. Quoted
# pattern prevents bash from parsing `####` as `## ##` (longest-prefix match
# on `## ` then on ` ` — wrong, eats arbitrary leading hashes).
TELEMETRY_PHASE_BANNER="${TELEMETRY_PHASE_HEADER#"### "}"

# In-flight banner value: count, or `—` when 0.
if (( IN_FLIGHT_COUNT == 0 )); then
  IN_FLIGHT_BANNER="—"
else
  IN_FLIGHT_BANNER="$IN_FLIGHT_COUNT"
fi

# Rewrite the banner lines in-place.
declare -a NEW_LINES2=()
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    "**Phase:**"*)
      NEW_LINES2+=("**Phase:** ${TELEMETRY_PHASE_BANNER}")
      ;;
    "**In flight:**"*)
      NEW_LINES2+=("**In flight:** ${IN_FLIGHT_BANNER}")
      ;;
    *)
      NEW_LINES2+=("$line")
      ;;
  esac
done < "$MC_FILE"
{
  for line in "${NEW_LINES2[@]}"; do
    printf '%s\n' "$line"
  done
} > "$MC_FILE.tmp" && mv "$MC_FILE.tmp" "$MC_FILE"

# ── Phase 4: recompute Recommended next prompt ───────────────────────────────
# Priority order (from /seal step 5f):
#   1. Open temper PRs remain                          → `/seal`
#   2. Temper in progress (🚧 row + open ready-for-agent issue)
#                                                       → `/temper <N>` (lowest)
#   3. Any ready-for-agent + slice:* issue              → `/forge`
#   4. Any 📝 prd-ready row with issues filed (mc:open) → `/forge`
#   5. Any ⏳ queued row                                → `/ponder <sub-phase>`
#   6. Otherwise                                        → "All features shipped" note

REC_PROMPT=""

# 1. Open temper PRs?
open_temper_prs="$(gh pr list --state open --json headRefName --jq '.[] | select(.headRefName | test("^feat/#[0-9]+-")) | .headRefName' 2>/dev/null || true)"
if [[ -n "$open_temper_prs" ]]; then
  REC_PROMPT="/seal"
fi

# 2. Temper in progress: 🚧 row exists AND open ready-for-agent issue exists.
if [[ -z "$REC_PROMPT" ]] && (( IN_FLIGHT_COUNT > 0 )); then
  lowest_ready="$(gh issue list --state open --label ready-for-agent --json number --jq 'sort_by(.number) | .[0].number' 2>/dev/null || true)"
  if [[ -n "$lowest_ready" && "$lowest_ready" != "null" ]]; then
    REC_PROMPT="/temper $lowest_ready"
  fi
fi

# 3. Any ready-for-agent + slice:* issue → /forge.
if [[ -z "$REC_PROMPT" ]]; then
  ready_count="$(gh issue list --state open --label ready-for-agent --json labels --jq '[.[] | select(.labels | map(.name) | any(. | startswith("slice:")))] | length' 2>/dev/null || echo 0)"
  if [[ -n "$ready_count" && "$ready_count" != "0" && "$ready_count" != "null" ]]; then
    REC_PROMPT="/forge"
  fi
fi

# 4. Any 📝 prd-ready row with mc:open marker → /forge.
if [[ -z "$REC_PROMPT" ]]; then
  if grep -qE '^\|[^|]*\|[^|]*\|[[:space:]]*📝[^|]*\|.*<!-- mc:open=' "$MC_FILE"; then
    REC_PROMPT="/forge"
  fi
fi

# 5. Any ⏳ queued row → /ponder <id>.  Take the lowest-by-sub-phase-id row.
if [[ -z "$REC_PROMPT" ]]; then
  queued_id="$(awk -F'|' '
    /^\|[[:space:]]*[0-9a-zA-Z]+[[:space:]]*\|/ {
      status = $4
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
      if (status ~ /^⏳/) {
        id = $2
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", id)
        print id
        exit
      }
    }
  ' "$MC_FILE")"
  if [[ -n "$queued_id" ]]; then
    REC_PROMPT="/ponder $queued_id"
  fi
fi

# 6. Fallback note.
REC_PROMPT_NOTE=""
if [[ -z "$REC_PROMPT" ]]; then
  REC_PROMPT_NOTE="_All features shipped or in motion. No recommendation._"
fi

# Splice the new recommendation into the MC's `**Recommended next prompt:**`
# block — between the literal `**Recommended next prompt:**` line and the next
# `## ` heading. The current shape is:
#
#   **Recommended next prompt:**
#
#   ```
#   /something
#   ```
#
#   > Optional one-line note.
#
# Rewrite policy: keep the `**Recommended next prompt:**` line, replace the
# fenced block (or the fallback paragraph) with the new value, drop any
# existing trailing `>` quote line (it's not regenerable without more state
# than reconcile carries). If we ever want to preserve operator-edited notes,
# that's a future enhancement.

declare -a NEW_LINES3=()
state=before
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$state" in
    before)
      NEW_LINES3+=("$line")
      if [[ "$line" == "**Recommended next prompt:**"* ]]; then
        state=in_block
        # Emit one blank line + the new block.
        NEW_LINES3+=("")
        if [[ -n "$REC_PROMPT" ]]; then
          NEW_LINES3+=('```')
          NEW_LINES3+=("$REC_PROMPT")
          NEW_LINES3+=('```')
        else
          NEW_LINES3+=("$REC_PROMPT_NOTE")
        fi
      fi
      ;;
    in_block)
      # Skip lines until the next `## ` heading; then resume passthrough.
      if [[ "$line" == "## "* ]]; then
        # Emit a blank line before the heading (consistent with current MC
        # spacing).
        NEW_LINES3+=("")
        NEW_LINES3+=("$line")
        state=after
      fi
      ;;
    after)
      NEW_LINES3+=("$line")
      ;;
  esac
done < "$MC_FILE"
{
  for line in "${NEW_LINES3[@]}"; do
    printf '%s\n' "$line"
  done
} > "$MC_FILE.tmp" && mv "$MC_FILE.tmp" "$MC_FILE"

# ── Phase 5: show diff, commit + push if non-empty ───────────────────────────

cd "$REPO_ROOT" || exit 1

DIFF_OUT="$(git diff -- MISSION-CONTROL.md)"
if [[ -z "$DIFF_OUT" ]]; then
  echo "reconcile-mc: MISSION-CONTROL.md already in sync."
  exit 0
fi

# Show the diff.
printf '%s\n' "$DIFF_OUT"

if (( DRY_RUN )); then
  echo "reconcile-mc: --dry-run set; skipping commit + push."
  exit 0
fi

# Compose the commit summary.
DATE_STR="$(date +%Y-%m-%d)"
if (( ROWS_ADVANCED == 0 )); then
  SUMMARY="banner + progress recompute"
elif (( ROWS_ADVANCED == 1 )); then
  SUMMARY="1 row shipped"
else
  SUMMARY="${ROWS_ADVANCED} rows shipped"
fi

git add MISSION-CONTROL.md
git commit -m "chore(mc): reconcile ${DATE_STR} — ${SUMMARY}" || {
  echo "reconcile-mc: git commit failed" >&2
  exit 1
}
git push || {
  echo "reconcile-mc: git push failed" >&2
  exit 1
}
exit 0
