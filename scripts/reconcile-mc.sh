#!/usr/bin/env bash
set -uo pipefail

# reconcile-mc.sh — full MISSION-CONTROL.md close-out (reconcile + commit + push).
#
# Sole writer of MC. Invoked by:
#
#   1. `/seal` at close-out time.
#   2. Operators on demand — for out-of-band merges, human-closed issues, or
#      anywhere MC has drifted from GitHub state without a /seal run.
#
# ── What it does ─────────────────────────────────────────────────────────────
# Reads `MISSION-CONTROL.md` (flat-ledger shape) and:
#
#   1. Walks each tracked state-bucket table (`## 🚧 In flight`,
#      `## ⏳ Queued`, `## ⏸ Deferred`).
#   2. For every row with an `<!-- mc:open=N,N -->` marker: queries
#      `gh issue view N --json state -q .state` for each issue. If the FULL
#      mc:open set is CLOSED on GitHub, the row is "shipped" — and shipped
#      work disappears from the flat-ledger MC (git log carries history).
#      The row is removed from the table entirely.
#   3. Recomputes the "Recommended next prompt" using the simple priority
#      order: open PRs → /seal; otherwise open ready-for-agent issues with a
#      slice:* label → /forge-overseer; otherwise → "All caught up" note.
#   4. Shows `git diff MISSION-CONTROL.md` on stdout.
#   5. If the diff is non-empty: `git add MISSION-CONTROL.md` + commit + push.
#      Commit message: `chore(mc): reconcile YYYY-MM-DD — <summary>`.
#
# ── MC schema (flat-ledger) ─────────────────────────────────────────────────
# Each state-bucket table has its own column header. The reconciler treats any
# row carrying `<!-- mc:open=N,N -->` uniformly — the bucket-specific column
# shape is preserved by removing the row in place rather than rewriting cells.
#
# In-flight table:    `| # | Title | Status |`
# Queued table:       `| # | Title |`
# Deferred table:     `| # | Title | Why deferred |`
#
# Tables under `## 📡 ADRs` and `## 🌑 Out of scope` use different shapes (a
# bullet list and a free-form list respectively) and are NOT touched.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 — success (whether or not a commit was produced)
#   1 — runtime error (gh failure, malformed MC, etc.)
#   2 — usage error (bad arg)
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   scripts/reconcile-mc.sh              # reconcile this repo's MC, commit + push
#   scripts/reconcile-mc.sh --dry-run    # show diff; do not commit/push

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MC_FILE="$REPO_ROOT/MISSION-CONTROL.md"

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      sed -n '3,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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

# Snapshot the original so --dry-run can restore the working tree cleanly,
# regardless of what git's index currently holds.
MC_BACKUP="$(mktemp)"
cp "$MC_FILE" "$MC_BACKUP"
# shellcheck disable=SC2064
trap "rm -f '$MC_BACKUP'" EXIT

# ── Phase 1: identify shipped-now rows and remove them ───────────────────────
# Read MC line-by-line. For each line carrying `<!-- mc:open=N,N -->`, extract
# the issue list. Query each issue's state. If ALL are CLOSED, drop the line.

declare -a MC_LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
  MC_LINES+=("$line")
done < "$MC_FILE"

# Cache issue states across rows. Parallel arrays for macOS bash 3.2.
ISSUE_CACHE_KEYS=()
ISSUE_CACHE_VALS=()

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

_cache_set() {
  ISSUE_CACHE_KEYS+=("$1")
  ISSUE_CACHE_VALS+=("$2")
}

# is_issue_closed <N> — exits 0 if closed, 1 otherwise. Caches the result.
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

# all_closed <comma-separated-N-list> — returns 0 iff every listed issue CLOSED.
all_closed() {
  local list="$1" n
  IFS=',' read -ra arr <<< "$list"
  for n in "${arr[@]}"; do
    n="${n// /}"
    [[ -z "$n" ]] && continue
    is_issue_closed "$n" || return 1
  done
  return 0
}

# strip_backticks <line> → echoes the line with every `...` span removed.
# Single-line backtick spans wrap example markers in the Legend; those are
# documentation, not real markers.
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

# Mark rows for removal. To preserve markdown spacing we drop each shipped row
# without re-flowing the table — the table separator and header stay where
# they were; only the data row vanishes.
#
# Real markers live on table rows (lines beginning with `|`). Anything that
# matches `<!-- mc:open=... -->` outside a table row, or inside a backtick
# span, or inside a multi-line `<!-- ... -->` comment block, is documentation
# and is left alone.
declare -a KEEP_FLAGS=()
ROWS_REMOVED=0
in_comment_block=0
for i in "${!MC_LINES[@]}"; do
  KEEP_FLAGS[$i]=1
  line="${MC_LINES[$i]}"

  # Track multi-line HTML comment blocks (stand-alone `<!--` / `-->` lines).
  trimmed="${line#"${line%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  if (( in_comment_block )); then
    [[ "$trimmed" == "-->" ]] && in_comment_block=0
    continue
  fi
  if [[ "$trimmed" == "<!--" ]]; then
    in_comment_block=1
    continue
  fi

  # Only consider table rows.
  [[ "$line" == \|* ]] || continue

  # Strip backtick spans (Legend example markers are wrapped).
  stripped="$(strip_backticks "$line")"
  [[ "$stripped" == *"<!-- mc:open="* ]] || continue
  ids="${stripped#*<!-- mc:open=}"
  ids="${ids%% -->*}"
  if all_closed "$ids"; then
    KEEP_FLAGS[$i]=0
    ROWS_REMOVED=$((ROWS_REMOVED + 1))
  fi
done

# Write the kept lines back to disk.
{
  for i in "${!MC_LINES[@]}"; do
    if [[ "${KEEP_FLAGS[$i]}" == "1" ]]; then
      printf '%s\n' "${MC_LINES[$i]}"
    fi
  done
} > "$MC_FILE.tmp" && mv "$MC_FILE.tmp" "$MC_FILE"

# ── Phase 2: recompute Recommended next prompt ───────────────────────────────
# Priority order:
#   1. Open feat/#*-* PRs                              → `/seal`
#   2. Any open ready-for-agent + slice:* issue        → `/forge-overseer`
#   3. Otherwise                                       → "All caught up" note

REC_PROMPT=""

open_prs="$(gh pr list --state open --json headRefName --jq '.[] | select(.headRefName | test("^feat/#[0-9]+-")) | .headRefName' 2>/dev/null || true)"
if [[ -n "$open_prs" ]]; then
  REC_PROMPT="/seal"
fi

if [[ -z "$REC_PROMPT" ]]; then
  ready_count="$(gh issue list --state open --label ready-for-agent --json labels --jq '[.[] | select(.labels | map(.name) | any(. | startswith("slice:")))] | length' 2>/dev/null || echo 0)"
  if [[ -n "$ready_count" && "$ready_count" != "0" && "$ready_count" != "null" ]]; then
    REC_PROMPT="/forge-overseer"
  fi
fi

REC_PROMPT_NOTE=""
if [[ -z "$REC_PROMPT" ]]; then
  REC_PROMPT_NOTE="_All caught up — no open PRs, no triaged work in the queue._"
fi

# Splice the new recommendation into MC's `**Recommended next prompt:**`
# block — between the literal `**Recommended next prompt:**` line and the next
# `## ` heading. Shape:
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
# existing trailing `>` quote line (it is not regenerable without more state
# than reconcile carries).

declare -a NEW_LINES=()
state=before
while IFS= read -r line || [[ -n "$line" ]]; do
  case "$state" in
    before)
      NEW_LINES+=("$line")
      if [[ "$line" == "**Recommended next prompt:**"* ]]; then
        state=in_block
        NEW_LINES+=("")
        if [[ -n "$REC_PROMPT" ]]; then
          NEW_LINES+=('```')
          NEW_LINES+=("$REC_PROMPT")
          NEW_LINES+=('```')
        else
          NEW_LINES+=("$REC_PROMPT_NOTE")
        fi
      fi
      ;;
    in_block)
      if [[ "$line" == "## "* ]]; then
        NEW_LINES+=("")
        NEW_LINES+=("$line")
        state=after
      fi
      ;;
    after)
      NEW_LINES+=("$line")
      ;;
  esac
done < "$MC_FILE"
{
  for line in "${NEW_LINES[@]}"; do
    printf '%s\n' "$line"
  done
} > "$MC_FILE.tmp" && mv "$MC_FILE.tmp" "$MC_FILE"

# ── Phase 3: show diff, commit + push if non-empty ───────────────────────────

cd "$REPO_ROOT" || exit 1

DIFF_OUT="$(git diff -- MISSION-CONTROL.md)"
if [[ -z "$DIFF_OUT" ]]; then
  echo "reconcile-mc: MISSION-CONTROL.md already in sync."
  exit 0
fi

printf '%s\n' "$DIFF_OUT"

if (( DRY_RUN )); then
  echo "reconcile-mc: --dry-run set; skipping commit + push."
  # Restore the unmodified MC so a dry-run leaves the working tree clean.
  cp "$MC_BACKUP" "$MC_FILE"
  exit 0
fi

DATE_STR="$(date +%Y-%m-%d)"
if (( ROWS_REMOVED == 0 )); then
  SUMMARY="recommended-prompt recompute"
elif (( ROWS_REMOVED == 1 )); then
  SUMMARY="1 row shipped"
else
  SUMMARY="${ROWS_REMOVED} rows shipped"
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
