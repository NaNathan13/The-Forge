#!/usr/bin/env bash
set -uo pipefail

# budget-mirror.sh — the statusline budget mirror (P2 single-session resilience, §3).
#
# A DISPLAY-ONLY operator gauge. Claude Code hands a statusline script a JSON blob on
# stdin on every render; this script reads the context-window percentage from it and
# renders that percentage against the warn / hard thresholds from
# .forge/resilience.config — e.g.  `ctx 42% ▸ warn 40 / hard 50`.
#
# It is the human-readable mirror of the loop's mechanical budget gate (the Stop hook
# owns the gate; see design doc §3 / §Q2). It NEVER influences control flow: it writes
# no files, sets no exit-status meaning, blocks nothing. It only prints one line.
#
# ── Input ────────────────────────────────────────────────────────────────────
# Claude Code's statusline JSON on stdin. The field consumed is:
#   .context_window.used_percentage   — a number, percent of the context window used.
# If stdin is empty / not JSON / missing that field, the gauge degrades gracefully to
# a `ctx --%` reading rather than erroring — a statusline must never be noisy.
#
# ── Thresholds ───────────────────────────────────────────────────────────────
# warn / hard are read from .forge/resilience.config, keyed by session role:
#   role=orchestrator (default) → FORGE_ORCH_WARN_PCT   / FORGE_ORCH_HARD_PCT
#   role=worker                 → FORGE_WORKER_WARN_PCT / FORGE_WORKER_HARD_PCT
# The role is resolved from FORGE_SESSION_ROLE if set, else defaults to orchestrator
# (the long-lived session a human is most likely watching a statusline for). If the
# config is missing or a key is absent, the design doc §Q1 defaults are used so the
# gauge still renders.
#
# ── Wiring it in ─────────────────────────────────────────────────────────────
# Register it as the statusline command in .claude/settings.json:
#   { "statusLine": { "type": "command", "command": ".claude/statusline/budget-mirror.sh" } }
# An operator who wants the worker thresholds instead exports FORGE_SESSION_ROLE=worker
# in the environment Claude Code launches under.
# ─────────────────────────────────────────────────────────────────────────────

# Design doc §Q1 fallback defaults — used only if resilience.config can't supply them.
DEFAULT_ORCH_WARN=40
DEFAULT_ORCH_HARD=50
DEFAULT_WORKER_WARN=50
DEFAULT_WORKER_HARD=60

# ── Locate resilience.config ─────────────────────────────────────────────────
# FORGE_DIR overrides the .forge location (the test harness sets it to a temp dir),
# mirroring scripts/continuation.sh. Otherwise resolve it relative to the repo root.
if [[ -n "${FORGE_DIR:-}" ]]; then
  CONFIG="$FORGE_DIR/resilience.config"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$REPO_ROOT" ]]; then
    # Not in a git tree — fall back to two levels up from this script (.claude/statusline/).
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  fi
  CONFIG="$REPO_ROOT/.forge/resilience.config"
fi

# ── Resolve thresholds ───────────────────────────────────────────────────────
# Source the config in a way that can't leak control flow: it is a KEY=value file by
# contract, but read it defensively all the same.
FORGE_ORCH_WARN_PCT=""
FORGE_ORCH_HARD_PCT=""
FORGE_WORKER_WARN_PCT=""
FORGE_WORKER_HARD_PCT=""
if [[ -f "$CONFIG" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG" 2>/dev/null || true
fi

role="${FORGE_SESSION_ROLE:-orchestrator}"
case "$role" in
  worker)
    warn="${FORGE_WORKER_WARN_PCT:-$DEFAULT_WORKER_WARN}"
    hard="${FORGE_WORKER_HARD_PCT:-$DEFAULT_WORKER_HARD}"
    ;;
  *)
    # Anything that isn't "worker" — including the explicit "orchestrator" and any
    # unrecognized value — uses the orchestrator pair. A statusline never errors.
    role="orchestrator"
    warn="${FORGE_ORCH_WARN_PCT:-$DEFAULT_ORCH_WARN}"
    hard="${FORGE_ORCH_HARD_PCT:-$DEFAULT_ORCH_HARD}"
    ;;
esac

# Guard against a malformed config value — a non-integer threshold falls back to the
# role default rather than rendering garbage.
[[ "$warn" =~ ^[0-9]+$ ]] || warn=$( [[ "$role" == worker ]] && echo "$DEFAULT_WORKER_WARN" || echo "$DEFAULT_ORCH_WARN" )
[[ "$hard" =~ ^[0-9]+$ ]] || hard=$( [[ "$role" == worker ]] && echo "$DEFAULT_WORKER_HARD" || echo "$DEFAULT_ORCH_HARD" )

# ── Read the context percentage from stdin JSON ──────────────────────────────
# Slurp stdin (the statusline JSON). It may be empty if invoked outside Claude Code.
input=""
if [[ ! -t 0 ]]; then
  input="$(cat)"
fi

used=""
if [[ -n "$input" ]] && command -v jq >/dev/null 2>&1; then
  # `// empty` so a missing/null field yields "" rather than the string "null".
  used="$(jq -r '.context_window.used_percentage // empty' <<<"$input" 2>/dev/null || true)"
fi

# ── Render the gauge ─────────────────────────────────────────────────────────
# Display-only: one line to stdout, exit 0 unconditionally. No file writes, no
# control-flow signalling.
if [[ -z "$used" ]]; then
  # Couldn't read a percentage — show a placeholder, still show the thresholds so the
  # operator knows the gauge is wired and what the lines are.
  printf 'ctx --%% \xe2\x96\xb8 warn %s / hard %s\n' "$warn" "$hard"
  exit 0
fi

# Round the percentage to a whole number for a compact display. `used` may be a float
# (e.g. 42.7) or an int; printf's %.0f handles both. If it somehow isn't numeric, fall
# back to the raw value rather than erroring.
if [[ "$used" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  used_display="$(printf '%.0f' "$used")"
else
  used_display="$used"
fi

# Optional marker so the eye catches a breach without reading the numbers: a caret at
# warn, a bang at hard. Purely cosmetic.
marker=""
if [[ "$used_display" =~ ^[0-9]+$ ]]; then
  if (( used_display >= hard )); then
    marker=" !"
  elif (( used_display >= warn )); then
    marker=" ^"
  fi
fi

printf 'ctx %s%%%s \xe2\x96\xb8 warn %s / hard %s\n' "$used_display" "$marker" "$warn" "$hard"
exit 0
