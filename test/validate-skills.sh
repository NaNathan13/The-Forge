#!/usr/bin/env bash
set -uo pipefail

# validate-skills.sh — validate frontmatter on every shipped skill and agent.
#
# Walks `.claude/skills/*/SKILL.md` and `.claude/agents/*.md` under the given root
# (default: the repo root inferred from this script's location). For each file:
#
#   1. Asserts YAML frontmatter is delimited by `---` fences — opening fence on
#      line 1, closing fence somewhere after.
#   2. Asserts a `name:` field is present, with a non-empty value.
#   3. Asserts a `description:` field is present, with a non-empty value.
#   4. For skill files (under `.claude/skills/<slug>/SKILL.md`): asserts the
#      `name` value matches the containing directory `<slug>` exactly.
#
# These files are copied verbatim into every downstream repo by
# `light-the-forge.sh` — a broken frontmatter today ships out to N projects.
# This validator is the cheap, fast guard.
#
# ── Usage ───────────────────────────────────────────────────────────────────
#   test/validate-skills.sh                       # validate this repo
#   test/validate-skills.sh /path/to/another/repo # validate elsewhere
#
# Exit codes:
#   0 — all files OK (or both trees absent — nothing to validate)
#   1 — one or more files failed validation; per-file errors printed to stderr
#   2 — runtime/usage error (bad arg, unreadable root)
# ────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="${1:-$DEFAULT_ROOT}"

if [[ ! -d "$ROOT" ]]; then
  echo "validate-skills.sh: root not found or not a directory: $ROOT" >&2
  exit 2
fi

SKILLS_DIR="$ROOT/.claude/skills"
AGENTS_DIR="$ROOT/.claude/agents"

# Collect target files. Both trees are optional (a fresh Forge install before
# customization may not have one or the other); validating zero files is success.
declare -a TARGETS=()
if [[ -d "$SKILLS_DIR" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && TARGETS+=("$f")
  done < <(find "$SKILLS_DIR" -mindepth 2 -maxdepth 2 -type f -name 'SKILL.md' | sort)
fi
if [[ -d "$AGENTS_DIR" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] && TARGETS+=("$f")
  done < <(find "$AGENTS_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.md' | sort)
fi

# Validate one file. Prints "FAIL <path>: <reason>" to stderr on failure and
# returns non-zero. Prints nothing on success.
validate_one() {
  local file="$1"
  local rel="${file#"$ROOT"/}"
  local kind="" expected_name=""

  # Classify: skill (dir-name must match) vs agent (no dir-name requirement).
  case "$file" in
    "$SKILLS_DIR"/*)
      kind="skill"
      # Skills live at $SKILLS_DIR/<slug>/SKILL.md — the parent dir's basename is the expected name.
      expected_name="$(basename "$(dirname "$file")")"
      ;;
    "$AGENTS_DIR"/*)
      kind="agent"
      ;;
    *)
      echo "FAIL $rel: classifier could not determine kind (skill vs agent)" >&2
      return 1
  esac

  # Frontmatter fence shape: opening `---` on line 1, closing `---` on some
  # later line. Anything else (no fences, no closer, fence not on line 1) is a fail.
  local first_line second_fence_line
  first_line="$(sed -n '1p' "$file" 2>/dev/null)"
  if [[ "$first_line" != "---" ]]; then
    echo "FAIL $rel: missing opening '---' frontmatter fence on line 1 (got: '$first_line')" >&2
    return 1
  fi
  # Find the line number of the next '---' after line 1.
  second_fence_line="$(awk 'NR>1 && $0=="---" {print NR; exit}' "$file")"
  if [[ -z "$second_fence_line" ]]; then
    echo "FAIL $rel: missing closing '---' frontmatter fence" >&2
    return 1
  fi

  # Extract the frontmatter body (between the two fences, exclusive).
  local body
  body="$(sed -n "2,$((second_fence_line - 1))p" "$file")"

  # Parse name and description. Strict, line-oriented: a field line begins at
  # column 0 with `<key>:` followed by optional whitespace and a value that
  # extends to end of line (no multi-line YAML, no quoted blocks — that's
  # intentional: the shipped frontmatter is flat). If the same key appears more
  # than once, the first occurrence wins (matches yaml.safe_load's "duplicate
  # key is an error", which would also be caught, but for our purposes the
  # first-wins read is fine — we only care that *a* valid value exists).
  local name="" description=""
  local saw_name=0 saw_description=0
  while IFS= read -r line; do
    # Skip blank lines inside frontmatter.
    [[ -z "$line" ]] && continue
    case "$line" in
      name:*)
        if [[ $saw_name -eq 0 ]]; then
          name="${line#name:}"
          # Strip leading whitespace.
          name="${name#"${name%%[![:space:]]*}"}"
          # Strip trailing whitespace.
          name="${name%"${name##*[![:space:]]}"}"
          saw_name=1
        fi
        ;;
      description:*)
        if [[ $saw_description -eq 0 ]]; then
          description="${line#description:}"
          description="${description#"${description%%[![:space:]]*}"}"
          description="${description%"${description##*[![:space:]]}"}"
          saw_description=1
        fi
        ;;
    esac
  done <<< "$body"

  if [[ $saw_name -eq 0 ]]; then
    echo "FAIL $rel: missing 'name' field in frontmatter" >&2
    return 1
  fi
  if [[ -z "$name" ]]; then
    echo "FAIL $rel: 'name' field is empty" >&2
    return 1
  fi
  if [[ $saw_description -eq 0 ]]; then
    echo "FAIL $rel: missing 'description' field in frontmatter" >&2
    return 1
  fi
  if [[ -z "$description" ]]; then
    echo "FAIL $rel: 'description' field is empty" >&2
    return 1
  fi

  if [[ "$kind" == "skill" ]]; then
    if [[ "$name" != "$expected_name" ]]; then
      echo "FAIL $rel: 'name' ($name) does not match containing directory ($expected_name)" >&2
      return 1
    fi
  fi

  return 0
}

PASS=0
FAIL=0
for f in "${TARGETS[@]+"${TARGETS[@]}"}"; do
  if validate_one "$f"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
done

TOTAL=$((PASS + FAIL))
if [[ $FAIL -eq 0 ]]; then
  echo "validate-skills: OK ($PASS/$TOTAL valid)"
  exit 0
else
  echo "validate-skills: FAIL ($FAIL/$TOTAL invalid, $PASS valid)" >&2
  exit 1
fi
