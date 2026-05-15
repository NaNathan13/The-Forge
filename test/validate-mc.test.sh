#!/usr/bin/env bash
# validate-mc.test.sh — tests for test/validate-mc.sh.
#
# Each test stages a synthetic root with a `MISSION-CONTROL.md` under it,
# runs the validator with `--no-github` (so tests stay deterministic and
# offline-safe), and asserts pass/fail behaviour.
#
# Also runs the validator against the live repo root with `--no-github` to
# guard the "no false positives on shipped MC" acceptance criterion. The
# GitHub-existence path is exercised only by the live CI workflow, not here.
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

# ── Helpers ──────────────────────────────────────────────────────────────────

# write_mc <contents>
# Writes the given contents verbatim to $WORKDIR/MISSION-CONTROL.md.
write_mc() {
  printf '%s' "$1" > "$WORKDIR/MISSION-CONTROL.md"
}

# run_validator <args...>
# Runs the validator against $WORKDIR with --no-github (plus any extra args).
# Captures combined stdout+stderr into VALIDATOR_OUT and exit code into
# VALIDATOR_RC. Does not propagate exit.
run_validator() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --no-github "$WORKDIR" "$@" 2>&1)" || VALIDATOR_RC=$?
}

# ── Happy path ───────────────────────────────────────────────────────────────

test_passes_on_well_formed_open_marker() {
  write_mc '| 1a | Foo | ⏳ | — | #1, #2, #3 <!-- mc:open=1,2,3 --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "validate-mc: OK"
}

test_passes_on_well_formed_done_marker() {
  write_mc '| 1a | Foo | ✅ | — | #10, #20 <!-- mc:done=10,20 --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_passes_on_mc_none() {
  write_mc '| 1a | Foo | ⏳ | — | <!-- mc:none --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_passes_on_missing_mc_file() {
  # No MISSION-CONTROL.md present → no-op success.
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "no MISSION-CONTROL.md"
}

test_passes_on_multiple_markers_across_rows() {
  write_mc '| 1a | Foo | ✅ | — | #1, #2 <!-- mc:done=1,2 --> |
| 1b | Bar | ⏳ | — | #5, #7, #9 <!-- mc:open=5,7,9 --> |
| 1c | Baz | ⏳ | — | <!-- mc:none --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_ignores_examples_in_multiline_html_comment() {
  # The legend block in real MISSION-CONTROL.md wraps marker examples in a
  # `<!-- ... -->` documentation block. Validator must not parse those as
  # real markers.
  write_mc '<!--
  Marker grammar:
    <!-- mc:none -->            no issues filed yet
    <!-- mc:open=N,N -->        open
    <!-- mc:done=N,N -->        done
-->

| 1a | Foo | ⏳ | — | #1 <!-- mc:open=1 --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_ignores_backtick_wrapped_examples() {
  # The legend at the bottom of MISSION-CONTROL.md uses single-backtick spans
  # to quote marker shapes. Validator must strip those before parsing.
  write_mc '| 1a | Foo | ⏳ | — | #1 <!-- mc:open=1 --> |

Legend:
- `<!-- mc:none -->` — no issues filed yet
- `<!-- mc:open=N,N -->` — open
- `<!-- mc:done=N,N -->` — done
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

# ── Failure modes ────────────────────────────────────────────────────────────

test_fails_on_trailing_comma() {
  write_mc '| 1a | Foo | ⏳ | — | #1, #2 <!-- mc:open=1,2, --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "trailing comma"
}

test_fails_on_unsorted_list() {
  write_mc '| 1a | Foo | ⏳ | — | #2, #1 <!-- mc:open=2,1 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "ascending"
}

test_fails_on_space_in_list() {
  write_mc '| 1a | Foo | ⏳ | — | #1, #2 <!-- mc:open=1, 2 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "whitespace"
}

test_fails_on_leading_comma() {
  write_mc '| 1a | Foo | ⏳ | — | #1, #2 <!-- mc:open=,1,2 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "leading or trailing comma"
}

test_fails_on_empty_open_list() {
  write_mc '| 1a | Foo | ⏳ | — | <!-- mc:open= --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "empty"
}

test_fails_on_mc_none_with_list() {
  write_mc '| 1a | Foo | ⏳ | — | <!-- mc:none=1,2 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "mc:none must not carry a list"
}

test_fails_on_non_integer_token() {
  write_mc '| 1a | Foo | ⏳ | — | <!-- mc:open=1,abc,3 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "non-positive-integer"
}

test_fails_on_duplicate_across_rows() {
  write_mc '| 1a | Foo | ✅ | — | #1, #2 <!-- mc:done=1,2 --> |
| 1b | Bar | ⏳ | — | #2, #3 <!-- mc:open=2,3 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "multiple rows"
}

test_fails_on_unknown_mc_tag() {
  write_mc '| 1a | Foo | ⏳ | — | <!-- mc:bogus=1 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "unknown mc:* tag"
}

# ── Argument handling ────────────────────────────────────────────────────────

test_bad_root_arg_returns_2() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --no-github /no/such/path 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 2 "$VALIDATOR_RC"
}

test_unknown_flag_returns_2() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --bogus 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 2 "$VALIDATOR_RC"
}

# ── Live-repo guard ──────────────────────────────────────────────────────────

test_no_false_positives_on_shipped_mc() {
  # Run validator with --no-github against the actual repo. The shape of
  # MISSION-CONTROL.md on main must validate without false positives. The
  # github-existence path is exercised by the live CI workflow, not this test
  # (it requires authenticated gh and would be flaky in offline runs).
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --no-github "$REPO_ROOT" 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 0 "$VALIDATOR_RC" "shipped MISSION-CONTROL.md must validate"
  assert_contains "$VALIDATOR_OUT" "validate-mc: OK"
}
