#!/usr/bin/env bash
set -euo pipefail

# setup-kanban.sh — Auto-discover GitHub Projects v2 board IDs and write them
# into kanban-move.sh, replacing the REPLACE_ME placeholders.
#
# Usage: .claude/scripts/setup-kanban.sh
#
# Replaces the manual GraphQL ID lookup documented in SETUP.md step 3.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KANBAN_SCRIPT="$SCRIPT_DIR/kanban-move.sh"

# Portable in-place sed (macOS requires -i '', GNU sed requires -i)
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"       # GNU sed
  else
    sed -i '' "$@"    # BSD/macOS sed
  fi
}

if [[ ! -f "$KANBAN_SCRIPT" ]]; then
  echo "Error: kanban-move.sh not found at $KANBAN_SCRIPT" >&2
  exit 1
fi

# ── 1. Prompt for project board number ──────────────────────────────────────

echo "=== GitHub Projects v2 — Kanban Setup ==="
echo ""
read -rp "Enter your GitHub Projects board number or URL: " PROJECT_INPUT

# Parse number from URL if needed (e.g. https://github.com/users/foo/projects/3)
if [[ "$PROJECT_INPUT" =~ /projects/([0-9]+) ]]; then
  PROJECT_NUMBER="${BASH_REMATCH[1]}"
elif [[ "$PROJECT_INPUT" =~ ^[0-9]+$ ]]; then
  PROJECT_NUMBER="$PROJECT_INPUT"
else
  echo "Error: Could not parse a project number from '$PROJECT_INPUT'." >&2
  echo "Provide either a number (e.g. 3) or a full URL (e.g. https://github.com/users/you/projects/3)." >&2
  exit 1
fi

echo ""
echo "Using project number: $PROJECT_NUMBER"

# ── 2. Determine project owner ─────────────────────────────────────────────

OWNER=$(gh api user --jq '.login' 2>/dev/null) || true
if [[ -z "$OWNER" ]]; then
  echo "Error: Could not determine GitHub username. Make sure 'gh auth login' is complete." >&2
  exit 1
fi

echo "Project owner: $OWNER"
echo ""

# ── 3. Look up PROJECT_ID ──────────────────────────────────────────────────

echo "Looking up project ID..."

PROJECT_ID=$(gh api graphql -f query='
  query($owner: String!, $number: Int!) {
    user(login: $owner) {
      projectV2(number: $number) {
        id
      }
    }
  }
' -f owner="$OWNER" -F number="$PROJECT_NUMBER" --jq '.data.user.projectV2.id' 2>/dev/null) || true

# If user lookup failed, try as organization
if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  PROJECT_ID=$(gh api graphql -f query='
    query($owner: String!, $number: Int!) {
      organization(login: $owner) {
        projectV2(number: $number) {
          id
        }
      }
    }
  ' -f owner="$OWNER" -F number="$PROJECT_NUMBER" --jq '.data.organization.projectV2.id' 2>/dev/null) || true
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "null" ]]; then
  echo "Error: Could not find project #$PROJECT_NUMBER for owner '$OWNER'." >&2
  echo "Make sure the project exists and you have access to it." >&2
  echo "Try: gh project list --owner $OWNER" >&2
  exit 1
fi

echo "  PROJECT_ID: $PROJECT_ID"

# ── 4. Look up STATUS_FIELD_ID and option IDs ──────────────────────────────

echo "Looking up Status field and options..."

FIELD_JSON=$(gh api graphql -f query='
  query($projectId: ID!) {
    node(id: $projectId) {
      ... on ProjectV2 {
        fields(first: 50) {
          nodes {
            ... on ProjectV2SingleSelectField {
              id
              name
              options {
                id
                name
              }
            }
          }
        }
      }
    }
  }
' -f projectId="$PROJECT_ID" --jq '.data.node.fields.nodes[] | select(.name == "Status")' 2>/dev/null) || true

if [[ -z "$FIELD_JSON" || "$FIELD_JSON" == "null" ]]; then
  echo "Error: Could not find a 'Status' single-select field on project #$PROJECT_NUMBER." >&2
  echo "Make sure your project has a single-select field named exactly 'Status'." >&2
  exit 1
fi

STATUS_FIELD_ID=$(echo "$FIELD_JSON" | jq -r '.id')
echo "  STATUS_FIELD_ID: $STATUS_FIELD_ID"

# Extract each option ID by name
get_option_id() {
  local name="$1"
  local option_id
  option_id=$(echo "$FIELD_JSON" | jq -r --arg name "$name" '.options[] | select(.name == $name) | .id')
  if [[ -z "$option_id" || "$option_id" == "null" ]]; then
    echo "Error: Could not find Status option named '$name'." >&2
    echo "Available options:" >&2
    echo "$FIELD_JSON" | jq -r '.options[].name' | sed 's/^/  - /' >&2
    exit 1
  fi
  echo "$option_id"
}

OPTION_ID_BACKLOG=$(get_option_id "Backlog")
OPTION_ID_READY=$(get_option_id "Ready")
OPTION_ID_IN_PROGRESS=$(get_option_id "In Progress")
OPTION_ID_IN_REVIEW=$(get_option_id "In Review")
OPTION_ID_DONE=$(get_option_id "Done")

echo "  OPTION_ID_BACKLOG:     $OPTION_ID_BACKLOG"
echo "  OPTION_ID_READY:       $OPTION_ID_READY"
echo "  OPTION_ID_IN_PROGRESS: $OPTION_ID_IN_PROGRESS"
echo "  OPTION_ID_IN_REVIEW:   $OPTION_ID_IN_REVIEW"
echo "  OPTION_ID_DONE:        $OPTION_ID_DONE"

# ── 5. Write values into kanban-move.sh ─────────────────────────────────────

echo ""
echo "Writing values into kanban-move.sh..."

sedi "s|^OWNER=.*|OWNER=\"$OWNER\"|" "$KANBAN_SCRIPT"
sedi "s|^PROJECT_NUMBER=.*|PROJECT_NUMBER=$PROJECT_NUMBER|" "$KANBAN_SCRIPT"
sedi "s|^PROJECT_ID=.*|PROJECT_ID=\"$PROJECT_ID\"|" "$KANBAN_SCRIPT"
sedi "s|^STATUS_FIELD_ID=.*|STATUS_FIELD_ID=\"$STATUS_FIELD_ID\"|" "$KANBAN_SCRIPT"
sedi "s|^OPTION_ID_BACKLOG=.*|OPTION_ID_BACKLOG=\"$OPTION_ID_BACKLOG\"|" "$KANBAN_SCRIPT"
sedi "s|^OPTION_ID_READY=.*|OPTION_ID_READY=\"$OPTION_ID_READY\"|" "$KANBAN_SCRIPT"
sedi "s|^OPTION_ID_IN_PROGRESS=.*|OPTION_ID_IN_PROGRESS=\"$OPTION_ID_IN_PROGRESS\"|" "$KANBAN_SCRIPT"
sedi "s|^OPTION_ID_IN_REVIEW=.*|OPTION_ID_IN_REVIEW=\"$OPTION_ID_IN_REVIEW\"|" "$KANBAN_SCRIPT"
sedi "s|^OPTION_ID_DONE=.*|OPTION_ID_DONE=\"$OPTION_ID_DONE\"|" "$KANBAN_SCRIPT"

echo ""
echo "=== Done! kanban-move.sh has been configured ==="
echo ""
echo "  OWNER:                 $OWNER"
echo "  PROJECT_NUMBER:        $PROJECT_NUMBER"
echo "  PROJECT_ID:            $PROJECT_ID"
echo "  STATUS_FIELD_ID:       $STATUS_FIELD_ID"
echo "  OPTION_ID_BACKLOG:     $OPTION_ID_BACKLOG"
echo "  OPTION_ID_READY:       $OPTION_ID_READY"
echo "  OPTION_ID_IN_PROGRESS: $OPTION_ID_IN_PROGRESS"
echo "  OPTION_ID_IN_REVIEW:   $OPTION_ID_IN_REVIEW"
echo "  OPTION_ID_DONE:        $OPTION_ID_DONE"
echo ""
echo "You can now use: .claude/scripts/kanban-move.sh <issue-number> <status>"
