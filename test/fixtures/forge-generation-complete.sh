# Fixture: the forge drained-queue generation (Option B — issue #182).
#
# Models the loop-managed `forge` generation that found its dispatch queue
# drained — every slice shipped / skipped / failed. Per forge/SKILL.md's
# "End of Run — Auto-ship", this generation does NOT dispatch a temper: it
# dispatches the seal subagent, relays seal's summary, and emits FORGEMASTER_COMPLETE
# as its final .result line. The relaunch loop should read FORGEMASTER_COMPLETE and
# break (exit 0) — the run is genuinely done.
#
# No `continuation.sh write` here: the drained-queue generation is the terminal
# one, so there is no next generation to hand off to.
CLAUDE_STUB_RESULT="queue drained, seal subagent merged 3 PRs, MC reconciled FORGEMASTER_COMPLETE"
CLAUDE_STUB_USAGE='{"input_tokens":42000,"output_tokens":4000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=0
