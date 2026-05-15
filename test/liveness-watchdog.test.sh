#!/usr/bin/env bash
# liveness-watchdog.test.sh — tests for scripts/liveness-watchdog.sh
#
# The watchdog reads .forge/heartbeat/<slug>, checks its age against a
# configurable threshold, and on a stale heartbeat captures diagnostics + kills
# the wedged claude process. These tests drive it with a temp .forge dir, a
# controllable "now" (FORGE_WATCHDOG_NOW), and a stubbed kill command
# (FORGE_WATCHDOG_KILL_CMD) so no real process is ever signalled.
#
# macOS-only note: the watchdog guards against non-Darwin hosts and uses BSD
# `stat -f`. These tests run on macOS (The Forge's dev host + CI is ubuntu —
# see the platform-skip note in test_* below).

source "$TEST_DIR/lib/assert.sh"

WATCHDOG="$REPO_ROOT/scripts/liveness-watchdog.sh"

# A fixed slug for every test — we pass --slug explicitly so the tests do not
# depend on the temp dir's basename slugifying to anything in particular.
SLUG="test-session"

setup() {
  WORKDIR="$(mktemp -d)"
  export FORGE_DIR="$WORKDIR/.forge"
  mkdir -p "$FORGE_DIR/heartbeat"
  export FORGE_WATCHDOG_LOG="$FORGE_DIR/watchdog.log"
  # A kill-command stub: record the PID it was asked to kill, never signal.
  KILL_RECORD="$WORKDIR/killed.txt"
  cat > "$WORKDIR/fake-kill.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" >> "$KILL_RECORD"
EOF
  chmod +x "$WORKDIR/fake-kill.sh"
  export FORGE_WATCHDOG_KILL_CMD="bash $WORKDIR/fake-kill.sh"
}

teardown() {
  rm -rf "$WORKDIR"
  unset FORGE_DIR FORGE_WATCHDOG_LOG FORGE_WATCHDOG_KILL_CMD FORGE_WATCHDOG_NOW \
        FORGE_HEARTBEAT_TIMEOUT_SECONDS
}

# Touch the heartbeat file with a specific mtime (epoch seconds). BSD `touch -t`
# wants [[CC]YY]MMDDhhmm[.SS]; convert from epoch with `date -r`.
_set_heartbeat_mtime() {
  local epoch="$1"
  local hb="$FORGE_DIR/heartbeat/$SLUG"
  : > "$hb"
  touch -t "$(date -r "$epoch" +%Y%m%d%H%M.%S)" "$hb"
}

# ── Platform guard ───────────────────────────────────────────────────────────
# The watchdog is macOS-only. If these tests are ever run on a non-Darwin host
# (e.g. CI on ubuntu), the watchdog exits 1 from require_darwin before doing
# anything — so the behavioural assertions below would all fail spuriously.
# Skip the whole suite gracefully off Darwin: a single passing no-op test.
test_darwin_only_or_skip() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    # Not Darwin — confirm the guard fires and bail out of the suite cleanly.
    local rc=0
    bash "$WATCHDOG" --slug "$SLUG" >/dev/null 2>&1 || rc=$?
    assert_exit_code 1 "$rc" "non-Darwin host: watchdog should refuse to run"
    return 0
  fi
  # On Darwin the rest of the suite runs for real.
  return 0
}

# Guard helper the behavioural tests call first — returns 1 (skips the test body
# by early-return, still a pass) when off Darwin so CI on ubuntu stays green.
_skip_if_not_darwin() {
  [[ "$(uname -s)" != "Darwin" ]]
}

# ── No heartbeat file ────────────────────────────────────────────────────────
test_no_heartbeat_file_exits_2() {
  _skip_if_not_darwin && return 0
  # heartbeat dir exists but no file for this slug.
  local rc=0
  bash "$WATCHDOG" --slug "$SLUG" >/dev/null 2>&1 || rc=$?
  assert_exit_code 2 "$rc" "missing heartbeat file → exit 2 (nothing to watch)"
  assert_file_exists "$FORGE_WATCHDOG_LOG" "watchdog should log the no-heartbeat case"
  assert_contains "$(cat "$FORGE_WATCHDOG_LOG")" "no heartbeat file" \
    "log should explain there was nothing to watch"
}

# ── Fresh heartbeat ──────────────────────────────────────────────────────────
test_fresh_heartbeat_exits_0_quietly() {
  _skip_if_not_darwin && return 0
  # Heartbeat touched 'now' — well under any timeout.
  local now=2000000000
  _set_heartbeat_mtime "$now"
  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "fresh heartbeat → exit 0"
  # Quiet success: a fresh heartbeat must not be killed.
  assert_file_absent "$KILL_RECORD" "fresh heartbeat must not trigger a kill"
}

test_heartbeat_just_under_timeout_is_fresh() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  # 899s old, timeout 900 → still fresh (strict <).
  _set_heartbeat_mtime "$((now - 899))"
  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "age just under timeout → fresh"
  assert_file_absent "$KILL_RECORD" "age under timeout must not trigger a kill"
}

# ── Stale heartbeat ──────────────────────────────────────────────────────────
test_stale_heartbeat_captures_diagnostics_and_kills() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  # 1000s old, timeout 900 → stale.
  _set_heartbeat_mtime "$((now - 1000))"

  # A transcript to capture the tail of.
  local transcript="$WORKDIR/transcript.jsonl"
  printf '{"type":"user","line":1}\n{"type":"assistant","line":2}\n' > "$transcript"

  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 --transcript "$transcript" \
    >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "stale heartbeat handled → exit 0"

  local log
  log="$(cat "$FORGE_WATCHDOG_LOG")"
  assert_contains "$log" "STALE heartbeat" "stale event must be logged"
  assert_contains "$log" "diagnostics" "diagnostics capture must be logged"
  assert_contains "$log" "transcript tail" "transcript tail must be captured"
  assert_contains "$log" '{"type":"assistant","line":2}' \
    "the actual transcript content must be in the log"

  # The kill stub recorded a PID — the watchdog asked to kill *something*.
  # find_claude_pid is a best-effort pgrep; on a dev host running this very
  # test there may or may not be a `claude` process. Accept either: a kill was
  # recorded, OR the log says no process was found. Both are correct handling.
  if [[ -f "$KILL_RECORD" ]]; then
    assert_ne "" "$(cat "$KILL_RECORD")" "if a kill ran, it must carry a PID"
  else
    assert_contains "$log" "no live claude process found" \
      "no process to kill → must say so in the log"
  fi
}

test_stale_heartbeat_with_no_process_logs_recovery_note() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  _set_heartbeat_mtime "$((now - 5000))"
  # Force "no process found" by pointing the kill stub at a recorder but
  # relying on find_claude_pid; we can't guarantee no claude runs, so instead
  # assert the universal post-handling line is always logged.
  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc"
  assert_contains "$(cat "$FORGE_WATCHDOG_LOG")" "crash-recovery path" \
    "watchdog must log that the non-clean exit drops into crash recovery"
}

# ── PID-file precedence (slice 1 of sub-phase 3d, rec #22) ───────────────────
# The relaunch loop writes its claude child PID to
# $FORGE_DIR/continuation/<slug>/claude.pid. find_claude_pid must read that
# file first and validate with `kill -0` before falling back to the existing
# pgrep heuristic.

test_pid_file_is_preferred_when_valid() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  _set_heartbeat_mtime "$((now - 1000))"

  # Spawn a long-lived sleep directly in the test shell (NOT in a command
  # substitution — that would orphan the child when the inner subshell exits
  # and `kill -0` would then return "no such process"). Capture its PID and
  # write to claude.pid; this is the "claude child" stand-in.
  sleep 60 &
  local pid=$!
  local pid_dir="$FORGE_DIR/continuation/$SLUG"
  mkdir -p "$pid_dir"
  printf '%s\n' "$pid" > "$pid_dir/claude.pid"

  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "stale heartbeat handled → exit 0"

  # The fake-kill stub should have recorded exactly the PID-file value, not
  # a pgrep hit. (FORGE_WATCHDOG_KILL_CMD is set in setup() to a recorder.)
  assert_file_exists "$KILL_RECORD" "kill stub must have been invoked"
  assert_eq "$pid" "$(head -n1 "$KILL_RECORD")" \
    "the PID file value must be what the watchdog targets"

  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

test_pid_file_malformed_falls_back() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  _set_heartbeat_mtime "$((now - 1000))"

  # Malformed PID file — not a number.
  local pid_dir="$FORGE_DIR/continuation/$SLUG"
  mkdir -p "$pid_dir"
  printf '%s\n' "not-a-pid" > "$pid_dir/claude.pid"

  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "malformed PID file → fall back, still exit 0"
  # Watchdog must not have crashed; either a pgrep hit was recorded or the log
  # carries the no-process-found note. Both are valid fallback behavior.
  if [[ ! -f "$KILL_RECORD" ]]; then
    assert_contains "$(cat "$FORGE_WATCHDOG_LOG")" "no live claude process found" \
      "malformed PID + no pgrep hit → log the recovery note"
  fi
}

test_pid_file_dead_process_falls_back() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  _set_heartbeat_mtime "$((now - 1000))"

  # Spawn and immediately reap a sleep so the PID names a dead one.
  sleep 30 &
  local pid=$!
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  local pid_dir="$FORGE_DIR/continuation/$SLUG"
  mkdir -p "$pid_dir"
  printf '%s\n' "$pid" > "$pid_dir/claude.pid"

  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "dead PID → fall back, still exit 0"
  # Confirm fall-through: if the kill stub ran, it must NOT carry the dead PID.
  if [[ -f "$KILL_RECORD" ]]; then
    assert_ne "$pid" "$(head -n1 "$KILL_RECORD")" \
      "dead PID from file must not be passed to kill"
  fi
}

test_pid_file_absent_falls_back_to_pgrep() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  _set_heartbeat_mtime "$((now - 1000))"

  # No PID file at all — explicitly the partial-upgrade case.
  local pid_dir="$FORGE_DIR/continuation/$SLUG"
  [[ -d "$pid_dir" ]] && rm -f "$pid_dir/claude.pid"

  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "no PID file → fall back, still exit 0"
}

# ── Timeout resolution / precedence ──────────────────────────────────────────
test_timeout_flag_overrides_everything() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  # 100s old. Env says timeout 50 (would be stale), flag says 900 (fresh).
  # Flag must win → fresh → no kill.
  _set_heartbeat_mtime "$((now - 100))"
  local rc=0
  FORGE_WATCHDOG_NOW="$now" FORGE_HEARTBEAT_TIMEOUT_SECONDS=50 \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc"
  assert_file_absent "$KILL_RECORD" "--timeout flag must override the env var"
}

test_timeout_env_var_used_when_no_flag() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  # 100s old, env timeout 50 → stale (100 >= 50).
  _set_heartbeat_mtime "$((now - 100))"
  local rc=0
  FORGE_WATCHDOG_NOW="$now" FORGE_HEARTBEAT_TIMEOUT_SECONDS=50 \
    bash "$WATCHDOG" --slug "$SLUG" >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "stale-by-env handled → exit 0"
  assert_contains "$(cat "$FORGE_WATCHDOG_LOG")" "STALE heartbeat" \
    "FORGE_HEARTBEAT_TIMEOUT_SECONDS must be honoured when no --timeout flag"
}

test_timeout_read_from_resilience_config() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  # No flag, no env — write a resilience.config with a small timeout.
  cat > "$FORGE_DIR/resilience.config" <<'EOF'
FORGE_HEARTBEAT_TIMEOUT_SECONDS=30
EOF
  _set_heartbeat_mtime "$((now - 60))"   # 60s old, config timeout 30 → stale
  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc"
  assert_contains "$(cat "$FORGE_WATCHDOG_LOG")" "STALE heartbeat" \
    "timeout must fall through to resilience.config"
}

# ── Argument handling ────────────────────────────────────────────────────────
test_unknown_arg_exits_1() {
  _skip_if_not_darwin && return 0
  local rc=0
  bash "$WATCHDOG" --bogus-flag >/dev/null 2>&1 || rc=$?
  assert_exit_code 1 "$rc" "unknown argument → exit 1"
}

test_help_exits_0() {
  # --help short-circuits before the platform guard, so this is safe everywhere.
  local out rc=0
  out="$(bash "$WATCHDOG" --help 2>&1)" || rc=$?
  assert_exit_code 0 "$rc" "--help → exit 0"
  assert_contains "$out" "liveness-watchdog.sh" "help text must name the script"
  assert_contains "$out" "macOS only" "help text must state the macOS limitation"
}

# ── Diagnostic capture: transcript absent ────────────────────────────────────
test_missing_transcript_is_not_fatal() {
  _skip_if_not_darwin && return 0
  local now=2000000000
  _set_heartbeat_mtime "$((now - 1000))"
  local rc=0
  FORGE_WATCHDOG_NOW="$now" \
    bash "$WATCHDOG" --slug "$SLUG" --timeout 900 \
    --transcript "$WORKDIR/does-not-exist.jsonl" >/dev/null 2>&1 || rc=$?
  assert_exit_code 0 "$rc" "a missing transcript must not fail the watchdog"
  assert_contains "$(cat "$FORGE_WATCHDOG_LOG")" "transcript: not provided or not found" \
    "a missing transcript should be noted, not crash the run"
}
