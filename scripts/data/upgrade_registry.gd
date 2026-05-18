extends Node
## UpgradeRegistry — GDD-08 升级牌池注册与抽取
## 12 张升级牌起步，每张满足"双向价值约束"（bidirectional_score ≥ 3）

var all_upgrades: Dictionary = {}  # id -> UpgradeData


func _ready() -> void:
	_register_numeric_upgrades()
	_register_attribute_upgrades()
	_register_keyword_upgrades()
	_register_structural_upgrades()


func get_upgrade(id: StringName) -> UpgradeData:
	return all_upgrades.get(id, null)


## 从池中随机抽 N 张候选（排除已使用的结构升级）
func draw_candidates(count: int, run_state: RunState) -> Array[UpgradeData]:
	var pool: Array[UpgradeData] = []
	for id in all_upgrades:
		var up: UpgradeData = all_upgrades[id]
		# 结构升级：同 Run 仅 1 张（给玩家侧和 Boss 侧分别限制）
		if up.is_structural:
			if run_state.is_structural_used("player", up.effect_id):
				continue
		pool.append(up)

	# 无重复随机抽取
	pool.shuffle()
	var result: Array[UpgradeData] = []
	for i in range(mini(count, pool.size())):
		result.append(pool[i])
	return result


## 应用升级牌到目标 CardData（返回新的 CardData，不修改原对象）
func apply_upgrade_to_card(upgrade: UpgradeData, target: CardData) -> CardData:
	if upgrade.is_structural:
		push_warning("[UpgradeRegistry] 结构升级应通过 apply_structural 而非 apply_upgrade_to_card")
		return target

	var new_card: CardData = target.duplicate()
	match upgrade.category:
		UpgradeData.Category.NUMERIC:
			_apply_numeric(upgrade, new_card)
		UpgradeData.Category.ATTRIBUTE:
			_apply_attribute(upgrade, new_card)
		UpgradeData.Category.KEYWORD:
			_apply_keyword(upgrade, new_card)
	return new_card


## 应用结构升级到 RunState
func apply_structural(upgrade: UpgradeData, side: String, run_state: RunState) -> void:
	if not upgrade.is_structural:
		return
	match upgrade.effect_id:
		&"energy_bonus":
			var key: String = "energy_bonus"
			run_state.struct_modifiers[side][key] = run_state.struct_modifiers[side].get(key, 0) + upgrade.effect_value
		&"candidate_bonus":
			var key: String = "candidate_bonus"
			run_state.struct_modifiers[side][key] = run_state.struct_modifiers[side].get(key, 0) + upgrade.effect_value
		&"zerocost_limit_bonus":
			var key: String = "zerocost_limit_bonus"
			run_state.struct_modifiers[side][key] = run_state.struct_modifiers[side].get(key, 0) + upgrade.effect_value


# ===== 内部方法 =====

func _reg(id: StringName, name: String, category: UpgradeData.Category,
		desc: String, bidir_score: int, repeatable: bool,
		effect_id: StringName, effect_val: int,
		replace_restriction: int = -1,
		target_elem: int = 0, polarity_flip: bool = false,
		structural: bool = false) -> void:
	var up := UpgradeData.new()
	up.id = id
	up.upgrade_name = name
	up.category = category
	up.description = desc
	up.bidirectional_score = bidir_score
	up.is_repeatable = repeatable
	up.is_structural = structural
	up.effect_id = effect_id
	up.effect_value = effect_val
	up.target_element = target_elem
	up.target_polarity_flip = polarity_flip
	up.replace_type_restriction = replace_restriction
	all_upgrades[id] = up


## 6.1 数值升级类（3 张）
func _register_numeric_upgrades() -> void:
	_reg(&"up_overflow", "OVERFLOW", UpgradeData.Category.NUMERIC,
		"替换攻击牌 → 费用不变，伤害+2",
		4, true, &"damage_bonus", 2,
		CardData.CardType.ATTACK)
	_reg(&"up_shard", "SHARD", UpgradeData.Category.NUMERIC,
		"替换防御牌 → 费用不变，护甲+2",
		4, true, &"armor_bonus", 2,
		CardData.CardType.DEFENSE)
	_reg(&"up_caffeine", "CAFFEINE", UpgradeData.Category.NUMERIC,
		"替换基础牌 → 该牌附加「使用后下回合+1能量上限」",
		3, false, &"energy_next_turn_bonus", 1,
		-1)


## 6.2 属性升级类（3 张）
func _register_attribute_upgrades() -> void:
	_reg(&"up_polarity_flip", "NULL_REF", UpgradeData.Category.ATTRIBUTE,
		"替换基础牌 → 光暗反转，其他不变",
		4, true, &"polarity_flip", 0,
		-1, 0, true)
	_reg(&"up_element_water", "HYDRO_INJECT", UpgradeData.Category.ATTRIBUTE,
		"替换基础牌 → 元素改为水（伤害/护甲不变）",
		3, true, &"element_change", CardData.Element.WATER,
		-1, CardData.Element.WATER)
	_reg(&"up_element_fire", "PYRO_INJECT", UpgradeData.Category.ATTRIBUTE,
		"替换基础牌 → 元素改为火（伤害/护甲不变）",
		3, true, &"element_change", CardData.Element.FIRE,
		-1, CardData.Element.FIRE)


## 6.3 关键字升级类（3 张）
func _register_keyword_upgrades() -> void:
	_reg(&"up_lifesteal", "PARASITE", UpgradeData.Category.KEYWORD,
		"替换攻击牌 → 附加「造成伤害的50%回血」",
		3, false, &"lifesteal", 50,
		CardData.CardType.ATTACK)
	_reg(&"up_pierce", "NULL_PIERCE", UpgradeData.Category.KEYWORD,
		"替换攻击牌 → 附加「无视护甲」",
		4, true, &"ignore_armor", 1,
		CardData.CardType.ATTACK)
	_reg(&"up_reflect", "KICKBACK", UpgradeData.Category.KEYWORD,
		"替换防御牌 → 附加「受击时反弹3点伤害」",
		4, true, &"reflect_bonus", 3,
		CardData.CardType.DEFENSE)


## 6.4 结构升级类（3 张，不替换牌库 NEW-Q1=A）
func _register_structural_upgrades() -> void:
	_reg(&"up_struct_energy", "KERNEL_BOOST", UpgradeData.Category.STRUCTURAL,
		"起始能量+1（每场战斗永久）",
		4, false, &"energy_bonus", 1,
		-1, 0, false, true)
	_reg(&"up_struct_pickslot", "EXTRA_LOOP", UpgradeData.Category.STRUCTURAL,
		"BP阶段抽7候选（仍Pick 4）",
		3, false, &"candidate_bonus", 1,
		-1, 0, false, true)
	_reg(&"up_struct_zerocost", "RECURSION", UpgradeData.Category.STRUCTURAL,
		"0费立即牌每回合上限2→3",
		3, false, &"zerocost_limit_bonus", 1,
		-1, 0, false, true)


# ===== 升级效果执行 =====

func _apply_numeric(upgrade: UpgradeData, card: CardData) -> void:
	match upgrade.effect_id:
		&"damage_bonus":
			card.damage += upgrade.effect_value
			card.description = card.description.rstrip("）") + "，伤害+%d" % upgrade.effect_value if "）" in card.description else card.description + "（伤害+%d）" % upgrade.effect_value
		&"armor_bonus":
			card.armor += upgrade.effect_value
			card.description = card.description.rstrip("）") + "，护甲+%d" % upgrade.effect_value if "）" in card.description else card.description + "（护甲+%d）" % upgrade.effect_value
		&"energy_next_turn_bonus":
			card.energy_next_turn += upgrade.effect_value
			card.description += " [CAFFEINE]"


func _apply_attribute(upgrade: UpgradeData, card: CardData) -> void:
	match upgrade.effect_id:
		&"polarity_flip":
			if card.polarity == CardData.Polarity.LIGHT:
				card.polarity = CardData.Polarity.DARK
			elif card.polarity == CardData.Polarity.DARK:
				card.polarity = CardData.Polarity.LIGHT
			card.description += " [NULL_REF:光暗反转]"
		&"element_change":
			card.element = upgrade.effect_value as CardData.Element
			var elem_name: String = "水" if card.element == CardData.Element.WATER else "火" if card.element == CardData.Element.FIRE else "木"
			card.description += " [%s注入]" % elem_name


func _apply_keyword(upgrade: UpgradeData, card: CardData) -> void:
	match upgrade.effect_id:
		&"lifesteal":
			card.heal += maxi(card.damage / 2, 1)
			card.description += " [PARASITE:吸血]"
		&"ignore_armor":
			card.ignore_armor = true
			card.description += " [NULL_PIERCE:破甲]"
		&"reflect_bonus":
			card.reflect_damage += upgrade.effect_value
			card.description += " [KICKBACK:反伤+%d]" % upgrade.effect_value
