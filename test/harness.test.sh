#!/usr/bin/env bash
# harness.test.sh — self-test for The Forge's test harness.
#
# Proves the two pieces of the harness work, so the component slices (P2 slices 4/5/6/7)
# can build on them with confidence:
#   - the bash test runner (run-tests.sh) — discovers + runs test_* functions, and the
#     assert.sh helpers pass on truth and fail on falsehood;
#   - the `claude` stub (test/stubs/claude) — emits well-formed `claude -p
#     --output-format json` output with a configurable `.result`, `.usage`, and exit code.
#
# Run via:  test/run-tests.sh test/harness.test.sh
# (or just  test/run-tests.sh  — it is discovered automatically)

# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

CLAUDE_STUB="$TEST_DIR/stubs/claude"

# ── assert.sh sanity ─────────────────────────────────────────────────────────

test_assert_eq_passes_on_equal() {
  assert_eq "abc" "abc"
}

test_assert_eq_fails_on_unequal() {
  # Invert: the assertion *should* return non-zero here.
  if assert_eq "abc" "xyz" 2>/dev/null; then
    fail "assert_eq should have failed on unequal values"
  fi
}

test_assert_contains_matches_substring() {
  assert_contains "the FORGEMASTER_CONTINUE sentinel" "FORGEMASTER_CONTINUE"
}

test_assert_not_contains_rejects_substring() {
  if assert_not_contains "has FORGEMASTER_COMPLETE here" "FORGEMASTER_COMPLETE" 2>/dev/null; then
    fail "assert_not_contains should have failed when substring present"
  fi
}

test_assert_exit_code_compares() {
  assert_exit_code 0 0
  if assert_exit_code 0 1 2>/dev/null; then
    fail "assert_exit_code should have failed on mismatch"
  fi
}

test_assert_file_exists_and_absent() {
  local tmp
  tmp="$(mktemp)"
  assert_file_exists "$tmp"
  rm -f "$tmp"
  assert_file_absent "$tmp"
}

# ── claude stub: defaults ────────────────────────────────────────────────────

test_stub_default_emits_valid_json() {
  local out
  out="$("$CLAUDE_STUB" -p --output-format json "ignored prompt")"
  # Must be parseable JSON of type "result".
  local type
  type="$(jq -r '.type' <<<"$out")"
  assert_eq "result" "$type" "stub output should be a result message"
}

test_stub_default_result_and_exit() {
  local out rc
  out="$("$CLAUDE_STUB" -p --output-format json)"
  rc=$?
  assert_exit_code 0 "$rc" "default stub should exit 0"
  assert_eq "stub result" "$(jq -r '.result' <<<"$out")"
}

test_stub_default_usage_is_zeroed() {
  local out
  out="$("$CLAUDE_STUB")"
  assert_eq "0" "$(jq -r '.usage.input_tokens' <<<"$out")"
  assert_eq "0" "$(jq -r '.usage.output_tokens' <<<"$out")"
}

# ── claude stub: configurable .result (sentinel strings) ─────────────────────

test_stub_result_carries_forge_continue_sentinel() {
  local out result
  out="$(CLAUDE_STUB_RESULT="handed off cleanly FORGEMASTER_CONTINUE" "$CLAUDE_STUB")"
  result="$(jq -r '.result' <<<"$out")"
  assert_contains "$result" "FORGEMASTER_CONTINUE"
}

test_stub_result_carries_forge_complete_sentinel() {
  local out result
  out="$(CLAUDE_STUB_RESULT="work done FORGEMASTER_COMPLETE" "$CLAUDE_STUB")"
  result="$(jq -r '.result' <<<"$out")"
  assert_contains "$result" "FORGEMASTER_COMPLETE"
}

# ── claude stub: configurable exit code ──────────────────────────────────────
#
# Note the `rc=0; cmd || rc=$?` idiom below. A test function runs under `set -e`, so a
# bare `cmd; rc=$?` would abort the test the instant `cmd` exits non-zero — before
# `rc=$?` ran. Pre-seed `rc=0` and capture the failure with `|| rc=$?`. This idiom is
# documented in test/README.md; it is the single most common harness gotcha.

test_stub_nonzero_exit_is_honored() {
  local rc=0
  CLAUDE_STUB_EXIT=37 "$CLAUDE_STUB" >/dev/null 2>&1 || rc=$?
  assert_exit_code 37 "$rc" "stub should exit with CLAUDE_STUB_EXIT"
}

test_stub_still_emits_json_on_nonzero_exit() {
  # A crash-simulating non-zero exit still prints the JSON object first — the loop
  # under test reads exit code first, but the output must remain well-formed.
  local out
  out="$(CLAUDE_STUB_EXIT=1 "$CLAUDE_STUB" || true)"
  assert_eq "result" "$(jq -r '.type' <<<"$out")"
}

test_stub_rejects_non_integer_exit() {
  local rc=0
  CLAUDE_STUB_EXIT="not-a-number" "$CLAUDE_STUB" >/dev/null 2>&1 || rc=$?
  # EX_USAGE — a malformed knob fails loud, not weird.
  assert_exit_code 64 "$rc"
}

# ── claude stub: configurable .usage ─────────────────────────────────────────

test_stub_usage_object_override() {
  local out
  out="$(CLAUDE_STUB_USAGE='{"input_tokens":195000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}' "$CLAUDE_STUB")"
  assert_eq "195000" "$(jq -r '.usage.input_tokens' <<<"$out")"
  assert_eq "5000" "$(jq -r '.usage.output_tokens' <<<"$out")"
}

test_stub_usage_per_field_knobs() {
  local out
  out="$(CLAUDE_STUB_INPUT_TOKENS=120000 CLAUDE_STUB_OUTPUT_TOKENS=4000 "$CLAUDE_STUB")"
  assert_eq "120000" "$(jq -r '.usage.input_tokens' <<<"$out")"
  assert_eq "4000" "$(jq -r '.usage.output_tokens' <<<"$out")"
}

test_stub_rejects_invalid_usage_json() {
  local rc=0
  CLAUDE_STUB_USAGE='{not valid json' "$CLAUDE_STUB" >/dev/null 2>&1 || rc=$?
  # EX_DATAERR — jq fails to assemble, stub surfaces it.
  assert_exit_code 65 "$rc"
}

# ── claude stub: fixture file support ────────────────────────────────────────

test_stub_loads_fixture_file() {
  local fixture out
  fixture="$(mktemp)"
  cat > "$fixture" <<'EOF'
CLAUDE_STUB_RESULT="from fixture FORGEMASTER_CONTINUE"
CLAUDE_STUB_USAGE='{"input_tokens":150000,"output_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=0
EOF
  out="$(CLAUDE_STUB_FIXTURE="$fixture" "$CLAUDE_STUB")"
  rm -f "$fixture"
  assert_contains "$(jq -r '.result' <<<"$out")" "FORGEMASTER_CONTINUE"
  assert_eq "150000" "$(jq -r '.usage.input_tokens' <<<"$out")"
}

test_stub_env_overrides_fixture() {
  local fixture out
  fixture="$(mktemp)"
  echo 'CLAUDE_STUB_RESULT="fixture value"' > "$fixture"
  # Env var set on the same invocation should win over the fixture.
  out="$(CLAUDE_STUB_FIXTURE="$fixture" CLAUDE_STUB_RESULT="env wins" "$CLAUDE_STUB")"
  rm -f "$fixture"
  assert_eq "env wins" "$(jq -r '.result' <<<"$out")"
}

test_stub_missing_fixture_fails_loud() {
  local rc=0
  CLAUDE_STUB_FIXTURE="/nonexistent/fixture/path" "$CLAUDE_STUB" >/dev/null 2>&1 || rc=$?
  assert_exit_code 64 "$rc"
}

test_stub_honors_explicit_empty_result() {
  # A crash fixture sets CLAUDE_STUB_RESULT="" — a crashed generation never reaches a
  # sentinel. An explicitly-set empty string must NOT fall back to the default.
  local out
  out="$(CLAUDE_STUB_RESULT="" "$CLAUDE_STUB")"
  assert_eq "" "$(jq -r '.result' <<<"$out")" "explicit empty .result must be honored"
}

test_stub_crash_fixture_shape() {
  # The shipped crash fixture: non-zero exit, empty .result, is_error true.
  local out rc=0
  out="$(CLAUDE_STUB_FIXTURE="$TEST_DIR/fixtures/crash-nonzero-exit.sh" "$CLAUDE_STUB")" || rc=$?
  assert_exit_code 1 "$rc" "crash fixture should exit non-zero"
  assert_eq "" "$(jq -r '.result' <<<"$out")" "crash fixture .result should be empty"
  assert_eq "true" "$(jq -r '.is_error' <<<"$out")"
}

# ── runner: discovery + execution end-to-end ─────────────────────────────────
# A meta-test: drive run-tests.sh against a throwaway test file and confirm it
# reports pass/fail correctly and sets its exit code accordingly.

test_runner_reports_passing_file_green() {
  local tmpdir rc=0 out
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/green.test.sh" <<'EOF'
test_trivially_true() { return 0; }
EOF
  out="$(bash "$TEST_DIR/run-tests.sh" "$tmpdir/green.test.sh" 2>&1)" || rc=$?
  rm -rf "$tmpdir"
  assert_exit_code 0 "$rc" "runner should exit 0 when all tests pass"
  assert_contains "$out" "PASS"
}

test_runner_reports_failing_file_red() {
  local tmpdir rc=0 out
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/red.test.sh" <<'EOF'
test_always_fails() { return 1; }
EOF
  out="$(bash "$TEST_DIR/run-tests.sh" "$tmpdir/red.test.sh" 2>&1)" || rc=$?
  rm -rf "$tmpdir"
  assert_exit_code 1 "$rc" "runner should exit 1 when a test fails"
  assert_contains "$out" "FAIL"
}

test_runner_runs_setup_before_each_test() {
  # A test that only passes if `setup` ran first proves the lifecycle hook fires.
  local tmpdir rc=0
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/lifecycle.test.sh" <<'EOF'
setup() { SETUP_DID_RUN=1; }
test_setup_ran_before_test() { [[ "${SETUP_DID_RUN:-0}" == "1" ]] || return 1; }
EOF
  bash "$TEST_DIR/run-tests.sh" "$tmpdir/lifecycle.test.sh" >/dev/null 2>&1 || rc=$?
  rm -rf "$tmpdir"
  assert_exit_code 0 "$rc" "setup should run before each test_* function"
}

test_runner_isolates_state_between_files() {
  # A var exported by one test file must not be visible to the next — each file runs
  # in its own subshell. File A sets a var; file B fails if it can see it.
  local tmpdir rc=0
  tmpdir="$(mktemp -d)"
  cat > "$tmpdir/a.test.sh" <<'EOF'
LEAKED_VAR=leaked
test_a_sets_a_var() { return 0; }
EOF
  cat > "$tmpdir/b.test.sh" <<'EOF'
test_b_cannot_see_a_var() { [[ -z "${LEAKED_VAR:-}" ]] || return 1; }
EOF
  bash "$TEST_DIR/run-tests.sh" "$tmpdir/a.test.sh" "$tmpdir/b.test.sh" >/dev/null 2>&1 || rc=$?
  rm -rf "$tmpdir"
  assert_exit_code 0 "$rc" "state from one test file must not leak into the next"
}

test_runner_errors_on_no_test_functions() {
  local tmpdir rc=0
  tmpdir="$(mktemp -d)"
  echo '# a file with no test_ functions' > "$tmpdir/empty.test.sh"
  bash "$TEST_DIR/run-tests.sh" "$tmpdir/empty.test.sh" >/dev/null 2>&1 || rc=$?
  rm -rf "$tmpdir"
  assert_exit_code 1 "$rc" "a test file with no test_* functions is a failure"
}

test_runner_errors_on_missing_file() {
  local rc=0
  bash "$TEST_DIR/run-tests.sh" "/nonexistent/path.test.sh" >/dev/null 2>&1 || rc=$?
  assert_exit_code 2 "$rc" "runner should exit 2 when given a missing file"
}
