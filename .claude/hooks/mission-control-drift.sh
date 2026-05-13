#!/usr/bin/env bash
# SessionStart hook — detect drift between gh issue state and MISSION-CONTROL.md.
# Prints a one-line reminder if any issue marked `mc:open=` is actually CLOSED on GH.
# Silent otherwise. Always exits 0 so it never blocks session start.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MC_FILE="$REPO_ROOT/MISSION-CONTROL.md"

[[ -f "$MC_FILE" ]] || exit 0
command -v gh >/dev/null 2>&1 || exit 0

# Extract every issue number listed in any `mc:open=...` marker.
issues=$(grep -oE 'mc:open=[0-9,]+' "$MC_FILE" 2>/dev/null \
  | sed 's/mc:open=//' \
  | tr ',' '\n' \
  | sort -un)

[[ -z "$issues" ]] && exit 0

# Count how many of those tracked-as-open issues are actually CLOSED on GitHub.
drift=0
while IFS= read -r issue; do
  [[ -z "$issue" ]] && continue
  state=$(gh issue view "$issue" --json state -q .state 2>/dev/null || echo "UNKNOWN")
  [[ "$state" == "CLOSED" ]] && drift=$((drift + 1))
done <<< "$issues"

if [[ "$drift" -gt 0 ]]; then
  echo "📊 Mission Control: $drift closed issue(s) since last sync — run /seal to refresh."
fi

# --- /examine nudge ---
# Suggest /examine when .claude/rules/ exists but has no real rule files
# and the repo contains actual source code (not just Forge scaffolding).
RULES_DIR="$REPO_ROOT/.claude/rules"
if [[ -d "$RULES_DIR" ]]; then
  real_rules=$(find "$RULES_DIR" -name '*.md' ! -name 'README.md' 2>/dev/null | head -1)
  if [[ -z "$real_rules" ]]; then
    # Check for source code files (not in .claude/ or node_modules/)
    has_code=$(find "$REPO_ROOT" -maxdepth 3 \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
         -o -name '*.py' -o -name '*.rs' -o -name '*.go' -o -name '*.rb' \
         -o -name '*.java' -o -name '*.swift' -o -name '*.kt' \) \
      ! -path '*/.claude/*' ! -path '*/node_modules/*' \
      2>/dev/null | head -1)
    if [[ -n "$has_code" ]]; then
      echo "💡 Tip: Run /examine to auto-detect your stack and generate project-specific rules in .claude/rules/."
    fi
  fi
fi

exit 0
