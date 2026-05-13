# GDD §5 — 洞察三效果·下回合应用方案（v0.4.3 草案）

> 作者：game-designer（vibe-lead 综合）  
> 状态：**方案，未实施**。本回合仅写设计稿与日志，代码改动留待下一对话。  
> 关联：`docs/design/gdd/04-blind-clash-revision.md` §4.4、`scripts/battle/blind_clash_battle.gd::_check_insight_effects()`、`scripts/battle/cognitive_probe.gd`

---

## 1. 问题陈述

当前 `_check_insight_effects()`（约 557–595 行）在认知结算阶段**立刻**对玩家手牌/牌库做手脚：

| 效果 | 现行实现 | 时序问题 |
|------|----------|---------|
| peek | 把目标牌 push 进 `peeked_cards` | 仅记录数组，下回合 PerceptionBuilder 没读 → 没有信息价值 |
| disrupt | push 进 `disrupted_cards` | BlindSelectUI 不读这个数组 → "下回合不可用"契约未兑现 |
| seize | `player.hand/full_deck.erase()` + 加进 boss 牌库 | 立刻执行，玩家无任何反应窗口；视觉只有一行字 |

→ 三效果的"压迫感"完全无法传递给玩家，玩法目标"让 Boss 像一个会学习的认知威胁"破功。

---

## 2. 时序契约（核心方案）

### 2.1 双阶段模型

```
本回合 PROBE 阶段：           下回合 ROUND_START：
  ┌──────────────────┐         ┌──────────────────────┐
  │ probe.resolve()  │         │ apply_pending_       │
  │  ↓               │         │   insights()         │
  │ 入队 pending_    │ ──────► │  ↓                   │
  │ insights[]       │         │ peek/disrupt/seize   │
  │  ↓               │         │ 真正落到手牌/牌库    │
  │ 演出"宣告"动画   │         │  ↓                   │
  │ 显示 Banner      │         │ 清空 pending_*       │
  └──────────────────┘         └──────────────────────┘
```

### 2.2 三效果的下回合作用点

| 效果 | 下回合应用子阶段 | 理由 |
|------|------------------|------|
| **peek** | `ROUND_START` 末尾 | 标记建立后，DEPLOY → BLIND 阶段的 PerceptionBuilder 才能把这张牌的真实数据写进 LLM 上下文（`leaked_player_card`） |
| **disrupt** | `ROUND_START` → `BLIND` 进入前 | BlindSelectUI 在 `set_hand()` 时读 `disrupted_cards` 渲染灰显锁链；强保证玩家选牌时已锁 |
| **seize** | `ROUND_START` 开头 | 玩家手牌渲染**之前**就把目标牌物理移除并转入 boss 牌库，避免"看到一半被抽走"的诡异闪烁 |

### 2.3 持续期与消费规则

| 效果 | 持续到何时 | 消费触发 |
|------|------------|----------|
| peek | 直到该牌被玩家打出/弃置 | 一次性，被打出后 `peeked_cards.erase()` |
| disrupt | 仅作用于"下一回合"BLIND；该回合结束自动解锁 | 1 回合 TTL，`apply_pending_insights()` 中入栈，`_end_round()` 中出栈 |
| seize | 永久（移除后玩家不再拥有） | N/A，移除即终结 |

---

## 3. 数据结构

### 3.1 `pending_insights` 队列

`BlindClashBattle` 新增成员：

```gdscript
# 待应用洞察队列（本回合宣告，下回合开头 apply）
var pending_insights: Array[Dictionary] = []
```

每条目结构：

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | String | `"peek"` / `"disrupt"` / `"seize"` |
| `target_card_id` | String | CardData.id（用于 LLM/日志稳定标识） |
| `target_card_ref` | CardData | 直接引用（手牌实例对象） |
| `source_streak` | int | 触发时的连续命中次数（用于演出强度分级） |
| `declared_round` | int | 宣告所在回合号 |
| `applied` | bool | 已落地为 true（防止重复 apply） |

### 3.2 边界处理

- **peek 目标牌在下回合开始时已不在玩家手牌**（弃牌堆/牌库中）：标记保留，等下次抽到再激活。
- **disrupt 目标牌已不在玩家手牌**：转为"下次抽到时立即锁"，TTL 延长至 2 回合防永久占位；2 回合还未抽到则失效。
- **seize 目标牌已不在玩家拥有**（已弃/已消耗）：降级为补偿性 peek（窥视玩家此刻的另一张随机手牌），保持 Boss 加强强度。

---

## 4. 与现有函数的改动映射

### 4.1 `_check_insight_effects(probe_result)` — **改写**

| 当前行为（保留？） | 改动后 |
|-------------------|--------|
| `streak == 2` 触发随机洞察预告 emit `insight_random_triggered` | **保留**（已是预告语义） |
| `streak == 2` 立刻 push `peeked_cards` + emit `insight_effect("peek", card)` | 改为：push 到 `pending_insights`，emit `insight_effect`（演出层用） |
| `streak >= 3` 立刻 push `disrupted_cards` + emit `insight_effect("disrupt", card)` | 改为：push 到 `pending_insights`，emit |
| `total >= 5` 立刻 erase 并加进 boss 牌库 + 重置 total_hits | **延迟**：仅 push 到 `pending_insights`，emit。`total_hits` 重置移到 `apply_pending_insights()` 内部 |

### 4.2 新增 `apply_pending_insights()`

调用点：`_next_round()` 开头（在 `_round_start_*` 快照之前、能量恢复之前）。  
逻辑：遍历 `pending_insights` 中 `applied == false` 的条目，按 `type` 分派：
- `peek` → 把 `target_card_ref` 加入 `peeked_cards`（如果已不在手牌则改进 watch list）
- `disrupt` → 加入 `disrupted_cards`，并在 `_end_round()` 中 pop
- `seize` → 执行原 `_check_insight_effects` 中的 erase + boss 牌库 append

每条 apply 完成后 emit 新信号：`insight_applied(effect_type, target_card)` — UI 用来播放"下回合应用瞬间"的二段动画（手牌锁链落下 / 牌被吸走）。

### 4.3 BlindSelectUI 接通 `disrupted_cards`

`set_hand()` 渲染每张卡时检查 `card in battle.disrupted_cards` → `card_ui.set_disrupted(true)`；点击被禁用，触发抖动反馈。

### 4.4 PerceptionBuilder 接通 `peeked_cards`

下回合 BLIND 阶段构造 LLM 上下文时新增字段：

```json
"leaked_player_cards": [
  {"id": "atk_basic", "name": "基础攻击", "type": "attack", "damage": 6}
]
```

让 Boss "看到底牌"具有真实信息价值。

---

## 5. 玩家可读性：Pending Insights Banner

UI 层在屏幕顶部新增持久 banner（认知结算后到下回合应用前持续显示）：

```
[下回合开局] ⚠ Boss 将偷看 你的"基础攻击"
[下回合开局] ⛓ Boss 将锁定 你的"防御姿态" — 下回合不可使用  
[下回合开局] ☠ Boss 将夺取 你的"过载冲击" — 永久失去
```

让玩家有 ≥1 回合的心理准备时间，符合"暗出对决=博弈"的设计支柱（玩家必须能预判 Boss 行为）。

---

## 6. 平衡考量

延迟一回合落地后，Boss 加强强度下降约 15–20%（玩家有反应窗口）。两个补偿方案：

| 方案 | 描述 | 优劣 |
|------|------|------|
| A | `streak == 3` 时同时 peek + disrupt 双触发 | 强度回升明显，但与"clear 单一效果"叙事冲突 |
| B | seize 应用时附赠一次立即 peek（看新手牌） | 节奏自然（夺走后窥视下一张），克制 |

**game-designer 倾向 B**，留给 creative-director 拍板。本方案先实现单触发版本，平衡补偿留作 v0.4.4。

---

## 7. 验收清单（下回合实施时检查）

- [ ] `pending_insights` 数组在 PROBE 入队、ROUND_START 出队
- [ ] peek 标记在被偷看牌打出后自动消费
- [ ] disrupt 1 回合 TTL，下下回合自动解锁
- [ ] seize 在下回合 ROUND_START 真正物理转移
- [ ] BlindSelectUI 渲染 disrupted 灰显 + 锁链 + 禁用点击
- [ ] PerceptionBuilder 输出 `leaked_player_cards` 字段供 LLM
- [ ] PendingInsightsBanner 在认知结算→下回合应用之间持续显示
- [ ] `insight_applied` 信号触发手牌"二段动画"
- [ ] 测试用例：streak 累积到 2/3、total 到 5 各路径，跨 3 回合时序正确
