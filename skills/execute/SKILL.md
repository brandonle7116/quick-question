---
description: "Smart implementation — read a plan, execute step by step with auto-compilation, subagent dispatch for large tasks, and checkpoint-based resume."
---

Respond in the user's preferred language (detect from their recent messages, or fall back to the language setting in CLAUDE.md).

Read a plan, execute it fully. Execution is always automatic — never ask "proceed?" or "start?" during implementation. The user invoked execute; that IS the go-ahead.

Arguments: $ARGUMENTS
- A file path to a plan/design document
- `--no-worktree`: skip worktree guard
- `--auto`: after completion, auto-select and run the next workflow step instead of asking the user (includes push — user should be aware)
- No arguments: detect the plan source from conversation or `Docs/qq/`

## 1. Worktree Guard

If already in a worktree, skip. If not, and `--no-worktree` was not passed:
1. Derive a slug from the plan filename.
2. Call `EnterWorktree` with `name: <slug>`.
3. If unavailable, fall back to `qq-worktree.py create --name <slug>`, then tell the user to reopen in the new path and stop.
4. Seed runtime cache: `qq-worktree.py seed-runtime-cache --project . --source "<SOURCE_PROJECT>"`

## 2. Locate Plan & Resume

Find the plan (user arg → conversation → `Docs/qq/` scan → ask).

**Resume check:** Scan the plan for checked boxes (`- [x]`). If found, resume from the first unchecked step, regardless of phase boundaries. If a phase was partially completed, dispatch a subagent for the remaining unchecked steps in that phase. Report: "Resuming from step N (steps 1–M already complete)."

## 3. Analyze

Read the plan. Read CLAUDE.md and AGENTS.md (if it exists) before writing any code. Classify:
- **Small** (≤8 steps touching ≤12 files): main agent executes directly, using subagents only for independent parallel files.
- **Large** (>8 steps or >12 files across >3 modules): main agent becomes a **coordinator only** — dispatch each phase/group as a subagent. Do NOT write implementation code in the main session.

Use judgment for borderline cases — a 9-step plan with trivial single-file changes may not need coordinator mode.

Present a one-line-per-step breakdown, then immediately begin execution. No "Proceed?" prompt.

## 4. Execute

Follow existing project patterns.

### Subagent context rule

**Always pass context inline in subagent prompts.** Never ask subagents to read CLAUDE.md, AGENTS.md, or the plan file — paste the relevant content directly. This saves tool calls and ensures subagents get exactly the context they need.

### Small task execution

For each step, decide:
- **Has dependencies on the previous step** → write it yourself (main session)
- **Independent files** → dispatch parallel subagents
- **Sequential chain (A→B→C)** → execute sub-steps one by one; consider subagents for long chains (4+) to prevent context accumulation

### Large task execution (coordinator mode)

For each phase, dispatch a subagent with inline context: the phase steps, interfaces/contracts from completed phases, CLAUDE.md/AGENTS.md rules.

**The main agent writes zero implementation code in coordinator mode.** Its job is dispatch → verify → checkpoint → next phase.

For truly large module-crossing refactors (10+ files, 3+ independent modules), consider dispatching subagents with `isolation: "worktree"` to avoid file conflicts.

### Per-step checkpoint

After each step or phase completes:
1. **Verify compilation** — auto-compile hook handles .cs files. If compilation cannot be fixed after 3 attempts, stop and report to the user.
2. **Update plan checkbox** — change `- [ ]` to `- [x]` in the plan file. This is the resume point if the session breaks.

## 5. Completion

Summarize: what was implemented, deviations from plan, issues resolved.

**Without `--auto`:** recommend next step, wait for user:
- Clean → `/qq:test`
- Needs coverage → `/qq:add-tests` then `/qq:test`
- Had issues → `/qq:best-practice`
- Multi-module → `/qq:claude-code-review`

**With `--auto`:** take the strictest path automatically:
`/qq:best-practice` → `/qq:claude-code-review` → `/qq:add-tests` → `/qq:test` → `/qq:commit-push`

## Rules

- Do not add features or abstractions beyond what the plan specifies
- Each .cs save triggers auto-compilation — never skip this
- If a step is significantly more complex than planned, note the deviation and continue
- If the plan is ambiguous or contradictory, use best judgment and note the decision
- Test steps → prefer `/qq:add-tests` over hand-writing test files
