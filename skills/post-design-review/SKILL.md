---
description: "Review a game design document from an implementer's perspective — check self-consistency, playability, buildability, and codebase gaps. Use after writing a design doc, or when you want to validate an existing design against the current codebase."
---

Respond in the user's preferred language (detect from their recent messages, or fall back to the language setting in CLAUDE.md).

Review a game design document from an implementer's perspective.

Arguments: $ARGUMENTS (path to a design document, or empty to use the most recent design doc in `Docs/qq/`)

## Process

1. **Find the document:** if a path is given, read it. Otherwise, find the most recent `*_design.md` in `Docs/qq/`.
2. **Read the reviewer prompt:** read [design-reviewer-prompt.md](design-reviewer-prompt.md) for the full review checklist.
3. **Review independently:** read the codebase (Services, configs, existing design docs) to verify claims in the document. Do not rely solely on what the document says exists.
4. **Output the review** in the format specified in the reviewer prompt.
5. **If verdict is HAS GAPS or NEEDS REWORK:** present findings to the user. Offer to revise the document together. Loop until SOLID or the user explicitly accepts the gaps.
6. **If verdict is SOLID:** confirm and recommend `/qq:plan`.
