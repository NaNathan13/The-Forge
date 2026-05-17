#!/usr/bin/env bash
# validate-mc.test.sh — tests for test/validate-mc.sh (flat-ledger shape).
#
# Each test stages a synthetic root with a `MISSION-CONTROL.md` under it,
# runs the validator with `--no-github` (so tests stay deterministic and
# offline-safe), and asserts pass/fail behaviour.
#
# Also runs the validator against the live repo root with `--no-github` to
# guard the "no false positives on shipped MC" acceptance criterion.
#
# Run via:  test/run-tests.sh test/validate-mc.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

VALIDATOR="$REPO_ROOT/test/validate-mc.sh"

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

# run_validator <args...>
run_validator() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --no-github "$WORKDIR" "$@" 2>&1)" || VALIDATOR_RC=$?
}

# ── Happy path ───────────────────────────────────────────────────────────────

test_passes_on_well_formed_open_marker() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 in-progress <!-- mc:open=1,2,3 --> |
'
  run_validator
  assert_eq 0 "$VALIDATOR_RC" "exit code"
  assert_contains "$VALIDATOR_OUT" "validate-mc: OK" "OK on well-formed open marker"
}

test_passes_on_well_formed_none_marker() {
  write_mc '## ⏸ Deferred

| # | Title | Why |
| --- | --- | --- |
| — | Foo | bar <!-- mc:none --> |
'
  run_validator
  assert_eq 0 "$VALIDATOR_RC" "exit code"
}

test_passes_on_empty_mc() {
  write_mc ''
  run_validator
  assert_eq 0 "$VALIDATOR_RC" "exit code"
}

test_passes_when_no_mc_file() {
  rm -f "$WORKDIR/MISSION-CONTROL.md"
  run_validator
  assert_eq 0 "$VALIDATOR_RC" "exit code"
  assert_contains "$VALIDATOR_OUT" "validate-mc: OK" "OK on missing MC"
}

test_passes_on_multiple_markers_across_rows() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 in-progress <!-- mc:open=1 --> |
| 2 | Bar | ⏳ queued <!-- mc:open=2,3 --> |
| 3 | Baz | ⏳ queued <!-- mc:open=4,5,6 --> |
'
  run_validator
  assert_eq 0 "$VALIDATOR_RC" "exit code"
  assert_contains "$VALIDATOR_OUT" "6 issue refs" "ref count"
}

# ── Marker malformations ─────────────────────────────────────────────────────

test_fails_on_open_marker_with_whitespace_in_list() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open=1, 2 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "whitespace in list" "diagnostic"
}

test_fails_on_open_marker_with_trailing_comma() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open=1,2, --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "leading or trailing comma" "diagnostic"
}

test_fails_on_open_marker_with_leading_comma() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open=,1,2 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "leading or trailing comma" "diagnostic"
}

test_fails_on_open_marker_with_double_comma() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open=1,,2 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "empty token" "diagnostic"
}

test_fails_on_open_marker_with_non_ascending_list() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open=2,1 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "not strictly ascending" "diagnostic"
}

test_fails_on_open_marker_with_duplicate_within_list() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open=1,1 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "not strictly ascending" "diagnostic"
}

test_fails_on_open_marker_with_zero_token() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open=0,1 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "non-positive-integer token" "diagnostic"
}

test_fails_on_open_marker_with_empty_list() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:open= --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "empty list" "diagnostic"
}

test_fails_on_none_marker_with_list() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:none=1 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "mc:none must not carry a list" "diagnostic"
}

test_fails_on_unknown_mc_tag() {
  write_mc '| 1 | Foo | 🚧 <!-- mc:bogus --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "unknown mc:* tag" "diagnostic"
}

test_fails_on_legacy_done_marker() {
  # mc:done is no longer permitted in the flat-ledger shape.
  write_mc '| 1 | Foo | ✅ <!-- mc:done=1,2 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "mc:done is no longer permitted" "diagnostic"
}

# ── Cross-row dedup ──────────────────────────────────────────────────────────

test_fails_on_duplicate_issue_across_rows() {
  write_mc '## 🚧 In flight

| # | Title | Status |
| --- | --- | --- |
| 1 | Foo | 🚧 <!-- mc:open=1,2 --> |
| 2 | Bar | ⏳ <!-- mc:open=2,3 --> |
'
  run_validator
  assert_ne 0 "$VALIDATOR_RC" "should fail"
  assert_contains "$VALIDATOR_OUT" "appears in multiple rows" "diagnostic"
}

# ── Documentation-block tolerance ────────────────────────────────────────────

test_ignores_markers_inside_multiline_html_comment_block() {
  # The Legend doc block uses `<!-- ... -->` to document the marker grammar.
  # Example marker tokens inside that block must NOT be parsed as real markers.
  write_mc '## Legend

<!--
  Examples — these must not be parsed as real markers:
    mc:none
    mc:open=1,2,3
-->
'
  run_validator
  assert_eq 0 "$VALIDATOR_RC" "exit code"
  assert_contains "$VALIDATOR_OUT" "0 issue refs" "no refs counted"
}

test_ignores_backtick_wrapped_marker_examples() {
  # The Legend body uses single-backtick spans to show the marker grammar.
  write_mc '## Legend

- `<!-- mc:none -->` — placeholder.
- `<!-- mc:open=N,N -->` — issue numbers tracked as open.
'
  run_validator
  assert_eq 0 "$VALIDATOR_RC" "exit code"
  assert_contains "$VALIDATOR_OUT" "0 issue refs" "no refs counted"
}

# ── Live MC ──────────────────────────────────────────────────────────────────

test_live_mc_validates_clean_offline() {
  # Run the validator against the live repo root with --no-github. This is
  # the "no false positives on shipped MC" guard.
  local out rc=0
  out="$(bash "$VALIDATOR" --no-github "$REPO_ROOT" 2>&1)" || rc=$?
  assert_eq 0 "$rc" "exit code (live MC, offline)"
  assert_contains "$out" "validate-mc: OK" "live MC passes"
}
