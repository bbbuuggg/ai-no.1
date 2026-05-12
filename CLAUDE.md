# Godot-Vibe-Studio 项目主提示（CLAUDE.md）

> 本文件是 CodeBuddy / Claude 智能体在本项目中的**最高级项目提示**。任何 agent、skill、rule 都以本文件为根。

## 项目定位

本项目是从开源方法论仓库 **Claude-Code-Game-Studios (CCGS)** 迁移、精简、中文化后的"Godot Vibe Coding 套件"。它提供：

- **16 个 CodeBuddy 智能体**（4 层编排 + 10 域专家 + 2 新增 Godot 架构专家）
- **27 个核心 Skill**（Vibe 链路：脑暴→快设计→原型→Story→验收）
- **11 条精简规则**（Godot/GDScript 聚焦）
- **12 个模板**（GDD、架构文档、User Story、Sprint、Review 等）
- **Godot 4.6 完整引擎参考知识库**（8 大模块）
- **协作方法论 2 篇**（COLLABORATIVE-DESIGN-PRINCIPLE / WORKFLOW-GUIDE）

## 核心哲学（铭刻五条）

1. **协作优先（Collaborative Over Autonomous）**：AI 主动推进常规决策，但每个关键节点产出"决策清单"供用户 Review。
2. **文件即记忆（File-as-Memory）**：所有状态、决策、进度、上下文写入 `docs/`、`commit_log.md`、`production/session-state/active.md`，不依赖对话记忆。
3. **版本感知（Version Awareness）**：所有 Godot 代码建议必须引用 `docs/engine-reference/godot/VERSION.md`（锁定 4.6），禁止使用 `deprecated-apis.md` 中列出的 API。
4. **验证驱动（Verification-Driven）**：任何"已完成"声明都必须附可运行/可打开的证据（场景文件路径、测试脚本、截图建议）。
5. **分级评审（Tiered Review）**：方案 → Tier 2 主管 Review → Tier 1 总监盖章。

## 目录约定（Vibe 模式下硬约定）

```
Godot-Vibe-Studio/
├─ .codebuddy/
│  ├─ agents/          16 个智能体定义
│  ├─ skills/          27 个可调用技能
│  ├─ rules/           11 条编码/设计规范
│  ├─ templates/       12 个产出模板
│  ├─ hooks/           2 个 PowerShell 生命周期钩子（可选）
│  └─ settings.json    全局配置
├─ docs/
│  ├─ engine-reference/  Godot 4.6 原厂知识库（只读）
│  ├─ methodology/       2 篇核心方法论（只读）
│  ├─ migration/         迁移记录 + Hook 适配记录
│  └─ design/            【游戏项目实际产出】GDD、架构、Story
├─ production/
│  └─ session-state/     当前工作会话状态（active.md）
└─ commit_log.md         项目级时间轴日志
```

> 如本 Studio 被复制进入具体 Godot 项目根，`scenes/`、`scripts/`、`assets/` 为游戏项目自有，不属于 Studio 管辖。

## 智能体调度约定

- **默认主入口**：`vibe-lead`（Vibe 主管），所有未明确指定 agent 的请求由它分流
- **三层结构**：
  - **T1 总监**（4）：vibe-lead / technical-director / creative-director / producer
  - **T2 主管**（6）：game-designer / lead-programmer / art-director / ux-lead / qa-lead / audio-director
  - **T3 专家**（6）：godot-specialist / godot-gdscript-specialist / godot-shader-specialist / godot-scene-architect / godot-animation-specialist / level-designer

## GDScript 硬约束

- 唯一编程语言：**GDScript**（Godot 4.6 原生）
- 禁用：C#（已剔除 csharp-specialist）、GDExtension C++（已剔除 gdextension-specialist）
- 风格：`snake_case` 变量/函数、`PascalCase` 类名、`ALL_CAPS` 常量
- 类型标注：所有公共函数参数和返回值必须显式标注类型
- 信号优先：组件间通信优先用 `signal`，避免直接 `get_node()` 跨层引用
- 场景树：浅、可复用、单一职责

## AI 主动性边界（平衡模式）

**AI 自动决策（不询问）**：
- 目录结构、文件命名、文档组织
- 中文本地化、注释翻译
- Rule 中 Unity/UE 引用替换为 Godot
- GDScript 代码实现的具体写法选择
- 引擎无关的流程/模板调整

**必须用户确认**：
- 删减 agent / skill / rule / template
- 修改 Godot 项目硬约定（目录布局、碰撞层、输入映射）
- 写入 `project.godot`、场景 `.tscn`、脚本 `.gd` 等工程文件
- Tier 阶段性 Review 节点

## 关键索引

- 迁移背景与整体方案：`docs/migration/MIGRATION-PLAN.md`（由 artifact plan.md 同步）
- 迁移变更清单：`docs/migration/MIGRATION-CHANGELOG.md`
- Hook 适配记录：`docs/migration/HOOK-ADAPTATION.md`
- 协作原则底层方法：`docs/methodology/COLLABORATIVE-DESIGN-PRINCIPLE.md`
- 7 阶段流水线：`docs/methodology/WORKFLOW-GUIDE.md`
- Godot 4.6 版本锁定：`docs/engine-reference/VERSION.md`
- 当前会话状态：`production/session-state/active.md`
- 时间轴日志：`commit_log.md`

## 使用快捷入口

- 新需求进场 → 直接 @vibe-lead 或"我要做 XX"
- 快速原型 → `skill:prototype` 或 `skill:quick-design`
- 故事落地 → `skill:dev-story`
- 代码评审 → `skill:code-review`
- 项目巡检 → `skill:smoke-check`

详见 `docs/migration/USAGE-GUIDE.md`。
