#!/usr/bin/env bash
set -euo pipefail

# Move a GitHub issue to a Kanban column on the project's Projects (v2) board.
# Usage: kanban-move.sh <issue-number> <status>
# Status: backlog | ready | in-progress | in-review | done
#
# ──────────────────────────────────────────────────────────────────────
# CUSTOMIZE THESE PER PROJECT (see docs/dev/setup.md for how to look them up):
#
#   OWNER            GitHub login or org that owns the Project
#   PROJECT_NUMBER   The number shown in the Project's URL
#   PROJECT_ID       The internal node ID (PVT_kw...) of the Project
#   STATUS_FIELD_ID  Field ID for the single-select "Status" column
#   OPTION_ID_*      Option IDs for each Status value
#
# Look them up:
#   gh project list --owner <OWNER>
#   gh project view <NUMBER> --owner <OWNER> --format json
#   gh project field-list <NUMBER> --owner <OWNER> --format json
# ──────────────────────────────────────────────────────────────────────

OWNER="REPLACE_ME"
PROJECT_NUMBER=0
PROJECT_ID="REPLACE_ME"
STATUS_FIELD_ID="REPLACE_ME"

OPTION_ID_BACKLOG="REPLACE_ME"
OPTION_ID_READY="REPLACE_ME"
OPTION_ID_IN_PROGRESS="REPLACE_ME"
OPTION_ID_IN_REVIEW="REPLACE_ME"
OPTION_ID_DONE="REPLACE_ME"

if [[ "$OWNER" == "REPLACE_ME" ]]; then
  echo "kanban-move.sh: project IDs not configured. See docs/dev/setup.md." >&2
  exit 1
fi

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <issue-number> <status>"
  echo "Status: backlog | ready | in-progress | in-review | done"
  exit 1
fi

ISSUE_NUMBER="$1"
STATUS="$2"

case "$STATUS" in
  backlog)     OPTION_ID="$OPTION_ID_BACKLOG" ;;
  ready)       OPTION_ID="$OPTION_ID_READY" ;;
  in-progress) OPTION_ID="$OPTION_ID_IN_PROGRESS" ;;
  in-review)   OPTION_ID="$OPTION_ID_IN_REVIEW" ;;
  done)        OPTION_ID="$OPTION_ID_DONE" ;;
  *)
    echo "Unknown status: $STATUS"
    echo "Valid: backlog | ready | in-progress | in-review | done"
    exit 1
    ;;
esac

ITEM_ID=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --format json --limit 500 \
  | jq -r ".items[] | select(.content.number == $ISSUE_NUMBER) | .id")

if [[ -z "$ITEM_ID" ]]; then
  echo "Issue #$ISSUE_NUMBER not found on project board"
  exit 1
fi

gh project item-edit \
  --project-id "$PROJECT_ID" \
  --id "$ITEM_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$OPTION_ID"

echo "Moved #$ISSUE_NUMBER → $STATUS"
