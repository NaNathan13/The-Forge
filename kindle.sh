#!/usr/bin/env bash
# kindle.sh — bootstrap a new project on The Forge.
#
# Run this once after copying The Forge into a new project directory.
# It checks prerequisites, then launches Claude with the /kindle skill,
# which asks you ~10 questions and sets everything up.
#
# After /kindle completes, this file removes itself.

set -uo pipefail

# ─── pretty output helpers ─────────────────────────────────────────────────────

cyan()   { printf '\033[36m%s\033[0m\n' "$*"; }
green()  { printf '\033[32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[33m%s\033[0m\n' "$*"; }
red()    { printf '\033[31m%s\033[0m\n' "$*" >&2; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

# ─── banner ────────────────────────────────────────────────────────────────────

clear 2>/dev/null || true
cat <<'BANNER'

    ╔═══════════════════════════════════════════╗
    ║           \   /                           ║
    ║            \ /   *  *                     ║
    ║        ━━━━━█━━━━━  *                     ║
    ║       ┃░░░░░░░░░░░┃                       ║
    ║       ┃░░░░░░░░░░░┃                       ║
    ║      ━┻━━━━━━━━━━━┻━                      ║
    ║                                           ║
    ║         K I N D L E  T H E  F O R G E     ║
    ║       Strike while the iron is hot.       ║
    ╚═══════════════════════════════════════════╝

BANNER

echo "This script will:"
echo "  1. Check that the tools you need are installed"
echo "  2. Launch Claude with a Q&A that fills in your project files"
echo "  3. Create a GitHub repo for you (if you want)"
echo "  4. Get out of your way."
echo
echo "Three starting points are supported:"
echo "  • Fresh project   — scaffold from scratch"
echo "  • Existing code   — wrap The Forge around a directory or git URL you point at"
echo "  • Starter template — Claude suggests a real starter; you pick; it clones; /examine fills CLAUDE.md"
echo
read -r -p "Press Enter to begin (or Ctrl+C to cancel)..." _

# ─── prereq checks ─────────────────────────────────────────────────────────────

echo
bold "Checking prerequisites..."
echo

fail=0

check_cmd() {
  local cmd="$1" install_hint="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    green "  ✓ $cmd"
  else
    red   "  ✗ $cmd is not installed"
    echo  "      Install: $install_hint"
    fail=1
  fi
}

check_cmd claude "Visit https://claude.ai/code and follow the install instructions."
check_cmd gh     "Mac: brew install gh   |   Other: https://cli.github.com/"
check_cmd git    "Mac: brew install git  |   Other: https://git-scm.com/downloads"
check_cmd jq     "Mac: brew install jq   |   Other: https://stedolan.github.io/jq/download/"

if [[ "$fail" -eq 1 ]]; then
  echo
  red "Please install the missing tools above, then run ./kindle.sh again."
  exit 1
fi

# Check gh auth
if ! gh auth status >/dev/null 2>&1; then
  echo
  red "✗ GitHub CLI is installed but you're not signed in."
  echo "      Run this command in your terminal, then try again:"
  echo "         gh auth login"
  exit 1
fi
green "  ✓ GitHub CLI signed in as: $(gh api user --jq .login 2>/dev/null || echo 'unknown')"

# Check we're in a The Forge project directory
if [[ ! -f "CLAUDE.md" || ! -f "MISSION-CONTROL.md" || ! -d ".claude/skills" ]]; then
  echo
  red "✗ This doesn't look like a The Forge project directory."
  echo "      Expected to find CLAUDE.md, MISSION-CONTROL.md, and .claude/skills/ here."
  echo "      Run this first:"
  echo "         git clone https://github.com/NaNathan13/The-Forge.git my-project"
  echo "         cd my-project"
  echo "         ./kindle.sh"
  exit 1
fi
green "  ✓ The Forge files found in this directory"

# If we're inside The Forge's own git history (cloned, not copied), offer to wipe it
# so /kindle can git init a fresh repo for the user's project.
if [[ -d ".git" ]]; then
  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$remote_url" == *"NaNathan13/The-Forge"* ]]; then
    echo
    yellow "  ! This directory has The Forge's own git history (origin: $remote_url)."
    yellow "    Kindle needs to create a fresh git repo for your project."
    read -r -p "    Remove .git/ and start fresh? [Y/n] " answer
    case "$answer" in
      n|N|no|No|NO)
        red "✗ Aborted. Either remove .git/ yourself, or copy The Forge into a separate directory."
        exit 1
        ;;
      *)
        rm -rf .git
        green "  ✓ Removed The Forge's git history. Kindle will init a fresh repo."
        ;;
    esac
  elif git rev-parse HEAD >/dev/null 2>&1; then
    echo
    yellow "  ! This directory is already a git repo with commits (not The Forge's)."
    yellow "    Kindle will reuse the existing repo (existing-codebase / starter-template flow)."
    yellow "    /examine will detect the stack."
  fi
fi

# Mid-flow re-launch detection: if a previous /kindle run cloned a starter template
# or wrapped an existing codebase but Claude exited before finishing, the directory
# now has user code AND The Forge files. That's expected — just inform the user.
if [[ -f ".claude/.kindle-in-progress" ]]; then
  echo
  yellow "  ! A previous /kindle run was interrupted (marker: .claude/.kindle-in-progress)."
  yellow "    Re-launching Claude — pick up where you left off, or say 'start over'."
fi

# ─── launch claude ─────────────────────────────────────────────────────────────

echo
bold "All set. Launching Claude..."
echo
cyan "Tip: Claude will ask you questions one at a time. Pick the recommended"
cyan "     option if you're unsure — you can always change things later."
echo
sleep 1

# Hand off to Claude with /kindle as the opening prompt.
# `exec` replaces this shell so the user's terminal lands directly in Claude.
exec claude "/kindle"
