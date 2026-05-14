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
