#!/usr/bin/env bash
# validate-blocked-by.test.sh — tests for test/validate-blocked-by.sh.
#
# Each test stages a synthetic issue body file, runs the validator with
# --no-github + --body-file (so tests stay deterministic and offline-safe),
# and asserts pass/fail behaviour for shape detection.
#
# The GitHub-existence path (referenced #N is OPEN / CLOSED / missing) is
# exercised by the live `/triage` workflow, not here — `gh` is a hard
# external dependency and stubbing it would just re-test the stub. The
# shape-detection logic (where the section ends, what counts as "None",
# which `#N` refs get extracted) is what these tests cover.
#
# Run via:  test/run-tests.sh test/validate-blocked-by.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

VALIDATOR="$REPO_ROOT/test/validate-blocked-by.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  BODY_FILE="$WORKDIR/body.md"
}

teardown() {
  rm -rf "$WORKDIR"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# write_body <contents>
# Writes the given contents verbatim to $BODY_FILE.
write_body() {
  printf '%s' "$1" > "$BODY_FILE"
}

# run_validator [extra args]
# Runs the validator with --no-github + --body-file $BODY_FILE.
# Captures combined stdout+stderr into VALIDATOR_OUT and exit code into
# VALIDATOR_RC. Does not propagate exit.
run_validator() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --no-github --body-file "$BODY_FILE" "$@" 2>&1)" || VALIDATOR_RC=$?
}

# ── Happy paths (shape-only, --no-github) ────────────────────────────────────

test_passes_on_no_blocked_by_section() {
  write_body '## What to build

Stuff.

## Acceptance criteria

- [ ] Foo
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "OK"
}

test_passes_on_empty_blocked_by_section() {
  write_body '## What to build

Stuff.

## Blocked by


## Acceptance

- [ ] foo
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "OK"
}

test_passes_on_blocked_by_none_bare() {
  write_body '## Blocked by

None
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "None"
}

test_passes_on_blocked_by_none_with_prose() {
  write_body '## Blocked by

None — can start immediately.
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_passes_on_blocked_by_none_case_insensitive() {
  write_body '## Blocked by

none
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_passes_on_blocked_by_with_refs_when_no_github() {
  # With --no-github, the ref-existence check is skipped; shape-only.
  write_body '## Blocked by

#192 — sentinel validator must exist first.
#193 — and skills validator.
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "GitHub check skipped"
}

test_extracts_multiple_refs_on_same_line() {
  # Sanity: regex pulls every `#N` token, not just one per line.
  write_body '## Blocked by

Depends on #100 and #200 and #300.
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "3 ref(s) found"
}

test_section_ends_at_next_h2() {
  # A `## Acceptance` heading immediately after must terminate the section
  # — refs in later sections must NOT be pulled in.
  write_body '## Blocked by

None

## Acceptance

- [ ] Closes #999 should not be counted as a blocker.
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  # Output should say "None", not "1 ref found".
  assert_contains "$VALIDATOR_OUT" "None"
}

test_passes_on_free_prose_no_refs() {
  # Section has content but no `#N` — treated as no dependencies (not a
  # failure at triage time; slice #198 covers the strict-shape forge-preflight
  # case).
  write_body '## Blocked by

Depends on an external dependency outside this repo.
'
  run_validator
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "no #N references found"
}

# ── Argument validation ──────────────────────────────────────────────────────

test_fails_with_no_args() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 2 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "must supply"
}

test_fails_on_non_numeric_issue_number() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --no-github abc 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 2 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "must be a positive integer"
}

test_fails_on_unreadable_body_file() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --no-github --body-file /nonexistent/path/body.md 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 2 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "cannot read body file"
}

test_fails_on_body_file_missing_arg() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --body-file 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 2 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "requires a path"
}

test_fails_on_unknown_flag() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --bogus 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 2 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "unknown option"
}

test_help_flag_exits_zero() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" --help 2>&1)" || VALIDATOR_RC=$?
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "Usage"
}
