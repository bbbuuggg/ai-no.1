# 迁移变更清单 (MIGRATION-CHANGELOG)

**源**：`Claude-Code-Game-Studios`（CCGS, Donchitos/github, commit: main 分支最新）
**目**：`Godot-Vibe-Studio`
**迁移日期**：2026-04-29
**执行者**：CodeBuddy（AI 主导，平衡模式，用户 C1-A/C2-A+C 决策）

---

## 顶层决策汇总（用户拍板）

| 决策点 | 选项 | 生效范围 |
|---|---|---|
| D1 目标目录命名 | `Godot-Vibe-Studio/`（独立方法论仓）| 目录结构 |
| D2 CodeBuddy agent 格式 | 对齐 `ai-no.1/.codebuddy/agents/game-designer.md` 范式 | 16 个 agent |
| D3 AI 主动性 | 平衡模式（删减/工程文件/目录规范三事件需确认，其他自动）| 全部 |
| D4 中英双语 | 方案乙：英文文件名 + 中文 name + 中文正文 | 16 个 agent |
| D5 Godot 版本 | 锁定 4.6 | docs/engine-reference/ + agents |
| D6 Hook 策略 | 默认放弃 + 保留 2 个 PowerShell 版 | `.codebuddy/hooks/` |
| D7 CCGS Skill Testing Framework | 整体不迁移 | - |
| C1 game-designer.md 命名冲突 | 方案 A：照常命名（迁入时手动备份）| `game-designer.md` |
| C2 新增两个专家选择 | A + C：场景架构师 + 动画师 | 两个新 agent |
| 16-agent 最终清单 | 见下表 | - |

---

## 最终 16-agent 清单

### Tier 1（总监层，4 个）
- [✓] `vibe-lead.md` — Vibe 主管（**新建**，本项目独有的主编排）
- [✓] `creative-director.md` — 创意总监（源自 CCGS）
- [✓] `technical-director.md` — 技术总监（源自 CCGS）
- [✓] `producer.md` — 制作人（源自 CCGS）

### Tier 2（主管层，6 个）
- [✓] `game-designer.md` — 游戏策划（源自 CCGS，合并 systems-designer / economy-designer 职责，⚠️与 ai-no.1 同名）
- [✓] `lead-programmer.md` — 主程序（合并 7 个细分 programmer 职责）
- [✓] `art-director.md` — 美术指导（源自 CCGS）
- [✓] `ux-lead.md` — 用户体验主管（源自 ux-designer，合并 accessibility-specialist）
- [✓] `qa-lead.md` — 测试主管（合并 qa-tester）
- [✓] `audio-director.md` — 音频总监（合并 sound-designer）

### Tier 3（专家层，6 个）
- [✓] `godot-specialist.md` — Godot 专家（剔除 GDScript/C#/GDExtension 选型相关内容）
- [✓] `godot-gdscript-specialist.md` — GDScript 专家
- [✓] `godot-shader-specialist.md` — 着色器专家
- [✓] `godot-scene-architect.md` — 场景架构师（**新建**，C2-A 决策）
- [✓] `godot-animation-specialist.md` — 动画师（**新建**，C2-C 决策）
- [✓] `level-designer.md` — 关卡设计师（源自 CCGS）

---

## 被剔除的 33 个源 Agent

### 引擎特定，不适用 GDScript-only（8 个）
- godot-csharp-specialist.md （C# 专家，GDScript-only 决策剔除）
- godot-gdextension-specialist.md（C++ GDExtension 专家，剔除）
- unity-specialist.md
- unity-addressables-specialist.md
- unity-dots-specialist.md
- unity-shader-specialist.md
- unity-ui-specialist.md
- unreal-specialist.md
- ue-blueprint-specialist.md
- ue-gas-specialist.md
- ue-replication-specialist.md
- ue-umg-specialist.md

### 合并到主程序（7 个细分 programmer）
- ai-programmer.md → lead-programmer + godot-gdscript-specialist（AI 行为由 GDScript 专家实现）
- gameplay-programmer.md → lead-programmer
- engine-programmer.md → lead-programmer + godot-specialist
- network-programmer.md → lead-programmer（项目默认单机）
- tools-programmer.md → lead-programmer
- ui-programmer.md → lead-programmer + godot-gdscript-specialist
- performance-analyst.md → lead-programmer + godot-specialist

### 合并到其他主管
- systems-designer.md → game-designer
- economy-designer.md → game-designer
- narrative-director.md → creative-director
- writer.md → creative-director（叙事文档）
- sound-designer.md → audio-director
- qa-tester.md → qa-lead
- accessibility-specialist.md → ux-lead
- technical-artist.md → art-director + godot-shader-specialist
- world-builder.md → level-designer + creative-director

### 运营/发布阶段暂不迁移（6 个，后期补）
- release-manager.md
- devops-engineer.md
- security-engineer.md
- analytics-engineer.md
- community-manager.md
- live-ops-designer.md
- localization-lead.md
- prototyper.md（与 prototype skill 功能重叠）

---

## Skills 迁移清单（27/72）

| 保留 skill | 用途 | Vibe 相关度 |
|---|---|---|
| `start` | 新用户引导 | 🔥 |
| `brainstorm` | 创意脑暴 | 🔥 |
| `quick-design` | 快速设计 | 🔥 |
| `prototype` | 快速原型 | 🔥 |
| `dev-story` | 故事实现 | 🔥 |
| `code-review` | 代码审查 | 🔥 |
| `design-review` | 设计审查 | ⭐ |
| `qa-plan` | 测试计划 | ⭐ |
| `smoke-check` | 冒烟检查 | 🔥 |
| `sprint-plan` | 冲刺规划 | ⭐ |
| `story-readiness` | 故事就绪检查 | ⭐ |
| `story-done` | 故事完成校验 | ⭐ |
| `create-epics` | Epic 创建 | ⭐ |
| `create-stories` | Story 拆解 | ⭐ |
| `architecture-decision` | ADR 记录 | ⭐ |
| `create-architecture` | 架构蓝图 | ⭐ |
| `estimate` | 工作量估算 | ⭐ |
| `balance-check` | 数值平衡 | ⭐ |
| `ux-design` | UX 设计 | ⭐ |
| `ux-review` | UX 审查 | ⭐ |
| `art-bible` | Art Bible | ⭐ |
| `asset-spec` | 资产规格 | ⭐ |
| `onboard` | 项目入职 | ⭐ |
| `help` | 帮助入口 | 🔥 |
| `map-systems` | 系统分解 | ⭐ |
| `design-system` | 系统设计 | ⭐ |
| `scope-check` | 范围检查 | ⭐ |

**注**：所有 skill 当前为英文原文，未中文化。使用策略：首次真正调用某 skill 时再按需改造，避免一次性翻译负担过大。

### 被剔除的 45 skills
- 全部 team-* (团队流水线，手动编排更合适)：team-audio, team-combat, team-level, team-live-ops, team-narrative, team-polish, team-qa, team-release, team-ui
- 所有 skill 测试/元技能：skill-test, skill-improve, test-evidence-review, test-flakiness, test-helpers, test-setup
- 运营/发布后期：hotfix, day-one-patch, launch-checklist, patch-notes, release-checklist, soak-test, regression-suite, changelog, localize
- 阶段检测/审计：project-stage-detect, content-audit, asset-audit, consistency-check, tech-debt, reverse-document, propagate-design-change, review-all-gdds
- 代理相关：adopt, bug-report, bug-triage, gate-check, milestone-review, perf-profile, playtest-report, retrospective, security-audit, setup-engine, architecture-review, create-control-manifest, sprint-status

---

## Templates 迁移清单（12/35）

| 保留 template | 用途 |
|---|---|
| `game-concept.md` | 游戏概念 |
| `game-design-document.md` | GDD |
| `game-pillars.md` | 核心 pillars |
| `architecture-decision-record.md` | ADR |
| `technical-design-document.md` | TDD |
| `level-design-document.md` | 关卡文档 |
| `sprint-plan.md` | 冲刺计划 |
| `test-plan.md` | 测试计划 |
| `release-notes.md` | 发布说明 |
| `art-bible.md` | Art Bible |
| `ux-spec.md` | UX 规格 |
| `changelog-template.md` | 更新日志 |

---

## Rules 改造清单（11 个全部改造 + 1 个新规则）

| 目标 | 源 | 主要改造 |
|---|---|---|
| `gameplay-code.md` | src/gameplay/** → scripts/gameplay/** | 路径改 Godot 式，示例 GDScript |
| `engine-code.md` | src/core/** → scripts/core/** | Autoload 白名单+Godot 4.6 特定 |
| `ai-code.md` | src/ai/** → scripts/ai/** | Godot 节点状态机/Navigation 示例 |
| `ui-code.md` | src/ui/** → scripts/ui/** | Control 节点+TranslationServer |
| `shader-code.md` | assets/shaders/** | 去除 Unity/UE 内容，仅 `.gdshader` |
| `test-standards.md` | tests/** | GUT/GdUnit4 + GDScript AAA 示例 |
| `data-files.md` | assets/data/** | `.tres` Resource 优先，JSON 次选 |
| `design-docs.md` | design/gdd/** → docs/design/gdd/** | 加 Godot 节点设计章节 |
| `prototype-code.md` | prototypes/** | GDScript 头标记格式 |
| `network-code.md` | src/network/** → scripts/network/** | 明确"默认单机" |
| `narrative.md` | 维持 | 加 Dialogic addon 建议 |

---

## Hooks 迁移清单（2/12 + 文档）

| 目标 | 源 | 状态 |
|---|---|---|
| `session-start.ps1` | `session-start.sh` | ✓ PowerShell 改写 |
| `detect-gaps.ps1` | `detect-gaps.sh` | ✓ PowerShell 改写 |

**放弃的 10 个 Hook**：pre-compact, post-compact, log-agent-start, log-agent-end, log-agent-stop, log-skill-usage, validate-assets, validate-commit, validate-naming, validate-skill-change

具体放弃原因见 `HOOK-ADAPTATION.md`。

---

## 知识资产迁移（复制保留原样）

- ✓ `docs/engine-reference/` — Godot 4.6 完整参考（VERSION.md + 4 份根文件 + 8 份模块文档）
- ✓ `docs/methodology/COLLABORATIVE-DESIGN-PRINCIPLE.md` — 协作方法论
- ✓ `docs/methodology/WORKFLOW-GUIDE.md` — 7 阶段流水线（57.85 KB 完整保留）

---

## 新增的配置与文档

- [新] `CLAUDE.md` — 项目主提示（Vibe 模式哲学 + AI 主动性边界 + 目录约定）
- [新] `.codebuddy/settings.json` — 全局配置（锁 Godot 4.6 + GDScript）
- [新] `docs/migration/USAGE-GUIDE.md` — 小白使用指南
- [新] `docs/migration/MIGRATION-CHANGELOG.md` — 本文
- [新] `docs/migration/HOOK-ADAPTATION.md` — Hook 适配记录
- [新] `README.md` — 项目 README
- [新] `commit_log.md` — 时间轴日志（初始条目）
- [新] `production/session-state/active.md` — 当前会话状态（模板）

---

## 待用户首次使用时决策的事项

以下事项在迁移时**有默认方案**，首次正式启动项目时再精细化：

1. **游戏 pillars**：`docs/design/pillars.md`（creative-director 在项目启动时产出）
2. **碰撞层约定**：延用 ai-no.1 的（1=Player 2=Enemy 3=Terrain 4=Projectile 5=Pickup 6=Trigger）
3. **输入动作**：延用 ai-no.1 的（move_left/right/up/down, jump, attack, interact, dash, pause, inventory）
4. **项目具体名字**：首次启动时 Vibe 主管会问
5. **测试框架**：推荐 GUT，待实际使用时技术总监批准 ADR

---

## 验证清单（使用前自检）

- [ ] `.codebuddy/agents/` 下有 16 个 `.md` 文件
- [ ] `.codebuddy/skills/` 下有 27 个子目录，每个含 `SKILL.md`
- [ ] `.codebuddy/rules/` 下有 11 个 `.md` 文件
- [ ] `.codebuddy/templates/` 下有 12 个 `.md` 文件
- [ ] `.codebuddy/hooks/` 下有 2 个 `.ps1` 文件
- [ ] `.codebuddy/settings.json` 存在且 engine=Godot, language=GDScript
- [ ] `CLAUDE.md` 在项目根目录
- [ ] `docs/engine-reference/` 下有 VERSION.md + modules/（8 份）
- [ ] `docs/methodology/` 下有 2 份 md
- [ ] `commit_log.md` 在项目根
- [ ] `production/session-state/active.md` 存在（即使空）

---

**迁移完成时间**：2026-04-29 10:00 UTC+8
**总耗时**：约 40 分钟
**产出文件总数**：约 70 个（16 agents + 27 skills + 12 templates + 11 rules + 2 hooks + 14 engine-ref + 2 methodology + 核心配置）
