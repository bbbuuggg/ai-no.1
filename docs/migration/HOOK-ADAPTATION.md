# Hook 适配记录 (HOOK-ADAPTATION)

本文档记录了从 CCGS 的 12 个 Shell Hook 到 Godot-Vibe-Studio 环境的适配决策。

---

## 背景

CCGS 的 Hook 设计对应 **Claude Code** 的生命周期事件机制（`.claude/settings.json` 中配置，在特定事件触发时由 Claude Code 运行时自动执行 shell 脚本）。事件包括：
- `SessionStart`：会话启动
- `UserPromptSubmit`：用户提交提问
- `PreToolUse` / `PostToolUse`：工具调用前后
- `PreCompact` / `PostCompact`：上下文压缩前后
- `Stop` / `SubagentStop`：agent 终止

**CodeBuddy 当前状态**：CodeBuddy 暂不支持等价的 hook 机制。因此本次迁移采取**选择性保留 + 手动调用**策略。

---

## 12 个源 Hook 的处理决策

| # | 源 Hook | 触发事件 | 决策 | 原因 |
|---|---|---|---|---|
| 1 | `session-start.sh` | SessionStart | ✓ **改写为 PowerShell** → `session-start.ps1` | 高价值：加载 Git、sprint、bug、会话状态，是 Vibe Coding 恢复上下文的基石 |
| 2 | `detect-gaps.sh` | SessionStart | ✓ **改写为 PowerShell** → `detect-gaps.ps1` | 高价值：检测项目状态是否一致，引导用户使用正确 skill |
| 3 | `pre-compact.sh` | PreCompact | ✗ 放弃 | CodeBuddy 的上下文管理机制不同，源脚本功能不适用 |
| 4 | `post-compact.sh` | PostCompact | ✗ 放弃 | 同上 |
| 5 | `log-agent-start.sh` | SubagentStop | ✗ 放弃 | CodeBuddy agent 调用栈不经由此 hook；要日志直接用 `commit_log.md` |
| 6 | `log-agent-end.sh` | SubagentStop | ✗ 放弃 | 同上 |
| 7 | `log-agent-stop.sh` | Stop | ✗ 放弃 | 同上 |
| 8 | `log-skill-usage.sh` | UserPromptSubmit | ✗ 放弃 | 改由 Vibe 主管主动记录到 `commit_log.md` |
| 9 | `validate-assets.sh` | PreToolUse (Write) | ✗ 放弃 | Godot 资产验证留给 Godot 编辑器导入机制；命名规范由 rules 检查 |
| 10 | `validate-commit.sh` | Stop | ✗ 放弃 | 改用 Git pre-commit hook（项目级）+ qa-lead 的 smoke-check skill |
| 11 | `validate-naming.sh` | PreToolUse (Write) | ✗ 放弃 | 命名规范在 `rules/gameplay-code.md`、`rules/data-files.md` 中约定，由 agent 读规则自律 |
| 12 | `validate-skill-change.sh` | PreToolUse (Write) | ✗ 放弃 | CodeBuddy 目前不改 skill 文件路径；skill 修改走人工审查 |

---

## 保留的 2 个 Hook 的触发方式

由于 CodeBuddy 不自动触发 Hook，以下是三种人工调用策略（任选其一）：

### 方式 A：每次开新会话前手动运行（推荐）

```powershell
# 在 Godot-Vibe-Studio 项目根目录下
pwsh .codebuddy/hooks/session-start.ps1
pwsh .codebuddy/hooks/detect-gaps.ps1
```

把终端输出粘到 CodeBuddy 对话开头作为上下文：

```
# 粘贴内容
我要继续推进项目。上面是 session-start 和 detect-gaps 的输出。
```

### 方式 B：使用 CodeBuddy automation（如果支持）

如果你的 CodeBuddy 版本支持自动化任务（automation），可创建一个每日/每次会话触发的任务：

```yaml
# 示例（实际语法以 CodeBuddy 文档为准）
name: "Godot Vibe Session Start"
trigger: session_start
cwd: d:/GodotGame/Godot-Vibe-Studio
command: pwsh .codebuddy/hooks/session-start.ps1
```

### 方式 C：让 Vibe 主管主动调用

对话中加一句：

```
请先运行 .codebuddy/hooks/session-start.ps1 和 detect-gaps.ps1 了解项目当前状态。
```

Vibe 主管会用 `execute_command` 工具主动调用。**这是最简单、推荐给小白的方式**。

---

## Hook PowerShell 改写要点

### session-start.ps1 与源 sh 的差异

| 原 sh | PS 等效 |
|---|---|
| `$(git log --oneline -5)` | `git log --oneline -5` |
| `ls -t file-*.md \| head -1` | `Get-ChildItem file-*.md \| Sort-Object LastWriteTime -Descending \| Select-Object -First 1` |
| `find src -name "*.gd"` | `Get-ChildItem scripts -Recurse -Filter *.gd` |
| `grep -r "TODO" src/` | `Get-ChildItem scripts -Recurse \| Select-String 'TODO'` |
| `wc -l < file` | `(Get-Content file).Count` |
| `[ -f "file" ]` | `Test-Path 'file'` |
| `exit 0` | `exit 0` |

### 关键路径差异（Shell 源路径 → PS 版路径）

| CCGS 源路径 | Godot-Vibe-Studio 路径 |
|---|---|
| `production/sprints/` | `docs/design/production/sprints/` |
| `production/milestones/` | `docs/design/production/milestones/` |
| `src/` | `scripts/` |
| `design/gdd/` | `docs/design/gdd/` |
| `docs/architecture/` | `docs/design/architecture/` |

这些差异反映了 Godot-Vibe-Studio 的新目录规约（见 `CLAUDE.md`）。

### 兼容性注意

- 需要 **PowerShell 5.1+**（Windows 10 自带）或 **PowerShell Core 7+**（跨平台）
- `pwsh` 命令 = PowerShell Core（推荐）；`powershell` = 旧 Windows PowerShell
- 若需 Linux/macOS 兼容，未来可改写为 Python 版，放在同目录 `.py`

---

## 未来扩展建议

如果你发现 Hook 价值高想增加，建议优先级：

1. **Git pre-commit hook**：在 `.git/hooks/pre-commit` 加 GDScript 静态类型检查
2. **validate-commit 的 PS 版**：如果你做 QA 严格的项目，改写为 `validate-commit.ps1`
3. **Godot 导入前校验**：在 Godot 的 `EditorImportPlugin` 里做资产命名/格式检查，比 Hook 更准确

---

## 测试 PowerShell Hook

```powershell
# 在 Godot-Vibe-Studio 根目录测试
cd d:/GodotGame/Claud-to-CodeBuddy/Godot-Vibe-Studio
pwsh .codebuddy/hooks/session-start.ps1
# 预期输出：
#  === Godot-Vibe-Studio — Session Context ===
#  Branch: ...
#  ===================================

pwsh .codebuddy/hooks/detect-gaps.ps1
# 预期输出：
#  === Checking for Documentation Gaps ===
#  NEW PROJECT: 无引擎配置...
#  ===================================
```

本次迁移后运行 `detect-gaps.ps1` 应该输出"NEW PROJECT"，因为还没有具体游戏内容。

---

## 故障排除

**问题 1**：`pwsh : 无法将"pwsh"项识别为 cmdlet`
→ 安装 PowerShell 7：`winget install Microsoft.PowerShell` 或用旧版 `powershell`

**问题 2**：`无法加载文件 ...，因为在此系统上禁止运行脚本`
→ 管理员 PowerShell 跑一次：
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**问题 3**：Hook 输出里 Git 报错
→ 项目不是 Git 仓库。可选择 `git init` 初始化，或忽略（Hook 会继续跑）

---

**如发现 Hook 行为不符合预期，随时调整 `.codebuddy/hooks/*.ps1` 即可。**
