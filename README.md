<p align="center">
  <img src="logo.png" alt="quick-question" width="200">
</p>

<h1 align="center">quick-question</h1>

<p align="center">
  <strong>Unity Agent Harness for Claude Code</strong><br>
  Auto-compile, test pipelines, cross-model code review — out of the box.
</p>

<p align="center">
  <a href="https://github.com/tykisgod/quick-question/actions/workflows/validate.yml"><img src="https://github.com/tykisgod/quick-question/actions/workflows/validate.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/tykisgod/quick-question/blob/main/LICENSE"><img src="https://img.shields.io/github/license/tykisgod/quick-question" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS-blue" alt="Platform">
  <img src="https://img.shields.io/badge/unity-2021.3%2B-black?logo=unity" alt="Unity">
  <img src="https://img.shields.io/badge/claude--code-plugin-blueviolet" alt="Claude Code Plugin">
  <a href="https://github.com/tykisgod/quick-question/stargazers"><img src="https://img.shields.io/github/stars/tykisgod/quick-question?style=social" alt="Stars"></a>
</p>

<p align="center">
  <a href="#english">English</a> |
  <a href="#中文">中文</a> |
  <a href="#日本語">日本語</a> |
  <a href="#한국어">한국어</a>
</p>

---

# English

## What It Does

> Edit → Compile → Test → Review → Ship. Fully automated.

🔧 **Auto-Compilation** — Edit a `.cs` file, compilation runs automatically via hook
🧪 **Test Pipeline** — EditMode + PlayMode tests with runtime error checking
🔍 **Cross-Model Review** — Claude orchestrates, Codex reviews, every finding verified against source
⚡ **15 Slash Commands** — test, commit, review, explain, dependency analysis, and more
🎮 **tykit** — HTTP server inside Unity Editor for AI agent control (play/stop/console/run tests)

```
Edit .cs file
     │ (PostToolUse hook)
     ▼
┌──────────────────┐
│  Smart Compile   │──── tykit (fast) / Editor trigger / Batch mode
└────────┬─────────┘
         ▼
┌──────────────────┐
│   /qq:test       │──── EditMode + PlayMode + error check
└────────┬─────────┘
         ▼
┌──────────────────────────┐
│  /qq:codex-code-review   │──── Codex reviews → Claude verifies → fix → loop
└────────┬─────────────────┘
         ▼
┌──────────────────┐
│  /qq:commit-push │──── commit + push
└──────────────────┘
```

## A Day with qq

> Alex is building a Unity RPG. She just installed qq. Here's her Tuesday.

**9:00 AM — Start coding**

Alex asks Claude to add a health regeneration system. Claude writes `HealthRegen.cs`.

She doesn't run any compile command. The moment Claude saves the file, a hook fires:

```
⚙️ Compiling Unity... ✅ Compilation successful (1.2s)
```

She doesn't even notice. It just works.

**9:30 AM — Run tests**

```
/qq:test
```

```
EditMode:  52/52 passed
PlayMode:  18/18 passed
Runtime errors: 1 found
  [Error] NullReferenceException at HealthRegen.cs:34
  Source: HealthRegen.OnEnable() — _playerStats not assigned
```

Even though all tests "passed", qq caught a runtime error hiding in the console. Claude reads the code, fixes the null ref, auto-compiles again. Clean.

**10:00 AM — Something feels wrong**

The regen formula seems off. Alex isn't sure how the original health system works.

```
/qq:grandma
```

> "Imagine your character is a water tank. Max HP is how big the tank is. Damage is someone poking holes. Healing is pouring water back in. Regeneration is a small faucet that's always dripping — slow, but it never stops. What you just built is that faucet."

Now she gets it. The regen rate should scale with max HP, not current HP.

**11:00 AM — How do others solve this?**

```
/qq:research
```

Claude searches open-source RPGs and returns a comparison:

| Game | Regen Model | Pros | Cons |
|------|------------|------|------|
| Rimworld | Flat rate per tick | Simple | Doesn't scale |
| Valheim | % of max HP | Scales naturally | Can be too fast at high HP |
| Diablo-likes | Stat-based (regen stat) | Player agency | Complex |

Alex picks the Valheim model. Simple, scales, done.

**2:00 PM — Code review before PR**

```
/qq:claude-code-review
```

Claude spawns a reviewer subagent. Before the findings come back, a **Review Gate** activates — Alex can't edit any code until the review is verified.

```
Review subagent found:
  [Critical] HealthRegen applies during death state — should check isDead
  [Medium] Regen tick runs in Update() — should use TickManager for consistency
  [Suggestion] Consider caching GetComponent<PlayerStats>()

Spawning 2 verification subagents...

  [Critical] isDead check: CONFIRMED — HealthRegen.cs:28, no guard
  [Medium] Update vs TickManager: CONFIRMED — all other systems use TickManager

Gate unlocked. Fixing confirmed issues...
  ✅ Compiled. 52/52 EditMode, 18/18 PlayMode passed.
```

The Gate prevented her from "just quickly fixing it" before verification. Every finding was checked against real code first.

**3:00 PM — Prepare PR materials**

```
/qq:full-brief
```

Three agents run in parallel. Four documents land in `Docs/qq/`:

```
arch-review    — Mermaid diagram showing HealthRegen → PlayerStats → TickManager
pr-review      — P0: isDead guard, P1: TickManager migration, P2: caching
timeline-arch  — Phase 1: base regen, Phase 2: scaling, Phase 3: death guard
timeline-review — review items grouped by development phase
```

Her reviewer opens the arch diagram, sees the dependency flow, and approves in 10 minutes.

**3:30 PM — Ship it**

```
/qq:commit-push
```

Claude groups changes into 2 logical commits, writes conventional commit messages. Pre-push hook runs tests one last time.

```
[pre-push] EditMode 52/52 ✅ PlayMode 18/18 ✅
[pre-push] Runtime errors: 0
All tests passed, push allowed.
```

Done. From idea to merged PR, every step had a safety net — and Alex never had to remember to run anything manually.

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| macOS | v1 limitation — Windows/Linux planned for v2 |
| Git | Required — hooks and review commands depend on it |
| Unity 2021.3+ | Required by tykit |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | CLI or IDE extension |
| curl, python3, jq | `brew install curl python3 jq` |
| [Codex CLI](https://github.com/openai/codex) | Optional — only for cross-model review |

## Install

### Step 1: Install Plugin (skills + hooks)

In Claude Code:
```
/plugin marketplace add tykisgod/quick-question
/plugin install qq@quick-question-marketplace
```

This gives you all 15 skills and hooks (auto-compile, skill review enforcement). No files are copied into your project — the plugin runs from its cache.

### Step 2: Install tykit (Unity package)

tykit is the HTTP server that lets Claude control Unity Editor:

```bash
git clone https://github.com/tykisgod/quick-question.git /tmp/qq-install
/tmp/qq-install/install.sh /path/to/your-unity-project
rm -rf /tmp/qq-install
```

The installer handles Unity-specific setup:
- Adds tykit to `Packages/manifest.json`
- Copies shell scripts to `scripts/`
- Creates `CLAUDE.md` and `AGENTS.md` from templates (only if missing, never overwrites)

## Quick Start

After installation, open your Unity project and start Claude Code:

```bash
# Run tests and check for errors
/qq:test

# Run PlayMode only
/qq:test play

# Filter by test name
/qq:test --filter "Health"

# Cross-model code review
/qq:codex-code-review

# Commit and push
/qq:commit-push
```

## Commands

| Command | Description |
|---------|-------------|
| **Testing** | |
| `/qq:test` | Run unit/integration tests with error checking |
| **Code Review (Codex)** | *Requires [Codex CLI](https://github.com/openai/codex)* |
| `/qq:codex-code-review` | Cross-model code review (Claude + Codex with verification) |
| `/qq:codex-plan-review` | Cross-model design document review |
| **Code Review (Claude-only)** | *No extra tools needed* |
| `/qq:claude-code-review` | Deep code review using Claude subagents |
| `/qq:claude-plan-review` | Deep design document review using Claude subagents |
| **Code Review (Quick)** | |
| `/qq:code-review` | Project-specific review (reads your `AGENTS.md` rules) |
| `/qq:self-review` | Review skill/config changes for quality |
| **Analysis** | |
| `/qq:brief` | Architecture diff + PR checklist (2 docs) |
| `/qq:timeline` | Commit history timeline with phase analysis (2 docs) |
| `/qq:full-brief` | Run brief + timeline in parallel (4 docs total) |
| `/qq:deps` | `.asmdef` dependency graph + matrix + health check |
| **Utilities** | |
| `/qq:commit-push` | Batch commit and push |
| `/qq:explain` | Explain module architecture in plain language |
| `/qq:grandma` | Explain any concept using everyday analogies anyone can understand |
| `/qq:research` | Search open-source solutions for current problem |
| `/qq:changes` | Summarize all changes in current conversation |
| `/qq:doc-tidy` | Scan repo docs, analyze organization, suggest cleanup |
| `/qq:doc-drift` | Compare design docs vs code, find inconsistencies |

## How It Works

### Auto-Compilation (PostToolUse Hook)

Every time Claude edits a `.cs` file, a PostToolUse hook triggers smart compilation:

```mermaid
flowchart LR
    A["Edit .cs file"] --> B{tykit\navailable?}
    B -->|Yes| C["HTTP compile\n(fast, non-blocking)"]
    B -->|No| D{Editor\nopen?}
    D -->|Yes| E["osascript trigger\n+ poll status"]
    D -->|No| F["Unity -batchmode\n(offline compile)"]
    C --> G["✅ Result"]
    E --> G
    F --> G
```

### tykit

An HTTP server that auto-starts inside Unity Editor. Port is determined by project path hash, stored in `Temp/eval_server.json`.

```mermaid
flowchart LR
    subgraph "Claude Code"
        A[Shell Scripts]
    end
    subgraph "Unity Editor"
        B[tykit :PORT]
        C[CompilePipeline]
        D[TestRunner]
        E[Console]
        F[SceneManager]
    end
    A -->|"HTTP POST"| B
    B --> C
    B --> D
    B --> E
    B --> F
```

**Available commands:**

| Command | Description |
|---------|-------------|
| `status` | Editor state overview |
| `compile-status` / `get-compile-result` | Compilation status and errors |
| `run-tests` / `get-test-result` | Run and poll EditMode/PlayMode tests |
| `play` / `stop` | Control Play Mode |
| `console` | Read console logs (with filter support) |
| `find` / `inspect` | Find and inspect GameObjects |
| `refresh` / `save-scene` / `clear-console` | Editor utilities |

### Cross-Model Review (Tribunal)

Two AI models reviewing each other's work with automatic verification:

```mermaid
flowchart TD
    A["Start /qq:codex-code-review"] --> B["Codex reviews diff"]
    B --> C["Claude spawns verification subagents"]
    C --> D{"Each finding\nconfirmed?"}
    D -->|"Not confirmed"| E["Discard finding"]
    D -->|"Confirmed"| F{"Over-engineered\nfix?"}
    F -->|"Yes"| G["Use simpler alternative"]
    F -->|"No"| H["Apply fix"]
    E --> I{"Critical issues\nremaining?"}
    G --> I
    H --> I
    I -->|"Yes (max 5 rounds)"| B
    I -->|"No"| J["✅ Review complete"]
```

**Review Gate:** While verification subagents are running, a PreToolUse hook blocks edits to `.cs` files and `Docs/*.md` — preventing premature fixes before findings are confirmed.

### Skill Review Enforcement (Stop Hook)

```mermaid
flowchart LR
    A["Edit a skill file"] -->|"PostToolUse"| B["Mark in /tmp/\nmarker file"]
    B --> C["Session ending..."]
    C -->|"Stop hook"| D{"Marker\nexists?"}
    D -->|"Yes"| E["❌ Block: run\n/qq:self-review first"]
    D -->|"No"| F["✅ Session ends"]
```

### Pre-Push Testing (Git Hook, Optional)

Automatically runs EditMode + PlayMode tests before every `git push`. If tests fail, the push is blocked.

```bash
# Install with pre-push hook
./install.sh /path/to/project --with-pre-push

# Skip for a single push
git push --no-verify
```

```mermaid
flowchart LR
    A["git push"] -->|"pre-push hook"| B["EditMode tests"]
    B -->|"Pass"| C["PlayMode tests"]
    C -->|"Pass"| D["Check Editor.log\nfor runtime errors"]
    D --> E{"Errors?"}
    E -->|"None"| F["✅ Push allowed"]
    E -->|"Found"| G["⚠️ Warning\n(push still allowed)"]
    B -->|"Fail"| H["❌ Push blocked"]
    C -->|"Fail"| H
```

## All Hooks Summary

| Hook | Trigger | What It Does | Default | Impact |
|------|---------|-------------|:-------:|--------|
| **Auto-compile** | Edit .cs file | Runs smart compilation | On | Every .cs edit |
| **Skill change marker** | Edit skill file | Records change for self-review | On | Only when editing skills |
| **Self-review enforcement** | Session ending | Blocks if unreviewed skill changes | On | Only when skills were edited |
| **Review Gate (set)** | Run code-review.sh | Locks code edits until verified | On | Only during `/qq:codex-*` reviews |
| **Review Gate (check)** | Edit .cs / docs | Blocks if gate is locked | On | Only when gate is active |
| **Review Gate (count)** | Subagent completes | Unlocks gate after verification | On | Only when gate is active |
| **Gate cleanup** | Session ending | Clears gate marker | On | Automatic, no impact |
| **Pre-push testing** | git push | Runs tests, blocks on failure | **Off** | Every push (when enabled) |

### Disabling Hooks

The Review Gate hooks only activate during cross-model review — **zero impact** on normal development.

To disable auto-compilation or self-review enforcement, override in your project's `.claude/settings.local.json`:

```json
{
  "hooks": {
    "PostToolUse": [{ "matcher": "Write|Edit", "hooks": [] }],
    "Stop": [{ "matcher": "", "hooks": [] }]
  }
}
```

This disables **all** PostToolUse and Stop hooks. To disable only specific ones, keep the hooks array but remove the entry you don't want.

To remove the pre-push hook:
```bash
rm .githooks/pre-push
git config --unset core.hooksPath
```

## Comparison

| Feature | quick-question | Typical AI Tools |
|---------|:---:|:---:|
| Auto-compile on edit | ✅ Hook-driven | ❌ Manual |
| Test pipeline | ✅ EditMode + PlayMode + error check | ❌ Manual |
| Cross-model review | ✅ Claude + Codex with verification loop | ⚠️ Single model |
| Runtime Editor control | ✅ tykit (HTTP) | ❌ No access |
| Skill review enforcement | ✅ Stop hook blocks until reviewed | ⚠️ Honor system |
| Scene restoration | ✅ Auto-restores after PlayMode tests | ❌ Left on test scene |
| Pre-push test gate | ✅ Optional git hook | ❌ None |

## Customization

### CLAUDE.md

Your coding standards. The auto-compilation hook and test commands respect whatever rules you define here. See [`templates/CLAUDE.md.example`](templates/CLAUDE.md.example) for Unity-specific defaults.

### AGENTS.md

Your architecture rules and review criteria. The `/qq:code-review` and cross-model review commands read this file to detect anti-patterns and module boundary violations. See [`templates/AGENTS.md.example`](templates/AGENTS.md.example) for a starting template.

### Priority System

All review commands classify findings by impact:

| Priority | Scope | Action |
|----------|-------|--------|
| **P0** | Architecture changes, anti-patterns, lifecycle issues | Must review |
| **P1** | Business logic, performance, error handling | Worth reviewing |
| **P2** | Getters/setters, logging, config tweaks | Quick scan |

## Limitations

- **macOS only** (v1) — scripts use `osascript`, `/Applications/Unity`, `~/Library/Logs`
- **Codex CLI required** for cross-model review features
- **Unity 2021.3+** required by tykit package
- **tykit is localhost-only, no authentication** — acceptable for dev machines, not for shared/CI environments
- **Console log scraping** for compile verification — use `clear-console` before critical compiles to avoid stale errors

## Contributing

Contributions are welcome! Please open an issue or submit a pull request.

## License

[MIT](LICENSE) © Yukang Tian

---

# 中文

## 功能

> 编辑 → 编译 → 测试 → 审阅 → 发布，全自动。

🔧 **自动编译** — 编辑 .cs 文件后自动编译验证
🧪 **测试流水线** — EditMode + PlayMode 测试 + 运行时错误检查
🔍 **跨模型审阅** — Claude 编排，Codex 审阅，每条发现逐一验证
⚡ **15 个斜杠命令** — 测试、提交、审阅、解释、依赖分析等
🎮 **tykit** — Unity Editor 内的 HTTP 服务器，AI agent 可控制

```
编辑 .cs 文件
     │ (PostToolUse hook)
     ▼
┌──────────────────┐
│    智能编译      │──── tykit（快速）/ Editor 触发 / Batch 模式
└────────┬─────────┘
         ▼
┌──────────────────┐
│   /qq:test       │──── EditMode + PlayMode + 错误检查
└────────┬─────────┘
         ▼
┌──────────────────────────┐
│  /qq:codex-code-review   │──── Codex 审阅 → Claude 验证 → 修复 → 循环
└────────┬─────────────────┘
         ▼
┌──────────────────┐
│  /qq:commit-push │──── 提交 + 推送
└──────────────────┘
```

## qq 的一天

> 小明在做一个 Unity RPG 游戏。他刚装好 qq。这是他的周二。

**9:00 — 开始写代码**

小明让 Claude 写一个生命回复系统。Claude 写完 `HealthRegen.cs`，他什么都不用做——hook 自动编译：

```
⚙️ Compiling Unity... ✅ 编译成功 (1.2s)
```

**9:30 — 跑测试**

```
/qq:test
```

52 个 EditMode + 18 个 PlayMode 全通过，但 qq 在 console 里发现了一个隐藏的 NullReferenceException。Claude 读代码，修复，再编译。干净了。

**10:00 — 搞不懂原来的血量系统**

```
/qq:grandma
```

> "想象你的角色是一个水桶。最大生命值是桶有多大。受伤是有人戳了个洞。治疗是往里倒水。回复是一个一直在滴的水龙头——慢，但永远不停。你刚写的就是那个水龙头。"

明白了！回复速率应该按最大 HP 算，不是当前 HP。

**11:00 — 别人怎么做的？**

```
/qq:research
```

Claude 搜索开源 RPG，返回对比表：Rimworld 用固定值、Valheim 按最大 HP 百分比、暗黑类用属性点。小明选了 Valheim 方案。

**14:00 — 提 PR 前审阅**

```
/qq:claude-code-review
```

审阅 subagent 发现 3 个问题。**Review Gate 激活**——验证完之前不能改代码。2 个 subagent 并行验证每条发现，确认后才解锁。修复，编译通过，测试通过。

**15:00 — 生成 PR 材料**

```
/qq:full-brief
```

三个 agent 并行，产出 4 份文档：架构图、审阅清单、时间线架构、时间线审阅。Reviewer 看了架构图，10 分钟批准。

**15:30 — 提交**

```
/qq:commit-push
```

Pre-push hook 最后跑一次测试。全绿。合并。

从想法到合并，每一步都有安全网——小明从不需要记住"该跑什么命令"。

## 前置条件

| 需求 | 说明 |
|------|------|
| macOS | v1 限制 — Windows/Linux 计划在 v2 支持 |
| Git | 必需 — hooks 和审阅命令依赖 git |
| Unity 2021.3+ | tykit 要求 |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | CLI 或 IDE 扩展 |
| curl, python3, jq | `brew install curl python3 jq` |
| [Codex CLI](https://github.com/openai/codex) | 可选 — 仅跨模型审阅需要 |

## 安装

### 第 1 步：安装插件（skills + hooks）

在 Claude Code 中：
```
/plugin marketplace add tykisgod/quick-question
/plugin install qq@quick-question-marketplace
```

这会安装全部 15 个 skill 和 hooks（自动编译、skill 审阅强制）。不会向你的项目复制任何文件 — 插件从缓存运行。

### 第 2 步：安装 tykit（Unity 包）

tykit 是让 Claude 控制 Unity Editor 的 HTTP 服务器：

```bash
git clone https://github.com/tykisgod/quick-question.git /tmp/qq-install
/tmp/qq-install/install.sh /path/to/your-unity-project
rm -rf /tmp/qq-install
```

安装器处理 Unity 相关配置：
- 将 tykit 添加到 `Packages/manifest.json`
- 复制 shell 脚本到 `scripts/`
- 从模板创建 `CLAUDE.md` 和 `AGENTS.md`（仅在不存在时创建，不会覆盖）

## 快速开始

安装完成后，打开 Unity 项目并启动 Claude Code：

```bash
# 运行测试并检查错误
/qq:test

# 仅运行 PlayMode
/qq:test play

# 按测试名过滤
/qq:test --filter "Health"

# 跨模型代码审阅
/qq:codex-code-review

# 提交并推送
/qq:commit-push
```

## 命令

| 命令 | 描述 |
|------|------|
| **测试** | |
| `/qq:test` | 运行单元/集成测试并检查错误 |
| `/qq:st` | 完整测试流水线（EditMode → PlayMode → 错误检查） |
| **代码审阅** | |
| `/qq:codex-code-review` | 跨模型代码审阅（Codex + 验证循环） |
| `/qq:codex-plan-review` | 跨模型设计文档审阅 |
| `/qq:code-review` | 项目专属审阅（读取 `AGENTS.md` 规则） |
| `/qq:self-review` | 审阅 skill/配置变更的质量 |
| **分析** | |
| `/qq:brief` | 架构 diff + PR 清单（1 个 skill 生成 2 份文档） |
| `/qq:timeline` | 提交历史时间线及阶段分析（2 份文档） |
| `/qq:full-brief` | 并行运行 brief + timeline（共 4 份文档） |
| `/qq:deps` | `.asmdef` 依赖关系图 + 矩阵 + 健康检查 |
| **工具** | |
| `/qq:commit-push` | 批量提交并推送 |
| `/qq:explain` | 用通俗语言解释模块架构 |
| `/qq:grandma` | 用日常类比解释任何概念，人人都能听懂 |
| `/qq:research` | 搜索当前问题的开源解决方案 |
| `/qq:changes` | 汇总当前会话的所有变更 |
| `/qq:doc-tidy` | 扫描仓库文档，分析组织问题，建议清理 |

## 工作原理

### 自动编译（PostToolUse Hook）

每当 Claude 编辑 `.cs` 文件时，PostToolUse hook 触发智能编译：

```mermaid
flowchart LR
    A["编辑 .cs 文件"] --> B{tykit\n可用？}
    B -->|是| C["HTTP 编译\n（快速，非阻塞）"]
    B -->|否| D{Editor\n已打开？}
    D -->|是| E["osascript 触发\n+ 轮询状态"]
    D -->|否| F["Unity -batchmode\n（离线编译）"]
    C --> G["✅ 结果"]
    E --> G
    F --> G
```

### tykit

Unity Editor 内自动启动的 HTTP 服务器。端口由项目路径哈希决定，存储在 `Temp/eval_server.json` 中。

```mermaid
flowchart LR
    subgraph "Claude Code"
        A[Shell 脚本]
    end
    subgraph "Unity Editor"
        B[tykit :PORT]
        C[编译管线]
        D[测试运行器]
        E[控制台]
        F[场景管理器]
    end
    A -->|"HTTP POST"| B
    B --> C
    B --> D
    B --> E
    B --> F
```

**可用命令：**

| 命令 | 描述 |
|------|------|
| `status` | Editor 状态概览 |
| `compile-status` / `get-compile-result` | 编译状态及错误 |
| `run-tests` / `get-test-result` | 运行并轮询 EditMode/PlayMode 测试 |
| `play` / `stop` | 控制 Play Mode |
| `console` | 读取控制台日志（支持过滤） |
| `find` / `inspect` | 查找和检视 GameObject |
| `refresh` / `save-scene` / `clear-console` | Editor 工具 |

### 跨模型审阅（Tribunal）

两个 AI 模型互相审阅，自动验证每条发现：

```mermaid
flowchart TD
    A["启动 /qq:codex-code-review"] --> B["Codex 审阅 diff"]
    B --> C["Claude 派出验证子 agent"]
    C --> D{"每条发现\n已确认？"}
    D -->|"未确认"| E["丢弃发现"]
    D -->|"已确认"| F{"修复方案\n过度设计？"}
    F -->|"是"| G["采用更简单的方案"]
    F -->|"否"| H["应用修复"]
    E --> I{"还有关键\n问题？"}
    G --> I
    H --> I
    I -->|"是（最多 5 轮）"| B
    I -->|"否"| J["✅ 审阅完成"]
```

**审阅门控：** 验证子 agent 运行期间，PreToolUse hook 会阻止所有代码编辑 — 防止在发现被确认前过早修复。

### Skill 审阅强制（Stop Hook）

```mermaid
flowchart LR
    A["编辑 skill 文件"] -->|"PostToolUse"| B["记录到 /tmp/\n标记文件"]
    B --> C["会话即将结束..."]
    C -->|"Stop hook"| D{"标记\n存在？"}
    D -->|"是"| E["❌ 阻止：先运行\n/qq:self-review"]
    D -->|"否"| F["✅ 会话结束"]
```

## 对比

| 特性 | quick-question | 传统 AI 工具 |
|------|:---:|:---:|
| 编辑即编译 | ✅ Hook 驱动 | ❌ 手动 |
| 测试流水线 | ✅ EditMode + PlayMode + 错误检查 | ❌ 手动 |
| 跨模型审阅 | ✅ Claude + Codex 验证循环 | ⚠️ 单模型 |
| 运行时 Editor 控制 | ✅ tykit (HTTP) | ❌ 无法访问 |
| Skill 审阅强制 | ✅ Stop hook 阻止直到审阅完成 | ⚠️ 靠自觉 |
| 场景恢复 | ✅ PlayMode 测试后自动恢复 | ❌ 停留在测试场景 |

## 自定义

### CLAUDE.md

你的编码规范。自动编译 hook 和测试命令会遵循你在此定义的规则。参见 [`templates/CLAUDE.md.example`](templates/CLAUDE.md.example) 获取 Unity 专用默认值。

### AGENTS.md

你的架构规则和审阅标准。`/qq:code-review` 和跨模型审阅命令会读取此文件来检测反模式和模块边界违规。参见 [`templates/AGENTS.md.example`](templates/AGENTS.md.example) 获取起始模板。

### 优先级系统

所有审阅命令按影响程度分类发现：

| 优先级 | 范围 | 处理 |
|--------|------|------|
| **P0** | 架构变更、反模式、生命周期问题 | 必须审阅 |
| **P1** | 业务逻辑、性能、错误处理 | 建议审阅 |
| **P2** | Getter/Setter、日志、配置微调 | 快速扫一眼 |

## 限制

- **仅 macOS**（v1）— 脚本使用 `osascript`、`/Applications/Unity`、`~/Library/Logs`
- **跨模型审阅功能需要 Codex CLI**
- **Unity 2021.3+**，tykit 包要求
- **tykit 仅限 localhost，无认证** — 适用于开发机，不适用于共享/CI 环境
- **编译验证使用控制台日志抓取** — 关键编译前使用 `clear-console` 避免残留错误

## 贡献

欢迎贡献！请提交 Issue 或 Pull Request。

## 许可证

[MIT](LICENSE) © Yukang Tian

---

# 日本語

## 機能

> 編集 → コンパイル → テスト → レビュー → リリース。完全自動化。

🔧 **自動コンパイル** — .cs ファイル編集後に自動コンパイル検証
🧪 **テストパイプライン** — EditMode + PlayMode テスト + ランタイムエラーチェック
🔍 **クロスモデルレビュー** — Claude が編成、Codex がレビュー、各指摘をソースで検証
⚡ **15 個のスラッシュコマンド** — テスト、コミット、レビュー、解説、依存分析など
🎮 **tykit** — Unity Editor 内の HTTP サーバー

## インストール

### ステップ 1：プラグインのインストール

Claude Code で：
```
/plugin marketplace add tykisgod/quick-question
/plugin install qq@quick-question-marketplace
```

### ステップ 2：tykit のインストール

```bash
git clone https://github.com/tykisgod/quick-question.git /tmp/qq-install
/tmp/qq-install/install.sh /path/to/unity-project
rm -rf /tmp/qq-install
```

前提条件：macOS、Unity 2021.3+、Claude Code、curl/python3/jq、Codex CLI（オプション）

## qq との一日

> アレックスは Unity RPG を開発中。qq をインストールしたばかりの火曜日。

**9:00** — コードを書く。Claude が `HealthRegen.cs` を保存した瞬間、hook が自動コンパイル。何も実行する必要なし。

**9:30** — `/qq:test`。テスト全通過、でもランタイムエラーを 1 件発見。Claude が修正、再コンパイル。クリーン。

**10:00** — `/qq:grandma`。HP 回復システムを水道の蛇口に例えて説明。回復率は現在 HP ではなく最大 HP に基づくべきだと気づく。

**11:00** — `/qq:research`。オープンソース RPG の回復モデルを比較。Valheim 方式を採用。

**14:00** — `/qq:claude-code-review`。Review Gate が起動 — 検証完了まで編集ブロック。subagent が各指摘を検証。修正、テスト通過。

**15:00** — `/qq:full-brief`。4 つのドキュメントを並列生成。レビュアーがアーキテクチャ図を見て 10 分で承認。

**15:30** — `/qq:commit-push`。Pre-push hook が最終テスト。全グリーン。マージ完了。

---

# 한국어

## 기능

> 편집 → 컴파일 → 테스트 → 리뷰 → 배포. 완전 자동화.

🔧 **자동 컴파일** — .cs 파일 편집 후 자동 컴파일 검증
🧪 **테스트 파이프라인** — EditMode + PlayMode 테스트 + 런타임 에러 체크
🔍 **크로스 모델 리뷰** — Claude 오케스트레이션, Codex 리뷰, 각 발견사항 소스 검증
⚡ **15개 슬래시 커맨드** — 테스트, 커밋, 리뷰, 설명, 의존성 분석 등
🎮 **tykit** — Unity Editor 내 HTTP 서버

## 설치

### 1단계: 플러그인 설치

Claude Code에서:
```
/plugin marketplace add tykisgod/quick-question
/plugin install qq@quick-question-marketplace
```

### 2단계: tykit 설치

```bash
git clone https://github.com/tykisgod/quick-question.git /tmp/qq-install
/tmp/qq-install/install.sh /path/to/unity-project
rm -rf /tmp/qq-install
```

사전 요구사항: macOS, Unity 2021.3+, Claude Code, curl/python3/jq, Codex CLI (선택)

## qq와 함께하는 하루

> 민수는 Unity RPG를 만들고 있다. qq를 막 설치한 화요일.

**9:00** — 코딩 시작. Claude가 `HealthRegen.cs`를 저장하는 순간 hook이 자동 컴파일. 아무것도 실행할 필요 없음.

**9:30** — `/qq:test`. 테스트 전부 통과, 하지만 런타임 에러 1건 발견. Claude가 수정, 재컴파일. 깔끔.

**10:00** — `/qq:grandma`. HP 회복 시스템을 수도꼭지에 비유해서 설명. 회복률은 현재 HP가 아니라 최대 HP 기준이어야 한다는 걸 깨달음.

**11:00** — `/qq:research`. 오픈소스 RPG의 회복 모델 비교. Valheim 방식 채택.

**14:00** — `/qq:claude-code-review`. Review Gate 작동 — 검증 완료 전까지 편집 차단. subagent가 각 지적 검증. 수정, 테스트 통과.

**15:00** — `/qq:full-brief`. 4개 문서 병렬 생성. 리뷰어가 아키텍처 다이어그램 보고 10분 만에 승인.

**15:30** — `/qq:commit-push`. Pre-push hook이 최종 테스트. 올 그린. 머지 완료.
