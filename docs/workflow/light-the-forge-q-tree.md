# Light the Forge — Question Tree

This is a one-screen map of every Block and branch in the `/light-the-forge` (LTF) Q&A.
LTF's `SKILL.md` is the canonical source for *content* (exact wording, recommendations,
file-writing behavior); this doc exists so you can see the *shape* of the conversation —
which blocks branch, which blocks skip, and where the sibling `/examine` skill is invoked
— without scrolling through the full skill prose. Update this file whenever the LTF Q&A
gains, loses, or rewires a block.

```mermaid
flowchart TD
    Start([User runs ./light-the-forge.sh]) --> B0

    B0{"Block 0<br/>Starting point?"}
    B0 -->|Fresh project<br/>asks Block 0b next| B0b
    B0 -->|Existing codebase| SubExisting
    B0 -->|Starter template| SubStarter

    subgraph SubExisting["Subflow: Existing codebase"]
        direction TB
        EX1[Ask: path or git URL] --> EX2{URL or path?}
        EX2 -->|git URL| EX3[Clone into cwd<br/>Forge files win on conflict]
        EX2 -->|local path| EX4[Lay Forge files on top<br/>of existing dir]
        EX3 --> EXamine[/Invoke /examine/]
        EX4 --> EXamine
    end

    subgraph SubStarter["Subflow: Starter template"]
        direction TB
        ST1[Ask: what do you want to build?] --> ST2[Suggest 2-3 real starter repos]
        ST2 --> ST3{User picks}
        ST3 -->|Template URL| ST4[Clone into cwd]
        ST3 -->|Show more| ST2
        ST3 -->|Paste own URL| ST4
        ST4 --> STamine[/Invoke /examine/]
    end

    SubExisting --> B0c
    SubStarter --> B0c

    B0b{"Block 0b<br/>Research or Build?<br/>(Fresh-project path only)"}
    B0b -->|Research first| B0c
    B0b -->|Build now| B0c

    B0c{"Block 0c<br/>Dev mode?<br/>(fast / balanced / tdd)"}
    B0c --> B1

    B1["Block 1 — Identity<br/>project name, one-liner"]
    B1 --> B2

    B2["Block 2 — Visual review<br/>Playwright / iOS Sim / Other / None"]
    B2 --> B3

    B3["Block 3 — First phase<br/>first sub-phase title"]
    B3 --> B4Decide{Skip Block 4?}

    B4Decide -->|"Yes — came via<br/>Existing / Starter<br/>(examine filled it)"| B5
    B4Decide -->|"Yes — Block 0b said<br/>Research first"| B5
    B4Decide -->|No — Fresh + Build now| B4

    B4["Block 4 — Tech stack<br/>preset, framework, check command"]
    B4 --> B5

    B5["Block 5 — Domain language<br/>key terms (optional, skippable)"]
    B5 --> B6

    B6{"Block 6 — GitHub<br/>new public / new private /<br/>link existing / skip"}
    B6 --> Work[Doing the work:<br/>fill CLAUDE.md / MISSION-CONTROL.md / CONTEXT.md,<br/>git init, create/link remote, push,<br/>workflow-setup.sh, delete light-the-forge.sh]
    Work --> Done([Final handoff:<br/>recommend /ponder next])

    classDef examine fill:#fef3c7,stroke:#b45309,color:#78350f
    class EXamine,STamine examine
```

## Block legend

- **Block 0 — Starting point.** Fresh project, existing codebase, or starter template. Reshapes the rest of the Q&A.
- **Block 0b — Research vs. Build intent.** Asked *only* on the Fresh-project path. Research-first skips Block 4 entirely.
- **Block 0c — Developer mode.** Asked on every path (Fresh / Existing / Starter). Sets `**Dev mode:** fast|balanced|tdd` in `CLAUDE.md`. Downstream skills (`/temper`, `/ponder`, `/inscribe`) branch on this line.
- **Block 1 — Identity.** Project name and one-line description.
- **Block 2 — Visual review.** Which tool temper uses for UI screenshots (Playwright, iOS Sim MCP, Other, None).
- **Block 3 — First phase.** The `0a` sub-phase title that lands in `MISSION-CONTROL.md`.
- **Block 4 — Tech stack.** Stack preset, framework, check command. Skipped when `/examine` already ran (Existing / Starter paths) or when the user chose Research-first in 0b.
- **Block 5 — Domain language.** Optional key terms that seed `CONTEXT.md`. Skippable.
- **Block 6 — GitHub.** Repo creation choice (new public / new private / link existing / skip).

The two yellow `/examine` nodes mark where the sibling skill is invoked — it auto-fills
Block 4 from files on disk, which is why the Existing-codebase and Starter-template paths
can skip the manual stack Q&A.

## Maintenance

Any future change to the `/light-the-forge` Q&A — adding a block, removing one, rewiring
a branch, changing where `/examine` is invoked, or changing which blocks are skipped on
which path — **must update this diagram in the same PR**. Treat the SKILL.md and this
file as a pair: if the prose drifts from the graph, the graph is wrong.
