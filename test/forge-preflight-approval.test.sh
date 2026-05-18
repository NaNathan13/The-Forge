#!/usr/bin/env bash
# forge-preflight-approval.test.sh — pre-flight approval persistence (issue #183, slice 1c-3).
#
# Pre-flight build-queue approval is the single required human touch-point. It must
# happen in *generation 1 only* — every resumed generation skips it. The mechanism:
#
#   1. On approval, generation 1 writes gen-001.md IMMEDIATELY — before dispatching
#      any temper. The verbatim hard-constraints section carries `approved-queue:
#      true`; the approved queue table goes in the Execution-frontier dispatch-queue
#      field.
#   2. A resumed generation starts with the previous gen-NNN.md re-injected by the
#      SessionStart hook. It reads `approved-queue: true` and skips pre-flight,
#      going straight to the dispatch loop.
#   3. Because gen-001.md is written *before* the first temper, a crash between
#      approval and the first temper completing cannot lose the approval: the
#      SessionStart hook finds gen-001.md and re-injects it instead of falling back
#      to the charter (which would re-prompt the human).
#
# forge/SKILL.md is a markdown skill, not a shell script — it has no direct unit
# surface. What IS deterministically testable:
#   - the *contract* the rewritten skill documents (the `approved-queue: true`
#     flag, the "write gen-001.md immediately after approval" step, the
#     resume-skips-pre-flight rule) — asserted against the SKILL.md text.
#   - the *mechanism* those instructions drive, exercised against the real
#     continuation substrate + SessionStart hook: a gen-001.md carrying
#     `approved-queue: true` is what a resumed generation's SessionStart hook
#     re-injects, and once gen-001.md exists the charter-fallback path is
#     unreachable — the crash-between-approval-and-first-temper defence.
#
# The claude stub is not needed here: the testable surface is the SKILL.md
# contract plus continuation.sh + the SessionStart hook, all deterministic shell.
#
# Run via:  test/run-tests.sh test/forge-preflight-approval.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

SKILL="$REPO_ROOT/.claude/skills/forge/SKILL.md"
CONT="$REPO_ROOT/scripts/continuation.sh"
START_HOOK="$REPO_ROOT/.claude/hooks/overseer-session-start.sh"

# Each test gets its own temp .forge dir so continuation chains never leak. SLUG
# is fixed so the hook (which derives the slug from `cwd`) and the test agree.
setup() {
  WORKDIR="$(mktemp -d)"
  export FORGE_DIR="$WORKDIR/.forge"
  mkdir -p "$FORGE_DIR/heartbeat"
  SESSION_CWD="$WORKDIR/the-forge"
  mkdir -p "$SESSION_CWD"
  SLUG="the-forge"
  # The continuation substrate is loop-managed under forge; default every test to
  # the loop-managed marker so the SessionStart hook behaves as it does in prod.
  export OVERSEER_LOOP_MANAGED=1
  unset FORGE_RETENTION_CAP
}

teardown() {
  rm -rf "$WORKDIR"
  unset FORGE_DIR OVERSEER_LOOP_MANAGED FORGE_RETENTION_CAP
}

# Build a SessionStart-hook input JSON object for SLUG's cwd.
start_input() {
  jq -cn --arg cwd "$SESSION_CWD" \
    '{session_id:"test", transcript_path:"/dev/null", cwd:$cwd,
      hook_event_name:"SessionStart", source:"startup"}'
}

# Write gen-001.md exactly as generation 1 does on pre-flight approval: stamp the
# skeleton via the real continuation.sh, then fill the hard-constraints section
# with `approved-queue: true` and the Execution-frontier dispatch-queue field with
# the approved queue table. Returns nothing; the file is at <slug>/gen-001.md.
write_approved_gen001() {
  bash "$CONT" write --slug "$SLUG" >/dev/null
  local gen_path
  gen_path="$(bash "$CONT" latest-path --slug "$SLUG")"
  cat > "$gen_path" <<'EOF'
# Continuation — the-forge — generation 001

## Hard constraints (RESTATED VERBATIM — do not summarize)

- approved-queue: true
- One temper per generation; the overseer does not self-measure context.
- Forge does not merge (seal does); forge does not resolve conflicts inline.

## Execution frontier

- **Branch:** n/a — forge does not hold a branch; tempers do.
- **Open PR(s):** none yet
- **Last sentinel:** none yet — generation 1, pre-dispatch
- **Dispatch queue:**

  | # | Issue | Title | Slice | Blocked by | Status |
  |---|-------|-------|-------|------------|--------|
  | 1 | #95 | logic: derive-status function | logic | — | pending |
  | 2 | #96 | ui: status chip on cards | ui | #95 | pending |

- **Mid-flight state:** none — gen-001 written immediately after pre-flight approval.
- **Pending seal dispatch:** false

## Conversation summary

Operator approved the build queue above at the generation-1 pre-flight.

## Next concrete action

dispatch /forge for issue #95

## Notes / scratch

gen-001 written before the first worker — crash defence per PRD Q3.
EOF
}

# Run the SessionStart hook and capture the additionalContext it injects.
injected_context() {
  start_input | bash "$START_HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""'
}

# ── The rewritten skill documents the approval-persistence contract ──────────

test_skill_documents_approved_queue_flag() {
  assert_contains "$(cat "$SKILL")" "approved-queue: true" \
    "forge/SKILL.md must document the approved-queue: true continuation flag"
}

test_skill_places_approved_queue_flag_in_verbatim_hard_constraints() {
  # The flag must live in the hard-constraints section — the one section restated
  # VERBATIM every generation and never summarized away. If it rode in a
  # lossy-safe section it could be summarized out and the human re-prompted.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "RESTATED VERBATIM" \
    "forge/SKILL.md must describe the hard-constraints section as restated verbatim"
  # The flag and the verbatim-section language must co-occur in the hard-constraints
  # description: extract the "Hard constraints" section and assert the flag is in it.
  local hard_section
  hard_section="$(awk '/^### 1\. Hard constraints/{f=1} /^### 2\. Execution frontier/{f=0} f' "$SKILL")"
  assert_contains "$hard_section" "approved-queue: true" \
    "the approved-queue flag must be documented inside the verbatim hard-constraints section"
}

test_skill_places_approved_queue_table_in_dispatch_queue_field() {
  # The approved queue table belongs in the Execution-frontier dispatch-queue
  # field — not prose, not the conversation summary.
  local frontier_section
  frontier_section="$(awk '/^### 2\. Execution frontier/{f=1} /^### 3\. Conversation summary/{f=0} f' "$SKILL")"
  assert_contains "$frontier_section" "Dispatch queue" \
    "forge/SKILL.md's Execution-frontier section must define the Dispatch queue field"
}

test_skill_has_explicit_write_gen001_after_approval_step() {
  # AC: forge/SKILL.md must have an explicit step — generation 1 writes gen-001.md
  # immediately after pre-flight approval, before dispatching any temper.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "gen-001.md" \
    "forge/SKILL.md must name gen-001.md as the file generation 1 writes after approval"
  # The pre-flight section must instruct the write before any dispatch.
  local preflight_section
  preflight_section="$(awk '/^## Pre-flight/{f=1} /^## Dispatch Loop/{f=0} f' "$SKILL")"
  assert_contains "$preflight_section" "gen-001.md" \
    "the Pre-flight section must instruct writing gen-001.md"
  assert_contains "$preflight_section" "before dispatching" \
    "the Pre-flight section must say gen-001.md is written before dispatching any temper"
}

test_skill_documents_resume_skips_preflight() {
  # AC: on resume, forge reads approved-queue: true and skips pre-flight entirely.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "skip pre-flight" \
    "forge/SKILL.md must state resumed generations skip pre-flight"
  # The skip must be tied to reading the approved-queue flag, not an unconditional
  # "generation > 1 skips" — the flag is the signal.
  local skip_section
  skip_section="$(awk '/Skipping pre-flight on resumed generations/{f=1} /^## Dispatch Loop/{f=0} f' "$SKILL")"
  assert_contains "$skip_section" "approved-queue:" \
    "the resume-skips-pre-flight rule must key off the approved-queue flag"
}

test_skill_documents_crash_defence_rationale() {
  # AC: a crash between approval and first-temper-completion must not re-trigger
  # pre-flight. The skill must explain WHY gen-001.md is written before dispatch:
  # so a crash in that window resumes from gen-001.md, not the charter.
  local preflight_section
  preflight_section="$(awk '/^## Pre-flight/{f=1} /^## Dispatch Loop/{f=0} f' "$SKILL")"
  assert_contains "$preflight_section" "crash" \
    "the Pre-flight section must explain the crash-between-approval-and-dispatch defence"
  assert_contains "$preflight_section" "charter" \
    "the crash-defence rationale must reference the charter-fallback path it makes unreachable"
}

# ── The mechanism: a resumed generation re-injects gen-001 and skips pre-flight ─

test_resumed_generation_reinjects_approved_queue_flag() {
  # Generation 1 wrote gen-001.md carrying `approved-queue: true`. A resumed
  # generation's SessionStart hook must re-inject that file verbatim — so the
  # resumed generation sees the flag and skips pre-flight.
  write_approved_gen001
  local ctx
  ctx="$(injected_context)"
  assert_contains "$ctx" "approved-queue: true" \
    "the resumed generation's injected context must carry approved-queue: true"
}

test_resumed_generation_reinjects_approved_queue_table() {
  # The approved queue table — in the Execution-frontier dispatch-queue field —
  # must also survive the re-injection, so the resumed generation can pick up the
  # next pending slice without re-deriving the queue.
  write_approved_gen001
  local ctx
  ctx="$(injected_context)"
  assert_contains "$ctx" "Dispatch queue:" \
    "the resumed generation's injected context must carry the dispatch-queue field"
  assert_contains "$ctx" "#95" \
    "the resumed generation's injected context must carry the approved queue table rows"
}

test_gen001_written_means_charter_fallback_unreachable() {
  # The crash defence: once gen-001.md exists, the SessionStart hook's
  # charter-fallback path is unreachable. Stage BOTH a gen-001.md AND a charter,
  # then assert the hook injects the continuation, NOT the charter — a crash
  # between approval and the first temper resumes from gen-001, never re-prompts.
  printf 'CHARTER: run /forge pre-flight and ASK THE HUMAN to approve.\n' \
    > "$FORGE_DIR/charter.md"
  write_approved_gen001
  local ctx
  ctx="$(injected_context)"
  assert_contains "$ctx" "approved-queue: true" \
    "with gen-001.md present, the hook must inject the continuation"
  assert_not_contains "$ctx" "ASK THE HUMAN" \
    "with gen-001.md present, the charter-fallback path must be unreachable — no re-prompt"
}

test_no_gen001_falls_back_to_charter() {
  # The contrast case that proves the defence is real: with NO continuation
  # generation written yet (the genuine first launch), the SessionStart hook DOES
  # fall back to the charter. This is exactly the window the "write gen-001.md
  # immediately after approval" step closes — without that step, a crash here
  # would re-run pre-flight from the charter.
  printf 'CHARTER: genuine first launch — run pre-flight.\n' > "$FORGE_DIR/charter.md"
  local ctx
  ctx="$(injected_context)"
  assert_contains "$ctx" "genuine first launch" \
    "with no gen-001.md, the hook falls back to the charter — the window the immediate-write step closes"
}

test_resumed_generation_carries_next_concrete_action() {
  # A resumed generation skips pre-flight and goes straight to the dispatch loop.
  # The re-injected gen-001.md must carry the single Next-concrete-action field
  # pointing at the first pending slice, so the resumed generation knows where to
  # pick up without re-running pre-flight.
  write_approved_gen001
  local ctx
  ctx="$(injected_context)"
  assert_contains "$ctx" "Next concrete action" \
    "the re-injected continuation must carry the Next-concrete-action field"
  assert_contains "$ctx" "dispatch /forge for issue #95" \
    "the resumed generation must pick up at the first pending slice, not at pre-flight"
}
