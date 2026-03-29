---
description: "Entry point — detect where you are in the dev workflow and guide you to the right next step."
---

Respond in the user's preferred language (detect from their recent messages, or fall back to the language setting in CLAUDE.md).

Entry point for the qq development workflow. Detects your current state and guides you to the right skill.

Arguments: $ARGUMENTS
- A file path (design doc, plan, or code file)
- A brief description of what to build
- `--auto`: full pipeline, no prompts
- No arguments: auto-detect from context

## State Detection

Assess the current situation by checking (in order):

### 1. Did the user provide input?
- **File path to a design doc** → "This looks like a design doc. Want to run `/qq:plan` to create an implementation plan?"
- **File path to an implementation plan** → "This is an implementation plan. Want to run `/qq:execute` to start building?"
- **File path to .cs code** → "Want to run `/qq:best-practice` to check this code, or `/qq:test`?"
- **A brief description** → "I'll help you build this. Starting with `/qq:plan` to create an implementation plan."

### 2. Check conversation context
- **Just finished brainstorming / discussing a feature** → suggest `/qq:plan`
- **A plan was recently generated or reviewed** → suggest `/qq:execute`
- **Code was recently written or modified** → suggest `/qq:best-practice` or `/qq:test`
- **Tests just passed** → suggest `/qq:commit-push`

### 3. Check git state
- **Uncommitted .cs changes** → "You have uncommitted C# changes. Want to run `/qq:best-practice` to check them?"
- **Clean working tree, recent commits not pushed** → "You have unpushed commits. Want to run `/qq:test` before pushing?"
- **Clean tree, all pushed** → "Everything looks clean. Describe what you want to build next."

### 4. Nothing to go on
→ Ask: "What are you working on? You can give me a design doc, a one-liner, or tell me what stage you're at."

## `--auto` Mode

Skip all questions. Determine state, pick the strictest path, and chain through the full pipeline with `--auto` on each skill:

- Has description/design doc → `/qq:plan --auto`
- Has plan → `/qq:execute --auto`
- Has uncommitted code → `/qq:best-practice --auto`
- Has passing tests → `/qq:commit-push`

## Notes

- This skill never does work itself — it only routes to the right skill
- Always confirm with the user before invoking a skill (unless `--auto`)
- If ambiguous, ask one clarifying question, not five
