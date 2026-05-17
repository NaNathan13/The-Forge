# Fixture: the work is genuinely done.
# The session emitted the OVERSEER_COMPLETE sentinel in .result and exited 0 — the
# relaunch loop should break (exit 0), and launchd's SuccessfulExit=false keeps the
# loop from being respun.
CLAUDE_STUB_RESULT="all slices merged, nothing left OVERSEER_COMPLETE"
CLAUDE_STUB_USAGE='{"input_tokens":60000,"output_tokens":4000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=0
