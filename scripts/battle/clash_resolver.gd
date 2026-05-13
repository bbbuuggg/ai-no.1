class_name ClashResolver
extends RefCounted
## 碰撞结算引擎 — 逐对翻开 + 三角克制

## 碰撞结果数据
class ClashResult:
	var player_card: CardData
	var boss_card: CardData  # null 表示多余牌（无对手）
	var player_multiplier: float = 1.0
	var boss_multiplier: float = 1.0
	var clash_type: String = ""  # "counter_player", "counter_boss", "neutral", "free_player", "free_boss"
	var trap_triggered: bool = false
	var trap_data: TrapData = null
	# v0.4.3 hotfix-4：本对玩家牌的 0 费绑定牌（用于 UI 展示"绑定+X 抽牌效果"）。
	# 由 BlindClashBattle.apply_clash_pair_at 在结算时填入。
	var player_bound_zero: CardData = null


## 三角克制判定：返回 1=player克制, -1=boss克制, 0=中立/同类型
static func get_counter_result(player_type: CardData.CardType, boss_type: CardData.CardType) -> int:
	# 攻击克技能、技能克防御、防御克攻击
	if player_type == boss_type:
		return 0
	# 协议牌视为技能类参与碰撞
	var p_type := _normalize_type(player_type)
	var b_type := _normalize_type(boss_type)
	if p_type == b_type:
		return 0
	if p_type == CardData.CardType.ATTACK and b_type == CardData.CardType.SKILL:
		return 1
	if p_type == CardData.CardType.SKILL and b_type == CardData.CardType.DEFENSE:
		return 1
	if p_type == CardData.CardType.DEFENSE and b_type == CardData.CardType.ATTACK:
		return 1
	# 反向
	if b_type == CardData.CardType.ATTACK and p_type == CardData.CardType.SKILL:
		return -1
	if b_type == CardData.CardType.SKILL and p_type == CardData.CardType.DEFENSE:
		return -1
	if b_type == CardData.CardType.DEFENSE and p_type == CardData.CardType.ATTACK:
		return -1
	return 0


## 协议牌归类为技能参与碰撞
static func _normalize_type(type: CardData.CardType) -> CardData.CardType:
	if type == CardData.CardType.PROTOCOL:
		return CardData.CardType.SKILL
	return type


## 执行完整碰撞序列，返回 ClashResult 数组
static func resolve_clash(player_cards: Array[CardData], boss_cards: Array[CardData]) -> Array[ClashResult]:
	var results: Array[ClashResult] = []
	var max_pairs: int = maxi(player_cards.size(), boss_cards.size())

	for i in range(max_pairs):
		var result := ClashResult.new()

		if i < player_cards.size() and i < boss_cards.size():
			# 正常配对
			result.player_card = player_cards[i]
			result.boss_card = boss_cards[i]
			var counter: int = get_counter_result(player_cards[i].type, boss_cards[i].type)
			if counter == 1:
				result.player_multiplier = 1.5
				result.boss_multiplier = 0.5
				result.clash_type = "counter_player"
			elif counter == -1:
				result.player_multiplier = 0.5
				result.boss_multiplier = 1.5
				result.clash_type = "counter_boss"
			else:
				result.player_multiplier = 1.0
				result.boss_multiplier = 1.0
				result.clash_type = "neutral"
		elif i < player_cards.size():
			# 玩家多余牌
			result.player_card = player_cards[i]
			result.boss_card = null
			result.player_multiplier = 1.0
			result.boss_multiplier = 0.0
			result.clash_type = "free_player"
		else:
			# Boss 多余牌
			result.player_card = null
			result.boss_card = boss_cards[i]
			result.player_multiplier = 0.0
			result.boss_multiplier = 1.0
			result.clash_type = "free_boss"

		results.append(result)

	return results


## 应用倍率到数值（向上取整）
static func apply_multiplier_int(base_value: int, multiplier: float) -> int:
	if multiplier == 1.0:
		return base_value
	return ceili(float(base_value) * multiplier)


## 判断状态/标记类效果是否因减半而失效
static func is_status_nullified(duration: int, multiplier: float) -> bool:
	if multiplier >= 1.0:
		return false
	return ceili(float(duration) * multiplier) <= 0
