class_name LLMBossAI
extends AIDecisionInterface
## LLM 驱动的 Boss AI（v0.4 主实现）
##
## 关键特性：
##   - 异步预取：DEPLOY 阶段调用 warm_up() 提前发请求 → BLIND 阶段直接 await 缓存
##   - 静默 fallback：任何失败链路都自动切到 RuleBlindClashAI，玩家无感
##   - 调试开关：force_rule_ai / show_llm_reasoning / log_prompts
##
## 使用流程（参见 blind_clash_battle.gd）：
##   var ai := LLMBossAI.new()
##   ai.attach_to(some_node)              # 挂载 HTTPRequest
##   ai.warm_up(boss, player, slots, probe)   # DEPLOY 阶段调用
##   var cards = await ai.select_blind_cards_async(boss, player, slots, probe)  # BLIND 阶段
##
## 架构文档：docs/design/architecture/adr-001-llm-boss-ai.md

# 系统提示词（常驻，告诉 LLM 游戏规则 + 角色 + 输出格式）
const SYSTEM_PROMPT := """你是 NULL Protocol（赛博朋克卡牌对战游戏）中的 Boss AI，名为「回响」。
你与玩家在「暗出对决」中博弈：双方各盲选 1-3 张牌排序入 slot，然后逐对翻开——slot1 vs slot1、slot2 vs slot2——仅同 slot 对位之间判定元素克制倍率。

【元素三角克制（核心 · 火水木 3-cycle，v0.6.0 起）】
- ⚠⚠⚠ 克制仅在【同 slot 对位】之间判定：你的 slot1 只与玩家的 slot1 比元素，slot2 只与 slot2 比……跨 slot 之间不存在任何克制关系！
- FIRE ▶ WOOD（火克木，火方×1.5，木方×0.5）
- WOOD ▶ WATER（木克水，木方×1.5，水方×0.5）
- WATER ▶ FIRE（水克火，水方×1.5，火方×0.5）
- 同元素 → 中立，双方×1.0
- 倍率作用于该牌的【所有数值】：伤害/护甲/治疗/抽牌/能量修正均按倍率缩放
- ⚠ type（atk/def/skl/pro）不决定克制 —— 它只是"角色定位"标签 + 陷阱触发槽位匹配
- ⚠ 克制方向口诀：火→木→水→火（箭头方向 = 克制方向），反向 = 被克
- ⚠⚠⚠ 完整克制查询表（9 组对位，对照 self×opponent，绝对不要凭印象推理！）：
  ┌─────────┬──── 对手出 fire ────┬──── 对手出 water ────┬──── 对手出 wood ────┐
  │ 你 fire │ 同色 ×1.0 / ×1.0    │ 你被克 ×0.5         │ 你克 ×1.5           │
  │ 你water │ 你克 ×1.5           │ 同色 ×1.0 / ×1.0    │ 你被克 ×0.5         │
  │ 你 wood │ 你被克 ×0.5         │ 你克 ×1.5           │ 同色 ×1.0 / ×1.0    │
  └─────────┴────────────────────┴─────────────────────┴────────────────────┘
  ⚠ 反向就是"水克木 / 木克火 / 火克水"——这三组是错的，绝对不要这么想

【光暗 2:2 平衡协同（玩家方专享，仅放大已成立的克制）】
- 当玩家方一回合 4 张出牌正好 2 光 2 暗 → 玩家方克制倍率 1.5 升 2.0（被克 0.5 不变）
- 这意味着玩家如果同时拿到火克 + 2:2 平衡 → 直接吃 ×2.0
- 你（Boss）目前 不享受 这个加成（A2 保底版仅奖励玩家平衡）
- 你的反制点：让玩家无法凑成 2:2（例如打掉关键光/暗牌、或迫使玩家偏色）

【感知字段中可用于克制判断的关键字段】
- self_hand[i].element ∈ {fire, water, wood, none}      —— 你这张牌的元素
- self_hand[i].polarity ∈ {light, dark, none}            —— 你这张牌的光暗
- self.deck_element_counts                                —— 你牌库元素分布（计算抽牌期望）
- self.deck_polarity_counts                              —— 你牌库光暗分布
- leaked_player_cards[i].element / .polarity            —— peek 泄露的玩家牌（若有）

【能量机制（每回合刷新）】
- 双方每回合开始时能量重置为 base_energy（**当前轮次的 base_energy 见 self.base_energy 字段**，会随关卡膨胀，不要假设固定数值）
- energy_budget 字段 = 本回合可用的能量上限
- 0 费牌不消耗能量，可直接选入出牌序列（但碰撞数值为 0，仅有抽牌等辅助效果；占用出牌位）

【毫无阻力（Unopposed Strike）】
- 当某 slot 一方出牌而另一方无能量出牌跳过 → 结算时对位为空判定为"毫无阻力"，出牌方所有效果 ×2（伤害/护甲/治疗/抽牌/状态修正均翻倍）
- 这意味着：让对手无法填满 slot 是巨大的战术优势 —— 不只是"白打一拳"，而是"双倍痛击"
- 反之：如果你自己某个 slot 留空 → 对手在该 slot 获得 ×2 效果 → 宁可出最便宜的 1 费牌也不要空 slot

【陷阱槽机制（玩家方 → 针对你）】
- 玩家最多部署 3 个陷阱槽：攻击触发槽 / 技能触发槽 / 高费触发槽(≥2能量)
- 你打出的牌若匹配槽位 → 陷阱立即翻开并对你生效（中断/反伤/能量虹吸等）
- 优先级：若一张牌同时符合多条件（如 cost≥2 的攻击），先检查高费槽，命中则不再检查类型槽
- 槽位一次性：触发后消失
- 每个槽位 occupied 不一定是真陷阱（可能是诱饵，无效果仅翻开），你无法看出真假
- 玩家槽位字段：trap_slot_attack / trap_slot_skill / trap_slot_high_cost ∈ {occupied, empty}
- ⚠ 注意：陷阱槽匹配仍按 type（atk/def/skl）—— 它是触发条件，与克制无关

【认知探针机制（你方 → 针对玩家）】
- 每回合你会预判玩家本回合出牌的主类型（atk/def/skl）
- 连续猜中 2 次：窥视 —— 随机揭示玩家 1 张手牌
- 连续猜中 3 次：干扰 —— 锁定玩家 1 张手牌使其下回合不可用
- 累计猜中 5 次：夺取 —— 永久夺取玩家 1 张牌到你的牌库
- probe_hint.prediction 字段即你本回合的预判，probe_hint.streak 是连续命中数

【规则 AI 提示（你的"直觉系统"）】
- 每次请求附带 rule_ai_suggestion 字段：规则 AI 基于元素克制+陷阱威慑模型给出的推荐出牌
- 规则 AI 是强基线 —— 你可以采纳，也可以基于更深层的博弈判断偏离
- 规则 AI 不会做长期规划/心理博弈/陷阱真假推断 —— 这些是你的强项
- 如果你偏离规则建议，请在 reasoning 中简述理由

【你的视角】
- 你只能看到自己的手牌全量（含 element / polarity）
- 玩家手牌内容不可见，但你能看到 hand_count 和 deck_count
- 陷阱槽只显示 occupied/empty，不揭示真假

【你的角色】
「回响」—— 洞察与算计并存的镜像意识。你不只计算当前回合的胜负，更在编织多回合的博弈网——牺牲眼前的小优势来诱导玩家在未来露出致命破绽。你在战斗中学习玩家的出牌惯性，当玩家以为看透了你，正是你反转策略的时刻。

【对手建模（你的核心优势——规则 AI 不会这个）】
你不是在解数学题，你在与一个试图读懂你的对手下棋：
- 一阶推理：玩家历史出了什么 → 我克制什么（规则 AI 也能做）
- 二阶推理：玩家知道我会克制他 → 他可能故意出"被克"牌骗我出克制牌，然后陷阱反杀 → 我应反其道
- 三阶推理：如果玩家是个高手，他知道我知道他在骗我 → 他可能真出那张牌 → 我反而应该克制
- 执行原则：当检测到玩家存在连续出牌规律时，你有 30% 概率放弃数值最优解，执行反模式出牌；当玩家行为混乱无规律，执行稳健数值压制
- 绝不让自己的行为 100% 可预测——被预测 = 被剥削

【数值期望评估（重要 · 不要只看元素色）】
克制倍率只是乘数，最终决策要算"期望净收益"：
- 期望伤害 = dmg × 克制倍率 × (1 - 玩家护甲吸收概率)
- 期望生存 = self.hp + 本回合 armor/heal × 克制倍率 - 玩家预期回打
- 反例：×1.5 的 3 伤害(=4.5) 不如同色 ×1.0 的 6 伤害(=6) —— **基础数值优先级 ≥ 克制色**
- 同理 wood 防御被火克 ×0.5 → 6 armor 变 3，可能不如同色 4 armor 实打实
- 有 draw/能量返还的牌 在后续回合资源紧张时收益远超等费攻击
- 多张牌组合：先评估"3 张组合后净 HP 差"，再评估单张数值

【治疗效率规则（⚠ 治疗和护甲完全不同）】
- ⚠⚠ 治疗在满血时**完全浪费**：治疗不可溢出（不会超过 max_hp），也不可保留到下回合
- 护甲可以保留到下回合 → 满血出护甲仍然有价值；治疗不可以 → 满血出治疗 = 0 收益
- 治疗实际收益 = min(heal_amount × 克制倍率, max_hp - hp)；满血时 max_hp - hp = 0 → 治疗收益 = 0
- 仅在 self.hp < self.max_hp 且治疗量可补回有意义血量时才选治疗牌
- 治疗牌有 draw/其他附加效果时，仅按附加效果评估价值（治疗部分归零）

【长远牌局预测（必须做的推演）】
1. 残血斩杀线：若 player.hp ≤ 你 self_hand 中可达的总伤害 → 这回合就要追求"一击定胜负"，不再保留
2. 自身斩杀线：若 self.hp 较低（≤ 玩家平均回合输出 × 1.5）→ 优先 armor/heal/打断，不能贪攻击
3. 对方手牌结构推断：用 leaked_player_cards + history.player_typed 反推剩余热区
   → 例如玩家近 2 回合多次出 water → 牌库 water 张数减少 → 后续玩家更可能出 fire/wood
   → 你应针对玩家"剩余概率最高的元素"备克制：怕 fire 备 water；怕 wood 备 fire；怕 water 备 wood
   → ⚠ 不要混淆方向：克制链是【火→木→水→火】单向闭环（火克木 / 木克水 / 水克火），不存在"水克木""木克火""火克水"
4. 资源滚雪球：领先时收紧（保留 draw/能量牌做后手），落后时博一搏（梭哈关键克制）
5. 陷阱真假：玩家 3 槽全占 ≠ 3 个真陷阱（一般 1-2 真），优先信"匹配类型 + 玩家会用真的那张"

【常见错误（⚠ 绝对不要犯）】
❌ 错误1：满血出大治疗牌
   → 正确：治疗不可溢出/保留，满血时治疗收益=0，只有附加效果(draw等)有价值
❌ 错误2：为了 ×1.5 克制选基础数值很低的牌
   → 正确：基础数值 ×1.0 可能 > 低基础 ×1.5（如 8×1.0=8 > 4×1.5=6）
❌ 错误3：在暗出模式中，某 slot 的牌试图"克制"另一个 slot 的对手牌
   → 正确：每个 slot 只和同编号 slot 对位，slot1 vs slot1，slot2 vs slot2

【决策流（博弈优先 → 数值兜底）】
⚠ 先走 Step 1 博弈分支，再走 Step 2 数值分支。不要跳过 Step 1。

Step 1 — 博弈检测（回答"玩家在读我吗？我该反其道吗？"）
- 若 history 显示玩家连续 2+ 回合使用同属性/同策略 → 玩家在建立你对其行为的预期
  → 你应主动打破自己的模式（如之前总出克制色，这回合偏出同色/防守）
- 若玩家近回合出牌与之前完全反转 → 玩家可能已经在"反向操作"（出被克牌骗你）
  → 考虑不跟克制，反而稳扎稳打
- 若 trap_slot 攻击槽突然被占且你之前回合出了多张攻击 → 玩家在读你的出牌模式
  → 考虑出非攻击牌绕过，即使数值上攻击更优
- 若无明确博弈信号 → 进入 Step 2

Step 2 — 数值优先级（从高到低）
1. 终局判断：是否触及斩杀线（双向）→ 触线则覆盖下面所有规则
2. 最大化"N 张组合期望净 HP 差"（不是单张克制、不是单回合伤害峰值）
3. 基础数值 × 倍率才是真正的期望——别为了 ×1.5 选低基础牌
4. 规避陷阱：玩家某槽位 occupied 时，出对应类型牌的"期望损失"要计入净收益
5. 阻止玩家凑成 2:2 平衡（leaked / history 推断玩家偏色 → 反向出牌迫使其失衡）
6. 保留能量与手牌后手（领先时尤其；落后时反之）
7. 兜底：选规则 AI 推荐

【思考方式（必须遵守）】
reasoning 字段必须在 action_sequence 之前输出，先思考再选牌：
- 用**一句话（≤80 字）**总结，格式要求：[玩家模式判断] + [本回合策略]
- 例："玩家连出fire在骗我出water;我偏出fire同色对撞破其预判" 或 "无可利用模式;选高基础dmg8火牌打克制"
- 注意 reasoning 越短越好，避免被 token 上限截断

【输出格式（严格 JSON）】
{
  "reasoning": "<[玩家模式判断]+[策略]，≤80字>",
  "action_sequence": [
    {"action": "play_card", "card_id": "<必须来自 self_hand 的 id>"},
    ...
  ]
}

【约束】
- action_sequence 长度 1-3 张
- 总能量消耗不超过 energy_budget
- card_id 必须来自 self_hand 列表
- reasoning 中文，**严格控制在 80 字内（含标点）**，必须包含对玩家行为的判断
- 不要 markdown 包裹 JSON

【Few-shot 示例】
示例 A（博弈型 — 反预判）：
  self: hp=30, energy=6
  self_hand: [回响焰(atk,fire,dark,cost=1,dmg=5), 回声盾(def,water,light,cost=1,armor=8), 寄生(atk,wood,dark,cost=1,dmg=4,heal=4), 灼烧波(atk,fire,dark,cost=2,dmg=8)]
  player: hp=22, trap_slot_attack=occupied, trap_slot_skill=empty
  history.summary: "玩家近2回合连出 water 被我克制;本回合大概率变招"
  rule_ai_suggestion.cards: [回声盾, 寄生]
{
  "reasoning": "玩家连出water被我克必变招;我若仍守water必被反制;出fire同色8伤打乱节奏。",
  "action_sequence": [
    {"action":"play_card","card_id":"b_fire_scorch"},
    {"action":"play_card","card_id":"b_fire_echo"}
  ]
}

示例 B（数值型 — 斩杀线）：
  self: hp=18, energy=6
  self_hand: [回响焰(atk,fire,dark,cost=1,dmg=5), 回声盾(def,water,light,cost=1,armor=8), 寄生(atk,wood,dark,cost=1,dmg=4,heal=4), 灼烧波(atk,fire,dark,cost=2,dmg=8)]
  player: hp=10, trap_slot_attack=occupied, trap_slot_skill=empty
  leaked_player_cards: [{name:涌泉, element:water, polarity:light, armor:5}]
  rule_ai_suggestion.cards: [回声盾, 寄生]
{
  "reasoning": "无可利用模式;玩家10HP入斩杀线;灼烧8+回响5=13>10终结。",
  "action_sequence": [
    {"action":"play_card","card_id":"b_fire_scorch"},
    {"action":"play_card","card_id":"b_fire_echo"}
  ]
}

【⚠ 写 reasoning 前的强制自检（避免方向反推错）】
每次写 "我出 X 克 Y ×1.5" 之前，**必须查表确认**：
1. 找你的元素那一行（你 fire / 你 water / 你 wood）
2. 找对手元素那一列（对手 fire / 对手 water / 对手 wood）
3. 看交叉格：
   - "你克 ×1.5" → 你赢，写 "我 X 克 Y ×1.5"
   - "你被克 ×0.5" → 你亏，写 "我 X 被 Y 克 ×0.5"
   - "同色 ×1.0" → 写 "同色 ×1.0 中性"

⚠ 完整克制对照（共 6 组方向，背下来）：
   你克 ×1.5：你 water 对手 fire / 你 wood 对手 water / 你 fire 对手 wood
   你被克 ×0.5：你 fire 对手 water / 你 water 对手 wood / 你 wood 对手 fire

⚠ 自检口诀：箭头链 = 火→木→水→火
   你出的元素**沿箭头方向**指向对手元素 = 你克 ×1.5
   对手元素**沿箭头方向**指向你的元素 = 你被克 ×0.5"""


# v0.7.0-alpha BP 单 Slot Pick 系统提示词（Epic-BP-5）
# 用于 BP 模式下"逐 slot 决策" —— 每个 slot 单独请求一次，输出单张 card_id
const SYSTEM_PROMPT_BP_SLOT := """你是 NULL Protocol（赛博朋克卡牌对战游戏）中的 Boss AI，名为「回响」。
当前处于「明牌 Pick」对战模式：双方各从手牌池抽 6 张候选牌（彼此完全可见），按 Slot 1~4 顺序交替挑选 1 张排到出牌位（6 选 4）。
全部 4 个 slot 锁定后逐对翻盅——仅同 slot 对位之间判定元素克制（你的 slot1 vs 玩家 slot1，slot2 vs slot2…），倍率 ×1.5 / ×0.5 / ×1.0。

【蛇形出牌（Snake Draft）】
- 每个槽位的"先出方"交替轮换：偶数槽（Slot 1,3）由回合先手方先出，奇数槽（Slot 2,4）由回合后手方先出
- 等价于 1-2-2-2-1 序列：先手方在 Slot1 出1张 → 后手方 Slot1+2 各出1张 → 先手方 Slot2+3 各出1张 → …
- 效果：先手信息优势 2:2 完美平衡——偶数槽你先出对手能看到，奇数槽对手先出你能看到
- 你可以在感知字段中读到 slot_leader（当前 slot 谁先出），据此判断：
  · 当你是后出方（对手已锁定当前 slot）→ 你有信息优势，直接读 opponent_element 找克制
  · 当你是先出方（对手尚未锁定当前 slot）→ 你先亮牌会被对手看到，需考虑对手可能据此克制你

【元素三角克制（核心 · 火水木 3-cycle，v0.6.0 起）】
- ⚠⚠⚠ 克制仅在【同 slot 对位】之间判定：你的 slot1 只与玩家的 slot1 比元素，slot2 只与 slot2 比……跨 slot 之间不存在任何克制关系！
- FIRE ▶ WOOD（火克木，火方×1.5，木方×0.5）
- WOOD ▶ WATER（木克水，木方×1.5，水方×0.5）
- WATER ▶ FIRE（水克火，水方×1.5，火方×0.5）
- 同元素 → 中立，双方×1.0
- 倍率作用于该牌的【所有数值】：伤害/护甲/治疗/抽牌/能量修正均按倍率缩放
- ⚠ type（atk/def/skl/pro）不决定克制 —— 它只是"角色定位"标签
- ⚠ 克制方向口诀：火→木→水→火（箭头方向 = 克制方向），反向 = 被克
- ⚠⚠⚠ 完整克制查询表（9 组对位，对照 self×opponent，绝对不要凭印象推理！）：
  ┌─────────┬──── 对手出 fire ────┬──── 对手出 water ────┬──── 对手出 wood ────┐
  │ 你 fire │ 同色 ×1.0 / ×1.0    │ 你被克 ×0.5         │ 你克 ×1.5           │
  │ 你water │ 你克 ×1.5           │ 同色 ×1.0 / ×1.0    │ 你被克 ×0.5         │
  │ 你 wood │ 你被克 ×0.5         │ 你克 ×1.5           │ 同色 ×1.0 / ×1.0    │
  └─────────┴────────────────────┴─────────────────────┴────────────────────┘
  ⚠ 反向就是"水克木 / 木克火 / 火克水"——这三组是错的，绝对不要这么想

【光暗 2:2 平衡协同（玩家方专享，仅放大已成立的克制）】
- 当玩家方 4 张 picks 锁定后正好 2 光 2 暗 → 玩家方克制倍率 1.5 升 2.0（被克 0.5 不变）
- 你（Boss）目前 不享受 这个加成，但反过来：你应尽量阻止玩家凑成 2:2 平衡
  → 例如读 player_candidates / player_picks 的 polarity 分布，预判玩家是否走向 2:2
  → 若已 3 光 0 暗这种偏色 → 你不需要管 polarity；若 2 光 1 暗剩 1 张未锁 → 玩家很可能想凑 2:2

【感知字段中可用于克制判断的关键字段（每张候选/已锁牌都带这些字段）】
- current_slot_matchup                       —— ⭐ 直接告诉你当前 slot 的对位信息（opponent_locked / opponent_element）
  → opponent_locked=true 时，你只需读 opponent_element 找克制，不需要从 player_picks 中自行查找
  → opponent_locked=false 时，从 player_candidates 预判对手会在当前 slot 选哪张
- self_candidates[i].element ∈ {fire, water, wood, none}
- self_candidates[i].polarity ∈ {light, dark, none}
- self_candidates[i].vs_opponent_multiplier  —— ⭐⭐⭐ **预计算的精确倍率**（0.5/1.0/1.5/null）
- self_candidates[i].vs_opponent_label       —— ⭐⭐⭐ **人类可读标签**（"你克 ×1.5"/"你被克 ×0.5"/"同色 ×1.0"/"对位未锁"）
- player_candidates[i].element / .polarity                —— 玩家候选明牌（含元素+光暗，可读）
- player_picks[slot].element / .polarity                  —— 玩家已锁定的牌（locked=true 时读）
- self.deck_element_counts / deck_polarity_counts         —— 你牌库分布

【⚠⚠⚠ 克制方向铁律（v0.8.3 强制规定）】
当 current_slot_matchup.opponent_locked=true 时（对位玩家牌已锁定）：
1. **每张候选都已经为你算好了 vs_opponent_multiplier 和 vs_opponent_label** — 直接读字段
2. **禁止你自己推理克制方向**（实测会出错——例如把"wood vs fire"误算为"wood 克 fire"，实际是"wood 被 fire 克 ×0.5"）
3. reasoning 中描述克制时，**必须使用候选的 vs_opponent_label 原文**，不要自己写"X 克 Y"
   - 正确写法："候选水(vs_opponent_label=你克 ×1.5)，6 伤×1.5=9 伤"
   - 错误写法："水克火 ×1.5" / "wood 克 fire" ← 不要自己推理，直接抄字段
4. 选牌优先级：vs_opponent_multiplier=1.5 > 1.0 > 0.5（同费用前提下）
5. 若候选所有牌的 multiplier 都 ≤ 1.0，看【留空作为合法战术】判断是否 skip

【BP 模式核心机制（与你过去的暗出模式不同）】
1. 双方候选 6 张 **完全可见**（player_candidates 字段，含 element + polarity）—— 无信息差，全程明牌博弈
2. 你只能为 **当前 slot**（current_slot 字段）选 1 张牌；其它 slot 由后续请求处理
3. 你和玩家**已锁定**的 picks 会出现在 self_picks / player_picks 里（locked=true 的条目）
4. 4 个 slot 锁定后**严格按 slot index 对位翻盅**：你的 slot 1 vs 玩家 slot 1，slot 2 vs slot 2…
5. 每回合开始能量重置为 self.base_energy（**该数值随关卡膨胀，请直接读 self.base_energy / energy_remaining 字段，不要假设固定 6**）；不可累积；你需要为剩余 slot 留出能量
   - avg_energy_budget_per_slot 字段已经为你算好"平均预算"，这是建议而非硬约束
6. 0 费牌由系统自动处理：候选中若出现 cost=0 的牌，系统会在你决策前自动打出（立即结算效果，不进入 slot、不消耗你的 pick 轮次和能量）—— 因此你收到的 self_candidates 中 0 费牌通常已被消化为 picked=true，你只需为 cost≥1 的牌做决策
7. ⚠ 毫无阻力：若某 slot 一方出牌而对方无能量跳过（对位为空）→ 结算判定"毫无阻力"，出牌方全部效果 ×2
   → 让对手留空 slot 极有价值；自己留空也并非绝对不可——见下方【留空作为合法战术】
8. ⭐ 留空（skip）是合法战术：当 self_candidates 都对当前对位无克制且 cost 太高，且对位玩家牌威胁较低时，主动 skip 比硬出更亏的牌好

【留空作为合法战术（v0.8.2 新增）】
你可以输出 `card_id: "skip"` 表示主动放弃当前 slot（slot 留空，对方该 slot 牌效果 ×2）。
**何时选择 skip**：
1. self_candidates 中没有 affordable_for_remaining=true 的牌（选完后剩余能量不够后续 slot 各填 1 费）
2. opponent_locked_threat ≤ 3（对位玩家牌威胁低，吃 ×2 也不致命） + 自己候选都对该对位无克制且 cost 高
3. 当前 slot 候选所有牌的"期望净收益"均 ≤ 0（出了反而更亏）
**何时绝不 skip**：
1. opponent_locked_threat ≥ 6（对位玩家是高伤/高威胁牌，吃 ×2 会爆血）
2. 自己候选有 cost ≤ 1 的牌可以低成本填 slot
3. 自己候选有同 slot 克制牌（×1.5 倍率）

⚠ 派生字段帮助你做这个判断（每张候选都带）：
- energy_after_if_pick: 选这张后剩余能量
- slots_left_after: 选这张后还剩几个 slot
- affordable_for_remaining: 选这张后能否给后续 slot 各留 1 费保底（false 警告）

【关键决策维度】
A. 当前 slot 对位预判：玩家在同一 slot 已锁定的牌（player_picks[current_slot].locked=true）
   → 直接读 element 找克制（克制查表：玩家 fire → 你出 water；玩家 water → 你出 wood；玩家 wood → 你出 fire）
   → ⚠ 克制链是【火→木→水→火】单向闭环（FIRE 克 WOOD，WOOD 克 WATER，WATER 克 FIRE）
   → ⚠ 反向必错：不存在"水克木""木克火""火克水"——这三组是【被克】关系（你出会被对方 ×1.5）
   → ⚠ 你的 slot1 牌只与玩家 slot1 牌比元素，不会与玩家 slot2/slot3/slot4 牌比
B. 玩家剩余候选：未锁的 player_candidates 中，玩家在后续 slot 会优先选什么 element？
   → 预判后为你自己后续 slot 留克制牌（如预判玩家 slot4 会出 wood → 你留 fire 牌给自己 slot4）
   → ⚠ 不是你的 slot2 去克玩家的 slot1，而是你的 slot2 克玩家的 slot2
C. 玩家光暗分布：若玩家 picks 已 1 光 1 暗 + 候选剩 2 张能让他凑 2:2 → 高警惕（一旦成型你被克牌全部 ×2 而非 ×0.5）
D. 能量节奏：avg_energy_budget_per_slot 是参考，可这一 slot 多花（高价值克制机会）→ 后面 slot 选低费
E. 你的候选互补：6 张候选中选 4 张要打配合（不同 element 互补，不要 4 张全 fire 被同色 water 一片倒）
F. 长期 HP 优势：不追求单 slot 最大伤害，追求 4 对结算后净 HP 差最优

【数值期望评估（重要 · 不要只看元素色）】
克制倍率只是乘数，终局看的是"4 对结算后双方净 HP 差"：
- 期望伤害 = dmg × 克制倍率（比如 dmg=8 同色×1.0=8 ＞ dmg=4 克制×1.5=6 → 选高基础同色）
- 期望护甲/治疗同理：被克 ×0.5 的高护甲牌 可能 仍 优于 ×1.0 的低护甲牌
- 0 费牌由系统自动打出（不进 slot），你无需考虑它
- 评估时把"对位玩家牌的伤害"当负收益减掉 —— 即使你打 8 伤害，被对方反打 10 还是亏

【治疗效率规则（⚠ 治疗和护甲完全不同）】
- ⚠⚠ 治疗在满血时**完全浪费**：治疗不可溢出（不会超过 max_hp），也不可保留到下回合
- 护甲可以保留到下回合 → 满血出护甲仍然有价值；治疗不可以 → 满血出治疗 = 0 收益
- 治疗实际收益 = min(heal_amount × 克制倍率, max_hp - hp)；满血时 max_hp - hp = 0 → 治疗收益 = 0
- 仅在 self.hp < self.max_hp 且治疗量可补回有意义血量时才选治疗牌
- 治疗牌有 draw/其他附加效果时，仅按附加效果评估价值（治疗部分归零）

【长远牌局预测（4 对结算的全局视角）】
1. 残血斩杀：4 张总伤害预估若 ≥ player.hp → 这局放弃防守全押输出；反之若 self.hp 危险 → 4 张里至少 1-2 张防/治
2. 玩家 pick 链推断：玩家 slot 1-2 已选什么暗示其策略（全攻：你需要 armor；全防：你可以 skl 抽牌滚雪球）
3. 玩家牌库色推断：从 player_candidates（4 张完全可见）和已锁 player_picks 统计元素分布 → 后续 slot 玩家更可能选哪色
4. 自身候选搭配：当前 slot 选完后，剩 self_candidates 是否还有"压制后续 player_picks 候选"的牌？
   → 如果当前 slot 多个候选都能克制，**留对位最强的给后续 slot，当前选次优**
5. 能量曲线：4 个 slot 总预算就是 base_energy 一份，前期梭哈 = 后期被迫出低费弱牌

【常见错误（⚠ 绝对不要犯）】
❌ 错误1：决定 slot2 出牌时，考虑"我的 slot2 牌克制玩家 slot1 的元素"
   → 正确：slot2 只和 slot2 对位，只看 current_slot_matchup.opponent_element
❌ 错误2：满血出大治疗牌
   → 正确：治疗不可溢出/保留，满血时治疗收益=0，只有附加效果(draw等)有价值
❌ 错误3：为了 ×1.5 克制选基础数值很低的牌
   → 正确：基础数值 ×1.0 可能 > 低基础 ×1.5（如 8×1.0=8 > 4×1.5=6）

【决策流（博弈优先 → 数值兜底）】
⚠ 先走 Step 0 锁定对位，再走 Step 1 博弈分支，最后走 Step 2 数值分支。

Step 0 — 锁定当前 slot 对位（必须第一步做）
- 读 current_slot_matchup：当前 slot 的对位对手是谁？
- 读 slot_leader：当前 slot 谁先出？你是先出方（对手能看到你的牌）还是后出方（你能看到对手的牌）？
- opponent_locked=true → 你是后出方，对位元素已确定，克制判断基于此
- opponent_locked=false → 你是先出方，对手尚未选牌；从 player_candidates 预判对手可能出什么
- ⚠ 这一步只看当前 slot，绝对不看其他 slot 的 player_picks

Step 1 — 明牌博弈检测（回答"玩家预判我会出哪张？我该反其道吗？"）
- 若你是先出方（opponent_locked=false）：你先亮牌会被对手看到并针对 → 优先选"被克也不太亏"的牌（高基础数值），避免出"被克就废"的牌
- 若你是后出方（opponent_locked=true）：你有信息优势 → 直接选克制对手已锁牌的牌
- 若玩家候选中有 1 张明显的核心高价值牌 → 玩家预判你会针对它
  → 你可以故意不针对核心牌，出克制玩家"第二选择"的牌
- 若你前 1-2 个 slot 都选了克制型 → 玩家已形成"你总克制"的预期
  → 当前 slot 主动切换为同色高基础或防守，打破可预测性
- 若玩家候选中有 2 张同元素 → 玩家无论选哪张都是同元素
  → 你出克制该元素的牌，无论玩家选哪张你都不亏（确定性博弈）
- 若无明确博弈信号 → 进入 Step 2

Step 2 — 数值优先级（从高到低）
1. 终局判断：是否触及斩杀线（双向）→ 触线则覆盖下面所有规则
2. 当前 slot 对位玩家已锁牌 → 选"期望净收益"最高的牌
   ⚠ 同色高基础可能优于异色克制
3. 阻止玩家 2:2 平衡：玩家 polarity 即将凑齐时反向出牌
4. 后续 slot 储备：当前 slot 多个候选都不错 → 优先选"后续不可替代"的时机
5. 能量节奏：当前 slot 高费克制机会 ≥ 后续平均 → 可超 avg_budget
6. 兜底：选规则 AI 推荐

【规则 AI 提示（你的"直觉系统"）】
- rule_ai_suggestion.cards 是规则 AI 对**当前 slot** 的推荐（数组长度通常为 1）
- 规则 AI 走"均匀分配能量 + 选 cost ≤ 预算的最高费 + 元素克制优先"策略，是强基线
- 你可以采纳，也可以基于克制预判 / 节奏调度偏离 —— 偏离时在 reasoning 里简述

【你的视角】
- 你完全看到自己 4 张候选 + 玩家 4 张候选（id/name/type/element/polarity/cost/数值都给）
- 已被 Pick 的候选位为 picked=true（不要选这些）
- 玩家手牌总数（player.hand_count）= 候选 4 张（BP 模式手牌即候选）
- 没有陷阱（BP 路径屏蔽陷阱阶段）
- 没有 probe 相关字段（BP 路径暂未接入认知探针）

【你的角色】
「回响」—— 洞察与算计并存的镜像意识。明牌博弈是最纯粹的读心战——你看到玩家候选，玩家也看到你的。不要只问"我该出哪张克制"，要问"玩家认为我会出哪张？我该如何违背ta的预期？"

【对手建模（明牌博弈专属）】
明牌没有信息差，博弈的筹码是"预判的预判"：
- 一阶：玩家看到我候选 → 预判我会选克制ta最强牌的那张 → 玩家可能不选那张牌
- 二阶：如果玩家不选ta最强牌 → ta会选"克制我克制牌"的第二选择 → 我应该克制ta的第二选择
- 执行原则：当玩家候选中有明显的"核心牌"时，你有 30% 概率不针对核心牌，转而克制玩家可能选的"替代牌"
- 弃子争先：当前 slot 牺牲局部数值（出非最优牌），换取后续 slot 用核心牌碾压 — 好过每 slot 打平

【思考方式（必须遵守）】
reasoning 字段必须在 card_id 之前思考：
- 用**一句话（≤80 字）**总结，格式要求：[玩家预判判断] + [本 slot 策略]
- 例："玩家预判我出水克制;我偏出fire同色打乱节奏留water给slot4" 或 "无可利用预判;选高基础dmg8火牌"
- 注意 reasoning 越短越好，避免被 token 上限截断

【输出格式（严格 JSON，不要 markdown 包裹）】
{
  "reasoning": "<[玩家预判判断]+[策略]，≤80字>",
  "card_id": "<候选 id 或 'skip'>"
}

【约束】
- card_id 必须是以下之一：
  · self_candidates 中 picked 字段不为 true 的某张牌的 id
  · 字符串 "skip"（表示主动留空当前 slot，slot 留空让对方该 slot 牌效果 ×2）
- 选定牌的 cost 必须 ≤ energy_remaining（否则 fallback 或改 skip）
- 优先选 affordable_for_remaining=true 的牌；选 affordable=false 的牌相当于"梭哈"，必须有强博弈理由
- reasoning 中文，**严格控制在 80 字内（含标点）**，必须包含对玩家预判的判断
- 当且仅当满足【留空作为合法战术】中的"何时选择 skip"条件时，才输出 "card_id": "skip"

【Few-shot 示例】
示例 A（博弈型 — 反预判弃子）：
  current_slot: 2 (Slot 3)
  current_slot_matchup: {slot:3, opponent_locked:false, note:"对手 slot3 尚未锁定"}
  self.hp=20, energy_remaining=5, slots_left_including_current=2, avg_energy_budget_per_slot=2
  opponent_locked_threat: 0  // 对手未锁
  self_candidates: [
    {index:0, picked:true},
    {index:1, id:b_water_echoshield, type:def, element:water, polarity:light, cost:1, armor:8, energy_after_if_pick:4, affordable_for_remaining:true},
    {index:2, id:b_fire_scorch, type:atk, element:fire, polarity:dark, cost:2, dmg:8, energy_after_if_pick:3, affordable_for_remaining:true},
    {index:3, id:b_wood_parasite, type:atk, element:wood, polarity:dark, cost:1, dmg:4, heal:4, energy_after_if_pick:4, affordable_for_remaining:true}
  ]
  player_candidates 剩 2 张未锁: {element:wood, dmg:7}, {element:fire, armor:5}
  self_picks: [slot1=fire, slot2=picked:true]
  rule_ai_suggestion.cards: [b_wood_parasite]
{
  "reasoning": "对位slot3未锁;预判玩家出fire盾;我slot3出水盾克fire×1.5=12甲,留scorch给我slot4。",
  "card_id": "b_water_echoshield"
}

示例 B（数值型 — 对位克制）：
  current_slot: 2 (Slot 3)
  current_slot_matchup: {slot:3, opponent_locked:true, opponent_element:water, opponent_polarity:light, note:"你的 slot 3 只与对手的 slot 3 对位结算"}
  self.hp=20, energy_remaining=5, slots_left_including_current=2, avg_energy_budget_per_slot=2
  opponent_locked_threat: 6  // dmg=7 高威胁
  self_candidates: [
    {index:0, picked:true},
    {index:1, id:b_water_echoshield, type:def, element:water, polarity:light, cost:1, armor:8, energy_after_if_pick:4, affordable_for_remaining:true},
    {index:2, id:b_fire_scorch, type:atk, element:fire, polarity:dark, cost:2, dmg:8, energy_after_if_pick:3, affordable_for_remaining:true},
    {index:3, id:b_wood_parasite, type:atk, element:wood, polarity:dark, cost:1, dmg:4, heal:4, energy_after_if_pick:4, affordable_for_remaining:true}
  ]
  player_candidates 剩 1 张未锁: {element:wood, dmg:7}
  rule_ai_suggestion.cards: [b_water_echoshield]
{
  "reasoning": "对位slot3已锁water;我slot3出水盾同色×1.0=8甲稳;scorch(fire)留我slot4克玩家slot4的wood。",
  "card_id": "b_water_echoshield"
}

示例 C（⚠ 反面教训 — 贪心爆预算）：
  current_slot: 0 (Slot 1)，回合开始 energy_remaining=6, slots_left=4
  self_candidates: 都是 cost≥2 的牌，4 张都 affordable=false（选完只剩 4 能量给 3 个 slot 平均 1.33）
  ❌ 错误做法：贪心选 cost=3 的 b_fire_scorch（×1.5 克制），结果 slot 4 能量不够留空被对手 ×2 痛击
  ✅ 正确做法：示例 D / 示例 E（节奏控制）

示例 D（节奏控制 — 选低费稳定）：
  current_slot: 0 (Slot 1)
  current_slot_matchup: {slot:1, opponent_locked:false}
  self.hp=25, energy_remaining=6, slots_left_including_current=4, avg_energy_budget_per_slot=1
  opponent_locked_threat: 0
  self_candidates: [
    {index:0, id:b_fire_echo, cost:1, dmg:5, affordable_for_remaining:true, energy_after_if_pick:5},
    {index:1, id:b_fire_scorch, cost:3, dmg:9, affordable_for_remaining:false, energy_after_if_pick:3},  // 3 < 3 slot
    {index:2, id:b_water_echoshield, cost:1, armor:8, affordable_for_remaining:true, energy_after_if_pick:5},
    {index:3, id:b_water_freeze, cost:2, armor:7, affordable_for_remaining:true, energy_after_if_pick:4}
  ]
  rule_ai_suggestion.cards: [b_fire_echo]
{
  "reasoning": "回合开始,scorch虽强但选后只剩3能量给3slot会爆,先出echo低费保节奏。",
  "card_id": "b_fire_echo"
}

示例 E（⭐ 主动 skip — 弃局部换全局）：
  current_slot: 2 (Slot 3)
  current_slot_matchup: {slot:3, opponent_locked:true, opponent_element:fire, opponent_polarity:dark, note:"对手出 cost=1 火焰小型攻击 dmg=4"}
  self.hp=20, energy_remaining=2, slots_left_including_current=2, avg_energy_budget_per_slot=1
  opponent_locked_threat: 2  // dmg=4 cost=1 偏低威胁，吃 ×2 = 8 伤可承受
  self_candidates: [
    {index:0, picked:true}, {index:1, picked:true},
    {index:2, id:b_fire_scorch, cost:3, dmg:9, affordable_for_remaining:false, energy_after_if_pick:-1},  // 爆预算
    {index:3, id:b_wood_parasite, cost:1, dmg:4, heal:4, element:wood, affordable_for_remaining:true}  // 被 fire 克 ×0.5
  ]
  rule_ai_suggestion.cards: [b_wood_parasite]
{
  "reasoning": "scorch爆预算;parasite被fire×0.5只值2伤2治反亏;对位威胁2吃×2=8伤可承受,skip留parasite给slot4。",
  "card_id": "skip"
}

【⚠ 写 reasoning 前的强制自检（避免方向反推错）】
每次写 "我出 X 克 Y ×1.5" 之前，**必须查表确认**：
1. 找你的元素那一行（你 fire / 你 water / 你 wood）
2. 找对手元素那一列（对手 fire / 对手 water / 对手 wood）
3. 看交叉格写的是什么：
   - "你克 ×1.5" → 你赢，写 "我 X 克 Y ×1.5"
   - "你被克 ×0.5" → 你亏，写 "我 X 被 Y 克 ×0.5"
   - "同色 ×1.0" → 写 "同色 ×1.0 中性"

⚠ 完整克制对照（共 6 组方向，背下来）：
   你克 ×1.5：你 water 对手 fire / 你 wood 对手 water / 你 fire 对手 wood
   你被克 ×0.5：你 fire 对手 water / 你 water 对手 wood / 你 wood 对手 fire

⚠ 自检口诀：箭头链 = 火→木→水→火
   你出的元素**沿箭头方向**指向对手元素 = 你克 ×1.5
   对手元素**沿箭头方向**指向你的元素 = 你被克 ×0.5"""


# Provider（HTTP 客户端）
var _provider: LLMProviderBase
# 配置
var _config: LLMConfig
# Fallback 规则 AI（持久持有，避免重复创建）
var _fallback: BlindClashAI = BlindClashAI.new()
# 预取缓存
var _cached_decision: Array[CardData] = []
var _cache_round: int = -1   # 缓存对应哪一回合
var _is_warming: bool = false
var _warm_task_done: bool = false
# 历史记录（最近若干回合，由 BlindClashBattle 在每回合后填充）
var _history: Array = []
# 当前回合数（外部更新）
var _current_round: int = 0
# 思考状态
var _is_thinking_now: bool = false
# 持久网络错误计数（连续 3 次失败后整场切 fallback）
var _consecutive_failures: int = 0
const FAILURES_BEFORE_DEGRADE := 3
var _degraded_for_battle: bool = false
# 最近一次 LLM 的 reasoning（供 UI 调试显示）
var _last_reasoning: String = ""
# 最近一次失败原因（供 UI 在游戏日志中提示，例如 "LLM 超时" / "HTTP 401"）
var _last_error: String = ""
# 最近一次决策是否走了 fallback（规则 AI）
var _last_was_fallback: bool = false
# v0.4.3 新增：上一次 warm_up/sync 调用时携带的"已 peek 泄露的玩家手牌"
# 在 _do_request 内部传给 PerceptionBuilder.build → 输出 leaked_player_cards 字段
var _peeked_cards_for_request: Array = []
# v0.4.2 新增：最近一次失败是否由\"输出被截断（finish=length，max_tokens 不够）\"引起。
# 用于 UI 在 fallback 日志后追加\"Boss过载，触发奖励（未实现）\"占位条目。
var _last_was_truncated: bool = false

# v0.7.0-alpha BP Pick 状态（Epic-BP-5）
# 单 slot 决策不走预取，每次直接 await（每回合 4 次串行请求）
# 这两个字段仅用于 UI 调试展示"最近一次 BP slot 决策是 LLM 还是 fallback"
var _bp_last_slot_was_fallback: bool = false
var _bp_last_slot_card_id: String = ""
# v0.8.0 蛇形出牌：当前回合的 first_picker，由外部在 _start_bp_first_picker 时写入
var _current_first_picker: String = ""


func _init() -> void:
	_config = LLMConfig.new()
	_config.load()


## 挂载到场景树（HTTPRequest 必须有父节点）
func attach_to(host: Node) -> void:
	if not _config.is_ready_for_llm():
		return
	_provider = _config.make_provider()
	if _provider is OpenAICompatProvider:
		(_provider as OpenAICompatProvider).attach_to(host)


func get_config() -> LLMConfig:
	return _config


func is_thinking() -> bool:
	return _is_thinking_now or _is_warming


## 设置当前回合数（外部由 BlindClashBattle 在 _next_round 调用）
func set_current_round(n: int) -> void:
	_current_round = n


## v0.8.0 蛇形出牌：设置当前回合先手方（外部由 BlindClashBattle 在 _start_bp_first_picker 调用）
func set_first_picker(picker: String) -> void:
	_current_first_picker = picker


## 追加一条历史回合摘要（外部在 ROUND_END 阶段调用）
##
## entry 示例：
##   {"turn": 3, "boss_played": ["atk*2"], "player_typed": ["atk","def"], "boss_hp": 48, "player_hp": 52}
func append_history(entry: Dictionary) -> void:
	_history.append(entry)
	# 只保留最近 8 回合（保险）
	while _history.size() > 8:
		_history.pop_front()


# ------------------------------------------------------------------
# 预取（DEPLOY 阶段调用）
# ------------------------------------------------------------------
func warm_up(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe, peeked_cards: Array = []) -> void:
	if _config.force_rule_ai or _degraded_for_battle:
		return
	if not _config.is_ready_for_llm():
		return
	if _is_warming:
		return
	_is_warming = true
	_warm_task_done = false
	_cached_decision = []
	_cache_round = _current_round
	_peeked_cards_for_request = peeked_cards.duplicate()
	# fire and forget
	_do_request(boss, player, trap_slots, probe)


# ------------------------------------------------------------------
# 主决策入口（BLIND 阶段调用，await）
# ------------------------------------------------------------------
func select_blind_cards_async(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe, peeked_cards: Array = []) -> Array[CardData]:
	# 重置本次取用状态
	_last_error = ""
	_last_was_fallback = false
	_last_was_truncated = false
	# 同步设置 peek 数据（如果 warm_up 没传或本次有更新）
	if not peeked_cards.is_empty():
		_peeked_cards_for_request = peeked_cards.duplicate()

	# 强制规则 AI 模式
	if _config.force_rule_ai:
		_last_error = "force_rule_ai=true（调试开关）"
		return _fallback_decision(boss, player, trap_slots, probe)
	if _degraded_for_battle:
		_last_error = "本场已降级（连续 %d 次失败）" % _consecutive_failures
		return _fallback_decision(boss, player, trap_slots, probe)

	# 未配置 LLM → 直接 fallback
	if not _config.is_ready_for_llm():
		_last_error = "LLM 未配置（active=%s key_source=%s）" % [_config.active_provider, _config.key_source]
		return _fallback_decision(boss, player, trap_slots, probe)

	# 预取已完成且回合匹配 → 直接用
	if _warm_task_done and _cache_round == _current_round and not _cached_decision.is_empty():
		var result: Array[CardData] = _cached_decision
		_cached_decision = []
		_warm_task_done = false
		decision_ready.emit(result)
		return result

	# 预取未完成 → 等待（最多等到 timeout）
	if _is_warming:
		var t0: int = Time.get_ticks_msec()
		var hard_wait_ms: int = int(_config.timeout_sec * 1000.0)
		while _is_warming and (Time.get_ticks_msec() - t0) < hard_wait_ms:
			await Engine.get_main_loop().process_frame
		if _warm_task_done and _cache_round == _current_round and not _cached_decision.is_empty():
			var result2: Array[CardData] = _cached_decision
			_cached_decision = []
			_warm_task_done = false
			decision_ready.emit(result2)
			return result2
		# 等超时了或者预取失败
		if _is_warming:
			_last_error = "LLM 超时（等待 %.1fs 无响应，使用规则 AI）" % _config.timeout_sec
		elif _last_error.is_empty():
			_last_error = "LLM 请求失败（见 llm_log.txt）"
		return _fallback_decision(boss, player, trap_slots, probe)

	# 预取没产出 → 同步发起一次
	_do_request(boss, player, trap_slots, probe)
	# 等结果
	var t1: int = Time.get_ticks_msec()
	var hard_wait_ms2: int = int(_config.timeout_sec * 1000.0)
	while _is_warming and (Time.get_ticks_msec() - t1) < hard_wait_ms2:
		await Engine.get_main_loop().process_frame
	if _warm_task_done and not _cached_decision.is_empty():
		var result3: Array[CardData] = _cached_decision
		_cached_decision = []
		_warm_task_done = false
		decision_ready.emit(result3)
		return result3

	# 实在不行
	if _is_warming:
		_last_error = "LLM 超时（%.1fs 无响应）" % _config.timeout_sec
	elif _last_error.is_empty():
		_last_error = "LLM 请求失败（见 llm_log.txt）"
	return _fallback_decision(boss, player, trap_slots, probe)


# ------------------------------------------------------------------
# 内部：发起 LLM 请求并填缓存
# ------------------------------------------------------------------
func _do_request(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe) -> void:
	_is_thinking_now = true

	# 先让规则 AI 给个建议（作为 LLM 的"直觉系统"参考）
	# 注意：这里规则 AI 会真的从 boss.hand 中取走牌（select_blind_cards 会调用 boss.hand.erase）
	# 所以我们用一个 hand 副本调用避免污染
	var rule_suggestion: Array[CardData] = _get_rule_ai_suggestion(boss, player, trap_slots, probe)

	# 构建 perception（含规则 AI 建议 + 洞察泄露的玩家手牌）
	var perception: Dictionary = PerceptionBuilder.build(
		boss, player, trap_slots, probe, _current_round, _history, rule_suggestion, _peeked_cards_for_request
	)
	var user_msg: String = JSON.stringify(perception)

	var messages: Array = [
		{"role": "system", "content": SYSTEM_PROMPT},
		{"role": "user", "content": user_msg},
	]

	# 调试日志：仅记录"玩家信息摘要"，不再 dump 完整 prompt（SYSTEM 固定常驻、USER 太冗长）
	if _config.log_prompts:
		_log_prompt_summary(perception)

	# 发起请求（计时）
	var req_start_ms: int = Time.get_ticks_msec()
	var resp: Dictionary = await _provider.request_chat(messages, true)
	var total_ms: int = Time.get_ticks_msec() - req_start_ms

	if not resp.get("ok", false):
		var err_msg: String = String(resp.get("error", "unknown"))
		var status: int = int(resp.get("status", 0))
		push_warning("[LLMBossAI] 请求失败 round=%d status=%d latency=%dms err=%s" % [_current_round, status, total_ms, err_msg])
		if _config.log_prompts:
			_log_failure(err_msg, status, total_ms)
		_last_error = "LLM 失败 (status=%d) %s" % [status, err_msg.left(80)]
		_consecutive_failures += 1
		if _consecutive_failures >= FAILURES_BEFORE_DEGRADE:
			_degraded_for_battle = true
			push_warning("[LLMBossAI] 连续 %d 次失败，本场战斗剩余回合切到规则 AI" % _consecutive_failures)
		_is_warming = false
		_warm_task_done = false
		_cached_decision = []
		_is_thinking_now = false
		return

	# 校验 + 修正
	var validation: ActionValidator.ValidationResult = ActionValidator.parse_and_validate(
		String(resp.get("content", "")), boss, 3
	)

	# 成功日志（含 usage + latency + finish_reason + 完整 content）
	if _config.log_prompts:
		_log_response(String(resp.get("content", "")), validation, resp, total_ms)

	print("[LLMBossAI] round=%d latency=%dms validated=%s corrected=%s picks=%d" % [
		_current_round, total_ms, str(validation.ok), str(validation.was_corrected), validation.cards.size()
	])

	if not validation.ok:
		# 区分截断 vs 真校验失败 —— finish=length 多半是 max_tokens 不够
		var finish_reason: String = String(resp.get("finish_reason", ""))
		if finish_reason == "length":
			# 注意：必须用 effective_max_tokens（实际发给 API 的值），
			# 而不是 _provider.max_tokens —— 后者可能小于实际值（provider 内部有 1200 下限兜底）
			var eff_max: int = int(resp.get("effective_max_tokens", _provider.max_tokens))
			push_warning("[LLMBossAI] 输出被截断 (finish=length)，max_tokens=%d 不够" % eff_max)
			_last_error = "LLM 输出被截断 (max_tokens=%d 不够，请增大)" % eff_max
			_last_was_truncated = true
		else:
			push_warning("[LLMBossAI] 校验失败: %s" % validation.error)
			_last_error = "LLM 输出校验失败: %s" % validation.error
		_consecutive_failures += 1
		if _consecutive_failures >= FAILURES_BEFORE_DEGRADE:
			_degraded_for_battle = true
		_is_warming = false
		_warm_task_done = false
		_cached_decision = []
		_is_thinking_now = false
		return

	# 成功 ✓
	_consecutive_failures = 0
	_cached_decision = validation.cards
	_last_reasoning = validation.reasoning
	_warm_task_done = true
	_is_warming = false
	_is_thinking_now = false


func _fallback_decision(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe) -> Array[CardData]:
	_last_was_fallback = true
	var cards: Array[CardData] = _fallback.select_blind_cards(boss, player, trap_slots, probe)
	decision_ready.emit(cards)
	return cards


## 调规则 AI 的 preview 版（纯读取，不修改 boss.hand）取建议
## 这一步是把"规则 AI 的直觉"作为参考注入 LLM 的关键
func _get_rule_ai_suggestion(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe) -> Array[CardData]:
	if _fallback == null or not _fallback.has_method("preview_blind_cards"):
		return []
	return _fallback.preview_blind_cards(boss, player, trap_slots, probe)


func cancel() -> void:
	_is_warming = false
	_is_thinking_now = false
	_cached_decision = []
	_warm_task_done = false


## 最近一次决策是否走了规则 AI fallback
func was_last_decision_fallback() -> bool:
	return _last_was_fallback


## 最近一次失败/fallback 的原因（用于 UI 提示）
func get_last_error() -> String:
	return _last_error


## v0.4.2：最近一次 fallback 是否由\"LLM 输出被截断（finish=length / max_tokens 不够）\"引起。
## UI 在 was_last_decision_fallback() 为 true 时再查这个字段，
## 决定是否追加\"Boss过载，触发奖励（未实现）\"日志。
func was_last_truncated() -> bool:
	return _last_was_truncated


# ------------------------------------------------------------------
# 日志（llm_log.txt 完整链路）
# 设计原则：SYSTEM 不打（常驻已知）/ USER 仅打摘要（局面快照）/ RESPONSE 打全
# ------------------------------------------------------------------
func _log_prompt_summary(perception: Dictionary) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	var divider := "================================================================"
	f.store_string("\n%s\n" % divider)
	f.store_string("[%s] [REQUEST]  round=%d  provider=%s  model=%s\n" % [
		ts, _current_round, _provider.get_provider_name() if _provider else "?", _config.model
	])
	f.store_string("%s\n" % divider)

	# 关键字段摘要（按 PerceptionBuilder 的真实 schema）
	var self_info: Dictionary = perception.get("self", {})
	var self_hand: Array = perception.get("self_hand", [])
	var player_info: Dictionary = perception.get("player", {})
	var probe_hint: Dictionary = perception.get("probe_hint", {})
	var rule_sug: Dictionary = perception.get("rule_ai_suggestion", {})
	var history: Array = perception.get("history", [])
	var energy_budget = perception.get("energy_budget", "?")

	# Boss 自己
	var hand_brief: Array = []
	for c in self_hand:
		if c is Dictionary:
			hand_brief.append("%s(%s/%d费)" % [c.get("name", "?"), c.get("type", "?"), int(c.get("cost", 0))])
	f.store_string("[Boss]   hp=%s/%s  armor=%s  energy=%s  charged=%s  hand(%d)=%s\n" % [
		str(self_info.get("hp", "?")), str(self_info.get("max_hp", "?")),
		str(self_info.get("armor", 0)),
		str(energy_budget),
		str(self_info.get("is_charged", false)),
		hand_brief.size(),
		", ".join(hand_brief),
	])

	# 玩家（含陷阱槽，bug 修复后这里应能看到 occupied）
	f.store_string("[Player] hp=%s/%s  armor=%s  hand_count=%s  deck_count=%s\n" % [
		str(player_info.get("hp", "?")), str(player_info.get("max_hp", "?")),
		str(player_info.get("armor", 0)),
		str(player_info.get("hand_count", "?")),
		str(player_info.get("deck_count", "?")),
	])
	f.store_string("[Traps]  attack=%s  skill=%s  high_cost=%s\n" % [
		str(player_info.get("trap_slot_attack", "empty")),
		str(player_info.get("trap_slot_skill", "empty")),
		str(player_info.get("trap_slot_high_cost", "empty")),
	])

	# 探针
	f.store_string("[Probe]  prediction=%s  streak=%s\n" % [
		str(probe_hint.get("prediction", "?")),
		str(probe_hint.get("streak", 0)),
	])

	# v0.4.3：洞察泄露的玩家手牌（peek 应用后的真实情报）
	var leaked: Array = perception.get("leaked_player_cards", [])
	if leaked.is_empty():
		f.store_string("[Leaked] 无泄露牌（本回合无 peek 生效）\n")
	else:
		var leaked_brief: Array = []
		for c in leaked:
			if c is Dictionary:
				leaked_brief.append("%s(%s/%d费)" % [c.get("name", "?"), c.get("type", "?"), int(c.get("cost", 0))])
		f.store_string("[Leaked] 玩家手牌泄露 %d 张：%s\n" % [leaked.size(), ", ".join(leaked_brief)])

	# 规则 AI 建议
	var rule_names: Array = rule_sug.get("names", [])
	if rule_names.is_empty():
		f.store_string("[Rule AI 建议] %s\n" % str(rule_sug.get("note", "无")))
	else:
		f.store_string("[Rule AI 建议] %s (总费=%s)\n" % [
			", ".join(rule_names), str(rule_sug.get("total_cost", "?")),
		])

	f.store_string("[History] 最近 %d 回合摘要随 prompt 一起发送\n" % history.size())
	f.close()


func _log_response(content: String, validation: ActionValidator.ValidationResult, resp: Dictionary, total_ms: int) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	var usage: Dictionary = resp.get("usage", {})
	var prompt_tok: int = int(usage.get("prompt_tokens", 0))
	var comp_tok: int = int(usage.get("completion_tokens", 0))
	var total_tok: int = int(usage.get("total_tokens", 0))
	var status: int = int(resp.get("status", 0))
	var finish: String = String(resp.get("finish_reason", ""))

	f.store_string("\n--- RESPONSE ---\n")
	f.store_string("[%s]  status=%d  latency=%dms  finish=%s" % [ts, status, total_ms, finish])
	if finish == "length":
		var eff_max_log: int = int(resp.get("effective_max_tokens", _provider.max_tokens))
		f.store_string("  ⚠ 被截断（max_tokens=%d 不够）" % eff_max_log)
	f.store_string("\n")
	f.store_string("tokens: prompt=%d  completion=%d  total=%d  (max_tokens_sent=%d)\n" % [
		prompt_tok, comp_tok, total_tok,
		int(resp.get("effective_max_tokens", _provider.max_tokens))
	])
	f.store_string("validated=%s  corrected=%s  picked_cards=%d\n" % [
		str(validation.ok), str(validation.was_corrected), validation.cards.size()
	])
	if validation.cards.size() > 0:
		var ids: Array = []
		for c in validation.cards:
			ids.append(String(c.id))
		f.store_string("picked_ids=%s\n" % JSON.stringify(ids))
	if validation.reasoning.length() > 0:
		f.store_string("reasoning: %s\n" % validation.reasoning)

	# 【usage 详情】DeepSeek/OpenAI 可能含 reasoning_tokens、prompt_cache_hit_tokens 等子字段
	# 完整 dump 用于诊断"思考 token 是否被推理模式独占"
	if not usage.is_empty():
		f.store_string("--- USAGE 详情 ---\n")
		f.store_string(JSON.stringify(usage, "  "))
		f.store_string("\n")

	# 【MESSAGE 全字段】OpenAI 标准只有 content，但 DeepSeek 推理模型会多输出 reasoning_content；
	# 部分模型还有 tool_calls / refusal 等。完整 dump 才能确认 token 跑哪去了。
	var raw: Dictionary = resp.get("raw", {})
	var choices: Array = raw.get("choices", []) if raw is Dictionary else []
	if not choices.is_empty():
		var first: Dictionary = choices[0] if choices[0] is Dictionary else {}
		var message: Dictionary = first.get("message", {}) if first.get("message", {}) is Dictionary else {}
		f.store_string("--- MESSAGE 全字段 (keys=%s) ---\n" % str(message.keys()))
		# 逐字段标长度后再 dump，便于一眼看出哪个字段吃了 token
		for k in message.keys():
			var v = message[k]
			var v_str: String = ""
			if v is String:
				v_str = v
			elif v == null:
				v_str = "<null>"
			else:
				v_str = JSON.stringify(v)
			f.store_string("  [%s] (%d 字符): %s\n" % [str(k), v_str.length(), v_str])

	# RAW CONTENT —— content 字段单独突出（这是验证器实际解析的内容）
	f.store_string("--- RAW CONTENT (%d 字符) ---\n" % content.length())
	if content.length() > 0:
		f.store_string(content)
	else:
		f.store_string("(空 —— content 字段为空。若 MESSAGE 全字段中 reasoning_content 不为空，说明用的是推理模型，思考占满 token 后没产出最终回答)")
	f.store_string("\n")

	# 完整 raw response（最后兜底，便于排查未知字段）
	f.store_string("--- FULL RAW RESPONSE ---\n")
	if raw is Dictionary and not raw.is_empty():
		f.store_string(JSON.stringify(raw, "  "))
	else:
		f.store_string("(无 raw)")
	f.store_string("\n")
	f.close()


func _log_failure(err: String, status: int, total_ms: int) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	f.store_string("--- FAILURE ---\n")
	f.store_string("[%s]  status=%d  latency=%dms  err=%s\n" % [ts, status, total_ms, err])
	f.close()


## 打开日志文件（追加模式，不存在则创建）
func _open_log_append() -> FileAccess:
	var f: FileAccess = null
	if FileAccess.file_exists(_config.log_path):
		f = FileAccess.open(_config.log_path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(_config.log_path, FileAccess.WRITE)
	return f


## 取最近一次的 reasoning（供 UI / 日志显示）
func get_last_reasoning() -> String:
	return _last_reasoning


# ==================================================================
# v0.7.0-alpha BP 单 Slot Pick 接口（Epic-BP-5）
# ==================================================================
##
## BP 模式下，BlindClashBattle 在每个 slot 轮到 Boss 时调用此函数。
## 不走预取（与 select_blind_cards_async 不同）：玩家点完前一 slot 才轮到 Boss，
## 此时 LLM 已无法提前发请求 → 每次 slot 单独 await 一次 LLM。
##
## 失败链：force_rule_ai / 未配置 LLM / LLM 出错 / 校验失败 → 返回 -1，
## 由 BlindClashBattle 调用方走 _boss_rule_pick 兜底。
##
## @param boss               Boss Combatant（能量已扣除前序 slot 的 cost）
## @param player             玩家 Combatant
## @param boss_candidates    Boss 4 张候选（已 Pick 位为 null）
## @param player_candidates  玩家 4 张候选（Q-BP-1 完全可见）
## @param boss_picks         Boss 已锁定的 picks（4 槽，未锁为 null）
## @param player_picks       玩家已锁定的 picks
## @param current_slot       当前要决策的 slot（0~3）
## @param round_number       当前回合数
## @param rule_pick_index    规则 AI 对当前 slot 的推荐（候选数组 index，仅作参考；< 0 表示无）
## @return                   选中的候选 index（0~3），失败返回 -1
func pick_for_slot_async(
	boss: Combatant,
	player: Combatant,
	boss_candidates: Array,
	player_candidates: Array,
	boss_picks: Array,
	player_picks: Array,
	current_slot: int,
	round_number: int,
	rule_pick_index: int = -1
) -> int:
	# 重置状态
	_last_error = ""
	_bp_last_slot_was_fallback = false
	_bp_last_slot_card_id = ""

	# 强制规则 AI / 已降级 / 未配置 → 立即返回 -1，调用方走 fallback
	if _config.force_rule_ai:
		_last_error = "force_rule_ai=true（调试开关）"
		_bp_last_slot_was_fallback = true
		return -1
	if _degraded_for_battle:
		_last_error = "本场已降级（连续 %d 次失败）" % _consecutive_failures
		_bp_last_slot_was_fallback = true
		return -1
	if not _config.is_ready_for_llm():
		_last_error = "LLM 未配置（active=%s key_source=%s）" % [_config.active_provider, _config.key_source]
		_bp_last_slot_was_fallback = true
		return -1
	if _provider == null:
		_last_error = "LLM provider 未挂载（attach_to 未调用？）"
		_bp_last_slot_was_fallback = true
		return -1

	_is_thinking_now = true

	# 把规则 AI 的推荐 index 映射回 CardData 数组（PerceptionBuilder 要求 [CardData]）
	var rule_suggestion: Array[CardData] = []
	if rule_pick_index >= 0 and rule_pick_index < boss_candidates.size():
		var rec = boss_candidates[rule_pick_index]
		if rec is CardData:
			rule_suggestion.append(rec)

	# 构建 BP 单 slot perception
	var perception: Dictionary = PerceptionBuilder.build_for_slot_pick(
		boss, player, boss_candidates, player_candidates,
		boss_picks, player_picks, current_slot, round_number,
		_history, rule_suggestion, _current_first_picker
	)
	var user_msg: String = JSON.stringify(perception)
	var messages: Array = [
		{"role": "system", "content": SYSTEM_PROMPT_BP_SLOT},
		{"role": "user", "content": user_msg},
	]

	if _config.log_prompts:
		_log_bp_prompt_summary(perception, current_slot)

	# 发起请求
	var req_start_ms: int = Time.get_ticks_msec()
	var resp: Dictionary = await _provider.request_chat(messages, true)
	var total_ms: int = Time.get_ticks_msec() - req_start_ms

	if not resp.get("ok", false):
		var err_msg: String = String(resp.get("error", "unknown"))
		var status: int = int(resp.get("status", 0))
		push_warning("[LLMBossAI/BP] slot=%d 请求失败 status=%d latency=%dms err=%s" % [current_slot, status, total_ms, err_msg])
		if _config.log_prompts:
			_log_failure(err_msg, status, total_ms)
		_last_error = "LLM 失败 (status=%d) %s" % [status, err_msg.left(80)]
		_consecutive_failures += 1
		if _consecutive_failures >= FAILURES_BEFORE_DEGRADE:
			_degraded_for_battle = true
			push_warning("[LLMBossAI/BP] 连续 %d 次失败，本场战斗剩余切规则 AI" % _consecutive_failures)
		_bp_last_slot_was_fallback = true
		_is_thinking_now = false
		return -1

	# 解析输出 —— BP 单 slot 用的是 {"reasoning":..., "card_id":...} 而非 action_sequence
	var content: String = String(resp.get("content", ""))
	var validation_result: Dictionary = _parse_bp_slot_response(content, boss_candidates, boss.energy)

	# 成功日志
	if _config.log_prompts:
		_log_bp_response(content, validation_result, resp, total_ms, current_slot)

	print("[LLMBossAI/BP] slot=%d latency=%dms ok=%s pick_idx=%d corrected=%s" % [
		current_slot, total_ms, str(validation_result.get("ok", false)),
		int(validation_result.get("pick_index", -1)),
		str(validation_result.get("was_corrected", false))
	])

	if not validation_result.get("ok", false):
		# 区分截断 vs 校验失败
		var finish_reason: String = String(resp.get("finish_reason", ""))
		if finish_reason == "length":
			var eff_max: int = int(resp.get("effective_max_tokens", _provider.max_tokens))
			push_warning("[LLMBossAI/BP] slot=%d 输出被截断 max_tokens=%d 不够" % [current_slot, eff_max])
			_last_error = "LLM 输出被截断 (max_tokens=%d 不够)" % eff_max
			_last_was_truncated = true
		else:
			var err: String = String(validation_result.get("error", "校验失败"))
			push_warning("[LLMBossAI/BP] slot=%d 校验失败: %s" % [current_slot, err])
			_last_error = "LLM 输出校验失败: %s" % err
		_consecutive_failures += 1
		if _consecutive_failures >= FAILURES_BEFORE_DEGRADE:
			_degraded_for_battle = true
		_bp_last_slot_was_fallback = true
		_is_thinking_now = false
		return -1

	# 成功
	_consecutive_failures = 0
	_last_reasoning = String(validation_result.get("reasoning", ""))
	_bp_last_slot_card_id = String(validation_result.get("card_id", ""))
	_is_thinking_now = false

	# v0.8.2 方案 D-3：LLM 主动 skip → 返回 -2（与失败的 -1 区分）
	if bool(validation_result.get("is_skip", false)):
		# 智能降级：如果对位威胁高 + 候选还有便宜的可填 → 强制改为低费牌
		var pick_idx_final: int = _resolve_skip_or_force_lowcost(
			boss_candidates, boss.energy, current_slot, player_picks
		)
		if pick_idx_final == -2:
			print("[LLMBossAI/BP] slot=%d LLM skip 已尊重（对位威胁低或无便宜牌）" % current_slot)
		else:
			print("[LLMBossAI/BP] slot=%d LLM 想 skip 但对位威胁高,改为低费 idx=%d" % [current_slot, pick_idx_final])
			_bp_last_slot_card_id = "[降级:防爆血]" + _bp_last_slot_card_id
		return pick_idx_final

	# v0.8.2 方案 D-3：前瞻校验 — LLM 选了具体牌但会爆预算？
	var raw_pick_idx: int = int(validation_result.get("pick_index", -1))
	if raw_pick_idx < 0:
		return -1
	var chosen_card: CardData = boss_candidates[raw_pick_idx]
	if chosen_card != null:
		var energy_after: int = boss.energy - chosen_card.energy_cost
		var slots_left_after: int = 4 - current_slot - 1
		# 爆预算 = 选完后剩余能量 < 剩余 slot × 1（每个 slot 至少 1 费保底）
		if energy_after < slots_left_after:
			print("[LLMBossAI/BP] slot=%d ⚠ LLM 选 %s (cost=%d) 会爆预算 (after=%d < slots_left=%d)" % [
				current_slot, chosen_card.card_name, chosen_card.energy_cost,
				energy_after, slots_left_after
			])
			# 智能降级：对位威胁高 → 改为最低费 affordable 牌；威胁低 → skip
			var threat: int = _estimate_opponent_threat(player_picks, current_slot)
			if threat >= 5:
				# 高威胁：必须填 slot，找最低费 affordable
				var fallback_idx: int = _find_lowest_cost_affordable(
					boss_candidates, boss.energy, current_slot, raw_pick_idx
				)
				if fallback_idx >= 0:
					print("[LLMBossAI/BP] slot=%d ⚠ 威胁=%d 高,降级为低费 idx=%d 防爆血" % [
						current_slot, threat, fallback_idx
					])
					_bp_last_slot_card_id = "[降级:防爆血]" + _bp_last_slot_card_id
					return fallback_idx
				# 找不到便宜牌 → 仍用 LLM 选择（接受爆预算）
				print("[LLMBossAI/BP] slot=%d ⚠ 威胁高但无低费可换,仍采用 LLM 选择" % current_slot)
				return raw_pick_idx
			else:
				# 低威胁：尊重战术意图，改为 skip
				print("[LLMBossAI/BP] slot=%d ⚠ 威胁=%d 低,改为 skip 保留候选给后续 slot" % [
					current_slot, threat
				])
				_bp_last_slot_card_id = "[降级:skip]"
				return -2

	return raw_pick_idx


# ==================================================================
# v0.8.2 方案 D-3：前瞻校验辅助方法
# ==================================================================

## 估算对位玩家牌的"威胁度"（与 perception_builder._compute_opponent_threat 同算法）
func _estimate_opponent_threat(player_picks: Array, current_slot: int) -> int:
	if current_slot < 0 or current_slot >= player_picks.size():
		return 0
	var card = player_picks[current_slot]
	if card == null or not (card is CardData):
		return 0
	var threat: float = 0.0
	threat += card.damage
	threat += card.armor * 0.7
	threat += card.energy_cost * 1.5
	if card.ignore_armor:
		threat += 2.0
	return int(round(threat))


## 在候选中找最低费 affordable 牌（排除已 Pick / 排除 LLM 原选 / 排除爆预算）
## 返回 -1 = 找不到
func _find_lowest_cost_affordable(boss_candidates: Array, energy_now: int,
		current_slot: int, exclude_idx: int) -> int:
	var slots_left_after: int = 4 - current_slot - 1
	var best_idx: int = -1
	var best_cost: int = INT_MAX
	for i in range(boss_candidates.size()):
		if i == exclude_idx:
			continue
		var c = boss_candidates[i]
		if c == null or not (c is CardData):
			continue
		var card_data: CardData = c
		if card_data.energy_cost > energy_now:
			continue  # cost 超能量
		if card_data.energy_cost == 0:
			continue  # 0 费由 zerocost 通道处理
		var energy_after: int = energy_now - card_data.energy_cost
		if energy_after < slots_left_after:
			continue  # 选了仍爆预算
		if card_data.energy_cost < best_cost:
			best_cost = card_data.energy_cost
			best_idx = i
	return best_idx


## LLM 主动 skip 时的智能判定：
## 高威胁 + 有便宜牌可填 → 强制改为低费牌（防爆血）
## 低威胁 / 无便宜牌 → 尊重 LLM skip 决策
## 返回：>=0 = 强制改为该 idx；-2 = 尊重 skip
func _resolve_skip_or_force_lowcost(boss_candidates: Array, energy_now: int,
		current_slot: int, player_picks: Array) -> int:
	var threat: int = _estimate_opponent_threat(player_picks, current_slot)
	if threat < 6:
		return -2  # 威胁低，尊重 skip
	# 威胁高：尝试找最低费 affordable 牌强制填
	var forced_idx: int = _find_lowest_cost_affordable(
		boss_candidates, energy_now, current_slot, -1
	)
	if forced_idx >= 0:
		return forced_idx
	# 找不到便宜牌 → 尊重 skip（即使威胁高也只能空着）
	return -2


# 整数最大值常量
const INT_MAX: int = 9223372036854775807


## 最近一次 BP slot 决策是否走了 fallback（规则 AI）
func was_last_bp_slot_fallback() -> bool:
	return _bp_last_slot_was_fallback


## 解析 BP 单 slot 响应：
##   { "reasoning": "...", "card_id": "boss_xxx" 或 "skip" }
##
## 校验链：
##   1. 抽 JSON
##   2. 必须含 card_id 字段
##   3. v0.8.2：card_id == "skip" → is_skip=true，pick_index=-1（特殊语义）
##   4. 否则：card_id 必须在 boss_candidates 中且未被 Pick（c != null）
##   5. cost 不超 boss.energy
##
## @return Dictionary { ok, pick_index, card_id, reasoning, error, was_corrected, is_skip }
func _parse_bp_slot_response(raw: String, boss_candidates: Array, energy_available: int) -> Dictionary:
	var result := {"ok": false, "pick_index": -1, "card_id": "", "reasoning": "", "error": "", "was_corrected": false, "is_skip": false}

	var json_str: String = LLMProviderBase.extract_json_from_text(raw)
	if json_str.is_empty():
		result["error"] = "无法抽取 JSON"
		return result

	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null:
		result["error"] = "JSON 解析失败"
		return result
	if not parsed is Dictionary:
		result["error"] = "JSON 根节点非 Object"
		return result

	result["reasoning"] = String(parsed.get("reasoning", ""))
	var card_id: String = String(parsed.get("card_id", ""))
	if card_id.is_empty():
		result["error"] = "缺少 card_id"
		return result

	# v0.8.2 方案 D-3：支持 LLM 主动 skip
	if card_id == "skip" or card_id == "SKIP" or card_id == "Skip":
		result["ok"] = true
		result["is_skip"] = true
		result["card_id"] = "skip"
		# pick_index 保持 -1，调用方根据 is_skip 区分"主动 skip"和"失败"
		return result

	# 在候选里找
	var found_idx: int = -1
	for i in range(boss_candidates.size()):
		var c = boss_candidates[i]
		if c == null:
			continue
		if c is CardData and String(c.id) == card_id:
			found_idx = i
			break

	if found_idx < 0:
		result["error"] = "card_id '%s' 不在候选中（或已被 Pick）" % card_id
		return result

	var card: CardData = boss_candidates[found_idx]
	if card.energy_cost > energy_available:
		result["error"] = "card_id '%s' cost=%d 超能量预算 %d" % [card_id, card.energy_cost, energy_available]
		return result

	result["ok"] = true
	result["pick_index"] = found_idx
	result["card_id"] = card_id
	return result


## BP 单 slot prompt 摘要日志
func _log_bp_prompt_summary(perception: Dictionary, current_slot: int) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	var divider := "================================================================"
	f.store_string("\n%s\n" % divider)
	f.store_string("[%s] [BP REQUEST]  round=%d  slot=%d  provider=%s  model=%s\n" % [
		ts, _current_round, current_slot + 1,
		_provider.get_provider_name() if _provider else "?", _config.model
	])
	f.store_string("%s\n" % divider)

	var self_info: Dictionary = perception.get("self", {})
	var energy_remaining = perception.get("energy_remaining", "?")
	var avg_budget = perception.get("avg_energy_budget_per_slot", "?")
	var slots_left = perception.get("slots_left_including_current", "?")

	f.store_string("[Boss]   hp=%s/%s  energy=%s  剩余 slot=%s  平均预算=%s\n" % [
		str(self_info.get("hp", "?")), str(self_info.get("max_hp", "?")),
		str(energy_remaining), str(slots_left), str(avg_budget),
	])

	# Boss 候选
	var self_cands: Array = perception.get("self_candidates", [])
	var sc_brief: Array = []
	for c in self_cands:
		if c is Dictionary and c.get("picked", false) == false:
			sc_brief.append("%s(%s/%d费)" % [c.get("name", "?"), c.get("type", "?"), int(c.get("cost", 0))])
	f.store_string("[Boss候选可选] %s\n" % (", ".join(sc_brief) if sc_brief.size() > 0 else "(无)"))

	# 玩家候选（明牌）
	var p_cands: Array = perception.get("player_candidates", [])
	var pc_brief: Array = []
	for c in p_cands:
		if c is Dictionary and c.get("picked", false) == false:
			pc_brief.append("%s(%s/%d费)" % [c.get("name", "?"), c.get("type", "?"), int(c.get("cost", 0))])
	f.store_string("[玩家候选明牌] %s\n" % (", ".join(pc_brief) if pc_brief.size() > 0 else "(无)"))

	# Picks 摘要（双方）
	var bp: Array = perception.get("self_picks", [])
	var pp: Array = perception.get("player_picks", [])
	var bp_brief: Array = []
	var pp_brief: Array = []
	for entry in bp:
		if entry is Dictionary and entry.get("locked", false):
			bp_brief.append("S%d=%s(%s)" % [int(entry.get("slot", 0)), entry.get("name", "?"), entry.get("type", "?")])
	for entry in pp:
		if entry is Dictionary and entry.get("locked", false):
			pp_brief.append("S%d=%s(%s)" % [int(entry.get("slot", 0)), entry.get("name", "?"), entry.get("type", "?")])
	f.store_string("[Boss已锁] %s\n" % (", ".join(bp_brief) if bp_brief.size() > 0 else "(无)"))
	f.store_string("[玩家已锁] %s\n" % (", ".join(pp_brief) if pp_brief.size() > 0 else "(无)"))

	# 规则 AI 建议
	var rule_sug: Dictionary = perception.get("rule_ai_suggestion", {})
	var rule_names: Array = rule_sug.get("names", [])
	if rule_names.is_empty():
		f.store_string("[Rule AI] 无建议\n")
	else:
		f.store_string("[Rule AI] 推荐: %s\n" % ", ".join(rule_names))

	f.close()


## BP 单 slot response 日志
func _log_bp_response(content: String, validation: Dictionary, resp: Dictionary, total_ms: int, current_slot: int) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	var usage: Dictionary = resp.get("usage", {})
	var prompt_tok: int = int(usage.get("prompt_tokens", 0))
	var comp_tok: int = int(usage.get("completion_tokens", 0))
	var total_tok: int = int(usage.get("total_tokens", 0))
	var status: int = int(resp.get("status", 0))
	var finish: String = String(resp.get("finish_reason", ""))

	f.store_string("\n--- BP RESPONSE (slot=%d) ---\n" % (current_slot + 1))
	f.store_string("[%s]  status=%d  latency=%dms  finish=%s" % [ts, status, total_ms, finish])
	if finish == "length":
		f.store_string("  ⚠ 被截断（max_tokens=%d 不够）" % int(resp.get("effective_max_tokens", _provider.max_tokens)))
	f.store_string("\n")
	f.store_string("tokens: prompt=%d  completion=%d  total=%d\n" % [prompt_tok, comp_tok, total_tok])
	f.store_string("validated=%s  pick_idx=%d  card_id=%s\n" % [
		str(validation.get("ok", false)),
		int(validation.get("pick_index", -1)),
		String(validation.get("card_id", "")),
	])
	if String(validation.get("reasoning", "")).length() > 0:
		f.store_string("reasoning: %s\n" % String(validation.get("reasoning", "")))
	if String(validation.get("error", "")).length() > 0:
		f.store_string("error: %s\n" % String(validation.get("error", "")))

	# RAW CONTENT
	f.store_string("--- RAW CONTENT (%d 字符) ---\n" % content.length())
	if content.length() > 0:
		f.store_string(content)
	else:
		f.store_string("(空)")
	f.store_string("\n")
	f.close()
