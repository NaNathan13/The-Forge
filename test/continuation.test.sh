#!/usr/bin/env bash
# continuation.test.sh — tests for scripts/continuation.sh and the .forge/ substrate.
#
# Covers P2 slice 1b (issue #138): slug derivation, monotonic zero-padded
# generation numbering, the `latest` symlink, retention prune, the gen-NNN.md
# template's five hardened sections, and that .forge/resilience.config is a
# clean bash-sourceable KEY=value file carrying the §Q1 defaults.
#
# Run via:  test/run-tests.sh test/continuation.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

CONT="$REPO_ROOT/scripts/continuation.sh"
CONFIG="$REPO_ROOT/.forge/resilience.config"
TEMPLATE="$REPO_ROOT/templates/continuation-gen.md"

# Each test gets its own temp .forge dir so generations never leak between tests.
setup() {
  WORKDIR="$(mktemp -d)"
  export FORGE_DIR="$WORKDIR/.forge"
  mkdir -p "$FORGE_DIR"
  unset FORGE_RETENTION_CAP
}

teardown() {
  rm -rf "$WORKDIR"
  unset FORGE_DIR FORGE_RETENTION_CAP
}

# ── Slug derivation ──────────────────────────────────────────────────────────

test_slug_is_slugified_dir_basename() {
  assert_eq "my-project" "$(bash "$CONT" slug /tmp/my-project)"
}

test_slug_lowercases_and_collapses_nonalnum() {
  # "My Project_v2!!" → lowercase, non-alnum runs → single '-', trimmed.
  assert_eq "my-project-v2" "$(bash "$CONT" slug "/tmp/My Project_v2!!")"
}

test_slug_trims_leading_and_trailing_separators() {
  assert_eq "abc" "$(bash "$CONT" slug "/tmp/--abc--")"
}

test_slug_falls_back_to_session_for_empty() {
  # A basename that slugifies to nothing falls back to "session".
  assert_eq "session" "$(bash "$CONT" slug "/tmp/___")"
}

test_slug_defaults_to_cwd_basename() {
  # No arg → derive from the current working directory.
  local sub="$WORKDIR/Cool Dir"
  mkdir -p "$sub"
  local got
  got="$(cd "$sub" && bash "$CONT" slug)"
  assert_eq "cool-dir" "$got"
}

# ── Monotonic, zero-padded generation numbering ──────────────────────────────

test_next_num_starts_at_001() {
  assert_eq "001" "$(bash "$CONT" next-num --slug demo)"
}

test_latest_num_is_000_when_empty() {
  assert_eq "000" "$(bash "$CONT" latest-num --slug demo)"
}

test_numbering_is_monotonic_and_zero_padded() {
  bash "$CONT" write --slug demo >/dev/null
  assert_eq "001" "$(bash "$CONT" latest-num --slug demo)"
  assert_eq "002" "$(bash "$CONT" next-num --slug demo)"
  bash "$CONT" write --slug demo >/dev/null
  bash "$CONT" write --slug demo >/dev/null
  assert_eq "003" "$(bash "$CONT" latest-num --slug demo)"
  assert_eq "004" "$(bash "$CONT" next-num --slug demo)"
}

test_write_creates_zero_padded_gen_file() {
  local path
  path="$(bash "$CONT" write --slug demo)"
  assert_eq "$FORGE_DIR/continuation/demo/gen-001.md" "$path"
  assert_file_exists "$path"
}

# ── latest symlink ───────────────────────────────────────────────────────────

test_latest_symlink_points_at_newest_generation() {
  bash "$CONT" write --slug demo >/dev/null
  bash "$CONT" write --slug demo >/dev/null
  local link="$FORGE_DIR/continuation/demo/latest"
  assert_file_exists "$link"
  # The symlink target is the bare filename of the newest generation.
  assert_eq "gen-002.md" "$(readlink "$link")"
}

test_latest_path_resolves_to_newest_absolute_path() {
  bash "$CONT" write --slug demo >/dev/null
  bash "$CONT" write --slug demo >/dev/null
  assert_eq "$FORGE_DIR/continuation/demo/gen-002.md" "$(bash "$CONT" latest-path --slug demo)"
}

test_latest_path_fails_when_no_generation_exists() {
  local rc=0
  bash "$CONT" latest-path --slug demo >/dev/null 2>&1 || rc=$?
  assert_exit_code 1 "$rc"
}

# ── Retention prune ──────────────────────────────────────────────────────────

test_prune_keeps_only_the_last_n_generations() {
  # cap=3, write 6 → only gen-004..gen-006 survive.
  local i
  for i in 1 2 3 4 5 6; do
    bash "$CONT" write --slug demo --cap 3 >/dev/null
  done
  local dir="$FORGE_DIR/continuation/demo"
  assert_file_absent "$dir/gen-001.md"
  assert_file_absent "$dir/gen-003.md"
  assert_file_exists "$dir/gen-004.md"
  assert_file_exists "$dir/gen-006.md"
}

test_prune_never_removes_the_latest_symlink_target() {
  local i
  for i in 1 2 3 4 5; do
    bash "$CONT" write --slug demo --cap 2 >/dev/null
  done
  # latest must still resolve to a file that exists.
  assert_eq "$FORGE_DIR/continuation/demo/gen-005.md" "$(bash "$CONT" latest-path --slug demo)"
  assert_file_exists "$(bash "$CONT" latest-path --slug demo)"
}

test_prune_is_a_noop_under_the_cap() {
  bash "$CONT" write --slug demo --cap 10 >/dev/null
  bash "$CONT" write --slug demo --cap 10 >/dev/null
  bash "$CONT" prune --slug demo --cap 10
  assert_file_exists "$FORGE_DIR/continuation/demo/gen-001.md"
  assert_file_exists "$FORGE_DIR/continuation/demo/gen-002.md"
}

test_retention_cap_is_read_from_resilience_config() {
  # Drop a config with a small cap into the temp .forge; write past it.
  echo 'FORGE_RETENTION_CAP=3' > "$FORGE_DIR/resilience.config"
  local i
  for i in 1 2 3 4 5; do
    bash "$CONT" write --slug demo >/dev/null
  done
  local count
  count="$(find "$FORGE_DIR/continuation/demo" -name 'gen-*.md' | wc -l | tr -d ' ')"
  assert_eq "3" "$count"
}

test_retention_cap_env_overrides_config() {
  echo 'FORGE_RETENTION_CAP=10' > "$FORGE_DIR/resilience.config"
  local i
  for i in 1 2 3 4 5; do
    FORGE_RETENTION_CAP=2 bash "$CONT" write --slug demo >/dev/null
  done
  local count
  count="$(find "$FORGE_DIR/continuation/demo" -name 'gen-*.md' | wc -l | tr -d ' ')"
  assert_eq "2" "$count"
}

# ── gen-NNN.md template — the five hardened §2 sections ──────────────────────

test_written_generation_has_all_five_hardened_sections() {
  local path body
  path="$(bash "$CONT" write --slug demo)"
  body="$(cat "$path")"
  assert_contains "$body" "## Hard constraints (RESTATED VERBATIM"
  assert_contains "$body" "## Execution frontier"
  assert_contains "$body" "## Conversation summary"
  assert_contains "$body" "## Next concrete action"
  assert_contains "$body" "## Notes / scratch"
}

test_written_generation_has_structured_execution_frontier_fields() {
  local path body
  path="$(bash "$CONT" write --slug demo)"
  body="$(cat "$path")"
  assert_contains "$body" "**Branch:**"
  assert_contains "$body" "**Open PR(s):**"
  assert_contains "$body" "**Last sentinel:**"
  assert_contains "$body" "**Dispatch queue:**"
  assert_contains "$body" "**Mid-flight state:**"
}

test_written_generation_header_is_stamped() {
  local path header
  path="$(bash "$CONT" write --slug demo --role worker)"
  header="$(head -2 "$path")"
  assert_contains "$header" "# Continuation — demo — generation 001"
  assert_contains "$header" "role: worker"
  assert_contains "$header" "prev: (none"
}

test_second_generation_header_references_prior() {
  bash "$CONT" write --slug demo >/dev/null
  local path header
  path="$(bash "$CONT" write --slug demo)"
  header="$(head -2 "$path")"
  assert_contains "$header" "generation 002"
  assert_contains "$header" "prev: gen-001"
}

test_template_file_exists_with_five_sections() {
  assert_file_exists "$TEMPLATE"
  local body
  body="$(cat "$TEMPLATE")"
  assert_contains "$body" "## Hard constraints (RESTATED VERBATIM"
  assert_contains "$body" "## Execution frontier"
  assert_contains "$body" "## Conversation summary"
  assert_contains "$body" "## Next concrete action"
  assert_contains "$body" "## Notes / scratch"
}

# ── resilience.config — bash-sourceable, §Q1 defaults ────────────────────────

test_resilience_config_exists() {
  assert_file_exists "$CONFIG"
}

test_resilience_config_is_bash_sourceable() {
  # Sourcing it must not error and must define the documented keys.
  local out
  out="$(
    # shellcheck disable=SC1090
    . "$CONFIG"
    echo "$FORGE_ORCH_WARN_PCT $FORGE_ORCH_HARD_PCT $FORGE_WORKER_WARN_PCT $FORGE_WORKER_HARD_PCT"
  )"
  assert_eq "40 50 50 60" "$out"
}

test_resilience_config_carries_throttle_heartbeat_retention() {
  local out
  out="$(
    # shellcheck disable=SC1090
    . "$CONFIG"
    echo "$FORGE_THROTTLE_SECONDS $FORGE_HEARTBEAT_TIMEOUT_SECONDS $FORGE_RETENTION_CAP"
  )"
  # All three present and non-empty (exact values are tunable, presence is the contract).
  assert_ne "" "$(. "$CONFIG"; echo "${FORGE_THROTTLE_SECONDS:-}")"
  assert_ne "" "$(. "$CONFIG"; echo "${FORGE_HEARTBEAT_TIMEOUT_SECONDS:-}")"
  assert_ne "" "$(. "$CONFIG"; echo "${FORGE_RETENTION_CAP:-}")"
}

test_resilience_config_has_no_executable_logic() {
  # A sourceable config should be comments + KEY=value only — no shebang, no
  # control flow that could surprise a `source`.
  local offending
  offending="$(grep -nE '^[[:space:]]*(if|for|while|case|function|\.|source|eval|exec)[[:space:]]' "$CONFIG" || true)"
  assert_eq "" "$offending" "resilience.config must contain no executable logic"
  # First line must not be a shebang.
  assert_not_contains "$(head -1 "$CONFIG")" "#!/"
}

test_templates_placeholder_resilience_config_mirrors_schema() {
  # The templates/ placeholder must define the same key set as the real config.
  local real_keys placeholder_keys
  real_keys="$(grep -oE '^[A-Z_]+=' "$CONFIG" | sort)"
  placeholder_keys="$(grep -oE '^[A-Z_]+=' "$REPO_ROOT/templates/resilience.config" | sort)"
  assert_eq "$real_keys" "$placeholder_keys"
}
