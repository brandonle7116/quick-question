# TODO

_Last updated: 2026-03-30_

This file tracks follow-up issues discovered after runtime, policy, and host-integration changes. Keep it current when new E2E or user-facing gaps show up.

## Open

### Codex MCP E2E

- [ ] Make Codex CLI non-interactive sessions expose the built-in `tykit_mcp` tool surface end-to-end.
  - Current finding: `codex mcp list/get` sees the server config, but `codex exec` only exposed generic MCP resource access in E2E and not the Unity tool surface.
  - Need to confirm whether this is:
    - a Codex CLI feature/config gap
    - an MCP server registration/detail issue
    - or a prompt/runtime limitation in `exec`

### Plugin rollout lag

- [ ] Make sure consumer projects get the current mode-aware `/qq:go` controller, not an older marketplace copy.
  - Current finding: repo-local `qq-project-state.py` and tests are correct, but a real Claude `/qq:go` run in `project_pirate_demo` still behaved like the older branch-centric controller.
  - Likely cause: the installed `qq@quick-question-marketplace` plugin has not picked up the latest skill/controller changes yet.
  - Need to verify:
    - how plugin content is packaged and versioned from this repo
    - whether a fresh publish/install is required
    - whether the project is actually loading the latest skill prompts

## Recently resolved

- [x] Artifact routing is now task-aware instead of repo-global.
  - `qq-project-state.py` only activates design docs / plans when they match current task evidence.
  - Repo-global docs remain background context unless they are the only candidate or match `task_focus` / modified files.
- [x] Compile/test freshness now invalidates stale verification after newer `.cs` changes.
  - `qq-project-state.py` downgrades stale runs to effective `not_run`.
  - `qq-run-record.py` and `tykit_bridge.py` now write sub-second timestamps so fresh verification is not immediately misclassified as stale.
- [x] `policy_profile` now changes controller recommendations, not just diagnostics.
- [x] `/qq:test` and pre-push now honor profile-driven default test scope.
- [x] `/qq:commit-push` checks controller state before continuing.
