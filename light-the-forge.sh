#!/usr/bin/env bash
# light-the-forge.sh — single-command bootstrap for The Forge.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
#
# Or, if you already cloned The Forge:
#   ./light-the-forge.sh
#
# Checks prerequisites, copies kit files (if run via curl), then launches
# Claude with the /kindle skill for interactive Q&A.

set -uo pipefail

REPO_URL="https://github.com/NaNathan13/The-Forge.git"
TARGET="$(pwd)"

# ─── color helpers (only when stdout is a terminal) ───────────────────────────

if [[ -t 1 ]]; then
  F=$'\033[38;5;208m' B=$'\033[38;5;75m' G=$'\033[38;5;78m'
  Y=$'\033[38;5;178m' R=$'\033[38;5;203m' D=$'\033[38;5;240m' N=$'\033[0m'
  BOLD=$'\033[1m' GREEN=$'\033[32m' YELLOW=$'\033[33m' RED=$'\033[31m'
else
  F='' B='' G='' Y='' R='' D='' N='' BOLD='' GREEN='' YELLOW='' RED=''
fi

cyan()   { printf '%s%s%s\n' "$B" "$*" "$N"; }
green()  { printf '%s%s%s\n' "$GREEN" "$*" "$N"; }
yellow() { printf '%s%s%s\n' "$YELLOW" "$*" "$N" >&2; }
red()    { printf '%s%s%s\n' "$RED" "$*" "$N" >&2; }
bold()   { printf '%s%s%s\n' "$BOLD" "$*" "$N"; }

# ─── banner ───────────────────────────────────────────────────────────────────

clear 2>/dev/null || true
printf '%s\n' "" \
  "${F}    _____ _            _____                    ${N}" \
  "${F}   |_   _| |__   ___  |  ___|__  _ __ __ _  ___ ${N}" \
  "${F}     | | | '_ \\ / _ \\ | |_ / _ \\| '__/ _\` |/ _ \\${N}" \
  "${F}     | | | | | |  __/ |  _| (_) | | | (_| |  __/${N}" \
  "${F}     |_| |_| |_|\\___| |_|  \\___/|_|  \\__, |\\___| ${N}" \
  "${F}                                      |___/      ${N}" \
  "" \
  "  ${D}──────────────────────────────────────────────────${N}" \
  "  💭 ${G}ponder${N}  →  🔥 ${Y}forge${N}  →  🧊 ${B}temper${N}  →  🗡️  ${R}seal${N}" \
  "  ${D}──────────────────────────────────────────────────${N}" \
  ""

echo "This script will:"
echo "  1. Ask which mode (Dev or Weenie Hut Junior)"
echo "  2. Check that the tools you need are installed"
echo "  3. Launch Claude with a Q&A that fills in your project files"
echo "  4. Create a GitHub repo for you (if you want)"
echo "  5. Get out of your way."
echo
echo "Three starting points are supported:"
echo "  • Fresh project   — scaffold from scratch"
echo "  • Existing code   — wrap The Forge around a directory or git URL you point at"
echo "  • Starter template — Claude suggests a real starter; you pick; it clones; /examine fills CLAUDE.md"
echo
read -r -p "Press Enter to begin (or Ctrl+C to cancel)..." _

# ─── detect mode: curl-pipe-bash vs already cloned ───────────────────────────

ALREADY_CLONED=false
if [[ -f "$TARGET/CLAUDE.md" && -d "$TARGET/.claude/skills" ]]; then
  ALREADY_CLONED=true
fi

# ─── if curl-pipe-bash: clone to temp and copy kit files ─────────────────────

if [[ "$ALREADY_CLONED" == "false" ]]; then
  echo
  bold "Fetching The Forge..."
  TMPDIR="$(mktemp -d -t the-forge.XXXXXX)"
  trap 'rm -rf "$TMPDIR"' EXIT

  if ! git clone --depth 1 "$REPO_URL" "$TMPDIR/repo" >/dev/null 2>&1; then
    red "✗ Failed to clone $REPO_URL"
    echo "  Check connectivity and that the repo exists."
    exit 1
  fi
  SRC="$TMPDIR/repo"

  echo "→ copying kit files..."
  # Core docs
  for f in CLAUDE.md MISSION-CONTROL.md CONTEXT.md WORKFLOW.md SETUP.md; do
    [[ -f "$SRC/$f" ]] && cp "$SRC/$f" "$TARGET/$f"
  done
  # .claude directory (skills, agents, scripts, hooks, settings)
  mkdir -p "$TARGET/.claude"
  for d in skills agents scripts hooks knowledge rules; do
    if [[ -d "$SRC/.claude/$d" ]]; then
      mkdir -p "$TARGET/.claude/$d"
      cp -R "$SRC/.claude/$d/." "$TARGET/.claude/$d/"
    fi
  done
  # Settings files (only if they don't exist — don't clobber user edits)
  for f in settings.json lessons.md; do
    if [[ -f "$SRC/.claude/$f" && ! -f "$TARGET/.claude/$f" ]]; then
      cp "$SRC/.claude/$f" "$TARGET/.claude/$f"
    fi
  done

  green "  ✓ Kit files copied"

  # Drop update helper
  mkdir -p "$TARGET/.claude/scripts"
  cat > "$TARGET/.claude/scripts/update.sh" <<'UPDATER'
#!/usr/bin/env bash
# Re-run the installer in update mode.
cd "$(dirname "$0")/../.." && curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash
UPDATER
  chmod +x "$TARGET/.claude/scripts/update.sh"
fi

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
    yellow "Re-run this script and pick Dev for now."
    exit 0
    ;;
  *)
    mkdir -p .claude
    echo "dev" > .claude/mode.txt
    ;;
esac

# ─── prereq checks ───────────────────────────────────────────────────────────

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
  red "Please install the missing tools above, then re-run this script."
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

# Verify The Forge files are present (should be after copy step or if already cloned)
if [[ ! -f "CLAUDE.md" || ! -f "MISSION-CONTROL.md" || ! -d ".claude/skills" ]]; then
  echo
  red "✗ The Forge files are missing. Something went wrong during setup."
  echo "      Try running again:"
  echo "         curl -fsSL https://raw.githubusercontent.com/NaNathan13/The-Forge/main/light-the-forge.sh | bash"
  exit 1
fi
green "  ✓ The Forge files found in this directory"

# If we're inside The Forge's own git history, offer to wipe it
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

# Mid-flow re-launch detection
if [[ -f ".claude/.kindle-in-progress" ]]; then
  echo
  yellow "  ! A previous /kindle run was interrupted (marker: .claude/.kindle-in-progress)."
  yellow "    Re-launching Claude — pick up where you left off, or say 'start over'."
fi

# ─── launch claude ────────────────────────────────────────────────────────────

echo
bold "All set. Launching Claude..."
echo
cyan "Tip: Claude will ask you questions one at a time. Pick the recommended"
cyan "     option if you're unsure — you can always change things later."
echo
sleep 1

exec claude "/kindle"
