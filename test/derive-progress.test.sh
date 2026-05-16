#!/usr/bin/env bash
# derive-progress.test.sh — tests for scripts/derive-progress.sh.
#
# Each test stages a synthetic root with a `MISSION-CONTROL.md` under it, runs
# the script, and asserts pass/fail behaviour. The script is read-only by
# design — these tests assert no MC writes ever happen, regardless of exit
# code (it would be a hard regression for derive-progress to mutate MC).
#
# Tests run against both schema shapes:
#
#   - OLD (5 columns): `# | Sub-phase | Status | PRD | Issues` — current main.
#   - NEW (6 columns): `# | Sub-phase | Status | Blocked by | PRD | Issues` —
#     after issue #236 / PR #241 lands. Status is column 3 in both, so the
#     script's per-row counter is schema-agnostic; we exercise both shapes
#     so a future schema move doesn't silently break parsing.
#
# Run via:  test/run-tests.sh test/derive-progress.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

SCRIPT="$REPO_ROOT/scripts/derive-progress.sh"

setup() {
  WORKDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORKDIR"
}

# write_mc <contents>
write_mc() {
  printf '%s' "$1" > "$WORKDIR/MISSION-CONTROL.md"
}

# run_script
# Runs the script against $WORKDIR. Captures stdout in OUT, combined stderr in
# ERR, exit code in RC.
run_script() {
  RC=0
  local out_file err_file
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  bash "$SCRIPT" "$WORKDIR" >"$out_file" 2>"$err_file" || RC=$?
  OUT="$(cat "$out_file")"
  ERR="$(cat "$err_file")"
  rm -f "$out_file" "$err_file"
}

# ── Happy path: bars match MC ────────────────────────────────────────────────

test_passes_when_all_bars_match_new_schema() {
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓▓░ 2/3

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
| 0b | Beta | ✅ shipped | — | — | <!-- mc:done=2 --> |
| 0c | Gamma | ⏳ queued | — | — | <!-- mc:none --> |

## Next section
'
  run_script
  assert_exit_code 0 "$RC"
  assert_contains "$OUT" "### P0 Foundations ▓▓░ 2/3"
}

test_passes_when_all_bars_match_old_schema() {
  # Pre-#241 shape. Status is still column 3.
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓▓░ 2/3

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | <!-- mc:done=1 --> |
| 0b | Beta | ✅ shipped | — | <!-- mc:done=2 --> |
| 0c | Gamma | ⏳ queued | — | <!-- mc:none --> |

## Next section
'
  run_script
  assert_exit_code 0 "$RC"
  assert_contains "$OUT" "### P0 Foundations ▓▓░ 2/3"
}

# ── Drift detection ──────────────────────────────────────────────────────────

test_exits_nonzero_when_bar_disagrees() {
  # MC claims 3/3 but only 2 of 3 rows are shipped.
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓▓▓ 3/3

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
| 0b | Beta | ✅ shipped | — | — | <!-- mc:done=2 --> |
| 0c | Gamma | ⏳ queued | — | — | <!-- mc:none --> |
'
  run_script
  assert_exit_code 1 "$RC"
  # Derived bar is still printed to stdout so callers can consume it.
  assert_contains "$OUT" "### P0 Foundations ▓▓░ 2/3"
  # Drift diagnostic goes to stderr.
  assert_contains "$ERR" "drift"
  assert_contains "$ERR" "P0 Foundations"
}

test_exits_nonzero_when_question_mark_in_bar() {
  # `0/?` style — derive computes M from rows, so this should drift to `0/1`.
  write_mc '# MC

## 🪐 Phase progress

### P4 — Dev Mode ░ 0/?

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 4a | Scope (TBD) | ⏳ scope-TBD | — | — | <!-- mc:none --> |
'
  run_script
  assert_exit_code 1 "$RC"
  assert_contains "$OUT" "### P4 — Dev Mode ░ 0/1"
}

test_multiple_phases_partial_drift() {
  # One phase matches, the other drifts. Exit non-zero; both lines emitted.
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |

### P1 Future ▓▓ 2/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 1a | Foo | ✅ shipped | — | — | <!-- mc:done=2 --> |
| 1b | Bar | ⏳ queued | — | — | <!-- mc:none --> |
'
  run_script
  assert_exit_code 1 "$RC"
  assert_contains "$OUT" "### P0 Foundations ▓ 1/1"
  assert_contains "$OUT" "### P1 Future ▓░ 1/2"
  assert_contains "$ERR" "P1 Future"
  # P0 should NOT appear in drift diagnostics.
  assert_not_contains "$ERR" "P0 Foundations"
}

# ── Stub-row counting (PRD: include in M) ────────────────────────────────────

test_stub_rows_count_toward_M() {
  # Stub rows with `⏳ queued` or `⏳ scope-TBD` should count toward total.
  write_mc '# MC

## 🪐 Phase progress

### P3 Improvements ▓░ 1/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3a | Done | ✅ shipped | — | — | <!-- mc:done=1 --> |
| 3b | TBD | ⏳ scope-TBD | — | — | <!-- mc:none --> |
'
  run_script
  assert_exit_code 0 "$RC"
  assert_contains "$OUT" "### P3 Improvements ▓░ 1/2"
}

# ── Section scoping ──────────────────────────────────────────────────────────

test_ignores_non_phase_tables() {
  # The Architectural-items table (header `| # | Item | ...`) lives under a
  # different `## ` section and must not be counted.
  write_mc '# MC

## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |

## 🛸 Architectural items

### Architecture group ▓ 1/1

| # | Item | Sequence | Status | Issues |
| --- | --- | --- | --- | --- |
| A1 | Thing | n/a | ✅ done | <!-- mc:done=42 --> |
'
  run_script
  assert_exit_code 0 "$RC"
  # Only the Phase-progress phase is emitted.
  assert_contains "$OUT" "### P0 Foundations ▓ 1/1"
  assert_not_contains "$OUT" "Architecture group"
}

# ── Read-only invariant ──────────────────────────────────────────────────────

test_does_not_write_to_mc() {
  # Drifting MC. After running the script, MC contents must be byte-identical.
  local input='# MC

## 🪐 Phase progress

### P0 Foundations ▓▓▓ 3/3

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Alpha | ✅ shipped | — | — | <!-- mc:done=1 --> |
| 0b | Beta | ⏳ queued | — | — | <!-- mc:none --> |
'
  write_mc "$input"
  local before
  before="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  run_script
  local after
  after="$(cat "$WORKDIR/MISSION-CONTROL.md")"
  assert_eq "$before" "$after" "derive-progress.sh must not write to MC"
}

# ── Runtime errors ───────────────────────────────────────────────────────────

test_missing_mc_file_returns_2() {
  # No MISSION-CONTROL.md in WORKDIR → exit 2 (vs validate-mc.sh which treats
  # it as success; derive's contract is stricter because its callers — the
  # drift hook and reconcile-mc.sh — always expect MC to be present).
  run_script
  assert_exit_code 2 "$RC"
  assert_contains "$ERR" "MISSION-CONTROL.md not found"
}

test_missing_root_returns_2() {
  RC=0
  local out_file err_file
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  bash "$SCRIPT" "$WORKDIR/does-not-exist" >"$out_file" 2>"$err_file" || RC=$?
  ERR="$(cat "$err_file")"
  rm -f "$out_file" "$err_file"
  assert_exit_code 2 "$RC"
  assert_contains "$ERR" "not found or not a directory"
}

# ── Live repo guard ──────────────────────────────────────────────────────────
# Sanity-check that the script can parse the real MC without crashing
# (exit 0 or 1 is both fine — drift here just means the live MC is out of
# sync, which is a normal state until /seal runs).

test_live_repo_parses_cleanly() {
  RC=0
  local out_file err_file
  out_file="$(mktemp)"
  err_file="$(mktemp)"
  bash "$SCRIPT" "$REPO_ROOT" >"$out_file" 2>"$err_file" || RC=$?
  local out err
  out="$(cat "$out_file")"
  err="$(cat "$err_file")"
  rm -f "$out_file" "$err_file"
  # 0 or 1 acceptable; 2 = runtime error and would fail this test.
  if [[ "$RC" -ne 0 && "$RC" -ne 1 ]]; then
    fail "expected exit 0 or 1 on live repo, got $RC (stderr: $err)"
  fi
  # At least one phase line should be emitted.
  assert_contains "$out" "### "
}
