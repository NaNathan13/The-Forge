#!/usr/bin/env bash
# relaunch-loop.test.sh — tests for scripts/relaunch-loop.sh (P2 slice 1b, issue #139).
#
# Covers every branch of the relaunch loop's per-generation decision (design doc §1):
#   - work-complete sentinel (FORGE_COMPLETE)        → loop exits 0
#   - clean-handoff sentinel (FORGE_CONTINUE)        → generation recorded, relaunch
#   - non-zero claude exit (crash)                   → exit code propagated, not masked
#   - exit 0 with no recognised sentinel             → treated as a fault, exit non-zero
#   - budget gate: under warn / over hard            → relaunch normally / stop
#   - thrash circuit breaker                         → trips after N-in-M, exits non-zero
#
# The loop is deterministic shell — it is exercised against the slice-2 harness: the
# `claude` stub (test/stubs/claude) stands in for the real CLI, fixtures under
# test/fixtures/ supply each scenario. No Claude runtime, zero token cost.
#
# Run via:  test/run-tests.sh test/relaunch-loop.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

LOOP="$REPO_ROOT/scripts/relaunch-loop.sh"
FIXTURES="$TEST_DIR/fixtures"

# Each test gets its own temp .forge dir so generation counters / thrash state /
# handoff signals never leak between tests. The claude stub is put first on PATH so
# the loop resolves `claude` to it.
setup() {
  WORKDIR="$(mktemp -d)"
  export FORGE_DIR="$WORKDIR/.forge"
  mkdir -p "$FORGE_DIR"
  # Ship a copy of the real resilience.config into the temp .forge so the loop's
  # budget gate / throttle reads exercise real config parsing, not just defaults.
  cp "$REPO_ROOT/.forge/resilience.config" "$FORGE_DIR/resilience.config"
  export PATH="$TEST_DIR/stubs:$PATH"
  # Throttle off in tests — we are not measuring wall-clock pacing.
  echo 'FORGE_THROTTLE_SECONDS=0' >> "$FORGE_DIR/resilience.config"
}

teardown() {
  rm -rf "$WORKDIR"
  unset FORGE_DIR FORGE_MAX_GENERATIONS
}

# Run the loop with a fixture; capture combined output + exit code. The `rc=0; ... || rc=$?`
# idiom is mandatory under `set -e` — see test/README.md gotchas.
run_loop() {
  local fixture="$1"; shift
  RUN_RC=0
  RUN_OUT="$(CLAUDE_STUB_FIXTURE="$fixture" bash "$LOOP" "$@" 2>&1)" || RUN_RC=$?
}

# ── Static checks ────────────────────────────────────────────────────────────

test_loop_passes_bash_syntax_check() {
  local rc=0
  bash -n "$LOOP" 2>/dev/null || rc=$?
  assert_exit_code 0 "$rc" "relaunch-loop.sh must pass bash -n"
}

# ── Work-complete sentinel → loop exits 0 ────────────────────────────────────

test_work_complete_sentinel_exits_zero() {
  run_loop "$FIXTURES/work-complete.sh" --slug demo
  assert_exit_code 0 "$RUN_RC" "FORGE_COMPLETE should make the loop exit 0"
  assert_contains "$RUN_OUT" "FORGE_COMPLETE"
}

# ── Clean-handoff sentinel → generation recorded, loop relaunches ────────────

test_clean_handoff_records_generation_and_relaunches() {
  # The stub always emits FORGE_CONTINUE, so the loop would relaunch forever —
  # FORGE_MAX_GENERATIONS=1 is the test/CI safety net: do exactly one handoff
  # decision, then stop. Reaching the cap is a clean (exit 0) stop.
  FORGE_MAX_GENERATIONS=1 run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC" "loop should stop cleanly at the generation cap"
  assert_contains "$RUN_OUT" "recorded handoff" "a clean handoff must record a generation"
}

test_clean_handoff_relaunches_multiple_generations() {
  # Cap at 3 — the loop should record three handoff generations before the safety net.
  FORGE_MAX_GENERATIONS=3 run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC"
  local count
  count="$(grep -c "recorded handoff" <<<"$RUN_OUT")"
  assert_eq "3" "$count" "loop should relaunch through three handoff generations"
}

# ── Budget gate: under the warn line → relaunch normally ─────────────────────

test_budget_gate_under_warn_relaunches_normally() {
  # clean-handoff-under-budget.sh is ~20% input usage — under the orchestrator
  # 40% warn line → relaunch normally, no "hand off promptly" signal written.
  FORGE_MAX_GENERATIONS=1 run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC"
  assert_contains "$RUN_OUT" "relaunch normally"
  assert_file_absent "$FORGE_DIR/continuation/demo/handoff-signal" \
    "under the warn line, no hand-off-promptly signal should be written"
}

# ── Budget gate: over the hard line → loop stops, does not relaunch ──────────

test_budget_gate_over_hard_stops_loop() {
  # clean-handoff-over-hard.sh is ~52% input usage — past the orchestrator 50%
  # hard line. The loop must NOT start another generation past hard; it exits 3.
  run_loop "$FIXTURES/clean-handoff-over-hard.sh" --slug demo
  assert_exit_code 3 "$RUN_RC" "over the hard line, the loop must stop with the budget-hard exit code"
  assert_contains "$RUN_OUT" "hard"
}

test_budget_gate_warn_band_writes_handoff_signal() {
  # A clean handoff at 45% input usage — between the orchestrator warn (40%) and
  # hard (50%) lines. The loop relaunches but writes the "hand off promptly"
  # signal the SessionStart hook reads.
  FORGE_MAX_GENERATIONS=1 \
    CLAUDE_STUB_RESULT="phase done FORGE_CONTINUE" \
    CLAUDE_STUB_USAGE='{"input_tokens":90000,"output_tokens":3000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}' \
    run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC"
  assert_contains "$RUN_OUT" "hands off promptly"
  assert_file_exists "$FORGE_DIR/continuation/demo/handoff-signal" \
    "in the warn band, the loop must write the hand-off-promptly signal"
}

test_budget_gate_resolves_worker_role_thresholds() {
  # 55% input usage. For an orchestrator (50% hard) that is over hard → stop.
  # For a worker (60% hard) the same usage is in the warn band → relaunch.
  FORGE_MAX_GENERATIONS=1 \
    CLAUDE_STUB_RESULT="handoff FORGE_CONTINUE" \
    CLAUDE_STUB_USAGE='{"input_tokens":110000,"output_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}' \
    run_loop "$FIXTURES/clean-handoff-under-budget.sh" --role worker --slug demo
  assert_exit_code 0 "$RUN_RC" "55% usage is within the worker 60% hard line — loop should relaunch"
  assert_contains "$RUN_OUT" "worker"
}

# ── Non-zero claude exit → propagated, not masked ────────────────────────────

test_crash_nonzero_exit_is_propagated() {
  # crash-nonzero-exit.sh exits 1 — the loop must propagate that, not respin.
  run_loop "$FIXTURES/crash-nonzero-exit.sh" --slug demo
  assert_exit_code 1 "$RUN_RC" "a non-zero claude exit must be propagated by the loop"
  assert_contains "$RUN_OUT" "propagating to launchd"
}

test_crash_arbitrary_exit_code_is_propagated_verbatim() {
  # An arbitrary crash code (37) must pass through unchanged — launchd needs the
  # real code, not a normalised one.
  CLAUDE_STUB_EXIT=37 run_loop "$FIXTURES/crash-nonzero-exit.sh" --slug demo
  assert_exit_code 37 "$RUN_RC" "the loop must propagate the claude exit code verbatim"
}

test_crash_does_not_record_a_generation() {
  # A crash never reached a sentinel — no generation should be recorded.
  run_loop "$FIXTURES/crash-nonzero-exit.sh" --slug demo
  assert_not_contains "$RUN_OUT" "recorded handoff" \
    "a crash is not a handoff — no generation should be recorded"
}

# ── Exit 0 with no recognised sentinel → treated as a fault ──────────────────

test_exit_zero_no_sentinel_is_a_fault() {
  # exit-zero-no-sentinel.sh: exit 0, .result has neither sentinel. Per design §1
  # the loop treats this as a fault and exits non-zero rather than spinning.
  run_loop "$FIXTURES/exit-zero-no-sentinel.sh" --slug demo
  assert_exit_code 1 "$RUN_RC" "exit 0 with no sentinel must be a fault, not a handoff"
  assert_contains "$RUN_OUT" "no FORGE_CONTINUE/FORGE_COMPLETE sentinel"
}

test_exit_zero_no_sentinel_does_not_relaunch() {
  run_loop "$FIXTURES/exit-zero-no-sentinel.sh" --slug demo
  assert_not_contains "$RUN_OUT" "recorded handoff" \
    "a no-sentinel fault must not be recorded as a handoff generation"
}

# ── Thrash circuit breaker → trips after N-in-M, exits non-zero ──────────────

test_thrash_circuit_breaker_trips() {
  # Drive a tight thrash window: max 2 handoffs in a 300s window. The stub always
  # emits FORGE_CONTINUE, so the 3rd handoff inside the window trips the breaker.
  # FORGE_MAX_GENERATIONS is high enough that the breaker — not the cap — stops it.
  echo 'FORGE_THRASH_MAX_GENERATIONS=2' >> "$FORGE_DIR/resilience.config"
  echo 'FORGE_THRASH_WINDOW_SECONDS=300' >> "$FORGE_DIR/resilience.config"
  FORGE_MAX_GENERATIONS=50 run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 2 "$RUN_RC" "the thrash circuit breaker must exit with the thrash exit code"
  assert_contains "$RUN_OUT" "circuit breaker tripped"
}

test_thrash_breaker_does_not_trip_under_the_limit() {
  # Max 5 handoffs in the window; cap the run at 3 generations. Three handoffs is
  # under the breaker limit → the loop stops on the cap (exit 0), not the breaker.
  echo 'FORGE_THRASH_MAX_GENERATIONS=5' >> "$FORGE_DIR/resilience.config"
  echo 'FORGE_THRASH_WINDOW_SECONDS=300' >> "$FORGE_DIR/resilience.config"
  FORGE_MAX_GENERATIONS=3 run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC" "three handoffs under a five-handoff limit must not trip the breaker"
  assert_not_contains "$RUN_OUT" "circuit breaker tripped"
}

# ── FORGE_LOOP_MANAGED marker exported into each generation (issue #181) ─────

test_loop_exports_forge_loop_managed_marker() {
  # The loop must export FORGE_LOOP_MANAGED=1 into the env of every `claude -p`
  # generation it launches — that is the marker the P2 hooks key off to tell a
  # loop-managed session from an interactive one. The claude stub's env probe
  # records what reached the child; assert it saw the marker set to 1.
  local probe="$WORKDIR/env-probe"
  FORGE_MAX_GENERATIONS=1 \
    CLAUDE_STUB_ENV_PROBE="$probe" \
    run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC"
  assert_file_exists "$probe" "the claude stub should have recorded its environment"
  assert_contains "$(cat "$probe")" "FORGE_LOOP_MANAGED=1" \
    "the loop must export FORGE_LOOP_MANAGED=1 into each generation"
}

test_loop_exports_marker_on_every_generation() {
  # The marker is exported on every relaunch, not just the first — cap at 3
  # generations and assert the probe recorded the marker set three times.
  local probe="$WORKDIR/env-probe"
  FORGE_MAX_GENERATIONS=3 \
    CLAUDE_STUB_ENV_PROBE="$probe" \
    run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC"
  local count
  count="$(grep -c "FORGE_LOOP_MANAGED=1" "$probe")"
  assert_eq "3" "$count" \
    "the loop must export the marker into every generation, not just the first"
}

# ── PID file (slice 1 of sub-phase 3d, rec #22) ──────────────────────────────
# The loop must write its `claude` child PID to
# $FORGE_DIR/continuation/<slug>/claude.pid before waiting on it. The watchdog
# reads that file to target the exact wedged process on multi-project hosts.

test_loop_writes_pid_file() {
  # After one generation the loop must have written its claude child PID to
  # $FORGE_DIR/continuation/<slug>/claude.pid. The value must be numeric.
  FORGE_MAX_GENERATIONS=1 \
    run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC"
  local pid_file="$FORGE_DIR/continuation/demo/claude.pid"
  assert_file_exists "$pid_file" "loop must write its claude child PID to claude.pid"
  local recorded
  recorded="$(cat "$pid_file")"
  assert_ne "" "$recorded" "the PID file must not be empty"
  if ! [[ "$recorded" =~ ^[0-9]+$ ]]; then
    fail "PID file contents must be numeric, got: $recorded"
  fi
}

test_loop_clears_stale_pid_file_at_startup() {
  # Pre-seed a bogus PID file. The loop must clear it before the first claude
  # generation runs — partial cleanup of a prior loop's state must not be
  # interpreted by the watchdog as a live target.
  mkdir -p "$FORGE_DIR/continuation/demo"
  printf '%s\n' "99999999" > "$FORGE_DIR/continuation/demo/claude.pid"

  FORGE_MAX_GENERATIONS=1 \
    run_loop "$FIXTURES/clean-handoff-under-budget.sh" --slug demo
  assert_exit_code 0 "$RUN_RC"
  # Either the file was overwritten with the real child PID, or it was empty
  # briefly mid-run. Either way it must NOT still hold the stale bogus value.
  local content
  content="$(cat "$FORGE_DIR/continuation/demo/claude.pid" 2>/dev/null || echo '')"
  assert_ne "99999999" "$content" \
    "loop must not leave a stale pre-existing PID value in claude.pid"
}

# ── Argument handling ────────────────────────────────────────────────────────

test_rejects_unknown_role() {
  local rc=0
  bash "$LOOP" --role bogus >/dev/null 2>&1 || rc=$?
  assert_exit_code 4 "$rc" "an unknown --role must fail with the config-error exit code"
}

test_rejects_unknown_argument() {
  local rc=0
  bash "$LOOP" --nonsense >/dev/null 2>&1 || rc=$?
  assert_exit_code 4 "$rc" "an unrecognised argument must fail with the config-error exit code"
}

test_help_flag_exits_zero() {
  local rc=0 out
  out="$(bash "$LOOP" --help 2>&1)" || rc=$?
  assert_exit_code 0 "$rc" "--help should exit 0"
  assert_contains "$out" "relaunch-loop.sh"
}

test_missing_claude_binary_fails_loud() {
  # Point FORGE_CLAUDE_BIN at something that does not exist — the loop must fail
  # with the config-error code, not crash mid-iteration.
  local rc=0
  FORGE_CLAUDE_BIN="/nonexistent/claude/bin" bash "$LOOP" --slug demo >/dev/null 2>&1 || rc=$?
  assert_exit_code 4 "$rc" "a missing claude binary must fail loud with the config-error code"
}
