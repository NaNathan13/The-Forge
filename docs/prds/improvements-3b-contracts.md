# PRD — Documented Contracts + Bootstrap Stamp

> **Naming context (after sub-phase 4b, 2026-05-17):** in the body below, "/forge" refers to the orchestrator role now named `/forgemaster`, and "/temper" refers to the builder role now named `/forge`. See [ADR-0005](../adr/0005-pipeline-role-split.md) for the rename rationale.
>
> **Naming context amended (after sub-phase 4e, 2026-05-17):** `/forgemaster` (the post-4b orchestrator name) was further retired and split into `/forge-overseer` + `/temper-overseer` per [ADR-0007](../adr/0007-pipeline-orchestrator-structure.md) and [ADR-0008](../adr/0008-naming-discipline.md). The builder/review worker names (`/forge` / `/temper`) carry over unchanged.


> Sub-phase **3b** (Phase **P3 — Improvements**) · Status: 📝 prd-ready · Filed 2026-05-15
>
> **Why this size?** Four cheap doc-contract recs that share a single review surface — two ADRs, prose pointers, one bootstrap-script tweak, one PRD-template wiring. Bundled as a sub-phase so the ADR discipline + template change land as one coherent move rather than four drive-by PRs.
>
> Umbrella context: [`docs/design/improvements-overview.md`](../design/improvements-overview.md).
> Source recs: `docs/audit/AUDIT-SUMMARY.md` §B Theme 9 (selected) + #30.

## Scope

3b ships the cheap doc-contract recs the audit grouped under "make conventions
auditable contracts" — load-bearing rules that today live only as prose inside
skill files and would survive a careless edit better as a stated invariant —
plus a tiny addition to `light-the-forge.sh` (the install-manifest stamp) that
pays off the moment Discord / multi-project work begins. Prose-only changes to
skill files + ~10 lines added to one bootstrap script + two new ADRs + one
PRD-template wiring. Smallest sub-phase by line count.

## Reframe from the stub PRD

The stub PRD (filed 2026-05-15 at sub-phase-list time) proposed dropping
recs #27 and #28 as **prose paragraphs** in `docs/shared/pipeline.md` and
`.claude/skills/forge/SKILL.md`. The `/ponder` grill upgraded both to **ADRs**:

- They are foundational design decisions with rejected alternatives
  (in-memory hand-offs; multi-worker concurrency) and consequences
  (composability / crash-resilience; context-budget discipline). That is the
  exact shape `docs/adr/` is for — context / decision / alternatives /
  consequences — and the shape that prose paragraphs *don't* enforce.
- ADRs are append-only by convention; prose paragraphs drift silently.
- `docs/adr/` already exists with one entry (ADR-0001 autonomous-forge
  architecture). Adopting ADRs as the home for "load-bearing design decisions
  worth preserving" activates the directory as a real discipline rather than
  a one-entry curio, which is itself a 3b-style win.

Each ADR pairs with a one-line **pointer** in the prose location the audit
originally named (`docs/shared/pipeline.md`, `forge/SKILL.md`). The pointer
keeps the ADR discoverable at the point of edit — removing the pointer
breaks a doc link, which is more conspicuous than removing a paragraph.

## Recs landing here

| Rec | What | Audit facet | 3b shape |
|---|---|---|---|
| #27 | "No shared session memory between phases" stated as an auditable contract | `phased-pipeline.md` | ADR-0002 + 1-line pointer in `docs/shared/pipeline.md` |
| #28 | Concurrency cap (max-1 temper worker) documented as a *deliberate trade* with a revisit precondition | `subagent-orchestration.md` | ADR-0003 + 1-line pointer in `.claude/skills/forge/SKILL.md` |
| #30 | `light-the-forge.sh` writes a `.forge/install-manifest.json` stamp — Forge git SHA, ref, install date, list of skills copied. Precondition for any future `--update` / drift-check / Discord-plugin SHA query | `skills-as-prompts.md` | ~10-line addition to `light-the-forge.sh`; JSON file at `.forge/install-manifest.json`; brief mention in `.forge/README.md` |
| #32 | PRD template gains a one-line "Why this size?" — record *why* a piece of work was scoped sub-phase vs single-slice | `planning-discipline.md` | Ponder captures rationale at the size check; inscribe renders the line into the PRD frontmatter `>` block |

## Slice plan

Four slices, all `slice:logic`, no dependency edges, file-disjoint. Build
order is unconstrained; `/forge` can dispatch them in any order serially
(per the concurrency cap that slice 2 documents).

### Slice 1 — ADR-0002: Phase isolation (no shared session memory)

**Files touched:**
- `docs/adr/0002-phase-isolation.md` (NEW)
- `docs/shared/pipeline.md` (add a one-line pointer in the appropriate section,
  e.g. *"Phases communicate only via on-disk artifacts — see ADR-0002."*)
- `MISSION-CONTROL.md` (append an entry to the `## ADRs` section)

**ADR content (skeleton):**

- **Context.** The pipeline's four phases each run in their own Claude session;
  the *only* hand-off channel is on-disk artifacts (issues, PRDs, sentinels,
  continuation files, kanban state). This invariant is implied everywhere but
  stated nowhere — a future "optimization" that passes state in-memory between
  phases would silently break composability, crash-recovery, and the Tier-1
  Discord-channel pattern that ADR-0001 commits to.
- **Decision.** Phases MUST hand off only via on-disk artifacts. Session memory
  between phases is forbidden. The artifact must be the source of truth; if a
  later phase needs information, the earlier phase writes it down.
- **Rejected alternative.** In-memory hand-offs (e.g. a parent session passing
  context to a child). Rejected because it couples phases at the session layer,
  defeats crash-recovery, and contradicts the Tier-0 / Tier-1 / Tier-2 model.
- **Consequences.** Skills, scripts, and hooks must read state from disk, not
  ambient session context. The continuation-file pattern, the sentinel, and
  the kanban move are the *only* sanctioned hand-off channels.

**Acceptance criteria:**

- [ ] `docs/adr/0002-phase-isolation.md` exists with Status / Date / Phase /
      Context / Decision / Rejected alternative / Consequences / Related sections.
- [ ] `docs/shared/pipeline.md` has a one-line pointer to ADR-0002 in a sensible
      place (likely just after the "## The four phases" section or at the top
      of "## Invariants").
- [ ] `MISSION-CONTROL.md` `## ADRs` section lists the ADR with a one-line hook.
- [ ] No other files modified.

### Slice 2 — ADR-0003: Single-worker concurrency cap as deliberate trade

**Files touched:**
- `docs/adr/0003-concurrency-cap.md` (NEW)
- `.claude/skills/forge/SKILL.md` (add a one-line pointer near the existing
  "one temper per generation" prose, e.g. line 217: *"This cap is a deliberate
  trade — see ADR-0003 for the rationale and revisit precondition."*)
- `MISSION-CONTROL.md` (append an entry to the `## ADRs` section)

**ADR content (skeleton):**

- **Context.** Forge dispatches *exactly one* temper subagent per generation.
  The existing prose in `forge/SKILL.md` states this as a directive but doesn't
  record *why* — leaving a future maintainer to either re-derive the rationale
  or remove the cap under the assumption that it's incidental.
- **Decision.** Forge runs at most one temper subagent at a time, in serial.
- **Rationale.** Context-budget discipline. Each temper consumes ~50–80k tokens
  per slice (proven in 3a's tempers: 49k–85k range). The orchestrator's
  context window is finite (the project memory hard-locks the 40 % warn /
  50 % hard checkpoints against a 200k-token baseline), and parallel tempers
  would multiply orchestrator-side state inspection cost. Serial dispatch
  keeps orchestrator overhead bounded.
- **Rejected alternatives.** (a) Unbounded parallelism (clear context blowout).
  (b) Configurable N>1 with a per-slice dispatcher (defers the cost but doesn't
  remove it — same context blow-out at higher N). (c) Fan-out via Tier-0
  sudo orchestration (different architectural layer entirely — that's
  ADR-0001's deferred Tier-0 work, not a 3b decision).
- **Revisit precondition.** This cap should be revisited if and only if:
  (i) tempers are routinely under-using their context budget (≪ 50 %), AND
  (ii) the orchestrator gains a way to inspect multiple sentinels without
  blow-up (likely a Tier-0 supervisor reading from disk, not in-session).
  Until both hold, the cap stays.
- **Consequences.** Throughput is bounded by serial dispatch. This is an
  accepted cost of the architecture; it is not a bug to optimize around.

**Acceptance criteria:**

- [ ] `docs/adr/0003-concurrency-cap.md` exists with all sections.
- [ ] `.claude/skills/forge/SKILL.md` has a one-line pointer to ADR-0003 next
      to existing "one temper per generation" prose.
- [ ] `MISSION-CONTROL.md` `## ADRs` section lists the ADR.
- [ ] No other files modified.

### Slice 3 — Install-manifest stamp in `light-the-forge.sh`

**Files touched:**
- `light-the-forge.sh` (~10 lines added after the kit-file copy block,
  approximately line 153 — after the `green "  ✓ Kit files copied"` line)
- `.forge/README.md` (brief mention of `install-manifest.json` and its purpose)

**Manifest schema (JSON, minimal):**

```json
{
  "v": 1,
  "forge_sha": "<git rev-parse HEAD of the cloned source>",
  "forge_ref": "<branch or tag, e.g. main>",
  "installed_at": "<ISO 8601 UTC timestamp>",
  "skills": ["ponder", "forge", "temper", "seal", "inscribe", "triage", "diagnose", "..."]
}
```

**Implementation notes:**

- Write to `.forge/install-manifest.json`. Create `.forge/` if it doesn't
  already exist (it usually does after the resilience-config copy step).
- `forge_sha`: from `git -C "$SRC" rev-parse HEAD` against the temp clone (or
  `HEAD` of `$TARGET` for the already-cloned path — both routes are valid;
  the cloned-temp path is more common for curl-pipe bootstrap).
- `forge_ref`: best-effort `git -C "$SRC" rev-parse --abbrev-ref HEAD`, or the
  ref that was cloned. Fallback to `"unknown"` if not resolvable.
- `installed_at`: `date -u +%Y-%m-%dT%H:%M:%SZ`.
- `skills`: enumerate `$SRC/.claude/skills/*` directory names. Use `jq` (already
  a hard prereq, line 187) to assemble the JSON safely.
- Both bootstrap paths (curl-pipe and already-cloned) must write the manifest.
  Refresh on every run — this is install state, not user state.

**Why JSON and not bash-sourceable:** see `improvements-3b-contracts.md` PRD
above and the grill summary. Multiple consumers over the manifest's lifetime
(bash bootstrap, possible Node Discord plugin, future validators); JSON serves
all readers cleanly; `jq` already prereq; matches the sentinel JSON convention.

**Explicitly out of scope:** file-by-file `sha256` hashes; a
`test/validate-manifest.sh` validator; any `--update` / drift-detection flow.
Each is a future slice in a downstream sub-phase.

**Acceptance criteria:**

- [ ] `.forge/install-manifest.json` exists after `light-the-forge.sh` runs.
- [ ] Schema matches the spec above (all five fields present, `v: 1`).
- [ ] `jq . .forge/install-manifest.json` parses cleanly (no malformed JSON).
- [ ] `forge_sha` matches `git rev-parse HEAD` of the installed source.
- [ ] `skills` array contains every directory under `.claude/skills/`.
- [ ] `.forge/README.md` mentions the manifest and its purpose in one short paragraph.
- [ ] Both bootstrap paths (curl-pipe and already-cloned) write the manifest.

### Slice 4 — "Why this size?" PRD template wiring

**Files touched:**
- `.claude/skills/ponder/SKILL.md` (size check captures one-sentence rationale
  alongside the size decision; pass to inscribe)
- `.claude/skills/inscribe/SKILL.md` (render `**Why this size?**` line into PRD
  frontmatter `>` block during PRD scaffolding)

**Shape of the line:**

The line lives inside the existing top `>` block of every PRD, alongside the
sub-phase / status / filed-date frontmatter. Example (as rendered in 3b's own
PRD, this file's header):

```markdown
> Sub-phase **3b** (Phase **P3 — Improvements**) · Status: 📝 prd-ready · Filed 2026-05-15
>
> **Why this size?** Four cheap doc-contract recs that share a single review
> surface — two ADRs, prose pointers, one bootstrap-script tweak, one
> PRD-template wiring. Bundled as a sub-phase so the ADR discipline + template
> change land as one coherent move rather than four drive-by PRs.
```

**Implementation notes:**

- Ponder's mid-grill size check (`/ponder/SKILL.md` §"Mid-grill size check")
  currently captures just the binary `sub-phase | single-slice` decision.
  Augment it to also capture a one-sentence **rationale** (the *why* of the
  size call) and pass `size_reason` to inscribe alongside `size_decision` and
  `sub-phase-id` / `dev-mode`.
- Inscribe's PRD scaffolding (Path A1 for sub-phase; Path B0 for tdd-mode
  single-slice) renders the `**Why this size?** <rationale>` line into the
  frontmatter `>` block immediately below the status/date line, mechanically.
- For runs where size_reason is absent (e.g. inscribe invoked standalone
  without a fresh grill), inscribe asks once via AskUserQuestion at PRD-write
  time. No TODO placeholders.
- This slice does **not** retroactively backfill the line into existing PRDs.
  The rec is forward-looking — future PRDs gain the line; historical PRDs
  stay as-is for the record.

**Applies to:** every PRD that gets written.
- Sub-phase PRDs: always (both `balanced` and `tdd` modes write a PRD for
  sub-phase work).
- Single-slice PRDs: only in `tdd` mode (per existing carve-out — `fast` and
  `balanced` modes do not write a PRD for single-slice work).

**Acceptance criteria:**

- [ ] `.claude/skills/ponder/SKILL.md` size-check step captures size_reason
      alongside size_decision and documents the new return value.
- [ ] `.claude/skills/inscribe/SKILL.md` renders the `**Why this size?**` line
      mechanically when PRD is scaffolded, both in Path A1 and Path B0.
- [ ] Inscribe asks once if size_reason is missing (standalone invocation path).
- [ ] No PRD scaffolding outside the documented paths is affected.

## Chicken-and-egg note — 3b's own PRD

Slice 4 codifies the "Why this size?" rendering into ponder + inscribe, but
this very PRD must already have the line in its frontmatter so that
re-readers immediately see the new shape in practice (the audit-rec's whole
point is for future re-audits to *see* the reasoning).

Resolved by: this PRD (the one you are reading) has the `**Why this size?**`
line in its header, written manually by inscribe at PRD-write time using the
rationale captured during the grill. Slice 4 then makes that behavior
automatic for every subsequent PRD.

## Dependencies on 3a

None. 3a's `validate-skills.sh` does not read these invariants — they're prose
and ADRs, not schema. The install-manifest does not yet have a
`validate-manifest.sh` (deferred). 3b can build directly on top of 3a's
shipped state with no validator update required.

## Sequencing within 3b

Slices have no edges between them. `/forge --phase 3b` dispatches them in
queue order; serial dispatch (one temper at a time per ADR-0003) means
ordering is purely a queue-position decision and not a correctness concern.

The natural queue order is:

1. Slice 4 — "Why this size?" template wiring. Cheapest skill edit; ships the
   ponder + inscribe wiring that everything downstream benefits from.
2. Slice 1 — ADR-0002 phase isolation.
3. Slice 2 — ADR-0003 concurrency cap.
4. Slice 3 — Install-manifest stamp.

This is a recommendation, not a requirement; any order ships green.

## Acceptance — sub-phase done when

- All four slices have shipped to `main` with green CI.
- `docs/adr/0002-phase-isolation.md` and `docs/adr/0003-concurrency-cap.md`
  exist and are linked from `MISSION-CONTROL.md`'s `## ADRs` section.
- `.forge/install-manifest.json` is written by `light-the-forge.sh` on every
  bootstrap run.
- `.claude/skills/ponder/SKILL.md` and `.claude/skills/inscribe/SKILL.md`
  emit `**Why this size?**` into every new PRD's frontmatter.
- The 3b row in `MISSION-CONTROL.md`'s P3 Improvements table flips to
  ✅ shipped, with `<!-- mc:done=N,N,N,N -->` row marker and all four issue
  numbers.
- `docs/audit/AUDIT-SUMMARY.md` §B annotated to mark recs #27, #28, #30, #32
  shipped in 3b. (Per umbrella PRD's phase-level acceptance — this annotation
  happens once at end-of-phase, not per sub-phase, but flagging here for the
  end-of-P3 reconciler.)

## Out of scope (carried from stub + grill)

- `validate-manifest.sh` — deferred. The manifest schema is fixed by this
  sub-phase; mechanical validation can ship later if needed.
- File-by-file `sha256` hashes in the manifest — deferred. Belongs with the
  eventual `--update` / drift-check feature.
- Retroactive `**Why this size?**` backfill into historical PRDs — explicit
  no. The rec is forward-looking.
- VCS-agnostic generalization of `light-the-forge.sh` — out of phase per
  umbrella grill lock #2 (WHJ v2 territory).
