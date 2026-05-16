#!/usr/bin/env bash
# SessionStart hook — detect drift between gh issue state and MISSION-CONTROL.md.
# Prints a one-line reminder if any issue marked `mc:open=` is actually CLOSED on GH.
# Silent otherwise. Always exits 0 so it never blocks session start.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MC_FILE="$REPO_ROOT/MISSION-CONTROL.md"

[[ -f "$MC_FILE" ]] || exit 0

# Extract every issue number listed in any `mc:open=...` marker.
issues=$(grep -oE 'mc:open=[0-9,]+' "$MC_FILE" 2>/dev/null \
  | sed 's/mc:open=//' \
  | tr ',' '\n' \
  | sort -un)

# Count how many of those tracked-as-open issues are actually CLOSED on GitHub.
# Skipped silently when there are no open markers or when `gh` is unavailable
# — the progress-bar check below runs regardless.
drift=0
if [[ -n "$issues" ]] && command -v gh >/dev/null 2>&1; then
  while IFS= read -r issue; do
    [[ -z "$issue" ]] && continue
    state=$(gh issue view "$issue" --json state -q .state 2>/dev/null || echo "UNKNOWN")
    [[ "$state" == "CLOSED" ]] && drift=$((drift + 1))
  done <<< "$issues"
fi

if [[ "$drift" -gt 0 ]]; then
  echo "📊 Mission Control: $drift closed issue(s) since last sync — run /seal to refresh."
fi

# --- Phase progress-bar drift (issue #237) ---
# Compare phase progress bars in MISSION-CONTROL.md to derive-progress.sh's
# canonical output. The script exits non-zero on drift; we surface its stderr
# diagnostic lines verbatim. Hook never writes — the fix path is /seal (which
# invokes scripts/reconcile-mc.sh as the sole writer).
DERIVE_SCRIPT="$REPO_ROOT/scripts/derive-progress.sh"
if [[ -x "$DERIVE_SCRIPT" ]]; then
  derive_stderr="$("$DERIVE_SCRIPT" 2>&1 >/dev/null)"
  derive_rc=$?
  if [[ "$derive_rc" -ne 0 && -n "$derive_stderr" ]]; then
    # Print each diagnostic line with a leading marker so the session banner
    # groups it visually with the other MC drift signals.
    while IFS= read -r diag; do
      [[ -z "$diag" ]] && continue
      echo "📊 Mission Control: $diag"
    done <<< "$derive_stderr"
  fi
fi

# --- Widened drift cases (issue #239) ---
# Three additional checks against MISSION-CONTROL.md's sub-phase rows. Each
# emits a one-line `[mc-drift] ...` message when drift is detected. The hook
# never writes — the fix path stays /seal + scripts/reconcile-mc.sh.
#
# Row schema (post-#236, 6 columns):
#   | <id> | <name> | <status> | <blocked by> | <PRD> | <issues> |
#
# We grep sub-phase rows by pattern `^| <id> | ... |` where <id> matches a
# short phase identifier like `0a`, `3f`, `4a`. Header rows (`| # | ...`) and
# separator rows (`| --- | ...`) are excluded by the id-shape check.

mc_drift_rows() {
  # Print every sub-phase data row from MC. One row per line, verbatim.
  grep -E '^\| [0-9]+[a-z]+ \| ' "$MC_FILE" 2>/dev/null
}

mc_row_field() {
  # Args: <row> <1-based field index into the markdown table>
  # Splits on `|`, trims surrounding whitespace, returns the requested field.
  local row="$1" idx="$2"
  printf '%s\n' "$row" | awk -F'|' -v n="$idx" '{
    f = $((n + 1))                    # first pipe makes $1 empty
    gsub(/^[ \t]+|[ \t]+$/, "", f)
    print f
  }'
}

mc_row_id()      { mc_row_field "$1" 1; }
mc_row_status()  { mc_row_field "$1" 3; }
mc_row_issues()  { mc_row_field "$1" 6; }

mc_row_open_issues() {
  # Echo the comma-separated list of issue numbers from the row's
  # `<!-- mc:open=N,N -->` marker, or empty if no such marker.
  local row="$1"
  printf '%s\n' "$row" \
    | grep -oE 'mc:open=[0-9,]+' \
    | head -1 \
    | sed 's/mc:open=//'
}

# Case (a) — 🚧 in-progress sub-phase with no open PR referencing its issues.
#
# For each in-progress row, parse mc:open=N,N. Get all open PRs from gh once.
# A PR "references" issue N if either its branch name matches `feat/#N-` or
# its body contains `closes #N` / `Closes #N` (case-insensitive). If no open
# PR references any issue in the row → drift.
#
# Skipped silently when gh is unavailable or there are no in-progress rows.
if command -v gh >/dev/null 2>&1; then
  open_prs_json=$(gh pr list --state open --json number,headRefName,body --limit 200 2>/dev/null || echo '[]')
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    status=$(mc_row_status "$row")
    [[ "$status" == *"🚧 in-progress"* ]] || continue
    open_issues=$(mc_row_open_issues "$row")
    [[ -z "$open_issues" ]] && continue
    id=$(mc_row_id "$row")
    referenced=0
    IFS=',' read -ra issue_list <<< "$open_issues"
    for n in "${issue_list[@]}"; do
      [[ -z "$n" ]] && continue
      # Match branches like `feat/#N-...` or bodies containing `closes #N`
      # (whole-word so #12 doesn't match #123).
      if printf '%s' "$open_prs_json" \
        | grep -qE "(feat/#${n}-|[Cc]loses #${n}([^0-9]|$))"; then
        referenced=1
        break
      fi
    done
    if [[ "$referenced" -eq 0 ]]; then
      echo "[mc-drift] sub-phase ${id} is 🚧 in-progress but no open PR references issues ${open_issues}"
    fi
  done < <(mc_drift_rows)
fi

# Case (b) — Recommended next prompt names a ✅ shipped sub-phase.
#
# Find the fenced code block immediately following "Recommended next prompt".
# Extract phase IDs (short `[0-9]+[a-z]+` tokens, e.g. `3f`, `0a`). For each,
# look up the row; if status is ✅ shipped → drift.
rec_block=$(awk '
  /Recommended next prompt/ { looking = 1; next }
  looking && /^```/ {
    if (in_block) { exit }
    in_block = 1; next
  }
  in_block { print }
' "$MC_FILE" 2>/dev/null)

if [[ -n "$rec_block" ]]; then
  rec_ids=$(printf '%s\n' "$rec_block" \
    | grep -oE '[0-9]+[a-z]+' \
    | sort -u)
  while IFS= read -r rid; do
    [[ -z "$rid" ]] && continue
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      [[ "$(mc_row_id "$row")" == "$rid" ]] || continue
      status=$(mc_row_status "$row")
      if [[ "$status" == *"✅ shipped"* ]]; then
        echo "[mc-drift] Recommended next prompt names ${rid} but that sub-phase is ✅ shipped"
      fi
    done < <(mc_drift_rows)
  done <<< "$rec_ids"
fi

# Case (d) — ⏳ queued stub row has issues filed.
#
# For each `⏳ queued` row, if the Issues column carries `mc:open=N,N` (i.e.
# issues have been filed against a row whose status still claims the slice
# is queued), surface drift — should be 🚧 in-progress.
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  status=$(mc_row_status "$row")
  [[ "$status" == *"⏳ queued"* ]] || continue
  open_issues=$(mc_row_open_issues "$row")
  [[ -z "$open_issues" ]] && continue
  id=$(mc_row_id "$row")
  echo "[mc-drift] sub-phase ${id} is ⏳ queued but has open issues ${open_issues}; should be 🚧 in-progress"
done < <(mc_drift_rows)

# --- /examine nudge ---
# Suggest /examine when .claude/rules/ exists but has no real rule files
# and the repo contains actual source code (not just Forge scaffolding).
RULES_DIR="$REPO_ROOT/.claude/rules"
if [[ -d "$RULES_DIR" ]]; then
  real_rules=$(find "$RULES_DIR" -name '*.md' ! -name 'README.md' 2>/dev/null | head -1)
  if [[ -z "$real_rules" ]]; then
    # Check for source code files (not in .claude/ or node_modules/).
    # Extension list covers the major mainstream stacks. When adding a language,
    # extend this list rather than inverting to a deny-list — explicit is cheaper
    # to reason about and avoids false positives from build artifacts.
    has_code=$(find "$REPO_ROOT" -maxdepth 3 \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
         -o -name '*.mjs' -o -name '*.cjs' \
         -o -name '*.py' -o -name '*.rs' -o -name '*.go' -o -name '*.rb' \
         -o -name '*.java' -o -name '*.swift' -o -name '*.kt' -o -name '*.kts' \
         -o -name '*.scala' -o -name '*.clj' -o -name '*.cljs' \
         -o -name '*.c' -o -name '*.h' \
         -o -name '*.cpp' -o -name '*.cc' -o -name '*.cxx' \
         -o -name '*.hpp' -o -name '*.hh' -o -name '*.hxx' \
         -o -name '*.m' -o -name '*.mm' \
         -o -name '*.cs' -o -name '*.fs' -o -name '*.fsx' \
         -o -name '*.ex' -o -name '*.exs' -o -name '*.erl' -o -name '*.hrl' \
         -o -name '*.php' -o -name '*.zig' -o -name '*.lua' \
         -o -name '*.dart' -o -name '*.hs' -o -name '*.ml' -o -name '*.mli' \
         -o -name '*.nim' -o -name '*.cr' -o -name '*.jl' \
         -o -name '*.pl' -o -name '*.pm' -o -name '*.r' -o -name '*.R' \
         -o -name '*.sh' -o -name '*.bash' -o -name '*.zsh' -o -name '*.fish' \
         -o -name '*.vue' -o -name '*.svelte' -o -name '*.astro' \) \
      ! -path '*/.claude/*' ! -path '*/node_modules/*' \
      ! -path '*/.git/*' ! -path '*/dist/*' ! -path '*/build/*' \
      ! -path '*/target/*' ! -path '*/.venv/*' ! -path '*/venv/*' \
      2>/dev/null | head -1)
    if [[ -n "$has_code" ]]; then
      echo "💡 Tip: Run /examine to auto-detect your stack and generate project-specific rules in .claude/rules/."
    fi
  fi
fi

exit 0
