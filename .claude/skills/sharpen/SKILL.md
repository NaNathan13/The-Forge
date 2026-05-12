---
name: sharpen
description: Turns a rough task idea into a precise, structured prompt for another skill or agent. Use when the user wants help writing a prompt, says "sharpen", or needs to formulate the next step in the pipeline.
---

# Sharpen — hone a rough idea into a precise prompt

Takes a fuzzy "I want to do X" and produces a prompt ready to paste into the next skill invocation or agent dispatch.

## Invocation

```
/sharpen                    # "what are you trying to do?"
/sharpen <rough idea>       # start from the idea
/sharpen for <skill-name>   # target a specific skill
```

## Workflow

### 1. Understand the target

Determine what the prompt is for:
- A pipeline skill (`/ponder`, `/temper`, `/forge`, `/diagnose`, etc.)
- A subagent dispatch (research, exploration, audit)
- A standalone task (one-shot ask)

If unclear, ask once. Read the target skill's SKILL.md to understand what inputs it expects.

### 2. Extract the raw intent

From the user's rough idea, identify:
- **What** they want done (the task)
- **Why** it matters right now (the motivation — read MISSION-CONTROL.md for context)
- **What "done" looks like** (success criteria)

If any of these are missing, ask — one question at a time, with a recommended answer.

### 3. Fill the structure

Build the prompt using these fields. Not every field applies to every prompt — omit what's empty.

| Field | Purpose | Example |
| --- | --- | --- |
| **Context** | Point to files, prior decisions, current state | "Sub-phase 7 just shipped. All screens built but never audited end-to-end." |
| **Task** | Single imperative directive | "Walk every screen in the running app and capture screenshots." |
| **Scope** | What's in, what's explicitly out | "All 11 user journey steps. Not: code changes or fixes." |
| **Constraints** | Rules, conventions, things to avoid | "Both light and dark mode. Use the project's screenshot conventions." |
| **Verification** | How to know it worked | "Every view has a screenshot pair (light + dark) saved to `screenshots/`." |
| **Output** | What artifact to produce | "Filed GitHub issues for every finding." |

### 4. Shape to target

Adapt the prompt to its destination:
- **Pipeline skills** (`/ponder`, `/temper`): Keep it to 1-3 sentences. The skill has its own structure — the prompt just seeds direction. Include the sub-phase ID.
- **Subagents**: Be explicit — they have no conversation context. Include file paths, success criteria, and what NOT to do.
- **Standalone tasks**: Balance between over-specifying (brittle) and under-specifying (drift).

### 5. Present and refine

Show the drafted prompt in a fenced code block. Ask:

> **Ready to run, or want to adjust?**

Use AskUserQuestion with options: "Run it" / "Adjust" / "Start over".

On "Run it": if the target is a skill, invoke it directly with the prompt. If it's an agent dispatch or standalone, hand the prompt to the user.

## Anti-patterns

- **Don't over-engineer simple prompts.** If the user just needs "/ponder 8a — expanded feature set", that might already be sharp enough. Say so.
- **Don't add fields that are empty.** A 2-field prompt that's precise beats a 6-field prompt padded with filler.
- **Don't second-guess the user's chosen skill.** Sharpen writes the prompt, not the workflow. If they say "for /ponder", write a ponder prompt.
- **Don't execute the task.** Sharpen produces the prompt. The user (or the next skill) executes it.
