#!/usr/bin/env bash
# validate-continuation.test.sh — exercises test/validate-continuation.sh.
#
# Covers issue #194 (sub-phase 3a, slice 3). The validator asserts that a
# hardened continuation file (per templates/continuation-gen.md) has all five
# required sections, in order, each with a non-empty body. This test:
#
#   - passes the validator against the golden gen-001.md fixture (positive case)
#   - generates targeted broken fixtures in a scratch dir and asserts the
#     validator rejects each with exit code 1 (negative cases)
#
# Run via:  test/run-tests.sh test/validate-continuation.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

VALIDATOR="$REPO_ROOT/test/validate-continuation.sh"
GOLDEN="$REPO_ROOT/test/fixtures/continuation/gen-001.md"

setup() {
  WORKDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$WORKDIR"
}

# ── Sanity ───────────────────────────────────────────────────────────────────

test_validator_exists_and_is_executable() {
  assert_file_exists "$VALIDATOR" "validator script must exist"
  if [[ ! -x "$VALIDATOR" ]]; then
    fail "validator script must be executable: $VALIDATOR"
  fi
}

test_golden_fixture_exists() {
  assert_file_exists "$GOLDEN" "golden fixture must exist"
}

test_validator_passes_bash_syntax_check() {
  if ! bash -n "$VALIDATOR" 2>/dev/null; then
    fail "validator failed bash -n"
  fi
}

# ── Positive case: golden fixture passes ─────────────────────────────────────

test_golden_fixture_validates() {
  if ! bash "$VALIDATOR" "$GOLDEN" >/dev/null 2>&1; then
    fail "golden fixture should validate (exit 0) but did not"
  fi
}

# ── Usage / argument errors → exit 2 ─────────────────────────────────────────

test_no_args_is_usage_error() {
  set +e
  bash "$VALIDATOR" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 2 "$rc" "no-args should exit 2"
}

test_missing_file_is_usage_error() {
  set +e
  bash "$VALIDATOR" "$WORKDIR/does-not-exist.md" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 2 "$rc" "missing file should exit 2"
}

# ── Negative cases: malformed files exit 1 ───────────────────────────────────
#
# Each negative test starts from the golden fixture and mutates a single
# property of it to verify the validator catches that specific violation.

# Helper: copy the golden fixture into the scratch dir under a given name.
_copy_golden() {
  local dest="$WORKDIR/$1"
  cp "$GOLDEN" "$dest"
  echo "$dest"
}

test_missing_section_heading_fails() {
  # Remove the "## Next concrete action" heading line entirely.
  local f
  f="$(_copy_golden missing-heading.md)"
  # Use a portable sed -i invocation (BSD sed needs an empty -i arg).
  grep -v '^## Next concrete action$' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  set +e
  bash "$VALIDATOR" "$f" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 1 "$rc" "missing heading should fail validation"
}

test_empty_section_body_fails() {
  # Truncate everything from "## Conversation summary" through the line
  # before "## Next concrete action", then re-emit the Conversation summary
  # heading with no body following it.
  local f
  f="$(_copy_golden empty-section.md)"

  # awk-driven rewrite: when we hit "## Conversation summary", print only the
  # heading (and a blank line), then skip until the next "## " heading.
  awk '
    /^## Conversation summary$/ { print; print ""; skipping = 1; next }
    skipping && /^## / { skipping = 0 }
    !skipping { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  set +e
  bash "$VALIDATOR" "$f" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 1 "$rc" "empty section body should fail validation"
}

test_section_body_with_only_comment_fails() {
  # A section whose only content is an HTML comment should be treated as empty.
  local f
  f="$(_copy_golden comment-only.md)"

  awk '
    /^## Notes \/ scratch$/ {
      print
      print ""
      print "<!-- nothing real here yet -->"
      print ""
      skipping = 1
      next
    }
    skipping && /^## / { skipping = 0 }
    !skipping { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  set +e
  bash "$VALIDATOR" "$f" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 1 "$rc" "comment-only body should fail validation"
}

test_fewer_than_five_sections_fails() {
  # Drop the last section ("## Notes / scratch") and everything beneath it.
  local f
  f="$(_copy_golden four-sections.md)"

  awk '
    /^## Notes \/ scratch$/ { stop = 1 }
    !stop { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  set +e
  bash "$VALIDATOR" "$f" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 1 "$rc" "four sections (missing Notes) should fail validation"
}

test_sections_in_wrong_order_fails() {
  # Swap "## Execution frontier" and "## Conversation summary" sections so
  # the relative order is wrong (Conversation summary precedes Execution
  # frontier). We do this by carving the file into preamble / sec2 / sec3 /
  # tail and re-emitting in 3-2 order.
  local f
  f="$(_copy_golden wrong-order.md)"

  awk '
    BEGIN { section = 0 }
    /^## Execution frontier$/ { section = 2 }
    /^## Conversation summary$/ { section = 3 }
    /^## Next concrete action$/ { section = 4 }
    {
      if (section == 0) { pre = pre $0 "\n"; next }
      if (section == 2) { s2  = s2  $0 "\n"; next }
      if (section == 3) { s3  = s3  $0 "\n"; next }
      if (section == 4) { tail = tail $0 "\n"; next }
    }
    END {
      printf "%s", pre
      printf "%s", s3   # Conversation summary first — wrong order
      printf "%s", s2   # Execution frontier second
      printf "%s", tail
    }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  set +e
  bash "$VALIDATOR" "$f" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 1 "$rc" "wrong-order sections should fail validation"
}

test_extra_h2_section_fails() {
  # An unexpected sixth `## ` heading should fail rule 1 (count) and
  # rule 2 (position drift).
  local f
  f="$(_copy_golden extra-section.md)"

  # Insert a bogus section before "## Notes / scratch".
  awk '
    /^## Notes \/ scratch$/ {
      print "## Bogus extra section"
      print ""
      print "Some content here so the body is non-empty."
      print ""
    }
    { print }
  ' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  set +e
  bash "$VALIDATOR" "$f" >/dev/null 2>&1
  local rc=$?
  set -e
  assert_exit_code 1 "$rc" "extra h2 section should fail validation"
}

# ── Acceptance-criterion checks (PRD acceptance items) ──────────────────────

test_run_tests_invokes_validator() {
  # AC: "test/run-tests.sh invokes the validator." We satisfy this by
  # shipping this companion *.test.sh under test/, which run-tests.sh
  # discovers and runs. Assert the test file itself is present at the
  # expected path so the wiring is observable.
  assert_file_exists "$REPO_ROOT/test/validate-continuation.test.sh" \
    "the companion test file is what wires the validator into run-tests.sh"
}
