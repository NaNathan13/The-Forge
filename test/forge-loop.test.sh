#!/usr/bin/env bash
# forge-loop.test.sh — tests for forge as a loop-managed session (issue #182, slice 1c-2).
#
# forge/SKILL.md was rewritten to Option B — one temper per generation. forge runs
# under scripts/relaunch-loop.sh: each `claude -p` generation dispatches exactly one
# temper, writes the next gen-NNN.md via scripts/continuation.sh write, and emits a
# sentinel as its final .result line:
#
#   FORGE_CONTINUE  — clean per-generation handoff → the loop relaunches fresh.
#   FORGE_COMPLETE  — the dispatch queue is drained → the loop breaks, exit 0.
#
# forge/SKILL.md is a markdown skill, not a shell script, so it has no direct unit
# surface. What IS deterministically testable is the *contract* the rewritten skill
# documents, exercised against the real relaunch loop + continuation substrate:
#   - a generation that writes gen-NNN.md and emits FORGE_CONTINUE → the loop records
#     the generation and relaunches, and the continuation file is on disk.
#   - the drained-queue generation that emits FORGE_COMPLETE → the loop exits 0.
#
# The claude stub (test/stubs/claude) stands in for a forge generation; the two
# fixtures forge-generation-handoff.sh / forge-generation-complete.sh model the two
# exits. The handoff fixture runs `continuation.sh write` as the generation's real
# side effect, exactly as forge/SKILL.md's Dispatch Loop step 7 instructs.
#
# Run via:  test/run-tests.sh test/forge-loop.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

LOOP="$REPO_ROOT/scripts/relaunch-loop.sh"
CONTINUATION="$REPO_ROOT/scripts/continuation.sh"
SKILL="$REPO_ROOT/.claude/skills/forge/SKILL.md"
START_HOOK="$REPO_ROOT/.claude/hooks/forge-session-start.sh"
FIXTURES="$TEST_DIR/fixtures"

# The slug both the fixture and the loop must agree on — the fixture writes
# gen-NNN.md under it, the loop records the generation under it.
FORGE_SLUG="forge-demo"

# Each test gets its own temp .forge dir so continuation chains / generation
# counters never leak between tests. The claude stub is put first on PATH so the
# loop resolves `claude` to it.
setup() {
  WORKDIR="$(mktemp -d)"
  export FORGE_DIR="$WORKDIR/.forge"
  mkdir -p "$FORGE_DIR"
  cp "$REPO_ROOT/.forge/resilience.config" "$FORGE_DIR/resilience.config"
  export PATH="$TEST_DIR/stubs:$PATH"
  # Throttle off in tests — not measuring wall-clock pacing.
  echo 'FORGE_THROTTLE_SECONDS=0' >> "$FORGE_DIR/resilience.config"
}

teardown() {
  rm -rf "$WORKDIR"
  unset FORGE_DIR FORGE_MAX_GENERATIONS
}

# Run the loop with a fixture; capture combined output + exit code. The
# `rc=0; ... || rc=$?` idiom is mandatory under `set -e` — see test/README.md.
run_loop() {
  local fixture="$1"; shift
  RUN_RC=0
  RUN_OUT="$(CLAUDE_STUB_FIXTURE="$fixture" bash "$LOOP" "$@" 2>&1)" || RUN_RC=$?
}

# ── The rewritten skill documents the Option B contract ──────────────────────

test_skill_documents_one_temper_per_generation() {
  assert_contains "$(cat "$SKILL")" "one temper per generation" \
    "forge/SKILL.md must document the one-temper-per-generation structure"
}

test_skill_documents_forge_continue_and_complete_sentinels() {
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "FORGE_CONTINUE" \
    "forge/SKILL.md must document the FORGE_CONTINUE per-generation handoff sentinel"
  assert_contains "$body" "FORGE_COMPLETE" \
    "forge/SKILL.md must document the FORGE_COMPLETE drained-queue sentinel"
}

test_skill_writes_gen_files_via_continuation_sh() {
  assert_contains "$(cat "$SKILL")" "continuation.sh write" \
    "forge/SKILL.md must write the next generation via scripts/continuation.sh write"
}

test_skill_retires_forge_continue_md() {
  # The .claude/forge-continue.md schema migrated INTO the gen-NNN.md body — the
  # skill must say so, and must not instruct writing the old file.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "retired" \
    "forge/SKILL.md must mark .claude/forge-continue.md retired"
  assert_not_contains "$body" "writes \`.claude/forge-continue.md\` with" \
    "forge/SKILL.md must not still instruct writing .claude/forge-continue.md"
}

test_skill_removes_context_pct_self_estimation() {
  # The old measured 40%/50% "end the session" pause path is gone — the handoff
  # trigger is structural. The skill must say it does not self-measure context.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "structural" \
    "forge/SKILL.md must describe the handoff trigger as structural, not measured"
  assert_contains "$body" "does not self-measure context" \
    "forge/SKILL.md must state forge does not self-measure context"
}

test_skill_names_budget_gate_as_the_real_token_safety_net() {
  assert_contains "$(cat "$SKILL")" "budget_gate" \
    "forge/SKILL.md must document the relaunch loop's budget_gate as the real-token safety net"
}

# ── --phase charter wiring + --resume demotion (issue #184, slice 1c-4) ───────
#
# The relaunch loop runs `claude -p` with no prompt args — there is no CLI path
# for --phase. A phase-scoped run reaches generation 1 through the charter file
# (.forge/continuation/<slug>/charter.md or .forge/charter.md), which the
# SessionStart hook injects on a genuine first launch. The skill must document
# the charter mechanism, the operator-hand-written resolution, the phase-scope
# carry-forward, and the --resume / interactive-/forge demotion.

test_skill_documents_charter_phase_wiring() {
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "charter" \
    "forge/SKILL.md must document the charter file as the --phase entry path"
  assert_contains "$body" "charter.md" \
    "forge/SKILL.md must name the charter.md file"
  assert_contains "$body" "no prompt arg" \
    "forge/SKILL.md must explain why --phase needs the charter (loop runs claude -p with no prompt args)"
}

test_skill_resolves_charter_as_hand_written() {
  # Issue #184 acceptance: the build must resolve and document whether the
  # charter is hand-written or setup-generated. The resolution is hand-written.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "hand-written" \
    "forge/SKILL.md must resolve the charter as operator-hand-written"
  assert_contains "$body" "not setup-generated" \
    "forge/SKILL.md must state the charter is not generated by a setup step"
}

test_skill_carries_phase_scope_into_gen_001() {
  # The resolved phase scope must be written into gen-001.md's hard-constraints
  # section so it carries forward across generations.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "phase-scope:" \
    "forge/SKILL.md must write phase-scope into the continuation hard-constraints"
  assert_contains "$body" "hard-constraints section" \
    "forge/SKILL.md must put the phase scope in the verbatim hard-constraints section"
}

test_skill_demotes_resume_to_escape_hatch() {
  # --resume is demoted to a documented manual escape hatch; interactive /forge
  # is the no-auto-continuation fallback.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "escape hatch" \
    "forge/SKILL.md must document /forge --resume as a manual escape hatch"
  assert_contains "$body" "no auto-continuation" \
    "forge/SKILL.md must document interactive /forge as the no-auto-continuation fallback"
}

# ── Charter reaches generation 1 via the real SessionStart hook ──────────────
#
# Stub-based end-to-end: a charter.md with a `phase:` line, fed through the real
# forge-session-start.sh hook on a genuine first launch (no gen-NNN.md yet),
# must surface in the injected context — that is how --phase reaches generation
# 1. Once gen-001.md exists, the charter is unreachable (a continuation always
# wins). Each test gets the test's own temp .forge dir, so charters never leak.

# Build a SessionStart-hook input JSON object whose cwd slugifies to FORGE_SLUG.
charter_start_input() {
  jq -cn --arg cwd "$WORKDIR/$FORGE_SLUG" \
    '{session_id:"test", transcript_path:"/dev/null", cwd:$cwd,
      hook_event_name:"SessionStart", source:"startup"}'
}

test_charter_phase_reaches_generation_one() {
  # First launch, no continuation generation — a slug-scoped charter carrying a
  # `phase:` line is what generation 1 reads to scope its pre-flight.
  mkdir -p "$WORKDIR/$FORGE_SLUG" "$FORGE_DIR/continuation/$FORGE_SLUG"
  printf '# Forge charter\n\nphase: 2a\n\nRun forge scoped to sub-phase 2a.\n' \
    > "$FORGE_DIR/continuation/$FORGE_SLUG/charter.md"
  local out ctx
  out="$(charter_start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "phase: 2a" \
    "a charter's phase: line must reach generation 1 via the SessionStart hook"
}

test_charter_project_wide_phase_reaches_generation_one() {
  # The project-wide .forge/charter.md is the fallback when no slug-scoped
  # charter exists — its phase: line must still reach generation 1.
  mkdir -p "$WORKDIR/$FORGE_SLUG"
  printf 'phase: 3b\n\nProject-wide charter.\n' > "$FORGE_DIR/charter.md"
  local out ctx
  out="$(charter_start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_contains "$ctx" "phase: 3b" \
    "a project-wide charter's phase: line must reach generation 1"
}

test_charter_unreachable_once_gen_001_exists() {
  # Once gen-001.md exists, the continuation wins — the charter (and its phase:
  # scope) is no longer injected; the phase scope now lives in the gen chain.
  mkdir -p "$WORKDIR/$FORGE_SLUG"
  printf 'phase: 2a\n\nthis charter must not reappear\n' \
    > "$FORGE_DIR/charter.md"
  bash "$CONTINUATION" write --slug "$FORGE_SLUG" >/dev/null
  local out ctx
  out="$(charter_start_input | bash "$START_HOOK" 2>/dev/null)"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
  assert_not_contains "$ctx" "this charter must not reappear" \
    "once gen-001.md exists the charter must no longer be injected"
  assert_contains "$ctx" "Hard constraints" \
    "the continuation generation wins over the charter once it exists"
}

# ── Per-generation exit: FORGE_CONTINUE → loop relaunches, gen file written ───

test_forge_generation_handoff_emits_forge_continue() {
  # One forge generation writes gen-NNN.md and emits FORGE_CONTINUE. The stub
  # always emits it, so FORGE_MAX_GENERATIONS=1 is the test/CI safety net: do
  # exactly one handoff decision, then stop cleanly (exit 0).
  FORGE_MAX_GENERATIONS=1 run_loop "$FIXTURES/forge-generation-handoff.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC" "FORGE_CONTINUE should drive a clean per-generation handoff"
  assert_contains "$RUN_OUT" "recorded handoff" \
    "a forge per-generation handoff must record a generation"
}

test_forge_generation_handoff_writes_continuation_file() {
  # The handoff fixture runs `continuation.sh write` as the generation's side
  # effect — after the loop runs, gen-001.md and the `latest` symlink must exist.
  FORGE_MAX_GENERATIONS=1 run_loop "$FIXTURES/forge-generation-handoff.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC"
  assert_file_exists "$FORGE_DIR/continuation/$FORGE_SLUG/gen-001.md" \
    "the forge generation must write the next gen-NNN.md via continuation.sh write"
  assert_file_exists "$FORGE_DIR/continuation/$FORGE_SLUG/latest" \
    "continuation.sh write must repoint the latest symlink"
}

test_forge_generation_handoff_relaunches_fresh() {
  # Cap at 3 — the loop should relaunch through three forge generations, each one
  # a one-temper-per-generation handoff. The continuation chain advances each time.
  FORGE_MAX_GENERATIONS=3 run_loop "$FIXTURES/forge-generation-handoff.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC"
  local count
  count="$(grep -c "recorded handoff" <<<"$RUN_OUT")"
  assert_eq "3" "$count" "the loop must relaunch forge through three generations"
  # Three generations → continuation chain reached gen-003.
  local latest
  latest="$(bash "$CONTINUATION" latest-num --slug "$FORGE_SLUG")"
  assert_eq "003" "$latest" "three forge generations must advance the continuation chain to gen-003"
}

test_forge_generation_runs_under_loop_managed_marker() {
  # forge runs as a loop-managed session: every generation carries
  # FORGE_LOOP_MANAGED=1 so the P2 hooks treat it as loop-managed.
  local probe="$WORKDIR/env-probe"
  FORGE_MAX_GENERATIONS=1 \
    CLAUDE_STUB_ENV_PROBE="$probe" \
    run_loop "$FIXTURES/forge-generation-handoff.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC"
  assert_contains "$(cat "$probe")" "FORGE_LOOP_MANAGED=1" \
    "a loop-managed forge generation must carry the FORGE_LOOP_MANAGED marker"
}

# ── Drained-queue exit: FORGE_COMPLETE → loop breaks, exit 0 ──────────────────

test_forge_drained_queue_emits_forge_complete() {
  # The drained-queue generation dispatches seal and emits FORGE_COMPLETE — the
  # loop must read it and break with exit 0.
  run_loop "$FIXTURES/forge-generation-complete.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC" "FORGE_COMPLETE must make the relaunch loop exit 0"
  assert_contains "$RUN_OUT" "FORGE_COMPLETE" "the loop must recognise the drained-queue sentinel"
}

test_forge_drained_queue_does_not_relaunch() {
  # FORGE_COMPLETE is terminal — the loop breaks, it does not record another
  # generation or relaunch.
  run_loop "$FIXTURES/forge-generation-complete.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC"
  assert_not_contains "$RUN_OUT" "recorded handoff" \
    "the drained-queue generation is terminal — no further generation is recorded"
}

# ── Handoff then complete: a realistic two-generation forge run ───────────────

test_forge_handoff_then_complete_full_sequence() {
  # Generation 1 hands off (FORGE_CONTINUE, writes gen-001.md); the loop
  # relaunches; generation 2 is the drained-queue generation (FORGE_COMPLETE).
  # Modelled by running the loop once per fixture against a shared continuation
  # chain — the loop is per-generation, the fixtures are per-generation.
  FORGE_MAX_GENERATIONS=1 run_loop "$FIXTURES/forge-generation-handoff.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC" "generation 1 hands off cleanly"
  assert_file_exists "$FORGE_DIR/continuation/$FORGE_SLUG/gen-001.md"

  run_loop "$FIXTURES/forge-generation-complete.sh" --slug "$FORGE_SLUG"
  assert_exit_code 0 "$RUN_RC" "the drained-queue generation completes the run"
  assert_contains "$RUN_OUT" "FORGE_COMPLETE"
}
