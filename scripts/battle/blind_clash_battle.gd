class_name BlindClashBattle
extends Node
## 暗出对决战斗管理器 — v0.3 全新回合结构
## 替代旧 BattleManager，实现：暗出→碰撞→陷阱→认知探针 五阶段流程

# ===== 信号 =====
signal battle_started()
signal round_started(round_number: int)
signal deploy_phase_started()  # 部署阶段开始（玩家部署陷阱）
signal blind_phase_started()  # 暗出阶段开始（双方选牌）
signal clash_phase_started()  # 对决阶段开始（逐张翻开）
signal clash_pair_resolved(result: ClashResolver.ClashResult)  # 单对碰撞结算完
signal probe_phase_started()  # 认知结算阶段
signal round_ended(round_number: int)
signal battle_ended(player_won: bool)

signal player_card_revealed(index: int, card: CardData, multiplier: float)
signal boss_card_revealed(index: int, card: CardData, multiplier: float)
signal trap_triggered_signal(trap: TrapData, triggered_by: CardData)
signal probe_prediction_announced(predicted_type: String)
signal probe_result_announced(correct: bool, streak: int, total: int)
signal insight_effect(effect_type: String, target_card: CardData)  # peek/disrupt/seize

enum Phase { IDLE, DEPLOY, BLIND, CLASH, PROBE, ROUND_END, BATTLE_OVER }

# ===== 战斗状态 =====
var player: Combatant
var boss: Combatant
var current_phase: Phase = Phase.IDLE
var round_number: int = 0

# 约束资源
var constraint_resource: int = 0
var trap_inventory: Array[TrapData] = []  # 玩家持有的陷阱牌

# 陷阱槽位 [攻击, 技能, 高费] — null=空, TrapData=有
var trap_slots: Array = [null, null, null]  # 3 slots

# 暗出缓存
var player_blind_cards: Array[CardData] = []  # 玩家暗出牌（已排列）
var player_bound_zero_cards: Dictionary = {}  # {主牌index: CardData} 绑定的0费牌
var boss_blind_cards: Array[CardData] = []  # Boss暗出牌（已排列）

# 认知探针
var probe: CognitiveProbe = CognitiveProbe.new()

# 被窥视的玩家手牌（对Boss可见）
var peeked_cards: Array[CardData] = []
# 被干扰的玩家手牌（下回合不可用）
var disrupted_cards: Array[CardData] = []

# 开发模式
var debug_god_mode: bool = false
var debug_infinite_energy: bool = false


# ===== 战斗启动 =====

func start_battle(p_player: Combatant, p_boss: Combatant, p_traps: Array[TrapData]) -> void:
	player = p_player
	boss = p_boss
	trap_inventory = p_traps.duplicate()
	constraint_resource = 0
	round_number = 0
	current_phase = Phase.IDLE
	trap_slots = [null, null, null]
	peeked_cards.clear()
	disrupted_cards.clear()
	player_blind_cards.clear()
	boss_blind_cards.clear()
	player_bound_zero_cards.clear()
	probe.setup({"attack": 0.4, "defense": 0.3, "skill": 0.3})
	battle_started.emit()
	_next_round()


# ===== 回合流程 =====

func _next_round() -> void:
	round_number += 1
	current_phase = Phase.IDLE

	# 清除上回合护甲
	player.armor = 0
	player.armor_changed.emit(0)
	boss.armor = 0
	boss.armor_changed.emit(0)

	# 重置状态
	player.all_attack_bonus = 0
	boss.all_attack_bonus = 0
	player.next_attack_bonus = 0
	boss.next_attack_bonus = 0

	# 双方获得能量
	player.energy = player.base_energy + player.energy_modifier_next_turn
	player.energy_modifier_next_turn = 0
	player.energy_changed.emit(player.energy)
	if debug_infinite_energy:
		player.energy = 99
		player.energy_changed.emit(99)

	boss.energy = boss.base_energy + boss.energy_modifier_next_turn
	boss.energy_modifier_next_turn = 0
	boss.energy_changed.emit(boss.energy)

	# 双方抽牌
	var player_draw: int = maxi(player.base_draw + player.draw_modifier_next_turn, 1)
	player.draw_modifier_next_turn = 0
	player.draw_cards(player_draw)

	var boss_draw: int = maxi(boss.base_draw + boss.draw_modifier_next_turn, 1)
	boss.draw_modifier_next_turn = 0
	boss.draw_cards(boss_draw)

	# 约束资源 +1
	constraint_resource += 1

	# 清理已过期的干扰牌
	disrupted_cards.clear()

	# 陷阱衰减（目前陷阱为一次性，不需要持续管理）
	# 清空上回合的陷阱槽位
	trap_slots = [null, null, null]

	# Boss 认知探针预判（内部计算但不公布，等暗出确认后再显示）
	probe.make_prediction()

	round_started.emit(round_number)

	# 进入部署阶段
	_start_deploy_phase()


func _start_deploy_phase() -> void:
	current_phase = Phase.DEPLOY
	deploy_phase_started.emit()
	# 等待玩家操作（部署陷阱/干扰探针），然后调用 confirm_deploy()


func _start_blind_phase() -> void:
	current_phase = Phase.BLIND
	player_blind_cards.clear()
	boss_blind_cards.clear()
	player_bound_zero_cards.clear()

	# Boss AI 暗出选牌
	var ai := BlindClashAI.new()
	boss_blind_cards = ai.select_blind_cards(boss, player, trap_slots, probe)

	blind_phase_started.emit()
	# 等待玩家选牌+排列，然后调用 confirm_blind()


func _start_clash_phase() -> void:
	current_phase = Phase.CLASH
	# 暗出确认后才公布Boss的认知探针预判
	probe_prediction_announced.emit(probe.current_prediction)
	clash_phase_started.emit()
	# 由 UI 驱动逐张翻开动画，调用 resolve_next_clash() 或 resolve_all_clashes()


func _start_probe_phase() -> void:
	current_phase = Phase.PROBE

	# 统计玩家实际暗出牌（包含绑定的0费牌）
	var all_player_cards: Array[CardData] = player_blind_cards.duplicate()
	for idx in player_bound_zero_cards:
		all_player_cards.append(player_bound_zero_cards[idx])

	var result: Dictionary = probe.resolve(all_player_cards)
	probe_result_announced.emit(result["correct"], result["streak"], result["total"])

	# 检查洞察效果
	_check_insight_effects(result)

	probe_phase_started.emit()


func _end_round() -> void:
	current_phase = Phase.ROUND_END

	# 暗出的牌移入弃牌堆
	for card in player_blind_cards:
		player.discard_pile.append(card)
	for idx in player_bound_zero_cards:
		player.discard_pile.append(player_bound_zero_cards[idx])
	for card in boss_blind_cards:
		boss.discard_pile.append(card)

	# 手牌上限检查
	while player.hand.size() > player.hand_limit:
		var discarded: CardData = player.hand.pop_back()
		player.discard_pile.append(discarded)
	while boss.hand.size() > boss.hand_limit:
		var discarded: CardData = boss.hand.pop_back()
		boss.discard_pile.append(discarded)

	player.hand_changed.emit()
	boss.hand_changed.emit()

	# 胜负检查
	if boss.is_dead():
		_end_battle(true)
		return
	if player.is_dead() and not debug_god_mode:
		_end_battle(false)
		return

	round_ended.emit(round_number)
	_next_round()


func _end_battle(player_won: bool) -> void:
	current_phase = Phase.BATTLE_OVER
	battle_ended.emit(player_won)


# ===== 玩家操作接口 =====

## 部署陷阱到指定槽位（0=攻击, 1=技能, 2=高费）
func deploy_trap(trap: TrapData, slot_index: int) -> bool:
	if current_phase != Phase.DEPLOY:
		return false
	if slot_index < 0 or slot_index > 2:
		return false
	if trap_slots[slot_index] != null:
		return false  # 槽位已占
	if not trap.is_bluff and trap.resource_cost > constraint_resource:
		return false
	if not trap_inventory.has(trap):
		return false

	# 消耗资源
	if not trap.is_bluff:
		constraint_resource -= trap.resource_cost
	trap_inventory.erase(trap)
	trap_slots[slot_index] = trap
	return true


## 干扰Boss猜测（消耗1约束资源）
func jam_probe() -> bool:
	if current_phase != Phase.DEPLOY:
		return false
	if constraint_resource < 1:
		return false
	constraint_resource -= 1
	probe.jam()
	return true


## 确认部署阶段结束 → 进入暗出阶段
func confirm_deploy() -> void:
	if current_phase != Phase.DEPLOY:
		return
	_start_blind_phase()


## 设置玩家暗出牌（已排列顺序）+ 绑定的0费牌
func set_player_blind_cards(cards: Array[CardData], bound_zeros: Dictionary) -> bool:
	if current_phase != Phase.BLIND:
		return false

	# 验证能量
	var total_energy: int = 0
	for card in cards:
		total_energy += card.energy_cost
	for idx in bound_zeros:
		var zero_card: CardData = bound_zeros[idx]
		if zero_card.energy_cost != 0:
			return false  # 绑定牌必须0费

	if total_energy > player.energy:
		return false

	# 验证手牌持有
	var temp_hand: Array[CardData] = player.hand.duplicate()
	for card in cards:
		if not temp_hand.has(card):
			return false
		temp_hand.erase(card)
	for idx in bound_zeros:
		if not temp_hand.has(bound_zeros[idx]):
			return false
		temp_hand.erase(bound_zeros[idx])

	# 检查干扰牌不可用
	for card in cards:
		if disrupted_cards.has(card):
			return false
	for idx in bound_zeros:
		if disrupted_cards.has(bound_zeros[idx]):
			return false

	player_blind_cards = cards.duplicate()
	player_bound_zero_cards = bound_zeros.duplicate()

	# 从手牌中移除已暗出的牌
	for card in player_blind_cards:
		player.hand.erase(card)
	for idx in player_bound_zero_cards:
		player.hand.erase(player_bound_zero_cards[idx])
	# 扣除能量
	player.energy -= total_energy
	player.energy_changed.emit(player.energy)
	player.hand_changed.emit()

	return true


## 确认暗出阶段结束 → 进入对决阶段
func confirm_blind() -> void:
	if current_phase != Phase.BLIND:
		return
	if player_blind_cards.is_empty():
		# 允许出0张牌（放弃行动）
		pass
	_start_clash_phase()


## 执行完整碰撞结算（一次性，由UI控制翻开动画节奏）
func resolve_all_clashes() -> Array[ClashResolver.ClashResult]:
	if current_phase != Phase.CLASH:
		return []

	var results: Array[ClashResolver.ClashResult] = ClashResolver.resolve_clash(player_blind_cards, boss_blind_cards)

	# 逐对结算
	for i in range(results.size()):
		var result: ClashResolver.ClashResult = results[i]

		# 检查陷阱触发（仅对Boss牌检查）
		if result.boss_card != null:
			var triggered_trap: TrapData = _check_trap_trigger(result.boss_card)
			if triggered_trap != null:
				result.trap_triggered = true
				result.trap_data = triggered_trap
				_apply_trap_effect(triggered_trap, result)
				trap_triggered_signal.emit(triggered_trap, result.boss_card)

		# 结算玩家牌效果
		if result.player_card != null and result.player_multiplier > 0:
			var bound_zero: CardData = player_bound_zero_cards.get(i, null)
			_resolve_card_with_multiplier(result.player_card, player, boss, result.player_multiplier, bound_zero)

		# 结算Boss牌效果（如果未被陷阱中断）
		if result.boss_card != null and result.boss_multiplier > 0:
			if not (result.trap_triggered and result.trap_data != null and result.trap_data.interrupt_card):
				_resolve_card_with_multiplier(result.boss_card, boss, player, result.boss_multiplier, null)

		clash_pair_resolved.emit(result)

		# 胜负检查
		if player.is_dead() and not debug_god_mode:
			_end_battle(false)
			return results
		if boss.is_dead():
			_end_battle(true)
			return results

	# 碰撞全部结束 → 认知结算
	if current_phase != Phase.BATTLE_OVER:
		_start_probe_phase()

	return results


# ===== 内部逻辑 =====

func _resolve_card_with_multiplier(card: CardData, caster: Combatant, target: Combatant, multiplier: float, bound_zero: CardData) -> void:
	# 合并绑定的0费牌效果
	var total_damage: int = card.damage
	var total_armor: int = card.armor
	var total_draw: int = card.draw_cards
	var total_heal: int = card.heal

	if bound_zero != null:
		total_damage += bound_zero.damage
		total_armor += bound_zero.armor
		total_draw += bound_zero.draw_cards
		total_heal += bound_zero.heal

	# 应用倍率
	if total_damage > 0:
		var final_damage: int = ClashResolver.apply_multiplier_int(total_damage, multiplier)
		final_damage += caster.all_attack_bonus + caster.next_attack_bonus
		caster.next_attack_bonus = 0
		var ignore_armor: bool = card.ignore_armor or (bound_zero != null and bound_zero.ignore_armor)
		for hit in range(card.hits):
			target.take_damage(final_damage, ignore_armor)

	if total_armor > 0:
		caster.gain_armor(ClashResolver.apply_multiplier_int(total_armor, multiplier))

	if total_draw > 0:
		caster.draw_cards(ClashResolver.apply_multiplier_int(total_draw, multiplier))

	if total_heal > 0:
		caster.heal_hp(ClashResolver.apply_multiplier_int(total_heal, multiplier))

	# 状态类效果（受减半可能失效）
	if card.grants_charge:
		if not ClashResolver.is_status_nullified(1, multiplier):
			caster.is_charged = true

	if card.requires_charge:
		caster.is_charged = false

	if card.next_attack_bonus > 0:
		caster.next_attack_bonus += ClashResolver.apply_multiplier_int(card.next_attack_bonus, multiplier)

	if card.all_attack_bonus > 0:
		caster.all_attack_bonus += ClashResolver.apply_multiplier_int(card.all_attack_bonus, multiplier)

	if card.energy_next_turn != 0:
		caster.energy_modifier_next_turn += ClashResolver.apply_multiplier_int(card.energy_next_turn, multiplier)

	if card.enemy_energy_modifier != 0:
		target.energy_modifier_next_turn += ClashResolver.apply_multiplier_int(card.enemy_energy_modifier, multiplier)

	if card.enemy_draw_modifier != 0:
		target.draw_modifier_next_turn += ClashResolver.apply_multiplier_int(card.enemy_draw_modifier, multiplier)

	if card.gain_constraint_resource > 0:
		constraint_resource += ClashResolver.apply_multiplier_int(card.gain_constraint_resource, multiplier)

	if card.discard_hand_and_draw > 0:
		caster.discard_hand()
		caster.draw_cards(ClashResolver.apply_multiplier_int(card.discard_hand_and_draw, multiplier))


func _check_trap_trigger(boss_card: CardData) -> TrapData:
	## 检查Boss出的牌是否触发某个陷阱槽位
	# 槽位0=攻击触发, 槽位1=技能触发, 槽位2=高费触发
	var slot_index: int = -1
	match boss_card.type:
		CardData.CardType.ATTACK:
			slot_index = 0
		CardData.CardType.SKILL, CardData.CardType.PROTOCOL:
			slot_index = 1

	# 高费检查（优先级低于类型检查）
	if boss_card.energy_cost >= 2 and trap_slots[2] != null:
		var trap: TrapData = trap_slots[2]
		trap_slots[2] = null  # 一次性
		return trap

	if slot_index >= 0 and trap_slots[slot_index] != null:
		var trap: TrapData = trap_slots[slot_index]
		trap_slots[slot_index] = null  # 一次性
		return trap

	return null


func _apply_trap_effect(trap: TrapData, result: ClashResolver.ClashResult) -> void:
	if trap.is_bluff:
		return  # 空白牌无效果

	if trap.interrupt_card:
		# 中断：Boss牌完全无效化
		result.boss_multiplier = 0.0

	if trap.reflect_attack and result.boss_card != null and result.boss_card.damage > 0:
		# 反射：Boss攻击反弹
		var reflected: int = ClashResolver.apply_multiplier_int(result.boss_card.damage, result.boss_multiplier)
		boss.take_damage(reflected, false)
		result.boss_multiplier = 0.0  # 原攻击不再对玩家生效

	if trap.energy_drain > 0:
		boss.energy_modifier_next_turn -= trap.energy_drain

	if trap.type_cost_increase > 0 and result.boss_card != null:
		# 类型封锁永久效果 — 存储到Boss状态（简化：用modifier）
		# TODO: 实现永久类型加费机制
		pass


func _check_insight_effects(probe_result: Dictionary) -> void:
	var streak: int = probe_result["streak"]
	var total: int = probe_result["total"]

	# 连续2次 → 窥视
	if streak == 2 and player.hand.size() > 0:
		var peek_idx: int = randi() % player.hand.size()
		var peeked: CardData = player.hand[peek_idx]
		peeked_cards.append(peeked)
		insight_effect.emit("peek", peeked)

	# 连续3次 → 干扰
	if streak >= 3 and player.hand.size() > 0:
		var disrupt_idx: int = randi() % player.hand.size()
		var disrupted: CardData = player.hand[disrupt_idx]
		disrupted_cards.append(disrupted)
		insight_effect.emit("disrupt", disrupted)

	# 累计5次 → 夺取
	if total >= 5 and player.hand.size() > 0:
		var seize_idx: int = randi() % player.hand.size()
		var seized: CardData = player.hand[seize_idx]
		player.hand.erase(seized)
		player.full_deck.erase(seized)
		boss.full_deck.append(seized)
		boss.deck.append(seized)
		player.hand_changed.emit()
		insight_effect.emit("seize", seized)
		# 重置累计（夺取只触发一次）
		probe.total_hits = 0


# ===== 开发模式 =====

func debug_kill_boss() -> void:
	boss.hp = 0
	_end_battle(true)

func debug_fill_constraints() -> void:
	constraint_resource = 10

func advance_to_probe() -> void:
	## 跳过碰撞直接进入认知结算（调试用）
	_start_probe_phase()

func advance_to_end_round() -> void:
	## 从认知结算进入回合结束
	_end_round()
