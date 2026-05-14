#!/usr/bin/env bash
# statusline.test.sh — tests for .claude/statusline/budget-mirror.sh (P2 slice 7, issue #142).
#
# The statusline budget mirror is a DISPLAY-ONLY operator gauge: it reads
# `.context_window.used_percentage` from the statusline JSON on stdin and renders it
# against the warn/hard thresholds from .forge/resilience.config. It must never
# influence control flow — no file writes, no meaningful exit status.
#
# These tests cover:
#   - reading the percentage from stdin JSON (int + float, missing/null/garbage input);
#   - reading warn/hard from a resilience.config and rendering them in the gauge;
#   - the orchestrator/worker role split;
#   - graceful degradation when config or input is absent;
#   - the display-only contract — exit 0 always, no file writes.
#
# Run via:  test/run-tests.sh test/statusline.test.sh
#
# REPO_ROOT and TEST_DIR are exported by run-tests.sh.
# shellcheck source=lib/assert.sh
source "$TEST_DIR/lib/assert.sh"

MIRROR="$REPO_ROOT/.claude/statusline/budget-mirror.sh"

# Each test gets its own temp .forge dir with a config it controls, so threshold
# values never leak between tests and we exercise the config-reading path for real.
setup() {
  WORKDIR="$(mktemp -d)"
  export FORGE_DIR="$WORKDIR/.forge"
  mkdir -p "$FORGE_DIR"
  # A baseline config carrying the design doc §Q1 defaults. Individual tests rewrite
  # it when they need different numbers.
  cat > "$FORGE_DIR/resilience.config" <<'EOF'
FORGE_ORCH_WARN_PCT=40
FORGE_ORCH_HARD_PCT=50
FORGE_WORKER_WARN_PCT=50
FORGE_WORKER_HARD_PCT=60
EOF
  unset FORGE_SESSION_ROLE
}

teardown() {
  rm -rf "$WORKDIR"
  unset FORGE_DIR FORGE_SESSION_ROLE
}

# Run the mirror with the given stdin, returning its stdout.
run_mirror() {
  bash "$MIRROR"
}

# ── Reading the percentage from stdin JSON ───────────────────────────────────

test_reads_used_percentage_from_stdin() {
  local out
  out="$(echo '{"context_window":{"used_percentage":22}}' | run_mirror)"
  assert_contains "$out" "ctx 22%"
}

test_rounds_a_float_percentage() {
  # 42.7 → 43. printf %.0f rounds; the gauge is a compact whole-number display.
  local out
  out="$(echo '{"context_window":{"used_percentage":42.7}}' | run_mirror)"
  assert_contains "$out" "ctx 43%"
}

test_missing_field_degrades_to_placeholder() {
  # JSON with no context_window → `ctx --%`, never an error or empty line.
  local out
  out="$(echo '{"foo":1}' | run_mirror)"
  assert_contains "$out" "ctx --%"
}

test_null_field_degrades_to_placeholder() {
  local out
  out="$(echo '{"context_window":{"used_percentage":null}}' | run_mirror)"
  assert_contains "$out" "ctx --%"
}

test_garbage_input_degrades_to_placeholder() {
  local out
  out="$(echo 'not json at all' | run_mirror)"
  assert_contains "$out" "ctx --%"
}

test_empty_input_degrades_to_placeholder() {
  local out
  out="$(printf '' | run_mirror)"
  assert_contains "$out" "ctx --%"
}

# ── Rendering the thresholds from resilience.config ──────────────────────────

test_renders_warn_and_hard_from_config() {
  local out
  out="$(echo '{"context_window":{"used_percentage":22}}' | run_mirror)"
  assert_contains "$out" "warn 40"
  assert_contains "$out" "hard 50"
}

test_thresholds_track_a_custom_config() {
  # Rewrite the config — the gauge must read these numbers, not hardcode anything.
  cat > "$FORGE_DIR/resilience.config" <<'EOF'
FORGE_ORCH_WARN_PCT=30
FORGE_ORCH_HARD_PCT=45
FORGE_WORKER_WARN_PCT=50
FORGE_WORKER_HARD_PCT=60
EOF
  local out
  out="$(echo '{"context_window":{"used_percentage":10}}' | run_mirror)"
  assert_contains "$out" "warn 30"
  assert_contains "$out" "hard 45"
}

test_missing_config_falls_back_to_q1_defaults() {
  # No resilience.config at all — the gauge still renders with the §Q1 defaults.
  rm -f "$FORGE_DIR/resilience.config"
  local out
  out="$(echo '{"context_window":{"used_percentage":22}}' | run_mirror)"
  assert_contains "$out" "warn 40"
  assert_contains "$out" "hard 50"
}

test_malformed_threshold_falls_back_to_default() {
  # A non-integer threshold value must not render as garbage — fall back to the default.
  cat > "$FORGE_DIR/resilience.config" <<'EOF'
FORGE_ORCH_WARN_PCT=not-a-number
FORGE_ORCH_HARD_PCT=50
EOF
  local out
  out="$(echo '{"context_window":{"used_percentage":10}}' | run_mirror)"
  assert_contains "$out" "warn 40"
}

# ── Role split: orchestrator (default) vs worker ─────────────────────────────

test_defaults_to_orchestrator_thresholds() {
  local out
  out="$(echo '{"context_window":{"used_percentage":10}}' | run_mirror)"
  assert_contains "$out" "warn 40"
  assert_contains "$out" "hard 50"
}

test_worker_role_uses_worker_thresholds() {
  local out
  out="$(echo '{"context_window":{"used_percentage":10}}' | FORGE_SESSION_ROLE=worker run_mirror)"
  assert_contains "$out" "warn 50"
  assert_contains "$out" "hard 60"
}

test_unrecognized_role_falls_back_to_orchestrator() {
  local out
  out="$(echo '{"context_window":{"used_percentage":10}}' | FORGE_SESSION_ROLE=banana run_mirror)"
  assert_contains "$out" "warn 40"
  assert_contains "$out" "hard 50"
}

# ── Breach markers (cosmetic — eye-catch for warn / hard) ────────────────────

test_under_warn_has_no_marker() {
  local out
  out="$(echo '{"context_window":{"used_percentage":22}}' | run_mirror)"
  assert_not_contains "$out" "^"
  assert_not_contains "$out" "!"
}

test_at_or_over_warn_shows_warn_marker() {
  local out
  out="$(echo '{"context_window":{"used_percentage":42}}' | run_mirror)"
  assert_contains "$out" "^"
}

test_at_or_over_hard_shows_hard_marker() {
  local out
  out="$(echo '{"context_window":{"used_percentage":55}}' | run_mirror)"
  assert_contains "$out" "!"
}

# ── Display-only contract ────────────────────────────────────────────────────

test_always_exits_zero() {
  # Display-only: the exit code carries no meaning, so it is always 0 — even on a
  # breach, even on garbage input. A non-zero exit could be read as control flow.
  local rc=0
  echo '{"context_window":{"used_percentage":99}}' | run_mirror >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "mirror over hard limit must still exit 0"

  rc=0
  echo 'garbage' | run_mirror >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "mirror on garbage input must still exit 0"

  rc=0
  printf '' | run_mirror >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "mirror on empty input must still exit 0"
}

test_writes_no_files() {
  # The mirror is a passive display — it must not write anything to .forge/ or the
  # working dir. Snapshot the temp tree before and after; it must be identical.
  local before after
  before="$(find "$WORKDIR" -type f | sort)"
  echo '{"context_window":{"used_percentage":55}}' | run_mirror >/dev/null 2>&1
  after="$(find "$WORKDIR" -type f | sort)"
  assert_eq "$before" "$after" "statusline mirror must not create or modify any files"
}

test_emits_exactly_one_line() {
  # A statusline command's stdout is the status line — it must be a single line.
  local out line_count
  out="$(echo '{"context_window":{"used_percentage":22}}' | run_mirror)"
  line_count="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  assert_eq "1" "$line_count" "statusline output must be exactly one line"
}

# ── Wiring ───────────────────────────────────────────────────────────────────

test_registered_as_statusline_in_settings() {
  # The script is wired into The Forge's own settings.json as the statusLine command,
  # so The Forge dogfoods its own mirror.
  local settings
  settings="$REPO_ROOT/.claude/settings.json"
  assert_file_exists "$settings"
  local cmd
  cmd="$(jq -r '.statusLine.command // empty' "$settings")"
  assert_eq ".claude/statusline/budget-mirror.sh" "$cmd"
}

test_script_is_executable() {
  [[ -x "$MIRROR" ]] || fail "budget-mirror.sh must be executable"
}
