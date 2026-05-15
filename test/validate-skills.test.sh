#!/usr/bin/env bash
# validate-skills.test.sh — tests for test/validate-skills.sh.
#
# Covers slice #193: each test stages a synthetic `.claude/skills/` and
# `.claude/agents/` tree under a tmp root, runs the validator against that
# root, and asserts pass/fail behaviour.
#
# Also runs the validator against the live repo root to guard the "no false
# positives on shipped artifacts" acceptance criterion.
#
# Run via:  test/run-tests.sh test/validate-skills.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

VALIDATOR="$REPO_ROOT/test/validate-skills.sh"

setup() {
  WORKDIR="$(mktemp -d)"
  mkdir -p "$WORKDIR/.claude/skills" "$WORKDIR/.claude/agents"
}

teardown() {
  rm -rf "$WORKDIR"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# write_skill <slug> <frontmatter-body>
# Creates $WORKDIR/.claude/skills/<slug>/SKILL.md with the given frontmatter
# body sandwiched between `---` fences (the body is inserted verbatim; pass
# whole lines including any `name:`/`description:` you want).
write_skill() {
  local slug="$1" body="$2"
  mkdir -p "$WORKDIR/.claude/skills/$slug"
  {
    echo "---"
    printf '%s\n' "$body"
    echo "---"
    echo ""
    echo "# $slug"
  } > "$WORKDIR/.claude/skills/$slug/SKILL.md"
}

# write_agent <name> <frontmatter-body>
write_agent() {
  local name="$1" body="$2"
  {
    echo "---"
    printf '%s\n' "$body"
    echo "---"
    echo ""
    echo "# $name"
  } > "$WORKDIR/.claude/agents/$name.md"
}

# write_skill_raw <slug> <full-file-contents>
# Same as write_skill but lets a test stage a malformed file (e.g. no fences).
write_skill_raw() {
  local slug="$1" contents="$2"
  mkdir -p "$WORKDIR/.claude/skills/$slug"
  printf '%s' "$contents" > "$WORKDIR/.claude/skills/$slug/SKILL.md"
}

# run_validator <root>
# Runs the validator, capturing combined stdout+stderr into VALIDATOR_OUT and
# the exit code into VALIDATOR_RC. Never propagates a non-zero exit (so a test
# under `set -e` can still inspect a failure).
run_validator() {
  VALIDATOR_RC=0
  VALIDATOR_OUT="$(bash "$VALIDATOR" "$@" 2>&1)" || VALIDATOR_RC=$?
}

# ── Happy path ───────────────────────────────────────────────────────────────

test_passes_on_well_formed_skill_and_agent() {
  write_skill "foo" "$(printf 'name: foo\ndescription: A foo skill.')"
  write_agent "bar" "$(printf 'name: bar\ndescription: A bar agent.')"
  run_validator "$WORKDIR"
  assert_exit_code 0 "$VALIDATOR_RC" "validator should pass"
  assert_contains "$VALIDATOR_OUT" "2/2 valid"
}

test_passes_on_empty_trees() {
  # Both dirs exist but empty — there is nothing to validate; validator should succeed.
  run_validator "$WORKDIR"
  assert_exit_code 0 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "0/0 valid"
}

test_passes_on_missing_trees() {
  # Neither .claude/skills nor .claude/agents exists — also a no-op success.
  rm -rf "$WORKDIR/.claude"
  run_validator "$WORKDIR"
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_tolerates_extra_frontmatter_fields() {
  # The shipped frontmatter sometimes carries disable-model-invocation:; the
  # validator must accept unknown fields, not treat them as errors.
  write_skill "foo" "$(printf 'name: foo\ndescription: A foo skill.\ndisable-model-invocation: true')"
  run_validator "$WORKDIR"
  assert_exit_code 0 "$VALIDATOR_RC"
}

# ── Failure modes ────────────────────────────────────────────────────────────

test_fails_when_opening_fence_missing() {
  write_skill_raw "foo" "name: foo
description: missing fences
"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "missing opening"
}

test_fails_when_closing_fence_missing() {
  write_skill_raw "foo" "---
name: foo
description: never closes
"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "missing closing"
}

test_fails_when_name_missing() {
  write_skill "foo" "description: no name field"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "missing 'name'"
}

test_fails_when_description_missing() {
  write_skill "foo" "name: foo"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "missing 'description'"
}

test_fails_when_name_empty() {
  write_skill "foo" "$(printf 'name:\ndescription: has no name value')"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "'name' field is empty"
}

test_fails_when_description_empty() {
  write_skill "foo" "$(printf 'name: foo\ndescription:   ')"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "'description' field is empty"
}

test_fails_when_skill_name_does_not_match_directory() {
  write_skill "foo" "$(printf 'name: bar\ndescription: dir is foo but name is bar')"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "does not match containing directory"
}

test_agent_name_does_not_need_to_match_filename() {
  # The spec only asserts name/dir match for skills. Agents are flat files; the
  # validator must not enforce a name/filename relationship on them.
  write_agent "bar" "$(printf 'name: completely-different\ndescription: still valid')"
  run_validator "$WORKDIR"
  assert_exit_code 0 "$VALIDATOR_RC"
}

test_reports_each_invalid_file_separately() {
  # Two broken files → both should appear in the failure output.
  write_skill "foo" "description: no name"
  write_skill "baz" "name: baz"
  run_validator "$WORKDIR"
  assert_exit_code 1 "$VALIDATOR_RC"
  assert_contains "$VALIDATOR_OUT" "skills/foo/SKILL.md"
  assert_contains "$VALIDATOR_OUT" "skills/baz/SKILL.md"
}

# ── Live-repo guard ──────────────────────────────────────────────────────────

test_no_false_positives_on_shipped_artifacts() {
  # Run validator against the actual repo — every skill and agent shipped on
  # main must validate. This is the load-bearing acceptance criterion: a
  # regression here means light-the-forge.sh would ship broken frontmatter.
  run_validator "$REPO_ROOT"
  assert_exit_code 0 "$VALIDATOR_RC" "shipped skills/agents must all validate"
  assert_contains "$VALIDATOR_OUT" "validate-skills: OK"
}

# ── Argument handling ────────────────────────────────────────────────────────

test_bad_root_arg_returns_2() {
  run_validator /no/such/path
  assert_exit_code 2 "$VALIDATOR_RC"
}
