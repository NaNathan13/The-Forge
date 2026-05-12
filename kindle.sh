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

    ██╗  ██╗██╗███╗   ██╗██████╗ ██╗     ███████╗
    ██║ ██╔╝██║████╗  ██║██╔══██╗██║     ██╔════╝
    █████╔╝ ██║██╔██╗ ██║██║  ██║██║     █████╗
    ██╔═██╗ ██║██║╚██╗██║██║  ██║██║     ██╔══╝
    ██║  ██╗██║██║ ╚████║██████╔╝███████╗███████╗
    ╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝╚═════╝ ╚══════╝╚══════╝

         Bootstrap your project on The Forge.

BANNER

echo "This script will:"
echo "  1. Ask which mode (Dev or Weenie Hut Junior)"
echo "  2. Check that the tools you need are installed"
echo "  3. Launch Claude with a Q&A that fills in your project files"
echo "  4. Create a GitHub repo for you (if you want)"
echo "  5. Get out of your way."
echo
read -r -p "Press Enter to begin (or Ctrl+C to cancel)..." _

# ─── mode picker ──────────────────────────────────────────────────────────────

echo
bold "Welcome to The Forge."
echo
echo "Quick question to set up the right experience for you:"
echo
echo "  [1]  Dev Mode"
echo "       You've written code before. You know what a Pull Request is."
echo "       You want the full keyboard-driven workflow with GitHub Issues,"
echo "       Projects, branches, and ~13 slash commands. Get out of my way."
echo
echo "  [2]  Weenie Hut Junior Mode  🍿"
echo "       You're an engineer who doesn't code daily, a PM, a marketer,"
echo "       or anyone who'd rather not look at a terminal. I'll grill you"
echo "       on what you're building, pick the stack for you, scaffold a"
echo "       real deployed app, and walk you through every feature as it ships."
echo "       You'll never touch GitHub. ~6 slash commands."
echo
read -r -p "Which mode?  [1/2] (default: 1) " mode_choice

case "$mode_choice" in
  2)
    mkdir -p .claude
    echo "whj" > .claude/mode.txt
    echo
    yellow "Weenie Hut Junior mode is not yet built."
    yellow "Re-run ./kindle.sh and pick Dev for now."
    exit 0
    ;;
  *)
    mkdir -p .claude
    echo "dev" > .claude/mode.txt
    ;;
esac

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
    yellow "    Kindle will skip 'git init' and try to use the existing repo."
  fi
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
