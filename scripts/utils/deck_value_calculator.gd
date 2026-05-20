class_name DeckValueCalculator
extends RefCounted
## 牌库价值评估工具（v0.9.4 自调升级牌 PR-1）
##
## 用途：
##   1. RewardScreen 用 calc_budget(player, boss, round_index) 计算\"自调建造预算\"
##   2. PerceptionBuilder 可选用 calc_deck_value() 给 LLM 提供 deck_value_diff 字段
##
## 设计原则：
##   - 静态工具类，无状态，可在任意上下文调用
##   - 公式与游戏内真实结算价值高度对齐（damage 1.0 / armor 0.7 / heal 1.0）
##   - 关键字加成基于历史 4 选 1 升级牌定价反推（保持与 v0.8.3 数值膨胀一致）
##   - 公式参数集中在常量段，方便后续 playtest 微调


## ============================================================
## 单卡基础价值表（每点效果对应的"价值分"）
## ============================================================

## 直接资源价值
const VAL_DAMAGE: float = 1.0          # 伤害 1 点 = 1.0 价值
const VAL_ARMOR: float = 0.7           # 护甲 1 点 = 0.7 价值（持续性次于爆发）
const VAL_HEAL: float = 1.0            # 治疗 1 点 = 1.0 价值（v0.9.3 等价于 1 点伤害）
const VAL_DRAW: float = 2.5            # 抽牌 1 张 = 2.5 价值（引擎效应）

## 关键字加成（独立加成，不与基础数值相乘）
const VAL_IGNORE_ARMOR: float = 1.5    # 无视护甲（依附于 damage > 0 的牌）
const VAL_REFLECT_DAMAGE_PER: float = 0.8  # 反伤每点
const VAL_NEXT_ATTACK_BONUS_PER: float = 0.8  # 下次攻击+X 每点
const VAL_ALL_ATTACK_BONUS_PER: float = 1.2  # 本回合所有攻击+X（更强）
const VAL_GRANTS_CHARGE: float = 1.0   # 给予蓄力
const VAL_REQUIRES_CHARGE_PENALTY: float = -0.8  # 需要蓄力（条件牌折扣）
const VAL_HITS_BONUS_PER: float = 0.5  # 多段攻击 hits>1 每段额外加成
const VAL_BONUS_IF_ATTACKED_PER: float = 0.6  # 本回合已出过攻击则+X
const VAL_ARMOR_ON_HIT_PER: float = 0.5  # 受伤获甲
const VAL_DISCARD_AND_DRAW: float = 1.5  # 弃手抽 X
const VAL_RESHUFFLE_DISCARD: float = 2.0  # 洗回牌库

## 元素 + 光暗 加分（已纳入克制 + 2:2 体系的牌价值更高）
const VAL_HAS_ELEMENT: float = 1.5     # 有 element 标记（参与火水木克制）
const VAL_HAS_POLARITY: float = 1.0    # 有 polarity 标记（参与光暗 2:2）

## 费用折扣：每点费用扣多少（牌的"使用门槛"）
## v0.8.3 数值膨胀：能量 6→10，所以费用价值占比下降，本工具用 1.0 平衡
const VAL_PER_ENERGY_COST: float = 1.0


## ============================================================
## 预算公式参数（v0.9.4 自调升级牌核心）
## ============================================================

## 关卡基线预算（玩家无论平衡如何都至少能建造的最小有用牌）
## v0.9.4 v4：再次上调（v3 7/9/11 仍被玩家反馈太抠 → 现 10/13/15）
## 配合数值上限放宽（1 费 dmg 6→8，对齐\"凤凰击 8 伤\"等升级牌强度）
## 让玩家能造\"和现役升级牌相当或更强\"的牌，而非\"乞丐版\"
const BASE_BUDGET_BY_ROUND: Dictionary = {
	1: 8,   # R1 不解锁（首周目走 4 选 1，2 周目才解锁，预留）
	2: 10,
	3: 13,
	4: 15,
	5: 16,  # R5 终局，但实际 R5 已不再 reward，预留
}

## 强弱差缩放系数：玩家落后 N 点价值 → 多拿 N × 0.4 点 budget
const GAP_SCALING: float = 0.4

## 单次最大调整幅度（避免极端 deck 差距导致预算爆表）
const MAX_GAP_ADJUST: int = 5

## budget 总上下限（绝对夹紧）
## v0.9.4 v4：上限 14→18（让落后玩家能造 2 费深度构筑）
const MIN_BUDGET: int = 4
const MAX_BUDGET: int = 18


## ============================================================
## 公开 API
## ============================================================

## 评估单张牌的价值分
## @param card 卡牌数据；null 返回 0
## @return 价值分（float，可能小数）
static func calc_card_value(card: CardData) -> float:
	if card == null:
		return 0.0

	var v: float = 0.0

	# 直接资源
	v += card.damage * VAL_DAMAGE
	v += card.armor * VAL_ARMOR
	v += card.heal * VAL_HEAL
	v += card.draw_cards * VAL_DRAW

	# 关键字加成（仅在前置条件满足时计入，避免无效字段加分）
	if card.ignore_armor and card.damage > 0:
		v += VAL_IGNORE_ARMOR
	if card.reflect_damage > 0:
		v += card.reflect_damage * VAL_REFLECT_DAMAGE_PER
	if card.next_attack_bonus > 0:
		v += card.next_attack_bonus * VAL_NEXT_ATTACK_BONUS_PER
	if card.all_attack_bonus > 0:
		v += card.all_attack_bonus * VAL_ALL_ATTACK_BONUS_PER
	if card.grants_charge:
		v += VAL_GRANTS_CHARGE
	if card.requires_charge:
		v += VAL_REQUIRES_CHARGE_PENALTY
	if card.hits > 1 and card.damage > 0:
		v += (card.hits - 1) * VAL_HITS_BONUS_PER * maxf(card.damage, 1.0)
	if card.bonus_if_attacked_this_turn > 0:
		v += card.bonus_if_attacked_this_turn * VAL_BONUS_IF_ATTACKED_PER
	if card.armor_on_hit > 0:
		v += card.armor_on_hit * VAL_ARMOR_ON_HIT_PER
	if card.discard_hand_and_draw > 0:
		v += card.discard_hand_and_draw * VAL_DISCARD_AND_DRAW
	if card.reshuffle_discard:
		v += VAL_RESHUFFLE_DISCARD

	# 元素 + 光暗（参与克制 / 2:2 体系的牌更值钱）
	if card.element != CardData.Element.NONE:
		v += VAL_HAS_ELEMENT
	if card.polarity != CardData.Polarity.NONE:
		v += VAL_HAS_POLARITY

	# 费用折扣
	v -= card.energy_cost * VAL_PER_ENERGY_COST

	return v


## 评估整套牌库的价值
## @param deck CardData 数组
## @return 总价值分
static func calc_deck_value(deck: Array) -> float:
	var total: float = 0.0
	for c in deck:
		if c is CardData:
			total += calc_card_value(c)
	return total


## 给定双方牌库 + 关卡，计算自调升级建造预算
## @param player_deck 玩家牌库（用 player.full_deck — 开战快照，11 张）
## @param boss_deck   Boss 牌库（用 boss.full_deck）
## @param round_index 当前轮次 1~5（决定基线 budget）
## @return Dictionary {budget, base, gap, adjust, player_value, boss_value}
##   budget: 最终建造预算（int，已 clamp 到 [4, 12]）
##   其他字段供 UI / debug 显示
static func calc_budget(player_deck: Array, boss_deck: Array, round_index: int) -> Dictionary:
	var p_value: float = calc_deck_value(player_deck)
	var b_value: float = calc_deck_value(boss_deck)
	var gap: float = b_value - p_value  # 正值 = 玩家落后

	var base: int = int(BASE_BUDGET_BY_ROUND.get(round_index, 6))

	# 调整：玩家落后越多，预算越多；玩家领先则预算减少
	var raw_adjust: float = gap * GAP_SCALING
	var adjust: int = int(round(clampf(raw_adjust, -float(MAX_GAP_ADJUST), float(MAX_GAP_ADJUST))))

	var budget: int = clampi(base + adjust, MIN_BUDGET, MAX_BUDGET)

	return {
		"budget": budget,
		"base": base,
		"gap": gap,
		"adjust": adjust,
		"player_value": p_value,
		"boss_value": b_value,
	}


## 便捷调用：直接拿到预算 int（供大多数调用方）
static func calc_budget_int(player_deck: Array, boss_deck: Array, round_index: int) -> int:
	return int(calc_budget(player_deck, boss_deck, round_index).get("budget", 6))
