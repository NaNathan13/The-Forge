# Fixture: exit 0 but no recognised sentinel in .result.
# The generation exited cleanly but .result contains neither FORGE_CONTINUE nor
# FORGE_COMPLETE. Per the design doc §1, the relaunch loop treats this as a fault
# (not a handoff) and exits non-zero rather than spinning.
CLAUDE_STUB_RESULT="...ran out of turns without writing a sentinel"
CLAUDE_STUB_USAGE='{"input_tokens":80000,"output_tokens":2000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=0
