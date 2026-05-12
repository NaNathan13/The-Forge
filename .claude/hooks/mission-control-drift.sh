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

exit 0
