#!/usr/bin/env bash
set -uo pipefail

# forgemaster-session-start.sh — P2 SessionStart hook: continuation re-injection.
#
# Design doc §3b / §4c. Registered on the `SessionStart` event in
# .claude/settings.json. A deterministic bash script — no Claude Code runtime.
# This is the piece that makes the relaunch loop *continuous* rather than
# *amnesiac*: the loop provides a fresh process, this hook provides the memory.
#
# ── What it does (design §4c) ────────────────────────────────────────────────
#   1. Resolve the session slug from the working directory.
#   2. Read .forge/continuation/<slug>/latest (the symlink → newest gen-NNN.md).
#   3. If it resolves, inject its full contents as the session's opening context
#      via `additionalContext` in `hookSpecificOutput` — the fresh session begins
#      already knowing its hard constraints, execution frontier, conversation
#      summary, and next concrete action.
#   4. If it does NOT resolve (a genuine first launch), inject the session's
#      charter / initial prompt instead — from .forge/continuation/<slug>/charter.md,
#      else .forge/charter.md, else a minimal built-in note.
#   5. Stamp the generation baseline the Stop hook reads — see below.
#
# ── The generation baseline (pairs with forgemaster-stop-handoff.sh) ───────────────
# The Stop hook needs to know whether *this* generation wrote a new continuation
# file. It cannot track generation numbers itself. So this hook, on a
# loop-managed launch, writes the continuation generation number that exists
# right now to .forge/heartbeat/<slug>.genbaseline. The Stop hook later compares
# the latest generation number against that baseline: greater → a handoff
# happened this generation; equal → it did not, block the stop.
#
# Stamping is gated on the FORGEMASTER_LOOP_MANAGED marker (issue #181). The relaunch
# loop exports FORGEMASTER_LOOP_MANAGED=1 into every `claude -p` generation it
# launches; an interactive session a developer opens by hand never carries it.
# This hook is registered unconditionally in .claude/settings.json, so it runs
# for interactive sessions too — but it must only stamp the baseline for
# loop-managed ones. "Baseline exists" is the Stop hook's "this is loop-managed"
# discriminator; stamping it for an interactive session would make the Stop hook
# wrongly enforce the handoff and block the turn (the confirmed double-block).
# Even a first loop-managed launch (baseline 0) needs the stamp; an interactive
# launch needs it skipped.
#
# A "hand-off promptly" signal file (written by the relaunch loop's budget gate
# when usage crosses the warn line) is appended to the injected context if
# present, so the fresh generation knows to hand off early.
#
# ── I/O contract (Claude Code SessionStart hook) ─────────────────────────────
# Input  — a JSON object on stdin: { session_id, transcript_path, cwd,
#          hook_event_name, source, ... }.
# Output — to inject context: print
#          {"hookSpecificOutput":{"hookEventName":"SessionStart",
#           "additionalContext":"..."}} on stdout, exit 0.
#          A SessionStart hook CANNOT block — exit code is advisory only. This
#          hook always exits 0.
#
# ── Environment ──────────────────────────────────────────────────────────────
#   FORGE_DIR   Override the .forge directory (default: repo-root /.forge,
#               falling back to ./.forge outside a git repo). Tests set this to
#               a temp dir. Mirrors continuation.sh / relaunch-loop.sh.
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# continuation.sh lives at repo-root scripts/; this hook is at .claude/hooks/.
CONTINUATION_SH="$SCRIPT_DIR/../../scripts/continuation.sh"

# Emit the SessionStart additionalContext payload and exit 0. Centralised so
# every injection path is identical and always well-formed JSON.
inject_context() {
  local ctx="$1"
  jq -cn --arg ctx "$ctx" \
    '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
  exit 0
}

# Nothing to inject — emit an empty object, exit 0. (A SessionStart hook cannot
# block; an empty object is the well-formed "no context" response.)
inject_nothing() {
  printf '{}\n'
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
  # Read the hook input JSON from stdin; empty stdin (hand-run) → "{}".
  local input
  input="$(cat 2>/dev/null || true)"
  [[ -n "$input" ]] || input="{}"

  # jq absent → we cannot build the payload. A SessionStart hook cannot block
  # and injecting nothing is harmless — fail safe by injecting nothing.
  command -v jq >/dev/null 2>&1 || inject_nothing

  # Resolve the slug from the hook input's `cwd` (fall back to process cwd) via
  # continuation.sh, so hook + loop + helper all agree on the slug.
  local cwd slug forge_dir
  cwd="$(jq -r '.cwd // ""' <<<"$input" 2>/dev/null || echo "")"
  [[ -n "$cwd" ]] || cwd="$PWD"

  if [[ -f "$CONTINUATION_SH" ]]; then
    slug="$(bash "$CONTINUATION_SH" slug "$cwd" 2>/dev/null || echo "")"
  fi
  [[ -n "$slug" ]] || slug="session"

  forge_dir="$(resolve_forge_dir)"

  # ── Stamp the generation baseline (loop-managed sessions only) ─────────────
  # Write the continuation generation number that exists *now* to
  # .forge/heartbeat/<slug>.genbaseline. The Stop hook reads this to decide
  # whether this generation wrote a new continuation file. 000 if none exist.
  #
  # Gated on FORGEMASTER_LOOP_MANAGED (issue #181): only the relaunch loop's
  # `claude -p` generations carry the marker. An interactive session must NOT be
  # stamped — a stamped baseline is exactly the signal that makes the Stop hook
  # enforce the handoff, and enforcing it on an interactive turn-end is the
  # confirmed double-block this gate fixes.
  if [[ -n "${FORGEMASTER_LOOP_MANAGED:-}" ]]; then
    local latest_num hb_dir baseline_file
    if [[ -f "$CONTINUATION_SH" ]]; then
      latest_num="$(bash "$CONTINUATION_SH" latest-num --slug "$slug" 2>/dev/null || echo "")"
    fi
    [[ "$latest_num" =~ ^[0-9]+$ ]] || latest_num="000"
    hb_dir="$forge_dir/heartbeat"
    baseline_file="$hb_dir/$slug.genbaseline"
    mkdir -p "$hb_dir" 2>/dev/null || true
    printf '%s\n' "$latest_num" > "$baseline_file" 2>/dev/null || true
  fi

  # ── Resolve the continuation `latest` to inject ────────────────────────────
  local latest_path continuation=""
  if [[ -f "$CONTINUATION_SH" ]]; then
    latest_path="$(bash "$CONTINUATION_SH" latest-path --slug "$slug" 2>/dev/null || echo "")"
  fi
  if [[ -n "$latest_path" && -f "$latest_path" ]]; then
    continuation="$(cat "$latest_path" 2>/dev/null || echo "")"
  fi

  # ── Pick what to inject ────────────────────────────────────────────────────
  local payload=""
  if [[ -n "$continuation" ]]; then
    # A continuation generation exists — inject it verbatim. This is the common
    # case: the fresh session resumes at "next concrete action".
    payload="$continuation"
  else
    # Genuine first launch — no continuation yet. Inject the session charter /
    # initial prompt instead. Look for a charter file under the slug's dir, then
    # a project-wide one, then fall back to a minimal built-in note.
    local charter_file charter=""
    for charter_file in \
      "$forge_dir/continuation/$slug/charter.md" \
      "$forge_dir/charter.md"; do
      if [[ -f "$charter_file" ]]; then
        charter="$(cat "$charter_file" 2>/dev/null || echo "")"
        [[ -n "$charter" ]] && break
      fi
    done
    if [[ -n "$charter" ]]; then
      payload="$charter"
    else
      payload="First launch — no continuation file for session '$slug' yet, and no charter found at .forge/continuation/$slug/charter.md or .forge/charter.md. Proceed from the initial prompt; write a continuation file (templates/continuation-gen.md) before this generation exits so the next session can resume."
    fi
  fi

  # ── Append the "hand off promptly" signal if the loop set it ───────────────
  # The relaunch loop's budget gate writes this file when usage crossed the warn
  # line. Surfacing it here tells the fresh generation to hand off early.
  local signal_file
  signal_file="$forge_dir/continuation/$slug/handoff-signal"
  if [[ -f "$signal_file" ]]; then
    local signal
    signal="$(cat "$signal_file" 2>/dev/null || echo "")"
    if [[ -n "$signal" ]]; then
      payload="$payload

---
BUDGET SIGNAL FROM THE RELAUNCH LOOP: $signal
This generation is over the warn threshold — finish your current phase and hand off promptly (write the next continuation generation, then exit)."
    fi
  fi

  [[ -n "$payload" ]] || inject_nothing
  inject_context "$payload"
}

main "$@"
