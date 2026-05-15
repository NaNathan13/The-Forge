#!/usr/bin/env bash
set -uo pipefail

# liveness-watchdog.sh — P2 single-session resilience, the liveness watchdog
# (design doc §4b). macOS-only — see the limitation note below.
#
# `launchd` knows whether the relaunch-loop *process* is alive. It does NOT know
# whether the `claude` session inside it is making *progress* — a session can be
# wedged (a stalled permission prompt, a hung tool call) while the process is
# technically up. R3 names this the "observability black hole".
#
# This watchdog closes that gap. It reads the heartbeat file the Stop hook
# touches every turn, checks its age, and when the heartbeat is stale past a
# configurable threshold it:
#   1. captures diagnostics (last transcript lines, tmux scrollback) to the log,
#   2. kills the wedged `claude` process.
# The kill produces a non-clean exit, which the relaunch loop propagates to
# `launchd` — i.e. the watchdog turns a *silent hang* into a *detected crash*
# that the existing two-layer recovery already handles. No new recovery path.
#
# The watchdog does NOT run itself on a timer — it does one check and exits. It
# is meant to be driven periodically by its own `launchd` agent (a
# `StartInterval` job); see templates/launchd/com.forge.project.watchdog.plist.
#
# ── macOS only ───────────────────────────────────────────────────────────────
# This watchdog is part of P2's macOS-only crash layer. It uses `stat -f` (BSD
# stat) for file age and assumes a `launchd` `StartInterval` job drives it.
# Linux (`systemd` timer + `stat -c`) and Windows are a noted future follow-up,
# out of scope for sub-phase 1b. The script fails loud on a non-Darwin host
# rather than silently doing the wrong thing.
#
# Bash 3.2-clean (macOS system bash): no associative arrays, no `mapfile`.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   liveness-watchdog.sh [--slug <slug>] [--timeout <seconds>]
#                        [--transcript <path>] [--tmux-session <name>]
#                        [--dir <project-dir>]
#
#   --slug          Session slug (default: derived from --dir / cwd via
#                   scripts/continuation.sh).
#   --timeout       Heartbeat-age threshold in seconds. Precedence: this flag >
#                   FORGE_HEARTBEAT_TIMEOUT_SECONDS env > resilience.config >
#                   built-in default of 900.
#   --transcript    Path to the session transcript JSONL, for diagnostic
#                   capture. Optional — skipped if absent/unset.
#   --tmux-session  tmux session name to scrape scrollback from, for diagnostic
#                   capture. Optional — skipped if absent/unset or tmux missing.
#   --dir           Project directory (default: cwd). Used for slug derivation
#                   and to locate .forge/.
#
# ── Environment ──────────────────────────────────────────────────────────────
#   FORGE_DIR          Override the .forge directory (default: git repo root's
#                      .forge, falling back to <project-dir>/.forge). Tests set
#                      this to a temp dir.
#   FORGE_HEARTBEAT_TIMEOUT_SECONDS   Heartbeat-age threshold (see --timeout).
#   FORGE_WATCHDOG_LOG Override the watchdog log path (default:
#                      $FORGE_DIR/watchdog.log). Tests set this to a temp file.
#   FORGE_WATCHDOG_KILL_CMD  Override the kill command, for tests. Receives the
#                      PID as $1. Default: `kill -TERM`, then `kill -KILL` after
#                      a short grace period if the process survives.
#   FORGE_WATCHDOG_NOW Override "current time" (epoch seconds), for tests.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0  heartbeat fresh, OR a stale heartbeat was handled (diagnostics + kill)
#   1  runtime error (bad args, cannot resolve slug, non-Darwin host)
#   2  no heartbeat file yet — nothing to watch (a session that never started,
#      or started but has not had a Stop hook fire). Logged, not fatal.
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TIMEOUT=900
KILL_GRACE_SECONDS=5

# ── Platform guard ───────────────────────────────────────────────────────────
# macOS only. `stat -f` is BSD; `launchd` is macOS. Fail loud on anything else.
require_darwin() {
  local uname_s
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  if [[ "$uname_s" != "Darwin" ]]; then
    echo "liveness-watchdog.sh: macOS only — this host is '$uname_s'." >&2
    echo "  Linux (systemd) / Windows crash recovery is a future follow-up." >&2
    return 1
  fi
}

# ── Locate the .forge directory ──────────────────────────────────────────────
# Mirrors scripts/continuation.sh: explicit FORGE_DIR wins, else the git repo
# root's .forge, else <project-dir>/.forge.
resolve_forge_dir() {
  local project_dir="$1"
  if [[ -n "${FORGE_DIR:-}" ]]; then
    printf '%s\n' "$FORGE_DIR"
    return 0
  fi
  local root
  if root="$(cd "$project_dir" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s/.forge\n' "$root"
  else
    printf '%s/.forge\n' "$project_dir"
  fi
}

# ── Heartbeat-timeout resolution ─────────────────────────────────────────────
# Precedence: explicit --timeout > FORGE_HEARTBEAT_TIMEOUT_SECONDS env >
# resilience.config > built-in default.
resolve_timeout() {
  local explicit="$1" forge_dir="$2"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  if [[ -n "${FORGE_HEARTBEAT_TIMEOUT_SECONDS:-}" ]]; then
    printf '%s\n' "$FORGE_HEARTBEAT_TIMEOUT_SECONDS"
    return 0
  fi
  local cfg="$forge_dir/resilience.config"
  if [[ -f "$cfg" ]]; then
    local val
    val="$(
      # shellcheck disable=SC1090
      . "$cfg" >/dev/null 2>&1 || true
      printf '%s' "${FORGE_HEARTBEAT_TIMEOUT_SECONDS:-}"
    )"
    if [[ -n "$val" ]]; then
      printf '%s\n' "$val"
      return 0
    fi
  fi
  printf '%s\n' "$DEFAULT_TIMEOUT"
}

# ── Slug derivation ──────────────────────────────────────────────────────────
# Defer to scripts/continuation.sh — the slug rule lives in exactly one place.
resolve_slug() {
  local explicit="$1" project_dir="$2"
  if [[ -n "$explicit" ]]; then
    printf '%s\n' "$explicit"
    return 0
  fi
  local helper="$SCRIPT_DIR/continuation.sh"
  if [[ ! -x "$helper" && ! -f "$helper" ]]; then
    echo "liveness-watchdog.sh: cannot resolve slug — $helper not found" >&2
    return 1
  fi
  bash "$helper" slug "$project_dir"
}

# ── File age in seconds ──────────────────────────────────────────────────────
# BSD `stat -f %m` gives the mtime as epoch seconds. "now" is overridable for
# tests via FORGE_WATCHDOG_NOW.
file_age_seconds() {
  local path="$1"
  local mtime now
  mtime="$(stat -f %m "$path" 2>/dev/null)" || return 1
  now="${FORGE_WATCHDOG_NOW:-$(date +%s)}"
  printf '%s\n' "$((now - mtime))"
}

# ── Logging ──────────────────────────────────────────────────────────────────
# Append a timestamped line to the watchdog log. The log is the after-the-fact
# record — "the session that died an hour ago" must still be visible (R3).
log_line() {
  local log="$1"; shift
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$(dirname "$log")" 2>/dev/null || true
  printf '%s liveness-watchdog: %s\n' "$ts" "$*" >> "$log"
}

# ── Diagnostic capture ───────────────────────────────────────────────────────
# Dump what we can about the wedged session to the log before killing it: the
# tail of the transcript JSONL and the tmux scrollback. Both are best-effort —
# a missing transcript or no tmux is not a watchdog failure, it just means less
# context in the post-mortem.
capture_diagnostics() {
  local log="$1" transcript="$2" tmux_session="$3"

  log_line "$log" "── diagnostics: capturing state of the wedged session ──"

  if [[ -n "$transcript" && -f "$transcript" ]]; then
    log_line "$log" "transcript tail ($transcript):"
    # Last 40 lines of the JSONL — enough to see the last few turns / the
    # wedged tool call without dumping the whole session.
    tail -n 40 "$transcript" 2>/dev/null | while IFS= read -r line; do
      printf '    %s\n' "$line" >> "$log"
    done
  else
    log_line "$log" "transcript: not provided or not found — skipped"
  fi

  if [[ -n "$tmux_session" ]] && command -v tmux >/dev/null 2>&1; then
    if tmux has-session -t "$tmux_session" 2>/dev/null; then
      log_line "$log" "tmux scrollback (session '$tmux_session'):"
      # -p prints to stdout, -S -200 starts 200 lines back into the scrollback.
      tmux capture-pane -p -t "$tmux_session" -S -200 2>/dev/null | while IFS= read -r line; do
        printf '    %s\n' "$line" >> "$log"
      done
    else
      log_line "$log" "tmux session '$tmux_session': not found — skipped"
    fi
  else
    log_line "$log" "tmux: not provided or tmux not installed — skipped"
  fi

  log_line "$log" "── end diagnostics ──"
}

# ── Kill the wedged claude process ───────────────────────────────────────────
# TERM first, then KILL after a grace period if it survives. Overridable for
# tests via FORGE_WATCHDOG_KILL_CMD (receives the PID as $1).
kill_process() {
  local log="$1" pid="$2"

  if [[ -n "${FORGE_WATCHDOG_KILL_CMD:-}" ]]; then
    log_line "$log" "killing PID $pid via FORGE_WATCHDOG_KILL_CMD"
    # shellcheck disable=SC2086
    $FORGE_WATCHDOG_KILL_CMD "$pid"
    return 0
  fi

  log_line "$log" "sending SIGTERM to wedged claude process (PID $pid)"
  kill -TERM "$pid" 2>/dev/null || {
    log_line "$log" "SIGTERM failed — process $pid may already be gone"
    return 0
  }

  # Give it a moment to exit cleanly, then SIGKILL if still alive.
  local waited=0
  while [[ "$waited" -lt "$KILL_GRACE_SECONDS" ]]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      log_line "$log" "process $pid exited after SIGTERM"
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done

  log_line "$log" "process $pid survived SIGTERM — sending SIGKILL"
  kill -KILL "$pid" 2>/dev/null || true
}

# ── Find the wedged claude process for this session ──────────────────────────
# Best-effort: the slug names the session, but the claude process does not
# carry the slug. We match a `claude` process whose working directory or
# command line references the project dir. If nothing matches, we log and
# treat the hang as already resolved (the process died on its own).
find_claude_pid() {
  local project_dir="$1"
  # Prefer the slug-namespaced PID file the relaunch loop writes — exact
  # target, no ambiguity on multi-project hosts. Validate with `kill -0`
  # before trusting it; fall through to the heuristic if absent, unreadable,
  # malformed, or names a dead process (so partial upgrades / orphaned files
  # don't regress current behavior).
  local pid_file="$forge_dir/continuation/$slug/claude.pid"
  local candidate=""
  if [[ -f "$pid_file" ]]; then
    candidate="$(cat "$pid_file" 2>/dev/null)"
    if [[ "$candidate" =~ ^[0-9]+$ ]] && kill -0 "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  # Fallback heuristic — preserves current behavior during partial upgrades.
  # `pgrep -f` matches against the full command line. `claude -p` is the
  # headless invocation the relaunch loop runs. A host running multiple Forge
  # projects should give each its own watchdog agent scoped by --dir, and
  # operators can override via FORGE_WATCHDOG_KILL_CMD.
  pgrep -f 'claude' 2>/dev/null | head -n 1
}

# ── Argument parsing ─────────────────────────────────────────────────────────
ARG_SLUG=""
ARG_TIMEOUT=""
ARG_TRANSCRIPT=""
ARG_TMUX_SESSION=""
ARG_DIR="$PWD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)         ARG_SLUG="${2:-}";          shift 2 ;;
    --timeout)      ARG_TIMEOUT="${2:-}";       shift 2 ;;
    --transcript)   ARG_TRANSCRIPT="${2:-}";    shift 2 ;;
    --tmux-session) ARG_TMUX_SESSION="${2:-}";  shift 2 ;;
    --dir)          ARG_DIR="${2:-}";           shift 2 ;;
    -h|--help)
      sed -n '3,62p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "liveness-watchdog.sh: unexpected argument: $1 (try --help)" >&2
      exit 1
      ;;
  esac
done

# ── Main ─────────────────────────────────────────────────────────────────────
main() {
  require_darwin || exit 1

  local forge_dir slug timeout heartbeat log
  forge_dir="$(resolve_forge_dir "$ARG_DIR")"
  log="${FORGE_WATCHDOG_LOG:-$forge_dir/watchdog.log}"

  slug="$(resolve_slug "$ARG_SLUG" "$ARG_DIR")" || exit 1
  if [[ -z "$slug" ]]; then
    echo "liveness-watchdog.sh: could not resolve session slug" >&2
    exit 1
  fi

  timeout="$(resolve_timeout "$ARG_TIMEOUT" "$forge_dir")"

  heartbeat="$forge_dir/heartbeat/$slug"

  # No heartbeat file → nothing to watch. This is not an error: it is a session
  # that never started, or started but has not had a Stop hook fire yet. Log it
  # at exit 2 so an operator tailing the log can tell "watchdog ran, found
  # nothing" from "watchdog never ran".
  if [[ ! -e "$heartbeat" ]]; then
    log_line "$log" "no heartbeat file at $heartbeat (slug '$slug') — nothing to watch"
    exit 2
  fi

  local age
  age="$(file_age_seconds "$heartbeat")" || {
    log_line "$log" "could not stat heartbeat $heartbeat — treating as nothing to watch"
    exit 2
  }

  if [[ "$age" -lt "$timeout" ]]; then
    # Fresh heartbeat — the session is making progress. Quiet success: do not
    # spam the log on every interval tick when all is well.
    exit 0
  fi

  # ── Stale heartbeat: the session is hung, not working. ─────────────────────
  log_line "$log" "STALE heartbeat for slug '$slug': age ${age}s >= timeout ${timeout}s — session is hung"

  capture_diagnostics "$log" "$ARG_TRANSCRIPT" "$ARG_TMUX_SESSION"

  local pid
  pid="$(find_claude_pid "$ARG_DIR")"
  if [[ -n "$pid" ]]; then
    kill_process "$log" "$pid"
  else
    log_line "$log" "no live claude process found — the hung session already exited; relaunch loop / launchd will recover"
  fi

  log_line "$log" "stale heartbeat handled — non-clean exit drops into the crash-recovery path"
  exit 0
}

main
