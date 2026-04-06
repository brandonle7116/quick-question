<p align="center">
  <img src="logo.png" alt="quick-question" width="200">
</p>

<h1 align="center">quick-question</h1>

<p align="center">
  <strong>The control plane for game-dev agents.</strong><br>
  Close the loop — compile, test, review, and ship — verified inside Unity, Godot, Unreal, and S&box.<br>
  <a href="https://docs.anthropic.com/en/docs/claude-code">Claude Code</a>-first.
  Open to any agent via HTTP and MCP.
</p>

<p align="center">
  <a href="https://github.com/tykisgod/quick-question/actions/workflows/validate.yml"><img src="https://github.com/tykisgod/quick-question/actions/workflows/validate.yml/badge.svg" alt="CI"></a>
  <img src="https://img.shields.io/badge/version-v1.16.7-blue" alt="Version">
  <a href="https://github.com/tykisgod/quick-question/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%20%7C%20Windows-blue" alt="Platform">
</p>

<table align="center" cellspacing="0" cellpadding="16" border="0">
  <tr>
    <td align="center" border="0">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/unity-light.svg">
        <img src="docs/images/unity-dark.svg" width="56" alt="Unity">
      </picture>
      <br>
      <a href="https://unity.com">Unity</a>
    </td>
    <td align="center" border="0">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/godot-light.svg">
        <img src="docs/images/godot-dark.svg" width="56" alt="Godot">
      </picture>
      <br>
      <a href="https://godotengine.org">Godot</a>
    </td>
    <td align="center" border="0">
      <picture>
        <source media="(prefers-color-scheme: dark)" srcset="docs/images/unreal-light.svg">
        <img src="docs/images/unreal-dark.svg" width="56" alt="Unreal">
      </picture>
      <br>
      <a href="https://www.unrealengine.com">Unreal</a>
    </td>
    <td align="center" border="0">
      <img src="docs/images/sbox.svg" width="56" alt="S&amp;box">
      <br>
      <a href="https://github.com/Facepunch/sbox-public">S&amp;box</a>
    </td>
  </tr>
</table>

<p align="center">
  English |
  <a href="docs/zh-CN/README.md">中文</a> |
  <a href="docs/ja/README.md">日本語</a> |
  <a href="docs/ko/README.md">한국어</a>
</p>

---

## Why qq

AI agents can write code. They cannot, by default, tell you whether the code compiles, the tests pass, the behavior is right, or whether they just produced 500 lines of plausible-looking nonsense. In a game project — where "running" means the editor opens, the scene loads, and frame N+1 looks like you wanted — that gap is the entire problem.

quick-question is the runtime layer that closes it. Four work modes — `prototype`, `feature`, `fix`, `hardening` — are first-class state, not flavor text. A prototype keeps the compile green and stays playable; a hardening pass forces tests, review, and document/code consistency before shipping. The artifact-driven controller (`/qq:go`) reads `.qq/state/*.json` and your `work_mode`, then recommends the concrete next skill — instead of guessing from chat history.

The runtime is engine-symmetric and agent-agnostic. tykit gives Unity the deepest integration (an in-process HTTP server, millisecond response). Godot, Unreal, and S&box are at runtime parity through Python bridges. [Claude Code](https://docs.anthropic.com/en/docs/claude-code) gets 26 skills, auto-compile hooks, and review gates. Codex, Cursor, Continue, and any MCP-compatible host get the same underlying runtime through HTTP and MCP. Structured state in `.qq/` is plain JSON on disk — readable by any agent, across sessions.

The methodology is grounded in the document-first approach described in [*AI Coding in Practice: An Indie Developer's Document-First Approach*](https://tyksworks.com/posts/ai-coding-workflow-en/).

## How it works

```
Edit .cs/.gd/.cpp file
  → Hook auto-compiles via qq-compile.sh
    → Result + error context written to .qq/state/
      → /qq:go reads state, recommends next skill
        → Skill runs, writes new state
          → Loop
```

Four layers cooperate:

- **Hooks** fire on every Claude Code tool call. PostToolUse compiles after `Edit`/`Write` on engine source files via `qq-compile.sh` (the multi-engine dispatcher). PreToolUse blocks edits during review verification, or after a red compile, until the relevant gate clears. Stop blocks session end if skills were modified without `/qq:self-review`. All gate files are keyed by `$PPID` for session isolation.
- **Controller** — `/qq:go` reads `.qq/state/*.json`, recent run records, your `work_mode`, and the active `policy_profile`, then routes to the next skill. It is a controller, not an implementation engine — it only falls back to context heuristics when state is ambiguous.
- **Engine bridges** — tykit (Unity in-process HTTP), `godot_bridge.py`, `unreal_bridge.py`, `sbox_bridge.py`. Compile, test, console, find / inspect — verified execution, not blind file writes.
- **Runtime data** — `.qq/runs/*.json` (raw run logs), `.qq/state/*.json` (latest compile / test state), `.qq/state/session-decisions.json` (cross-skill decision journal), `.qq/telemetry/`. Plain JSON, readable by any agent across sessions.

For code review, two symmetric modes share the same verification loop: **Codex review** (`code-review.sh` → `codex exec`, cross-model) and **Claude review** (`claude-review.sh` → `claude -p`, single-model). Each produces findings, then independent verification subagents check every finding against actual source and flag over-engineering — up to 5 rounds until clean. The unified review gate (`scripts/hooks/review-gate.sh`) blocks edits until all verification subagents complete (three-field format: `<ts>:<completed>:<expected>`). MCP exposes one-shot `qq_code_review` and `qq_plan_review` tools for non-Claude hosts.

See [Architecture Overview](docs/dev/architecture/overview.md), [Hook System](docs/en/hooks.md), [Cross-Model Review](docs/en/cross-model-review.md), and [Worktrees](docs/en/worktrees.md) for layer-by-layer detail.

## Engines

| Engine | Compile | Test | Editor control | Bridge |
|--------|---------|------|----------------|--------|
| **Unity 2021.3+** | tykit / editor trigger / batch | EditMode + PlayMode | tykit HTTP server | `tykit_bridge.py` |
| **Godot 4.x** | GDScript check via headless editor | GUT / GdUnit4 | Editor addon | `godot_bridge.py` |
| **Unreal 5.x** | UnrealBuildTool + editor commandlet | Automation tests | Editor command (Python) | `unreal_bridge.py` |
| **S&box** | `dotnet build` | Runtime tests | Editor bridge | `sbox_bridge.py` |

Unity has the deepest integration via tykit (in-process HTTP, millisecond response). Godot, Unreal, and S&box are at runtime parity — compile, test, editor control, and structured run records all work — with active development continuing.

## Install

### Requirements

- macOS or Windows (Windows needs [Git for Windows](https://gitforwindows.org/) for bash + core utilities)
- Engine: Unity 2021.3+ / Godot 4.x / Unreal 5.x / S&box
- `python3` (required), `jq` (recommended — hook scripts fall back to python3 when jq is missing)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) for the full skill + hook experience
- [Codex CLI](https://github.com/openai/codex) (optional — enables cross-model review)

### Install the runtime

All agents share the same runtime install. It auto-detects your engine and writes scripts, bridges, and config into the project.

```bash
git clone https://github.com/tykisgod/quick-question.git /tmp/qq
/tmp/qq/install.sh /path/to/your-project          # auto-detect engine
/tmp/qq/install.sh --wizard /path/to/your-project  # interactive wizard
/tmp/qq/install.sh --preset quickstart /path/to/your-project  # one-shot preset
rm -rf /tmp/qq
```

Available presets: `quickstart` (minimal), `daily` (recommended), `stabilize` (full checks for release prep). Use `--profile`, `--modules`, `--without` for fine-grained control.

### Connect your agent

| Agent | Setup | What you get |
|-------|-------|--------------|
| **Claude Code** | `/plugin marketplace add tykisgod/quick-question`<br>`/plugin install qq@quick-question-marketplace` | All 26 `/qq:*` slash commands, auto-compile hooks, review gates, MCP — full experience |
| **Codex CLI** | `python3 ./scripts/qq-codex-mcp.py install --pretty` | Project-local MCP bridge; use `qq-codex-exec.py` to pin the working root |
| **Cursor / Continue / other MCP hosts** | Add `qq` to `mcpServers` in your host config: `command: python3`, `args: ["./scripts/qq_mcp.py"]`, `cwd: /path/to/project` | Compile, test, console, editor control as MCP tools — see [`docs/en/tykit-mcp.md`](docs/en/tykit-mcp.md) |
| **Any HTTP client** | Read port from `Temp/tykit.json`, POST JSON to `localhost:$PORT/` | Direct tykit access — see [`docs/en/tykit-api.md`](docs/en/tykit-api.md) |

For non-Unity engines, call the bridge scripts directly (e.g. `python3 ./scripts/godot_bridge.py compile`).

## Quick start

```bash
/qq:go                                       # detect phase, recommend next step
/qq:design "inventory with drag-and-drop"    # write a design doc
/qq:plan                                     # generate implementation plan
/qq:execute                                  # implement with auto-compile on every edit
/qq:test                                     # run tests, surface runtime errors
/qq:commit-push                              # batch commit and push
```

`/qq:go` adapts to your `work_mode`. In `prototype` it stays light (compile green, stay playable). In `hardening` it forces tests, review, and document/code consistency before shipping. See [Getting Started](docs/en/getting-started.md) for walkthroughs.

## Commands

### Workflow

| Command | Description |
|---------|-------------|
| `/qq:go` | Detect workflow stage, recommend next step |
| `/qq:bootstrap` | Decompose a game vision into epics, orchestrate full pipeline for each |
| `/qq:design` | Write a game design document |
| `/qq:plan` | Generate technical implementation plan |
| `/qq:execute` | Smart implementation with auto-compile verification |

### Testing

| Command | Description |
|---------|-------------|
| `/qq:add-tests` | Author EditMode, PlayMode, or regression tests |
| `/qq:test` | Run tests and check for runtime errors |

### Code review

| Command | Description |
|---------|-------------|
| `/qq:codex-code-review` | Cross-model: Codex reviews, Claude verifies (max 5 rounds) |
| `/qq:codex-plan-review` | Cross-model plan / design review |
| `/qq:claude-code-review` | Claude-only deep code review with auto-fix loop |
| `/qq:claude-plan-review` | Claude-only plan / design review |
| `/qq:best-practice` | Quick scan for anti-patterns and performance issues |
| `/qq:self-review` | Review recent skill / config changes |
| `/qq:post-design-review` | Review a design doc from implementer's perspective — check consistency, buildability, codebase gaps |

### Analysis

| Command | Description |
|---------|-------------|
| `/qq:brief` | Architecture diagram + PR review checklist vs base branch |
| `/qq:timeline` | Commit history grouped into semantic phases |
| `/qq:full-brief` | Run brief + timeline in parallel |
| `/qq:deps` | Analyze `.asmdef` dependencies (Mermaid graph + matrix) |
| `/qq:doc-drift` | Compare design docs against actual code |

### Utilities

| Command | Description |
|---------|-------------|
| `/qq:commit-push` | Batch commit and push |
| `/qq:explain` | Explain module architecture in plain language |
| `/qq:grandma` | Explain concepts using everyday analogies |
| `/qq:tech-research` | Search open-source communities for technical solutions |
| `/qq:design-research` | Search for game design references and patterns |
| `/qq:changes` | Summarize all changes from the current session |
| `/qq:doc-tidy` | Scan and recommend documentation cleanup |

## Work modes

| Mode | When | Must do | Usually skip |
|------|------|---------|--------------|
| `prototype` | New mechanic, greybox, fun check | Keep compile green, stay playable | Formal docs, full review |
| `feature` | Building a retainable system | Design, plan, compile, targeted tests | Full regression on every change |
| `fix` | Bug fix, regression repair | Reproduce first, smallest safe fix | Large refactors |
| `hardening` | Risky refactor, release prep | Tests, review, doc / code consistency | Prototype shortcuts |

Set the shared default in `qq.yaml`. Override per-worktree in `.qq/local.yaml`. `work_mode` and `policy_profile` are independent: the first answers "what kind of task is this?", the second answers "how much verification does this project expect?". A prototype and a hardening pass can share the same policy profile, or not. See [Configuration](docs/en/configuration.md) for the full reference.

## Configuration

Three files control qq's behavior in your project:

- **`qq.yaml`** — runtime config: `work_mode`, `policy_profile`, `trust_level`, module selection. Built-in profiles: `lightweight`, `core`, `feature`, `hardening`. See [`templates/qq.yaml.example`](templates/qq.yaml.example).
- **`CLAUDE.md`** — coding standards and compile verification rules scoped to your project. See [`templates/CLAUDE.md.example`](templates/CLAUDE.md.example).
- **`AGENTS.md`** — architecture rules and review criteria for subagent workflows. See [`templates/AGENTS.md.example`](templates/AGENTS.md.example).

## tykit

tykit is a lightweight HTTP server inside the Unity Editor process — zero setup, no external dependencies, millisecond response. It exposes compile, test, play / stop, console, and inspector commands over localhost. Port is derived from your project path hash and stored in `Temp/tykit.json`.

```bash
PORT=$(python3 -c "import json; print(json.load(open('Temp/tykit.json'))['port'])")
curl -s -X POST http://localhost:$PORT/ -d '{"command":"compile"}' -H 'Content-Type: application/json'
curl -s -X POST http://localhost:$PORT/ -d '{"command":"run-tests","args":{"mode":"editmode"}}' -H 'Content-Type: application/json'
```

tykit also works standalone, without qq — add the [UPM package](packages/com.tyk.tykit/) to any Unity project. Any agent that can send HTTP can use it directly. The MCP bridge (`tykit_mcp.py`) wraps it for MCP-compatible hosts. See [`docs/en/tykit-api.md`](docs/en/tykit-api.md) and [`docs/en/tykit-mcp.md`](docs/en/tykit-mcp.md).

## FAQ

**Does this work on Windows?**
Yes. Requires [Git for Windows](https://gitforwindows.org/) for bash, curl, and core utilities. The 1.15.x and 1.16.x releases hardened Windows support — LF line endings via `.gitattributes`, path normalization, Python Store-alias detection, and a jq fallback in hook scripts.

**Do I need Codex CLI?**
No. Codex CLI enables cross-model review (`/qq:codex-code-review`), but `/qq:claude-code-review` works without it.

**Can I use this with Cursor / Copilot / Codex / other agents?**
Yes. The runtime layer (tykit, engine bridges, `.qq/` state, scripts) is agent-agnostic — anything that can send HTTP or speak MCP can use it. The 26 `/qq:*` slash commands and auto-compile hooks are Claude Code-specific, but the underlying scripts they call are ordinary shell and Python. See [`docs/dev/agent-integration.md`](docs/dev/agent-integration.md).

**What happens when compilation fails?**
The auto-compile hook captures the error output and surfaces it in the conversation. The compile gate then blocks subsequent edits to engine source files until the compile recovers. The agent reads the errors, fixes the code, and the hook compiles again automatically.

**Can I use tykit without quick-question?**
Yes. Add the UPM package from [`packages/com.tyk.tykit/`](packages/com.tyk.tykit/). See the [tykit README](packages/com.tyk.tykit/README.md).

**Which Unity versions are supported?**
tykit requires Unity 2021.3+. MCP alternatives: [mcp-unity](https://github.com/nicoboss/mcp-unity) requires Unity 6+; [Unity-MCP](https://github.com/mpiechot/Unity-MCP) has no version requirement.

---

> ⚠️ The Chinese section below temporarily lags behind the English. The English content above is canonical until the Chinese pass lands.

<h2 align="center">中文</h2>

## qq 是什么

qq 是一个运行时层，让 AI agent 深度感知游戏开发周期。它不会把所有任务一视同仁——qq 知道你是在验证新玩法原型、构建生产功能、修复回归 bug，还是在发版前加固——并据此调整流程强度。artifact 驱动的控制器从 `.qq/` 读取结构化项目状态、最近的运行记录和你配置的 `work_mode`，然后推荐具体的下一步。

运行时核心是 agent 无关的。引擎桥接（Unity 的 tykit、Godot/Unreal/S&box 的编辑器桥接）通过 HTTP 暴露编译、测试和编辑器控制。MCP 桥接（`tykit_mcp.py`）让 Codex、Cursor、Continue 及任何 MCP 兼容宿主都能使用这些能力。`.qq/` 中的结构化状态是磁盘上的纯 JSON——任何 agent 都能读取。

[Claude Code](https://docs.anthropic.com/en/docs/claude-code) 拥有最深度的集成：26 个 slash 命令（从 `/qq:go` 到 `/qq:commit-push`）、每次代码编辑自动编译的 hook、跨模型验证期间阻止编辑的审阅门，以及完整编排层。其他 agent 通过 HTTP 和 MCP 访问相同的底层运行时——直接调用脚本和桥接即可。

方法论基于 [AI 编程实践：独立开发者的文档驱动方法](https://tyksworks.com/posts/ai-coding-workflow-zh/)。

## 功能亮点

- **`/qq:go` — 生命周期感知路由** — 读取项目状态、`work_mode` 和运行历史，为当前阶段推荐正确的下一步
- **自动编译** — hook 驱动，每次代码编辑自动触发；支持 `.cs`（Unity/S&box）、`.gd`（Godot）和 C++（Unreal）
- **测试流水线** — Unity 的 EditMode + PlayMode、Godot 的 GUT/GdUnit4、Unreal 的 Automation、S&box 的运行时测试，全部结构化通过/失败报告
- **结构化代码审阅** — 跨模型（Codex 审阅，Claude 验证）或单模型（Claude 审阅，独立 Claude 子 agent 验证）；无论哪种，每条发现都经过对照源码验证后才应用修复
- **编辑器控制** — tykit HTTP 服务器（Unity），加上 Godot、Unreal、S&box 的 Python 桥接；任何 agent 可通过 HTTP 或 MCP 访问
- **工作模式** — `prototype`、`feature`、`fix`、`hardening` — 每种模式施加适当的流程强度，原型保持轻量，发版获得完整验证
- **运行时数据** — `.qq/` 中的结构化状态提供跨会话的循环连续性，并为控制器提供数据
- **模块化安装** — 向导模式自动检测引擎，一键预设（`quickstart`/`daily`/`stabilize`），按模块细粒度控制

## 支持的引擎

| 引擎 | 编译 | 测试 | 编辑器控制 | 桥接 |
|------|------|------|-----------|------|
| **Unity 2021.3+** | tykit / editor trigger / batch | EditMode + PlayMode | tykit HTTP server | `tykit_bridge.py` |
| **Godot 4.x** | GDScript check via headless editor | GUT / GdUnit4 | Editor addon | `godot_bridge.py` |
| **Unreal 5.x** | UnrealBuildTool + editor commandlet | Automation tests | Editor command (Python) | `unreal_bridge.py` |
| **S&box** | `dotnet build` | Runtime tests | Editor bridge | `sbox_bridge.py` |

Unity 集成最深（tykit 提供进程内 HTTP 控制，毫秒级响应）。Godot、Unreal 和 S&box 已达到运行时对等——编译、测试、编辑器控制和结构化运行记录均可用——持续开发中。

## 安装

### 前置条件

- macOS 或 Windows（需要 [Git for Windows](https://gitforwindows.org/)；Windows 支持为预览版）
- 引擎：Unity 2021.3+ / Godot 4.x / Unreal 5.x / S&box
- `curl`、`python3`、`jq`
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) *（完整 skill + hook 体验）*
- [Codex CLI](https://github.com/openai/codex) *（可选——启用跨模型审阅）*

### 安装运行时

所有 agent 共享同一套运行时安装——自动检测引擎，将脚本、桥接和配置写入你的项目。

```bash
git clone https://github.com/tykisgod/quick-question.git /tmp/qq
/tmp/qq/install.sh /path/to/your-project          # 自动检测引擎
/tmp/qq/install.sh --wizard /path/to/your-project  # 交互式向导
/tmp/qq/install.sh --preset quickstart /path/to/your-project  # 一键预设
rm -rf /tmp/qq
```

可用预设：`quickstart`（最轻量）、`daily`（推荐）、`stabilize`（发版前完整检查）。细粒度控制参见 `--profile`、`--modules` 和 `--without`。

### 连接你的 agent

<details>
<summary><b>Claude Code</b> — 完整体验（skill + hook + MCP）</summary>

```
/plugin marketplace add tykisgod/quick-question
/plugin install qq@quick-question-marketplace
```

提供 24 个 `/qq:*` slash 命令、每次代码编辑自动编译 hook、审阅门和完整编排层。安装器已自动配置 `.claude/settings.local.json` 和 `.mcp.json`。
</details>

<details>
<summary><b>Codex CLI</b> — 通过 MCP 使用运行时</summary>

```bash
cd /path/to/your-project
python3 ./scripts/qq-codex-mcp.py install --pretty
```

向 Codex 注册项目本地 MCP 桥接。之后 Codex 可调用 `unity_compile`、`unity_run_tests`、`unity_console` 等引擎工具。用薄包装器固定工作根目录：

```bash
python3 ./scripts/qq-codex-exec.py "compile and run editmode tests"
```
</details>

<details>
<summary><b>Cursor / Continue / 其他 MCP 宿主</b> — 通过 MCP 使用运行时</summary>

将 MCP 桥接添加到 agent 的 MCP 配置中（具体文件因宿主而异）：

```json
{
  "mcpServers": {
    "qq": {
      "command": "python3",
      "args": ["./scripts/qq_mcp.py"],
      "cwd": "/path/to/your-project"
    }
  }
}
```

将编译、测试、控制台和编辑器控制暴露为 MCP tool。参见 [tykit MCP 桥接](docs/zh-CN/tykit-mcp.md)了解 profile 和 tool 详情。
</details>

<details>
<summary><b>任何 agent / 原始 HTTP</b> — 直接访问 tykit</summary>

不需要 MCP。tykit 是一个普通 HTTP 服务器。打开 Unity 后自动启动：

```bash
PORT=$(python3 -c "import json; print(json.load(open('Temp/tykit.json'))['port'])")
curl -s -X POST http://localhost:$PORT/ -d '{"command":"compile"}' -H 'Content-Type: application/json'
```

参见 [tykit API 参考](docs/zh-CN/tykit-api.md)了解完整命令。非 Unity 引擎直接调用桥接脚本（如 `python3 ./scripts/godot_bridge.py compile`）。
</details>

安装后打开编辑器。Unity 中 tykit 自动启动。其他引擎请按安装脚本输出的提示操作。

## 快速开始

```bash
# 让 qq 判断你在哪个阶段
/qq:go

# 设计一个功能
/qq:design "inventory system with drag-and-drop"

# 生成实现计划
/qq:plan

# 执行计划——每次编辑自动编译
/qq:execute

# 运行测试
/qq:test
```

qq 根据工作模式调整流程强度。在 `prototype` 模式下保持轻量——编译绿灯、可运行、快速推进。在 `hardening` 模式下强制测试和审阅后才发布。详细场景演练参见[快速上手](docs/zh-CN/getting-started.md)。

## 命令

### 工作流

| 命令 | 描述 |
|------|------|
| `/qq:go` | 检测工作流阶段，推荐下一步 |
| `/qq:bootstrap` | 从游戏愿景分解成 epics，编排完整 pipeline |
| `/qq:design` | 编写游戏设计文档 |
| `/qq:plan` | 生成技术实现计划 |
| `/qq:execute` | 智能实现，自动编译验证 |

### 测试

| 命令 | 描述 |
|------|------|
| `/qq:add-tests` | 编写 EditMode、PlayMode 或回归测试 |
| `/qq:test` | 运行测试并检查运行时错误 |

### 代码审阅

| 命令 | 描述 |
|------|------|
| `/qq:codex-code-review` | 跨模型审阅：Codex 审阅，Claude 验证（最多 5 轮） |
| `/qq:codex-plan-review` | 跨模型计划/设计审阅 |
| `/qq:claude-code-review` | Claude 深度代码审阅，自动修复循环 |
| `/qq:claude-plan-review` | Claude 计划/设计审阅 |
| `/qq:best-practice` | 快速扫描反模式和性能问题 |
| `/qq:self-review` | 审阅最近的 skill/配置变更 |
| `/qq:post-design-review` | 从实现者视角审查设计文档——检查自洽性、可实现性、代码库差距 |

### 分析

| 命令 | 描述 |
|------|------|
| `/qq:brief` | 架构图 + PR 审阅清单（对比基准分支） |
| `/qq:timeline` | 提交历史按语义阶段分组 |
| `/qq:full-brief` | 并行运行 brief + timeline |
| `/qq:deps` | 分析 `.asmdef` 依赖关系（Mermaid 图 + 矩阵） |
| `/qq:doc-drift` | 对比设计文档与实际代码，找出不一致 |

### 工具

| 命令 | 描述 |
|------|------|
| `/qq:commit-push` | 批量提交并推送 |
| `/qq:explain` | 用通俗语言解释模块架构 |
| `/qq:grandma` | 用日常类比解释概念 |
| `/qq:tech-research` | 搜索开源社区寻找技术解决方案 |
| `/qq:design-research` | 搜索游戏设计参考和设计模式 |
| `/qq:changes` | 汇总当前会话的所有变更 |
| `/qq:doc-tidy` | 扫描并建议文档清理 |

## 工作模式

| 模式 | 适用场景 | 必须做 | 通常跳过 |
|------|---------|--------|---------|
| `prototype` | 新玩法、灰盒、fun check | 保持编译绿灯，可运行 | 正式文档，完整审阅 |
| `feature` | 构建可保留的系统 | 设计、计划、编译、定向测试 | 每次改动跑完整回归 |
| `fix` | bug 修复、回归修复 | 先复现，最小安全修复 | 大规模重构 |
| `hardening` | 风险重构、发版前 | 测试、审阅、文档/代码一致性 | 原型快捷方式 |

在 `qq.yaml` 中设置共享默认值。在 `.qq/local.yaml` 中按 worktree 覆盖。输入 `/qq:go` 开始——它读取你的模式并调整推荐。

`work_mode` 和 `policy_profile` 是两个独立旋钮。`work_mode` 回答"这是什么类型的任务？"，`policy_profile` 回答"这个项目需要多少验证？"原型和加固阶段可以共享同一个 policy profile，也可以不——它们是独立的。完整参考参见[配置参考](docs/zh-CN/configuration.md)。

## 工作原理

qq 作为四层运行时运行：

```
Edit .cs/.gd file
  → Hook auto-compiles (tykit / editor trigger / batch mode)
    → Result written to .qq/state/
      → /qq:go reads state, recommends next step
```

**Hooks** 在工具使用时自动触发——代码编辑后编译、追踪 skill 修改、审阅验证期间阻止编辑。**`/qq:go`** 是控制器：读取项目状态（`work_mode`、`policy_profile`、最近的编译/测试结果）并路由到正确的 skill。**引擎桥接**提供经过验证的进程内执行，而非盲目文件写入。**运行时数据**在 `.qq/` 中为每一层提供共享的结构化项目健康视图。

代码审阅提供两种对称模式：Codex 审阅（`code-review.sh` → `codex exec`）和 Claude 审阅（`claude-review.sh` → `claude -p`）。两者都产出发现，然后独立的验证子 agent 对照实际源码逐条检查并标记过度设计——最多 5 轮直到通过。审阅门在所有验证完成前阻止编辑（三字段格式：`<ts>:<completed>:<expected>`）。跨模型审阅（Codex + Claude）能捕获单模型审阅无法发现的盲区。MCP 为非 Claude 宿主提供一次性 `qq_code_review` 和 `qq_plan_review` 工具。

参见[架构总览](docs/dev/architecture/overview.md)获取架构图和层级详情，[Hook 系统](docs/zh-CN/hooks.md)了解自动编译和审阅门控内部机制，[跨模型审阅](docs/zh-CN/cross-model-review.md)了解 Codex Tribunal 流程，[并行 Worktree](docs/zh-CN/worktrees.md) 了解并行任务隔离。

## 自定义

三个文件控制 qq 在你项目中的行为：

- **`qq.yaml`** — 运行时配置：`work_mode`、`policy_profile`、`trust_level`、模块选择。内置 profile：`lightweight`、`core`、`feature`、`hardening`。参见 [`templates/qq.yaml.example`](templates/qq.yaml.example)。
- **`CLAUDE.md`** — 项目级编码规范和编译验证规则。参见 [`templates/CLAUDE.md.example`](templates/CLAUDE.md.example)。
- **`AGENTS.md`** — 子 agent 工作流的架构规则和审阅标准。参见 [`templates/AGENTS.md.example`](templates/AGENTS.md.example)。

## tykit

tykit 是 Unity Editor 进程内的轻量级 HTTP 服务器——零配置、无外部依赖、毫秒级响应。它通过 localhost 暴露编译、测试、Play/Stop、控制台和检视器命令。端口由项目路径哈希生成，存储在 `Temp/tykit.json`。

```bash
PORT=$(python3 -c "import json; print(json.load(open('Temp/tykit.json'))['port'])")
curl -s -X POST http://localhost:$PORT/ -d '{"command":"compile"}' -H 'Content-Type: application/json'
curl -s -X POST http://localhost:$PORT/ -d '{"command":"run-tests","args":{"mode":"editmode"}}' -H 'Content-Type: application/json'
```

tykit 不依赖 qq 即可独立使用——只需添加 [UPM 包](packages/com.tyk.tykit/)。任何能发 HTTP 请求的 agent 都可以直接使用。MCP 桥接（`tykit_mcp.py`）为 MCP 兼容宿主（Codex、Cursor、Continue 等）提供封装。参见 [tykit API 参考](docs/zh-CN/tykit-api.md)获取完整 API，[tykit MCP 桥接](docs/zh-CN/tykit-mcp.md)了解 MCP 集成。

## 常见问题

**支持 Windows 吗？**
支持，预览版。需要 [Git for Windows](https://gitforwindows.org/)（提供 bash、curl 和核心工具）。

**必须安装 Codex CLI 吗？**
不需要。Codex CLI 启用跨模型审阅（`/qq:codex-code-review`），但 `/qq:claude-code-review` 无需它即可使用。

**能和 Cursor/Copilot/Codex 等 agent 一起用吗？**
可以。运行时层（tykit、引擎桥接、`.qq/` 状态、脚本）是 agent 无关的——任何能发 HTTP 请求或使用 MCP 的工具都能使用。24 个 `/qq:*` slash 命令和自动编译 hook 是 Claude Code 专属的，但底层脚本是普通的 shell 和 Python。参见 [`docs/dev/agent-integration.md`](docs/dev/agent-integration.md) 了解集成细节。

**编译失败了会怎样？**
自动编译 hook 捕获错误输出并在对话中显示。agent 读取错误信息并修复代码，然后 hook 自动重新编译。

**能不装 quick-question 单独用 tykit 吗？**
可以。将 [`packages/com.tyk.tykit/`](packages/com.tyk.tykit/) 中的 UPM 包添加到你的项目。参见 [tykit README](packages/com.tyk.tykit/README.md)。

**支持哪些 Unity 版本？**
tykit 需要 Unity 2021.3+。MCP 替代方案：[mcp-unity](https://github.com/nicoboss/mcp-unity) 需要 Unity 6+，[Unity-MCP](https://github.com/mpiechot/Unity-MCP) 无版本要求。

---

## Contributing

Contributions welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
