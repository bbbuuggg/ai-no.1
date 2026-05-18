# A2 砍牌库 — 三方产出汇总与执行计划

> 日期：2026-05-14 14:55
> 上游决策：`docs/design/decisions/2026-05-14-bargaining-space-收敛.md`
> 用户拍板：A2 砍牌库 / B-2 + B-3 / 不做 B-1（Boss 全透明）
> 与会：game-designer / ux-lead / vibe-lead（兼工程拆解）

---

## 1. game-designer 产出（要点）

### 玩家 8 张牌库（3 攻 / 2 防 / 2 技 / 1 零费）

| # | 卡名 | 类型 | 费用 | 效果 |
|---|---|---|---|---|
| 1 | strike.exe | 攻 | 1 | 6 伤害 |
| 2 | pierce.exe | 攻 | 2 | 9 伤害，无视 3 护甲 |
| 3 | overload.exe | 攻 | 2 | 12 伤害，自伤 3 |
| 4 | firewall.def | 防 | 1 | 6 护甲 |
| 5 | mirror.def | 防 | 2 | 4 护甲 + 反弹本回合 50% 伤害 |
| 6 | scan.tec | 技 | 1 | 抽 2，下回合 +1 能量 |
| 7 | purge.tec | 技 | 2 | 弃 Boss 手牌随机 1 张（关键反制） |
| 8 | null_op | 工具 | 0 | 本回合不出牌，下回合首攻 +3 |

### Boss 8 张牌库（默认 Sentinel：3 攻 / 3 防 / 1 技 / 1 特殊）

详见 game-designer 报告。**克制矩阵**：
- `aegis`（免破甲）克 `pierce` → 玩家应换 `overload`
- `intercept`（全攻 -3）克 3 张攻击 → 玩家应 `null_op` 蓄力
- `purge` 可弃 `execute`（高伤处决） → 博弈高光

### 7 层 Rush 牌组策略

**每层独立 8 张**（共 7 套 56 张）。L1 教学 / L4 Glitch（不可预测）/ L7 Sovereign（**保留 1 张暗置**作为最终战难度跳跃 — 需用户额外确认是否接受这条妥协）。

### 平衡参数同步

| 参数 | 现值 | 推荐 |
|---|---|---|
| 玩家 HP | 60（已是） | 不变 |
| Boss HP | 55（已是） | **80**（game-designer 建议改为 80，让 5-7 回合战斗成立） |
| 能量 | 3 | 不变 |
| 抽牌 | 起手 3 / 每回合 3 | 不变 |
| 洗回 | 弃堆耗尽自动洗回 | **保留"本场已出过"标记**（用 `Combatant.full_deck` 已实现） |

### 第 4 回合心理样例（证明博弈成立）

> "Boss 已出 siege/bulwark/crush，浮层显示牌库剩 execute、aegis、regen、protocol_lock、intercept。手上 3 张里**必有** execute——我 HP 28，处决线 30。purge 锁死 execute，mirror 防其余，null_op 留下回合反打。"

→ 算得动 + 不无脑。

### 风险红线（3 条）

| # | 风险 | 规避 |
|---|---|---|
| 🔴 | 洗回后"已出"信息归零 | 保留"曾出 N 次"标记（**已有 `full_deck`**） |
| 🔴 | 8 张池 degenerate strategy | 三角克制硬约束 + 第一周 playtest |
| 🟡 | B 浮层信息过载 | 默认摘要，Shift 才展开全列表 |

---

## 2. ux-lead 产出（要点）

### B 键浮层重做（纵向 3 段，**不用 Tab，不用横向并列**）

```
┌──────── BOSS PROTOCOL [8] ────────┐
│ ▼ DEPLOYED  3/8        [⚔🛡⚙ 筛选] │
│  [T1 ATK]  [T2 DEF]  [T3 ATK]     │ ← 每张左上角 T1/T2/T3 回合标
│ ▼ IN HAND   3/8                   │
│  [▓back▓] [▓back▓] [▓back▓]       │ ← 牌背
│ ▼ DECK      2/8                   │
│  ▦ 2 cards remaining              │ ← 仅文字+图标
└────────────────────────────────────┘
```

**关键规格**：
- 浮层 70%×60% 居中，卡片 120×168，回合标 `T3` 必有
- 配色：DEPLOYED 品红 `#FF2E88` 80% / 手牌牌背 `#5A2A3E` 暗品红去饱和 / DECK `#2A1520` 最暗
- B 暂停游戏，0.2s 滑入

### B-2 玩家牌堆 HUD（左下角）

抽牌堆 🂠N（青蓝 #00E5FF）+ 弃牌堆 🗑N（**琥珀 #FFB400**，新增第三色位）
- 56×56 + 角标 20px，悬停外发光，点击复用 `deck_view_ui` Tab
- 数字变化 punch scale 1.3→1.0（150ms）

### B-3 回合 Toast（屏幕中略偏上）

```
┌─────── ROUND 3 RESOLVED ───────┐
│  YOU    [⚔ STRIKE]  ×2.0       │
│  BOSS   [🛡 GUARD]   ×0.5       │
│  ───────────────────────────    │
│  YOU  -8 HP    BOSS  -16 HP    │
└─────────────────────────────────┘
```

420×140，2.5s，倍率 ≥ ×2.0 字号 +30% 闪烁，📌 钉住功能 P1。

### 优先级

- **P0**：B 键浮层 DEPLOYED 区 + 回合标 / B-3 Toast 基础
- **P1**：B-2 牌堆图标 + 类型筛选
- **P2**：Toast 钉住 / 时间轴排序

### 反例 3 条（**绝对不做**）

1. ❌ Boss 手牌区加"猜测提示"（与 A2 决策矛盾）
2. ❌ B 浮层做成可拖动常驻小窗（信息密度太高）
3. ❌ Toast 默认钉住或停留 > 3s（节奏崩）

---

## 3. 工程拆解（vibe-lead 实地调研产出）

### 3.1 现状盘点

| 项 | 文件 / 位置 | 备注 |
|---|---|---|
| 玩家 20 张定义 | `autoload/card_database.gd:20-32` `get_player_starter_deck()` | 硬编码 `_copies(id, count)` 拼装 |
| Boss 25 张定义 | `autoload/card_database.gd:35-50` `get_boss_layer1_deck()` | **只有 layer1，没有 layer2-7** |
| 卡牌注册 | `card_database.gd:71-97` `_register_player_cards / _register_boss_layer1_cards` | 通过 `_reg(id, name, type, cost, desc, props)` 注册到 `all_cards` 字典 |
| 战斗装载 | `scripts/battle/blind_clash_scene.gd:161-168` `_setup_battle()` | `card_db.get_player_starter_deck()` / `get_boss_layer1_deck()` |
| 洗回逻辑 | `scripts/battle/combatant.gd:78-82` `_shuffle_discard_into_deck()` | 弃堆完整倒回 deck 并 shuffle |
| **"已出"信息** | `scripts/battle/combatant.gd:24,45` `var full_deck`，`_init` 时复制一份 | **天然不被洗回影响 — game-designer 风险 #1 已有现成解** |
| B 键浮层 | `scripts/battle/blind_clash_scene.gd:118-123` `_open_boss_deck()` + `scripts/ui/deck_view_ui.gd:66` `show_boss_deck()` | **当前是 deck+hand+discard 合并显示，未分区** |
| 玩家弃堆 UI 入口 | `scripts/ui/deck_view_ui.gd` Tab 浮层（按 Tab 打开） | **HUD 无常驻图标**——B-2 要补 |
| 回合结束信号 | 待确认（搜 `round_ended` / `_round_end`） | B-3 Toast 挂点 |
| HP 实际值 | `blind_clash_scene.gd:167-168` Player 60 / Boss 55 | **不是文档里的 80/100** —— GD 建议 Boss → 80 |
| 7 层 Rush | **不存在**（grep 无 floor/level/boss_rush 命中） | 需新增进度系统 |
| LLM Boss perception | `scripts/ai/llm/perception_builder.gd:115-131` 看 `boss.deck` 算 deck_count + type 分布 | **不需改代码**，但 prompt 模板要重写（牌库结构变了） |

### 3.2 改造拆解（按层分组）

#### 数据层

| 改动 | 文件 | 工时 |
|---|---|---|
| 玩家牌库改 8 张（按 GD 表注册新卡 + 改 `get_player_starter_deck`） | `autoload/card_database.gd:20-32, 71-81` | M |
| Boss L1 改 8 张 | `autoload/card_database.gd:35-50, 84-97` | M |
| 新增 7 层架构：`get_boss_layer_deck(floor: int) -> Array[CardData]` + L1-L7 共 7×8=56 张数据 | `autoload/card_database.gd` 新方法 + `_register_boss_layerN_cards()` × 6 | XL（每层都要 GD 设计） |
| 卡数据扩展（mirror 反弹、purge 弃 Boss 手牌、null_op 跳回合） | `scripts/data/card_data.gd` 加字段 + `clash_resolver.gd` 处理 | M |

#### 战斗逻辑

| 改动 | 文件 | 工时 |
|---|---|---|
| 8 张池洗回边界（必然多次洗回，确认 `_shuffle_discard_into_deck` 工作正常） | `scripts/battle/combatant.gd:78-82` | L（已正确） |
| **"本场已出过"统计**：通过 `full_deck − hand − deck` 实时算（不需新增数据） | `scripts/battle/blind_clash_scene.gd` 新加辅助方法 | L |
| HP 调整 Boss 55 → 80（如 GD 推荐） | `blind_clash_scene.gd:168, 172` | L |
| `mirror.def` 反弹 50% 伤害 | `scripts/battle/clash_resolver.gd` 新增 reflect_percent 字段处理 | M |
| `purge.tec` 弃 Boss 手牌随机 1 张 | `clash_resolver.gd` + `combatant.gd` 加 force_discard_random | M |
| `null_op` 跳回合 + 下回合首攻 +3 | `clash_resolver.gd` + `combatant.gd` 状态字段 | M |
| 多层进度路由（floor 状态 + 战斗结束后切下一层） | 新增 `autoload/run_state.gd` 单例 + `blind_clash_scene._on_battle_end` | L（不阻塞 P0，可后做） |

#### UI 层

| 改动 | 文件 | 工时 |
|---|---|---|
| **B 浮层重做 3 段分区**（DEPLOYED + IN HAND + DECK） | 新建 `scripts/ui/boss_protocol_view.gd` + `.tscn`，替换原 `deck_view_ui.show_boss_deck` 调用 | L（按 UX 规格 1-2 天） |
| DEPLOYED 区每张挂"第 X 回合"标记 | 需 battle 层新增"出牌历史"List：`var played_history: Array[Dictionary] = [{turn, card, actor}]`，`apply_clash_pair_at` 时 push | M |
| 类型筛选（⚔🛡⚙ 三按钮） | `boss_protocol_view.gd` UI 逻辑 | L |
| **B-2 HUD 牌堆图标**（左下角，🂠 抽 / 🗑 弃，复用 deck_view Tab 弹层） | 新建 `scripts/ui/deck_hud_widget.gd` + 挂载到主场景左下 | M |
| **B-3 回合结算 Toast** | 新建 `scripts/ui/round_resolve_toast.gd`，监听战斗 `round_ended` 信号触发 | M |
| 旧 InfoLabel/伤害飘字与 Toast 冲突处理（Toast 期间 InfoLabel 下移 160px） | `scripts/ui/info_label.gd` 加 push/pop 接口 | L |

#### 调试 / 测试

| 改动 | 文件 | 工时 |
|---|---|---|
| F4-F12 debug 键不需扩展（已支持) | — | — |
| 新增"打印当前 8 张牌库分布"调试键（如 F11） | `blind_clash_scene._unhandled_input` | L |
| Playtest 用快速重启键（已可用 Esc 回到主菜单） | — | — |

### 3.3 推荐实施顺序（4 个 sprint）

#### Sprint 1（数据层先行，UI 不动 — 1.5 天）
- ✅ 玩家牌库 20 → 8（`get_player_starter_deck` 改写 + 8 张数据注册）
- ✅ Boss L1 牌库 25 → 8
- ✅ Boss HP 55 → 80
- ✅ 老 UI 不变，跑通战斗确保不崩
- **可测试目标**：能开战、能打完、Boss 用 8 张池 AI 决策不报错
- **产出**：可运行的 v0.5.0-alpha

#### Sprint 2（B-3 Toast + B 浮层最小可用版 — 2 天）
- ✅ `played_history` 数据收集
- ✅ B 浮层 3 段分区（DEPLOYED 含回合标）+ 数据接通
- ✅ B-3 Toast 基础版（无钉住）
- **可测试目标**：内测 1 局，体验"博弈感是否回来"
- **产出**：v0.5.0-beta，**这一版应当能让导师看到改善**

#### Sprint 3（B-2 牌堆图标 + 类型筛选 + 新卡效果 — 2 天）
- ✅ B-2 左下 HUD 图标
- ✅ B 浮层类型筛选
- ✅ `mirror` / `purge` / `null_op` 新效果实现
- **可测试目标**：完整 8 张池博弈循环
- **产出**：v0.5.0-rc

#### Sprint 4（7 层架构 + L2-L7 牌组 — 5-7 天，**可独立后做，不阻塞试玩**）
- ✅ `RunState` 单例
- ✅ L2-L7 共 6×8=48 张 Boss 牌设计 + 注册（GD 重负担）
- ✅ 战胜后切层流程
- **可测试目标**：完整 7 层 Boss Rush
- **产出**：v0.5.1

### 3.4 风险评估

| 等级 | 风险 | 规避 |
|---|---|---|
| 🔴 高 | LLM Boss prompt 仍按"25 张大池"假设训练（"我的牌库有 25 张，攻击占 10 张..."）—— 砍到 8 张后 LLM 决策可能失准 | Sprint 1 完成后立即跑 3 局看 LLM log，必要时改 `scripts/ai/llm/prompts/*.gd` 模板 |
| 🔴 高 | 7 层架构当前**完全不存在**——若用户期望"试玩版"包含完整 7 层，工时翻倍 | **建议先发 1 层 + B 浮层透明化**给导师看博弈感是否回来，7 层放下个里程碑 |
| 🟡 中 | `mirror.def` 反弹 50% 在暗出对决"伤害已计算 + 翻面"的时序里如何插入？需要 GD 跟 lead-programmer 联调时序 | Sprint 3 实施前先做 1 小时设计 review |
| 🟡 中 | 玩家从 20 张缩到 8 张，可能感觉"无构筑深度" — 与 docs/design/gdd 描绘的"卡组构筑"存在张力 | game-designer 需评估是否保留奖励/解锁系统，或干脆改为"每层之间换 1-2 张"的轻构筑 |
| 🟢 低 | 现有 `full_deck` 字段在洗回时不被影响 — 已验证 | — |
| 🟢 低 | 调试键 / playtest 流程 | 现有完善 |

### 3.5 工时总估

| 范围 | P50 | P90 |
|---|---|---|
| Sprint 1-3（不含 7 层 Rush） | **5-6 人日** | 8 人日 |
| Sprint 1-4（含完整 7 层） | 12 人日 | 18 人日 |

**假设**：单人开发 / GD 与 P 同一人 / 美术资源不阻塞（卡牌沿用现有图或文字占位）。

---

## 4. 待用户拍板的 3 个执行阶段决定

| ID | 问题 | 推荐 | 用户拍板（2026-05-14 15:33） |
|---|---|---|---|
| **E-1** | 试玩版只发 1 层（Sprint 1-3，5-6 天）还是必须 7 层（12+ 天）？ | 只发 1 层 | ✅ **1 层**（Sprint 1-3 给导师看 v0.5.0-beta） |
| **E-2** | L7 是否接受 GD 提议的"保留 1 张暗置协议"作为终极战变奏？ | 同意 | ✅ **同意**（L7 落地，Sprint 4） |
| **E-3** | 玩家 8 张是固定还是允许"每层间换 1-2 张"轻构筑？ | 固定 8 张 | ⚠️ **允许轻构筑**（vibe-lead 调度：落在 Sprint 4，不进 Sprint 1） |

---

## 8. 拍板后的执行调度（vibe-lead 决策）

**用户 E-3 选了"允许"，但落点不是 Sprint 1**，原因如下：

| 维度 | 固定 8 张 | 轻构筑 |
|---|---|---|
| Sprint 1 工时影响 | +0 | +2~3 人日（牌池设计 + 选牌 UI + 平衡） |
| 关键风险 | 无 | 引入构筑空间可能稀释博弈纯度，需要 game-designer 重新做平衡矩阵 |
| 与"先验证博弈感"目标的契合度 | 完全契合 | 引入混淆变量 |

**调度结论**：
- **Sprint 1-3**：玩家 8 张**固定**（按 GD 当前 8 张表）。先证明博弈感本身。
- **Sprint 4（与 7 层架构同期）**：引入轻构筑——每过 1 层从 3 张候选里选 1 张换入；这要求 game-designer 在 Sprint 3 末出 12-15 张玩家牌池（含 8 张核心 + 4-7 张备选）。

如此 E-3 不阻塞关键路径，但承诺会兑现。**用户如要求 E-3 立即上 Sprint 1，请明确推翻此调度。**

---

## 5. 推荐立刻动作

1. ✅ **不必再开会**——三方信息齐了，直接进 Sprint 1
2. **下一步**：用户对 E-1/E-2/E-3 拍板 → 派 lead-programmer 写 Sprint 1 卡牌数据 + 改 `card_database.gd`
3. **同步**：game-designer 把 Boss L2-L7 牌组放进设计 backlog（不阻塞 Sprint 1-3）
4. **文档**：Sprint 3 完成时更新 `docs/design/gdd/03-card-data-layer1.md` + `04-blind-clash-revision.md` + `06-deck-revision-a2.md`（新建）
