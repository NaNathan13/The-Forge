#!/usr/bin/env bash
# mission-control-drift.test.sh — tests for .claude/hooks/mission-control-drift.sh.
#
# Scope of this file (issue #237): exercise the new progress-bar drift
# surfacing wired into the hook. The pre-existing closed-issue drift and the
# /examine nudge are out of scope here — they live in this hook but were
# never under test, and slice #239 will widen the hook with more drift cases.
# Adding bare-bones coverage of just the new wiring keeps this file scoped
# to slice #237's diff.
#
# Strategy: the hook runs from a working tree's repo root (it uses
# `git rev-parse --show-toplevel`). We stage a fake repo under $WORKDIR with a
# `.git` placeholder so `git rev-parse` succeeds, a copy of `derive-progress.sh`
# at `scripts/derive-progress.sh`, and a synthetic `MISSION-CONTROL.md`. We
# then invoke the hook with `cwd` set to that fake root.
#
# The hook always exits 0 (it must never block session start). We assert on
# its stdout to verify drift surfacing.
#
# Run via:  test/run-tests.sh test/mission-control-drift.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

HOOK="$REPO_ROOT/.claude/hooks/mission-control-drift.sh"
DERIVE="$REPO_ROOT/scripts/derive-progress.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  # Initialise a real git repo so `git rev-parse --show-toplevel` resolves
  # to $WORKDIR. We don't need any commits.
  (cd "$WORKDIR" && git init -q >/dev/null)
  mkdir -p "$WORKDIR/scripts"
  cp "$DERIVE" "$WORKDIR/scripts/derive-progress.sh"
  chmod +x "$WORKDIR/scripts/derive-progress.sh"
}

teardown() {
  rm -rf "$WORKDIR"
}

write_mc() {
  printf '%s' "$1" > "$WORKDIR/MISSION-CONTROL.md"
}

# run_hook
# Runs the hook from inside $WORKDIR. Captures stdout+stderr and exit code.
run_hook() {
  RC=0
  HOOK_OUT="$(cd "$WORKDIR" && bash "$HOOK" 2>&1)" || RC=$?
}

# ── Drift surfaced when bars disagree ────────────────────────────────────────

test_surfaces_progress_bar_drift() {
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓▓▓ 3/3

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
| 0b | Beta | ⏳ queued | — | — | <!-- mc:none --> |
'
  run_hook
  # Hook always exits 0.
  assert_exit_code 0 "$RC"
  # Drift line is surfaced with the MC banner prefix.
  assert_contains "$HOOK_OUT" "📊 Mission Control:"
  assert_contains "$HOOK_OUT" "P0 Foundations"
  assert_contains "$HOOK_OUT" "drift"
}

# ── Silent when bars match ───────────────────────────────────────────────────

test_silent_when_bars_match() {
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  # No progress-bar drift line.
  assert_not_contains "$HOOK_OUT" "drift in"
}

# ── Hook tolerates missing derive-progress.sh ────────────────────────────────

test_silent_when_derive_script_absent() {
  # Remove the script — hook should fall through silently rather than crash.
  rm -f "$WORKDIR/scripts/derive-progress.sh"
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
'
  run_hook
  assert_exit_code 0 "$RC"
  assert_not_contains "$HOOK_OUT" "drift"
}
