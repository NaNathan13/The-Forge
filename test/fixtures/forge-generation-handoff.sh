# Fixture: one forge generation under the relaunch loop (Option B — issue #182).
#
# Models a single loop-managed `forge` generation that dispatched its one temper,
# handled the TEMPER:RESULT sentinel, token-logged, and is now handing off: it
# writes the next continuation generation via scripts/continuation.sh write and
# emits FORGE_CONTINUE as its final .result line.
#
# A fixture is sourced by the claude stub, so the `continuation.sh write` here runs
# as the generation's real side effect — exactly what forge/SKILL.md's Dispatch
# Loop step 7 instructs. The relaunch loop should then see FORGE_CONTINUE, run its
# thrash + budget gates, and relaunch fresh.
#
# FORGE_DIR / a --slug are supplied by the test; continuation.sh derives the rest.
CLAUDE_STUB_RESULT="temper #95 success (PR #110, CI green), continuation written FORGE_CONTINUE"
CLAUDE_STUB_USAGE='{"input_tokens":35000,"output_tokens":3000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=0

# The forge generation writes its next gen-NNN.md before emitting FORGE_CONTINUE.
# --slug forge-demo keeps it under the same continuation chain the test inspects.
bash "$REPO_ROOT/scripts/continuation.sh" write --slug forge-demo >/dev/null 2>&1 || true
