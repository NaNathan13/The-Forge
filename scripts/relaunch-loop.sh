#!/usr/bin/env bash
set -uo pipefail

# relaunch-loop.sh — P2's external relaunch loop (design doc §1 / §2).
#
# Huntley's original Ralph pattern — NOT the `ralph-loop` plugin. A plain shell
# loop that owns one long-lived session's lifecycle: it relaunches `claude` fresh
# after every clean context-limit handoff so each generation starts with an empty
# context window. The continuation file (written by the session, re-injected by the
# SessionStart hook) is the only state carried across — the loop never touches it.
#
# It is a script, not a Claude session: zero token cost. It only reads `claude`'s
# exit code, the JSON `.result` / `.usage` fields, and a generation counter.
#
# ── The loop, per design doc §1 ──────────────────────────────────────────────
# Each iteration runs `claude -p --output-format json` (plain `-p` = fresh window;
# no resume/session flags — none exist, see design §Q2) and then:
#
#   - non-zero exit            → crash/OOM/panic/signal. PROPAGATE the exit code to
#                                launchd; do NOT silently respin. This is the
#                                boundary between the two supervision layers.
#   - exit 0, FORGE_COMPLETE   → work is genuinely done. Break, exit 0. launchd's
#                                SuccessfulExit=false keeps the loop from respinning.
#   - exit 0, FORGE_CONTINUE   → clean handoff. Record the generation, run the
#                                thrash circuit breaker, run the budget gate, then
#                                relaunch fresh.
#   - exit 0, no sentinel      → fault, not a handoff (design §1). Exit non-zero
#                                rather than spinning.
#
# ── Budget gate (design §Q1 / §Q2) ───────────────────────────────────────────
# After a clean handoff the loop parses `.usage`, turns the token counts into a
# percentage of the context window, resolves the session role (orchestrator vs
# worker) to its warn/hard threshold pair from resilience.config, and:
#   used < warn          → relaunch normally
#   warn <= used < hard  → relaunch, signal the next generation to hand off promptly
#   used >= hard         → the session is over the hard line; the loop does not
#                          start another unbounded generation — it stops.
# The "hand off promptly" signal is written to a small file the SessionStart hook
# (slice 5) reads; this loop only writes the signal, it does not inject it.
#
# ── Thrash circuit breaker (design §2 / §Q3) ─────────────────────────────────
# Q3's monotonic generation counter makes handoff thrash trivial to see: if more
# than FORGE_THRASH_MAX_GENERATIONS handoffs happen within
# FORGE_THRASH_WINDOW_SECONDS, the loop trips its breaker and exits non-zero so a
# human is alerted. An infinite hand-off loop is a bug, not a state to spin in.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   relaunch-loop.sh [--role orchestrator|worker] [--slug <slug>]
#
#   --role   Session role → which warn/hard threshold pair the budget gate uses.
#            Default: orchestrator (the long-lived sessions P2 hardens).
#   --slug   Session slug → which .forge/continuation/<slug>/ directory the
#            generation counter and "hand off promptly" signal live under.
#            Default: derived from the working directory (via continuation.sh).
#
# ── Environment ──────────────────────────────────────────────────────────────
#   FORGE_DIR                Override the .forge directory (default: repo-root
#                            /.forge). Tests set this to a temp dir.
#   FORGE_CLAUDE_BIN         The claude binary to invoke. Default: `claude` on
#                            PATH. Tests point this at test/stubs/claude.
#   FORGE_MAX_GENERATIONS    Hard cap on total handoff generations this run — a
#                            test/CI safety net so a misbehaving stub cannot spin
#                            forever. Default: 0 (unlimited).
#
# Thresholds, throttle, and the circuit-breaker window are read from
# resilience.config (sourced, never executed). resilience.config keys consumed:
#   FORGE_ORCH_WARN_PCT / FORGE_ORCH_HARD_PCT
#   FORGE_WORKER_WARN_PCT / FORGE_WORKER_HARD_PCT
#   FORGE_CONTEXT_WINDOW_TOKENS
#   FORGE_THROTTLE_SECONDS
#   FORGE_THRASH_MAX_GENERATIONS / FORGE_THRASH_WINDOW_SECONDS
# Every key above is on the shipped config surface; the built-in defaults below
# are the fallback for when a key is absent or malformed.
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0    work complete (FORGE_COMPLETE) — clean stop
#   1    exit-0 generation with no recognised sentinel — treated as a fault
#   2    thrash circuit breaker tripped — too many handoffs too fast
#   3    budget hard line crossed — session is over the hard threshold
#   4    runtime/config error (bad args, missing config, malformed JSON)
#   *    any other code = a `claude` crash exit, propagated verbatim to launchd
# ─────────────────────────────────────────────────────────────────────────────

# Sentinel strings carried in `.result` (design §1, amended §1 sentinel contract).
SENTINEL_CONTINUE="FORGE_CONTINUE"
SENTINEL_COMPLETE="FORGE_COMPLETE"

# Exit codes — named so the loop body reads as intent, not magic numbers.
EXIT_COMPLETE=0
EXIT_NO_SENTINEL=1
EXIT_THRASH=2
EXIT_BUDGET_HARD=3
EXIT_CONFIG=4

# Built-in circuit-breaker defaults — fallback for when resilience.config does
# not set the thrash pair (or sets a malformed value). The shipped config
# carries these same values as its documented surface.
DEFAULT_THRASH_MAX_GENERATIONS=5
DEFAULT_THRASH_WINDOW_SECONDS=300

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTINUATION_SH="$SCRIPT_DIR/continuation.sh"

log() { printf 'relaunch-loop: %s\n' "$*" >&2; }
die() { log "$*"; exit "$EXIT_CONFIG"; }

# ── .forge directory + config ────────────────────────────────────────────────
# Honour an explicit FORGE_DIR (tests, custom layouts); otherwise prefer the git
# repo root, falling back to the current directory. Mirrors continuation.sh.
resolve_forge_dir() {
  if [[ -n "${FORGE_DIR:-}" ]]; then
    printf '%s\n' "$FORGE_DIR"
    return 0
  fi
  local root
  if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s/.forge\n' "$root"
  else
    printf '%s/.forge\n' "$PWD"
  fi
}

# Read one KEY from resilience.config without letting the config clobber our
# locals — it is sourced in a subshell, then only the requested var is printed.
# Prints the value (possibly empty) on stdout; never fails the loop.
config_get() {
  local key="$1" cfg="$2"
  [[ -f "$cfg" ]] || return 0
  (
    # shellcheck disable=SC1090
    . "$cfg" >/dev/null 2>&1 || true
    eval "printf '%s' \"\${$key:-}\""
  )
}

# ── Argument parsing ─────────────────────────────────────────────────────────
ROLE="orchestrator"
SLUG=""
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role) ROLE="${2:-}"; shift 2 ;;
      --slug) SLUG="${2:-}"; shift 2 ;;
      -h|--help)
        sed -n '3,72p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
      *) die "unexpected argument: $1 (try --help)" ;;
    esac
  done
  case "$ROLE" in
    orchestrator|worker) ;;
    *) die "unknown --role: $ROLE (expected 'orchestrator' or 'worker')" ;;
  esac
}

# ── Budget gate ──────────────────────────────────────────────────────────────
# Turn a `.usage` JSON block into a whole-number percentage of the context
# window. The window denominator is FORGE_CONTEXT_WINDOW_TOKENS from the config.
# Input tokens are the load-bearing measure of how full the *next* generation's
# window would start — cache_* and output tokens are not carried into a fresh
# window — so the gate measures input_tokens against the window.
usage_pct() {
  local usage="$1" window="$2"
  local input
  input="$(jq -r '.input_tokens // 0' <<<"$usage" 2>/dev/null)"
  [[ "$input" =~ ^[0-9]+$ ]] || { printf 'ERR\n'; return 1; }
  [[ "$window" =~ ^[0-9]+$ && "$window" -gt 0 ]] || { printf 'ERR\n'; return 1; }
  # Integer percentage, floored — good enough for a warn/hard gate.
  printf '%s\n' "$(( input * 100 / window ))"
}

# Resolve the warn/hard pair for the active role; echoes "WARN HARD".
resolve_thresholds() {
  local cfg="$1" warn hard
  if [[ "$ROLE" == "worker" ]]; then
    warn="$(config_get FORGE_WORKER_WARN_PCT "$cfg")"
    hard="$(config_get FORGE_WORKER_HARD_PCT "$cfg")"
  else
    warn="$(config_get FORGE_ORCH_WARN_PCT "$cfg")"
    hard="$(config_get FORGE_ORCH_HARD_PCT "$cfg")"
  fi
  # Fall back to the design §Q1 shipped defaults if the config is silent.
  [[ "$warn" =~ ^[0-9]+$ ]] || warn=$([[ "$ROLE" == worker ]] && echo 50 || echo 40)
  [[ "$hard" =~ ^[0-9]+$ ]] || hard=$([[ "$ROLE" == worker ]] && echo 60 || echo 50)
  printf '%s %s\n' "$warn" "$hard"
}

# Write the "hand off promptly" signal the SessionStart hook (slice 5) reads.
# The loop only writes it; injecting it into the next generation is the hook's job.
write_handoff_signal() {
  local forge_dir="$1" slug="$2" pct="$3"
  local sigdir="$forge_dir/continuation/$slug"
  mkdir -p "$sigdir" 2>/dev/null || return 0
  printf 'hand-off-promptly used=%s%%\n' "$pct" > "$sigdir/handoff-signal"
}

clear_handoff_signal() {
  local forge_dir="$1" slug="$2"
  rm -f "$forge_dir/continuation/$slug/handoff-signal" 2>/dev/null || true
}

# The gate proper. Returns:
#   0 — below warn; relaunch normally (handoff signal cleared)
#   0 — warn<=used<hard; relaunch, handoff signal written
#   EXIT_BUDGET_HARD — used>=hard; caller must stop, do not relaunch
#   EXIT_CONFIG — usage/config could not be parsed
budget_gate() {
  local usage="$1" forge_dir="$2" slug="$3" cfg="$4"
  local window pct warn hard
  window="$(config_get FORGE_CONTEXT_WINDOW_TOKENS "$cfg")"
  [[ "$window" =~ ^[0-9]+$ && "$window" -gt 0 ]] || window=200000

  pct="$(usage_pct "$usage" "$window")"
  if [[ "$pct" == "ERR" ]]; then
    log "budget gate: could not parse .usage / window — treating as a fault"
    return "$EXIT_CONFIG"
  fi

  read -r warn hard <<<"$(resolve_thresholds "$cfg")"

  if [[ "$pct" -ge "$hard" ]]; then
    log "budget gate: ${ROLE} at ${pct}% >= hard ${hard}% — stopping, no further generation"
    return "$EXIT_BUDGET_HARD"
  elif [[ "$pct" -ge "$warn" ]]; then
    log "budget gate: ${ROLE} at ${pct}% >= warn ${warn}% — relaunch, next gen hands off promptly"
    write_handoff_signal "$forge_dir" "$slug" "$pct"
    return 0
  else
    log "budget gate: ${ROLE} at ${pct}% < warn ${warn}% — relaunch normally"
    clear_handoff_signal "$forge_dir" "$slug"
    return 0
  fi
}

# ── Thrash circuit breaker ───────────────────────────────────────────────────
# Records a unix timestamp per handoff generation, keeps a sliding window, and
# trips when the window holds more than MAX entries. State lives in a single
# file under the slug's continuation dir so it survives nothing — it is per-run
# scratch, recreated each loop start.
THRASH_FILE=""

thrash_init() {
  local forge_dir="$1" slug="$2"
  local dir="$forge_dir/continuation/$slug"
  mkdir -p "$dir" 2>/dev/null || true
  THRASH_FILE="$dir/.thrash-window"
  : > "$THRASH_FILE"
}

# Record this handoff and test the window. Returns EXIT_THRASH if tripped, 0 otherwise.
thrash_check() {
  local max="$1" window_secs="$2"
  local now cutoff kept count
  now="$(date +%s)"
  cutoff="$(( now - window_secs ))"

  printf '%s\n' "$now" >> "$THRASH_FILE"

  # Keep only timestamps within the window.
  kept="$(awk -v c="$cutoff" '$1 >= c' "$THRASH_FILE")"
  printf '%s\n' "$kept" > "$THRASH_FILE"

  count="$(grep -c . "$THRASH_FILE" 2>/dev/null || printf '0')"
  if [[ "$count" -gt "$max" ]]; then
    log "circuit breaker tripped: ${count} handoff generations within ${window_secs}s (max ${max})"
    return "$EXIT_THRASH"
  fi
  return 0
}

# ── Generation recording ─────────────────────────────────────────────────────
# Bump the monotonic per-slug generation counter via continuation.sh. The
# continuation helper owns gen-NNN.md / `latest`; here we only need the count to
# feed the thrash detector and the log, so we read its next-num view. If the
# helper is unavailable (custom layouts), fall back to an internal counter.
GEN_COUNT=0
record_generation() {
  GEN_COUNT="$(( GEN_COUNT + 1 ))"
  if [[ -x "$CONTINUATION_SH" || -f "$CONTINUATION_SH" ]]; then
    local latest
    latest="$(bash "$CONTINUATION_SH" latest-num --slug "$SLUG" 2>/dev/null || printf '')"
    if [[ -n "$latest" ]]; then
      log "recorded handoff — continuation latest=gen-${latest} (loop count ${GEN_COUNT})"
      return 0
    fi
  fi
  log "recorded handoff — loop count ${GEN_COUNT}"
}

# ── Main loop ────────────────────────────────────────────────────────────────
main() {
  parse_args "$@"

  command -v jq >/dev/null 2>&1 || die "jq is required but not found on PATH"

  local forge_dir cfg claude_bin
  forge_dir="$(resolve_forge_dir)"
  cfg="$forge_dir/resilience.config"
  claude_bin="${FORGE_CLAUDE_BIN:-claude}"
  command -v "$claude_bin" >/dev/null 2>&1 || die "claude binary not found: $claude_bin"

  # Resolve the session slug — explicit --slug wins, else derive from cwd via the
  # continuation helper so the loop and the helper agree on the slug.
  if [[ -z "$SLUG" ]]; then
    if [[ -f "$CONTINUATION_SH" ]]; then
      SLUG="$(bash "$CONTINUATION_SH" slug 2>/dev/null || printf '')"
    fi
    [[ -n "$SLUG" ]] || SLUG="session"
  fi

  # Circuit-breaker tunables — config first, built-in defaults otherwise.
  local thrash_max thrash_window throttle
  thrash_max="$(config_get FORGE_THRASH_MAX_GENERATIONS "$cfg")"
  thrash_window="$(config_get FORGE_THRASH_WINDOW_SECONDS "$cfg")"
  throttle="$(config_get FORGE_THROTTLE_SECONDS "$cfg")"
  [[ "$thrash_max" =~ ^[0-9]+$ ]] || thrash_max="$DEFAULT_THRASH_MAX_GENERATIONS"
  [[ "$thrash_window" =~ ^[0-9]+$ ]] || thrash_window="$DEFAULT_THRASH_WINDOW_SECONDS"
  [[ "$throttle" =~ ^[0-9]+$ ]] || throttle=0

  local max_generations="${FORGE_MAX_GENERATIONS:-0}"
  [[ "$max_generations" =~ ^[0-9]+$ ]] || max_generations=0

  thrash_init "$forge_dir" "$SLUG"

  log "starting — role=${ROLE} slug=${SLUG} claude=${claude_bin}"

  while true; do
    local json_output exit_code result usage

    # Fresh context window every call: plain `claude -p --output-format json`.
    # The SessionStart hook (slice 4c) injects the continuation `latest` for us.
    #
    # FORGE_LOOP_MANAGED=1 is the explicit "this is a loop-managed generation"
    # marker. The P2 hooks key off it: SessionStart stamps the genbaseline only
    # when it is set, the Stop hook enforces the handoff only when it is set.
    # Interactive `claude` sessions a developer opens by hand never carry it, so
    # they are never stamped and never blocked — see design doc §4.C / issue #181.
    json_output="$(FORGE_LOOP_MANAGED=1 "$claude_bin" -p --output-format json 2>/dev/null)"
    exit_code=$?

    # ── Crash path ───────────────────────────────────────────────────────────
    # Any non-zero `claude` exit is a crash (OOM, panic, signal, internal error).
    # PROPAGATE it to launchd — do not mask, do not respin. This is the boundary
    # between the two supervision layers.
    if [[ "$exit_code" -ne 0 ]]; then
      log "claude exited non-zero (${exit_code}) — propagating to launchd, not respinning"
      exit "$exit_code"
    fi

    # ── Exit 0 — inspect the JSON to tell handoff from completion ─────────────
    result="$(jq -r '.result // ""' <<<"$json_output" 2>/dev/null)"
    if [[ -z "$result" && -z "$json_output" ]]; then
      log "claude exited 0 but produced no parseable output — treating as a fault"
      exit "$EXIT_NO_SENTINEL"
    fi
    usage="$(jq -c '.usage // {}' <<<"$json_output" 2>/dev/null)"

    # Work-complete sentinel → nothing left to do. Break, exit 0.
    if [[ "$result" == *"$SENTINEL_COMPLETE"* ]]; then
      log "FORGE_COMPLETE — work done, loop exiting 0"
      exit "$EXIT_COMPLETE"
    fi

    # Clean-handoff sentinel → session wrote a continuation generation.
    if [[ "$result" == *"$SENTINEL_CONTINUE"* ]]; then
      record_generation

      # Thrash circuit breaker — too many handoffs too fast → trip and exit.
      thrash_check "$thrash_max" "$thrash_window"
      local thrash_rc=$?
      if [[ "$thrash_rc" -ne 0 ]]; then
        exit "$thrash_rc"
      fi

      # Budget gate — parse .usage, compare to role thresholds, set or clear the
      # next generation's "hand off promptly" signal. A hard-line crossing stops
      # the loop; a config/parse failure is a fault.
      budget_gate "$usage" "$forge_dir" "$SLUG" "$cfg"
      local gate_rc=$?
      if [[ "$gate_rc" -eq "$EXIT_BUDGET_HARD" ]]; then
        exit "$EXIT_BUDGET_HARD"
      elif [[ "$gate_rc" -ne 0 ]]; then
        exit "$gate_rc"
      fi

      # Test/CI safety net — never spin past an explicit generation cap.
      if [[ "$max_generations" -gt 0 && "$GEN_COUNT" -ge "$max_generations" ]]; then
        log "reached FORGE_MAX_GENERATIONS=${max_generations} — stopping (test/CI safety net)"
        exit "$EXIT_COMPLETE"
      fi

      # Loop-level throttle — pairs with launchd's process-crash throttle.
      if [[ "$throttle" -gt 0 ]]; then
        sleep "$throttle"
      fi

      continue  # relaunch fresh — SessionStart re-injects the continuation
    fi

    # ── Exit 0 but no recognised sentinel — a fault, not a handoff ────────────
    # The session ran out of turns / ended without emitting either sentinel.
    # Do not spin — exit non-zero so the fault surfaces.
    log "claude exited 0 with no FORGE_CONTINUE/FORGE_COMPLETE sentinel — treating as a fault"
    exit "$EXIT_NO_SENTINEL"
  done
}

main "$@"
