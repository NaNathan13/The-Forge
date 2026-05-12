#!/usr/bin/env bash
# workflow-setup.sh — one-shot per-project setup for the Ponder → Forge → Temper pipeline.
# Idempotent: safe to re-run. Creates GitHub labels and verifies prerequisites.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"

# --- Pretty status helpers ----------------------------------------------------

ok()    { printf '\033[32m✓\033[0m %s\n' "$1"; }
note()  { printf '\033[34m·\033[0m %s\n' "$1"; }
warn()  { printf '\033[33m!\033[0m %s\n' "$1"; }

# --- 1. Verify gh CLI is auth'd -----------------------------------------------

if ! command -v gh >/dev/null 2>&1; then
    printf '\033[31m✗\033[0m gh CLI not found. Install with: brew install gh\n' >&2
    exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    printf '\033[31m✗\033[0m gh CLI not authenticated. Run: gh auth login\n' >&2
    exit 1
fi
ok "gh CLI authenticated"

# --- 2. Create labels (idempotent via --force) --------------------------------

create_label() {
    local name="$1" color="$2" desc="$3"
    if gh label create "$name" --color "$color" --description "$desc" --force >/dev/null 2>&1; then
        ok "label '$name' created/updated"
    else
        warn "could not create label '$name' — check repo permissions"
    fi
}

create_label "needs-triage"    "ededed" "Maintainer needs to evaluate"
create_label "needs-info"      "fef2c0" "Waiting on reporter for more information"
create_label "needs-human"     "d73a4a" "Temper got stuck; needs human attention"
create_label "ready-for-agent" "0e8a16" "Triaged and ready for temper"
create_label "ready-for-human" "1d76db" "Triaged but needs human implementation"
create_label "friction"        "FBCA04" "Temper hit unexpected friction during build"
create_label "slice:logic"     "c5def5" "Pure logic slice"
create_label "slice:ui"        "bfdadc" "UI-only slice"
create_label "slice:mixed"     "d4c5f9" "Mixed logic + UI slice"

# --- 3. Verify lessons.md exists ----------------------------------------------

if [ -f .claude/lessons.md ]; then
    ok ".claude/lessons.md exists"
else
    warn ".claude/lessons.md not found — temper workers expect this file"
fi

# --- 4. Verify kanban-move.sh is configured -----------------------------------

if grep -q "REPLACE_ME" .claude/scripts/kanban-move.sh 2>/dev/null; then
    warn ".claude/scripts/kanban-move.sh still has REPLACE_ME placeholders — fill in your Project IDs (see docs/dev/setup.md)"
else
    ok ".claude/scripts/kanban-move.sh is configured"
fi

# --- Done ---------------------------------------------------------------------

echo
echo "Setup complete. Run \`/ponder\` to plan, then \`/forge\` to build."
