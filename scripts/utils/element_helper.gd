class_name ElementHelper
extends RefCounted
## 元素+光暗系统工具类（纯静态，无状态）
##
## v0.6.0 火水木+光明暗黑 战斗系统（ADR-002 / GDD-06）
## - 3-cycle 克制：火克木 / 木克水 / 水克火（石头剪刀布纳什最优解）
## - 光暗 2:2 平衡协同：4 张牌中正好 2 光 2 暗 → 本回合克制倍率 ×1.5 → ×2.0
##
## 注意：本工具类不持有任何战斗状态，所有 API 都是纯函数。


# ============================================================================
# 3-cycle 克制判定
# ============================================================================

## 返回 1=A克制B, -1=B克制A, 0=同元素中立
## 火 → 木 → 水 → 火（环式克制）
static func get_element_counter(a: int, b: int) -> int:
	# NONE 元素视为中立
	if a == CardData.Element.NONE or b == CardData.Element.NONE:
		return 0
	if a == b:
		return 0
	# 火克木
	if a == CardData.Element.FIRE and b == CardData.Element.WOOD:
		return 1
	# 木克水
	if a == CardData.Element.WOOD and b == CardData.Element.WATER:
		return 1
	# 水克火
	if a == CardData.Element.WATER and b == CardData.Element.FIRE:
		return 1
	# 反向
	return -1


## 是否双方都已声明元素（用于决定使用元素克制还是退回 type 克制）
static func has_elements(a: CardData, b: CardData) -> bool:
	if a == null or b == null:
		return false
	return a.element != CardData.Element.NONE and b.element != CardData.Element.NONE


# ============================================================================
# 光暗 2:2 平衡协同（A2 保底版唯一实装）
# ============================================================================

## 检查 4 出牌位是否触发 2:2 平衡协同
## 仅当 LIGHT 数 == 2 且 DARK 数 == 2 时返回 true
## NONE 极性的牌不计入（兼容旧牌）
static func is_balanced_polarity(cards: Array[CardData]) -> bool:
	var counts := count_polarity(cards)
	return counts.light == 2 and counts.dark == 2


## 统计一组牌的光暗分布
## 返回 {light: int, dark: int, none: int, total_polarity: int}
static func count_polarity(cards: Array[CardData]) -> Dictionary:
	var light := 0
	var dark := 0
	var none := 0
	for c in cards:
		if c == null:
			continue
		match c.polarity:
			CardData.Polarity.LIGHT: light += 1
			CardData.Polarity.DARK:  dark += 1
			_:                       none += 1
	return {
		"light": light,
		"dark": dark,
		"none": none,
		"total_polarity": light + dark,
	}


## A2 协同奖励倍率：基础克制倍率 → 经过 2:2 平衡放大
## 输入：基础倍率（1.5 / 0.5 / 1.0）+ 是否触发平衡
## 输出：调整后倍率
##
## 设计：仅放大正向克制倍率（1.5 → 2.0），不放大反向（0.5 不变，避免被克情况下还吃额外惩罚）
static func apply_balance_bonus(base_multiplier: float, balanced: bool) -> float:
	if not balanced:
		return base_multiplier
	if base_multiplier > 1.0:
		return 2.0  # 1.5 → 2.0
	# 中立 / 被克情况下不变（A2 保底设计）
	return base_multiplier


# ============================================================================
# 距离平衡（UI 实时预测条用）
# ============================================================================

## 给当前已选牌列表，计算距离 2:2 平衡还差几张牌（哪种）
## 返回 {distance: int, need: String}
##   distance: 还差几张到达 2 光 2 暗（已平衡 = 0）
##   need: "light" / "dark" / "any" / "none_balanced"（已平衡）/ "overflow"（>4 张已超）
static func distance_to_balance(cards: Array[CardData], target_size: int = 4) -> Dictionary:
	var counts := count_polarity(cards)
	var light: int = counts.light
	var dark: int = counts.dark
	var total: int = cards.size()

	if total > target_size:
		return {"distance": -1, "need": "overflow"}
	if light == 2 and dark == 2 and total == target_size:
		return {"distance": 0, "need": "none_balanced"}

	# 还能加几张
	var remaining := target_size - total
	var need_light: int = maxi(0, 2 - light)
	var need_dark: int = maxi(0, 2 - dark)
	var total_need: int = need_light + need_dark

	if total_need > remaining:
		# 已不可能达到平衡（如已 3 光，剩余 1 张无论如何都到不了 2:2）
		return {"distance": -1, "need": "impossible"}

	if need_light > 0 and need_dark == 0:
		return {"distance": need_light, "need": "light"}
	if need_dark > 0 and need_light == 0:
		return {"distance": need_dark, "need": "dark"}
	# 两者都还需要
	return {"distance": total_need, "need": "any"}


# ============================================================================
# 显示用辅助
# ============================================================================

static func element_name(e: int) -> String:
	match e:
		CardData.Element.FIRE:  return "火"
		CardData.Element.WATER: return "水"
		CardData.Element.WOOD:  return "木"
		_:                      return "无"


static func element_short(e: int) -> String:
	match e:
		CardData.Element.FIRE:  return "fire"
		CardData.Element.WATER: return "water"
		CardData.Element.WOOD:  return "wood"
		_:                      return "none"


static func polarity_name(p: int) -> String:
	match p:
		CardData.Polarity.LIGHT: return "光"
		CardData.Polarity.DARK:  return "暗"
		_:                       return "无"


static func polarity_short(p: int) -> String:
	match p:
		CardData.Polarity.LIGHT: return "light"
		CardData.Polarity.DARK:  return "dark"
		_:                       return "none"
