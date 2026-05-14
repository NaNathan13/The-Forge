# Fixture: a clean handoff well under the budget warn line.
# The session wrote its continuation and exited with the FORGE_CONTINUE sentinel;
# token usage is low, so the relaunch loop should relaunch normally (no "hand off
# promptly" signal). Orchestrator warn is 40% — 40k/200k input tokens ≈ 20%.
CLAUDE_STUB_RESULT="phase complete, continuation written FORGE_CONTINUE"
CLAUDE_STUB_USAGE='{"input_tokens":40000,"output_tokens":3000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=0
