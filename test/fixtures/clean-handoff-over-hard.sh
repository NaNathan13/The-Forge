# Fixture: a clean handoff that lands over the orchestrator HARD line (50%).
# The session handed off cleanly (FORGE_CONTINUE), but .usage is past the hard
# threshold — the relaunch loop's budget gate must NOT start another generation that
# would run past the hard line without a handoff. ~105k/200k input tokens ≈ 52%.
CLAUDE_STUB_RESULT="budget hit, handing off FORGE_CONTINUE"
CLAUDE_STUB_USAGE='{"input_tokens":105000,"output_tokens":5000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=0
