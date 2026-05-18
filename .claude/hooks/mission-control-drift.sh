#!/usr/bin/env bash
# SessionStart hook — detect drift between gh issue state and MISSION-CONTROL.md.
# Flat-ledger shape: any `<!-- mc:open=N,N -->` marker whose listed issues are
# actually CLOSED on GH is drift (the row should have been removed by
# scripts/reconcile-mc.sh on the last /seal).
#
# Silent when no drift. Always exits 0 so it never blocks session start.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MC_FILE="$REPO_ROOT/MISSION-CONTROL.md"

[[ -f "$MC_FILE" ]] || exit 0

# ── Case (1): closed-issue drift ──────────────────────────────────────────
# Extract every issue number listed in any `mc:open=...` marker.
issues=$(grep -oE 'mc:open=[0-9,]+' "$MC_FILE" 2>/dev/null \
  | sed 's/mc:open=//' \
  | tr ',' '\n' \
  | sort -un)

# Count how many of those tracked-as-open issues are actually CLOSED on GitHub.
# Skipped silently when there are no open markers or when `gh` is unavailable.
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

# ── Case (2): in-flight row has no open PR referencing its issues ─────────
# For each row in the `## 🚧 In flight` table with an `mc:open=N,N` marker:
# fetch all open PRs once, and check that at least one open PR references one
# of the row's issues (via `feat/#N-` branch name or `closes #N` in the body).
# Skipped silently when gh is unavailable or there are no in-flight rows.

if command -v gh >/dev/null 2>&1; then
  open_prs_json=$(gh pr list --state open --json number,headRefName,body --limit 200 2>/dev/null || echo '[]')

  in_inflight=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "## "* ]]; then
      if [[ "$line" == "## 🚧 In flight"* ]]; then
        in_inflight=1
      else
        in_inflight=0
      fi
      continue
    fi
    (( in_inflight )) || continue
    # Row of interest: starts with `|` AND carries an mc:open marker.
    [[ "$line" == \|* ]] || continue
    [[ "$line" == *"<!-- mc:open="* ]] || continue
    open_issues="${line#*<!-- mc:open=}"
    open_issues="${open_issues%% -->*}"
    [[ -z "$open_issues" ]] && continue

    # Extract the `#` cell — first cell after the leading `|`.
    row_id="$(printf '%s' "$line" | awk -F'|' '{ s = $2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); print s }')"

    referenced=0
    IFS=',' read -ra issue_list <<< "$open_issues"
    for n in "${issue_list[@]}"; do
      n="${n// /}"
      [[ -z "$n" ]] && continue
      if printf '%s' "$open_prs_json" \
        | grep -qE "(feat/#${n}-|[Cc]loses #${n}([^0-9]|$))"; then
        referenced=1
        break
      fi
    done
    if [[ "$referenced" -eq 0 ]]; then
      echo "[mc-drift] in-flight row '${row_id}' has no open PR referencing issues ${open_issues}"
    fi
  done < "$MC_FILE"
fi

# ── Case (3): Recommended next prompt names a non-existent skill ──────────
# Skipped — the flat-ledger recommended prompt is `/seal`, `/forge`,
# `/temper`, or `/ponder`. We do not introspect; reconcile-mc.sh is
# authoritative for what gets written.

# ── /examine nudge ─────────────────────────────────────────────────────────
# Suggest /examine when .claude/rules/ exists but has no real rule files
# and the repo contains actual source code (not just Forge scaffolding).
RULES_DIR="$REPO_ROOT/.claude/rules"
if [[ -d "$RULES_DIR" ]]; then
  real_rules=$(find "$RULES_DIR" -name '*.md' ! -name 'README.md' 2>/dev/null | head -1)
  if [[ -z "$real_rules" ]]; then
    # Check for source code files (not in .claude/ or node_modules/).
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
