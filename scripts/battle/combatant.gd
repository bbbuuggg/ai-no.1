class_name Combatant
extends RefCounted
## 战斗中的参与者状态（玩家和 Boss 共用）

signal hp_changed(new_hp: int, max_hp: int)
signal armor_changed(new_armor: int)
signal energy_changed(new_energy: int)
signal hand_changed()
signal deck_changed()

var combatant_name: String = ""
var max_hp: int = 25
var hp: int = 25
var armor: int = 0
var energy: int = 0
var base_energy: int = 6    # v0.7.x-rebal：双方每回合 6 能量（4 Pick 槽 × cost 1~2 平均，留一档给 0 费多投或失误容错）
var base_draw: int = 6      # v0.7.x-rebal：与 hand_pool_size 同步，每回合补满候选池到 6 张
var hand_limit: int = 6     # v0.7.x-rebal：手牌池窗（hand_pool）上限 = 6，候选展示窗扩大，4 槽从中筛选

# v0.7.x-rebal：手牌池窗设置（候选窗 = hand 6 张，从中 Pick 4 进入 slot）
const HAND_POOL_SIZE: int = 6        # 候选展示窗大小
const PICK_SLOTS: int = 4            # 实际 Pick 槽数（不变）
const ZEROCOST_LIMIT_PER_TURN: int = 2  # 每回合 0 费上限（防止刷牌过度）

# v0.7.x-rebal：本回合 0 费已用次数（每回合 _next_round 重置）
var zerocost_used_this_turn: int = 0
# v0.7.x-rebal：本回合 0 费使用日志（[card_id, ...]，用于全明牌契约对外广播）
var zerocost_used_log: Array[StringName] = []

# 牌组
var deck: Array[CardData] = []  # 抽牌堆
var hand: Array[CardData] = []  # 手牌
var discard_pile: Array[CardData] = []  # 弃牌堆
var full_deck: Array[CardData] = []  # 完整牌库（用于查看）

# 状态标记
var is_charged: bool = false  # 蓄力状态
var all_attack_bonus: int = 0  # 本回合全攻击加成
var next_attack_bonus: int = 0  # 下次攻击加成
var energy_modifier_next_turn: int = 0  # 下回合能量修正
var draw_modifier_next_turn: int = 0  # 下回合抽牌修正

# 约束令（仅 Boss 受约束）
var active_constraints: Array[Dictionary] = []  # {data: ConstraintData, remaining: int}

# Boss 预判的下回合出牌（用于意图预告）
var pending_actions: Array[CardData] = []
var has_pending_turn: bool = false


func _init(p_name: String, p_hp: int, p_deck: Array[CardData]) -> void:
	combatant_name = p_name
	max_hp = p_hp
	hp = p_hp
	full_deck = p_deck.duplicate()
	deck = p_deck.duplicate()
	deck.shuffle()


func start_turn() -> void:
	# 清除上回合护甲
	armor = 0
	armor_changed.emit(armor)
	# 重置本回合状态
	all_attack_bonus = 0
	# 应用能量修正
	energy = base_energy + energy_modifier_next_turn
	energy_modifier_next_turn = 0
	energy_changed.emit(energy)
	# 抽牌
	var draw_count: int = base_draw + draw_modifier_next_turn
	draw_modifier_next_turn = 0
	draw_cards(maxi(draw_count, 1))


func draw_cards(count: int) -> void:
	for i in range(count):
		if hand.size() >= hand_limit:
			break
		if deck.is_empty():
			_shuffle_discard_into_deck()
		if deck.is_empty():
			break
		hand.append(deck.pop_back())
	hand_changed.emit()


func _shuffle_discard_into_deck() -> void:
	deck = discard_pile.duplicate()
	discard_pile.clear()
	deck.shuffle()
	deck_changed.emit()


func play_card(card: CardData) -> void:
	energy -= card.energy_cost
	hand.erase(card)
	discard_pile.append(card)
	energy_changed.emit(energy)
	hand_changed.emit()


func discard_hand() -> void:
	discard_pile.append_array(hand)
	hand.clear()
	hand_changed.emit()


func take_damage(amount: int, ignore_armor_flag: bool = false) -> void:
	var effective_damage: int = amount
	if not ignore_armor_flag and armor > 0:
		var blocked: int = mini(armor, amount)
		armor -= blocked
		effective_damage -= blocked
		armor_changed.emit(armor)
	if effective_damage > 0:
		hp = maxi(hp - effective_damage, 0)
		hp_changed.emit(hp, max_hp)


func gain_armor(amount: int) -> void:
	armor += amount
	armor_changed.emit(armor)


func heal_hp(amount: int) -> void:
	hp = mini(hp + amount, max_hp)
	hp_changed.emit(hp, max_hp)


func is_dead() -> bool:
	return hp <= 0


# ========================================================================
# v0.7.x-rebal：辅助方法
# ========================================================================

## 重置每回合 0 费用计数（在 _next_round 开头调用）
func reset_turn_counters() -> void:
	zerocost_used_this_turn = 0
	zerocost_used_log.clear()


## 是否还能再使用 0 费牌（每回合上限 ZEROCOST_LIMIT_PER_TURN 次）
func can_use_zerocost() -> bool:
	return zerocost_used_this_turn < ZEROCOST_LIMIT_PER_TURN


## 标记一次 0 费使用（计数 + 日志）
func mark_zerocost_used(card_id: StringName) -> void:
	zerocost_used_this_turn += 1
	zerocost_used_log.append(card_id)


## 牌库类型统计（攻 / 防 / 技 / 协 / 0费 计数）— 全明牌 perception 用
func get_deck_type_counts() -> Dictionary:
	var counts: Dictionary = {
		"attack": 0, "defense": 0, "skill": 0, "protocol": 0, "zerocost": 0,
	}
	for c in deck:
		if c.energy_cost == 0:
			counts["zerocost"] += 1
		match c.type:
			CardData.CardType.ATTACK: counts["attack"] += 1
			CardData.CardType.DEFENSE: counts["defense"] += 1
			CardData.CardType.SKILL: counts["skill"] += 1
			CardData.CardType.PROTOCOL: counts["protocol"] += 1
	return counts
