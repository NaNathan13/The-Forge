#!/usr/bin/env bash
set -uo pipefail

# forge-stop-handoff.sh — P2 Stop hook: handoff enforcer + heartbeat.
#
# Design doc §3a / amended §Q2. Registered on the `Stop` event in
# .claude/settings.json. A deterministic bash script — no Claude Code runtime,
# no token cost. It does the two jobs the CLI actually gives a Stop hook:
#
#   1. HEARTBEAT — touch .forge/heartbeat/<slug> with a fresh timestamp on every
#      fire, unconditionally. This is the liveness signal the slice-6 watchdog
#      reads to tell a live session from a hung one.
#
#   2. HANDOFF ENFORCEMENT — block the stop if this generation is trying to exit
#      *without* having written its continuation file. The amended §Q2 is
#      explicit that a Stop hook CANNOT inject a message and CANNOT read a
#      context-window percentage — it can only `block`/allow. So this hook does
#      the one thing it can: it `block`s a stop that would silently skip the
#      handoff, with a reason string telling the session to write its
#      continuation file first.
#
# ── How "this generation wrote its continuation" is detected ─────────────────
# The relaunch loop (slice 4) launches a fresh `claude` per generation. The
# SessionStart hook (forge-session-start.sh), on each launch, records a baseline
# — the continuation generation number that existed *at session start* — to
# .forge/heartbeat/<slug>.genbaseline. This Stop hook compares the current
# latest generation number against that baseline:
#
#   latest-num >  baseline  → the session wrote a new gen-NNN.md → ALLOW the stop.
#   latest-num == baseline  → no new continuation this generation → BLOCK the stop.
#
# This makes "this generation's continuation file" precise and testable without
# the hook needing to track generation numbers itself — the SessionStart hook
# stamps the baseline, this hook reads it.
#
# "Loop-managed" is an explicit positive signal, not an inference (issue #181).
# The relaunch loop exports FORGE_LOOP_MANAGED=1 into every `claude -p`
# generation it launches; an interactive session a developer opens by hand never
# carries it. This hook enforces the handoff ONLY when FORGE_LOOP_MANAGED is set
# (and a baseline exists). If the marker is unset — an interactive session — the
# hook ALLOWS the stop unconditionally. P2 only enforces handoffs on loop-managed
# sessions; it must never wedge a hand-run interactive session that has nothing
# to do with the resilience loop.
#
# The baseline check still runs after the marker check: even a loop-managed
# session with no baseline yet (SessionStart somehow did not stamp) is allowed,
# rather than risk wedging on missing state.
#
# ── stop_hook_active ─────────────────────────────────────────────────────────
# Claude Code sets `stop_hook_active: true` in the Stop hook input when the
# session is already continuing *because* a previous Stop hook blocked it. If we
# blocked again on that fire we would spin forever. So: when stop_hook_active is
# true, this hook ALLOWS the stop unconditionally — the session was already told
# once; a second block is a loop, not enforcement.
#
# ── I/O contract (Claude Code Stop hook) ─────────────────────────────────────
# Input  — a JSON object on stdin: { session_id, transcript_path, cwd,
#          hook_event_name, stop_hook_active, ... }.
# Output — to BLOCK: print {"decision":"block","reason":"..."} on stdout, exit 0.
#          to ALLOW: print nothing (or {}), exit 0.
# The hook always exits 0; the decision is carried in the JSON, not the code —
# a non-zero exit would be read as a hook *error*, not an allow.
#
# ── Environment ──────────────────────────────────────────────────────────────
#   FORGE_DIR   Override the .forge directory (default: repo-root /.forge,
#               falling back to ./.forge outside a git repo). Tests set this to
#               a temp dir. Mirrors continuation.sh / relaunch-loop.sh.
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# continuation.sh lives at repo-root scripts/; this hook is at .claude/hooks/.
CONTINUATION_SH="$SCRIPT_DIR/../../scripts/continuation.sh"

# Allow the stop: emit nothing meaningful, exit 0. Centralised so every allow
# path is identical.
allow_stop() {
  exit 0
}

# Block the stop: emit the block decision with a reason, exit 0 (the decision is
# in the JSON — a non-zero exit would be read as a hook error instead).
block_stop() {
  local reason="$1"
  jq -cn --arg reason "$reason" '{decision:"block", reason:$reason}'
  exit 0
}

# ── Locate the .forge directory ──────────────────────────────────────────────
# Honour an explicit FORGE_DIR; otherwise prefer the git repo root, falling back
# to the current directory. Identical resolution to continuation.sh.
resolve_forge_dir() {
  if [[ -n "${FORGE_DIR:-}" ]]; then
    printf '%s\n' "$FORGE_DIR"
    return 0
  fi
  local root
  if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s/.forge\n' "$root"
  else
    printf '%s/.forge\n' "$PWD"
  fi
}

main() {
  # Read the hook input JSON from stdin. A Stop hook always gets one; if stdin is
  # empty (a hand-run test of the script with no piped input), treat it as "{}".
  local input
  input="$(cat 2>/dev/null || true)"
  [[ -n "$input" ]] || input="{}"

  # jq is a hard dependency of the P2 harness and of this hook. If it is somehow
  # absent we must still ALLOW the stop — a missing tool must never wedge a
  # session. (The relaunch loop and the test runner both fail loud on missing
  # jq elsewhere; here, fail safe.)
  command -v jq >/dev/null 2>&1 || allow_stop

  # stop_hook_active — already continuing because of a prior block. A second
  # block here is an infinite loop, not enforcement. Allow.
  local stop_hook_active
  stop_hook_active="$(jq -r '.stop_hook_active // false' <<<"$input" 2>/dev/null || echo false)"

  # Resolve the slug. The hook input carries `cwd` (the session's working
  # directory) — derive the slug from it via continuation.sh so the hook, the
  # loop, and the continuation helper all agree on the slug. Fall back to the
  # process cwd if the input has no `cwd`.
  local cwd slug forge_dir
  cwd="$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null || echo "")"
  [[ -n "$cwd" ]] || cwd="$PWD"

  if [[ -f "$CONTINUATION_SH" ]]; then
    slug="$(bash "$CONTINUATION_SH" slug "$cwd" 2>/dev/null || echo "")"
  fi
  [[ -n "$slug" ]] || slug="session"

  forge_dir="$(resolve_forge_dir)"

  # ── Job 1: heartbeat — unconditional, on every fire ────────────────────────
  # Touch .forge/heartbeat/<slug> with a fresh timestamp. The watchdog reads its
  # age. Do this FIRST and unconditionally — even the early-allow paths below
  # are control flow the watchdog still wants a heartbeat for. Best-effort:
  # never let a heartbeat write failure wedge the stop.
  local hb_dir hb_file
  hb_dir="$forge_dir/heartbeat"
  hb_file="$hb_dir/$slug"
  mkdir -p "$hb_dir" 2>/dev/null || true
  date -u +%Y-%m-%dT%H:%M:%SZ > "$hb_file" 2>/dev/null || true

  # ── Job 2: handoff enforcement ─────────────────────────────────────────────

  # Already continuing because of a previous block → allow (no infinite loop).
  if [[ "$stop_hook_active" == "true" ]]; then
    allow_stop
  fi

  # FORGE_LOOP_MANAGED is the explicit "this generation is loop-managed" marker
  # (issue #181). The relaunch loop exports it into every `claude -p` generation;
  # an interactive session never carries it. Unset → not loop-managed → allow the
  # stop. This is the primary discriminator: P2 must never wedge a hand-run
  # interactive session, and an interactive SessionStart no longer stamps a
  # baseline either, so this and the baseline check agree.
  if [[ -z "${FORGE_LOOP_MANAGED:-}" ]]; then
    allow_stop
  fi

  # The SessionStart hook stamps a per-session baseline: the continuation
  # generation number that existed when this generation launched. No baseline →
  # treat as not loop-managed and allow, rather than risk wedging on missing
  # state. P2 only enforces handoffs on loop-managed sessions.
  local baseline_file baseline
  baseline_file="$hb_dir/$slug.genbaseline"
  if [[ ! -f "$baseline_file" ]]; then
    allow_stop
  fi
  baseline="$(cat "$baseline_file" 2>/dev/null || echo "")"
  # A malformed baseline (not a number) is treated as "not loop-managed" — allow
  # rather than risk wedging on bad state.
  [[ "$baseline" =~ ^[0-9]+$ ]] || allow_stop

  # Current latest continuation generation number for this slug.
  local latest
  if [[ -f "$CONTINUATION_SH" ]]; then
    latest="$(bash "$CONTINUATION_SH" latest-num --slug "$slug" 2>/dev/null || echo "")"
  fi
  # If we cannot read the latest number, we cannot prove the handoff was
  # skipped — allow rather than wedge on an unreadable state.
  [[ "$latest" =~ ^[0-9]+$ ]] || allow_stop

  # Strip leading zeros for a clean numeric compare (zero-padded → octal trap).
  local latest_n baseline_n
  latest_n="$((10#$latest))"
  baseline_n="$((10#$baseline))"

  if [[ "$latest_n" -gt "$baseline_n" ]]; then
    # A new gen-NNN.md was written this generation — the handoff happened. Allow.
    allow_stop
  fi

  # No new continuation file this generation — the session is trying to exit
  # without handing off. Block, with a reason that tells it exactly what to do.
  local next_num gen_path
  next_num="$(printf '%03d' "$((baseline_n + 1))")"
  gen_path=".forge/continuation/$slug/gen-$next_num.md"
  block_stop "No continuation file written for this generation — write $gen_path (the five hardened sections from templates/continuation-gen.md) before exiting, so the next session can resume. Run: scripts/continuation.sh write --slug $slug"
}

main "$@"
