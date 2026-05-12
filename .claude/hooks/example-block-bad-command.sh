#!/usr/bin/env bash
# EXAMPLE — project-specific PreToolUse Bash guardrail.
#
# Copy this file, rename it, and edit the pattern to block a command that
# bypasses your project's conventions. A common motivating example: block
# `npx tsc` when the project standard is a wrapped check command — `npx tsc`
# bypasses the local tsconfig and can silently produce "passing" output.
#
# Example patterns worth blocking:
#   - `npx tsc`  (bypasses local tsconfig, doesn't run project lint)
#   - `npm test` (when the project standard is `pnpm test` or a wrapped script)
#   - `git commit --no-verify` (skips pre-commit hooks)
#   - `rm -rf` outside a known scratch dir
#
# To enable: add an entry to .claude/settings.json under hooks.PreToolUse:
#   { "matcher": "Bash",
#     "hooks": [{ "type": "command", "command": ".claude/hooks/<your-renamed>.sh" }] }
#
# Hooks receive the tool call as JSON on stdin. Exit 2 with stderr message
# to block; exit 0 to allow. See Claude Code hook docs for full schema.

COMMAND=$(jq -r '.tool_input.command // ""')

# Edit the regex below for whatever you want to block.
if [[ "$COMMAND" =~ ^[[:space:]]*REPLACE_ME[[:space:]] ]]; then
  echo "BLOCKED: Replace this example regex with whatever is bad in your project." >&2
  exit 2
fi

exit 0
