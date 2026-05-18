# ADR-002: 题材与克制系统转向 — 火水木 + 光明暗黑

**状态**：✅ Accepted（数据层已实施）
**日期**：2026-05-14
**决策者**：vibe-lead + 用户拍板
**Supersedes**：ADR-001 中关于"赛博朋克 NULL Protocol 题材"的描述部分（ADR-001 的 LLM AI 架构本身仍有效）

---

## 上下文

NULL Protocol（v0.5.0 之前）以**赛博朋克题材** + **ATK/DEF/SKL 三角克制** 为基础。BP（暗出对决）方案 B 在 2026-05-14 18:43 锁定后，用户提出**两点反思**：

1. **赛博朋克题材与玩法脱节**：「程序入侵 / 协议」叙事难以解释"为什么打牌就能造成伤害"
2. **三角克制博弈空间偏窄**：ATK/DEF/SKL 三类克制在 BP 5 张出牌位下博弈深度不足

随后讨论中，用户先提议**金木水火土五行**（5 元素 + 相生相克双环），vibe-lead 反思后指出五行存在**博弈学问题**：

| 维度 | 3 类（石头剪刀布）| 5 类（五行双环）|
|---|---|---|
| 单张克制关系 | 2 种结果 | 4 种结果 |
| 4 出牌位组合 | 3⁴ = 81 | 5⁴ = 625 |
| 玩家脑内决策树 | ~30 节点 | **~200 节点** |
| 数学最优性 | **纳什均衡纯混合策略** | 有"中立位"，出牌懒惰 |

**结论**：5 类 + 双环会把休闲对局变成棋类计算，违反 Roguelike 卡牌"快节奏多局数"核心体验。

---

## 决策

**采用方案 A 改良版**：

1. **3 元素克制（火/水/木）**：保持 3-cycle 石头剪刀布纳什最优解，命名采用直观的「火/水/木」（替代抽象的"攻/守/化"）
2. **光明/暗黑 2 极性**：作为**正交第二维度**而非第二克制环，不增加单对计算量
3. **协同奖励仅实装 2:2 平衡 ×2.0（A2 保底版）**：不实装 4 光、4 暗、3:1、1:3 等其他档位（留作 v0.7.0+ 扩展）
4. **Boss「回响 Echo」名字与视觉保留不动**，仅文案去赛博词
5. **旧 GDD 01-04 + ADR-001** 标 DEPRECATED 不改写（GDD-05 认知陷阱保留有效）

---

## 备选方案与拒绝理由

| 方案 | 描述 | 拒绝原因 |
|---|---|---|
| **不改（保留赛博朋克 + ATK/DEF/SKL）** | 维持现状 | 题材与玩法脱节，BP 博弈深度不足 |
| **B 三色魔法（红/蓝/绿）** | 纯换皮，无第二维度 | 设计创新度过低，只是换名字 |
| **C 四象（4-cycle 克制）** | 4 类青龙白虎朱雀玄武 | 4-cycle 在博弈学上不如 3-cycle 优雅，且存在"中立对手"导致出牌懒惰 |
| **D 五行（5 类 + 相生相克双环）** | 用户最初提议 | **计算量过载**（5⁴=625），新手前 3 局瞎打；相生链导致玩家抱团出顺序牌而非博弈 |
| **A1 火水木+光暗 全协同奖励** | 4 光治+抽1 / 4 暗+3伤 / 3:1 弱奖励 / 2:2 平衡 ×2.0 | 实施工期 +1.5d，且非平衡档奖励会鼓励"堆光"或"堆暗"破坏博弈本质 |
| **✅ A2 火水木+光暗 仅 2:2 平衡** | 唯一奖励=平衡 ×2.0 | **被采纳**——目标极清晰，新手第 1 局学会，老手深度来自"2:2 该选哪 4 张"|

---

## 后果

### 正面

- **博弈深度↑**：从 ATK/DEF/SKL 一维克制 → 元素克制 + 平衡协同 双维度
- **学习曲线↓**：3-cycle 是石头剪刀布皮肤（无学习成本）+ 平衡奖励单一目标（"凑 2 光 2 暗"一句话讲清）
- **计算量↓**：3⁴=81 vs 五行 5⁴=625（**省 87%**）
- **题材统一**：火/水/木 + 光/暗 是任何文化都能秒懂的视觉语言（无文化门槛）
- **工程量↓**：保留 CardType 枚举（type 字段仍用于陷阱触发匹配），CardData 仅**新增** element/polarity 字段（**未删除任何旧字段**）
- **LLM 强度可控**：A2 保底版仅奖励玩家方平衡，Boss 不享受 → 不需要重新调 LLM SYSTEM_PROMPT 的强度公式

### 负面

- **旧 13 篇赛博词 GDD/ADR 报废**（标 DEPRECATED 处理，不改写）
- **新 GDD-06 + 20 张牌数值** 需在 Sprint A 内完成
- **UI 改造量**：trap_card_ui / rules_overlay_ui / battle_effects 需改图标与配色（Sprint C，~3d）
- **LLM Prompt 需改**：去赛博词 + 加元素+光暗感知（Sprint D，~1d）
- **BP 文案打架风险**：BP 机制有"暗出/翻牌"，元素标签也有"暗黑" → 已预案：BP 机制叫「伏/藏」（face-down），元素叫「光明/暗黑」

### 中性

- CardType 枚举（ATTACK/DEFENSE/SKILL/PROTOCOL）保留 —— 仍用于陷阱槽位触发匹配（攻击触发槽 0、技能触发槽 1、高费触发槽 2）
- 现有 BP（暗出对决/陷阱/认知探针）流程**完全不变**
- 现有 LLM AI 架构（ADR-001）**完全不变**

---

## 实施

### 数据层（已完成 2026-05-14）

```
scripts/data/card_data.gd:
  + enum Element { NONE, FIRE, WATER, WOOD }
  + enum Polarity { NONE, LIGHT, DARK }
  + @export var element: Element = Element.NONE
  + @export var polarity: Polarity = Polarity.NONE

scripts/utils/element_helper.gd (新建):
  + get_element_counter(a, b) -> int       # 3-cycle 克制
  + is_balanced_polarity(cards) -> bool    # 2:2 平衡判定
  + count_polarity(cards) -> Dictionary    # {light, dark, none}
  + distance_to_balance(cards) -> {distance, need}  # UI 实时预测
  + apply_balance_bonus(mult, balanced)    # 1.5 → 2.0

scripts/battle/clash_resolver.gd:
  ~ get_counter_result(card, card)         # 签名改为 CardData，元素优先 + type fallback
  + _legacy_type_counter(...)              # 旧三角作兼容路径
  ~ resolve_clash(...)                     # 注入 player_balanced 检查 + 1.5→2.0 升级
  + ClashResult.balanced_bonus: bool       # 标记本对是否吃了平衡加成

autoload/card_database.gd:
  ~ get_player_starter_deck()              # v0.5.0 A2 8 张 → v0.6.0 10 张（火3水3木4，光6暗4）
  ~ get_boss_layer1_deck()                 # → Echo 10 张（火4水3木3，光4暗6）
  + _register_v06_player_cards()           # 阳焰/业火/烈日/月华盾/寒霜镜/涌泉/春芽/荆棘/藤甲/蚀根
  + _register_v06_boss_cards()             # 回响焰/灼烧波/残阳/余烬/回声盾/冰封/修复泉/回响藤/共鸣芽/寄生
  + _reg_v06(...) 注册器                   # 携带 element + polarity 字段
```

### 后续（Sprint B/C/D）

- Sprint B（2-3d）：BP 流程信号扩展 + UI 实时预测条 + 平衡飘字
- Sprint C（2-3d）：trap_card_ui 元素图标 + 光暗外框 / theme 配色 / rules_overlay 三角图改造
- Sprint D（1-2d）：LLM SYSTEM_PROMPT 去赛博词 + perception_builder 加 element/polarity 字段

---

## 验证标准

Sprint A.1 数据层完工 Gate：

- [ ] 能开新局到 round 3 不崩溃
- [ ] 4 张玩家牌 vs 4 张 Boss 牌正确触发火/水/木 3-cycle 克制
- [ ] 玩家组合 2 光 2 暗时所有克制对倍率从 1.5 升至 2.0
- [ ] 旧牌（reward_cards 等）仍走 type fallback 不崩
- [ ] 伤害数值与 GDD-06 §6 公式偏差 ±10% 内

---

## 引用

- 任务计划：`docs/design/decisions/2026-05-14-elements-polarity-pivot-task-plan.md`（v3.1 决策闭环）
- BP 提案（已锁）：`docs/design/decisions/2026-05-14-bp-pivot-proposal.md`
- GDD：`docs/design/gdd/06-elements-polarity-battle.md`
- 旧 ADR（仍有效部分）：`docs/design/architecture/adr-001-llm-boss-ai.md`

---

**作者**：vibe-lead
**复审**：technical-director（架构）+ game-designer（数值）
**最终拍板**：用户（2026-05-14 19:18）
