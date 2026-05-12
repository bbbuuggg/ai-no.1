class_name BattleManager
extends Node
## 战斗流程状态机 — 管理回合循环

signal battle_started()
signal turn_started(turn_number: int)
signal player_phase_started()
signal boss_phase_started()
signal turn_ended(turn_number: int)
signal battle_ended(player_won: bool)
signal card_played(who: String, card: CardData)
signal constraint_used(constraint: ConstraintData)
signal boss_intent_ready(intent: BossIntent)

enum Phase { IDLE, PLAYER_TURN, BOSS_TURN, BATTLE_OVER }

var player: Combatant
var boss: Combatant
var current_phase: Phase = Phase.IDLE
var turn_number: int = 0
var constraint_resource: int = 0  # 玩家约束资源
var constraints_inventory: Array[ConstraintData] = []  # 玩家持有的约束令

# 开发模式标志
var debug_god_mode: bool = false
var debug_infinite_energy: bool = false


func start_battle(p_player: Combatant, p_boss: Combatant, p_constraints: Array[ConstraintData]) -> void:
	player = p_player
	boss = p_boss
	constraints_inventory = p_constraints.duplicate()
	constraint_resource = 0
	turn_number = 0
	current_phase = Phase.IDLE
	battle_started.emit()
	_next_turn()


func _next_turn() -> void:
	turn_number += 1
	turn_started.emit(turn_number)
	# 回合开始：约束衰减
	_tick_constraints()
	# 玩家阶段
	_start_player_phase()


func _start_player_phase() -> void:
	current_phase = Phase.PLAYER_TURN
	# 约束资源 +1
	constraint_resource += 1
	# 玩家开始回合
	player.start_turn()
	if debug_infinite_energy:
		player.energy = 99
	# 让 Boss 提前抽牌+决策，生成意图预告
	_prepare_boss_intent()
	player_phase_started.emit()


func _prepare_boss_intent() -> void:
	# Boss 提前"准备"：清除上回合护甲、补能量、抽牌
	boss.armor = 0
	boss.armor_changed.emit(0)
	boss.all_attack_bonus = 0
	boss.energy = boss.base_energy + boss.energy_modifier_next_turn
	boss.energy_changed.emit(boss.energy)
	var draw_count: int = boss.base_draw + boss.draw_modifier_next_turn
	boss.draw_cards(maxi(draw_count, 1))
	# AI 决策
	var ai := RuleAI.new()
	var actions: Array[CardData] = ai.make_decision(boss, player)
	boss.pending_actions = actions
	boss.has_pending_turn = true
	# 生成意图
	var intent: BossIntent = BossIntent.analyze_actions(actions)
	boss_intent_ready.emit(intent)


func player_play_card(card: CardData) -> bool:
	if current_phase != Phase.PLAYER_TURN:
		return false
	if card.energy_cost > player.energy:
		return false
	if not player.hand.has(card):
		return false
	# 检查蓄力需求
	if card.requires_charge and not player.is_charged:
		return false

	player.play_card(card)
	_resolve_card(card, player, boss)
	card_played.emit("player", card)

	if boss.is_dead():
		_end_battle(true)
	return true


func player_use_constraint(constraint: ConstraintData) -> bool:
	if current_phase != Phase.PLAYER_TURN:
		return false
	if constraint.resource_cost > constraint_resource:
		return false
	if not constraints_inventory.has(constraint):
		return false

	constraint_resource -= constraint.resource_cost
	constraints_inventory.erase(constraint)
	_apply_constraint(constraint)
	constraint_used.emit(constraint)
	return true


func player_end_turn() -> void:
	if current_phase != Phase.PLAYER_TURN:
		return
	player.discard_hand()
	_start_boss_phase()


func _start_boss_phase() -> void:
	current_phase = Phase.BOSS_TURN
	# Boss 已在玩家回合开始时完成"start_turn"逻辑，不再重复
	# 但需要应用约束令对本回合资源的修正
	_apply_resource_constraints()
	boss_phase_started.emit()


func execute_boss_action(card: CardData) -> bool:
	## 执行 Boss 单张出牌，返回是否成功
	if boss.energy < card.energy_cost:
		return false
	if not boss.hand.has(card):
		return false
	if _is_card_blocked_by_constraint(card):
		# 牌被打出（消耗手牌和能量）但效果不结算
		boss.play_card(card)
		card_played.emit("boss_blocked", card)
		return true
	boss.play_card(card)
	_resolve_card(card, boss, player)
	card_played.emit("boss", card)
	if player.is_dead() and not debug_god_mode:
		_end_battle(false)
	return true


func finish_boss_turn() -> void:
	## Boss 出牌结束后调用
	boss.discard_hand()
	_end_turn()


func _end_turn() -> void:
	turn_ended.emit(turn_number)
	if current_phase == Phase.BATTLE_OVER:
		return
	_next_turn()


func _end_battle(player_won: bool) -> void:
	current_phase = Phase.BATTLE_OVER
	battle_ended.emit(player_won)


func _resolve_card(card: CardData, caster: Combatant, target: Combatant) -> void:
	# 攻击
	if card.damage > 0:
		var total_damage: int = card.damage + caster.all_attack_bonus + caster.next_attack_bonus
		caster.next_attack_bonus = 0
		for i in range(card.hits):
			target.take_damage(total_damage, card.ignore_armor)
	# 护甲
	if card.armor > 0:
		caster.gain_armor(card.armor)
	# 抽牌
	if card.draw_cards > 0:
		caster.draw_cards(card.draw_cards)
	# 治疗
	if card.heal > 0:
		caster.heal_hp(card.heal)
	# 蓄力
	if card.grants_charge:
		caster.is_charged = true
	if card.requires_charge:
		caster.is_charged = false
	# 下次攻击加成
	if card.next_attack_bonus > 0:
		caster.next_attack_bonus += card.next_attack_bonus
	# 全攻击加成
	if card.all_attack_bonus > 0:
		caster.all_attack_bonus += card.all_attack_bonus
	# 能量修正（对手）
	if card.enemy_energy_modifier != 0:
		target.energy_modifier_next_turn += card.enemy_energy_modifier
	# 抽牌修正（对手）
	if card.enemy_draw_modifier != 0:
		target.draw_modifier_next_turn += card.enemy_draw_modifier
	# 下回合能量（自己）
	if card.energy_next_turn != 0:
		caster.energy_modifier_next_turn += card.energy_next_turn
	# 约束资源获取
	if card.gain_constraint_resource > 0:
		constraint_resource += card.gain_constraint_resource
	# 弃手抽牌
	if card.discard_hand_and_draw > 0:
		caster.discard_hand()
		caster.draw_cards(card.discard_hand_and_draw)
	# 受伤时额外护甲（标记到 combatant，简化处理）
	if card.armor_on_hit > 0:
		caster.gain_armor(card.armor_on_hit)


func _apply_constraint(constraint: ConstraintData) -> void:
	if constraint.duration == 0:
		# 即时型（如协议否决）— 由 UI 在 Boss 出牌时触发
		pass
	else:
		boss.active_constraints.append({
			"data": constraint,
			"remaining": constraint.duration,
		})


func _tick_constraints() -> void:
	var to_remove: Array[int] = []
	for i in range(boss.active_constraints.size()):
		if boss.active_constraints[i]["remaining"] > 0:
			boss.active_constraints[i]["remaining"] -= 1
			if boss.active_constraints[i]["remaining"] <= 0:
				to_remove.append(i)
	to_remove.reverse()
	for idx in to_remove:
		boss.active_constraints.remove_at(idx)


func _apply_resource_constraints() -> void:
	for entry in boss.active_constraints:
		var c: ConstraintData = entry["data"]
		if c.draw_reduction > 0:
			boss.draw_modifier_next_turn -= c.draw_reduction
		if c.energy_reduction > 0:
			boss.energy = maxi(boss.energy - c.energy_reduction, 1)
		if c.hand_limit_reduction > 0:
			boss.hand_limit = maxi(boss.hand_limit - c.hand_limit_reduction, 3)


func _is_card_blocked_by_constraint(card: CardData) -> bool:
	for entry in boss.active_constraints:
		var c: ConstraintData = entry["data"]
		# 行为锁定：阻止攻击类牌（初始约束令默认锁攻击）
		if c.type == ConstraintData.ConstraintType.LOCK_CARD:
			if card.type == CardData.CardType.ATTACK:
				return true
		# 类型封印：阻止指定类型的牌
		if c.type == ConstraintData.ConstraintType.SEAL_TYPE:
			if card.type == c.seal_card_type:
				return true
	return false


# ===== 开发模式快捷方法 =====

func debug_kill_boss() -> void:
	boss.hp = 0
	_end_battle(true)

func debug_fill_constraints() -> void:
	constraint_resource = 10
