#!/usr/bin/env bash
# validate-prd-terms.test.sh — tests for scripts/validate-prd-terms.sh
#
# Covers the /inscribe hard-gate check logic (term lookup, halt-on-undefined,
# resume-after-add) per issue #266 acceptance.

source "$TEST_DIR/lib/assert.sh"

SCRIPT="$REPO_ROOT/scripts/validate-prd-terms.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  CONTEXT_FILE="$WORKDIR/CONTEXT.md"
  PRD_FILE="$WORKDIR/prd.md"

  # Minimal canonical glossary fixture — matches the **Term**: header shape
  # used by the real CONTEXT.md.
  cat > "$CONTEXT_FILE" <<'EOF'
# CONTEXT — Test fixture

## Language

**Ponder**: The planning phase.

**Forge**: The build phase worker.

**Slice**: One triaged GitHub issue.

**Dev mode**: One of fast / balanced / tdd.
EOF
}

teardown() {
  rm -rf "$WORKDIR"
}

# ---------------------------------------------------------------------------
# Usage / error-path tests
# ---------------------------------------------------------------------------

test_missing_args_exits_2() {
  set +e
  output="$("$SCRIPT" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 2 "$ec"
  assert_contains "$output" "usage:"
}

test_missing_prd_file_exits_2() {
  set +e
  output="$("$SCRIPT" "$WORKDIR/does-not-exist.md" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 2 "$ec"
  assert_contains "$output" "cannot read PRD"
}

test_missing_context_file_exits_2() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Ponder**: canonical.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$WORKDIR/no-context.md" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 2 "$ec"
  assert_contains "$output" "cannot read CONTEXT.md"
}

test_no_terms_section_exits_2() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Why

No terms section here.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 2 "$ec"
  assert_contains "$output" "no '## Terms used' section"
}

# ---------------------------------------------------------------------------
# Term-lookup tests (the core of the hard-gate)
# ---------------------------------------------------------------------------

test_all_terms_canon_and_defined_passes() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Ponder**: see glossary.
- **Forge**: see glossary.
- **Slice**: see glossary.

## Some other section
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 0 "$ec"
  assert_contains "$output" "ok: 3 canon, 0 non-canon"
}

test_single_undefined_term_halts() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Ponder**: see glossary.
- **Nebula**: a brand-new term not in CONTEXT.md.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 1 "$ec"
  assert_contains "$output" "undefined: Nebula"
  assert_contains "$output" "fail: 1 undefined"
}

test_multiple_undefined_terms_all_listed() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Ponder**: see glossary.
- **Nebula**: undefined.
- **Pulsar**: undefined.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 1 "$ec"
  assert_contains "$output" "undefined: Nebula"
  assert_contains "$output" "undefined: Pulsar"
  assert_contains "$output" "fail: 2 undefined"
}

# ---------------------------------------------------------------------------
# Non-canon escape hatch — terms marked non-canon are not checked
# ---------------------------------------------------------------------------

test_non_canon_term_skipped() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Ponder**: see glossary.
- **Nebula**: non-canon — local term for this PRD only.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 0 "$ec"
  assert_contains "$output" "ok: 1 canon, 1 non-canon"
}

test_non_canon_case_insensitive() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Nebula**: Non-Canon — capitalization should not matter.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 0 "$ec"
  assert_contains "$output" "ok: 0 canon, 1 non-canon"
}

# ---------------------------------------------------------------------------
# Resume-after-add — simulates the operator adding the missing glossary
# entry, then re-running the gate
# ---------------------------------------------------------------------------

test_resume_after_add_passes() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Nebula**: a new term.
EOF
  # First run — fails because Nebula is not in CONTEXT.md.
  set +e
  "$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" >/dev/null 2>&1
  ec1=$?
  set -e
  assert_exit_code 1 "$ec1"

  # Operator adds the term to CONTEXT.md.
  cat >> "$CONTEXT_FILE" <<'EOF'

**Nebula**: a new term, now canonical.
EOF

  # Second run — passes.
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec2=$?
  set -e
  assert_exit_code 0 "$ec2"
  assert_contains "$output" "ok: 1 canon, 0 non-canon"
}

# ---------------------------------------------------------------------------
# Parser edge cases
# ---------------------------------------------------------------------------

test_empty_terms_section_passes() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

(none used in this PRD body)

## Next section
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 0 "$ec"
  assert_contains "$output" "ok: 0 canon, 0 non-canon"
}

test_terms_with_multi_word_names() {
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Dev mode**: see glossary.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 0 "$ec"
  assert_contains "$output" "ok: 1 canon"
}

test_terms_section_ends_at_next_heading() {
  # A term listed AFTER the next `## ` heading should NOT be parsed.
  cat > "$PRD_FILE" <<'EOF'
# PRD

## Terms used

- **Ponder**: see glossary.

## Other section

- **Nebula**: this is outside Terms used — should be ignored.
EOF
  set +e
  output="$("$SCRIPT" "$PRD_FILE" "$CONTEXT_FILE" 2>&1)"
  ec=$?
  set -e
  assert_exit_code 0 "$ec"
  assert_contains "$output" "ok: 1 canon, 0 non-canon"
}
