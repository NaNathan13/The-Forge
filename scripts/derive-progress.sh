#!/usr/bin/env bash
set -uo pipefail

# derive-progress.sh — compute phase progress bars from MISSION-CONTROL.md rows.
#
# Read-only by design. The sole writer for MC is `scripts/reconcile-mc.sh`
# (sub-phase 3f / issue #238). This script is consumed by:
#
#   1. `.claude/hooks/mission-control-drift.sh` — surfaces drift between the
#      derived bars and the bars currently in MC at SessionStart.
#   2. `scripts/reconcile-mc.sh` — rewrites the MC phase headers with the
#      derived output.
#   3. Operators directly — `bash scripts/derive-progress.sh` prints the
#      canonical bars; a non-zero exit means "MC is out of sync, run /seal
#      or scripts/reconcile-mc.sh".
#
# ── What it does ─────────────────────────────────────────────────────────────
# For each `### <phase header>` in MISSION-CONTROL.md, parse the markdown table
# that follows it under the `## 🪐 Phase progress` section. Count:
#
#   N = data rows whose Status cell starts with `✅ shipped`
#   M = total data rows in the table (including ⏳ stub rows — the bar shows
#       progress against the *full known scope* per PRD §Slice 2)
#
# Print one line per phase, format:
#
#   ### P0 Foundations ▓▓▓ 3/3
#
# i.e. the phase header keyword/name, then N copies of `▓`, then (M-N) copies
# of `░`, then `N/M`.
#
# ── MC schema this expects ───────────────────────────────────────────────────
# This script targets the *new* 6-column schema introduced by issue #236 /
# PR #241: `# | Sub-phase | Status | Blocked by | PRD | Issues`. Status is
# column 3 (0-indexed 2). Tables under `## 🛸 Architectural items` (header
# `| # | Item | ...`) are NOT sub-phase tables and are skipped.
#
# Sub-phase tables live under `## 🪐 Phase progress` and only under that
# section. The script identifies them by header signature `| # | Sub-phase |`.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — every printed bar matches the bar currently in MC's phase header
#   1 — at least one bar disagrees with MC (drift); per-phase diagnostic on
#       stderr, derived bars still printed to stdout so callers can consume them
#   2 — runtime/usage error (MC not found, malformed table, bad arg)
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   scripts/derive-progress.sh                # validate this repo
#   scripts/derive-progress.sh /path/to/repo  # validate a different repo root
#
# The script is read-only — it never writes to MC, regardless of exit code.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ROOT=""
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '3,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "derive-progress.sh: unknown option: $arg" >&2
      exit 2
      ;;
    *)
      if [[ -n "$ROOT" ]]; then
        echo "derive-progress.sh: unexpected extra positional arg: $arg" >&2
        exit 2
      fi
      ROOT="$arg"
      ;;
  esac
done
ROOT="${ROOT:-$DEFAULT_ROOT}"

if [[ ! -d "$ROOT" ]]; then
  echo "derive-progress.sh: root not found or not a directory: $ROOT" >&2
  exit 2
fi

MC_FILE="$ROOT/MISSION-CONTROL.md"
if [[ ! -f "$MC_FILE" ]]; then
  echo "derive-progress.sh: MISSION-CONTROL.md not found at $MC_FILE" >&2
  exit 2
fi

# ── Parse phase headers + tables ─────────────────────────────────────────────
# State machine over the file:
#
#   in_phase_progress = 1 once we cross `## 🪐 Phase progress`, 0 once we cross
#       the next `## ` heading (Architectural items, ADRs, etc.).
#
#   current_phase     = the `### <name>` text currently being accumulated, with
#       the trailing ` <bar> N/M` stripped off so we can re-emit canonical form.
#
#   current_phase_raw = the raw header line as it appears in MC, so we can
#       compare canonical vs. raw for drift detection.
#
#   counting_table    = 1 once we've seen the sub-phase table header for the
#       current phase, 0 before or after.
#
#   n, m              = shipped + total counters for the current phase.
#
# When we hit the next `### ` (or leave the section), we emit the previous
# phase's canonical line.

FAIL_COUNT=0
declare -a OUTPUT_LINES=()

in_phase_progress=0
current_phase=""        # phase name w/o the trailing bar (e.g. "P0 Foundations")
current_phase_raw=""    # the raw `### ...` line as-is in MC
counting_table=0
saw_table_header=0
n=0
m=0

# strip_trailing_bar <header-text-after-###>
# Strips a trailing ` ▓...░... N/M` (or any combination of ▓/░ + N/M) from the
# header label, leaving the bare phase name.
strip_trailing_bar() {
  local s="$1"
  # Pattern: optional bar (▓ or ░ chars), optional space, N/M (M may be `?`
  # for a stub-only phase like the original P4 row, which is the only place
  # the `?` form appears — once derive runs over a real-rowed phase, M is
  # always numeric). Anchor at end of line. The ▓/░ glyphs are multibyte
  # UTF-8 but `sed -E` handles them fine as byte runs.
  printf '%s' "$s" | sed -E 's/[[:space:]]+[▓░]*[[:space:]]*[0-9]+\/([0-9]+|\?)[[:space:]]*$//'
}

# emit_phase
# Emit the canonical line for the current phase and compare it to current_phase_raw.
emit_phase() {
  [[ -z "$current_phase" ]] && return 0

  # Build the bar.
  local bar="" i
  for ((i = 0; i < n; i++)); do bar+="▓"; done
  for ((i = 0; i < m - n; i++)); do bar+="░"; done
  # Edge case: empty table (M=0). Emit no bar glyphs — just `0/0`. Drift
  # comparison still works since the raw line is canonicalised the same way.
  local canonical
  if (( m == 0 )); then
    canonical="### ${current_phase} 0/0"
  else
    canonical="### ${current_phase} ${bar} ${n}/${m}"
  fi
  OUTPUT_LINES+=("$canonical")

  # Drift check — compare canonical against the raw header line in MC,
  # normalising whitespace.
  local raw_norm canon_norm
  raw_norm="$(printf '%s' "$current_phase_raw" | tr -s '[:space:]' ' ' | sed 's/[[:space:]]*$//')"
  canon_norm="$(printf '%s' "$canonical" | tr -s '[:space:]' ' ' | sed 's/[[:space:]]*$//')"
  if [[ "$raw_norm" != "$canon_norm" ]]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "derive-progress: drift in '${current_phase}': MC says '${raw_norm}', derived '${canon_norm}'" >&2
  fi
}

# reset_phase
# Clear per-phase accumulators.
reset_phase() {
  current_phase=""
  current_phase_raw=""
  counting_table=0
  saw_table_header=0
  n=0
  m=0
}

while IFS= read -r line || [[ -n "$line" ]]; do
  # Section boundaries: `## ` headers toggle in_phase_progress.
  if [[ "$line" == "## "* ]]; then
    # Emit pending phase before switching sections.
    if (( in_phase_progress )); then
      emit_phase
      reset_phase
    fi
    if [[ "$line" == "## 🪐 Phase progress"* ]]; then
      in_phase_progress=1
    else
      in_phase_progress=0
    fi
    continue
  fi

  (( in_phase_progress )) || continue

  # Phase header line.
  if [[ "$line" == "### "* ]]; then
    # Emit previous phase before starting a new one.
    emit_phase
    reset_phase
    current_phase_raw="$line"
    # Strip leading "### " and the trailing bar/fraction. The substring uses
    # `${line#"### "}` (quoted pattern) so the literal `### ` prefix is
    # removed; unquoted `${line#### }` is parsed as `# # #` which fails.
    label_text="${line#"### "}"
    current_phase="$(strip_trailing_bar "$label_text")"
    continue
  fi

  # Inside a phase. Look for sub-phase table.
  # The header row is `| # | Sub-phase | ...`. The next line is the separator
  # `| --- | --- | ...`. After that, every `|`-leading line until a blank
  # line or non-`|` line is a data row.
  if [[ -z "$current_phase" ]]; then
    continue
  fi

  # Detect sub-phase table header. We accept either the old schema or the
  # new schema by checking the first two cells are `#` and `Sub-phase`.
  if [[ "$line" == "| # | Sub-phase "* ]]; then
    counting_table=1
    saw_table_header=1
    continue
  fi

  # Skip the separator row.
  if (( counting_table )) && [[ "$line" =~ ^\|[[:space:]]*-+[[:space:]]*\| ]]; then
    continue
  fi

  # Data row inside the active sub-phase table.
  if (( counting_table )) && [[ "$line" == "|"* ]]; then
    # Split on `|`; expected cells: empty, #, Sub-phase, Status, ... (new
    # schema has Blocked-by next then PRD then Issues; old schema has PRD
    # then Issues). Status is always the 3rd content cell (index 3 after the
    # leading empty cell from the leading `|`).
    IFS='|' read -ra cells <<< "$line"
    # cells[0] is empty (text before leading `|`).
    # cells[1]=#, cells[2]=Sub-phase, cells[3]=Status, ...
    if (( ${#cells[@]} >= 4 )); then
      status="${cells[3]}"
      # Trim whitespace.
      status="${status#"${status%%[![:space:]]*}"}"
      status="${status%"${status##*[![:space:]]}"}"
      m=$((m + 1))
      # Shipped ↔ status starts with the ✅ glyph (covers `✅ shipped` and any
      # equivalent suffix form). Use a prefix match on the glyph to stay
      # robust against status-line wording tweaks.
      if [[ "$status" == "✅"* ]]; then
        n=$((n + 1))
      fi
    fi
    continue
  fi

  # Any non-`|`-leading non-blank line ends the current table (but we keep
  # the phase open in case there's more text before another `### ` arrives).
  if (( counting_table )) && [[ -n "$line" && "$line" != "|"* ]]; then
    counting_table=0
  fi
done < "$MC_FILE"

# Emit the final phase (the loop's `## ` / `### ` triggers don't fire on EOF).
if (( in_phase_progress )); then
  emit_phase
fi

# Print all derived lines to stdout (one per phase).
for out_line in "${OUTPUT_LINES[@]}"; do
  printf '%s\n' "$out_line"
done

if (( FAIL_COUNT > 0 )); then
  exit 1
fi
exit 0
