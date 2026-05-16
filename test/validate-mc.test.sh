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

# ── Sub-phase table column shape ─────────────────────────────────────────────
# The slice-1 change formalized MC's sub-phase tables with a `Blocked by`
# column. The validator must recognize the new shape, accept stub rows, and
# reject tables missing the column.

test_passes_on_well_formed_subphase_table() {
  write_mc '## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Foo | ✅ shipped | — | [`docs/prds/foo.md`](docs/prds/foo.md) | #1 <!-- mc:done=1 --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "validate-mc: OK"
}

test_fails_on_subphase_table_missing_blocked_by_column() {
  # Old shape — missing the `Blocked by` column.
  write_mc '## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | PRD | Issues |
| --- | --- | --- | --- | --- |
| 0a | Foo | ✅ shipped | [`docs/prds/foo.md`](docs/prds/foo.md) | #1 <!-- mc:done=1 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "sub-phase table header"
  assert_contains "$VALIDATOR_OUT" "Blocked by"
}

test_fails_on_subphase_table_blocked_by_in_wrong_position() {
  # `Blocked by` present but placed after PRD instead of after Status.
  write_mc '## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | PRD | Blocked by | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Foo | ✅ shipped | [`docs/prds/foo.md`](docs/prds/foo.md) | — | #1 <!-- mc:done=1 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "sub-phase table header"
}

test_accepts_stub_row_shape() {
  # `⏳ queued` / `⏳ scope-TBD` stub row with `<!-- mc:none -->` must pass.
  write_mc '## 🪐 Phase progress

### P4 — Dev Mode ░ 0/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 4a | Scope (TBD post-P3) | ⏳ scope-TBD | — | [`docs/design/dev-mode-overview.md`](docs/design/dev-mode-overview.md) (stub) | <!-- mc:none --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "validate-mc: OK"
}

test_ignores_non_subphase_tables_for_column_check() {
  # The Architectural-items table has a different header shape and must not
  # be flagged by the sub-phase column check.
  write_mc '## 🪐 Phase progress

### P0 Foundations ▓ 1/1

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 0a | Foo | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |

## 🛸 Architectural items

| # | Item | Sequence | Status | Issues |
| --- | --- | --- | --- | --- |
| A1 | Some prerequisite | 1 | ⏳ queued | — |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

# ── In-progress Blocked-by ID-existence check ────────────────────────────────

test_passes_on_inprogress_row_with_known_blocked_by_id() {
  write_mc '## 🪐 Phase progress

### P3 — Improvements ▓░ 1/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3a | Foo | ✅ shipped | — | [`docs/prds/foo.md`](docs/prds/foo.md) | #1 <!-- mc:done=1 --> |
| 3b | Bar | 🚧 in-progress | 3a | [`docs/prds/bar.md`](docs/prds/bar.md) | #2 <!-- mc:open=2 --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_passes_on_inprogress_row_with_multiple_known_ids() {
  write_mc '## 🪐 Phase progress

### P3 — Improvements ▓▓░ 2/3

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3a | Foo | ✅ shipped | — | — | #1 <!-- mc:done=1 --> |
| 3b | Bar | ✅ shipped | — | — | #2 <!-- mc:done=2 --> |
| 3c | Baz | 🚧 in-progress | 3a, 3b | [`docs/prds/baz.md`](docs/prds/baz.md) | #3 <!-- mc:open=3 --> |
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_fails_on_inprogress_row_with_unknown_blocked_by_id() {
  write_mc '## 🪐 Phase progress

### P3 — Improvements ▓░ 1/2

| # | Sub-phase | Status | Blocked by | PRD | Issues |
| --- | --- | --- | --- | --- | --- |
| 3a | Foo | ✅ shipped | — | [`docs/prds/foo.md`](docs/prds/foo.md) | #1 <!-- mc:done=1 --> |
| 3b | Bar | 🚧 in-progress | 9z | [`docs/prds/bar.md`](docs/prds/bar.md) | #2 <!-- mc:open=2 --> |
'
  run_validator
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "unknown sub-phase ID"
  assert_contains "$VALIDATOR_OUT" "9z"
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
