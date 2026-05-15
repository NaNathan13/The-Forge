# PRD — Crash-Layer Correctness + Measurement

> Sub-phase **3d** (Phase **P3 — Improvements**) · Status: 📝 prd-ready · Filed 2026-05-15
>
> **Why this size?** 3d closes two correctness gaps in the P1.1b crash layer (PID-file kill target, persistent crash-respin breaker) and converts temper's context checkpoint from eyeball to statusline-read — three file-disjoint logic slices that ship the audit's Theme-7+8 picks (recs #22, #23, #25, #31) under one PRD.
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 7 (selected: #22, #23) + Theme 8 (#25) + #31.

## Scope

3d closes real correctness gaps in the P1.1b resilience substrate (`launchd`
keep-alive + `relaunch-loop.sh` + `liveness-watchdog.sh`) and converts one
context-discipline checkpoint from self-assessment to a computed-number read.

1. **Watchdog's kill target made exact (#22).** The relaunch loop records its
   `claude` child PID to a slug-namespaced file; the watchdog prefers that over
   the existing `pgrep -f 'claude' | head -n 1` heuristic. Removes the "kill
   the wrong `claude`" failure mode on multi-project hosts.

2. **Crash-path circuit breaker (#23).** The existing breaker counts clean
   handoffs only — a session that crashes on startup respawns forever every
   ~30s with no alert. 3d adds a *persistent* crash-respin counter (must cross
   loop-process restarts because each crash respawn is the event being
   counted), plus a stay-down sentinel file that halts `launchd` respawn when
   tripped.

3. **Statusline-tied context checkpoint (#25 + #31).** Temper's context
   checkpoint moves from "eyeball your context %" to "read the `ctx N%` figure
   from `.claude/statusline/budget-mirror.sh`." Combined with #31, a one-line
   **near-done override** on the warn threshold — a 95%-complete slice
   finishes rather than hands off mid-flight. Hard stop stays absolute.

All three are file-disjoint at the boundaries — slices 1 and 2 both edit
`scripts/relaunch-loop.sh` but in different functions, so forge sequences them
per ADR-0003.

## Recs landing here

| Rec | What | Audit facet | 3d shape |
|---|---|---|---|
| #22 | Watchdog's kill target made exact — relaunch loop records its `claude` child PID to a file; watchdog prefers that over `pgrep -f 'claude' \| head -n 1`. Removes "kill the wrong claude" on multi-project hosts | `crash-resilience.md` | Slice 1 |
| #23 | Crash-path circuit breaker — count crash respins, not just clean handoffs; trip on `N` crashes within window and stop-and-alert | `crash-resilience.md` | Slice 2 |
| #25 | Statusline-tied context checkpoint — change skill files from "check current context usage" (eyeball) to "read the figure from the statusline" | `context-discipline.md` | Slice 3 |
| #31 | "Near-done override" for the *warn* threshold — if the current slice is within one concrete action of done, finishing it beats handing off mid-slice. One sentence in `temper/SKILL.md`; hard stop stays absolute | `context-discipline.md` | Slice 3 (folded in) |

## Slice plan

Three slices, all `slice:logic`. PRD-recommended dispatch order: **#22 →
#23 → temper edit**. Slices 1 and 2 both edit `scripts/relaunch-loop.sh`
(different functions, but same file) — forge sequences them serially per
ADR-0003. Slice 3 is fully independent and can ship anytime.

### Slice 1 — PID-file kill target (rec #22)

**Files touched:**
- `scripts/relaunch-loop.sh`
- `scripts/liveness-watchdog.sh`

**Change shape:**

**A. relaunch-loop.sh — write the PID.**

The loop currently invokes `claude` synchronously and captures stdout:

```bash
json_output="$(FORGE_LOOP_MANAGED=1 "$claude_bin" -p --output-format json 2>/dev/null)"
exit_code=$?
```

Refactor to background-with-wait so we can capture `$!`:

```bash
tmp_out="$(mktemp -t forge-claude-out.XXXXXX)" || die "could not create temp file"
FORGE_LOOP_MANAGED=1 "$claude_bin" -p --output-format json \
    >"$tmp_out" 2>/dev/null &
claude_pid=$!
printf '%s\n' "$claude_pid" > "$PID_FILE"
wait "$claude_pid"
exit_code=$?
json_output="$(cat "$tmp_out")"
rm -f "$tmp_out"
```

`PID_FILE` is `$forge_dir/continuation/$SLUG/claude.pid` — slug-namespaced
to match `.forge/heartbeat/<slug>` shape; safe on multi-project hosts. Resolve
the path once at startup (after `thrash_init`), clear any stale file, and
ensure the directory exists.

**B. liveness-watchdog.sh — read the PID.**

Augment `find_claude_pid` so the PID-file path takes precedence over `pgrep`:

```bash
find_claude_pid() {
  local project_dir="$1"
  local pid_file="$forge_dir/continuation/$slug/claude.pid"
  local candidate=""
  if [[ -f "$pid_file" ]]; then
    candidate="$(cat "$pid_file" 2>/dev/null)"
    if [[ "$candidate" =~ ^[0-9]+$ ]] && kill -0 "$candidate" 2>/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  # Fallback: existing heuristic — preserves current behavior during partial upgrades.
  pgrep -f 'claude' 2>/dev/null | head -n 1
}
```

`$forge_dir` and `$slug` are already in scope (main resolves them before
`find_claude_pid` is called).

**Acceptance criteria:**

- [ ] `scripts/relaunch-loop.sh` writes its `claude` child PID to
      `$forge_dir/continuation/$SLUG/claude.pid` before `wait`-ing on it.
- [ ] `scripts/relaunch-loop.sh` clears any stale PID file at loop start.
- [ ] `scripts/liveness-watchdog.sh::find_claude_pid` reads the PID file first
      and validates with `kill -0` before using it.
- [ ] Watchdog falls back to the existing `pgrep -f 'claude' | head -n 1`
      heuristic when the PID file is absent, unreadable, malformed, or names
      a dead process.
- [ ] Crash + handoff + completion paths in the relaunch loop all continue
      to behave correctly (no regression in exit-code handling, sentinel
      detection, or JSON parsing now that stdout comes from a temp file).
- [ ] `bash -n` passes on both scripts.
- [ ] No other files modified.

### Slice 2 — Crash-respin circuit breaker (rec #23)

**Files touched:**
- `scripts/relaunch-loop.sh`
- `.forge/resilience.config`
- `docs/workflow/p2-resilience-operations.md` (operator recovery section)

**Change shape:**

**A. resilience.config — new tunables.**

Add (next to the existing `FORGE_THRASH_*` block):

```bash
# ── Crash-respin circuit breaker (sub-phase 3d) ──────────────────────────────
# Distinct from the handoff thrash breaker above — that one counts clean
# FORGE_CONTINUE handoffs within a single loop process; this one counts
# CRASH respawns across loop processes (each crash exits the loop; launchd
# respawns it; the counter must persist to see the cycle). Trips when more
# than FORGE_CRASH_MAX_RESPINS crashes happen within FORGE_CRASH_WINDOW_SECONDS.
# Defaults intentionally match the handoff-thrash values.
FORGE_CRASH_MAX_RESPINS=5
FORGE_CRASH_WINDOW_SECONDS=300
```

**B. relaunch-loop.sh — persistent counter + stay-down sentinel.**

Add three pieces of state and three new functions:

```bash
DEFAULT_CRASH_MAX_RESPINS=5
DEFAULT_CRASH_WINDOW_SECONDS=300

CRASH_FILE=""
CRASH_SENTINEL=""

crash_init() {
  local forge_dir="$1" slug="$2"
  local dir="$forge_dir/continuation/$slug"
  mkdir -p "$dir" 2>/dev/null || true
  CRASH_FILE="$dir/.crash-window"
  CRASH_SENTINEL="$dir/.crash-breaker-tripped"
  # NOTE: do NOT truncate CRASH_FILE — it must persist across loop processes.
  [[ -f "$CRASH_FILE" ]] || : > "$CRASH_FILE"
}

# Append a crash timestamp, prune to window, return EXIT_THRASH if tripped.
crash_check() {
  local max="$1" window_secs="$2" exit_code="$3"
  local now cutoff kept count
  now="$(date +%s)"
  cutoff="$(( now - window_secs ))"
  printf '%s\t%s\n' "$now" "$exit_code" >> "$CRASH_FILE"
  kept="$(awk -v c="$cutoff" '$1 >= c' "$CRASH_FILE")"
  printf '%s\n' "$kept" > "$CRASH_FILE"
  count="$(grep -c . "$CRASH_FILE" 2>/dev/null || printf '0')"
  if [[ "$count" -gt "$max" ]]; then
    write_crash_sentinel "$max" "$window_secs" "$count" "$exit_code"
    log "crash breaker tripped: ${count} crashes within ${window_secs}s (max ${max})"
    log "  → wrote $CRASH_SENTINEL; next launchd respawn will stay down"
    return "$EXIT_THRASH"
  fi
  return 0
}

write_crash_sentinel() {
  local max="$1" window_secs="$2" count="$3" last_exit="$4"
  {
    printf 'crash-breaker tripped at %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'window: %s crashes within %ss (max %s)\n' "$count" "$window_secs" "$max"
    printf 'most recent exit code: %s\n' "$last_exit"
    printf '\nrecent crash timestamps + exit codes:\n'
    tail -n 20 "$CRASH_FILE"
    printf '\nRecovery: investigate the crashes (logs at .forge/launchd-loop.err.log)\n'
    printf 'then `rm %s` to clear the breaker.\n' "$CRASH_SENTINEL"
  } > "$CRASH_SENTINEL"
}
```

**Startup gate** (immediately after `crash_init`, before `thrash_init`):

```bash
if [[ -f "$CRASH_SENTINEL" ]]; then
  log "crash breaker tripped — staying down (rm $CRASH_SENTINEL to recover)"
  cat "$CRASH_SENTINEL" >&2
  exit 0   # SuccessfulExit=false in the plist → launchd does NOT respawn
fi
```

**Crash-branch hook** (inside the existing `if [[ "$exit_code" -ne 0 ]]; then`
block, **before** the existing `exit "$exit_code"` propagation):

```bash
if [[ "$exit_code" -ne 0 ]]; then
  crash_check "$crash_max" "$crash_window" "$exit_code" || true
  log "claude exited non-zero (${exit_code}) — propagating to launchd, not respinning"
  exit "$exit_code"
fi
```

The `|| true` is intentional — even if `crash_check` returns the trip code, we
still want the loop to propagate the original crash exit so `launchd` sees the
real failure. The sentinel halts the *next* respawn (and the loop's own
startup gate enforces it).

**C. p2-resilience-operations.md — operator recovery section.**

Add a parallel "Recovering from a tripped crash breaker" subsection to whatever
already exists for the handoff thrash breaker. Steps:

1. Confirm the agent stopped respawning:
   `launchctl print gui/$UID/com.forge.<slug> | grep state`
2. Read the sentinel file:
   `cat ~/Library/LaunchAgents/../.../continuation/<slug>/.crash-breaker-tripped`
   (or wherever your `.forge/` lives — exact path is in the loop's stderr log).
3. Investigate the crashes — `.forge/launchd-loop.err.log` is the after-the-fact
   record.
4. Once you've addressed the root cause:
   `rm <path-to>/.crash-breaker-tripped`
5. Optionally kickstart the agent immediately rather than waiting for the next
   reboot:
   `launchctl kickstart -k gui/$UID/com.forge.<slug>`

**Acceptance criteria:**

- [ ] `.forge/resilience.config` carries new `FORGE_CRASH_MAX_RESPINS` and
      `FORGE_CRASH_WINDOW_SECONDS` keys, with documented defaults (5 / 300).
- [ ] `scripts/relaunch-loop.sh` reads both keys via `config_get` with the
      same fallback shape as the existing `FORGE_THRASH_*` reads.
- [ ] Crash-respin counter persists at
      `$forge_dir/continuation/$slug/.crash-window` — survives loop-process
      restarts (this is the load-bearing invariant; the existing
      `.thrash-window` truncates on every loop start; this one must not).
- [ ] On trip, a stay-down sentinel is written at
      `$forge_dir/continuation/$slug/.crash-breaker-tripped` with a
      human-readable alert (trip timestamp, window stats, recovery
      instructions).
- [ ] Loop startup gate checks for the sentinel BEFORE `thrash_init` and
      `exit 0`s (so `KeepAlive.SuccessfulExit=false` halts launchd respawn).
- [ ] Operator recovery steps documented in
      `docs/workflow/p2-resilience-operations.md` — parallel to the existing
      handoff-thrash breaker recovery shape.
- [ ] `bash -n` passes on `scripts/relaunch-loop.sh`.
- [ ] Existing handoff-thrash breaker behavior (`thrash_check` /
      `FORGE_THRASH_*`) is unchanged — slice 2 adds a new path, does not
      modify the existing one.
- [ ] The launchd plist (`templates/launchd/com.forge.project.plist`) is
      **NOT** modified — `KeepAlive.SuccessfulExit=false` already does the
      right thing.

### Slice 3 — Temper context-discipline rewrite (recs #25 + #31)

**Files touched:**
- `.claude/skills/temper/SKILL.md`

**Change shape:**

Replace bullets 1 and 2 of §"Context discipline" → "A. Context-window
(per-session token budget)" (currently lines 194–195) with the four-line block
below. Keep bullets 3-5 (Don't load heavy docs / Use knowledge library / CI
failure fix sessions) verbatim.

**Replacement text (paste verbatim):**

```markdown
- **Read your context usage from the statusline** — the `ctx N%` figure rendered by `.claude/statusline/budget-mirror.sh`. Do not estimate; the statusline is the source of truth.
- **At warn (`ctx N% ^`, default 40%) — finish the current phase** (build/verify/PR), then hand off. **Near-done override:** if the slice is within one concrete action of done, finish it — a 95%-complete slice that hands off mid-flight is worse than a slightly-over-warn slice that ships.
- **At hard (`ctx N% !`, default 50%) — hard stop, no exceptions.** Write a continuation file and emit `TEMPER:RESULT` with `"status":"continue"` immediately. The override does NOT apply here.
```

The statusline already consumes `.context_window.used_percentage` (verified in
`budget-mirror.sh`) and renders `ctx N% ^` at warn / `ctx N% !` at hard — no
statusline-side change needed.

**Why temper-only:** the audit names temper explicitly. `forge/SKILL.md` is
**not** touched — orchestrator is structurally exit-triggered ("one temper per
generation"), does not self-estimate context %, and has no "near-done" target
to override (temper-completion *is* the end of a forge generation). Forge's
existing context-discipline text (lines 273–281 + 338–359) already says this.

**Acceptance criteria:**

- [ ] `.claude/skills/temper/SKILL.md` §A bullets 1+2 replaced with the
      three-bullet block above (statusline-read, warn + near-done override,
      hard stop absolute).
- [ ] Bullets 3-5 of §A (heavy-docs guard, knowledge library, CI failure fix
      sessions) preserved verbatim.
- [ ] §B (session rate-limit) and the rest of the file unchanged.
- [ ] `forge/SKILL.md` not modified (verified by `git diff --stat` on the
      PR — only `temper/SKILL.md` changes).
- [ ] No other files modified.

## Cross-slice contract

| Slice | Files | Other slices touch this file? |
|---|---|---|
| 1 | `scripts/relaunch-loop.sh`, `scripts/liveness-watchdog.sh` | Slice 2 also edits `relaunch-loop.sh` |
| 2 | `scripts/relaunch-loop.sh`, `.forge/resilience.config`, `docs/workflow/p2-resilience-operations.md` | Slice 1 also edits `relaunch-loop.sh` |
| 3 | `.claude/skills/temper/SKILL.md` | none |

**Overlap on `relaunch-loop.sh`:** slice 1 edits the while-loop body (claude
invocation block) + adds PID-file init at startup. Slice 2 adds a *separate*
startup gate (crash sentinel check, before `thrash_init`) and a crash-branch
hook (inside the existing `if [[ "$exit_code" -ne 0 ]]; then` block, before
`exit "$exit_code"`). These are textually disjoint regions of the same file —
auto-merge usually handles it, but to be safe, forge dispatches them serially
per ADR-0003: **#22 first, then #23, then the temper edit**.

No MC `## ADRs` append-conflict pattern (3d adds no ADRs — both crash-layer
slices are implementation refinements of decisions already recorded in
sub-phase 1b's design).

## Explicit non-goals (carried from stub PRD, restated)

Recorded so future re-readers don't re-litigate:

- **#21 (`systemd` sibling for the watchdog)** — cut per grill lock #4.
  Already documented at `docs/workflow/p2-resilience-operations.md`
  §macOS-only caveat (lines 323–341). No additional doc slice in 3d.
- **#24 (instrument serial-dispatch cost)** — cut per grill lock #4. No
  concurrency-cap question on the table.
- **`forge/SKILL.md` edits** — out of scope for 3d. Statusline-read doesn't
  apply (forge does not self-estimate context %); near-done override has no
  structural target (orchestrator's exit trigger is temper-completion).
- **Retroactively making the handoff-thrash breaker (`FORGE_THRASH_*`) also
  stay-down** — out of scope. The audit named the crash path specifically;
  the handoff breaker's existing in-process behavior is consistent with the
  pattern described in the design doc, and any change there is a separate
  design call.
- **Statusline JSON contract change** — out of scope. The field consumed
  (`.context_window.used_percentage`) is already verified against the shipped
  `budget-mirror.sh`; no script-side change is needed for slice 3.

## Acceptance — sub-phase done when

- All three slice issues are closed via merged PRs.
- `scripts/relaunch-loop.sh` writes its `claude` child PID to
  `$forge_dir/continuation/<slug>/claude.pid`.
- `scripts/liveness-watchdog.sh` prefers the PID file over the `pgrep`
  heuristic, with `kill -0` validation and the heuristic as fallback.
- `.forge/resilience.config` carries `FORGE_CRASH_MAX_RESPINS` and
  `FORGE_CRASH_WINDOW_SECONDS` keys.
- `scripts/relaunch-loop.sh` carries a persistent crash-respin counter and a
  stay-down sentinel that halts launchd respawn when tripped.
- `docs/workflow/p2-resilience-operations.md` carries an operator-recovery
  subsection for the crash breaker.
- `.claude/skills/temper/SKILL.md` §A reads context % from the statusline,
  with the near-done override on warn and hard-stop absolute.
- `docs/audit/AUDIT-SUMMARY.md` §B annotates recs #22, #23, #25, #31 as
  shipped in 3d (the umbrella PRD's phase-close bookkeeping).
- `MISSION-CONTROL.md`'s 3d row flips to ✅ shipped via `/seal`.

## Inputs

- `scripts/relaunch-loop.sh` — current synchronous claude invocation (the
  refactor target) and the existing `EXIT_THRASH` / `thrash_check` shape (the
  pattern the crash breaker mirrors).
- `scripts/liveness-watchdog.sh::find_claude_pid` — current `pgrep` heuristic
  the PID-file read augments.
- `.forge/resilience.config` — existing `FORGE_THRASH_*` block (defines the
  shape and naming convention the new `FORGE_CRASH_*` keys mirror).
- `.claude/statusline/budget-mirror.sh` — the statusline rendering script;
  confirms the JSON field name (`.context_window.used_percentage`) and the
  glyph contract (`^` at warn, `!` at hard).
- `.claude/skills/temper/SKILL.md` §Context discipline (current lines
  186–198) — the prose region slice 3 rewrites.
- `templates/launchd/com.forge.project.plist` — `KeepAlive.SuccessfulExit=false`
  setting that makes the stay-down sentinel mechanism work without a plist
  change.
- `docs/workflow/p2-resilience-operations.md` — operator guide where slice 2's
  recovery subsection lands.
- `docs/audit/AUDIT-SUMMARY.md` §B — the four audit recs landing here (#22,
  #23, #25, #31).
- `docs/design/improvements-overview.md` — umbrella PRD; 3d sequencing
  rationale (closes the P3 crash-correctness gap before the live-grill +
  MC-deepening sub-phases 3e / 3f).
