#!/usr/bin/env bash
# temper-continuation.test.sh — tests for temper's continuation file format
# (issue #185, slice 1c-5).
#
# temper/SKILL.md was updated so temper's continuation file
# (.claude/temper-continue-<N>.md) is reformatted into the hardened five-section
# `gen-NNN.md` schema that the P2 substrate uses (templates/continuation-gen.md).
# This is a FORMAT alignment only: temper stays a subagent — it does NOT move to
# the `.forge/continuation/<slug>/` chain and does NOT call continuation.sh.
#
# temper/SKILL.md is a markdown skill, not a shell script, so it has no direct
# unit surface. What IS deterministically testable is the *contract* it
# documents: the five mandatory section headings, the kept per-issue path, the
# "not the .forge chain / no continuation.sh" boundary, and the read side.
# These assertions mirror the doc-contract pattern in forge-loop.test.sh.
#
# Run via:  test/run-tests.sh test/temper-continuation.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

SKILL="$REPO_ROOT/.claude/skills/temper/SKILL.md"
GEN_TEMPLATE="$REPO_ROOT/templates/continuation-gen.md"

# ── temper/SKILL.md documents the hardened five-section schema ────────────────

test_skill_documents_all_five_section_headings() {
  # The five mandatory sections of the hardened gen-NNN.md schema must all
  # appear as headings in temper's continuation-file format block.
  local body
  body="$(cat "$SKILL")"
  assert_contains "$body" "## Hard constraints (RESTATED VERBATIM — do not summarize)" \
    "temper/SKILL.md must document the verbatim Hard constraints section"
  assert_contains "$body" "## Execution frontier" \
    "temper/SKILL.md must document the Execution frontier section"
  assert_contains "$body" "## Conversation summary" \
    "temper/SKILL.md must document the Conversation summary section"
  assert_contains "$body" "## Next concrete action" \
    "temper/SKILL.md must document the Next concrete action section"
  assert_contains "$body" "## Notes / scratch" \
    "temper/SKILL.md must document the Notes / scratch section"
}

test_skill_section_headings_match_the_gen_template() {
  # The headings temper documents must be the SAME ones the canonical
  # gen-NNN.md template defines — that is what "format alignment" means.
  local skill_body template_body heading
  skill_body="$(cat "$SKILL")"
  template_body="$(cat "$GEN_TEMPLATE")"
  while IFS= read -r heading; do
    assert_contains "$skill_body" "$heading" \
      "temper/SKILL.md must use the gen-NNN.md heading verbatim: $heading"
  done < <(grep -E '^## ' "$GEN_TEMPLATE")
}

test_skill_keeps_per_issue_continuation_path() {
  # Format-only reformat — the file stays at .claude/temper-continue-<N>.md so
  # forge/seal/scrub references do not break.
  assert_contains "$(cat "$SKILL")" ".claude/temper-continue-<N>.md" \
    "temper/SKILL.md must keep the per-issue .claude/temper-continue-<N>.md path"
}

test_skill_keeps_temper_outside_the_forge_chain() {
  # The boundary: temper is a subagent — it does NOT join the slug-namespaced
  # .forge/continuation/<slug>/ chain and does NOT call continuation.sh.
  # Collapse whitespace first so arbitrary markdown line-wraps don't matter.
  local body flat
  body="$(cat "$SKILL")"
  flat="$(tr '\n' ' ' < "$SKILL" | tr -s '[:space:]' ' ')"
  assert_contains "$body" ".forge/continuation/<slug>/" \
    "temper/SKILL.md must name the .forge chain it deliberately does NOT join"
  assert_contains "$flat" "does not call \`scripts/continuation.sh\`" \
    "temper/SKILL.md must state temper does not call scripts/continuation.sh"
}

test_skill_documents_format_only_no_behavior_change() {
  # Acceptance criterion: no behavioral change — schema/format reformat only.
  local flat
  flat="$(tr '\n' ' ' < "$SKILL" | tr -s '[:space:]' ' ')"
  assert_contains "$flat" "format alignment only" \
    "temper/SKILL.md must state the change is a format alignment only"
}

test_skill_documents_the_read_side() {
  # Acceptance criterion: SKILL.md updated to write AND read the new format.
  # The Setup step must tell a resuming temper to read the continuation file.
  local flat
  flat="$(tr '\n' ' ' < "$SKILL" | tr -s '[:space:]' ' ')"
  assert_contains "$flat" "If resuming from a continuation file" \
    "temper/SKILL.md Setup must tell a resuming temper to read the continuation file"
}
