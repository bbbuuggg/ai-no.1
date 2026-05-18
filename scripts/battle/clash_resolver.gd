class_name ClashResolver
extends RefCounted
## 碰撞结算引擎 — 逐对翻开 + 元素克制
##
## v0.6.0 元素+光暗转向（ADR-002）：
## - 主克制：火/水/木 3-cycle（火克木 / 木克水 / 水克火），见 ElementHelper
## - 协同：4 张牌 2:2 平衡光暗 → 玩家克制倍率 1.5 → 2.0（A2 保底版仅实装此项）
## - 旧 ATK/DEF/SKL 三角克制已移除，element=NONE 的牌视为中立

## 碰撞结果数据
class ClashResult:
	var player_card: CardData
	var boss_card: CardData  # null 表示多余牌（无对手）
	var player_multiplier: float = 1.0
	var boss_multiplier: float = 1.0
	var clash_type: String = ""  # "counter_player", "counter_boss", "neutral", "free_player", "free_boss"
	var balanced_bonus: bool = false  # v0.6.0：本对玩家方是否吃了 2:2 平衡 ×2.0 加成
	var trap_triggered: bool = false
	var trap_data: TrapData = null
	# v0.4.3 hotfix-4：本对玩家牌的 0 费绑定牌（用于 UI 展示"绑定+X 抽牌效果"）。
	# 由 BlindClashBattle.apply_clash_pair_at 在结算时填入。
	var player_bound_zero: CardData = null


## v0.6.0：克制判定（仅元素克制，旧牌 NONE 元素视为中立）
## 返回 1=玩家克制, -1=Boss克制, 0=中立
static func get_counter_result(player_card: CardData, boss_card: CardData) -> int:
	if player_card == null or boss_card == null:
		return 0
	# 仅使用元素克制；双方都已声明元素才判定
	if ElementHelper.has_elements(player_card, boss_card):
		return ElementHelper.get_element_counter(player_card.element, boss_card.element)
	# 有一方 element=NONE → 中立（不再使用旧 type 三角克制）
	return 0


## 执行完整碰撞序列，返回 ClashResult 数组
##
## v0.6.0：先计算玩家牌组的 2:2 平衡状态（一次性，对所有对都生效），
## 再逐对计算克制倍率，玩家方触发平衡时把 1.5 → 2.0
static func resolve_clash(player_cards: Array[CardData], boss_cards: Array[CardData]) -> Array[ClashResult]:
	var results: Array[ClashResult] = []
	var max_pairs: int = maxi(player_cards.size(), boss_cards.size())

	# v0.6.0：仅对玩家牌组检查 2:2 平衡（A2 保底版只奖励玩家平衡出牌）
	var player_balanced: bool = ElementHelper.is_balanced_polarity(player_cards)

	for i in range(max_pairs):
		var result := ClashResult.new()

		if i < player_cards.size() and i < boss_cards.size():
			# 同 slot 配对（BP 模式下两数组等长，null 表示该方未出牌）
			var p_card: CardData = player_cards[i]
			var b_card: CardData = boss_cards[i]

			if p_card != null and b_card != null:
				# 双方均出牌 → 正常克制判定
				result.player_card = p_card
				result.boss_card = b_card
				var counter: int = get_counter_result(p_card, b_card)
				if counter == 1:
					if player_balanced:
						result.player_multiplier = 2.0
						result.balanced_bonus = true
					else:
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
			elif p_card != null and b_card == null:
				# 玩家出牌，Boss 未出 → 毫无阻力，效果 ×2
				result.player_card = p_card
				result.boss_card = null
				result.player_multiplier = 2.0
				result.boss_multiplier = 0.0
				result.clash_type = "unopposed_player"
			elif p_card == null and b_card != null:
				# Boss 出牌，玩家未出 → 毫无阻力，效果 ×2
				result.player_card = null
				result.boss_card = b_card
				result.player_multiplier = 0.0
				result.boss_multiplier = 2.0
				result.clash_type = "unopposed_boss"
			else:
				# 双方均未出牌
				result.player_multiplier = 0.0
				result.boss_multiplier = 0.0
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
