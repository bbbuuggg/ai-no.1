class_name Combatant
extends RefCounted
## 战斗中的参与者状态（玩家和 Boss 共用）

signal hp_changed(new_hp: int, max_hp: int)
signal armor_changed(new_armor: int)
signal energy_changed(new_energy: int)
signal hand_changed()
signal deck_changed()

var combatant_name: String = ""
var max_hp: int = 60
var hp: int = 60
var armor: int = 0
var energy: int = 0
var base_energy: int = 3
var base_draw: int = 3
var hand_limit: int = 7

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
