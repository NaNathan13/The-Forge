# Fixture: a hard crash mid-generation.
# claude exited non-zero (OOM, panic, signal, internal error). The relaunch loop must
# propagate the non-zero exit to launchd rather than masking it or respinning — this
# is the boundary between the two supervision layers (loop = context limits, launchd =
# crashes). .result is empty because a crashed generation never reaches a sentinel.
CLAUDE_STUB_RESULT=""
CLAUDE_STUB_IS_ERROR="true"
CLAUDE_STUB_SUBTYPE="error_during_execution"
CLAUDE_STUB_USAGE='{"input_tokens":70000,"output_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}'
CLAUDE_STUB_EXIT=1
