# Token Efficiency Improvements — qq + Maliang

## Problem
Agent-based pipelines burn tokens fast. Main waste areas: repeated file reads, full-plan prompts, wrong model for task, redundant review sessions, excessive max_turns.

## Proposal: 6 Improvements

### 1. Model Tiering (Largest Cost Saving)

Not all tasks need Opus ($15/M input). Route by task complexity:

| Task Type | Model | Cost/M Input |
|-----------|-------|-------------|
| Design, Plan, Execute | Opus | $15 |
| Code review, Commit | Sonnet | $3 |
| Compile check, Format validation | Haiku | $0.25 |

**qq implementation:** Add `model` hint in SKILL.md metadata. Agent uses it when dispatching subagents.
```yaml
---
description: "..."
recommended_model: sonnet  # for review skills
---
```

**Maliang implementation:** Add `model` field to Phase definition. Factory creates adapter with specified model.
```python
Phase("commit", agent_task="commit", model="sonnet")
```

**Expected saving: 30-40% total cost.**

### 2. Incremental Plan Context for Execute

Current: 105KB full plan YAML sent in every execute prompt.
Proposed: Only send current step + summary of completed steps.

```
## Goal: Inventory System

## Completed (summary only)
- Step 1: WeaponData.cs created (ScriptableObject with bodyDamage, fireRate fields)
- Step 2: PlayerHealth.cs created (100HP, TakeDamage, OnDeath event)

## Current Step (3 of 14)
Title: WeaponController
Instruction: [full instruction for this step only]
Files to read: [...]
Files to edit: [...]
Acceptance criteria: [...]

## Upcoming (titles only)
- Step 4: PlayerMovement
- Step 5: WeaponPickup
```

**Expected saving: 80% plan token (~95KB → ~10KB per step).**

### 3. Context File Summaries

Agent reads the same files repeatedly across steps/phases. After first read, store a one-line summary.

```python
# accumulated_decisions / prior_decisions becomes:
[
    "WeaponData.cs: ScriptableObject — bodyDamage(float), fireRate(float), magazineCapacity(int), recoilPattern(Vector2[])",
    "PlayerHealth.cs: MonoBehaviour — 100HP, TakeDamage(float,HitZone,TeamId), OnDeath event, TeamId property",
]
```

Agent gets enough context to write code that interfaces with these files without re-reading them. Only reads full file if needed for modification.

**Expected saving: 50% context file tokens.**

### 4. Dynamic max_turns

Fixed max_turns wastes tokens on simple tasks and may truncate complex ones.

| Task Complexity | Signals | max_turns |
|----------------|---------|-----------|
| Simple (1-2 files, enum/data class) | <50 lines expected | 30 |
| Medium (3-5 files, logic) | 50-200 lines | 80 |
| Complex (full feature, AI, UI) | 200+ lines | 200 |

Complexity estimated from plan step's `files_to_edit` count and instruction length.

```python
def estimate_turns(step: dict) -> int:
    files = len(step.get("files_to_edit", []))
    instruction_len = len(step.get("instruction", ""))
    if files <= 2 and instruction_len < 200:
        return 30
    if files <= 5:
        return 80
    return 200
```

**Expected saving: 20-30% execute tokens.**

### 5. Incremental Diff for Review

Current: `git diff HEAD` sends entire diff (potentially 5000+ lines).
Proposed: Send only file names, let agent read what it needs.

```python
# Current
diff = await run_cmd("git diff HEAD")  # 5000 lines
prompt = f"Review:\n{diff}"

# Proposed  
changed_files = await run_cmd("git diff --name-only HEAD")  # 20 lines
prompt = f"Review these changed files:\n{changed_files}\nRead each file and review for bugs."
```

Agent uses Read tool to inspect only what matters, rather than having 5000 lines of diff in context.

**Expected saving: 60-70% review tokens.**

### 6. Review Merged Into Phase (Already Done)

Design self-review and plan self-review already merged into design/plan prompts in v1.16.3. No separate review session needed.

**Already achieved: ~40% review token saving.**

## Combined Expected Impact

| Before (per feature pipeline) | After |
|------|------|
| ~2M tokens | ~600K-800K tokens |
| ~$30 (all Opus) | ~$8-12 (tiered) |
| 8 separate sessions | 4 sessions |
| 200 fixed turns per phase | 30-200 dynamic |

## Implementation Priority

1. **Model tiering** — config change, highest ROI
2. **Incremental plan context** — prompt change, second highest ROI
3. **Dynamic max_turns** — small code change
4. **Incremental diff** — prompt change
5. **Context summaries** — medium code change

## Risks

- **Model tiering:** Sonnet for review may miss subtle bugs Opus would catch. Mitigation: keep Opus for code review, use Sonnet only for design review and commit.
- **Incremental plan:** Agent may lose big-picture context if only seeing current step. Mitigation: include full step titles as "upcoming" preview.
- **Dynamic turns:** Underestimating complexity may truncate. Mitigation: start generous, tune down based on data.
- **Incremental diff:** Agent may skip reading important files. Mitigation: include diff --stat (lines changed per file) to guide attention.
