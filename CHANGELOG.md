# Changelog

All notable changes to quick-question are documented here.

## [1.16.25] — 2026-04-07

v1.16.25 closes the EnterWorktree completion gap discovered when an agent's Phase 0 dispatch failed with 'scripts/platform/ missing'. New 'seed-local-runtime' subcommand finishes what EnterWorktree starts: copies LOCAL_RUNTIME_PATHS (scripts/, .mcp.json, AGENTS.md, CLAUDE.md, qq.yaml), baseline state files, baseline run records, and writes .qq/state/worktree.json metadata so the new worktree behaves identically to a command_create-created one. Without it, every qq script in the new worktree exits 127 because scripts/platform/detect.sh is missing, and 5+ downstream consumers (commit-push Type B closeout, qq-codex-exec --add-dir injection, qq-project-state.py, qq-doctor.py, build_status flags) silently treat the worktree as unmanaged. Validation uses git common-dir matching plus 'git worktree list --porcelain' membership (NOT --show-toplevel, which differs by design between linked worktrees). clone_copy_tree gains an allow_hardlink parameter scoped strictly to Unity (Library is the only currently-supported engine cache that's safe to alias — Godot's uid_cache.bin and Unreal's UBT manifests are rewritten in place and would corrupt the source). Hardlink path uses a sibling staging directory with atomic rename: on partial failure (cross-device, unsupported FS), the staging dir is rmtreed and the function falls through to shutil.copytree on a clean target — preventing the catastrophic case where copytree's O_TRUNC on a partially-hardlinked file would write through the shared inode and corrupt the source's Library cache. On Windows (no rsync, no clonefile), this turns multi-GB Library seed from a 30-120 second real-byte copy into sub-second per-file os.link. /qq:execute and /qq:go SKILL.md updated to call seed-local-runtime then seed-runtime-cache (no --source, so metadata is authoritative). 6 new test.sh checks via TDD, full test.sh 384/384 green. Built test-first; followed two rounds of codex-plan-review (4 + 3 findings, all verified by parallel subagents, all incorporated).



## [1.16.24] — 2026-04-07

Comprehensive structural fix for the v1.16.22 README sync failure class. Four root causes are now mechanically enforced instead of relying on agent discipline: (a) NEW test.sh section 5f cross-language link discipline check — flags any docs/<lang>/X.md link to ../<other-lang>/Y.md when docs/<lang>/Y.md exists, with README.md ↔ README.md exempted as legitimate language switchers; (b) NEW qq-release.sh always-on pre-flight runs the README sync drift check (already in test.sh 5d) and the new cross-language link check at release time, BEFORE any commit, regardless of --skip-tests — closing the loophole where v1.16.22 was released because --skip-tests bypassed the entire section 5 pre-flight; (c) NEW HTML comment block above the Chinese half of root README explicitly warning agents that the section is auto-generated from docs/zh-CN/README.md, including the correct edit-then-sync workflow and noting that CI enforces it; (d) the existing test.sh 5d sync drift check is unchanged because it caught v1.16.22 at CI time, but B is its commit-time complement so the failure cannot reach remote in the first place. Together this means the v1.16.22 sequence (edit zh-CN README → forget to sync → use --skip-tests → push broken release → CI red → hot-fix release) is mechanically impossible going forward.



## [1.16.23] — 2026-04-07

Hot-fix v1.16.22 readme rollout: (a) three links in docs/zh-CN/README.md were pointing to docs/en/* instead of the existing zh-CN siblings (tykit-mcp.md, tykit-api.md, worktrees.md), (b) the root README.md is a bilingual file whose Chinese half is generated from docs/zh-CN/README.md by scripts/qq-sync-readme-zh.py — v1.16.22 updated the English half and docs/zh-CN/README.md but never ran the sync, leaving the root README's Chinese half stuck on the old 12-line Quick Start and tripping the CI structural check 'root README Chinese half drifts from docs/zh-CN/README.md'. v1.16.23 fixes the three zh-CN links and runs the sync script, so the bilingual root README is now consistent across both halves and CI passes. Behavior unchanged — pure docs sync.



## [1.16.22] — 2026-04-07

Rewrite README Quick Start as an ROI-focused 5-step onboarding guide (en + zh-CN). The previous Quick Start was 12 lines — a flat code block + one sentence — which left new users with no guidance on which of the 26 commands actually matter, when to escalate work_mode, what to skip in week one, or how to avoid the most common ceremony pitfalls. The new version follows the 80/20 principle: (1) work_mode selection table with the explicit warning that the most common new-user mistake is leaving the project on hardening by default, (2) the 4-command happy path /qq:go → /qq:execute → /qq:test → /qq:best-practice covering 90% of work, (3) three concrete templates for feature dev / bug fix / pre-merge gate, (4) a 'do not touch in week one' list (bootstrap, heavy doc ceremony, cross-model review on every change, --auto, custom profiles), (5) CLAUDE.md customization with 6 example Unity-project hard rules positioned as the highest-ROI customization. Adds two explicit anti-patterns (do not read raw .qq/runs/*.json in prompts, do not run cross-model review after every small edit) and four week-one self-check questions for diagnosing whether the workflow is actually saving time vs just adding ceremony noise. ja/ko READMEs not yet updated and remain on the old thin Quick Start until the next i18n batch.



## [1.16.21] — 2026-04-07

Fix two related worktree bugs in /qq:execute and /qq:go that surfaced when an agent (a) silently invented a '--no-worktree semantics' to bypass the worktree guard on encountering an untracked plan file, polluting main with a 24-step plan execution; and (b) called EnterWorktree which silently branched the new worktree from develop instead of the current feature branch (u/tyk/DPP-961-...), losing a freshly-committed plan commit and forcing a cherry-pick recovery. The Worktree Guard section is now strict — only three skip conditions are allowed (already in a worktree, literal --no-worktree token, or trivially small plan), agent-invented bypasses are explicitly forbidden, common obstacles like 'plan is untracked' get a corrective fix table ('git commit the plan first, then enter worktree'), and silent skips are banned. After EnterWorktree runs, the skill now mandatorily captures the source HEAD beforehand and verifies via git merge-base --is-ancestor that the new worktree's HEAD includes the source HEAD; if EnterWorktree branched from the wrong ref, the skill auto-recovers via git reset --hard SOURCE_HEAD (because the new worktree branch has no commits of its own yet). Cherry-pick is documented as NOT sufficient — it brings commits over but leaves the merge-base wrong, which corrupts later git diff source...HEAD scoping. Same fixes mirrored to /qq:go's Worktree Isolation section.



## [1.16.20] — 2026-04-07

Unify the Chinese README via a generator + drift check, complementing v1.16.19 (review script bin/ path fix from a parallel session). The Chinese content used to live in two parallel files (root README's Chinese half and docs/zh-CN/README.md), translated independently in different sessions and gradually drifting apart — different section titles, different phrasing, different table cells in some places translated and others left in English. This release collapses both onto a single canonical source. New scripts/qq-sync-readme-zh.py reads docs/zh-CN/README.md (the canonical), strips the title + lang nav, rewrites relative paths to be repo-rooted (../../X → X, ../X → docs/X, bare → docs/zh-CN/X), and replaces the block between the Chinese h2 and the project footer in root README. Modes: --check (default, exit 1 on drift), --write (rewrite root in place), --print (debugging). test.sh section 4 enforces the contract by running --check after the tykit coverage ratchet, failing CI with a clear DRIFT message if anyone forgets to run --write. The lang nav 中文 link in the root README now points to the in-page anchor (#中文) instead of navigating to docs/zh-CN/README.md, so Chinese readers see the content directly on the GitHub project page. docs/zh-CN/README.md still exists as the canonical editing target and a fallback for direct navigation. CLAUDE.md Conventions documents the contract: edit the canonical, run --write, commit both, and let test.sh catch forgotten syncs.



## [1.16.19] — 2026-04-07

Fix 4 review skills (codex-plan-review, codex-code-review, claude-plan-review, claude-code-review) that told agents to invoke scripts as bare commands like 'plan-review.sh <file>'. The qq plugin never puts its scripts on PATH, and install.sh's permission allowlist only covers relative-path variants ('./scripts/X', 'scripts/X'), so bare invocation was unreliable from day one — it only 'worked' when agents happened to use relative paths or jumped straight to the fallback. Today a real agent hit exit 127 on 'plan-review.sh' and had to manually switch to the ${CLAUDE_PLUGIN_ROOT}/bin/ fallback mid-run. All four SKILL.md files now use ${CLAUDE_PLUGIN_ROOT}/bin/<script>.sh as the canonical invocation (absolute path, cwd-independent, env var injected by Claude Code for every plugin context), and the top-of-skill callout was reworded from 'bare command with fallback' to 'use ${CLAUDE_PLUGIN_ROOT}/bin/, bare is NOT reliable'. Non-review scripts like unity-test.sh are untouched — they continue to work through install.sh's relative-path allowlist.



## [1.16.18] — 2026-04-07

Honest sourcing pass on the README. Adds a verified/experimental status callout to all five language READMEs (English half + Chinese half of root README, plus docs/zh-CN, docs/ja, docs/ko) right under the language nav, before the Why qq section. The callout makes the actual support level visible: Claude Code + Unity 2021.3+ on macOS or Windows is the verified path (daily-driven, end-to-end battle-tested), and Godot / Unreal / S&box adapters plus non-Claude hosts (Codex CLI, Cursor, Continue, other MCP hosts) are experimental scaffolds. The non-Unity adapters have CI smoke tests and bridge code in place but no one has yet shipped a real game on any of them. Bug reports and PRs are how an adapter graduates to verified. Also tags non-Unity rows in the Engines table with 🧪 preview markers (Unity gets ✅ verified) and rewrites the prose under the table to drop the previous runtime parity framing. Hero tagline corrected from 'verified inside Unity, Godot, Unreal, and S&box' to the neutral 'across Unity, Godot, Unreal, and S&box'. The previous wording overclaimed and could lead users to expect a level of support that does not yet exist for non-Unity engines.



## [1.16.17] — 2026-04-07

Add tykit command coverage audit (scripts/qq-tykit-coverage.py) and integrate it into test.sh as a regression ratchet, complementing v1.16.16's bridge coverage work. Where v1.16.16 closed the Python MCP bridge gap (89/89 tykit commands now ergonomically exposed via unity_editor instead of unity_raw_command), this release closes the test coverage visibility gap on the C# side: the audit walks packages/com.tyk.tykit/Editor/Commands/*Commands.cs to extract every CommandRegistry.Describe call, then walks Tests/Editor/*.cs to check whether each command name appears as a literal string in any test file. Result: 89 registered tykit commands, only 11 with test references (12%), 78 uncovered. test.sh section 4 enforces TYKIT_MAX_UNCOVERED=78 — the gap cannot grow, only shrink. As tests land in v1.17.x the threshold ratchets down each release until parity. The audit script supports --strict, --max-uncovered N, --json, --project flags for both standalone use and CI integration. Why this matters: tykit v0.5.0 shipped roughly 50 new commands across reflection / prefab / physics / asset / UI / prefs / batch / main-thread recovery (commits dfbe63b, fabc8a3, 81b0bbe) but C# test coverage did not follow at the same pace, leaving 9 of 13 command classes (Animation, Hierarchy, Input, Physics, Prefab, Screenshot, Test, UI, Visual) with zero dedicated tests. This audit makes that gap visible and is a prerequisite for promoting the Evaluator layer (core-roadmap.md short-term) which depends on tykit being a trustworthy capability provider. Also closes issue #3 (claude-plan-review.sh script-name mismatch + codex CLI dependency + Windows git-bash failures) — all three points were resolved across v1.13.x through v1.16.x and verified by test.sh review-script-symmetry section.



## [1.16.16] — 2026-04-07

Tykit MCP bridge now exposes 89/89 commands ergonomically (added request-script-reload to unity_editor action dict, closing the last raw-command-only gap). New shared/tykit-first.md captures the when-to-use-tykit-vs-read-code decision rule with 14 concrete scenarios, linked from tykit-reference.md and from the codex-code-review, claude-code-review, explain, and self-review skills so verification subagents reach for live runtime queries before falling back to source reading.



## [1.16.15] — 2026-04-07

Documentation mirror pass: bring zh-CN, ja, and ko READMEs to parity with the v1.16.7 English restructure (new 'Why qq' / 'なぜ qq か' / '왜 qq인가' pitch, How it works 4-layer breakdown, Install agent table, all 26 commands including bootstrap / post-design-review / design-research that were previously missing, tykit v0.5.0 + listener-thread main-thread recovery story, refreshed FAQ). docs/zh-CN/hooks.md fully rewritten to mirror docs/en/hooks.md from v1.16.14 — adds compile-gate, auto-pipeline-stop, auto-sync, SessionStart resume hints, qq_hook_input fallback note, and an Implementation Notes section. docs/dev/architecture/overview.md hook table extended to cover the same set, with a sentence about the jq → python3 fallback. docs/dev/core-roadmap.md drops the stale 'Unity is the current wedge / can later support Unreal, Godot, custom engines' framing — Godot, Unreal, and S&box are now at runtime parity through Python bridges, not future work — and the Engine Adapters listing enumerates all four current adapters.



## [1.16.14] — 2026-04-07

Documentation pass: rewrite docs/en/hooks.md to cover the full current hook surface (compile-gate, auto-pipeline-stop, auto-sync, SessionStart resume hints — none of which the previous version mentioned), replace the legacy review-gate-{check,set,count,stop}.sh references with the unified review-gate.sh subcommands, document qq_hook_input (jq-first, python3 fallback) so future hook authors stop calling jq directly, clarify pre-push-test.sh is wired through .claude/settings.json (not the plugin hooks.json), and add an Implementation Notes section. Also lands three docs/zh-CN updates: README.md tykit section rewritten for the v0.5.0 60+ command surface plus listener-thread recovery differentiator, configuration.md gains the .qq/state/session-decisions.json row, getting-started.md gains an engine-support callout noting the scenarios use Unity for concrete examples but the same flow works on Godot, Unreal, and S&box.



## [1.16.13] — 2026-04-07

Ship the actual tykit doc content described in v1.16.12's release notes. The v1.16.12 commit bumped the version and added the CHANGELOG entry but qq-release.sh only auto-staged the 3 release-managed files (plugin.json, README badge, CHANGELOG), not the 5 supporting tykit doc rewrites — so the changelog described content that hadn't shipped yet. This release contains: docs/en/tykit-api.md (full ~60-command rewrite organized by category, plus Two HTTP Channels and Main Thread Recovery sections), docs/zh-CN/tykit-api.md (mirror), docs/en/tykit-mcp.md (standard profile 11→15 tools, new examples for unity_physics / unity_object reflection / unity_main_thread_health, dedicated Main Thread Recovery section, Fast-Path Routing now mentions qq-compile.sh), docs/zh-CN/tykit-mcp.md (mirror), and packages/com.tyk.tykit/README.md (en/zh full rewrite + ja/ko summary refresh). Also fixes qq-release.sh itself: the 'these will be included in the release commit' warning was a lie — it didn't actually stage the listed files. v1.16.13 makes the warning true by auto-staging extra dirty files into the release commit.



## [1.16.12] — 2026-04-07

Big tykit doc refresh after the v0.5.0 surface expansion (~50 new commands across reflection, prefab, physics, asset, UI, prefs, batch, recovery). Rewrites docs/en/tykit-api.md, docs/zh-CN/tykit-api.md, and packages/com.tyk.tykit/README.md (en + zh + ja + ko sections) to cover the full ~60-command surface organized by category. Updates docs/en/tykit-mcp.md and docs/zh-CN/tykit-mcp.md: standard profile from 11 to 15 tools, new examples for unity_physics / unity_object reflection / unity_main_thread_health, dedicated 'Main Thread Recovery' section, Fast-Path Routing now mentions qq-compile.sh multi-engine dispatcher. Root README tykit section expanded with the v0.5.0 differentiator story (listener-thread GET endpoints surviving blocked main threads — every other Unity bridge dies in this scenario).



## [1.16.11] — 2026-04-06

Add cross-doc link rot lint as test.sh section 5e and fix the 32 broken links it found across docs/. Also fixes a bug in qq-release.sh introduced in v1.16.10 (re.escape leaking into a text.replace call) — caught by the helper's own post-bump lint check on first dogfood.



## [1.16.10] — 2026-04-06

### Fixed
- **Windows: `test.sh` now runs all 10 sections** (was: dying at section 7 → 8 with exit 49 because of the Microsoft Store `python3` alias). The Store alias is on PATH but exits non-zero on `--version`, so several detection sites needed to switch from `command -v python3` (which finds the broken stub) to `"$QQ_PY" --version` (which the stub fails). Coverage on Windows went from **226 ✓ / 0 ✗ across 7 sections** to **369 ✓ / 3 ✗ across all 10 sections** — a 143-test increase that was previously hidden because section 8 never ran on Windows.
- **5 shell scripts** updated from the broken `command -v` pattern to the proven `--version` pattern: `scripts/docker-dev.sh`, `scripts/qq-runtime.sh`, `scripts/qq-doctor.sh`, `scripts/qq-compile.sh`, `scripts/qq-test.sh`. The fix matches the pattern already in `scripts/qq-policy-check.sh` from v1.15.6.
- **9 Python subprocess sites** now use `sys.executable` instead of hardcoded `"python3"`, so child processes inherit the working interpreter instead of re-hitting the Store alias: `scripts/qq-project-state.py:235`, `scripts/qq-codex-exec.py:42`, `scripts/qq-doctor.py:444`, `scripts/qq-doctor.py:570`, `scripts/qq_mcp.py:266`, `scripts/qq_mcp.py:282`, `scripts/godot_bridge.py:853`, `scripts/sbox_bridge.py:748`, `scripts/unreal_bridge.py:717`.
- **`scripts/qq-project-state.py` path output normalized to forward slashes** via a new `posix_str()` helper applied to four path fields (`project_dir`, `shared_config_path`, `local_config_path`, `worktree_source_worktree_path`). Previously, Windows backslashes broke any test or downstream tool that used `.endswith(".qq/local.yaml")` style suffix checks.
- **`scripts/qq-codex-exec.py:run_codex()` resolves `codex.CMD` on Windows** via `shutil.which()` before calling `subprocess.run`. Python on Windows can't exec `.CMD` / `.BAT` files via a bare name without PATHEXT resolution; passing the full resolved path works on every OS.
- **`install.sh` is now Windows-clean**: added `QQ_PY` detection at the top (using `--version`, not `command -v`); replaced ~14 hard-coded `python3` subprocess invocations with `$QQ_PY` (excluding the literal `python3` strings inside the Claude permission baseline heredoc, which must stay literal because Claude Code matches them against the user's actual command line); the dependency check itself now uses `--version` so the Store stub is correctly flagged as missing instead of silently passing.
- **`test.sh` now exports `GIT_CONFIG_PARAMETERS="'core.autocrlf=false'"`** at the top, so all git fixtures see autocrlf off. Without this, Windows git autocrlf converted committed files back to CRLF in the working copy, making them appear "modified" relative to the index — which made the worktree closeout test fail with "uncommitted changes" right after committing the fixture.

### Added
- **`scripts/qq-release.sh`** — release helper that wraps the 4×-this-session manual ceremony into one command. Bumps `plugin.json`, the README version badge, and prepends a CHANGELOG entry; runs the v1.16.9 section 5 lint as a pre-flight gate (refusing to release if version-badge ↔ plugin.json drift, skill-count drift, or legacy `review-gate-*.sh` references are present); commits, pushes, and watches CI. Supports `--dry-run`, `--no-push`, `--skip-tests`, `--version X.Y.Z`. Designed to never amend, never auto-skip hooks, and refuse to bundle unrelated working-tree changes silently.

- **`test.sh` now exits 0 on Windows** (was: exit 49 → exit 1 → exit 0). Final result: **370 ✓ / 0 ✗ / 3 ∅** across all 10 sections. The 3 skipped tests are gated on `IS_WINDOWS` because they create fake bare-name executables (`codex`, `UnrealEditor-Cmd`, `dotnet`) that Linux can shebang-exec but Windows can't run via PATHEXT. The skip helper (`skip()`) and a new `IS_WINDOWS` detection were added at the top of `test.sh`. The skipped tests are: `qq-codex-exec isolates the current qq MCP server when multiple qq servers are registered`, `unreal-compile invokes the project-local compile check through UnrealEditor-Cmd`, `qq-compile and qq-test route S&box projects onto dotnet build/test targets`. Linux CI runs all three normally.
- The unreal-compile and sbox tests also got partial path-normalization improvements (`replace("\\", "/")` + `.as_posix()` on the expected paths) so the assertion is OS-independent at the comparison layer; the OS gate is still needed because the underlying log content can also have path differences in earlier args. Future work: drop the gate once the gen path is fully normalized.
- **`scripts/qq-auto-sync.py`** + **`scripts/qq_internal_git.py`** — small auto-repair feature: when `auto-sync.sh` runs at session start, if the project's local `core.hooksPath` is set to the silently-broken default `.git/hooks/`, repair it. Only acts on the local config; never touches global / system git config or user-chosen custom hook directories. Required by the qq-doctor test fixtures that v1.16.10's Windows-clean test.sh now exposes.

## [1.16.9] — 2026-04-06

### Added
- **`test.sh` README consistency lint extended** with four new checks (section 5):
  1. Skill count consistency across the three language READMEs (`docs/zh-CN/README.md`, `docs/ja/README.md`, `docs/ko/README.md`) — regex covers English, Chinese 个, Japanese 個, and Korean 개.
  2. README version badge matches `.claude-plugin/plugin.json` version field — catches the kind of badge drift we had between v1.13.0 and v1.16.6 unnoticed for several releases.
  3. No legacy `review-gate-{check,set,count,stop}.sh` references anywhere in `docs/` or `templates/` — the unified `review-gate.sh <subcommand>` form is now enforced by CI.
  4. (Future-proofing the same shape for any other split-script consolidation we do.)

### Changed
- **`docs/dev/agent-integration.md`** — updated three sections to reflect multi-engine reality: the qq/Claude transport list now references `qq-compile.sh` / `qq-test.sh` (multi-engine dispatchers); the Adapter Boundary section no longer claims Unity is the only strongly implemented adapter family (Godot, Unreal, S&box are at runtime parity); the Operational Guidance section now uses Unity tool names as concrete examples but explicitly notes the same patterns apply to `godot_*` / `unreal_*` / `sbox_*`.

### Notes
- Survey agents during the v1.16.7 / v1.16.8 cleanup produced multiple false positives (claimed stale items in `templates/CLAUDE.md.example`, `templates/AGENTS.md.example`, `packages/com.tyk.tykit/README.md` ja/ko sections, `docs/dev/qq-project-state.md` field naming, `docs/dev/qq-benchmarks.md` suite files, `scripts/docker-dev.sh`). All were verified by grep / Glob and confirmed not stale. Future survey passes should require agents to include grep-verifiable line refs or run their own grep first.

## [1.16.8] — 2026-04-06

### Changed
- **README.md Chinese section rewritten** to mirror the new English half: control-plane pitch ("游戏开发 agent 的控制平面，闭环 — 编译、测试、审阅、交付"), tightened prose, lifecycle-aware narrative woven into "为什么是 qq", "工作原理" promoted next to the intro with a 4-layer breakdown, four `<details>` install collapsibles consolidated into a single connect-your-agent table. Banner added in v1.16.7 removed; English and Chinese halves are now in sync. Total README size 601 → 466 lines (-22.5%).
- **Translated READMEs (`docs/zh-CN/README.md`, `docs/ja/README.md`, `docs/ko/README.md`)** — fixed stale "23 commands" → 26 in all three; dropped "Windows preview" labels (Windows 1.15.x / 1.16.x hardening is now reflected); Chinese FAQ Windows answer expanded with the recent Windows fixes (LF, path normalization, Python Store alias, jq fallback).
- **`docs/en/hooks.md` and `docs/zh-CN/hooks.md`** — updated all 8 references each from the legacy split scripts (`review-gate-{check,set,count,stop}.sh`) to the unified `review-gate.sh <subcommand>` form.
- **`docs/en/cross-model-review.md` and `docs/zh-CN/cross-model-review.md`** — same `review-gate-stop.sh` → `review-gate.sh stop` cleanup.
- **`docs/dev/architecture/overview.md`** — opening paragraph rewritten to match the new pitch + multi-engine framing; "Smart Compilation Stack (Unity)" section replaced with "Smart Compile Dispatch" that documents the `qq-compile.sh` multi-engine entry point and per-engine common files.
- **`docs/en/getting-started.md`** — added an opening note that the Unity examples in the scenarios apply equally to Godot, Unreal, and S&box; the runtime auto-detects the engine.
- **`docs/en/configuration.md`** — added `.qq/state/session-decisions.json` (cross-skill decision journal) to the file table so readers know `/qq:go` consults it for cross-skill coherence.
- **`templates/qq.yaml.example`** — removed the stale `context_capsule:` block; Context Capsule was deleted in v1.10.0, the template was a forgotten residue.
- **GitHub repo metadata** — description updated to match the new control-plane pitch; topics swapped: dropped 3 vague internal-sounding ones (`cid`, `harness-engineering`, `context-engineering`), added 4 missing engine / interop topics (`godot`, `unreal`, `sbox`, `mcp`).

## [1.16.7] — 2026-04-06

### Changed
- **README rewrite (English half)** — sharper pitch ("The control plane for game-dev agents. Close the loop — compile, test, review, and ship — verified inside Unity, Godot, Unreal, and S&box."), tightened prose, the lifecycle-aware narrative woven directly into "Why qq", "How it works" promoted to immediately after the intro, the four engine bridges treated as runtime parity throughout. Version badge bumped to v1.16.6, "preview" label dropped from the platform badge to reflect the 1.15.x / 1.16.x Windows hardening. Install section's four `<details>` collapsibles consolidated into a single connect-your-agent table. The Chinese section is unchanged this pass and now carries a banner pointing to the English section as canonical.
- **`.claude-plugin/plugin.json` description** — replaced the feature-list paragraph with the new control-plane pitch, aligned with README hero.
- **`CLAUDE.md` (project root) full rewrite** — corrected stale claims ("Unity developer-loop runtime" / "22 skills" / "Unity 2021.3+"). Now: multi-engine runtime, 26 skills, four engines, accurate hook surface (compile gate, review gate, session-start auto-sync, decision journal), `qq-compile.sh` multi-engine dispatcher, unified `review-gate.sh` with subcommands, mention of `qq_hook_input` shared helper.
- **`AGENTS.md` cleanup** — removed Context Capsule residue (Context Capsule was removed in v1.10.0 but the trust-level description still referenced it). Generalized "Unity-specific validation" to "engine-specific validation" so the host / Docker split rule reads correctly for Godot / Unreal / S&box work too.

## [1.16.6] — 2026-04-06

### Fixed
- **Hook scripts no longer require `jq`** — all 6 Bash/Edit/Write/Agent hook scripts (`auto-compile.sh`, `compile-gate-check.sh`, `pre-push-test.sh`, `review-gate.sh`, `skill-modified-track.sh`) now use a new `qq_hook_input` helper in `qq-runtime.sh` that prefers `jq` when available and falls back to `$QQ_PY` (python3) when it isn't. Previously, Windows users without `jq` on PATH saw repeated `PreToolUse:Bash hook error` / `PostToolUse:Bash hook error` on every Bash tool call because `set -euo pipefail` + `jq: command not found` (exit 127) crashed the scripts. The fallback keeps hooks working on any box that has python3 (already a hard dependency).

## [1.16.5] — 2026-04-06

### Fixed
- **Windows hook execution** — `.gitattributes` now forces LF line endings for `.sh` and `.py` files. Previously, Windows `core.autocrlf=true` converted hook scripts to CRLF on checkout, causing Git Bash to fail with "No such file or directory" errors when executing hooks (bash interprets `\r` as part of the path).

## [1.16.4] — 2026-04-06

### Added
- **Token efficiency spec** at `docs/qq/main/token-efficiency-spec.md` — analysis of model tiering, incremental plan context, dynamic max_turns, smart diff. Implementation landed in maliang-orchestrator (separate repo).

### Notes
- v1.16.3 was released as a hotfix bundle but missed CHANGELOG entries for several earlier improvements; v1.16.4 catches up the docs.

## [1.16.3] — 2026-04-05

### Added
- **Self-review directives** in design/plan/execute skills — agent self-checks before saving
- **Completeness validation** in execute — checks for stubs, empty methods, TODO markers after each step
- **Decision journal** (`qq-decisions.py`) — tracks cross-skill design decisions in `.qq/state/session-decisions.json`
- **Unified review gate** (`review-gate.sh`) — consolidated 4 gate scripts into one with subcommands

## [1.16.2] — 2026-04-04

### Fixed
- **Windows 全面兼容**：benchmark runner 用 Git Bash 完整路径替代 bare `bash`（避免 WSL 截获）；solver JSON 用 `{python}` 占位符替代硬编码 `python3`；shell solver 在 Windows 用 bash 替代 zsh；subprocess 加 `errors="replace"` 防 UnicodeDecodeError
- Windows 本地 5 个 benchmark suite 29 个用例全部通过

## [1.16.1] — 2026-04-04

### Fixed
- **Windows 全量路径修复**：7 个文件共 23 处 `str(path.relative_to())` 改为 `.as_posix()`，所有路径输出统一 `/` 分隔符
- benchmark runner Windows 上 `.sh` 文件自动加 `bash` 前缀

## [1.16.0] — 2026-04-04

### Fixed
- benchmark runner 用 `sys.executable` 替代 `shutil.which("python3")`（Windows 兼容）
- review gate 只在有运行时代码变更时触发（doc-only 不拦截）
- 更新所有 eval benchmark 断言适配 add-tests gate + review gate 新逻辑

## [1.15.9] — 2026-04-04

### Fixed
- `should_recommend_add_tests` 简化：有运行时变更 + 编译通过 + 无测试文件变更 → 推荐 add-tests（所有模式）
- review gate 只在有运行时代码变更时触发（doc-only 改动不拦截）
- 更新 eval benchmark 断言适配新的 recommend_next 逻辑

## [1.15.8] — 2026-04-04

### Fixed
- `should_recommend_add_tests` 改为检测"有运行时代码但无测试文件变更"，而非"测试没跑"。修复新功能代码通过旧测试后直接跳到 commit-push、不补测试的问题
- `recommend_next` 在 commit-push 前增加 add-tests 检查门（review → add-tests → commit-push）

## [1.15.7] — 2026-04-04

### Fixed
- review 脚本自动检测主分支（develop → main → master），不再硬编码 `main`
- branch diff 为空时自动 fallback 到 uncommitted changes（而非报 "no changes found" 退出）
- 同时修复 `code-review.sh` 和 `claude-review.sh`

## [1.15.6] — 2026-04-04

### Fixed
- `qq-policy-check.sh` 内嵌 Python 中 `python3` 硬编码改为 `sys.executable`（Windows 兼容）
- `qq-policy-check.sh` QQ_PY fallback 用 `--version` 替代 `command -v`（避免 Windows Store alias）

## [1.15.5] — 2026-04-04

### Fixed
- auto-sync 在无 `selectedModules` 时全量同步 plugin scripts/ 目录，修复 `code-review.sh` 等 workflow 脚本缺失问题

## [1.15.4] — 2026-04-04

### Fixed
- execute 完成后推荐顺序改为 review → test → commit-push，不再直接推荐 commit

## [1.15.3] — 2026-04-04

### Changed
- **code review 默认审查未提交代码**：`claude-code-review` 和 `codex-code-review` 的默认 scope 从 `develop...HEAD`（branch diff）改为 `git diff HEAD`（uncommitted changes）。修复"代码没 commit 导致 review 找不到 diff"的问题。
- review skill description 精简，明确使用时机："Use after /qq:test passes, before /qq:commit-push"

## [1.15.1] — 2026-04-04

### Changed
- **恢复 per-phase review**：实测证明 review 能抓到编译抓不到的逻辑错误（如"每次伤害触发声望"应为"仅击杀时触发"、"状态存在非持久对象上"）。review prompt 聚焦行为正确性而非类型正确性。

## [1.15.0] — 2026-04-04

### Added
- `bin/` wrapper 脚本（14 个），Claude Code 自动加入 PATH，SKILL.md 裸命令调用
- `qq-run-record.py --state-only` flag，只写 state 不写 runs/

### Changed
- 所有 SKILL.md 中 `./scripts/xxx` → 裸命令（兼容 Claude Code + Codex）
- review_gate hooks 改用 `--state-only`，不再往 runs/ 写记录
- **`/qq:execute` 精简**：移除 per-phase review subagent，只保留编译验证 + checkpoint。质量把关由完成后的 `/qq:best-practice` + `/qq:claude-code-review` 负责。

### Fixed
- `hooks.json` 用 `${CLAUDE_PLUGIN_ROOT}` 替代 `git rev-parse`
- Windows `python3 --version` 检测替代 `command -v python3`（避免 Store alias）
- `windows.sh` 加 Unity Hub `editors-v2.json` 查找

## [1.14.1] — 2026-04-04

### Fixed
- execute per-phase review 标记为 mandatory（"NOT optional"），防止 agent 跳过
- 删除无关的 script path fallback 行

## [1.14.0] — 2026-04-04

### Changed
- **`/qq:execute` coordinator 模式重构**：
  - 独立 phase 可并行 dispatch + 并行 review；依赖 phase 严格串行 + review gate
  - 编译失败明确 dispatch fix subagent（主 agent 不写代码）
  - review subagent 传入 prior phase 接口代码作为上下文
  - 支持非线性 phase 顺序（按 plan 指定顺序执行）
  - 小任务 3+ 文件也 dispatch review subagent
  - 禁止写 plan 文件或进入 plan mode

### Fixed
- CI `grep -P` 改为 python3 提取版本号（macOS 兼容）
- pre-push hook 本地检查版本一致性

## [1.13.3] — 2026-04-04

### Fixed
- auto-sync 支持无 `install-state.json` 的项目（`.qq/` 存在但从未成功跑过 `install.sh`）
- Windows `bin/` 脚本兼容 + 全面 Windows 路径修复

## [1.13.1] — 2026-04-04

### Fixed
- auto-sync hook matcher 从 `startup` 改为空匹配，覆盖 resume/clear/compact 所有 session 事件

## [1.13.0] — 2026-04-04

### Added
- **Plugin Auto-Sync**：`SessionStart[startup]` hook 自动检测 plugin 升级，将新增/更新的 scripts 同步到项目目录。用户只需 `/plugins → upgrade`，下次开 session 自动部署脚本，不再需要手动跑 `install.sh`
- `qq-auto-sync.py`：轻量同步脚本，读写 `install-state.json` 作为唯一 state 源，不需要 jq

## [1.12.1] — 2026-04-04

### Fixed
- `qq-execute-checkpoint.py` 加入 `runtime-core` 安装列表，修复 install 后项目目录缺少 checkpoint 脚本的问题

## [1.12.0] — 2026-04-04

### Added
- **Execute Checkpoint/Resume 系统**：
  - `qq-execute-checkpoint.py`：确定性 checkpoint 脚本（save/resume/clear），用 step 标题文本匹配 checkbox，JSON 为权威源
  - `SessionStart[compact]` hook：上下文压缩后自动注入执行恢复提示
  - `qq-project-state.py` 检测活跃执行，`recommend_next` 自动返回 `/qq:execute <plan>`
- `/qq:execute` coordinator 模式 per-phase 轻量 review（dispatch subagent 检查实现与 plan 一致性）

### Changed
- `/qq:execute` checkpoint 从 Edit plan 文件改为调用 `qq-execute-checkpoint.py` Bash 命令（确定性，不依赖 agent 记忆）

## [1.11.0] — 2026-04-04

### Changed
- **`/qq:execute` 重写**：
  - 执行永远自动，不再逐步问用户确认
  - `--auto` 语义改为"完成后自动走下一步"（best-practice → code-review → add-tests → test → commit-push）
  - 大任务（>8步 / >12文件 / >3模块）自动切 coordinator 模式，每 phase 派 subagent，主 agent 不写实现代码
  - 每步完成后更新 plan checkbox（`- [x]`），支持断点恢复
  - 从 154 行精简到 88 行

## [1.10.0] — 2026-04-04

### Removed
- **Context Capsule 系统**：移除 `qq-context-capsule.py`（~660 行）、capsule 配置、capsule 测试、所有相关 hook 触发和文档。该功能在 Claude Code 端从未被消费，在 Codex 端可被 `.qq/state/` 直接读取替代。
- `qq-codex-exec.py` 中的 `--resume` / `--no-resume` / `--resume-refresh` / `--resume-note` 参数
- `qq_internal_config.py` 中的 `context_capsule` 配置段（`qq.yaml` 中的 `context_capsule:` 字段将被静默忽略）

### Changed
- `session-cleanup` hook 不再触发 capsule 构建，仅执行 gate 清理和 prune
- `qq-codex-exec.py` 精简为纯 worktree/sandbox/MCP 隔离 wrapper
- `qq-doctor` 输出不再包含 `contextCapsule` 段
- `qq-worktree` create/closeout 不再构建或携带 capsule

### Added
- `/qq:plan` skill 增强：review 步骤必选，优先跨模型 codex review，技术选型时自动调用 `/qq:tech-research`
- `/qq:post-design-review` 独立 skill，主 agent 验证 subagent 结果后再呈现
- 4 个 review skill 统一引用共享 `verification-prompt.md`

### Fixed
- `skills/_shared/` 路径修正为 `shared/`
- codex-exec worktree 测试中残留的 resume 字段断言

## [1.9.0] — 2026-03-31

### Added
- first-party S&box runtime parity:
  - `qq_engine.py` / `qq_mcp.py` now compose S&box as a first-class engine alongside Unity, Godot, and Unreal
  - S&box compile/test/runtime bridge scripts and capabilities
  - bundled S&box editor bridge runtime under `engines/sbox/Editor/QQ/QQSboxEditorBridge.cs`
- modular install planning and a guided onboarding flow:
  - `install.sh --wizard`
  - preset installs: `quickstart`, `daily`, `stabilize`
  - physical install modules resolved from engine/host/profile instead of copying the whole runtime by default

### Changed
- `install.sh` now installs only the selected runtime modules for the current engine/host surface
- `qq-doctor` now reports installed-vs-expected modules and module drift
- `qq-policy-check`, `qq-project-state`, `qq-compile.sh`, `qq-test.sh`, and `qq_mcp.py` now resolve S&box-aware runtime/test flows

### Fixed
- install-time `qq.yaml install` settings now merge correctly with local overrides instead of being reset by missing local config
- `git-pre-push` is no longer installed implicitly just because a heavier workflow profile is selected; it is now explicit opt-in
- `install.sync: true` now actually prunes stale managed runtime files during reinstall

## [1.8.0] — 2026-03-31

### Added
- first-party Unreal runtime parity:
  - `qq_engine.py` / `qq_mcp.py` now compose Unreal as a first-class engine alongside Unity and Godot
  - Unreal compile/test/runtime bridge scripts and capabilities
  - bundled Unreal editor bridge bootstrap under `engines/unreal/python/qq_unreal_bridge.py`

### Changed
- `install.sh` now detects Unreal projects, enables required Unreal project plugins, installs support scripts, and wires the built-in live editor bridge
- `qq-doctor`, `qq-policy-check`, `qq-compile.sh`, and `qq-test.sh` now resolve Unreal-aware runtime/test flows
- trust-level MCP filtering now applies consistently to Unreal raw tools as well as Unity/Godot

### Fixed
- engine-generic MCP composition now keeps trust-level raw-command restrictions intact while adding Unreal runtime delegates
- regression coverage now exercises Unreal provider resolution, compile/test routing, and install-time project bootstrap
## [1.7.0] — 2026-03-31

### Added
- first-party Godot runtime parity:
  - `qq_engine.py` engine registry and engine-aware defaults
  - `qq_mcp.py` as the engine-generic project-local MCP entrypoint
  - Godot compile/test/runtime bridge scripts and capabilities
  - bundled Godot editor bridge addon under `engines/godot/addons/qq_editor_bridge`

### Changed
- `qq-project-state` now uses an engine-agnostic runtime/test status model (`changed_runtime_files`, `changed_test_files`) instead of Unity-only code-change fields
- `install.sh`, `qq-compile.sh`, `qq-test.sh`, and auto-compile hooks now route through the active engine instead of assuming Unity-only project semantics
- project-local Claude/Codex host setup now resolves the correct engine bridge for Unity or Godot projects

### Fixed
- managed worktree and controller tests now declare the target engine explicitly, so runtime verification stays correct in engine-agnostic fixtures

## [1.6.0] — 2026-03-31

### Added
- `/qq:add-tests` as an explicit test-authoring skill for targeted EditMode, PlayMode, and regression coverage

### Changed
- `feature`, `fix`, and `hardening` controller flows now route compile-green code changes to `/qq:add-tests` before `/qq:test` when fresh coverage is still missing
- `workflow-basic` and `lightweight` now include explicit test authoring as part of the default runtime loop
- docs, install output, benchmark suites, and marketplace metadata now reflect the new 23-skill surface

### Fixed
- `qq-worktree cleanup` now prunes copied local runtime artifacts before removal, so consumer linked worktrees no longer get stuck on untracked `qq.yaml` / `scripts/` noise during closeout

## [1.5.1] — 2026-03-31

### Fixed
- `/qq:changes` now persists a meaningful local-change snapshot, so prototype flows can advance from `/qq:changes` to `/qq:commit-push` without forcing the push path
- changes summaries now invalidate immediately after newer local edits, even when the follow-up edit lands within the same filesystem timestamp bucket
- `qq-worktree closeout` now deletes the remote linked branch before removing the managed worktree directory, so the normal closeout path no longer leaves behind a stale remote worktree branch
- runtime change detection now ignores `.qq` and `qq.yaml` config/runtime noise when deciding whether controller flows should treat the project as having unfinished user work

## [1.5.0] — 2026-03-31

### Added
- `qq.yaml` as the single supported shared project config surface, with `.qq/local.yaml` as the per-worktree override
- `qq-config.py` / `qq_internal_config.py` as the new config resolver and CLI entrypoint
- built-in profiles: `lightweight`, `core`, `feature`, `hardening`
- `qq-context-capsule.py consume` as a host-neutral capsule handoff/consume API
- `qq_internal_git.py` for correct git inspection in bare+worktree repo layouts
- qq benchmark suites and reference solver scaffolding:
  - `docs/evals/qq-bench-*.json`
  - `scripts/eval/reference_solver.py`

### Changed
- removed legacy `qq-policy.json` / `.qq/local-policy.json` compatibility; qq now only reads `qq.yaml` and `.qq/local.yaml`
- `qq-project-state`, `qq-doctor`, hooks, install flow, and worktree runtime copying now all resolve through the new config/runtime layer
- `qq-codex-exec.py` now consumes Context Capsules through the host-neutral `consume` API instead of duplicating resume logic
- `qq-worktree create` now copies project-local runtime files required by consumer installs (`qq.yaml`, `.mcp.json`, `.claude/settings.local.json`, `scripts/`, and related handoff artifacts)

### Fixed
- bare+worktree repos now report dirty state, branch state, and controller context correctly
- copied runtime artifacts in managed worktrees no longer block merge-back / cleanup as false-positive dirt
- real Codex E2E now passes on both the root `project_pirate_demo` project and a seeded qq-managed linked worktree

## [1.4.0] — 2026-03-31

### Added
- `qq-worktree.py seed-library` to seed or refresh a managed worktree `Library` from its source worktree

### Changed
- `qq-worktree create` now seeds the source worktree `Library` into the linked worktree when one is available
- `unity-test.sh` now auto-seeds a missing managed-worktree `Library` before falling back to batch mode
- `qq-project-state` and `qq-doctor` now expose managed-worktree Library readiness (`sourceLibraryExists`, `localLibraryExists`, `librarySeedState`, `librarySeedStrategy`)

### Fixed
- real Claude `/qq:test editmode` now succeeds in a qq-managed linked worktree with a seeded `Library`
- real Codex `unity_run_tests editmode` now succeeds in the same qq-managed linked worktree

## [1.3.0] — 2026-03-31

### Added
- `qq-codex-mcp.py` for project-local Codex MCP registration
- `qq-codex-exec.py` for thin Codex execution against the current project/worktree
- qq-managed worktree `closeout` flow with source-branch publication and cleanup
- Dev Container support for repository-side development:
  - `.devcontainer/`
  - `scripts/docker-dev.sh`
  - `docs/containerization.md`
  - `docs/developer-workflow.md`

### Changed
- `qq-worktree create` now copies source compile/test baseline state into linked worktrees so doc-only work can close out without re-running local verification unnecessarily
- `qq-doctor` now reports Codex registration, built-in MCP host verification, and richer managed-worktree publication state
- collaboration E2E docs now reflect real Claude and Codex host coverage on `project_pirate_demo`

### Fixed
- built-in `tykit_mcp` now speaks both framed MCP and Claude's JSONL MCP initialize flow
- real Claude `/qq:test editmode` succeeds on `project_pirate_demo`
- real Codex can execute `unity_run_tests` on `project_pirate_demo`
- `install.sh` now repins existing `com.tyk.tykit` dependencies to the current tested release instead of silently leaving older git revisions in place
- managed-worktree closeout no longer depends on manually adding the source worktree to Codex writable scope

## [1.2.2] — 2026-03-30

### Changed
- `install.sh` now merges a baseline Claude local allowlist for qq state/doctor/compile/test commands in `.claude/settings.local.json`

### Fixed
- fresh consumer installs no longer hit the first `/qq:go` permission wall just to run `qq-project-state.py`

## [1.2.1] — 2026-03-30

### Changed
- `/qq:go` now has stricter controller rules in the shipped plugin:
  - read `qq-project-state.py` before any git/branch heuristics
  - avoid repo-audit style branch summaries by default
  - answer with the current mode/profile/next step first

### Fixed
- real Claude `/qq:go` runs are steered away from expensive fallback repo scans when structured project state is already available

## [1.2.0] — 2026-03-30

### Added
- `docs/todo.md` to track user-facing follow-up issues discovered during E2E validation

### Changed
- `/qq:go` is now explicitly project-state-first and mode-aware in the shipped plugin, instead of relying on conversation/git heuristics as the default controller
- controller artifact routing now treats repo-global design docs as background context unless they match the current task focus or active changes
- compile/test freshness now uses sub-second run timestamps so freshly verified work is not immediately marked stale

### Fixed
- prototype work is no longer incorrectly dragged into `/qq:plan` just because unrelated design docs exist elsewhere in the repo
- stale test results are invalidated after newer local `.cs` changes, and fresh compile runs remain valid in the same second they complete

## [1.1.0] — 2026-03-30

### Added
- Built-in project-local `tykit_mcp` bridge with `unity_*` MCP tools and capability metadata
- `./scripts/qq-doctor.sh` to inspect direct-path vs MCP routing in consumer Unity projects
- Agent integration and consumer rollout docs for validating the published install path

### Changed
- `install.sh` now copies the built-in bridge into the consumer project, wires `.mcp.json`, and pins `tykit` to the tested published revision
- qq now prefers the built-in `tykit_mcp` bridge before third-party Unity MCP backends when MCP is available
- README installation docs now describe the default built-in bridge flow for consumer projects

### Fixed
- Unity test runs now stop Play Mode first and prevent overlapping test executions
- Missing Unity meta files for the mirrored `tykit` package are restored
- `qq-doctor.sh` is shipped as an executable script

## [1.0.0] — 2026-03-28

### Added
- 22 skills (`/qq:*`) covering the full dev lifecycle
- `/qq:go` — lifecycle-aware routing (detect stage, suggest next step, `--auto` mode)
- `/qq:design` — write game design documents from ideas or drafts
- `/qq:plan` — generate technical implementation plans from design docs
- `/qq:execute` — smart implementation with adaptive execution strategy
- `/qq:best-practice` — 18-rule Unity best-practice check
- `/qq:claude-code-review` / `/qq:claude-plan-review` — deep review using Claude subagents
- `/qq:codex-code-review` / `/qq:codex-plan-review` — cross-model review (Claude + Codex)
- `/qq:test` — EditMode + PlayMode tests with runtime error checking
- `/qq:brief` — architecture diff + PR checklist (merged from brief-arch + brief-checklist)
- `/qq:full-brief` — run brief + timeline in parallel (4 docs total)
- `/qq:timeline` — commit history timeline with phase analysis
- `/qq:deps` — `.asmdef` dependency graph + matrix + health check
- `/qq:doc-tidy` — scan repo docs, analyze organization, suggest cleanup
- `/qq:doc-drift` — compare design docs vs code, find inconsistencies
- `/qq:grandma` — explain any concept using everyday analogies
- `/qq:explain` — explain module architecture in plain language
- `/qq:research` — search open-source solutions for current problem
- Auto-compilation hook — edit a `.cs` file, compilation runs automatically
- Smart compilation stack: tykit (HTTP) → Editor trigger → batch mode fallback
- tykit — HTTP server inside Unity Editor for AI agent control
- Codex Review Gate — blocks edits while review verification is pending
- Skill review enforcement — Stop hook blocks session end until `/qq:self-review` runs
- Smart handoff between skills with `--auto` mode for full pipeline execution
- Multi-language README (English, 中文, 日本語, 한국어)
- Plugin marketplace SEO optimization
- `test.sh` — self-test script (shellcheck + JSON + structural checks)
- GitHub Actions CI workflow
- Issue templates (bug report + feature request)

### Fixed
- `install.sh` now copies `scripts/hooks/` subdirectory
- `install.sh` output uses current skill names (`/qq:test`, `/qq:commit-push`)
- Duplicate scripts in tykit `Scripts~/` replaced with symlinks
- Review Gate documentation accuracy (`.cs` and `Docs/*.md`, not "all edits")
- Git added to Prerequisites (hard dependency)
- Claude-only review skills now read `AGENTS.md` for architecture rules
- `claude-plan-review` fallback glob excludes generated review artifacts

## [0.1.0] — 2026-03-27

### Added
- Initial release — Unity Agent Harness for Claude Code
- Core skills: test, st, commit-push, codex-code-review, codex-plan-review, code-review, self-review, explain, research, changes
- Hook system: auto-compile, skill review enforcement
- tykit UPM package
- `install.sh` installer
- Claude Code Plugin format (plugin.json, marketplace.json)
