# GDD-08：MIRROR 进度系统 — 升级替换 + 牌库互换

> **版本**：v0.8.1-locked （2026-05-18 用户拍板：流程重构互换前置于升级）
> **取代关系**：在 GDD-04（BP 单回合）+ GDD-06（元素+光暗）之上新增"跨回合进度层"，不修改这两份文档的核心规则
> **核心情感锚点**：「**对镜博弈 / Mirror Duel**」(creative-director 定调)
> **项目主标签升级为**："与会成长的 AI 对镜博弈"

---

## 0. 锁定决策一览（用户拍板，不可改）

| ID | 决策 | 出处 |
|---|---|---|
| Q1 | **互换：整套牌库 + 5s 预览** | 用户 = A |
| Q2 | **4 选 2：玩家先挑 1 给自己 → 剩 3 张挑 1 给 Boss（顺序流程）** | 用户 = C |
| Q3 | **单 Run 上限 5 轮** | 用户 = A |
| Q4 | **失败 = 单次死即结算（无续命）** | 用户 = A |
| Q5 | **升级牌池起步 12 张**（4 类 × 3 张）| 用户 = B |
| Q6 | **Boss 名从一开始就叫 MIRROR**（不做演化阶梯）| 用户 = C |
| **🔒 RULE-Z** | **"零膨胀替换"原则：每次升级必须替换牌库中现有的一张牌，牌库总数永远 13 张** | 用户本轮新加 |
| NEW-Q1 | **结构升级不消耗牌库替换次数**（设为同 Run 仅 1 张防滚雪球）| 用户 = A |
| NEW-Q2 | **奖励界面完全开放 Boss 牌库查看** | 用户 = A |
| FLOW | **先互换牌库，再选择升级**（互换前置于升级阶段）| 用户本轮拍板 |

> **RULE-Z 的设计立柱地位**：等同于 GDD-04 的 "13 张牌库 / HP 25 / 6 候选 / 4 槽 Pick"。任何后续提案如要破坏此规则，等同于推翻整个进度系统的可读性与博弈密度，必须重开决策。

---

## 1. Overview

**MIRROR 进度系统**：玩家击败 Boss 后，**先互换双方整套 13 张牌库**（玩家拿到 Boss 旧牌库，Boss 拿到玩家旧牌库），然后进入"4 选 2 替换升级"——挑 1 张升级给自己（替换当前己方牌库 = ex-Boss 牌库中已有的某一张），再从剩 3 张中挑 1 张给 Boss（替换当前 Boss 牌库 = ex-玩家牌库中玩家指定的某一张）。下一轮战斗，玩家用 Boss 旧牌库 + 自己给自己的升级，对战 Boss 用玩家旧牌库 + 玩家给 Boss 的升级。

> 这是「**自己挖坑给自己跳**」的博弈结构 —— 互换后你先拿到对方的牌库，再在上面动手脚。你升级自己时是在改造一张**你不熟悉的牌库**（因为它是 Boss 的），而你给 Boss 的升级则加在了**你曾经的牌库**上（下一轮 Boss 用它打你）。每次升级都是在"我即将使用"和"对手即将使用"之间做价值权衡。

5 轮封顶，连续击败次数即玩家成就度。

---

## 2. Player Fantasy

### 2.1 MDA 拆解

- **核心动力学（Mechanics）**：替换升级（牌库零膨胀）+ 双向博弈分配 + 强制互换
- **关键动态（Dynamics）**：玩家被迫预演"下一轮我会变成对手"
- **目标美学（Aesthetics）**：Challenge（博弈强度）+ Expression（构筑选择）+ Reflection（自我对决的反思）

### 2.2 玩家时刻地图（5 轮典型 Run）

| 时刻 | 玩家心声 | 情感强度 |
|---|---|---|
| Round 1 胜 | "我赢了！牌库要交换了！" | 满足+好奇 |
| Round 1 互换 | "等等……我现在拿的是 Boss 的牌库？这张牌怎么用？" | 陌生感 |
| Round 1 升级 | "+2 伤害的烈日给自己这副新牌库——我得先搞清楚这牌有什么；再给 Boss 一张回响焰，反正已经不是我的牌库了" | 决策 |
| Round 2 开局 | "我在用 Boss 旧牌库 + 自己的升级打 Boss，Boss 在用我旧牌库 + 我给的升级打我" | **顿悟（对镜瞬间）** |
| Round 2 胜（艰难） | "差点输……刚才我给 Boss 加的那张牌真的伤我" | 紧张-释放 |
| Round 3 升级 | "这次我要克制 Boss 拿到的牌——它现在用我旧的水系防御，我给它一张暗黑火攻让它阵营冲突" | 高级博弈 |
| Round 5 胜（完美 Run）| "我撑过 5 轮——我已经把自己的牌库改造成对手的样子了" | 史诗感 |
| Round X 失败 | "我连胜 N 次。下次我会更聪明地分配升级" | rogue-lite 启动 |

### 2.3 NULL Protocol 独有的"自我对决"美学

普通 rogue-lite："我变强 → 我打更强的怪"
**MIRROR 模型**："我变强 → 我变成更强的怪 → 我必须打败昨天的我"

这是**项目辨识度的决定性差异**。

---

## 3. Detailed Rules（核心流程，无歧义）

### 3.1 一个完整 Run 的状态机

```
        ┌──────────────────────────────────────┐
        │  Run 启动（玩家选"挑战 MIRROR"）     │
        │  · 玩家牌库 = 13 张基础（GDD-06）     │
        │  · Boss 牌库 = 13 张基础（对称）      │
        │  · round_index = 1                   │
        │  · victory_streak = 0                │
        └──────────────────────────────────────┘
                        ↓
   ╔════════════════════════════════════════════════╗
   ║   战斗回合（沿用 GDD-04 BP 模式 + GDD-06）      ║
   ║   · 6 候选 → Pick 4 → 翻盅 → 第 6 回合枯竭     ║
   ║   · LLM Boss AI 用扩展感知（含进度上下文）     ║
   ╚════════════════════════════════════════════════╝
                        ↓
              ╭─────────╨─────────╮
        玩家失败                玩家胜利
              ↓                    ↓
   ┌──────────────┐    ┌──────────────────────────┐
   │ FAILURE_END  │    │  victory_streak += 1      │
   │ 显示连胜 N   │    │  if round_index >= 5:     │
   │ + 最强 build │    │      → PERFECT_RUN_END    │
   │ 截图         │    │  else:                   │
   │ + "再来一次" │    │      → 进入互换阶段       │
   └──────────────┘    └──────────────────────────┘
                                    ↓
   ╔════════════════════════════════════════════════╗
   ║   牌库互换（SWAP）                             ║
   ║   · player.deck ↔ boss.deck（整套 13 张）     ║
   ║   · 双方弃牌堆/手牌清空                        ║
   ║   · 双方 HP 重置（玩家 25，Boss 按缩放公式）   ║
   ║   · 双方能量/护甲重置                           ║
   ║   · round_index += 1                           ║
   ║   · 互换动画（~2s 轰然交换）                   ║
   ╚════════════════════════════════════════════════╝
                        ↓
   ╔════════════════════════════════════════════════╗
   ║   升级阶段（REWARD_SCREEN）                    ║
   ║   阶段 A：从 12 张池随机抽 4 张候选            ║
   ║   阶段 B：玩家挑 1 张给自己 →                  ║
   ║           选自己牌库（已互换后）中要被替换的 1 张║
   ║   阶段 C：剩 3 张里玩家挑 1 张给 Boss →        ║
   ║           选 Boss 牌库（已互换后）中要被替换的1张║
   ║   阶段 D：升级总结（双方最终牌库 + 高亮新升级） ║
   ╚════════════════════════════════════════════════╝
                        ↓
                   （回到战斗循环）
```

> **流程关键变化**：互换前置于升级。玩家先拿到 Boss 的牌库（陌生感），然后在**这张陌生牌库上做升级决策**。这比"先升级再互换"更直觉——你升级的是自己即将使用的牌，给 Boss 的升级也是加在 Boss 即将使用的牌上。

### 3.2 升级阶段精确流程（每一帧）

> **前置条件**：牌库已互换完成，玩家当前持有 ex-Boss 牌库，Boss 当前持有 ex-玩家牌库。HP/能量已重置。

**阶段 A：候选生成**（场景切换 → REWARD_SCREEN，~0.5s 淡入）
- 从 12 张升级牌池中**无重复**随机抽 4 张
- 4 张同时翻面亮出（可读 + 悬停显示 tooltip）
- 同屏右上角持续显示："**当前牌库 (13/13)** · 我方牌库[查看] · MIRROR 牌库[查看]（完全开放）"
- 玩家可随时点查看牌库按钮打开浮层（双方牌库均完全可见，NEW-Q2=A）

**阶段 B：玩家自选**
- 顶部 banner：「**第 1 步 / 共 2 步：选 1 张给自己**」
- 玩家点 4 张中任意 1 张 → 该牌高亮 + 飞向"我方"槽
- 弹出"**选择要被替换的牌**"模态：玩家当前牌库（ex-Boss 牌库）13 张以 Grid 显示，玩家点 1 张 → 该牌灰化 + 飞向"弃牌"动画
- **不可逆**：选择确认后立即执行，不提供"再考虑一下"撤销
- 玩家牌库现在仍是 13 张（替换完成）

**阶段 C：玩家给 Boss**
- 顶部 banner：「**第 2 步 / 共 2 步：选 1 张给 MIRROR**」
- 剩余 3 张展示 + Boss 牌库[查看] 按钮持续可用（完全开放）
- 玩家点 3 张中任意 1 张 → 飞向"对方"槽
- 弹出"**选择 MIRROR 牌库中要被替换的牌**"模态：Boss 当前牌库（ex-玩家牌库）13 张以 Grid 显示
- 玩家点 1 张 → 该牌从 Boss 牌库被替换
- Boss 牌库现在仍是 13 张

**阶段 D：升级总结**
- 顶部 banner：「**升级完成——准备下一轮**」
- 屏幕分上下两栏：上=玩家最终 13 张（含本轮新升级，金色描边）/ 下=Boss 最终 13 张（含本轮新升级，红色描边）
- 点击"开战"按钮或 3s 后自动进入下一回合战斗
- Boss 名固定显示 "MIRROR"（不做演化）

### 3.3 互换的精确语义（互换前置于升级）

**整套牌库互换**在升级阶段**之前**执行，意味着：
- `player.deck` ↔ `boss.deck`（13 张完全交换）
- `player.discard_pile` 清空，`boss.discard_pile` 清空（互换后等价于"新一局开始"）
- `player.hand` 清空，`boss.hand` 清空
- `player.hp = 25, boss.hp = 25 + (round_index) × 3`（HP 重置，Boss 按缩放公式，此时 round_index 已 +1）
- `player.energy = 6, boss.energy = 6`（能量重置）
- `player.armor = 0, boss.armor = 0`
- `round_index += 1`（互换时推进，下一轮战斗直接使用新 round_index）
- 跨回合保留的字段：`run_state.victory_streak`、`run_state.round_index`、`run_state.upgrade_history`（用于 LLM perception）

> 注：HP 重置是"每轮独立"语义。互换时 round_index 已 +1，Boss HP 按新 round_index 缩放。升级阶段在互换后进行，升级操作直接作用于互换后的牌库。

### 3.4 异常与可中止条件

| 场景 | 处理 |
|---|---|
| 玩家在阶段 B 选完后突然 Alt+F4 | 持久化 `run_state` 到 `user://run_state.tres`，下次启动时读回继续（推荐 v0.8.1 实现，v0.8.0 简化为内存即可、关游戏丢失）。注意：互换已在升级前执行，重载后应从升级阶段继续 |
| 玩家点"再考虑一下" | **不提供**。设计上加深"决策即承诺"的博弈感 |
| 玩家想替换的牌恰好就是刚收到的升级 | 允许（自助式回退），但 UI 给"确定要替换刚拿到的升级吗?" 二次确认 |
| 互换后玩家发现手里牌全不熟 | **这是设计意图**。陌生感=对镜博弈的起点。升级阶段就是在陌生牌库上做价值判断 |
| Boss 牌库要被替换的牌恰好被玩家"留着想换给自己" | **无关联限制**。两次替换是独立的。互换后你选的是 Boss 当前牌库（=你旧牌库）中的牌 |
| 12 张池在抽取时不足 4 张 | 不可能发生（每次重新随机抽 4 张，不维护"已被抽过"状态）|
| 升级牌可重复抽到吗 | **同 Run 内同一升级牌可重复出现在候选**（每次重新随机抽 4 张）|
| 升级牌效果与基础牌冲突 | 不可能。升级牌池设计时已规避（详见 §6）|

---

## 4. Formulas

### 4.1 牌库总数公式（RULE-Z 强制约束）

```
∀ round, ∀ side ∈ {player, boss}:
    side.deck.size() + side.hand.size() + side.discard_pile.size() == 13
```

### 4.2 升级牌力量曲线（数值锚定）

> 锚定参考：基础牌中"业火"= 2 费 9 伤、"烈日"= 2 费 7 伤、"回声盾"= 1 费 8 甲

```
单次升级牌的"价值上限" = 替换掉的基础牌价值 × 1.4 ~ 1.6
```

例如 "烈日"（2 费 7 伤）被升级牌"业火 PLUS"（2 费 11 伤）替换 → 价值提升 ~1.57 倍，即玩家"赚到"约 4 点伤害收益。

**5 轮累积**：玩家连胜 5 次 = 替换 5 张牌 + Boss 也替换 5 张 → 双方各 5/13 ≈ 38% 牌库被改造。

### 4.3 Boss HP 缩放公式（防止后轮过快/过慢）

```
boss_max_hp(round_index) = 25 + (round_index - 1) × 3
```

| Round | Boss HP |
|---|---|
| 1 | 25 |
| 2 | 28 |
| 3 | 31 |
| 4 | 34 |
| 5 | 37 |

> 玩家 HP 始终 25。这意味着后轮 Boss 越来越"硬"——补偿了玩家升级带来的强度膨胀，同时提升完美 Run 的难度感。

### 4.4 第 6 回合枯竭机制（沿用 GDD-04，不调整）

每轮战斗的第 6 回合开局双方 -1 HP（无视护甲）继续。后轮 Boss HP 上调后，枯竭压力天然递增，无需额外修改。

### 4.5 完美 Run 计算

```
victory_streak == 5 → PERFECT_RUN
完美 Run 数（存档可选）：累计完美 Run 次数
最长连胜（存档）：max(victory_streak across all runs)
```

---

## 5. Edge Cases

| # | 场景 | 处理 |
|---|---|---|
| E1 | 玩家替换自己牌库时所有牌都"不舍得换" | UI 不提供"放弃升级"选项——升级是强制承诺。设计意图：让玩家学会做权衡 |
| E2 | 玩家想给 Boss 的牌恰好已经在 Boss 牌库中（重复）| 允许。Boss 牌库变成 "12 张 + 2 张同名"，机制无破绽 |
| E3 | 玩家给 Boss 的升级牌效果"对 Boss 反而是 buff 自己"（如 +1 抽牌）| 已在升级牌池设计时规避——所有升级"双向价值都成立"，详见 §6 双向价值表 |
| E4 | 升级牌互相矛盾（如同时给"+1 能量上限"+ "起始能量+1"）| 在同 Run 内可叠加。这是博弈的一部分，玩家需自己评估是否两次都拿这种结构升级 |
| E5 | LLM 调用全部失败（5 轮中没有任何 reasoning）| 沿用 Epic-BP-5 的 fallback 链——降级到规则 AI。完美 Run 仍可达成，仅缺少 reasoning 红字 |
| E6 | 互换后双方 0 费立即牌堆叠 | 当前 0 费牌仅 1 张（c_inspiration_surge），玩家/Boss 各自牌库都有 1 张。互换后一方仍只有 1 张，不会堆叠。**升级牌池不允许新增 0 费立即牌**（红线）|
| E7 | 玩家在阶段 B 替换掉了那张唯一的 0 费牌 | 允许。这是合法策略——但代价是失去过牌能力。Boss 在互换后会拿到这张被改造的牌库，双方对称受制 |
| E8 | 替换升级后牌库元素分布严重失衡（火 8 + 木 5）| 允许。失衡=博弈代价。LLM 感知会获悉这一点并影响决策 |
| E9 | 玩家在阶段 D 升级总结时突然反悔 | 不提供反悔。升级总结只是信息展示，不是决策点 |
| E10 | 第 5 轮 Boss HP=37，玩家用互换后的陌生牌库打不过 | 这是 RULE-Z + 互换机制的纯风险。Mitigation：升级阶段就是在陌生牌库上补强；Boss HP 缩放数值可调（见 §7 Tuning Knob T2）|

---

## 6. 升级牌池草案（12 张起步，每张满足"双向价值约束"）

> 命名风格：赛博/协议感（NULL_REF / OVERFLOW / SHARD 等），保持项目辨识度
> 双向价值标注：**[给自己=A 价值 / 给 Boss=B 价值]**

### 6.1 数值升级类（3 张）

| ID | 名称 | 效果 | 估值 | 双向博弈分析 | 可重复 |
|---|---|---|---|---|---|
| `up_overflow` | OVERFLOW | 替换基础攻击牌 → cost +0, dmg +2 | +2 dmg ≈ +50% 单卡输出 | **A**：自己输出爆表 / **B**：Boss 多 2 伤压你；都强但不偏向 | ✅ |
| `up_shard` | SHARD | 替换基础防御牌 → cost +0, armor +2 | +2 armor ≈ +33% 单卡防御 | **A**：自己更稳 / **B**：Boss 更难打；都中性偏防 | ✅ |
| `up_caffeine` | CAFFEINE | 替换基础牌 → 该牌额外效果"使用后下回合 +1 能量上限"（永久绑定该牌）| 跨回合资源，~1.2 倍价值 | **A**：续航爽 / **B**：Boss 中后期更可怕；后轮博弈 | ❌（同 Run 仅 1 张）|

### 6.2 属性升级类（3 张）

> 改变某张牌的元素或光暗 → 影响 GDD-06 三角克制 + 2:2 协同

| ID | 名称 | 效果 | 估值 | 双向博弈分析 | 可重复 |
|---|---|---|---|---|---|
| `up_polarity_flip` | NULL_REF | 替换基础牌 → 光↔暗反转，其他不变 | 改变 2:2 协同结构 | **A**：调整自己光暗比触发 ×2.0 / **B**：破坏 Boss 光暗结构；纯结构博弈 | ✅ |
| `up_element_water` | HYDRO_INJECT | 替换基础牌 → 元素改为 WATER（保持 dmg/armor）| 改克制方向 | **A**：让自己多一张水克火 / **B**：让 Boss 在反水时被你火克；视当前牌库结构 | ✅ |
| `up_element_fire` | PYRO_INJECT | 替换基础牌 → 元素改为 FIRE（保持 dmg/armor） | 同上 | 镜像 HYDRO_INJECT | ✅ |

### 6.3 关键字升级类（3 张）

> 给基础牌加一个关键字效果，不改基础数值

| ID | 名称 | 效果 | 估值 | 双向博弈分析 | 可重复 |
|---|---|---|---|---|---|
| `up_lifesteal` | PARASITE | 替换基础攻击牌 → 该牌附加"造成伤害的 50% 回血" | 续航 +50% | **A**：自己爆肝战车 / **B**：Boss 难以处理；中后期偏强但平衡 | ❌（同 Run 仅 1 张）|
| `up_pierce` | NULL_PIERCE | 替换基础攻击牌 → 该牌附加"无视护甲" | 破甲 | **A**：破 Boss 的盾 / **B**：Boss 直接砸你脸；都强但镜像对称 | ✅ |
| `up_reflect` | KICKBACK | 替换基础防御牌 → 受击时反弹 3 点伤害 | 反伤 +3 | **A**：被 Boss 攻就反伤 / **B**：你攻 Boss 就反伤；纯对称博弈 | ✅ |

### 6.4 结构升级类（3 张，影响整局而非单卡）

> 这类升级**不替换牌库中的牌**，而是改变战斗规则。但为了维持 RULE-Z（牌库 13 张），玩家**仍然需要替换牌库中一张牌为"已使用过的标记牌"**——细则见 §6.5。

| ID | 名称 | 效果 | 估值 | 双向博弈分析 | 可重复 |
|---|---|---|---|---|---|
| `up_struct_energy` | KERNEL_BOOST | 该方起始能量 +1（每场战斗永久）| ~1.3 倍战斗节奏 | **A**：自己更灵活 / **B**：Boss 更暴力；都强 | ❌（同 Run 仅 1 张）|
| `up_struct_pickslot` | EXTRA_LOOP | 该方 BP 阶段抽 7 候选（仍 Pick 4） | 决策空间 +1 | **A**：选择更多 / **B**：Boss 选择更多；都博弈 | ❌（同 Run 仅 1 张）|
| `up_struct_zerocost` | RECURSION | 该方 0 费立即牌每回合上限 2→3 | ~1.5 倍过牌 | **A**：续航爆表 / **B**：Boss 续航爆表；都强 | ❌（同 Run 仅 1 张）|

### 6.5 结构升级如何兼容 RULE-Z

结构升级牌不进入牌库（13 张牌库不变），但生效需要"占一个升级槽位"。处理：

- 玩家选了结构升级 → 不进入牌库交换流程，直接生效到 `run_state.struct_modifiers[side]`
- 仍然计入"本轮升级 1/2"配额（玩家给自己 1 张 + 给 Boss 1 张的限制依然成立）
- **但不消耗牌库替换次数**——即玩家可以"白拿"一个结构升级且不需要丢弃任何基础牌
- 这让结构升级**比单卡升级更划算** → 必须设为"同 Run 仅 1 张"防止滚雪球

### 6.6 双向价值约束的强制校验（设计 lint）

在 `UpgradeData.tres` 资源里加 `bidirectional_score: int (1-5)` 字段，每张升级必须 ≥ 3 才允许进池。

未来扩展（v0.9+）：可加"诅咒类"升级牌（明显有利于自己/对手），让玩家可以"恶意分配"——但这会破坏对镜博弈的纯粹性，v0.8.0 不做。

---

## 7. Tuning Knobs（≥8 个，feel/curve/gate 分类）

| ID | Knob | 类型 | 默认值 | 调整理由 |
|---|---|---|---|---|
| T1 | `MAX_ROUNDS_PER_RUN` | gate | **5** | Q3 决策。可改 7 给硬核模式 |
| T2 | `BOSS_HP_PER_ROUND_INCREMENT` | curve | **3** | 防止后轮玩家碾压。可调 2-5 |
| T3 | `UPGRADE_CANDIDATE_POOL_SIZE` | gate | **12** | Q5 决策。验证后扩到 24 |
| T4 | `UPGRADE_CANDIDATES_PER_REWARD` | gate | **4** | 4 选 2，固定 |
| T5 | `SWAP_ANIMATION_DURATION_SEC` | feel | **2.0** | 互换动画时长。旧版 5s 预览已移除（互换前置于升级，不再需要预览倒计时） |
| T6 | `STARTING_HP_EACH_ROUND` | curve | **25** | 与 GDD-06 对齐 |
| T7 | `BIDIRECTIONAL_VALUE_THRESHOLD` | curve | **3 (out of 5)** | 升级牌进池门槛 |
| T8 | `STRUCT_UPGRADE_NO_REPLACE` | feel | **true** | 结构升级不消耗牌库替换次数。如改 false 则结构升级强度大幅下降 |
| T9 | `BOSS_NAME` | feel | **"MIRROR"** | Q6 决策。未来可加 handle 输入扩展 |
| T10 | `RUN_STATE_PERSISTENCE` | gate | **memory_only** | v0.8.0 不做存档；v0.8.1 上 user://run_state.tres |

---

## 8. Acceptance Criteria

### 8.1 功能性

- [ ] 玩家能完成 1 轮战斗 → 牌库互换动画 → 进入奖励界面
- [ ] 互换后玩家持有 ex-Boss 牌库，Boss 持有 ex-玩家牌库
- [ ] 4 张候选可见、可悬停 tooltip
- [ ] 玩家给自己 1 张 → 选自己当前牌库（ex-Boss 牌库）1 张被替换 → 牌库仍 13 张
- [ ] 玩家给 Boss 1 张 → 选 Boss 当前牌库（ex-玩家牌库）1 张被替换 → Boss 牌库仍 13 张
- [ ] 双方牌库在升级界面完全开放查看（NEW-Q2=A）
- [ ] 升级总结正常显示双方最终牌库（含本轮新升级高亮）
- [ ] 互换后双方 HP/能量/armor 重置正确，Boss HP 按缩放公式
- [ ] 第 N 轮 Boss HP = 25 + (N-1)×3
- [ ] 第 5 轮胜利 → PERFECT_RUN 结算
- [ ] 任何一轮失败 → FAILURE_END 显示连胜数 + 当前 build 截图
- [ ] LLM 感知正确接收 `round_index` / `victory_streak` / `last_upgrade_given_to_self` / `last_upgrade_given_to_boss`
- [ ] 结构升级正常生效到 run_state.struct_modifiers，不消耗牌库替换次数（NEW-Q1=A）

### 8.2 体验性

- [ ] "对镜博弈"情感锚点在 Round 1 结束后的互换瞬间被玩家感知到（陌生牌库在手）
- [ ] 玩家自然产生"我现在拿着 Boss 的牌——升级得想清楚"的认知
- [ ] 单 Run 完美时长 < 35 分钟（5 轮 × ≤7 分钟/轮）
- [ ] 升级界面无信息过载——4 张候选 + 一目了然的"步骤 1/2"指示
- [ ] LLM reasoning 在升级后回合明显发生认知变化（如"对手刚强化了水属性，我的火攻需要谨慎"）

---

## 9. 场景与节点设计（Godot 实现指南）

### 9.1 新场景

```
scenes/run/run_scene.tscn (RunScene 根节点，autoload 不直接放此)
└── ViewportContainer (复用现有)
    ├── BattleScene (现有 blind_clash_scene.tscn 实例化)
    ├── SwapAnimation (互换动画层，~2s 轰然交换)
    └── RewardScreen (新建 scenes/run/reward_screen.tscn，叠加层)
        ├── DimBackground (黑幕 70%)
        ├── CandidatesContainer (4 张升级牌横排)
        ├── StepIndicator (顶部 banner)
        ├── PlayerDeckPreviewBtn / BossDeckPreviewBtn (双方牌库完全开放)
        ├── ReplaceModal (浮层：选择被替换的牌，13 张 Grid)
        └── UpgradeSummaryPanel (升级总结：双栏对照，点击"开战"继续)
```

### 9.2 新数据类

```gdscript
# scripts/data/upgrade_data.gd
class_name UpgradeData
extends Resource

enum Category { NUMERIC, ATTRIBUTE, KEYWORD, STRUCTURAL }

@export var id: StringName
@export var name: String
@export var category: Category
@export var description: String
@export var bidirectional_score: int = 3  # 1-5，进池门槛 ≥3
@export var is_repeatable: bool = true     # 同 Run 内可否重复出现
@export var is_structural: bool = false    # 结构升级（不替换牌库）

# 替换执行函数（针对单卡升级）
func apply_to_card(target: CardData) -> CardData:
    # 子类或 lambda 重写
    pass

# 结构升级生效函数
func apply_structural(side: String, run_state) -> void:
    pass
```

### 9.3 新 Autoload：RunState

```gdscript
# autoload/run_state.gd（新增到 project.godot autoload）
extends Node
class_name RunStateMgr

var round_index: int = 1
var victory_streak: int = 0
var struct_modifiers: Dictionary = {
    "player": {},  # {"energy_bonus": 1, "candidate_bonus": 1, ...}
    "boss": {},
}
var upgrade_history: Array = []  # [{"round":1, "given_to_self":"up_overflow", "given_to_boss":"up_shard"}]

signal decks_swapped  # 互换完成，通知 RewardScreen 可以显示

func reset_for_new_run() -> void:
    round_index = 1
    victory_streak = 0
    struct_modifiers = {"player": {}, "boss": {}}
    upgrade_history.clear()

## 互换前置于升级：胜利后先调用此函数执行互换
func execute_swap(player: Combatant, boss: Combatant) -> void:
    var temp_deck = player.deck.duplicate()
    player.deck = boss.deck.duplicate()
    boss.deck = temp_deck
    player.discard_pile.clear()
    boss.discard_pile.clear()
    player.hand.clear()
    boss.hand.clear()
    player.hp = 25
    boss.hp = 25 + round_index * 3  # 缩放后 Boss HP
    player.energy = 6
    boss.energy = 6
    player.armor = 0
    boss.armor = 0
    round_index += 1
    victory_streak += 1
    decks_swapped.emit()

## 升级阶段完成后记录
func record_upgrade(player_upgrade: UpgradeData, boss_upgrade: UpgradeData) -> void:
    upgrade_history.append({
        "round": round_index - 1,  # 记录的是刚结束的轮次
        "given_to_self": player_upgrade.id,
        "given_to_boss": boss_upgrade.id,
    })

func is_perfect_run_done() -> bool:
    return victory_streak >= 5
```

### 9.4 跨轮持久化策略

- **v0.8.0**：内存即可，关游戏 = 进度丢失（rogue-lite 标准）
- **v0.8.1+**：`user://run_state.tres` 持久化，但只持久化 `victory_streak` 历史最高，不持久化"未完成的 run"（避免 save scumming）

---

## 10. 实施任务清单（Epic-08 拆分预览）

| Epic | 描述 | 优先级 | 工时 |
|---|---|---|---|
| **08-A** | RunState autoload + UpgradeData 资源类 | P0 | 1.5h |
| **08-B** | 12 张升级牌池注册（card_database 扩展或独立 upgrade_database）| P0 | 2h |
| **08-C** | SwapAnimation 互换动画层（~2s，player.deck ↔ boss.deck）| P0 | 1.5h |
| **08-D** | RewardScreen 场景（4 张候选 + 步骤 banner + 双方牌库完全开放查看）| P0 | 3h |
| **08-E** | ReplaceModal（13 张 Grid 选被替换牌，操作互换后的牌库）| P0 | 1.5h |
| **08-F** | UpgradeSummaryPanel（双栏对照 + "开战"按钮）| P0 | 1h |
| **08-G** | LLM perception_builder 扩展（`round_index` / `victory_streak` / `upgrade_history`）+ prompt 更新 | P0 | 1.5h |
| **08-H** | Boss HP 缩放 + struct_modifiers 接入战斗 | P0 | 1.5h |
| **08-I** | FAILURE_END / PERFECT_RUN_END 结算页 | P1 | 1.5h |
| **08-J** | 烟测 + 平衡迭代（多 Run 跑完整 5 轮） | P0 | 2h |

**预估总工时**：~17h（约 4-5 个 30min vibe-coding loop）

---

## Open Questions for User Review

> ~~上次会话 6 个 Q 已全部拍板，本次新增"零膨胀替换"原则后涌出 2 个微决策需要确认~~ → **已全部拍板**：

| Question | 决策 | 状态 |
|---|---|---|
| NEW-Q1 | **A**：结构升级不消耗牌库替换次数 | ✅ 已锁定 |
| NEW-Q2 | **A**：奖励界面完全开放 Boss 牌库查看 | ✅ 已锁定 |
| FLOW | **先互换牌库，再选择升级** | ✅ 已锁定 |

**无剩余 Open Questions。**

---

## 文档元数据

- **作者**：vibe-lead（接 game-designer 失能后亲笔）
- **审稿**：creative-director（情感锚点 + 红线警告）
- **用户拍板**：6 个 Q + RULE-Z 零膨胀 + NEW-Q1 + NEW-Q2 + 流程调整 = 10 个核心决策
- **版本**：v0.8.1-locked（流程重构：互换前置于升级）
- **下次行动**：拆 Epic-08-A~J 实施清单，进入代码实施
