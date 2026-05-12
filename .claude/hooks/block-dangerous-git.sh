#!/usr/bin/env bash
# Block destructive git operations — run in your own terminal if truly needed.
COMMAND=$(jq -r '.tool_input.command // ""')

if echo "$COMMAND" | grep -qE '(git\s+push(\s|$)|git\s+push\s+--force|git\s+push\s+-f\b|git\s+reset\s+--hard|git\s+clean\s+-[fd]+|git\s+branch\s+-D|git\s+checkout\s+\.|git\s+restore\s+\.)'; then
  echo "BLOCKED: Dangerous git operation detected. Run in your own terminal if intentional." >&2
  exit 2
fi
exit 0
