---
description: "Run Unity unit/integration tests and check for runtime errors."
---

Respond in the user's preferred language (detect from their recent messages, or fall back to the language setting in CLAUDE.md).

Run Unity unit/integration tests and check for runtime errors.

> **Unity Backend:** This skill supports multiple backends. If MCP tools are available (`run_tests` from mcp-unity, or `tests-run` from Unity-MCP), use them instead of the tykit/script commands below. If no MCP tools are available, use tykit's EvalServer as documented here. To discover tykit commands: `curl -s -X POST http://localhost:$PORT/ -d '{"command":"commands"}' -H 'Content-Type: application/json'` where PORT comes from `Temp/eval_server.json`.

Arguments: $ARGUMENTS
- (no arguments): Run both EditMode and PlayMode
- `editmode` / `edit`: EditMode only
- `playmode` / `play`: PlayMode only
- `--filter "TestName"`: Filter by test name (semicolon-separated for multiple)
- `--assembly "Asm.Tests"`: Filter by assembly (semicolon-separated for multiple)
- `--timeout 300`: Custom timeout in seconds

Examples:
- `/qq:test` → Run EditMode + PlayMode
- `/qq:test play` → PlayMode only
- `/qq:test editmode --filter "Health"` → Filter by name
- `/qq:test --assembly "Game.PlayerSystem.Tests"` → Filter by assembly

## Steps

### 1. Clear Console + Mark Editor.log position

```bash
source "$(git rev-parse --show-toplevel)/scripts/platform/detect.sh"
EDITOR_LOG="$(qq_get_editor_log_path)"
BASELINE=$(wc -l < "$EDITOR_LOG")
PORT=$(python3 -c "import json; print(json.load(open('Temp/eval_server.json'))['port'])" 2>/dev/null)
if [ -n "$PORT" ]; then
  curl -s --connect-timeout 5 --max-time 15 -X POST http://localhost:$PORT/ \
    -d '{"command":"clear-console"}' -H 'Content-Type: application/json'
fi
```

> **MCP backends:** Skip this step — neither mcp-unity nor Unity-MCP has a console-clear equivalent. Runtime error checking (Step 3) uses Editor.log directly and does not depend on console state.

### 2. Run tests

Select command based on arguments:

| Argument | Command |
|----------|---------|
| (none) | `./scripts/unity-unit-test.sh` |
| `editmode` | `./scripts/unity-test.sh editmode --timeout 180` |
| `playmode` | `./scripts/unity-test.sh playmode --timeout 180` |
| with filter/assembly | `./scripts/unity-test.sh <mode> --filter "X" --assembly "Y" --timeout Z` |

- With no arguments, run `unity-unit-test.sh` (EditMode → PlayMode in sequence; skip PlayMode if EditMode fails)
- With arguments, call `unity-test.sh` and pass all arguments through
- On failure, analyze the cause and determine whether it was introduced by the current changes or was pre-existing

> **MCP backends:** Use `run_tests` (mcp-unity) or `tests-run` (Unity-MCP) instead of the scripts above. Pass mode, filter, assembly, and timeout as tool parameters. When no mode argument is given, preserve the sequencing: run EditMode first, check the result, and only proceed to PlayMode if EditMode passes. On failure, apply the same analysis as below.

### 3. Check runtime errors

Even if all tests pass, runtime errors may still occur. Check via Editor.log (not dependent on the console API buffer):

```bash
tail -n +$((BASELINE + 1)) "$EDITOR_LOG" | \
  grep -iE "NullReferenceException|Exception:|Error\b" | \
  grep -v "^UnityEngine\.\|^Cysharp\.\|^System\.Threading\.\|^  at \|CompilerError\|StackTrace" | \
  sort -u
```

**Show all errors to the user — do not filter or omit any.** For each error, include a source assessment (e.g., "exception from TaskEdgeCaseTests safety test, likely expected behavior"), and let the user decide whether action is needed.

## On test failure

1. Analyze the failure output and identify the failing test name and assertion
2. Read the failing test's source file and the code under test
3. Propose a concrete fix
4. Ask the user whether to apply the fix automatically

## Handoff

After tests complete, recommend the next step:

- **All tests pass, no runtime errors** → "All green. Want to run `/qq:doc-drift` to check docs match the code before committing?"
- **Tests pass but runtime errors found** → "Tests passed but found N runtime errors. Want me to investigate, or proceed to `/qq:doc-drift`?"
- **Test failures were fixed** → "Fixed N failures. Want to re-run `/qq:test` to confirm, or proceed to `/qq:doc-drift`?"

**`--auto` mode:** skip asking:
- All pass → `/qq:doc-drift --auto` → `/qq:commit-push`
- Failures → auto-fix → re-run `/qq:test` (max 3 attempts, then stop and ask user)
