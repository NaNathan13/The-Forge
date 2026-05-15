#!/usr/bin/env bash
# hooks.test.sh — tests for the P2 Stop + SessionStart hooks (issue #140, #181).
#
# Covers .claude/hooks/forge-stop-handoff.sh and .claude/hooks/forge-session-start.sh:
#   - Stop hook touches .forge/heartbeat/<slug> on every fire (heartbeat).
#   - Stop hook blocks the stop when this generation wrote no continuation file,
#     allows it when it did, and allows hand-run (non-loop-managed) sessions.
#   - Stop hook allows when stop_hook_active is true (no infinite block loop).
#   - SessionStart hook stamps the generation baseline the Stop hook reads.
#   - SessionStart hook injects `latest` via additionalContext, falls back to a
#     charter on first launch, and appends the loop's hand-off-promptly signal.
#   - Both hooks key off the FORGE_LOOP_MANAGED env marker (issue #181): the
#     marker set → loop-managed → SessionStart stamps, Stop enforces; the marker
#     unset → interactive → SessionStart does NOT stamp, Stop allows the turn.
#
# These exercise the hooks as the CLI invokes them: hook input JSON on stdin,
# decision / context JSON on stdout. FORGE_DIR points the hooks at a temp .forge
# dir so nothing leaks between tests. FORGE_LOOP_MANAGED is exported in setup so
# the default for every test is a loop-managed session; the interactive-session
# tests unset it explicitly.
#
# Run via:  test/run-tests.sh test/hooks.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

STOP_HOOK="$REPO_ROOT/.claude/hooks/forge-stop-handoff.sh"
START_HOOK="$REPO_ROOT/.claude/hooks/forge-session-start.sh"
CONT="$REPO_ROOT/scripts/continuation.sh"

# Each test gets its own temp .forge dir. SLUG is fixed so the hooks (which derive
# the slug from `cwd`) and the test agree: we feed the hooks a `cwd` whose basename
# slugifies to SLUG.
setup() {
  WORKDIR="$(mktemp -d)"
  export FORGE_DIR="$WORKDIR/.forge"
  # Pre-create the heartbeat dir so a test can stamp a .genbaseline directly
  # without racing the hook's own mkdir. The hooks also mkdir -p defensively.
  mkdir -p "$FORGE_DIR/heartbeat"
  # A cwd whose basename slugifies to a known slug — passed to the hooks as the
  # `cwd` field of the input JSON.
  SESSION_CWD="$WORKDIR/the-forge"
  mkdir -p "$SESSION_CWD"
  SLUG="the-forge"
  # Default every test to a loop-managed session: the relaunch loop exports
  # FORGE_LOOP_MANAGED=1 into each `claude -p` generation, and that is the
  # common case the hooks were written for. Tests that exercise an interactive
  # session unset it explicitly (see the FORGE_LOOP_MANAGED section).
  export FORGE_LOOP_MANAGED=1
  unset FORGE_RETENTION_CAP
}

teardown() {
  rm -rf "$WORKDIR"
  unset FORGE_DIR FORGE_RETENTION_CAP FORGE_LOOP_MANAGED
}

# Build a Stop-hook input JSON object. Args: [stop_hook_active] (default false).
stop_input() {
  local active="${1:-false}"
  jq -cn --arg cwd "$SESSION_CWD" --argjson active "$active" \
    '{session_id:"test", transcript_path:"/dev/null", cwd:$cwd,
      hook_event_name:"Stop", stop_hook_active:$active}'
}

# Build a SessionStart-hook input JSON object.
start_input() {
  jq -cn --arg cwd "$SESSION_CWD" \
    '{session_id:"test", transcript_path:"/dev/null", cwd:$cwd,
      hook_event_name:"SessionStart", source:"startup"}'
}

# Write a continuation generation for SLUG and return its number, via the helper.
# Uses the real continuation.sh + template so the chaining matches production.
write_generation() {
  bash "$CONT" write --slug "$SLUG" >/dev/null
}

# ── Stop hook: heartbeat ─────────────────────────────────────────────────────

test_stop_hook_touches_heartbeat_on_every_fire() {
  # No baseline file → not loop-managed → the hook allows the stop. But it must
  # STILL have touched the heartbeat — that is unconditional.
  stop_input | bash "$STOP_HOOK" >/dev/null 2>&1
  assert_file_exists "$FORGE_DIR/heartbeat/$SLUG" "Stop hook must touch the heartbeat"
}

test_stop_hook_heartbeat_is_a_fresh_timestamp() {
  stop_input | bash "$STOP_HOOK" >/dev/null 2>&1
  local hb
  hb="$(cat "$FORGE_DIR/heartbeat/$SLUG")"
  # ISO-8601 UTC, e.g. 2026-05-14T13:00:00Z
  assert_contains "$hb" "T" "heartbeat should be an ISO timestamp"
  assert_contains "$hb" "Z" "heartbeat should be a UTC (Z) timestamp"
}

test_stop_hook_heartbeat_touched_even_when_blocking() {
  # Loop-managed (baseline stamped) + no new continuation → the hook blocks. The
  # heartbeat must be touched anyway — it fires before the enforcement branch.
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  stop_input | bash "$STOP_HOOK" >/dev/null 2>&1
  assert_file_exists "$FORGE_DIR/heartbeat/$SLUG" \
    "heartbeat must be touched even on a blocked stop"
}

# ── Stop hook: handoff enforcement ───────────────────────────────────────────

test_stop_hook_allows_when_no_baseline() {
  # Marker is set (loop-managed) but no .genbaseline was stamped — missing
  # state. The hook must ALLOW rather than risk wedging on it.
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_not_contains "$out" '"decision":"block"' \
    "a missing baseline must not block the stop"
}

test_stop_hook_blocks_when_continuation_not_written() {
  # Loop-managed: SessionStart stamped baseline 000, and no generation was
  # written this run. The hook must BLOCK the stop.
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_contains "$out" '"decision":"block"' \
    "must block when this generation wrote no continuation file"
}

test_stop_hook_block_reason_names_the_continuation_path() {
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  local out reason
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  reason="$(jq -r '.reason' <<<"$out")"
  # The reason should point at the gen file the session must write.
  assert_contains "$reason" ".forge/continuation/$SLUG/gen-001.md" \
    "block reason should name the continuation file to write"
}

test_stop_hook_allows_when_continuation_written_this_generation() {
  # Baseline stamped at 000, then a generation is written → latest (001) > baseline
  # (000) → the handoff happened → the hook must ALLOW.
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  write_generation   # creates gen-001.md
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_not_contains "$out" '"decision":"block"' \
    "must allow once this generation has written its continuation file"
}

test_stop_hook_blocks_when_continuation_is_stale_prior_generation() {
  # A prior generation wrote gen-001, then a new session launched and SessionStart
  # stamped baseline 001. This generation wrote nothing new → latest (001) ==
  # baseline (001) → the hook must BLOCK: a stale prior file is not this
  # generation's handoff.
  write_generation                       # gen-001 from a prior generation
  echo "001" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_contains "$out" '"decision":"block"' \
    "a prior generation's continuation file must not satisfy this generation"
}

test_stop_hook_allows_when_stop_hook_active() {
  # stop_hook_active=true → the session is already continuing because of a prior
  # block. Blocking again is an infinite loop — the hook must ALLOW.
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  local out
  out="$(stop_input true | bash "$STOP_HOOK" 2>/dev/null)"
  assert_not_contains "$out" '"decision":"block"' \
    "must not block again when stop_hook_active is true (infinite-loop guard)"
}

test_stop_hook_always_exits_zero() {
  # The decision is carried in the JSON, never the exit code — a non-zero exit
  # would be read by the CLI as a hook *error*. Both allow and block exit 0.
  local rc=0
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  stop_input | bash "$STOP_HOOK" >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "Stop hook must exit 0 even when it blocks"
}

# ── SessionStart hook: generation baseline ───────────────────────────────────

test_session_start_stamps_baseline_zero_on_first_launch() {
  # No continuation generations yet → baseline must be stamped as 000 so the Stop
  # hook can still tell this is a loop-managed session.
  start_input | bash "$START_HOOK" >/dev/null 2>&1
  assert_file_exists "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  assert_eq "000" "$(cat "$FORGE_DIR/heartbeat/$SLUG.genbaseline")"
}

test_session_start_stamps_baseline_at_current_latest() {
  # Two generations already exist → the baseline must be stamped at the current
  # latest (002), so the Stop hook knows anything <= 002 is not this gen's work.
  write_generation   # gen-001
  write_generation   # gen-002
  start_input | bash "$START_HOOK" >/dev/null 2>&1
  assert_eq "002" "$(cat "$FORGE_DIR/heartbeat/$SLUG.genbaseline")"
}

# ── SessionStart hook: continuation injection ────────────────────────────────

test_session_start_injects_latest_continuation() {
  write_generation   # gen-001 — the `latest`
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  # Well-formed SessionStart hookSpecificOutput.
  assert_eq "SessionStart" "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  # The injected context is the gen file — it carries the hardened section headers.
  assert_contains "$ctx" "Hard constraints" \
    "injected context should be the continuation file's contents"
  assert_contains "$ctx" "Next concrete action"
}

test_session_start_falls_back_to_charter_on_first_launch() {
  # No continuation file, but a project charter exists → inject the charter.
  printf 'CHARTER: build the thing per the spec.\n' > "$FORGE_DIR/charter.md"
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "CHARTER: build the thing" \
    "first launch with a charter should inject the charter"
}

test_session_start_falls_back_to_slug_charter_first() {
  # A slug-scoped charter takes precedence over the project-wide one.
  mkdir -p "$FORGE_DIR/continuation/$SLUG"
  printf 'SLUG CHARTER wins\n' > "$FORGE_DIR/continuation/$SLUG/charter.md"
  printf 'PROJECT CHARTER\n' > "$FORGE_DIR/charter.md"
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "SLUG CHARTER wins"
  assert_not_contains "$ctx" "PROJECT CHARTER"
}

test_session_start_first_launch_no_charter_injects_builtin_note() {
  # No continuation, no charter → a minimal built-in note, still well-formed.
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "First launch" \
    "first launch with no charter should still inject a usable note"
}

test_session_start_continuation_wins_over_charter() {
  # Both a continuation generation AND a charter exist → the continuation wins
  # (the charter is the first-launch fallback only).
  printf 'CHARTER should not appear\n' > "$FORGE_DIR/charter.md"
  write_generation   # gen-001
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "Hard constraints"
  assert_not_contains "$ctx" "CHARTER should not appear"
}

test_session_start_appends_handoff_signal_when_present() {
  # The relaunch loop's budget gate wrote a hand-off-promptly signal → the hook
  # appends it to the injected context so the fresh generation hands off early.
  write_generation   # gen-001
  mkdir -p "$FORGE_DIR/continuation/$SLUG"
  printf 'hand-off-promptly used=44%%\n' > "$FORGE_DIR/continuation/$SLUG/handoff-signal"
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "BUDGET SIGNAL" \
    "a present handoff-signal should be surfaced in the injected context"
  assert_contains "$ctx" "used=44%"
}

test_session_start_no_handoff_signal_no_budget_text() {
  # No signal file → no budget text leaks into the injected context.
  write_generation   # gen-001
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_not_contains "$ctx" "BUDGET SIGNAL"
}

test_session_start_always_exits_zero() {
  # A SessionStart hook cannot block; it always exits 0.
  local rc=0
  start_input | bash "$START_HOOK" >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc"
}

test_session_start_emits_valid_json() {
  # Output must always be parseable JSON, even on the first-launch path.
  local out
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  echo "$out" | jq . >/dev/null || fail "SessionStart output must be valid JSON"
}

# ── FORGE_LOOP_MANAGED marker: loop-managed vs interactive (issue #181) ──────
# The relaunch loop exports FORGE_LOOP_MANAGED=1 into every `claude -p`
# generation. The hooks key off it: SessionStart stamps the genbaseline only
# when it is set; the Stop hook enforces the handoff only when it is set. An
# interactive session (no marker) is never stamped and never blocked — this is
# the fix for the confirmed Stop-hook double-block.

test_session_start_stamps_baseline_when_loop_managed() {
  # Marker set (the setup default) → loop-managed → the baseline IS stamped.
  start_input | bash "$START_HOOK" >/dev/null 2>&1
  assert_file_exists "$FORGE_DIR/heartbeat/$SLUG.genbaseline" \
    "a loop-managed SessionStart must stamp the genbaseline"
}

test_session_start_does_not_stamp_baseline_when_interactive() {
  # Marker unset → interactive session → the baseline must NOT be stamped.
  # A stamped baseline is exactly what makes the Stop hook enforce the handoff;
  # stamping it for an interactive session is the confirmed double-block.
  unset FORGE_LOOP_MANAGED
  start_input | bash "$START_HOOK" >/dev/null 2>&1
  assert_file_absent "$FORGE_DIR/heartbeat/$SLUG.genbaseline" \
    "an interactive SessionStart must not stamp the genbaseline"
}

test_session_start_still_injects_context_when_interactive() {
  # Skipping the baseline stamp must not skip context injection — an interactive
  # session still gets its continuation / charter injected normally.
  unset FORGE_LOOP_MANAGED
  printf 'CHARTER: interactive run\n' > "$FORGE_DIR/charter.md"
  local out ctx
  out="$(start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "CHARTER: interactive run" \
    "an interactive session must still receive injected context"
}

test_stop_hook_enforces_when_loop_managed_and_no_handoff() {
  # Marker set + baseline stamped + no new continuation → loop-managed session
  # skipping its handoff → the hook must BLOCK.
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_contains "$out" '"decision":"block"' \
    "a loop-managed session that skipped its handoff must be blocked"
}

test_stop_hook_allows_when_interactive_even_with_baseline() {
  # Marker unset → interactive session. Even if a stale .genbaseline is present
  # (e.g. left by a prior loop run in the same workdir), the marker check fires
  # first and the hook must ALLOW — the interactive turn-end is not blocked.
  unset FORGE_LOOP_MANAGED
  echo "000" > "$FORGE_DIR/heartbeat/$SLUG.genbaseline"
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_not_contains "$out" '"decision":"block"' \
    "an interactive session must not be blocked even with a stale baseline"
}

test_stop_hook_interactive_can_end_turn_double_block_gone() {
  # The end-to-end fix for issue #181: an interactive session (no marker) where
  # SessionStart ran (unconditionally registered) but — correctly — stamped no
  # baseline. The Stop hook must allow the turn to end. This is the confirmed
  # double-block, verified gone.
  unset FORGE_LOOP_MANAGED
  start_input | bash "$START_HOOK" >/dev/null 2>&1
  assert_file_absent "$FORGE_DIR/heartbeat/$SLUG.genbaseline" \
    "interactive SessionStart left no baseline"
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_not_contains "$out" '"decision":"block"' \
    "an interactive session must end its turn without the Stop hook blocking"
}

test_stop_hook_heartbeat_touched_when_interactive() {
  # The heartbeat is unconditional — it fires before the marker check. An
  # interactive session is allowed through, but still leaves a heartbeat.
  unset FORGE_LOOP_MANAGED
  stop_input | bash "$STOP_HOOK" >/dev/null 2>&1
  assert_file_exists "$FORGE_DIR/heartbeat/$SLUG" \
    "the heartbeat must be touched even for an interactive (allowed) session"
}

# ── Stop + SessionStart together: the round trip ─────────────────────────────

test_round_trip_session_start_then_clean_handoff_allows_stop() {
  # 1. SessionStart stamps the baseline (000, first launch).
  # 2. The generation writes its continuation file (gen-001).
  # 3. Stop hook sees latest (001) > baseline (000) → allows the stop.
  start_input | bash "$START_HOOK" >/dev/null 2>&1
  write_generation
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_not_contains "$out" '"decision":"block"' \
    "a clean handoff after SessionStart should allow the stop"
}

test_round_trip_session_start_then_no_handoff_blocks_stop() {
  # 1. SessionStart stamps the baseline (000).
  # 2. The generation writes NO continuation file.
  # 3. Stop hook sees latest (000) == baseline (000) → blocks the stop.
  start_input | bash "$START_HOOK" >/dev/null 2>&1
  local out
  out="$(stop_input | bash "$STOP_HOOK" 2>/dev/null)"
  assert_contains "$out" '"decision":"block"' \
    "skipping the handoff after SessionStart should block the stop"
}
