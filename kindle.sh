#!/usr/bin/env bash
# kindle.sh — light the forge fire on a new Blacksmith project.
#
# Run this once after copying Blacksmith into a new project directory.
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

    ██╗  ██╗██╗███╗   ██╗██████╗ ██╗     ███████╗
    ██║ ██╔╝██║████╗  ██║██╔══██╗██║     ██╔════╝
    █████╔╝ ██║██╔██╗ ██║██║  ██║██║     █████╗
    ██╔═██╗ ██║██║╚██╗██║██║  ██║██║     ██╔══╝
    ██║  ██╗██║██║ ╚████║██████╔╝███████╗███████╗
    ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚══════╝

         Bootstrap your project on Blacksmith.

BANNER

echo "This script will:"
echo "  1. Check that the tools you need are installed"
echo "  2. Launch Claude with a Q&A that fills in your project files"
echo "  3. Create a GitHub repo for you (if you want)"
echo "  4. Get out of your way."
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

# Check we're in a Blacksmith directory
if [[ ! -f "CLAUDE.md" || ! -f "MISSION-CONTROL.md" || ! -d ".claude/skills" ]]; then
  echo
  red "✗ This doesn't look like a Blacksmith directory."
  echo "      Expected to find CLAUDE.md, MISSION-CONTROL.md, and .claude/skills/ here."
  echo "      Did you copy Blacksmith into this folder first? See README.md."
  exit 1
fi
green "  ✓ Blacksmith files found in this directory"

# Check we're not already inside a git repo with commits (that we didn't make)
if [[ -d ".git" ]] && git rev-parse HEAD >/dev/null 2>&1; then
  echo
  yellow "  ! This directory is already a git repo with commits."
  yellow "    Kindle will skip 'git init' and try to use the existing repo."
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
