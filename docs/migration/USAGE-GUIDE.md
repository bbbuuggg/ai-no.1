# Godot-Vibe-Studio 小白使用指南（新手必读）

> 本指南假定你从未用过 CCGS、对 Claude/CodeBuddy agent 机制也不熟悉。按本文一步步来即可。

---

## 第一部分：这套工具是什么？

想象你雇了一支 **16 人的游戏工作室**，但这个工作室住在你的 CodeBuddy 里。每个成员有自己的专业：

| 当你想要…… | 找哪位成员 |
|---|---|
| 聊一个全新的游戏想法 | **Vibe 主管** 或 **创意总监** |
| 设计一个系统 / 玩法 | **游戏策划** |
| 把设计落地成 GDScript | **GDScript 专家** |
| 搭场景树结构 | **场景架构师** |
| 做动画 | **动画师** |
| 写 shader 特效 | **着色器专家** |
| 规划进度 | **制作人** |
| 审代码 | **主程序** |
| 做测试 | **测试主管** |
| 定风格 | **美术指导** / **音频总监** |
| UI 和交互 | **用户体验主管** |
| 关卡布局 | **关卡设计师** |

**你永远不需要记住这 16 个人**。你只需要召唤 **Vibe 主管**（`vibe-lead`），它会帮你分流到正确的人。

---

## 第二部分：三分钟上手

### 第 0 步：把 Godot-Vibe-Studio 当作什么用？

**两种用法**（你现在在用的是用法 A）：

**用法 A：独立方法论仓**（当前状态）
```
d:/GodotGame/Claud-to-CodeBuddy/Godot-Vibe-Studio/   ← 这就是你现在的位置
```
这里存了所有"智能体定义、技能、规则、模板、方法论"。它**本身不是**一个 Godot 游戏项目，你不能双击打开 Godot 编辑器。

**用法 B：迁入你的实际 Godot 游戏项目**
当你要开发具体游戏时，把 `Godot-Vibe-Studio/.codebuddy/` 和 `Godot-Vibe-Studio/docs/` 两个目录**复制**到你的 Godot 项目根目录（比如 `d:/GodotGame/MyAwesomeGame/`）。复制后，CodeBuddy 会自动加载这 16 个 agent。

> **重要提醒**：如果你把它复制到 `d:/GodotGame/ai-no.1/`（你已有项目），会和现有的 `game-designer.md`（"游戏策划"）冲突。**先备份**那个文件，再复制。

### 第 1 步：验证 agent 是否被 CodeBuddy 识别

打开 CodeBuddy，在对话框输入：

```
@Vibe 主管 你好，介绍一下自己
```

如果 CodeBuddy 下拉菜单能出现"Vibe 主管"选项，说明 agent 加载成功。如果出不来，参考"故障排除"章节。

### 第 2 步：开始你的第一个游戏

直接对话即可：

```
我想做一个类似《星露谷物语》的农场模拟游戏，2D 像素风，单机。
```

Vibe 主管会：
1. 识别这是"新项目启动 + 方向探索"
2. 委派给 **创意总监** 帮你定 pillars
3. 再委派给 **游戏策划** 拆系统
4. 产出 `docs/design/gdd/game-concept.md` 草稿
5. 给你"下一步建议"：先做原型？先补完 GDD？先配置 Godot 项目？

**你只需要回答每次 AI 问你的 2-3 个问题**，它会自动推进。

---

## 第三部分：日常工作模式

### 模式 A：完全新项目

```
你 → "我想做 XX 游戏"
Vibe 主管 → 调 brainstorm skill + 召唤创意总监
→ 产出游戏概念
→ 召唤游戏策划产出 GDD
→ 召唤技术总监产出架构 ADR
→ 召唤 GDScript 专家开始第一个可玩原型
```

### 模式 B：已有 Godot 项目，想加新功能

```
你 → "我已有游戏，想加一个合成系统"
Vibe 主管 → 读已有 GDD + commit_log.md 了解现状
→ 召唤游戏策划补充合成系统 GDD
→ 召唤主程序审是否和已有系统冲突
→ 产出 user story 和任务清单
→ 召唤 GDScript 专家开始实现
```

### 模式 C：只想快速做个原型验证玩法

```
你 → "我想试试 GDScript 能不能轻松实现 platformer 控制"
Vibe 主管 → 召唤 GDScript 专家 + 场景架构师
→ 直接走 prototype skill（宽松规范）
→ 产出 prototypes/platformer/ 可运行场景
```

---

## 第四部分：最常用的 10 条对话模板（复制即用）

### 1. 启动新项目
```
启动一个新项目，我想做 [类型] 游戏，参考 [参考作品]，想实现 [核心机制]。
```

### 2. 设计一个系统
```
设计一个 [系统名] 系统，要求 [具体需求]，参考 [类似游戏]。
```

### 3. 实现一个功能
```
实现 [功能名]，设计文档在 docs/design/gdd/[文件].md。
```

### 4. 代码审查
```
审一下 scripts/gameplay/[文件].gd 有什么问题？
```

### 5. 搭场景结构
```
我要给 [玩家/敌人/UI] 搭一个场景树，它需要 [功能]。
```

### 6. 数值平衡
```
我的战斗系统玩家打怪 3 刀死，太快了，怎么调？
```

### 7. 性能问题
```
我的游戏卡顿，帮我分析可能原因。
```

### 8. 规划进度
```
我有 2 周时间，想做完 [功能清单]，帮我排冲刺。
```

### 9. 整理状态
```
整理一下我项目现在的进度。
```

### 10. 继续上次的工作
```
继续。
```
（Vibe 主管会读 `production/session-state/active.md` 自动恢复上下文）

---

## 第五部分：目录在干什么？（打开文件夹看一眼能懂）

```
Godot-Vibe-Studio/
├── CLAUDE.md                    ← 项目主提示（AI 每次会话都读这个）
├── .codebuddy/                  ← 所有 AI 智能体的定义
│   ├── settings.json           ← 全局配置（锁 Godot 4.6 + GDScript）
│   ├── agents/                  ← 16 个智能体（你可以 @ 召唤）
│   │   ├── vibe-lead.md        ← 主编排（默认入口）
│   │   ├── creative-director.md
│   │   ├── technical-director.md
│   │   ├── producer.md
│   │   ├── game-designer.md     ← 注意：和 ai-no.1 同名
│   │   ├── lead-programmer.md
│   │   ├── art-director.md
│   │   ├── ux-lead.md
│   │   ├── qa-lead.md
│   │   ├── audio-director.md
│   │   ├── godot-specialist.md
│   │   ├── godot-gdscript-specialist.md
│   │   ├── godot-shader-specialist.md
│   │   ├── godot-scene-architect.md  ← 新建
│   │   ├── godot-animation-specialist.md  ← 新建
│   │   └── level-designer.md
│   ├── skills/                  ← 27 个可调用"技能"（流水线）
│   │   ├── start/              ← 新用户引导
│   │   ├── brainstorm/         ← 创意脑暴
│   │   ├── quick-design/       ← 快速设计
│   │   ├── prototype/          ← 快速原型
│   │   ├── dev-story/          ← 故事实现
│   │   └── ...（22 个其他）
│   ├── rules/                   ← 11 条编码/设计规则
│   │   ├── gameplay-code.md    ← 玩法代码规范
│   │   ├── engine-code.md      ← 引擎代码规范
│   │   ├── ui-code.md          ← UI 代码规范
│   │   ├── ai-code.md          ← AI 代码规范
│   │   ├── shader-code.md      ← 着色器规范
│   │   ├── test-standards.md   ← 测试规范
│   │   ├── data-files.md       ← 数据文件规范
│   │   ├── design-docs.md      ← 设计文档规范
│   │   ├── network-code.md     ← 网络代码（默认单机，不用）
│   │   ├── prototype-code.md   ← 原型规范（宽松）
│   │   └── narrative.md        ← 叙事内容规范
│   ├── templates/               ← 12 个产出模板
│   │   ├── game-concept.md
│   │   ├── game-design-document.md
│   │   ├── architecture-decision-record.md
│   │   └── ...
│   └── hooks/                   ← 2 个会话钩子（PowerShell）
│       ├── session-start.ps1   ← 会话启动时加载上下文
│       └── detect-gaps.ps1     ← 检测文档缺口
├── docs/
│   ├── engine-reference/        ← Godot 4.6 完整知识库（只读）
│   │   ├── VERSION.md
│   │   ├── current-best-practices.md
│   │   ├── deprecated-apis.md
│   │   ├── breaking-changes.md
│   │   └── modules/             ← 8 大子系统文档
│   ├── methodology/             ← 2 篇核心方法论（只读）
│   │   ├── COLLABORATIVE-DESIGN-PRINCIPLE.md
│   │   └── WORKFLOW-GUIDE.md
│   └── migration/               ← 本次迁移的记录
│       ├── USAGE-GUIDE.md       ← 本文
│       ├── MIGRATION-CHANGELOG.md
│       └── HOOK-ADAPTATION.md
└── README.md
```

**你真正要读的只有 3 个**：
- 本文（USAGE-GUIDE.md）
- `CLAUDE.md`（5 分钟扫一眼了解"AI 被限定做什么")
- `README.md`（项目概览）

**其他都是给 AI 自己读的。**

---

## 第六部分：Vibe Coding 的 3 个"典型剧本"

### 剧本 1：凌晨两点灵感闪现

```
你：我想做一个"开局一条蛇"的 roguelike
Vibe 主管：好！识别为新项目创意探索。

我要和创意总监一起给你三个方向：
A) 经典贪吃蛇 + roguelike 随机关卡（安全）
B) 蛇作为玩家身体 + 器官成为装备（独特，推荐）
C) 多人合作一起操纵一条蛇（困难）

你喜欢哪个？为什么？
你：B
Vibe 主管：开工。调 quick-design，生成 docs/design/gdd/game-concept.md 草稿...

[5 分钟后]
Vibe 主管：✓ 概念文档已写入。推荐下一步：
1. 用 prototype skill 做个 30 分钟的移动+吃食物雏形
2. 用 art-bible 定视觉风格
3. 保存先睡觉，明天继续

你想做哪个？
```

### 剧本 2：周六下午埋头实现

```
你：把昨晚的蛇移动逻辑做了
Vibe 主管：[读 session-state/active.md]

✓ 识别上下文：昨日概念文档已完成，未开始编码
识别意图：实现原型
委派给：GDScript 专家 + 场景架构师

场景架构师：我建议的场景树：
Player (Node2D)
├── Head (Sprite2D, %Head)
├── Body (Node2D, %Body) ← 动态管理尾段
└── HitBox (Area2D, %HitBox)

GDScript 专家：配套的 player.gd 大致结构：
[显示代码骨架]

可以开始了吗？（会创建 prototypes/snake/player.tscn + player.gd）
你：开始
[实际写代码]
Vibe 主管：✓ 完成。验证方式：
1. 打开 Godot 4.6，导入 prototypes/snake/
2. 运行 player.tscn
3. 用方向键移动，应该能看到蛇头以每秒 N 格移动

想继续：吃食物逻辑 / 尾段增长 / 先存档？
```

### 剧本 3：卡 bug 求救

```
你：蛇移动有时候会卡住 1 帧
Vibe 主管：[识别为性能/bug 调试]
委派给：GDScript 专家 + 主程序

GDScript 专家：猜测 3 种可能：
1. _physics_process 里用了 get_tree().get_nodes_in_group() 导致树查询
2. 信号连接多次没断开
3. Tween 链没正确清理

要我看一下具体代码吗？
你：[贴代码]
GDScript 专家：定位到 #2，修复建议：...
你：改。
GDScript 专家：✓ 修复完成。更新 commit_log.md 记录："修复蛇移动 1 帧卡顿"。
```

---

## 第七部分：故障排除

### Q1. CodeBuddy 找不到 agent / @ 菜单里没有

检查：
1. `.codebuddy/` 目录是否在项目**根目录**？（不能在子目录）
2. 文件名是否是 `.md`（不是 `.txt`）？
3. YAML frontmatter 是否用 `---` 开头和结尾？
4. CodeBuddy 版本是否支持 agent 机制？（参考官方文档）

### Q2. agent 回答风格不像"游戏专家"

检查：
1. `CLAUDE.md` 是否在项目根？没有的话 AI 不会加载项目语境
2. 对话中是否明确 `@` 了某个 agent？没 @ 时 AI 可能用默认模板

### Q3. AI 要写 `.gd` 文件但我不想它碰工程

这是"平衡模式"的保护机制——它应该**先问你**再写 `.gd`。如果它直接写了，说明没读到 `CLAUDE.md` 的"平衡模式"约束。把以下一句明确丢给它：

```
重要：本项目启用平衡模式，写入 .gd/.tscn/project.godot 前必须得到我明确"可以"批准。
```

### Q4. Skill 是英文的，怎么办？

本次迁移先保留 skill 原文。首次真正调用某 skill 时再按需中文化——反正都是 AI 读，英文完全工作。

如果你想全部中文化，可以对 vibe-lead 说："把 `.codebuddy/skills/[skillname]/SKILL.md` 中文化"。

### Q5. Hook (PowerShell 脚本) 怎么触发？

**当前设计**：Hook 在 CodeBuddy 中**不会自动触发**（CodeBuddy 目前不支持 Claude Code 式的 hook 机制）。

两个使用方式：
1. **手动调用**：每次新开会话前，在终端 `pwsh .codebuddy/hooks/session-start.ps1`，把输出复制给 AI 做上下文
2. **CodeBuddy automation**：如果你的 CodeBuddy 版本支持 automation（定时任务），可以配置一个每次会话启动时跑的任务

详见 `docs/migration/HOOK-ADAPTATION.md`。

### Q6. 我想改 agent 的行为

直接编辑对应 `.codebuddy/agents/[agent].md` 文件即可。下次会话生效。

### Q7. 怎么只用其中 3-5 个 agent，砍掉其他的？

直接删除不要的 `.md` 文件。其他 agent 引用它时会"找不到"，你让 AI 修一下 Delegation Map 即可。

---

## 第八部分：下一步做什么？

**如果你现在还没有具体游戏想法**：
- 停在这，本 Studio 算准备完毕
- 下次有灵感时，回来跑一句"我想做 XX"

**如果你想立刻试一下**：
1. 在 CodeBuddy 打开 `d:/GodotGame/Claud-to-CodeBuddy/Godot-Vibe-Studio/`
2. 验证 @ 菜单能看到 16 个 agent
3. 说："启动一个新项目，我想做 [X]" —— 等 Vibe 主管分流

**如果你要迁入到已有 Godot 游戏**：
1. 备份现有 `.codebuddy/agents/game-designer.md`（或直接重命名）
2. 复制 `Godot-Vibe-Studio/.codebuddy/` → 你的游戏项目根
3. 复制 `Godot-Vibe-Studio/docs/engine-reference/` 和 `docs/methodology/` → 你的游戏项目 `docs/`
4. 在游戏项目根写一个指向本工具的 `CLAUDE.md`（可复制过去直接改几处）

---

## 附录：16 个 Agent 全貌

| 层级 | 中文名 | 文件 | 一句话用途 |
|---|---|---|---|
| T1 | Vibe 主管 | `vibe-lead.md` | 主编排默认入口，分流到其他专家 |
| T1 | 创意总监 | `creative-director.md` | 游戏愿景与 pillars 最终裁决 |
| T1 | 技术总监 | `technical-director.md` | 架构与技术选型最终裁决 |
| T1 | 制作人 | `producer.md` | 冲刺规划与范围管理 |
| T2 | 游戏策划 | `game-designer.md` | GDD、机制、数值、经济 |
| T2 | 主程序 | `lead-programmer.md` | 代码审查、API 设计、重构 |
| T2 | 美术指导 | `art-director.md` | Art Bible、风格、资产规格 |
| T2 | 用户体验主管 | `ux-lead.md` | UX 流、交互、可访问性 |
| T2 | 测试主管 | `qa-lead.md` | 测试策略、bug 分类、发布门 |
| T2 | 音频总监 | `audio-director.md` | 声音身份、音乐、SFX |
| T3 | Godot 专家 | `godot-specialist.md` | 引擎全局决策与最佳实践 |
| T3 | GDScript 专家 | `godot-gdscript-specialist.md` | GDScript 代码质量 |
| T3 | 着色器专家 | `godot-shader-specialist.md` | `.gdshader`、VFX、后处理 |
| T3 | 场景架构师 | `godot-scene-architect.md` | 场景树、节点、预制件 |
| T3 | 动画师 | `godot-animation-specialist.md` | AnimationPlayer、AnimationTree、Tween |
| T3 | 关卡设计师 | `level-designer.md` | 关卡布局、遭遇、节奏 |

---

**祝你 Vibe Coding 愉快！** 🎮

有任何问题，对 Vibe 主管说"我需要帮助"就好。
