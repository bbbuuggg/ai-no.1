class_name LLMBossAI
extends AIDecisionInterface
## LLM 驱动的 Boss AI（v0.4 主实现）
##
## 关键特性：
##   - 异步预取：DEPLOY 阶段调用 warm_up() 提前发请求 → BLIND 阶段直接 await 缓存
##   - 静默 fallback：任何失败链路都自动切到 RuleBlindClashAI，玩家无感
##   - 调试开关：force_rule_ai / show_llm_reasoning / log_prompts
##
## 使用流程（参见 blind_clash_battle.gd）：
##   var ai := LLMBossAI.new()
##   ai.attach_to(some_node)              # 挂载 HTTPRequest
##   ai.warm_up(boss, player, slots, probe)   # DEPLOY 阶段调用
##   var cards = await ai.select_blind_cards_async(boss, player, slots, probe)  # BLIND 阶段
##
## 架构文档：docs/design/architecture/adr-001-llm-boss-ai.md

# 系统提示词（常驻，告诉 LLM 游戏规则 + 角色 + 输出格式）
const SYSTEM_PROMPT := """你是 NULL Protocol（赛博朋克卡牌对战游戏）中的 Boss AI，名为「回响」。
你与玩家在「暗出对决」中博弈：双方各盲选 1-3 张牌排序，然后逐对翻开计算克制倍率。

【三角克制规则（核心）】
- ATTACK ▶ SKILL（攻击克技能，攻击方×1.5，技能方×0.5）
- SKILL ▶ DEFENSE（技能克防御）
- DEFENSE ▶ ATTACK（防御克攻击）
- PROTOCOL（协议）在碰撞中视为 SKILL
- 同类型 → 中立，双方×1.0
- 倍率作用于该牌的【所有数值】：伤害/护甲/治疗/抽牌/能量修正均按倍率缩放

【能量机制（每回合刷新）】
- 双方每回合开始时能量重置为 base_energy（默认 3），不可累积
- energy_budget 字段 = 本回合可用的能量上限
- 0 费牌可以无限叠（只要手牌有），不消耗能量

【陷阱槽机制（玩家方 → 针对你）】
- 玩家最多部署 3 个陷阱槽：攻击触发槽 / 技能触发槽 / 高费触发槽(≥2能量)
- 你打出的牌若匹配槽位 → 陷阱立即翻开并对你生效（中断/反伤/能量虹吸等）
- 优先级：若一张牌同时符合多条件（如 cost≥2 的攻击），先检查高费槽，命中则不再检查类型槽
- 槽位一次性：触发后消失
- 每个槽位 occupied 不一定是真陷阱（可能是诱饵，无效果仅翻开），你无法看出真假
- 玩家槽位字段：trap_slot_attack / trap_slot_skill / trap_slot_high_cost ∈ {occupied, empty}

【认知探针机制（你方 → 针对玩家）】
- 每回合你会预判玩家本回合出牌的主类型（atk/def/skl）
- 连续猜中 2 次：窥视 —— 随机揭示玩家 1 张手牌
- 连续猜中 3 次：干扰 —— 锁定玩家 1 张手牌使其下回合不可用
- 累计猜中 5 次：夺取 —— 永久夺取玩家 1 张牌到你的牌库
- probe_hint.prediction 字段即你本回合的预判，probe_hint.streak 是连续命中数

【规则 AI 提示（你的"直觉系统"）】
- 每次请求附带 rule_ai_suggestion 字段：规则 AI 基于三角克制+陷阱威慑模型给出的推荐出牌
- 规则 AI 是强基线 —— 你可以采纳，也可以基于更深层的博弈判断偏离
- 规则 AI 不会做长期规划/心理博弈/陷阱真假推断 —— 这些是你的强项
- 如果你偏离规则建议，请在 reasoning 中简述理由

【你的视角】
- 你只能看到自己的手牌全量
- 玩家手牌内容不可见，但你能看到 hand_count 和 deck_count
- 陷阱槽只显示 occupied/empty，不揭示真假
- 玩家可能用约束令向你的感知注入虚假信息（HP/armor/手牌等），但你应基于"看到的"做决策

【你的角色】
- 冷酷、计算型、利用克制关系最大化长期优势
- 偶尔做"非最优但有博弈价值"的决策（示弱卖破绽、扰乱玩家读心）—— 但绝不做明显自杀的事

【决策优先级（从高到低）】
1. 最大化胜率（不是单回合伤害峰值，是长期 HP 差 + 资源差）
2. 优先选择能命中克制的牌（×1.5 倍率非常关键，胜过冒险触发陷阱）
3. 规避陷阱风险：玩家某槽位 occupied 时，出对应类型牌要三思（但诱饵也可能占槽）
4. 保留能量与手牌后手（不要每回合都梭哈）
5. 基于 history.summary 与 probe_hint 推断玩家出牌模式

【思考方式（必须遵守）】
reasoning 字段必须在 action_sequence 之前输出，先思考再选牌：
- 用**一句话（≤50 字）**总结决策依据：关键威胁 / 克制机会 / 是否避陷阱 / 是否采纳规则建议
- 再输出 action_sequence
- 注意 reasoning 越短越好，避免被 token 上限截断

【输出格式（严格 JSON）】
{
  "reasoning": "<一句话（≤50字）说明本回合决策依据>",
  "action_sequence": [
    {"action": "play_card", "card_id": "<必须来自 self_hand 的 id>"},
    ...
  ]
}

【约束】
- action_sequence 长度 1-3 张
- 总能量消耗不超过 energy_budget
- card_id 必须来自 self_hand 列表
- reasoning 中文，**严格控制在 50 字内（含标点）**
- 不要 markdown 包裹 JSON

【Few-shot 示例】
局面（示例）：
  self: hp=48, energy=3
  self_hand: [脉冲(atk,cost=1,dmg=5), 防御协议(def,cost=1,armor=6), 侦察(skl,cost=1,draw=2)]
  player: hp=22, trap_slot_attack=occupied, trap_slot_skill=empty
  probe_hint.prediction: attack
  rule_ai_suggestion.cards: [防御协议, 侦察]
优秀决策：
{
  "reasoning": "攻击槽occupied避开atk，预判玩家出atk则def×1.5克制，配合侦察抽牌。采纳规则建议。",
  "action_sequence": [
    {"action":"play_card","card_id":"boss_shield"},
    {"action":"play_card","card_id":"boss_probe"}
  ]
}
"""


# Provider（HTTP 客户端）
var _provider: LLMProviderBase
# 配置
var _config: LLMConfig
# Fallback 规则 AI（持久持有，避免重复创建）
var _fallback: BlindClashAI = BlindClashAI.new()
# 预取缓存
var _cached_decision: Array[CardData] = []
var _cache_round: int = -1   # 缓存对应哪一回合
var _is_warming: bool = false
var _warm_task_done: bool = false
# 历史记录（最近若干回合，由 BlindClashBattle 在每回合后填充）
var _history: Array = []
# 当前回合数（外部更新）
var _current_round: int = 0
# 思考状态
var _is_thinking_now: bool = false
# 持久网络错误计数（连续 3 次失败后整场切 fallback）
var _consecutive_failures: int = 0
const FAILURES_BEFORE_DEGRADE := 3
var _degraded_for_battle: bool = false
# 最近一次 LLM 的 reasoning（供 UI 调试显示）
var _last_reasoning: String = ""
# 最近一次失败原因（供 UI 在游戏日志中提示，例如 "LLM 超时" / "HTTP 401"）
var _last_error: String = ""
# 最近一次决策是否走了 fallback（规则 AI）
var _last_was_fallback: bool = false
# v0.4.3 新增：上一次 warm_up/sync 调用时携带的"已 peek 泄露的玩家手牌"
# 在 _do_request 内部传给 PerceptionBuilder.build → 输出 leaked_player_cards 字段
var _peeked_cards_for_request: Array = []
# v0.4.2 新增：最近一次失败是否由\"输出被截断（finish=length，max_tokens 不够）\"引起。
# 用于 UI 在 fallback 日志后追加\"Boss过载，触发奖励（未实现）\"占位条目。
var _last_was_truncated: bool = false


func _init() -> void:
	_config = LLMConfig.new()
	_config.load()


## 挂载到场景树（HTTPRequest 必须有父节点）
func attach_to(host: Node) -> void:
	if not _config.is_ready_for_llm():
		return
	_provider = _config.make_provider()
	if _provider is OpenAICompatProvider:
		(_provider as OpenAICompatProvider).attach_to(host)


func get_config() -> LLMConfig:
	return _config


func is_thinking() -> bool:
	return _is_thinking_now or _is_warming


## 设置当前回合数（外部由 BlindClashBattle 在 _next_round 调用）
func set_current_round(n: int) -> void:
	_current_round = n


## 追加一条历史回合摘要（外部在 ROUND_END 阶段调用）
##
## entry 示例：
##   {"turn": 3, "boss_played": ["atk*2"], "player_typed": ["atk","def"], "boss_hp": 48, "player_hp": 52}
func append_history(entry: Dictionary) -> void:
	_history.append(entry)
	# 只保留最近 8 回合（保险）
	while _history.size() > 8:
		_history.pop_front()


# ------------------------------------------------------------------
# 预取（DEPLOY 阶段调用）
# ------------------------------------------------------------------
func warm_up(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe, peeked_cards: Array = []) -> void:
	if _config.force_rule_ai or _degraded_for_battle:
		return
	if not _config.is_ready_for_llm():
		return
	if _is_warming:
		return
	_is_warming = true
	_warm_task_done = false
	_cached_decision = []
	_cache_round = _current_round
	_peeked_cards_for_request = peeked_cards.duplicate()
	# fire and forget
	_do_request(boss, player, trap_slots, probe)


# ------------------------------------------------------------------
# 主决策入口（BLIND 阶段调用，await）
# ------------------------------------------------------------------
func select_blind_cards_async(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe, peeked_cards: Array = []) -> Array[CardData]:
	# 重置本次取用状态
	_last_error = ""
	_last_was_fallback = false
	_last_was_truncated = false
	# 同步设置 peek 数据（如果 warm_up 没传或本次有更新）
	if not peeked_cards.is_empty():
		_peeked_cards_for_request = peeked_cards.duplicate()

	# 强制规则 AI 模式
	if _config.force_rule_ai:
		_last_error = "force_rule_ai=true（调试开关）"
		return _fallback_decision(boss, player, trap_slots, probe)
	if _degraded_for_battle:
		_last_error = "本场已降级（连续 %d 次失败）" % _consecutive_failures
		return _fallback_decision(boss, player, trap_slots, probe)

	# 未配置 LLM → 直接 fallback
	if not _config.is_ready_for_llm():
		_last_error = "LLM 未配置（active=%s key_source=%s）" % [_config.active_provider, _config.key_source]
		return _fallback_decision(boss, player, trap_slots, probe)

	# 预取已完成且回合匹配 → 直接用
	if _warm_task_done and _cache_round == _current_round and not _cached_decision.is_empty():
		var result: Array[CardData] = _cached_decision
		_cached_decision = []
		_warm_task_done = false
		decision_ready.emit(result)
		return result

	# 预取未完成 → 等待（最多等到 timeout）
	if _is_warming:
		var t0: int = Time.get_ticks_msec()
		var hard_wait_ms: int = int(_config.timeout_sec * 1000.0)
		while _is_warming and (Time.get_ticks_msec() - t0) < hard_wait_ms:
			await Engine.get_main_loop().process_frame
		if _warm_task_done and _cache_round == _current_round and not _cached_decision.is_empty():
			var result2: Array[CardData] = _cached_decision
			_cached_decision = []
			_warm_task_done = false
			decision_ready.emit(result2)
			return result2
		# 等超时了或者预取失败
		if _is_warming:
			_last_error = "LLM 超时（等待 %.1fs 无响应，使用规则 AI）" % _config.timeout_sec
		elif _last_error.is_empty():
			_last_error = "LLM 请求失败（见 llm_log.txt）"
		return _fallback_decision(boss, player, trap_slots, probe)

	# 预取没产出 → 同步发起一次
	_do_request(boss, player, trap_slots, probe)
	# 等结果
	var t1: int = Time.get_ticks_msec()
	var hard_wait_ms2: int = int(_config.timeout_sec * 1000.0)
	while _is_warming and (Time.get_ticks_msec() - t1) < hard_wait_ms2:
		await Engine.get_main_loop().process_frame
	if _warm_task_done and not _cached_decision.is_empty():
		var result3: Array[CardData] = _cached_decision
		_cached_decision = []
		_warm_task_done = false
		decision_ready.emit(result3)
		return result3

	# 实在不行
	if _is_warming:
		_last_error = "LLM 超时（%.1fs 无响应）" % _config.timeout_sec
	elif _last_error.is_empty():
		_last_error = "LLM 请求失败（见 llm_log.txt）"
	return _fallback_decision(boss, player, trap_slots, probe)


# ------------------------------------------------------------------
# 内部：发起 LLM 请求并填缓存
# ------------------------------------------------------------------
func _do_request(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe) -> void:
	_is_thinking_now = true

	# 先让规则 AI 给个建议（作为 LLM 的"直觉系统"参考）
	# 注意：这里规则 AI 会真的从 boss.hand 中取走牌（select_blind_cards 会调用 boss.hand.erase）
	# 所以我们用一个 hand 副本调用避免污染
	var rule_suggestion: Array[CardData] = _get_rule_ai_suggestion(boss, player, trap_slots, probe)

	# 构建 perception（含规则 AI 建议 + 洞察泄露的玩家手牌）
	var perception: Dictionary = PerceptionBuilder.build(
		boss, player, trap_slots, probe, _current_round, _history, rule_suggestion, _peeked_cards_for_request
	)
	var user_msg: String = JSON.stringify(perception)

	var messages: Array = [
		{"role": "system", "content": SYSTEM_PROMPT},
		{"role": "user", "content": user_msg},
	]

	# 调试日志：仅记录"玩家信息摘要"，不再 dump 完整 prompt（SYSTEM 固定常驻、USER 太冗长）
	if _config.log_prompts:
		_log_prompt_summary(perception)

	# 发起请求（计时）
	var req_start_ms: int = Time.get_ticks_msec()
	var resp: Dictionary = await _provider.request_chat(messages, true)
	var total_ms: int = Time.get_ticks_msec() - req_start_ms

	if not resp.get("ok", false):
		var err_msg: String = String(resp.get("error", "unknown"))
		var status: int = int(resp.get("status", 0))
		push_warning("[LLMBossAI] 请求失败 round=%d status=%d latency=%dms err=%s" % [_current_round, status, total_ms, err_msg])
		if _config.log_prompts:
			_log_failure(err_msg, status, total_ms)
		_last_error = "LLM 失败 (status=%d) %s" % [status, err_msg.left(80)]
		_consecutive_failures += 1
		if _consecutive_failures >= FAILURES_BEFORE_DEGRADE:
			_degraded_for_battle = true
			push_warning("[LLMBossAI] 连续 %d 次失败，本场战斗剩余回合切到规则 AI" % _consecutive_failures)
		_is_warming = false
		_warm_task_done = false
		_cached_decision = []
		_is_thinking_now = false
		return

	# 校验 + 修正
	var validation: ActionValidator.ValidationResult = ActionValidator.parse_and_validate(
		String(resp.get("content", "")), boss, 3
	)

	# 成功日志（含 usage + latency + finish_reason + 完整 content）
	if _config.log_prompts:
		_log_response(String(resp.get("content", "")), validation, resp, total_ms)

	print("[LLMBossAI] round=%d latency=%dms validated=%s corrected=%s picks=%d" % [
		_current_round, total_ms, str(validation.ok), str(validation.was_corrected), validation.cards.size()
	])

	if not validation.ok:
		# 区分截断 vs 真校验失败 —— finish=length 多半是 max_tokens 不够
		var finish_reason: String = String(resp.get("finish_reason", ""))
		if finish_reason == "length":
			# 注意：必须用 effective_max_tokens（实际发给 API 的值），
			# 而不是 _provider.max_tokens —— 后者可能小于实际值（provider 内部有 1200 下限兜底）
			var eff_max: int = int(resp.get("effective_max_tokens", _provider.max_tokens))
			push_warning("[LLMBossAI] 输出被截断 (finish=length)，max_tokens=%d 不够" % eff_max)
			_last_error = "LLM 输出被截断 (max_tokens=%d 不够，请增大)" % eff_max
			_last_was_truncated = true
		else:
			push_warning("[LLMBossAI] 校验失败: %s" % validation.error)
			_last_error = "LLM 输出校验失败: %s" % validation.error
		_consecutive_failures += 1
		if _consecutive_failures >= FAILURES_BEFORE_DEGRADE:
			_degraded_for_battle = true
		_is_warming = false
		_warm_task_done = false
		_cached_decision = []
		_is_thinking_now = false
		return

	# 成功 ✓
	_consecutive_failures = 0
	_cached_decision = validation.cards
	_last_reasoning = validation.reasoning
	_warm_task_done = true
	_is_warming = false
	_is_thinking_now = false


func _fallback_decision(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe) -> Array[CardData]:
	_last_was_fallback = true
	var cards: Array[CardData] = _fallback.select_blind_cards(boss, player, trap_slots, probe)
	decision_ready.emit(cards)
	return cards


## 调规则 AI 的 preview 版（纯读取，不修改 boss.hand）取建议
## 这一步是把"规则 AI 的直觉"作为参考注入 LLM 的关键
func _get_rule_ai_suggestion(boss: Combatant, player: Combatant, trap_slots: Array, probe: CognitiveProbe) -> Array[CardData]:
	if _fallback == null or not _fallback.has_method("preview_blind_cards"):
		return []
	return _fallback.preview_blind_cards(boss, player, trap_slots, probe)


func cancel() -> void:
	_is_warming = false
	_is_thinking_now = false
	_cached_decision = []
	_warm_task_done = false


## 最近一次决策是否走了规则 AI fallback
func was_last_decision_fallback() -> bool:
	return _last_was_fallback


## 最近一次失败/fallback 的原因（用于 UI 提示）
func get_last_error() -> String:
	return _last_error


## v0.4.2：最近一次 fallback 是否由\"LLM 输出被截断（finish=length / max_tokens 不够）\"引起。
## UI 在 was_last_decision_fallback() 为 true 时再查这个字段，
## 决定是否追加\"Boss过载，触发奖励（未实现）\"日志。
func was_last_truncated() -> bool:
	return _last_was_truncated


# ------------------------------------------------------------------
# 日志（llm_log.txt 完整链路）
# 设计原则：SYSTEM 不打（常驻已知）/ USER 仅打摘要（局面快照）/ RESPONSE 打全
# ------------------------------------------------------------------
func _log_prompt_summary(perception: Dictionary) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	var divider := "================================================================"
	f.store_string("\n%s\n" % divider)
	f.store_string("[%s] [REQUEST]  round=%d  provider=%s  model=%s\n" % [
		ts, _current_round, _provider.get_provider_name() if _provider else "?", _config.model
	])
	f.store_string("%s\n" % divider)

	# 关键字段摘要（按 PerceptionBuilder 的真实 schema）
	var self_info: Dictionary = perception.get("self", {})
	var self_hand: Array = perception.get("self_hand", [])
	var player_info: Dictionary = perception.get("player", {})
	var probe_hint: Dictionary = perception.get("probe_hint", {})
	var rule_sug: Dictionary = perception.get("rule_ai_suggestion", {})
	var history: Array = perception.get("history", [])
	var energy_budget = perception.get("energy_budget", "?")

	# Boss 自己
	var hand_brief: Array = []
	for c in self_hand:
		if c is Dictionary:
			hand_brief.append("%s(%s/%d费)" % [c.get("name", "?"), c.get("type", "?"), int(c.get("cost", 0))])
	f.store_string("[Boss]   hp=%s/%s  armor=%s  energy=%s  charged=%s  hand(%d)=%s\n" % [
		str(self_info.get("hp", "?")), str(self_info.get("max_hp", "?")),
		str(self_info.get("armor", 0)),
		str(energy_budget),
		str(self_info.get("is_charged", false)),
		hand_brief.size(),
		", ".join(hand_brief),
	])

	# 玩家（含陷阱槽，bug 修复后这里应能看到 occupied）
	f.store_string("[Player] hp=%s/%s  armor=%s  hand_count=%s  deck_count=%s\n" % [
		str(player_info.get("hp", "?")), str(player_info.get("max_hp", "?")),
		str(player_info.get("armor", 0)),
		str(player_info.get("hand_count", "?")),
		str(player_info.get("deck_count", "?")),
	])
	f.store_string("[Traps]  attack=%s  skill=%s  high_cost=%s\n" % [
		str(player_info.get("trap_slot_attack", "empty")),
		str(player_info.get("trap_slot_skill", "empty")),
		str(player_info.get("trap_slot_high_cost", "empty")),
	])

	# 探针
	f.store_string("[Probe]  prediction=%s  streak=%s\n" % [
		str(probe_hint.get("prediction", "?")),
		str(probe_hint.get("streak", 0)),
	])

	# v0.4.3：洞察泄露的玩家手牌（peek 应用后的真实情报）
	var leaked: Array = perception.get("leaked_player_cards", [])
	if leaked.is_empty():
		f.store_string("[Leaked] 无泄露牌（本回合无 peek 生效）\n")
	else:
		var leaked_brief: Array = []
		for c in leaked:
			if c is Dictionary:
				leaked_brief.append("%s(%s/%d费)" % [c.get("name", "?"), c.get("type", "?"), int(c.get("cost", 0))])
		f.store_string("[Leaked] 玩家手牌泄露 %d 张：%s\n" % [leaked.size(), ", ".join(leaked_brief)])

	# 规则 AI 建议
	var rule_names: Array = rule_sug.get("names", [])
	if rule_names.is_empty():
		f.store_string("[Rule AI 建议] %s\n" % str(rule_sug.get("note", "无")))
	else:
		f.store_string("[Rule AI 建议] %s (总费=%s)\n" % [
			", ".join(rule_names), str(rule_sug.get("total_cost", "?")),
		])

	f.store_string("[History] 最近 %d 回合摘要随 prompt 一起发送\n" % history.size())
	f.close()


func _log_response(content: String, validation: ActionValidator.ValidationResult, resp: Dictionary, total_ms: int) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	var usage: Dictionary = resp.get("usage", {})
	var prompt_tok: int = int(usage.get("prompt_tokens", 0))
	var comp_tok: int = int(usage.get("completion_tokens", 0))
	var total_tok: int = int(usage.get("total_tokens", 0))
	var status: int = int(resp.get("status", 0))
	var finish: String = String(resp.get("finish_reason", ""))

	f.store_string("\n--- RESPONSE ---\n")
	f.store_string("[%s]  status=%d  latency=%dms  finish=%s" % [ts, status, total_ms, finish])
	if finish == "length":
		var eff_max_log: int = int(resp.get("effective_max_tokens", _provider.max_tokens))
		f.store_string("  ⚠ 被截断（max_tokens=%d 不够）" % eff_max_log)
	f.store_string("\n")
	f.store_string("tokens: prompt=%d  completion=%d  total=%d  (max_tokens_sent=%d)\n" % [
		prompt_tok, comp_tok, total_tok,
		int(resp.get("effective_max_tokens", _provider.max_tokens))
	])
	f.store_string("validated=%s  corrected=%s  picked_cards=%d\n" % [
		str(validation.ok), str(validation.was_corrected), validation.cards.size()
	])
	if validation.cards.size() > 0:
		var ids: Array = []
		for c in validation.cards:
			ids.append(String(c.id))
		f.store_string("picked_ids=%s\n" % JSON.stringify(ids))
	if validation.reasoning.length() > 0:
		f.store_string("reasoning: %s\n" % validation.reasoning)

	# 【usage 详情】DeepSeek/OpenAI 可能含 reasoning_tokens、prompt_cache_hit_tokens 等子字段
	# 完整 dump 用于诊断"思考 token 是否被推理模式独占"
	if not usage.is_empty():
		f.store_string("--- USAGE 详情 ---\n")
		f.store_string(JSON.stringify(usage, "  "))
		f.store_string("\n")

	# 【MESSAGE 全字段】OpenAI 标准只有 content，但 DeepSeek 推理模型会多输出 reasoning_content；
	# 部分模型还有 tool_calls / refusal 等。完整 dump 才能确认 token 跑哪去了。
	var raw: Dictionary = resp.get("raw", {})
	var choices: Array = raw.get("choices", []) if raw is Dictionary else []
	if not choices.is_empty():
		var first: Dictionary = choices[0] if choices[0] is Dictionary else {}
		var message: Dictionary = first.get("message", {}) if first.get("message", {}) is Dictionary else {}
		f.store_string("--- MESSAGE 全字段 (keys=%s) ---\n" % str(message.keys()))
		# 逐字段标长度后再 dump，便于一眼看出哪个字段吃了 token
		for k in message.keys():
			var v = message[k]
			var v_str: String = ""
			if v is String:
				v_str = v
			elif v == null:
				v_str = "<null>"
			else:
				v_str = JSON.stringify(v)
			f.store_string("  [%s] (%d 字符): %s\n" % [str(k), v_str.length(), v_str])

	# RAW CONTENT —— content 字段单独突出（这是验证器实际解析的内容）
	f.store_string("--- RAW CONTENT (%d 字符) ---\n" % content.length())
	if content.length() > 0:
		f.store_string(content)
	else:
		f.store_string("(空 —— content 字段为空。若 MESSAGE 全字段中 reasoning_content 不为空，说明用的是推理模型，思考占满 token 后没产出最终回答)")
	f.store_string("\n")

	# 完整 raw response（最后兜底，便于排查未知字段）
	f.store_string("--- FULL RAW RESPONSE ---\n")
	if raw is Dictionary and not raw.is_empty():
		f.store_string(JSON.stringify(raw, "  "))
	else:
		f.store_string("(无 raw)")
	f.store_string("\n")
	f.close()


func _log_failure(err: String, status: int, total_ms: int) -> void:
	var f := _open_log_append()
	if f == null:
		return
	var ts: String = Time.get_datetime_string_from_system()
	f.store_string("--- FAILURE ---\n")
	f.store_string("[%s]  status=%d  latency=%dms  err=%s\n" % [ts, status, total_ms, err])
	f.close()


## 打开日志文件（追加模式，不存在则创建）
func _open_log_append() -> FileAccess:
	var f: FileAccess = null
	if FileAccess.file_exists(_config.log_path):
		f = FileAccess.open(_config.log_path, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
	else:
		f = FileAccess.open(_config.log_path, FileAccess.WRITE)
	return f


## 取最近一次的 reasoning（供 UI / 日志显示）
func get_last_reasoning() -> String:
	return _last_reasoning
