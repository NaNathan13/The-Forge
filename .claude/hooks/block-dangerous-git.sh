#!/usr/bin/env bash
# Block destructive git operations — run in your own terminal if truly needed.
# Normal feature-branch pushes (e.g. git push -u origin feat/#42-foo) are allowed.
COMMAND=$(jq -r '.tool_input.command // ""')

# Block force-push variants
if echo "$COMMAND" | grep -qE 'git\s+push\s+.*--force|git\s+push\s+.*-f\b'; then
  echo "BLOCKED: Force-push detected. Run in your own terminal if intentional." >&2
  exit 2
fi

# Block pushes targeting main or master
if echo "$COMMAND" | grep -qE 'git\s+push\s+\S+\s+(main|master)\b'; then
  echo "BLOCKED: Push to main/master detected. Run in your own terminal if intentional." >&2
  exit 2
fi

# Block other destructive operations
if echo "$COMMAND" | grep -qE '(git\s+reset\s+--hard|git\s+clean\s+-[fd]+|git\s+branch\s+-D|git\s+checkout\s+\.|git\s+restore\s+\.)'; then
  echo "BLOCKED: Dangerous git operation detected. Run in your own terminal if intentional." >&2
  exit 2
fi

exit 0
