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

# ===== v0.7 BP 方案 B' 信号（Epic-BP-1） =====
# 触发顺序：bp_phase_changed → bp_candidates_drawn → bp_first_picker_decided
#         → bp_pick_made (×8) → bp_all_picks_locked
#         → bp_clash_pair_resolved (×4) → bp_round_cleanup
signal bp_phase_changed(new_phase: int, old_phase: int)  # BPPhase enum 值
signal bp_candidates_drawn(player_candidates: Array, boss_candidates: Array)  # Q-BP-1 完全可见
signal bp_first_picker_decided(picker: String)  # "player" | "boss"
signal bp_pick_made(picker: String, slot_index: int, card: CardData)  # 单次 Pick（玩家或 Boss）
signal bp_all_picks_locked(player_picks: Array, boss_picks: Array)  # 8 次 Pick 完成，进入翻盅
# Epic-BP-7：reveal 拆出"预计算结果 → UI 揭示完成 → 逐对结算"三段
signal bp_reveal_started(results: Array)  # 揭示阶段开始：results=Array[ClashResolver.ClashResult]，UI 据此画 4 对倍率/克制
signal bp_resolve_started()                # UI 揭示完成 → 进入逐对结算阶段
signal bp_clash_pair_resolved(slot_index: int, result: ClashResolver.ClashResult)  # 同时翻盅期间逐对飘字
signal bp_resolve_completed()              # 4 对 apply 全部完成
signal bp_round_cleanup(player_discarded: Array, boss_discarded: Array)  # 候选 4 张回合末全弃
# v0.7.x-rebal：0 费牌立即生效信号（picker / 候选索引 / 卡 / 已用次数 / 上限）
signal bp_zerocost_used(side: String, candidate_index: int, card: CardData, used_count: int, limit: int)

enum Phase { IDLE, DEPLOY, BLIND, CLASH, PROBE, ROUND_END, BATTLE_OVER }

# v0.7.0 BP 6 阶段状态机（GDD-07 v0.7-locked §5）
# 与旧 Phase enum 并存，BP_MODE_ENABLED=true 时走 BP 路径
enum BPPhase { IDLE, BP_DRAW_CANDIDATES, BP_FIRST_PICKER, BP_PICKING, BP_REVEAL, BP_RESOLVING, BP_ROUND_END, BATTLE_OVER }

# v0.6.0 流程开关：是否启用陷阱/约束部署阶段
# false → 直接跳过 DEPLOY 阶段（_next_round 后立刻进 BLIND），与当前核心博弈解耦
# true  → 旧流程保留（部署 → 暗出 → 对决 → 探针）
# 注意：屏蔽 DEPLOY 时 trap_slots 永远为空、约束资源不再产生消耗——LLM 也看到的是空快照
const ENABLE_TRAP_PHASE: bool = false

# v0.7.0 BP 模式开关（Epic-BP-1）
# true  → 启用 BP 方案 B'（明牌 Pick 4 张 + 同时翻盅），走 _start_bp_* 状态机
# false → 沿用 v0.6.1 暗出对决（_start_blind_phase），用于 v0.7 实施期间随时回退
# Epic-BP-9 烟测通过后此开关将被砍掉，旧 BLIND 路径退役
const BP_MODE_ENABLED: bool = true

# Q-BP-5 锁定：陷阱阶段在 v0.8.0 才回归，BP 模式下永远 false（不要改这里）
# Q-BP-4 更新：0 费机制已恢复（v0.7.x-rebal），由 _try_boss_zerocost_pick() 规则 AI 自动消化；card_database 不再过滤 cost==0
# 灰色地带 #2 锁定（2026-05-15）：LLM 失败 → 单次失败立切兜底规则 AI（不累计），由 LLMBossAI 内部处理

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

# ===== v0.7 BP 方案 B' 状态（Epic-BP-1） =====
var current_bp_phase: BPPhase = BPPhase.IDLE
# Phase 0：候选 4 张（Q-BP-3 = 回合内固定，回合末全弃）
var player_candidates: Array[CardData] = []
var boss_candidates: Array[CardData] = []
# Phase 1：先手 ("player" | "boss")，预留扩展抢先手机制
var first_picker: String = ""
# Phase 2：4 槽出牌位（按 Slot 1~4 顺序，对应数组 index 0~3）
var player_picks: Array[CardData] = [null, null, null, null]
var boss_picks: Array[CardData] = [null, null, null, null]
# 当前激活槽位（0~3，全 -1=未开始/已结束）
var current_pick_slot: int = -1
# 当前轮到谁 Pick ("player" | "boss")，由调度循环切换
var current_picker: String = ""
# 已跳过记录：{ "player": [slot_idx, ...], "boss": [slot_idx, ...] }
# 区别于 picks[slot]==null（可能只是还没轮到），这里只记录主动跳过的 slot
var _skipped_slots: Dictionary = {"player": [], "boss": []}
# Epic-BP-7：BP 模式下的预计算结算结果（reveal 阶段算出，UI 逐对调 apply_bp_clash_pair_at(i) 提交）
var _bp_pending_clash_results: Array[ClashResolver.ClashResult] = []


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
	# v0.7 BP 状态重置（Epic-BP-1）
	current_bp_phase = BPPhase.IDLE
	player_candidates.clear()
	boss_candidates.clear()
	first_picker = ""
	player_picks = [null, null, null, null]
	boss_picks = [null, null, null, null]
	current_pick_slot = -1
	current_picker = ""
	_skipped_slots = {"player": [], "boss": []}
	probe.setup({"attack": 0.4, "defense": 0.3, "skill": 0.3})
	battle_started.emit()
	_next_round()


# ===== 回合流程 =====

func _next_round() -> void:
	round_number += 1
	current_phase = Phase.IDLE

	# v0.7.x-rebal：第 6 回合起每回合开头双向 -1 HP（枯竭曲线，给僵局施压）
	# 设计依据：docs/design/proposals/2026-05-15-hand-deck-economy-rebalance.md §3
	if round_number >= 6:
		player.take_damage(1, true)  # 无视护甲
		boss.take_damage(1, true)
		print("[Attrition] round %d 双方枯竭 -1 HP（player=%d, boss=%d）" % [round_number, player.hp, boss.hp])
		# 枯竭可能直接打死，提前判负避免空跑能量/抽牌
		if player.is_dead() or boss.is_dead():
			# 枯竭同归于尽 → 玩家败（设计：施压机制不为玩家送胜）
			# 单方阵亡 → 按存活者判
			var player_won: bool = boss.is_dead() and not player.is_dead()
			_end_battle(player_won)
			return

	# v0.7.x-rebal：重置每回合 0 费用计数 + 日志
	player.reset_turn_counters()
	boss.reset_turn_counters()

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
	# BP 模式下 draw_modifier_next_turn 不在此处重置——留给 _start_bp_draw_candidates 消费
	# （BP 模式下抽牌后总会补满候选池，modifier 的真实效果是缩小候选池而非减少抽牌数）
	if not BP_MODE_ENABLED:
		player.draw_modifier_next_turn = 0
	player.draw_cards(player_draw)

	var boss_draw: int = maxi(boss.base_draw + boss.draw_modifier_next_turn, 1)
	if not BP_MODE_ENABLED:
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

	# v0.7 BP 模式分流（Epic-BP-1）
	if BP_MODE_ENABLED:
		# Epic-BP-5：每回合开头通知 LLM AI 当前 round（日志/历史记录用）
		# BP 模式不调用 warm_up（BLIND 阶段已被 BP 6 阶段取代，单 slot 决策走 pick_for_slot_async）
		if boss_ai != null and boss_ai.has_method("set_current_round"):
			boss_ai.set_current_round(round_number)
		# BP 路径：跳过部署/陷阱/暗出，直接进入候选抽取
		_start_bp_draw_candidates()
		return

	# v0.6.0：根据开关决定是否进入部署阶段
	if ENABLE_TRAP_PHASE:
		_start_deploy_phase()
	else:
		# 屏蔽陷阱流程时，跳过 DEPLOY 直接进 BLIND
		# 但仍要保证 LLM 预取被发起（原本是在 confirm_deploy 调用 warm_up）
		if boss_ai != null:
			if boss_ai.has_method("set_current_round"):
				boss_ai.set_current_round(round_number)
			boss_ai.warm_up(boss, player, trap_slots, probe, peeked_cards)
		_start_blind_phase()


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

	# 暗出的牌移入弃牌堆（BP 路径下 blind_cards 可能含 null 占位，需守门）
	for card in player_blind_cards:
		if card == null:
			continue
		player.discard_pile.append(card)
	for idx in player_bound_zero_cards:
		player.discard_pile.append(player_bound_zero_cards[idx])
	for card in boss_blind_cards:
		if card == null:
			continue
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
	# Epic-BP-7：BP 路径下也要切 BPPhase，避免 apply_bp_clash_pair_at 在战斗结束后继续处理后续对决
	if BP_MODE_ENABLED:
		_set_bp_phase(BPPhase.BATTLE_OVER)
	battle_ended.emit(player_won)


# ===== 玩家操作接口 =====

## 部署陷阱到指定槽位（0=攻击, 1=技能, 2=高费）
##
## skip_resource_cost: true 时跳过资源校验和扣款（用于 UI 内已扣减的最终回写）
##   单一信源原则：UI 在部署过程中已正确扣减 _constraint_resource，
##   确认时由 scene 把 UI 的最终值写回 battle.constraint_resource，
##   再以 skip_resource_cost=true 调用此函数，避免双重扣款的时序 BUG
func deploy_trap(trap: TrapData, slot_index: int, skip_resource_cost: bool = false) -> bool:
	if current_phase != Phase.DEPLOY:
		return false
	if slot_index < 0 or slot_index > 2:
		return false
	if trap_slots[slot_index] != null:
		return false  # 槽位已占
	if not skip_resource_cost:
		if not trap.is_bluff and trap.resource_cost > constraint_resource:
			return false
	if not trap_inventory.has(trap):
		return false

	# 消耗资源（仅当外部未自行扣款时）
	if not skip_resource_cost:
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
	# 统计 Boss 出牌类型（BP 路径下 picks 可能含 null 占位，需守门）
	var boss_types: Array = []
	for c in boss_blind_cards:
		if c == null:
			continue
		boss_types.append(_type_short(c.type))
	# 统计玩家出牌类型（同样守门）
	var player_types: Array = []
	for c in player_blind_cards:
		if c == null:
			continue
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


# ============================================================
# v0.7 BP 方案 B' 状态机（Epic-BP-1/2/3）
# 6 阶段：BP_DRAW_CANDIDATES → BP_FIRST_PICKER → BP_PICKING → BP_REVEAL → BP_RESOLVING → BP_ROUND_END
# ============================================================

## 设置 BP 阶段并发射信号（统一入口，方便 UI 监听）
func _set_bp_phase(new_phase: BPPhase) -> void:
	var old_phase: BPPhase = current_bp_phase
	current_bp_phase = new_phase
	bp_phase_changed.emit(int(new_phase), int(old_phase))
	print("[BP] Phase: %s → %s" % [BPPhase.keys()[old_phase], BPPhase.keys()[new_phase]])


## Phase 0：双方各抽 6 张候选（v0.7.x-rebal：HAND_POOL_SIZE = 6 候选窗，4 槽从中筛选）
## Q-BP-1 完全可见 + Q-BP-3 回合内固定（v0.7.x 全明牌契约）
func _start_bp_draw_candidates() -> void:
	_set_bp_phase(BPPhase.BP_DRAW_CANDIDATES)

	# 清空上回合候选（保险，_next_round 已 clear 一次）
	player_candidates.clear()
	boss_candidates.clear()

	# v0.7.x-rebal：候选窗 = hand 6 张（HAND_POOL_SIZE），先把 hand 补满到 6 张再灌入 candidates
	# enemy_draw_modifier 修正：如果对手上回合对你施加了"抽牌-1"，你的候选池缩小 1 张
	var player_pool_size: int = maxi(Combatant.HAND_POOL_SIZE + player.draw_modifier_next_turn, 1)
	player.draw_modifier_next_turn = 0
	var boss_pool_size: int = maxi(Combatant.HAND_POOL_SIZE + boss.draw_modifier_next_turn, 1)
	boss.draw_modifier_next_turn = 0

	if player.hand.size() < player_pool_size:
		player.draw_cards(player_pool_size - player.hand.size())
	if boss.hand.size() < boss_pool_size:
		boss.draw_cards(boss_pool_size - player.hand.size())

	# 如果抽牌后手牌超过有效池大小（上回合有余牌+抽牌未到 limit），裁剪到池大小
	while player.hand.size() > player_pool_size:
		var discarded: CardData = player.hand.pop_back()
		player.discard_pile.append(discarded)
	while boss.hand.size() > boss_pool_size:
		var discarded: CardData = boss.hand.pop_back()
		boss.discard_pile.append(discarded)

	# 全量同步 hand → candidates（hand 可能仍不足：牌库+弃牌堆都空了，那就用现有数量）
	for card in player.hand:
		player_candidates.append(card)
	for card in boss.hand:
		boss_candidates.append(card)

	print("[BP] DrawCandidates: player=%d boss=%d" % [player_candidates.size(), boss_candidates.size()])

	# Q-BP-1 完全可见：广播双方候选（含完整 CardData，UI 可直接渲染对方候选）
	bp_candidates_drawn.emit(player_candidates.duplicate(), boss_candidates.duplicate())

	# 推进到 Phase 1：随机先手
	_start_bp_first_picker()


## Phase 1：决定先手（轮流制，首回合随机）
## v0.8.0-locked.1 修订：
##   - 第 1 回合：随机决定先手（randi % 2）
##   - 第 N>1 回合：与上回合先手相反（轮流交换）
##   - first_picker 字段在战斗内持续写入，横幅 UI 监听信号渲染
##   - 注：跨"Run 轮"（victory_streak 推进）后视为新场战斗，round_number 重置为 1，
##         届时再次走"首回合随机"分支（这是合理的：每场新战斗起点都重新洗牌）
func _start_bp_first_picker() -> void:
	_set_bp_phase(BPPhase.BP_FIRST_PICKER)

	# 轮流先手 + 首回合随机
	if round_number <= 1 or first_picker == "":
		# 首回合（或异常未初始化）：随机决定
		first_picker = "player" if (randi() % 2 == 0) else "boss"
		print("[BP] FirstPicker: %s (首回合随机)" % first_picker)
	else:
		# 后续回合：与上回合相反（轮流交换）
		first_picker = "boss" if first_picker == "player" else "player"
		print("[BP] FirstPicker: %s (轮流先手 R%d)" % [first_picker, round_number])
	current_picker = first_picker

	# v0.8.0 蛇形出牌：通知 LLM AI 当前回合的 first_picker（用于 build_for_slot_pick 计算 slot_leader）
	if boss_ai != null and boss_ai.has_method("set_first_picker"):
		boss_ai.set_first_picker(first_picker)

	# 广播给 UI 播放横幅演出（scene 监听该信号 → 实例化 first_picker_banner）
	# v0.7.x-hotfix5：横幅 2.0s + 牌局淡入 0.4s + 缓冲 0.6s = 3.0s 兜底
	# 严格串行：横幅完全谢幕后才开始淡入牌局
	bp_first_picker_decided.emit(first_picker)

	# 等待横幅播完（UI 那边 await timer 后调 confirm_first_picker_banner_done()）
	# 当前 stub：3.0s 后自动推进（Epic-BP-3 UI 落地后改由 UI 主动推进）
	await get_tree().create_timer(3.0).timeout
	# 防御：若战斗已结束（debug_kill_boss）则不推进
	if current_phase == Phase.BATTLE_OVER or current_bp_phase == BPPhase.BATTLE_OVER:
		return
	_start_bp_picking()


## Phase 2：蛇形 Pick 调度（v0.8.0 Snake Draft）
##
## 触发顺序（v0.8.0 蛇形出牌）：
##   偶数 Slot（0,2）：先手方先 Pick → 后手方 Pick
##   奇数 Slot（1,3）：后手方先 Pick → 先手方 Pick
##   等价于 1-2-2-2-1 序列：先手方在 Slot1 出1 → 后手方 Slot1+2 各出1 → …
##   先手信息优/劣势 2:2 完美平衡
##
## 状态机：
##   current_pick_slot ∈ [0..3]：当前激活的槽位
##   current_picker ∈ {"player", "boss"}：当前轮到谁
##
## 接口：
##   make_player_pick(candidate_index) → 玩家点击候选时调用，返回是否成功
##   _request_boss_pick() → 内部调度：调 boss_ai 选牌 + 写入 slot
func _start_bp_picking() -> void:
	# 先设状态，再 emit phase_changed（避免监听者读到旧的 current_picker）
	current_pick_slot = 0
	# v0.8.0 蛇形出牌：Slot 0 偶数槽 → first_picker 先出
	current_picker = _get_slot_leader(0)
	_skipped_slots = {"player": [], "boss": []}
	_set_bp_phase(BPPhase.BP_PICKING)
	print("[BP] Picking: 进入蛇形 Pick 阶段，先手=%s，Slot 1 先出方=%s" % [first_picker, current_picker])

	# 启动调度：如果先手是 Boss，立即让 Boss Pick；如果是玩家则等 UI 调用 make_player_pick
	_advance_pick_turn()


## 推进 Pick 调度：根据 current_picker 决定动作
## - player：检查是否有可出的牌，没有则自动跳过；有则等 UI 触发 make_player_pick
## - boss：立即调度 _request_boss_pick
func _advance_pick_turn() -> void:
	if current_bp_phase != BPPhase.BP_PICKING:
		return

	# 全部 Pick 完成 → 进入翻盅
	if current_pick_slot >= 4:
		_finish_picking()
		return

	if current_picker == "boss":
		# Boss 自动 Pick（Epic-BP-4 用规则 AI 占位，Epic-BP-5 接 LLM）
		_request_boss_pick()
	elif current_picker == "player":
		# 玩家轮次：检查是否有任何可出的牌
		if _player_has_no_playable_card():
			# 无能量出牌 → 自动跳过（延迟一帧，避免递归 _advance_pick_turn 栈溢出）
			print("[BP] 玩家无能量出牌，自动跳过 slot %d" % (current_pick_slot + 1))
			await get_tree().process_frame
			if current_bp_phase != BPPhase.BP_PICKING or current_picker != "player":
				return
			skip_player_pick()
	# 否则：等 UI 调用 make_player_pick 或 skip_player_pick


## 玩家当前是否没有任何可出的牌（无能量起任何候选）
func _player_has_no_playable_card() -> bool:
	if player == null:
		return true
	for c in player_candidates:
		if c == null:
			continue
		if c.energy_cost == 0:
			# 0 费牌：还需检查本回合 0 费使用次数是否已满
			if player.can_use_zerocost():
				return false
			continue
		if c.energy_cost <= player.energy:
			return false
	return true


## 玩家 Pick 接口：UI 在玩家点击候选卡时调用
##
## @param candidate_index: 候选数组索引（0~3）
## @return: true=成功 / false=失败（轮次错/索引错/能量不足/卡已被 picked）
##
## 失败原因会通过 print 打日志，UI 可自行配合 toast 提示
func make_player_pick(candidate_index: int) -> bool:
	if current_bp_phase != BPPhase.BP_PICKING:
		print("[BP] make_player_pick 拒绝：当前阶段不是 BP_PICKING")
		return false
	if current_picker != "player":
		print("[BP] make_player_pick 拒绝：当前轮到 %s 而非 player" % current_picker)
		return false
	if candidate_index < 0 or candidate_index >= player_candidates.size():
		print("[BP] make_player_pick 拒绝：候选索引越界 %d" % candidate_index)
		return false

	var card: CardData = player_candidates[candidate_index]
	if card == null:
		print("[BP] make_player_pick 拒绝：该候选已被 Pick (idx=%d)" % candidate_index)
		return false

	# v0.7.x-rebal：0 费牌不进 slot、不切 picker，立即结算并补抽（每回合限 ZEROCOST_LIMIT_PER_TURN 次）
	if card.energy_cost == 0:
		return use_zerocost_card("player", candidate_index)

	# Q-BP-4：cost > 0 才扣能量
	if player.energy < card.energy_cost:
		print("[BP] make_player_pick 拒绝：能量不足 (need=%d, have=%d)" % [card.energy_cost, player.energy])
		return false

	# === 扣能量 + 写入 picks + 候选置 null（保留索引稳定）===
	player.energy -= card.energy_cost
	player.energy_changed.emit(player.energy)

	player_picks[current_pick_slot] = card
	player_candidates[candidate_index] = null  # Q-BP-3：候选位锁定（不补抽）

	bp_pick_made.emit("player", current_pick_slot, card)
	print("[BP] pick: player → slot %d (%s, cost=%d, energy_left=%d)" % [
		current_pick_slot + 1, card.card_name, card.energy_cost, player.energy
	])

	_after_pick_advance()
	return true


## v0.7.x-rebal：0 费牌立即生效路径
##
## 设计契约：
##   1. 不进入 picks 槽，不切换 picker turn（仍是当前一方继续 Pick）
##   2. 立即应用效果（draw_cards / discard_hand_and_draw / reshuffle_discard）
##   3. 每回合每方上限 ZEROCOST_LIMIT_PER_TURN（默认 2 次）
##   4. 0 费牌从候选移除（置 null，索引稳定）并进入弃牌堆
##   5. 触发新增信号 bp_zerocost_used 让 UI 刷新候选 + 显示日志
##   6. 全明牌契约：使用记录写入 combatant.zerocost_used_log，对方可见
##
## @param side: "player" 或 "boss"
## @param candidate_index: 候选索引
## @return: true=成功
func use_zerocost_card(side: String, candidate_index: int) -> bool:
	if current_bp_phase != BPPhase.BP_PICKING:
		print("[ZC] 拒绝：phase 不是 BP_PICKING")
		return false
	var caster: Combatant = player if side == "player" else boss
	var candidates: Array = player_candidates if side == "player" else boss_candidates

	if candidate_index < 0 or candidate_index >= candidates.size():
		print("[ZC] 拒绝：索引越界")
		return false
	var card: CardData = candidates[candidate_index]
	if card == null or card.energy_cost != 0:
		print("[ZC] 拒绝：该候选不是 0 费牌")
		return false
	if not caster.can_use_zerocost():
		print("[ZC] 拒绝：%s 本回合 0 费已用满（%d/%d）" % [
			side, caster.zerocost_used_this_turn, Combatant.ZEROCOST_LIMIT_PER_TURN
		])
		return false

	# 标记使用 + 立即结算
	caster.mark_zerocost_used(card.id)
	candidates[candidate_index] = null  # 候选位锁定
	# 移到弃牌堆（hand 包含该卡：BP 模式 hand=candidates，所以从 hand 也要清掉）
	caster.hand.erase(card)
	caster.discard_pile.append(card)

	_resolve_zerocost_immediate(caster, card)

	# 广播信号（UI 刷新 + 全明牌可见）
	bp_zerocost_used.emit(side, candidate_index, card,
		caster.zerocost_used_this_turn, Combatant.ZEROCOST_LIMIT_PER_TURN)

	print("[ZC] %s 使用 %s（本回合 %d/%d）" % [
		side, card.card_name,
		caster.zerocost_used_this_turn, Combatant.ZEROCOST_LIMIT_PER_TURN
	])
	return true


## 0 费牌效果实际应用（共用三种 0 费牌的结算）
func _resolve_zerocost_immediate(caster: Combatant, card: CardData) -> void:
	# 1. 抽牌（c_inspiration_surge）
	# v0.7.x-hotfix2：BUG FIX —— 抽到的新牌只会进 caster.hand，但 BP 模式 UI 渲染的是
	# player_candidates / boss_candidates 这条独立数组；必须把新抽到的卡精确同步到
	# candidates 的 null 位，否则 UI 上"少了一张"。
	# 不能直接复用 _sync_hand_to_candidates（它会把"已 pick 进 slot 但仍在 hand 的卡"
	# 错误回填进候选窗）。改为精确处理：记录抽前 hand 长度，抽后取末尾新增项。
	if card.draw_cards > 0:
		var cands_ref: Array = player_candidates if caster == player else boss_candidates
		var hand_size_before: int = caster.hand.size()
		caster.draw_cards(card.draw_cards)
		# 把新抽到的牌（hand 末尾追加项）依次填到 candidates 的第一个 null 位
		var newly_drawn: Array = caster.hand.slice(hand_size_before)
		for nc in newly_drawn:
			for i in range(cands_ref.size()):
				if cands_ref[i] == null:
					cands_ref[i] = nc
					break
	# 2. 弃所有候选未 pick 的牌再抽相同数量（c_reorganize "弃几张抽几张"）
	#    注：BP 模式下 hand = 候选窗，"弃手牌"语义 = 弃所有未 pick 的非 null 候选
	if card.discard_hand_and_draw > 0:
		var cands_ref: Array = player_candidates if caster == player else boss_candidates
		# 先统计将被弃的张数（不包含 card 自己 — 已经在前面 erase 过）
		var discard_count: int = 0
		for i in range(cands_ref.size()):
			var c: CardData = cands_ref[i]
			if c != null and c != card:
				caster.hand.erase(c)
				caster.discard_pile.append(c)
				cands_ref[i] = null
				discard_count += 1
		# 抽相同数量（设计承诺：弃几张抽几张，再加上 c_reorganize 自身效果不补"+1"）
		# 上限保护：不超过 HAND_POOL_SIZE，避免 deck 异常时无限抽
		var draw_n: int = mini(discard_count, Combatant.HAND_POOL_SIZE)
		if draw_n > 0:
			caster.draw_cards(draw_n)
		# 抽完后把新 hand 同步回 candidates（保持 BP 候选 = hand 契约）
		_sync_hand_to_candidates(caster)
	# 3. 洗弃牌堆回牌库（c_resonance_loop）
	if card.reshuffle_discard:
		# 把 discard 全部洗回 deck（不动 hand 和 candidates）
		caster.deck.append_array(caster.discard_pile)
		caster.discard_pile.clear()
		caster.deck.shuffle()
		caster.deck_changed.emit()


## 重整牌后把 hand 同步回 candidates 数组（填充 null 槽位）
func _sync_hand_to_candidates(caster: Combatant) -> void:
	var cands_ref: Array = player_candidates if caster == player else boss_candidates
	# 收集已经在 cands 中的非 null（被 pick 过 → null；没被 pick 的非 0 费仍存在）
	# 然后把 hand 中不在 cands 的牌追加到 null 位
	var existing := {}
	for c in cands_ref:
		if c != null:
			existing[c] = true
	for h in caster.hand:
		if existing.has(h):
			continue
		# 找一个 null 位插入
		for i in range(cands_ref.size()):
			if cands_ref[i] == null:
				cands_ref[i] = h
				break


## 玩家跳过当前 Slot Pick（无能量起任何候选牌时的兜底）
##
## UI 在 make_player_pick 全部返回 false 或玩家选择"跳过"按钮时调用。
## 等价于 Boss 无可 Pick 时的 null 路径。
func skip_player_pick() -> bool:
	if current_bp_phase != BPPhase.BP_PICKING:
		return false
	if current_picker != "player":
		return false
	_skipped_slots["player"].append(current_pick_slot)
	bp_pick_made.emit("player", current_pick_slot, null)
	print("[BP] player 跳过 slot %d（无可 Pick 牌）" % (current_pick_slot + 1))
	_after_pick_advance()
	return true


## Boss Pick：v0.7.0-alpha Epic-BP-5 接入 LLM 单 slot 决策
##
## 决策链：
##   1. 先算规则 AI 推荐（`_boss_rule_pick()`）—— 作为 LLM 的"直觉建议"参考 + fallback
##   2. 若 boss_ai 实现了 `pick_for_slot_async`（即 LLMBossAI），调用 LLM 决策
##      - LLM 返回有效 pick_index → 用 LLM 选择
##      - LLM 失败/未配置/降级（返回 -1）→ 用规则 AI 推荐
##   3. 否则直接用规则 AI（兼容旧 BlindClashAI 等不支持 BP 的实现）
##
## 思考延迟：LLM 自带网络延迟（1-3s），不再额外加 sleep；
##           规则 AI 兜底时仍保留 0.4s 模拟思考，避免 UI 节奏跳脱
func _request_boss_pick() -> void:
	if current_bp_phase != BPPhase.BP_PICKING or current_picker != "boss":
		return

	# v0.7.x-hotfix：Boss 0 费规则 AI（在 slot 决策前优先消化 0 费牌，因为不切 picker）
	# 简化为单规则：boss.hp <= 8 且候选含 c_inspiration_surge → 抽 1 找救命
	# 触发后 return（picker 仍是 boss，本帧 _after_pick_advance 不会被调用）
	if _try_boss_zerocost_pick():
		# Boss 用了 0 费，0.4s 思考延迟后再次进入决策（可能再用一张或转向 cost > 0）
		await get_tree().create_timer(0.4).timeout
		if current_bp_phase != BPPhase.BP_PICKING or current_picker != "boss":
			return
		_request_boss_pick()
		return

	# 1. 先算规则 AI 推荐（始终算，作为 LLM 输入 + fallback）
	var rule_pick_idx: int = _boss_rule_pick()

	# 2. 若 boss_ai 是 LLM 实现 → 调 BP 单 slot 接口
	var llm_pick_idx: int = -1
	var used_llm: bool = false
	if boss_ai != null and boss_ai.has_method("pick_for_slot_async"):
		used_llm = true
		# pick_for_slot_async 内部已经记录请求时间，不再外面加 sleep
		llm_pick_idx = await boss_ai.pick_for_slot_async(
			boss, player,
			boss_candidates, player_candidates,
			boss_picks, player_picks,
			current_pick_slot, round_number, rule_pick_idx
		)
		# 防御：异步期间 phase 可能已经被推进（debug_kill_boss / 玩家点跳过等），二次确认
		if current_bp_phase != BPPhase.BP_PICKING or current_picker != "boss":
			return

	# 3. 决定最终 pick_idx：
	#    - LLM 返回 >=0 → 用 LLM 选择
	#    - LLM 返回 -2 → LLM 主动 skip（v0.8.2 方案 D-3：留空作为合法战术）
	#    - LLM 返回 -1 / 没用 LLM → 走规则 AI 兜底
	var pick_idx: int = -1
	var llm_skipped: bool = false
	if used_llm and llm_pick_idx == -2:
		llm_skipped = true
		print("[BP] Boss[LLM] 主动 skip slot %d（战术留空）" % (current_pick_slot + 1))
	elif used_llm and llm_pick_idx >= 0:
		pick_idx = llm_pick_idx
	else:
		# 没用 LLM（旧实现）/ LLM 失败 → 规则 AI 兜底，加 0.4s 思考延迟保 UI 节奏
		if not used_llm:
			await get_tree().create_timer(0.4).timeout
			if current_bp_phase != BPPhase.BP_PICKING or current_picker != "boss":
				return
		pick_idx = rule_pick_idx

	if llm_skipped:
		# LLM 主动留空：与"被动无解"走相同的 emit 路径，但日志区分
		_skipped_slots["boss"].append(current_pick_slot)
		bp_pick_made.emit("boss", current_pick_slot, null)
		_after_pick_advance()
		return

	if pick_idx < 0:
		# 极端情况：Boss 没有任何能起的牌（能量为 0 或候选全 null）
		# 兜底：跳过本 slot（Boss pick 留 null）— 翻盅时 ClashResolver 会按毫无阻力×2 处理
		_skipped_slots["boss"].append(current_pick_slot)
		print("[BP] Boss 无可 Pick，slot %d 跳过（毫无阻力）" % (current_pick_slot + 1))
		bp_pick_made.emit("boss", current_pick_slot, null)
		_after_pick_advance()
		return

	var card: CardData = boss_candidates[pick_idx]
	# v0.7.x-hotfix2：双保险——若 LLM/规则 误返了 0 费索引，统一走 zerocost 通道，
	# 行为对齐玩家（不进 slot、不切 picker、立即抽 1）。本帧消化掉后等 0.4s 再决策。
	if card.energy_cost == 0:
		var zc_ok: bool = use_zerocost_card("boss", pick_idx)
		if zc_ok:
			await get_tree().create_timer(0.4).timeout
			if current_bp_phase != BPPhase.BP_PICKING or current_picker != "boss":
				return
			_request_boss_pick()
		return

	if card.energy_cost > 0:
		boss.energy -= card.energy_cost
		boss.energy_changed.emit(boss.energy)

	boss_picks[current_pick_slot] = card
	boss_candidates[pick_idx] = null

	bp_pick_made.emit("boss", current_pick_slot, card)
	var src_tag: String = "LLM" if (used_llm and llm_pick_idx >= 0) else "rule"
	print("[BP] pick: boss[%s] → slot %d (%s, cost=%d, energy_left=%d)" % [
		src_tag, current_pick_slot + 1, card.card_name, card.energy_cost, boss.energy
	])

	_after_pick_advance()


## v0.7.x-hotfix2：Boss 0 费规则 AI（在主决策前调用）
##
## 行为对齐玩家：候选含 0 费牌 + 本回合 0 费未用满 → 立即使用，
## 不进 slot、不切 picker。这样 Boss 用 c_inspiration_surge 就和玩家一样
## 只是抽 1 张，不会被错误塞进 picks 槽。
##
## @return: true=本帧打出了 0 费牌，调用方应等候 0.4s 后再次调度
func _try_boss_zerocost_pick() -> bool:
	if not boss.can_use_zerocost():
		return false

	# 找候选里第一张 0 费牌
	for i in range(boss_candidates.size()):
		var c: CardData = boss_candidates[i]
		if c != null and c.energy_cost == 0:
			return use_zerocost_card("boss", i)
	return false


## Boss 简单规则 AI：均匀分配能量策略 —— 优先保证每个 slot 都能填一张牌
##
## 策略：
##   预算 = floor(剩余能量 / 剩余 slot 数)
##   - 在候选里选 cost ≤ 预算的牌中 cost 最高的（不浪费预算 + 不挤占后续槽位）
##   - 若预算=0（能量不够分摊，例：1 能量剩 2 slot）→ 选最便宜的能起的牌
##   - 若全无能起的牌 → 返回 -1（_request_boss_pick 走兜底留空）
##
## 返回候选索引（0~3），全部不可选时返回 -1
##
## Epic-BP-5 LLM 接入后此函数会被 boss_ai.pick_for_slot_async 替代
func _boss_rule_pick() -> int:
	# 计算剩余 slot 数（含当前 slot）：4 - current_pick_slot
	var slots_left: int = 4 - current_pick_slot
	if slots_left <= 0:
		return -1

	# 预算 = 平均每槽可用能量（向下取整，保守留量）
	var budget: int = boss.energy / slots_left

	# === Pass 1：预算 > 0 → 选 cost ≤ 预算的牌中 cost 最高的 ===
	# v0.7.x-hotfix2：跳过 0 费（已被 _try_boss_zerocost_pick 前置消化，进入这里说明本回合 0 费用满）
	if budget > 0:
		var best_idx: int = -1
		var best_cost: int = -1
		for i in range(boss_candidates.size()):
			var c: CardData = boss_candidates[i]
			if c == null:
				continue
			if c.energy_cost == 0:
				continue  # 0 费走 zerocost 通道，不进 slot
			if c.energy_cost > budget:
				continue  # 超预算 → 留给后续槽位
			if c.energy_cost > best_cost:
				best_cost = c.energy_cost
				best_idx = i
		if best_idx >= 0:
			return best_idx
		# Pass 1 找不到（全部超预算）→ 退到 Pass 2 选最便宜的

	# === Pass 2：预算=0 或 Pass 1 失败 → 选能起的牌中 cost 最低的（保槽位优先）===
	# v0.7.x-hotfix2：同样跳过 0 费
	var cheapest_idx: int = -1
	var cheapest_cost: int = 999
	for i in range(boss_candidates.size()):
		var c: CardData = boss_candidates[i]
		if c == null:
			continue
		if c.energy_cost == 0:
			continue
		if c.energy_cost > boss.energy:
			continue
		if c.energy_cost < cheapest_cost:
			cheapest_cost = c.energy_cost
			cheapest_idx = i
	return cheapest_idx


## 单次 Pick 完成后推进调度：切换 picker / 切换 slot
## v0.8.0 蛇形出牌（Snake Draft）：偶数槽先手方先出，奇数槽后手方先出
## 等价于 1-2-2-2-1 序列，2:2 完美平衡先手信息优/劣势
func _after_pick_advance() -> void:
	# 当前 slot 的"先出方"由奇偶决定
	var slot_leader: String = _get_slot_leader(current_pick_slot)

	if current_picker == slot_leader:
		# 先出方刚 Pick 完，切到后出方（同一 Slot）
		current_picker = "boss" if slot_leader == "player" else "player"
	else:
		# 后出方刚 Pick 完，进入下一 Slot
		current_pick_slot += 1
		# 下一 Slot 的先出方由奇偶决定
		if current_pick_slot < 4:
			current_picker = _get_slot_leader(current_pick_slot)

	_advance_pick_turn()


## 蛇形出牌辅助：返回指定 slot 的"先出方"
## 偶数 slot（0,2）→ first_picker 先出；奇数 slot（1,3）→ second_picker 先出
func _get_slot_leader(slot: int) -> String:
	if slot % 2 == 0:
		return first_picker
	else:
		return "boss" if first_picker == "player" else "player"


## 玩家在某 Slot 是否已主动跳过（无能量出牌）
func _slot_player_skipped(slot: int) -> bool:
	return slot in _skipped_slots["player"]


func _slot_boss_skipped(slot: int) -> bool:
	return slot in _skipped_slots["boss"]


## 8 次 Pick 全部完成 → 进入翻盅
func _finish_picking() -> void:
	bp_all_picks_locked.emit(player_picks.duplicate(), boss_picks.duplicate())
	_start_bp_reveal()


## Phase 3：揭示阶段（Epic-BP-7）
## 仅做"预计算结果 + 同步 picks→blind_cards + emit bp_reveal_started"
## **不应用伤害**！应用由 UI 端逐对调 apply_bp_clash_pair_at(i) 触发，确保飘字与扣血对齐
func _start_bp_reveal() -> void:
	_set_bp_phase(BPPhase.BP_REVEAL)
	print("[BP] Reveal: 预计算 4 对结果，等 UI 揭示完成")

	# 把 picks 灌进 blind_cards（严格按 slot index 对位，保留 null 让 ClashResolver 走 neutral）
	# 这一步是为了让 _resolve_card_with_multiplier 走旧管道时能正确读 blind_cards 索引
	player_blind_cards.clear()
	boss_blind_cards.clear()
	for c in player_picks:
		player_blind_cards.append(c)  # 保留 null，对位 slot 索引
	for c in boss_picks:
		boss_blind_cards.append(c)

	# 仅算结果，不应用
	_bp_pending_clash_results = ClashResolver.resolve_clash(player_blind_cards, boss_blind_cards)
	bp_reveal_started.emit(_bp_pending_clash_results)
	# 等 UI 调 confirm_bp_reveal_done() 推进


## Epic-BP-7：UI 揭示动画（4 对同时光晕 + 倍率标签）播完后调用，进入逐对结算
func confirm_bp_reveal_done() -> void:
	if current_bp_phase != BPPhase.BP_REVEAL:
		return
	_start_bp_resolving()


## Phase 4：结算阶段（Epic-BP-7 拆分版）
## 不再同步 apply 全部 4 对；只 emit bp_resolve_started，UI 端按 350ms/对错开调 apply_bp_clash_pair_at(i)
func _start_bp_resolving() -> void:
	_set_bp_phase(BPPhase.BP_RESOLVING)
	print("[BP] Resolving: 等 UI 逐对调 apply_bp_clash_pair_at")
	bp_resolve_started.emit()


## Epic-BP-7：UI 在每对飘字时机调用，提交单对的伤害/护甲/buff 到 Combatant
##
## @param index: 0~3 对应 Slot 1~4
## @return: true=已应用 / false=拒绝（阶段错 / 索引错 / 战斗已结束）
func apply_bp_clash_pair_at(index: int) -> bool:
	if current_bp_phase != BPPhase.BP_RESOLVING:
		return false
	if index < 0 or index >= _bp_pending_clash_results.size():
		return false

	var result: ClashResolver.ClashResult = _bp_pending_clash_results[index]

	# 应用结算（玩家牌效果）
	if result.player_card != null and result.player_multiplier > 0:
		_resolve_card_with_multiplier(result.player_card, player, boss, result.player_multiplier, null)
	# 应用结算（Boss 牌效果）
	if result.boss_card != null and result.boss_multiplier > 0:
		_resolve_card_with_multiplier(result.boss_card, boss, player, result.boss_multiplier, null)

	# 广播单对结果（UI 飘字 + 旧日志兼容）
	bp_clash_pair_resolved.emit(index, result)
	clash_pair_resolved.emit(result)

	# 胜负检查（一对就死也立即收尾）
	if player.is_dead() and not debug_god_mode:
		_end_battle(false)
		return true
	if boss.is_dead():
		_end_battle(true)
		return true

	# 最后一对应用完 → 进 round_end（延迟 0.6s 让飘字 + 血条扣减播完，避免立刻被新回合刷掉）
	if index == _bp_pending_clash_results.size() - 1:
		bp_resolve_completed.emit()
		_finish_resolving_after_delay()  # 不 await，由内部 timer 推进

	return true


func _finish_resolving_after_delay() -> void:
	## Epic-BP-7：最后一对应用后延迟让飘字/血条 tween 完整播放
	## v0.3 翻盅回归：演出节奏由 ClashDisplayUI 主控，此处仅做战斗状态机收尾兜底，缩短到 0.6s
	## （ClashDisplayUI 自身在最后一对 RESOLVE_DUR 已留出 1.6s，再叠 0.6s 即可触发 round_end）
	await get_tree().create_timer(0.6).timeout
	if current_bp_phase == BPPhase.BP_RESOLVING:
		_start_bp_round_end()


## Phase 5：回合末清理（v0.7.x-rebal2：6 选 4 → 未 Pick 的 2 张保留进下回合）
func _start_bp_round_end() -> void:
	_set_bp_phase(BPPhase.BP_ROUND_END)

	# v0.7.x-rebal2：候选窗 6 张里只 Pick 4 张（PICK_SLOTS） → 剩 2 张未被 Pick 的牌保留到下回合
	# 已 Pick 的牌（picks 数组）→ discard
	# 未 Pick 的牌（candidates 中非 null 且不在 picks 中）→ 留在 hand，下回合 _start_bp_draw_candidates 自动补满至 6 张
	# 0 费立即生效的牌：在 use_zerocost_card 里已经 hand.erase + discard_pile.append，无需此处再处理
	var player_discarded: Array[CardData] = []
	var boss_discarded: Array[CardData] = []
	var player_kept: Array[CardData] = []
	var boss_kept: Array[CardData] = []

	# 1. 已 Pick 的牌（picks 数组）→ discard，并从 hand 中移除
	for card in player_picks:
		if card != null:
			player.discard_pile.append(card)
			player.hand.erase(card)
			player_discarded.append(card)
	for card in boss_picks:
		if card != null:
			boss.discard_pile.append(card)
			boss.hand.erase(card)
			boss_discarded.append(card)

	# 2. 候选中未被 Pick 的牌 → 保留在 hand（不清不弃）
	# 由于 make_player_pick / make_boss_pick 不动 hand，pick 后 hand 仍含所有未消耗牌；
	# 步骤 1 已把 picks 牌从 hand 移除，剩下的 hand 即未 Pick 的候选 + 已被 zerocost 用掉前已经 erase 过
	# 这里仅采集"留下"的统计用于日志/信号
	for card in player_candidates:
		if card != null and card in player.hand:
			player_kept.append(card)
	for card in boss_candidates:
		if card != null and card in boss.hand:
			boss_kept.append(card)

	player.hand_changed.emit()
	boss.hand_changed.emit()

	# 清空候选/picks（_next_round 也会清，这里早清便于 UI 立刻刷新）
	player_candidates.clear()
	boss_candidates.clear()
	player_picks = [null, null, null, null]
	boss_picks = [null, null, null, null]

	bp_round_cleanup.emit(player_discarded, boss_discarded)
	print("[BP] RoundEnd: pick→弃 player=%d boss=%d ｜ 未 Pick→留 player=%d boss=%d → 推进下回合" % [
		player_discarded.size(), boss_discarded.size(), player_kept.size(), boss_kept.size()
	])

	# 记录历史 + 胜负检查 + 推进下回合（沿用旧 _end_round 的部分语义）
	_record_history_for_round()

	# 触发旧 round_ended 信号（让 scene 的日志/UI 仍能监听）
	round_ended.emit(round_number)

	# 进入下一回合（_next_round 会再次走 BP 路径）
	_next_round()


# ============================================================
# v0.7 BP UI 回调入口（Epic-BP-3/4 用，本 Epic 仅声明）
# ============================================================

## Epic-BP-3：横幅播完后 UI 主动调用此函数推进
## 当前 _start_bp_first_picker 内已有 1.5s timer 兜底，UI 接入后会改为 await UI 完成信号
func confirm_first_picker_banner_done() -> void:
	if current_bp_phase != BPPhase.BP_FIRST_PICKER:
		return
	# 暂留空：当前路径已由内部 timer 推进；UI 落地后这里直接 _start_bp_picking()
	pass
