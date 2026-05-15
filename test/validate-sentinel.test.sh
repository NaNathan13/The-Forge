#!/usr/bin/env bash
# validate-sentinel.test.sh — exercises test/validate-sentinel.sh.
#
# Runs the validator against each golden fixture under test/fixtures/sentinel/
# (one per `status` value — success / continue / needs_human / fail) and
# checks a handful of headline failure modes the validator must reject:
# malformed JSON, missing required fields, multi-line input, empty input,
# un-escaped quote in friction. The negative cases are what make the
# friction-text guard meaningful — they are the silent breakage that this
# validator exists to catch.
#
# This file follows the run-tests.sh contract: every `test_*` function is a
# test case, sourced into a subshell with `set -e` so a failed assertion
# aborts the test at first failure.

# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

VALIDATOR="$REPO_ROOT/test/validate-sentinel.sh"
FIXTURES="$REPO_ROOT/test/fixtures/sentinel"

# Run the validator and capture the exit code without tripping set -e. The
# `|| rc=$?` idiom mirrors how the existing test files (continuation.test.sh,
# hooks.test.sh, etc.) capture exit codes from commands expected to fail.
_run_validator() {
  rc=0
  "$VALIDATOR" "$@" >/dev/null 2>&1 || rc=$?
}

_run_validator_stdin() {
  rc=0
  echo "$1" | "$VALIDATOR" >/dev/null 2>&1 || rc=$?
}

# ── Positive: every golden fixture must validate ─────────────────────────────

test_fixture_success_validates() {
  _run_validator "$FIXTURES/success.txt"
  assert_exit_code 0 "$rc" "success fixture should validate"
}

test_fixture_continue_validates() {
  _run_validator "$FIXTURES/continue.txt"
  assert_exit_code 0 "$rc" "continue fixture should validate"
}

test_fixture_needs_human_validates() {
  _run_validator "$FIXTURES/needs_human.txt"
  assert_exit_code 0 "$rc" "needs_human fixture should validate"
}

test_fixture_fail_validates() {
  _run_validator "$FIXTURES/fail.txt"
  assert_exit_code 0 "$rc" "fail fixture should validate"
}

# ── Positive: stdin path works the same as file path ─────────────────────────

test_stdin_accepts_sentinel_line() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"success","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 0 "$rc" "stdin sentinel line should validate"
}

test_stdin_accepts_bare_json_without_prefix() {
  # Forge sees the line with the `TEMPER:RESULT ` prefix already stripped; the
  # validator should accept either form so it is callable from both sides of
  # the parse.
  _run_validator_stdin '{"v":1,"status":"success","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 0 "$rc" "bare JSON (no prefix) should validate"
}

# ── Positive: `"v":1` is accepted (current protocol version) ─────────────────

test_accepts_v1_field_present() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"success","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 0 "$rc" "v:1 should validate"
}

# ── Positive: back-compat — absent `v` still validates ───────────────────────
#
# The protocol gained `"v":1` as an additive field. For one back-compat
# release a sentinel WITHOUT `v` still validates, so a temper that has not
# been updated yet does not break the forge run.
test_accepts_absent_v_field_back_compat() {
  _run_validator_stdin 'TEMPER:RESULT {"status":"success","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 0 "$rc" "absent v field should validate (back-compat)"
}

# ── Negative: `v` present but wrong type or value ────────────────────────────

test_rejects_v_field_wrong_type() {
  _run_validator_stdin 'TEMPER:RESULT {"v":"1","status":"success","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 1 "$rc" "v as string should be rejected"
}

test_rejects_v_field_unknown_version() {
  # v=2 is not a currently-defined protocol version; the validator must
  # reject it loudly rather than silently accept a future schema it has not
  # been taught yet.
  _run_validator_stdin 'TEMPER:RESULT {"v":2,"status":"success","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 1 "$rc" "v=2 should be rejected (only v=1 currently defined)"
}

# ── Negative: empty input ────────────────────────────────────────────────────

test_rejects_empty_input() {
  rc=0
  echo -n "" | "$VALIDATOR" >/dev/null 2>&1 || rc=$?
  assert_exit_code 1 "$rc" "empty input should be rejected"
}

# ── Negative: malformed JSON ─────────────────────────────────────────────────

test_rejects_malformed_json() {
  _run_validator_stdin 'TEMPER:RESULT {not valid json}'
  assert_exit_code 1 "$rc" "malformed JSON should be rejected"
}

# This is the headline bug class the validator exists to catch: an un-escaped
# quote in the friction field, which silently breaks the entire forge run.
test_rejects_unescaped_quote_in_friction() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"needs_human","issue":1,"pr":2,"branch":"b","tokens":null,"friction":"he said "hi" oops","reason":"friction"}'
  assert_exit_code 1 "$rc" "un-escaped quote in friction should be rejected"
}

# ── Negative: missing required fields ────────────────────────────────────────

test_rejects_missing_friction_field() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"success","issue":1,"pr":2,"branch":"b","tokens":null}'
  assert_exit_code 1 "$rc" "missing friction field should be rejected"
}

test_rejects_continue_without_continuation_file() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"continue","issue":1,"pr":null,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 1 "$rc" "continue without continuation_file should be rejected"
}

test_rejects_needs_human_without_reason() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"needs_human","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 1 "$rc" "needs_human without reason should be rejected"
}

test_rejects_fail_without_reason() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"fail","issue":1,"pr":null,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 1 "$rc" "fail without reason should be rejected"
}

# ── Negative: invalid status value ───────────────────────────────────────────

test_rejects_unknown_status() {
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"weird","issue":1,"pr":null,"branch":"b","tokens":null,"friction":null}'
  assert_exit_code 1 "$rc" "unknown status value should be rejected"
}

# ── Negative: multi-line input ───────────────────────────────────────────────

test_rejects_multiline_input() {
  rc=0
  printf 'TEMPER:RESULT {"v":1,"status":"success","issue":1,"pr":2,"branch":"b","tokens":null,"friction":null}\nextra line\n' \
    | "$VALIDATOR" >/dev/null 2>&1 || rc=$?
  assert_exit_code 1 "$rc" "multi-line input should be rejected"
}

# ── Negative: wrong field types ──────────────────────────────────────────────

test_rejects_non_null_tokens() {
  # Tokens must be null — Forge backfills it. A non-null value from temper is
  # almost always a bug (a stale value, a wrong field, etc.).
  _run_validator_stdin 'TEMPER:RESULT {"v":1,"status":"success","issue":1,"pr":2,"branch":"b","tokens":1234,"friction":null}'
  assert_exit_code 1 "$rc" "non-null tokens should be rejected"
}

test_rejects_top_level_array() {
  _run_validator_stdin 'TEMPER:RESULT [1,2,3]'
  assert_exit_code 1 "$rc" "top-level array should be rejected"
}
