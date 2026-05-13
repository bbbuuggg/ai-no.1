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
signal insight_effect(effect_type: String, target_card: CardData)  # peek/disrupt/seize 宣告（本回合 PROBE）
# v0.4.3：洞察实际落地到玩家牌库/手牌时（下回合 ROUND_START）触发，UI 据此播放"二段动画"
signal insight_applied(effect_type: String, target_card: CardData)
# v0.4.2 新增：streak==2 时触发的"随机洞察"预告（peek/disrupt/seize 三选一）。
# 当前仅打日志、不应用真实效果（逻辑留待后续实装），仅作为 Boss 加强的视觉/心理威慑。
signal insight_random_triggered(effect_type: String)

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
# v0.4.3：待应用洞察队列（本回合 PROBE 入队，下回合 ROUND_START apply）
# 每条目: {type, target_card, source_streak, declared_round, applied}
var pending_insights: Array[Dictionary] = []
# v0.4.3：disrupt TTL 计数器（target -> 剩余回合数；0 表示当前回合解锁）
var _disrupt_ttl: Dictionary = {}

# 开发模式
var debug_god_mode: bool = false
var debug_infinite_energy: bool = false

# ===== AI 决策（v0.4 新增 LLM 支持）=====
# AI 实例（LLMBossAI 优先，fallback 到 BlindClashAI 由 LLMBossAI 内部处理）
var boss_ai: AIDecisionInterface = null
# 战斗历史记录（最近回合摘要，供 LLM 推理用）
var _battle_history: Array = []
# 本回合开始时双方 HP/护甲快照（计算 summary 用）
var _round_start_boss_hp: int = 0
var _round_start_player_hp: int = 0
var _round_start_boss_armor: int = 0
var _round_start_player_armor: int = 0
# 本回合发生的事件（陷阱触发、克制结果），ROUND_END 时合并到 summary
var _round_events: Array = []
# 当前对决回合的预计算结果（prepare_clash 填充，UI 逐对 apply 时取用）
var _pending_clash_results: Array[ClashResolver.ClashResult] = []


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
	pending_insights.clear()
	_disrupt_ttl.clear()
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

	# v0.4.3：先衰减/清理上一轮已到期的 disrupt（TTL=0 的解锁）
	# 此时 disrupted_cards 还是上回合 apply 后留下的状态；新一轮 apply_pending_insights 会再补上本轮的
	_decay_disrupted_for_new_round()

	# v0.4.3：在能量/抽牌之前 apply pending_insights —— seize 必须在玩家"看到手牌"前完成
	# 否则会出现"看到一半被夺走"的诡异闪烁。
	apply_pending_insights()

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

	# 陷阱衰减（目前陷阱为一次性，不需要持续管理）
	# 清空上回合的陷阱槽位
	trap_slots = [null, null, null]

	# Boss 认知探针预判（内部计算但不公布，等暗出确认后再显示）
	probe.make_prediction()

	# 记录本回合开始快照（ROUND_END 时计算 summary）
	_round_start_boss_hp = boss.hp
	_round_start_player_hp = player.hp
	_round_start_boss_armor = boss.armor
	_round_start_player_armor = player.armor
	_round_events.clear()

	round_started.emit(round_number)

	# 进入部署阶段
	_start_deploy_phase()


func _start_deploy_phase() -> void:
	# 【部署阶段开始】此时玩家还没部署陷阱，trap_slots 为全空
	# 不在此处预取 LLM —— 否则 LLM 看到的陷阱信息永远是空快照
	# 改为在 confirm_deploy 时（玩家陷阱敲定后）发起预取
	current_phase = Phase.DEPLOY
	if boss_ai != null and boss_ai.has_method("set_current_round"):
		boss_ai.set_current_round(round_number)
	deploy_phase_started.emit()
	# 等待玩家操作（部署陷阱/干扰探针），然后调用 confirm_deploy()


func _start_blind_phase() -> void:
	# 【暗出阶段开始】只广播信号，不再阻塞等待 boss_ai
	# LLM 在 confirm_deploy 已发起预取，此时正在后台跑
	# 玩家选牌期间（5-15s）足够覆盖 LLM 延迟（1-3s）
	# Boss 暗出牌的真正取用推迟到 confirm_blind() —— 玩家点暗出确认时
	current_phase = Phase.BLIND
	player_blind_cards.clear()
	boss_blind_cards.clear()
	player_bound_zero_cards.clear()
	_pending_clash_results.clear()
	blind_phase_started.emit()


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

	# 把本回合摘要追加到历史，供 LLM 下回合参考
	_record_history_for_round()

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
	# 【确认部署】玩家陷阱已敲定，此时才是发起 LLM 请求的正确时机
	# trap_slots 已包含玩家本回合的陷阱布置，LLM 能感知到
	if current_phase != Phase.DEPLOY:
		return
	# 发起 LLM 预取（带最终的 trap_slots 信息 + v0.4.3：本回合已生效的 peek 泄露牌）
	if boss_ai != null:
		boss_ai.warm_up(boss, player, trap_slots, probe, peeked_cards)
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

	# v0.4.3 hotfix-6：泄露是一次性效果。
	# 时机：玩家"确认暗出"成功这一刻，意味着泄露信息已被本回合 LLM 决策消费完毕（warm_up 阶段已传过去），
	# 应立即从战斗状态中清掉 → 下一回合 LLM perception 的 [Leaked] 字段会变回"无泄露牌"。
	# 注意：clear 必须在 hand_changed.emit() 之前，这样 UI 重绘手牌时
	# `if battle.peeked_cards.has(card)` 判断为 false，特效自然消失。
	if not peeked_cards.is_empty():
		peeked_cards.clear()

	player.hand_changed.emit()

	return true


## 确认暗出阶段结束 → 进入对决阶段
func confirm_blind() -> void:
	# 【确认暗出】此时才真正取用 Boss 的暗出牌
	# 玩家选牌期间（5-15s）已足够 LLM 完成思考；
	# 若 LLM 仍未就绪，select_blind_cards_async 内部会等待至 timeout 再 fallback
	if current_phase != Phase.BLIND:
		return
	if player_blind_cards.is_empty():
		# 允许出0张牌（放弃行动）
		pass
	# 取 Boss 暗出牌（LLM 走预取缓存 / fallback 规则 AI；scene 未注入时本地兜底）
	# v0.4.3：再次显式传 peeked_cards，覆盖 warm_up 之后玩家可能产生的变化（保险）
	if boss_ai != null:
		boss_blind_cards = await boss_ai.select_blind_cards_async(boss, player, trap_slots, probe, peeked_cards)
	else:
		boss_blind_cards = BlindClashAI.new().select_blind_cards(boss, player, trap_slots, probe)
	_start_clash_phase()


## 执行完整碰撞结算（一次性，由UI控制翻开动画节奏）
##
## ⚠️ v0.4.2 起：UI 推荐使用 prepare_clash() + apply_clash_pair_at(i)
## 让单对结算与翻牌动画对齐（HP 数字逐对扣，不再瞬间清零）。
## 本方法保留用于无 UI 的测试 / 调试 / 自动战斗。
func resolve_all_clashes() -> Array[ClashResolver.ClashResult]:
	if current_phase != Phase.CLASH:
		return []
	var results: Array[ClashResolver.ClashResult] = prepare_clash()
	for i in range(results.size()):
		apply_clash_pair_at(i)
		if current_phase == Phase.BATTLE_OVER:
			return results
	# 碰撞全部结束 → 认知结算
	if current_phase != Phase.BATTLE_OVER:
		_start_probe_phase()
	return results


## 仅计算碰撞结果（不应用任何效果），把 results 缓存到 _pending_clash_results。
## UI 拿到 results 后逐对播放动画，并在每对的"显示结果"阶段调
## apply_clash_pair_at(index) 来真正提交伤害/陷阱/事件。
func prepare_clash() -> Array[ClashResolver.ClashResult]:
	if current_phase != Phase.CLASH:
		return []
	_pending_clash_results = ClashResolver.resolve_clash(player_blind_cards, boss_blind_cards)
	return _pending_clash_results


## 提交单对碰撞的实际效果（伤害/陷阱/事件/胜负）。
## index 必须在 prepare_clash() 返回的范围内。
## 返回值：本场战斗是否仍在进行（false 表示已 BATTLE_OVER，UI 应停止后续 apply）。
func apply_clash_pair_at(index: int) -> bool:
	if index < 0 or index >= _pending_clash_results.size():
		return current_phase != Phase.BATTLE_OVER
	if current_phase == Phase.BATTLE_OVER:
		return false

	var result: ClashResolver.ClashResult = _pending_clash_results[index]

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
		var bound_zero: CardData = player_bound_zero_cards.get(index, null)
		# v0.4.3 hotfix-4：把绑定 0 费牌写入 ClashResult，UI 据此展示"+抽牌""+伤害"等绑定效果
		result.player_bound_zero = bound_zero
		_resolve_card_with_multiplier(result.player_card, player, boss, result.player_multiplier, bound_zero)

	# 结算Boss牌效果（如果未被陷阱中断）
	if result.boss_card != null and result.boss_multiplier > 0:
		if not (result.trap_triggered and result.trap_data != null and result.trap_data.interrupt_card):
			_resolve_card_with_multiplier(result.boss_card, boss, player, result.boss_multiplier, null)

	clash_pair_resolved.emit(result)

	# 记录本回合事件（ROUND_END 用于生成 summary）
	_round_events.append(_summarize_clash_result(result))

	# 胜负检查
	if player.is_dead() and not debug_god_mode:
		_end_battle(false)
		return false
	if boss.is_dead():
		_end_battle(true)
		return false

	# 全部对决都已结算 → 推进到认知结算
	if index == _pending_clash_results.size() - 1 and current_phase != Phase.BATTLE_OVER:
		_start_probe_phase()

	return true


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
	# v0.4.3：本回合 PROBE 阶段只"宣告 + 入队"，不立刻篡改玩家牌库/手牌。
	# 真实落地（标记 / 锁链 / 物理转移）推迟到下回合 ROUND_START 的 apply_pending_insights()。
	# 这样玩家有 1 回合反应窗口，并由 PendingInsightsBanner UI 持续提示。
	var streak: int = probe_result["streak"]
	var total: int = probe_result["total"]

	# 【v0.4.2 Boss 加强】streak == 2 时额外触发一次"随机洞察预告"
	# 三选一（peek / disrupt / seize），仅 emit 信号给 UI 写日志，
	# 真实效果暂未实现（在以下"原洞察机制"中保留旧的真效果路径）。
	if streak == 2:
		var pool: Array = ["peek", "disrupt", "seize"]
		var chosen: String = pool[randi() % pool.size()]
		insight_random_triggered.emit(chosen)

	# 连续2次 → 窥视（入队）
	if streak == 2 and player.hand.size() > 0:
		var peek_idx: int = randi() % player.hand.size()
		var peeked: CardData = player.hand[peek_idx]
		_enqueue_insight("peek", peeked, streak)

	# 连续3次 → 干扰（入队）
	if streak >= 3 and player.hand.size() > 0:
		var disrupt_idx: int = randi() % player.hand.size()
		var disrupted: CardData = player.hand[disrupt_idx]
		_enqueue_insight("disrupt", disrupted, streak)

	# 累计5次 → 夺取（入队）
	if total >= 5 and player.hand.size() > 0:
		var seize_idx: int = randi() % player.hand.size()
		var seized: CardData = player.hand[seize_idx]
		_enqueue_insight("seize", seized, streak)
		# 重置累计（夺取只触发一次）— 仍在宣告阶段重置，避免下回合再次触发
		probe.total_hits = 0


## v0.4.3：把一次洞察宣告入队，并 emit insight_effect 让 UI 播宣告动画
func _enqueue_insight(effect_type: String, target_card: CardData, source_streak: int) -> void:
	if target_card == null:
		return
	# 防重复入队（同一回合同一目标同一类型只入一次）
	for entry in pending_insights:
		if entry["type"] == effect_type and entry["target_card"] == target_card and entry["declared_round"] == round_number:
			return
	pending_insights.append({
		"type": effect_type,
		"target_card": target_card,
		"source_streak": source_streak,
		"declared_round": round_number,
		"applied": false,
	})
	insight_effect.emit(effect_type, target_card)


## v0.4.3：下回合 ROUND_START 调用，把 pending_insights 真正落地
func apply_pending_insights() -> void:
	if pending_insights.is_empty():
		return
	for entry in pending_insights:
		if entry.get("applied", false):
			continue
		var effect_type: String = entry["type"]
		var target_card: CardData = entry["target_card"]
		match effect_type:
			"peek":
				_apply_peek(target_card)
			"disrupt":
				_apply_disrupt(target_card)
			"seize":
				_apply_seize(target_card)
		entry["applied"] = true
		insight_applied.emit(effect_type, target_card)
	# 清空已应用条目（保持 array 简单：直接清空，未来若有跨多回合条目再调整）
	pending_insights.clear()


## peek 落地：把目标牌登记到 peeked_cards（PerceptionBuilder 下回合即可读取）
## 边界：若目标牌已不在玩家手牌（被弃/消耗），仍登记 —— 下次抽到时仍泄露
func _apply_peek(target_card: CardData) -> void:
	if target_card == null:
		return
	if not peeked_cards.has(target_card):
		peeked_cards.append(target_card)


## disrupt 落地：登记 disrupted_cards + TTL=1（仅作用本回合 BLIND）
## 边界：若目标牌已不在玩家手牌，仍登记 —— BlindSelectUI set_hand 时若手牌中有则锁
func _apply_disrupt(target_card: CardData) -> void:
	if target_card == null:
		return
	if not disrupted_cards.has(target_card):
		disrupted_cards.append(target_card)
	# TTL=1：本回合结束（_decay_disrupted_for_new_round）后解锁
	_disrupt_ttl[target_card] = 1


## seize 落地：物理移除玩家牌，加入 Boss 牌库
## 边界：若目标牌已不在玩家拥有（已弃/已消耗），降级为补偿 peek 一张随机手牌
func _apply_seize(target_card: CardData) -> void:
	if target_card == null:
		return
	# 检查目标是否仍在玩家可拥有的位置（手牌 / 牌库 / 弃牌堆 / full_deck）
	var still_owned: bool = (
		player.hand.has(target_card)
		or player.deck.has(target_card)
		or player.discard_pile.has(target_card)
		or player.full_deck.has(target_card)
	)
	if not still_owned:
		# 降级：随机偷看一张当前手牌（保持 Boss 加强强度）
		if player.hand.size() > 0:
			var fallback: CardData = player.hand[randi() % player.hand.size()]
			_apply_peek(fallback)
			# 用补偿 peek 信号告诉 UI（让玩家也能看到这次降级）
			insight_applied.emit("peek", fallback)
		return
	player.hand.erase(target_card)
	player.deck.erase(target_card)
	player.discard_pile.erase(target_card)
	player.full_deck.erase(target_card)
	boss.full_deck.append(target_card)
	boss.deck.append(target_card)
	player.hand_changed.emit()


## v0.4.3：每个新回合开始时，给 disrupted 牌的 TTL -1，到 0 的解锁
## 调用时机：_next_round 开头、apply_pending_insights 之前
func _decay_disrupted_for_new_round() -> void:
	if _disrupt_ttl.is_empty():
		return
	var to_remove: Array = []
	for key in _disrupt_ttl.keys():
		var ttl: int = _disrupt_ttl[key]
		ttl -= 1
		if ttl <= 0:
			to_remove.append(key)
		else:
			_disrupt_ttl[key] = ttl
	for key in to_remove:
		_disrupt_ttl.erase(key)
		disrupted_cards.erase(key)


# ===== 开发模式 =====

func debug_kill_boss() -> void:
	boss.hp = 0
	_end_battle(true)

func debug_fill_constraints() -> void:
	constraint_resource = 10


## v0.4.3 调试接口：强行触发一次洞察宣告（用于审核动画 / 调参）
## 不依赖 streak 条件，从玩家当前手牌随机选一张作为目标。
## 立即 emit insight_effect 走 UI 演出，并入队 pending_insights，
## 下回合 ROUND_START 会被 apply_pending_insights() 正常落地。
##
## v0.4.3 修订：
## - 接受可选的 hand_idx 参数，让 UI 直接指定哪张牌（避免内部 randi 与 UI 重新查找时
##   因 CardData 引用差异定位错牌）。
## - 返回选中的 CardData（失败返回 null），便于 UI 直接拿到引用做后续标记。
## @param effect_type  "peek" / "disrupt" / "seize"
## @param hand_idx     可选；若 < 0（默认）则随机
## @return  选中的 CardData（玩家手牌为空 / 类型非法 → null）
func debug_trigger_insight(effect_type: String, hand_idx: int = -1) -> CardData:
	if player == null or player.hand.is_empty():
		return null
	if not effect_type in ["peek", "disrupt", "seize"]:
		return null
	var idx: int = hand_idx
	if idx < 0 or idx >= player.hand.size():
		idx = randi() % player.hand.size()
	var target: CardData = player.hand[idx]
	_enqueue_insight(effect_type, target, 99)  # streak=99 标记为 debug 来源
	return target


## v0.4.3 调试接口：把当前 pending_insights 立即落地（绕过等待下回合）
## 配合 debug_trigger_insight() 使用：宣告 → 短暂演出 → 立即 apply。
## 让 banner 在审核场景下也能被自动移除。
func debug_apply_pending_insights() -> void:
	apply_pending_insights()

func advance_to_probe() -> void:
	## 跳过碰撞直接进入认知结算（调试用）
	_start_probe_phase()


# ===== AI 历史记录（供 LLM 上下文）=====

## 把本回合的关键事件摘要追加到 _battle_history，并通知 boss_ai
func _record_history_for_round() -> void:
	# 统计 Boss 出牌类型
	var boss_types: Array = []
	for c in boss_blind_cards:
		boss_types.append(_type_short(c.type))
	# 统计玩家出牌类型
	var player_types: Array = []
	for c in player_blind_cards:
		player_types.append(_type_short(c.type))
	for idx in player_bound_zero_cards:
		player_types.append(_type_short((player_bound_zero_cards[idx] as CardData).type))

	# 计算 HP/护甲变化（自然语言因果，比纯数据有用得多）
	var boss_hp_delta: int = boss.hp - _round_start_boss_hp
	var player_hp_delta: int = player.hp - _round_start_player_hp
	var summary: String = _build_history_summary(boss_hp_delta, player_hp_delta)

	var entry: Dictionary = {
		"turn": round_number,
		"boss_played": boss_types,
		"player_typed": player_types,
		"boss_hp": boss.hp,
		"player_hp": player.hp,
		"boss_hp_delta": boss_hp_delta,
		"player_hp_delta": player_hp_delta,
		"summary": summary,
	}
	_battle_history.append(entry)
	# 仅保留最近 8 回合（容错）
	while _battle_history.size() > 8:
		_battle_history.pop_front()

	# 同步给 LLM AI（如果 AI 实现支持）
	if boss_ai != null and boss_ai.has_method("append_history"):
		boss_ai.append_history(entry)


## 把本回合 _round_events 浓缩成一句话 summary
func _build_history_summary(boss_hp_delta: int, player_hp_delta: int) -> String:
	var parts: Array = []

	# 克制结果统计
	var counter_p: int = 0  # 玩家克制 boss 次数
	var counter_b: int = 0  # boss 克制玩家次数
	var trap_hits: Array = []
	for ev in _round_events:
		match ev.get("clash_type", ""):
			"counter_player": counter_p += 1
			"counter_boss": counter_b += 1
		if ev.get("trap_triggered", false):
			trap_hits.append(ev.get("trap_name", "?"))

	if counter_b > 0:
		parts.append("你克制玩家 %d 次" % counter_b)
	if counter_p > 0:
		parts.append("被玩家克制 %d 次" % counter_p)
	if trap_hits.size() > 0:
		parts.append("触发陷阱: %s" % ", ".join(trap_hits))

	# HP 变化
	if boss_hp_delta < 0:
		parts.append("你 HP-%d" % -boss_hp_delta)
	elif boss_hp_delta > 0:
		parts.append("你 HP+%d" % boss_hp_delta)
	if player_hp_delta < 0:
		parts.append("玩家 HP-%d" % -player_hp_delta)
	elif player_hp_delta > 0:
		parts.append("玩家 HP+%d" % player_hp_delta)

	if parts.is_empty():
		return "中性回合，双方无关键变化"
	return "; ".join(parts)


## 把单对碰撞结果转为字典（_round_events 用）
func _summarize_clash_result(result) -> Dictionary:
	var d: Dictionary = {"clash_type": result.clash_type, "trap_triggered": result.trap_triggered}
	if result.trap_triggered and result.trap_data != null:
		d["trap_name"] = result.trap_data.trap_name if not result.trap_data.is_bluff else "诱饵"
	return d


static func _type_short(t: int) -> String:
	match t:
		CardData.CardType.ATTACK: return "atk"
		CardData.CardType.DEFENSE: return "def"
		CardData.CardType.SKILL: return "skl"
		CardData.CardType.PROTOCOL: return "pro"
	return "?"

func advance_to_end_round() -> void:
	## 从认知结算进入回合结束
	_end_round()
