class_name PerceptionBuilder
extends RefCounted
## 把游戏状态打包为紧凑 JSON，供 LLM 决策使用
##
## 设计原则（由 game-designer 定调）：
##   - Boss 视角真实：可以看到玩家陷阱"占位/空"，但不能看真假；
##                    不能看玩家手牌内容（仅张数 + 历史推断）
##   - Token 节俭：紧凑 key 名，最近 3 回合历史足够
##   - 决策必须信息齐全：手牌全量 + 牌库类型计数 + 当前能量/血量/护甲
##
## ★★ 信息对称契约（v0.5.0-beta / Sprint 2 锁定，game-designer + ux-lead 双签）★★
## 本 PerceptionBuilder 暴露给 Boss LLM 的"玩家信息"必须 ⊆ 玩家通过 B 浮层能看到的"Boss 信息"。
## 镜像表（修改前请重读 GDD 04 信息对称章节）：
##
##   B 浮层（玩家可见）         vs.   Boss 视角（_build_player_view）
##   --------------------------------------------------------------
##   boss_panel.HP/Armor/Energy  ←→   player.hp/armor/energy            ✓
##   🂠×N 手牌徽章                ←→   player.hand_count                 ✓
##   DRAW 区类型分布横条          ←→   player.deck_count（仅总数，无分布） ✓ 玩家信息略多（已知 boss 分布）
##   DEPLOYED 区缩略条            ←→   history.player_typed              ✓
##   陷阱槽 占位/空              ←→   player.trap_slot_*                ✓
##                              （任何一方都不知对方真假/类型）
##   peek 洞察后曝光的对方手牌    ←→   leaked_player_cards               ✓ 双向对称（机制内合法泄露）
##
## ⚠ 修改 _build_player_view 之前，必须 review 是否破坏上表。
## ⚠ 严禁向 _build_player_view 添加：player.hand 内容、player.deck 类型分布、陷阱真假。
##
## 输出 schema 示例（v0.6.0 起：element + polarity 双维度）：
## {
##   "self": {"hp":48, "armor":0, "energy":3, "deck_count":12, "discard_count":4,
##            "deck_type_counts":{"atk":3,"def":2,"skl":4,"pro":3},
##            "deck_element_counts":{"fire":4,"water":4,"wood":4,"none":0},
##            "deck_polarity_counts":{"light":6,"dark":6,"none":0}},
##   "self_hand": [
##     {"id":"b_fire_echo", "name":"回响焰", "type":"atk", "element":"fire", "polarity":"dark",
##      "cost":1, "dmg":5, "desc":"造成5伤害"}
##   ],
##   "player": {"hp":52, "armor":2, "energy":6, "hand_count":4,
##              "trap_slot_attack":"occupied", "trap_slot_skill":"empty", "trap_slot_high_cost":"empty"},
##   "history": [
##     {"turn":3, "boss_played":["atk×2"], "player_typed":["atk","def"], "result":"draw"}
##   ],
##   "rules_summary": "克制(主)：火克木 / 木克水 / 水克火 → 命中×1.5 被克×1.0 满数值；玩家方 4 张正好 2 光 2 暗 → 每张牌伤害/护甲/治疗各 +1",
##   "round": 4,
##   "energy_budget": 6,
##   "max_picks": 3
## }
##
## ⚠ 字段语义（v0.6.0 / ADR-002）：
##   - element ∈ {"fire","water","wood","none"} —— 决定克制倍率主维度
##   - polarity ∈ {"light","dark","none"} —— 决定 2:2 平衡协同（仅玩家方 4 张全部锁定后判定）
##   - type 仅作"角色定位"语义 + 陷阱触发槽位匹配（不再是克制判定的主维度）
##   - element=NONE 的牌：碰撞视为中立（不参与元素克制）

const TYPE_SHORT := {
	CardData.CardType.ATTACK: "atk",
	CardData.CardType.DEFENSE: "def",
	CardData.CardType.SKILL: "skl",
	CardData.CardType.PROTOCOL: "pro",
}

## v0.6.0：元素短码（与 ElementHelper.element_short 保持一致）
const ELEMENT_SHORT := {
	CardData.Element.NONE: "none",
	CardData.Element.FIRE: "fire",
	CardData.Element.WATER: "water",
	CardData.Element.WOOD: "wood",
}

## v0.6.0：光暗极性短码
const POLARITY_SHORT := {
	CardData.Polarity.NONE: "none",
	CardData.Polarity.LIGHT: "light",
	CardData.Polarity.DARK: "dark",
}

## 克制规则一句话提示（喂给 LLM 当作 system prompt 的"在线版"补强）
## 任何修改请同步 llm_boss_ai.gd 的两个 SYSTEM_PROMPT
const _RULES_SUMMARY := "克制仅在同slot对位之间判定(你slot1只vs玩家slot1);克制链单向闭环：火→木→水→火(火克木/木克水/水克火)→命中×1.5被克×1.0(v0.9.4 v5：被克方满数值不再×0.5减半,克制是单边奖励);⚠反向必错:不存在'水克木/木克火/火克水';协同：玩家方4张正好2光2暗→玩家每张牌结算时非零字段(伤害/护甲/治疗)在倍率后+1;治疗满血=0(不溢出不保留);倍率作用于该牌全部数值（伤害/护甲/治疗/抽牌/能量）;毫无阻力:某slot一方出牌对方无能量跳过(对位为空)→出牌方全部效果×2;蛇形出牌(Snake Draft):偶数slot先手方先出奇数slot后手方先出→先手信息优劣势2:2平衡"


## 主入口：构建一份感知
##
## @param boss               Boss Combatant
## @param player             玩家 Combatant
## @param trap_slots         陷阱槽位 [TrapData|null]×3
## @param probe              认知探针
## @param round_number       当前回合数
## @param history            最近 3 回合的简要记录（含 summary 自然语言）
## @param rule_suggestion    规则 AI 的推荐牌组（Array[CardData]）+ 推荐理由
## @param peeked_cards       已被 peek 洞察泄露的玩家手牌 [CardData]（v0.4.3 起）
## @return                   Dictionary，可直接 JSON.stringify
static func build(
	boss: Combatant,
	player: Combatant,
	trap_slots: Array,
	probe: CognitiveProbe,
	round_number: int,
	history: Array,
	rule_suggestion: Array = [],
	peeked_cards: Array = [],
	progression: Dictionary = {}
) -> Dictionary:
	return {
		"self": _build_self(boss),
		"self_hand": _build_hand_full(boss),
		"player": _build_player_view(player, trap_slots),
		"history": _trim_history(history, 3),
		"probe_hint": {
			"prediction": probe.current_prediction if probe else "",
			"streak": probe.consecutive_hits if probe else 0,
		},
		"rule_ai_suggestion": _build_rule_suggestion(rule_suggestion),
		"leaked_player_cards": _build_leaked_cards(peeked_cards),
		"progression": _build_progression(progression),
		"rules_summary": _RULES_SUMMARY,
		"round": round_number,
		"energy_budget": boss.energy,
		"max_picks": 3,
	}


## 构建 current_slot_matchup：直接告诉 LLM 当前 slot 的对位对手是谁
## 这是解决"LLM 误读跨 slot 元素做克制判断"的结构性方案：
## LLM 不需要从 player_picks 数组中自行查找当前 slot → 消除跨 slot 误判根因
static func _build_current_slot_matchup(player_picks: Array, current_slot: int) -> Dictionary:
	var opponent_card = null
	if current_slot < player_picks.size():
		opponent_card = player_picks[current_slot]
	if opponent_card != null and opponent_card is CardData:
		return {
			"slot": current_slot + 1,
			"opponent_locked": true,
			"opponent_element": ELEMENT_SHORT.get(opponent_card.element, "none"),
			"opponent_polarity": POLARITY_SHORT.get(opponent_card.polarity, "none"),
			"opponent_cost": opponent_card.energy_cost,
			"note": "你的 slot %d 只与对手的 slot %d 对位结算，不看其他 slot" % [current_slot + 1, current_slot + 1],
		}
	return {
		"slot": current_slot + 1,
		"opponent_locked": false,
		"opponent_element": null,
		"opponent_polarity": null,
		"note": "对手 slot %d 尚未锁定，你无法确定对位元素；请从 player_candidates 预判" % [current_slot + 1],
	}


## 已被 peek 洞察泄露的玩家手牌（Boss "看到底牌"的真实信息）
## 仅在洞察生效时有内容；空数组表示没有泄露
static func _build_leaked_cards(cards: Array) -> Array:
	var arr: Array = []
	for c in cards:
		if c is CardData:
			arr.append({
				"id": String(c.id),
				"name": c.card_name,
				"type": TYPE_SHORT.get(c.type, "skl"),
				"element": ELEMENT_SHORT.get(c.element, "none"),
				"polarity": POLARITY_SHORT.get(c.polarity, "none"),
				"cost": c.energy_cost,
				"dmg": c.damage,
				"hits": c.hits,
				"armor": c.armor,
				"heal": c.heal,
				"note": "玩家手牌（由认知洞察泄露，可信）",
			})
	return arr


## 规则 AI 建议压缩成简短 JSON
static func _build_rule_suggestion(cards: Array) -> Dictionary:
	if cards.is_empty():
		return {"cards": [], "note": "规则AI无建议"}
	var ids: Array = []
	var names: Array = []
	var total_cost: int = 0
	for c in cards:
		if c is CardData:
			ids.append(String(c.id))
			names.append(c.card_name)
			total_cost += c.energy_cost
	return {
		"cards": ids,
		"names": names,
		"total_cost": total_cost,
		"note": "规则 AI 基于火/水/木 3-cycle 克制 + 2:2 光暗平衡 + 陷阱威慑给出的推荐。你可以采纳或偏离。",
	}


## 自己侧（不含手牌明细，由 self_hand 单独给）
static func _build_self(boss: Combatant) -> Dictionary:
	var deck_type_counts := {"atk": 0, "def": 0, "skl": 0, "pro": 0}
	var deck_element_counts := {"fire": 0, "water": 0, "wood": 0, "none": 0}
	var deck_polarity_counts := {"light": 0, "dark": 0, "none": 0}
	for c in boss.deck:
		var tkey: String = TYPE_SHORT.get(c.type, "skl")
		deck_type_counts[tkey] += 1
		var ekey: String = ELEMENT_SHORT.get(c.element, "none")
		deck_element_counts[ekey] += 1
		var pkey: String = POLARITY_SHORT.get(c.polarity, "none")
		deck_polarity_counts[pkey] += 1
	return {
		"hp": boss.hp,
		"max_hp": boss.max_hp,
		"armor": boss.armor,
		"energy": boss.energy,
		"base_energy": boss.base_energy,  # v0.8.3：随关卡膨胀（R1=6, R5=10），LLM 必须读这个字段而非假设固定 6
		"is_charged": boss.is_charged,
		"deck_count": boss.deck.size(),
		"discard_count": boss.discard_pile.size(),
		"deck_type_counts": deck_type_counts,
		"deck_element_counts": deck_element_counts,
		"deck_polarity_counts": deck_polarity_counts,
		"hand_size": boss.hand.size(),
	}


## Boss 自己的手牌（完整，决策必需）
static func _build_hand_full(boss: Combatant) -> Array:
	var arr: Array = []
	for c in boss.hand:
		arr.append({
			"id": String(c.id),
			"name": c.card_name,
			"type": TYPE_SHORT.get(c.type, "skl"),
			"element": ELEMENT_SHORT.get(c.element, "none"),
			"polarity": POLARITY_SHORT.get(c.polarity, "none"),
			"cost": c.energy_cost,
			"dmg": c.damage,
			"hits": c.hits,
			"armor": c.armor,
			"heal": c.heal,
			"draw": c.draw_cards,
			"enemy_draw_mod": c.enemy_draw_modifier,
			"enemy_energy_mod": c.enemy_energy_modifier,
			"ignore_armor": c.ignore_armor,
			"requires_charge": c.requires_charge,
			"grants_charge": c.grants_charge,
			"all_atk_bonus": c.all_attack_bonus,
			"desc": c.description,
		})
	return arr


## 对方（玩家）视角 —— 不能看牌
## ⚠ 信息对称契约：本函数返回的字段必须 ⊆ 玩家 B 浮层可见集合（详见文件头镜像表）
## ⚠ 严禁添加：玩家手牌内容 / 玩家牌库类型分布 / 陷阱真假
static func _build_player_view(player: Combatant, trap_slots: Array) -> Dictionary:
	# 陷阱槽：仅暴露占位/空，不揭示真假（与人类对手对称）
	var slot_a: String = "occupied" if trap_slots.size() > 0 and trap_slots[0] != null else "empty"
	var slot_s: String = "occupied" if trap_slots.size() > 1 and trap_slots[1] != null else "empty"
	var slot_h: String = "occupied" if trap_slots.size() > 2 and trap_slots[2] != null else "empty"
	return {
		"hp": player.hp,
		"max_hp": player.max_hp,
		"armor": player.armor,
		"energy": player.energy,
		"hand_count": player.hand.size(),
		"deck_count": player.deck.size(),
		"discard_count": player.discard_pile.size(),
		"trap_slot_attack": slot_a,
		"trap_slot_skill": slot_s,
		"trap_slot_high_cost": slot_h,
	}


## 取最近 N 回合
static func _trim_history(history: Array, n: int) -> Array:
	if history.size() <= n:
		return history
	return history.slice(history.size() - n)


# ------------------------------------------------------------------
# 信息对称校验（运维 / 单测 用）
# ------------------------------------------------------------------
# ------------------------------------------------------------------
# v0.7.0-alpha BP 单 Slot Pick 感知（Epic-BP-5）
# ------------------------------------------------------------------
## BP 模式下"逐 slot 决策"的紧凑感知。
##
## 与 build() 的差异：
##   - 不暴露 self_hand（手牌已变形为 self_candidates 4 张）
##   - 暴露双方候选 4 张（Q-BP-1 完全可见 → 玩家候选对 Boss 可见）
##   - 暴露当前激活 slot + 已锁的双方 picks（让 LLM 看到自己/玩家已在前序 slot 锁定的牌）
##   - 不带 history（BP 单回合内 4 次 pick，历史负担放回合后的 select 不同）—— 仍带最近 1 回合摘要做长期记忆
##   - 不带 probe_hint / leaked_cards（BP 第一版剥离这些机制，v0.7.x 再补；当前 BP 模式下二者均为空）
##
## @param boss               Boss Combatant（当前能量已扣除前序 slot 的 cost）
## @param player             玩家 Combatant
## @param boss_candidates    Boss 候选 4 张（已 Pick 的位为 null）
## @param player_candidates  玩家候选 4 张（已 Pick 的位为 null，Q-BP-1 完全可见）
## @param boss_picks         Boss 已锁定的 4 个 slot（数组长度 4，未锁为 null）
## @param player_picks       玩家已锁定的 4 个 slot
## @param current_slot       当前要决策的 slot（0~3）
## @param round_number       当前回合数
## @param history            最近回合摘要（v0.7.0-alpha 仅取最近 1 条用于长期记忆）
## @param rule_suggestion    规则 AI 对当前 slot 的推荐 [CardData]（长度 1）
## @return                   Dictionary，可直接 JSON.stringify
static func build_for_slot_pick(
	boss: Combatant,
	player: Combatant,
	boss_candidates: Array,
	player_candidates: Array,
	boss_picks: Array,
	player_picks: Array,
	current_slot: int,
	round_number: int,
	history: Array = [],
	rule_suggestion: Array = [],
	first_picker: String = "",
	progression: Dictionary = {}
) -> Dictionary:
	# 计算剩余 slot 数 + 平均能量预算（与 _boss_rule_pick 对称）
	var slots_left: int = 4 - current_slot
	var avg_budget: int = boss.energy / max(slots_left, 1)
	# 构建 current_slot_matchup：直接告知 LLM 当前 slot 的对位对手信息
	# 目的：避免 LLM 从 player_picks 中自行查找时误读跨 slot 元素做克制判断
	var matchup: Dictionary = _build_current_slot_matchup(player_picks, current_slot)
	# 蛇形出牌：当前 slot 的先出方
	var slot_leader: String = _get_slot_leader(current_slot, first_picker)

	# v0.8.2 方案 D-1：构建带"前瞻预算"派生字段的候选数组
	# 每张未 Pick 的候选追加：energy_after_if_pick / slots_left_after / affordable_for_remaining
	# v0.9.0：升级为"关系陈述视图"——杜绝 LLM 推理克制方向，给硬关系字段
	var self_candidates_view: Array = _build_candidates_with_budget_outlook(
		boss_candidates, current_slot, boss.energy
	)
	# 收集玩家未锁候选（用于 relation view + future slots view + threat profile）
	var player_unlocked: Array = _collect_player_unlocked(player_candidates, player_picks)

	# 关系陈述视图（每张候选）：
	#   - vs_current_opponent.my_actual_damage （当前 slot 对位精确伤害）
	#   - counters_elements / countered_by_elements / neutral_against / relation_summary
	#   - vs_each_player_pick_candidate （后续 slot 风险预览）
	_inject_relation_view(self_candidates_view, matchup, boss_candidates,
						   player_candidates, player_picks)

	# 全局视图（候选内）：
	#   - if_i_pick_this_now.uncovered_player_cards （选这张后我剩余池能罩谁）
	#   slot 4 跳过（后面没 slot）
	_inject_future_slots_view(self_candidates_view, current_slot, boss_candidates, player_unlocked)

	# 顶层威胁档位：玩家每张未锁候选的"中性/被克/克我"三档伤害
	var threat_profile: Array = _build_player_unlocked_threat_profile(player_unlocked)

	# v0.9.1：预结算前 N 个已锁 slot，得出当前 slot 翻盅时的真实 HP/护甲
	# 解决 LLM 在 slot 4 决策治疗时\"看 self.hp 仍满血\"的盲点
	var sim: Dictionary = _simulate_locked_slots_outcome(
		boss_picks, player_picks, current_slot,
		boss.hp, boss.max_hp, boss.armor,
		player.hp, player.max_hp, player.armor
	)
	var hp_before_current: int = int(sim.get("self_hp", boss.hp))
	var armor_before_current: int = int(sim.get("self_armor", boss.armor))
	var p_hp_before_current: int = int(sim.get("player_hp", player.hp))
	var p_armor_before_current: int = int(sim.get("player_armor", player.armor))
	var room_for_heal: int = maxi(boss.max_hp - hp_before_current, 0)
	var pre_slot_outlook: Dictionary = {
		"locked_slots_count": current_slot,
		"current_slot_index": current_slot,
		"self_hp_before_current_slot": hp_before_current,
		"self_armor_before_current_slot": armor_before_current,
		"self_hp_room_for_heal": room_for_heal,
		"player_hp_before_current_slot": p_hp_before_current,
		"details": sim.get("details", []),
		"summary": _build_pre_slot_summary(boss.hp, hp_before_current, player.hp, p_hp_before_current, current_slot),
	}

	# v0.9.1：把 pre_slot 的 hp_room_for_heal 注入每张候选的 vs_current_opponent
	# 让 LLM 直接看到"我这张治疗牌的真实有效收益"（已 clamp）
	_enrich_candidates_with_pre_slot(
		self_candidates_view, hp_before_current, armor_before_current,
		boss.max_hp, p_hp_before_current, player.max_hp
	)

	# 当前 slot 对位玩家牌的"威胁估值"（用于 LLM 判断是否值得 skip）
	var opponent_threat: int = _compute_opponent_threat(matchup, player_picks, current_slot)
	# Skip 战术合法性提示（恒为 true，但显式给 LLM 信号）
	var skip_legal: bool = true

	# v0.9.2：self / player 的 hp+armor 直接用模拟后的预测值
	# 让 LLM 看到的就是\"slot N 翻盅时\"的真相，无需再去对比 pre_slot_outlook
	# v0.9.3：删除 hp_displayed 字段（实测 LLM 看到两份 HP 仍会误信 displayed → 退化为\"满血\"幻觉）
	var self_dict: Dictionary = _build_self(boss)
	self_dict["hp"] = hp_before_current
	self_dict["armor"] = armor_before_current

	var player_dict: Dictionary = _build_player_view(player, [])  # BP 路径下 trap_slots 永远空
	player_dict["hp"] = p_hp_before_current
	player_dict["armor"] = p_armor_before_current

	return {
		"mode": "bp_slot_pick",
		"self": self_dict,
		"self_candidates": self_candidates_view,
		"self_picks": _build_picks_summary(boss_picks),
		"player": player_dict,
		"player_candidates": _build_candidates(player_candidates),
		"player_picks": _build_picks_summary(player_picks),
		"current_slot_matchup": matchup,
		"current_slot": current_slot,                  # 0~3
		"current_slot_human": current_slot + 1,        # 1~4 给 LLM 看
		"slot_leader": slot_leader,                    # 当前 slot 谁先出
		"slot_leader_is_self": slot_leader == "boss",  # 你是否是先出方
		"first_picker": first_picker,                  # 回合先手方
		"slots_total": 4,
		"slots_left_including_current": slots_left,
		"energy_remaining": boss.energy,
		"avg_energy_budget_per_slot": avg_budget,
		# v0.8.2 方案 D-1 新增：留空合法性 + 对位威胁估值
		"skip_is_legal": skip_legal,
		"opponent_locked_threat": opponent_threat,
		# v0.9.0 新增：玩家未锁候选三档伤害陈述（顶层）
		"player_unlocked_threat_profile": threat_profile,
		# v0.9.1 新增：前 N slot 翻盅后的预测 HP（治疗有效空间核心字段）
		"pre_slot_outlook": pre_slot_outlook,
		"rule_ai_suggestion": _build_rule_suggestion(rule_suggestion),
		"progression": _build_progression(progression),
		"rules_summary": _RULES_SUMMARY,
		"history": _trim_history(history, 1),
		"round": round_number,
	}


## v0.8.2 方案 D-1：候选构造器 +"前瞻预算"派生字段
## 给每张未 Pick 候选追加：
##   - energy_after_if_pick: 选这张后 Boss 剩余能量
##   - slots_left_after: 选这张后剩余 slot 数（含 0）
##   - affordable_for_remaining: 选这张后剩余能量是否够后续 slot 各填 1 费保底
## 已 Pick 位仍为 {index, picked:true}
static func _build_candidates_with_budget_outlook(
		cards: Array, current_slot: int, energy_now: int) -> Array:
	var base: Array = _build_candidates(cards)
	var slots_left_after: int = 4 - current_slot - 1  # 选完这张后还剩几个 slot
	for entry in base:
		if entry.get("picked", false):
			continue
		var cost: int = int(entry.get("cost", 0))
		var energy_after: int = energy_now - cost
		# 保底：每个剩余 slot 至少需要 1 费（这是软指标；存在 0 费时仍可填）
		var min_needed: int = slots_left_after
		entry["energy_after_if_pick"] = energy_after
		entry["slots_left_after"] = slots_left_after
		entry["affordable_for_remaining"] = energy_after >= min_needed
	return base


## v0.8.2 方案 D-1：估算当前 slot 对位玩家牌的"威胁度"
## 0=对位空/玩家未锁；1-3=低威胁（小型牌）；4-6=中等；7+=高威胁（不该 skip）
## 公式：dmg + armor*0.7 + cost*1.5（粗略加权）
static func _compute_opponent_threat(matchup: Dictionary, player_picks: Array, current_slot: int) -> int:
	if matchup == null or matchup.is_empty():
		return 0
	if not bool(matchup.get("opponent_locked", false)):
		return 0
	# 从 player_picks 拿原始牌做精确估值（matchup 已脱敏）
	if current_slot < 0 or current_slot >= player_picks.size():
		return 0
	var card = player_picks[current_slot]
	if card == null or not (card is CardData):
		return 0
	var threat: float = 0.0
	threat += card.damage
	threat += card.armor * 0.7
	threat += card.energy_cost * 1.5
	if card.ignore_armor:
		threat += 2.0
	return int(round(threat))


## v0.9.0：候选注入"关系陈述"字段（替代 v0.8.3 扁平 vs_opponent_*）
## 杜绝 LLM 推理克制方向（实测会出现"wood 克 fire"反向幻觉）
## 给每张未 picked 候选注入：
##   - vs_current_opponent: 当前 slot 对位的精确结算（含 my_actual_damage）
##   - counters_elements / countered_by_elements / neutral_against: 静态克制全景
##   - relation_summary: 一行摘要（LLM 复读防错）
##   - vs_each_player_pick_candidate: 玩家未锁候选 → 倍率/伤害（后续 slot 风险预览）
static func _inject_relation_view(candidates: Array, matchup: Dictionary,
		boss_candidates: Array, player_candidates: Array,
		player_picks: Array) -> void:
	# 收集玩家未锁候选（用于 vs_each_player_pick_candidate）
	var player_unlocked: Array = _collect_player_unlocked(player_candidates, player_picks)

	for i in range(candidates.size()):
		var entry: Dictionary = candidates[i]
		if entry.get("picked", false):
			continue
		var self_elem: String = String(entry.get("element", "none"))
		var base_dmg: int = int(entry.get("dmg", 0))

		# === 1. 当前 slot 对位（已锁/未锁两态）===
		entry["vs_current_opponent"] = _build_vs_current_opponent(matchup, self_elem, base_dmg)

		# === 2. 静态克制全景（这张牌克谁、被谁克）===
		var counter_info: Dictionary = _compute_counter_info(self_elem)
		entry["counters_elements"] = counter_info["counters"]
		entry["countered_by_elements"] = counter_info["countered_by"]
		entry["neutral_against"] = counter_info["neutral"]
		entry["relation_summary"] = counter_info["summary"]

		# === 3. vs 玩家每张未锁候选（后续 slot 风险）===
		entry["vs_each_player_pick_candidate"] = _build_vs_each_player_pick(
			self_elem, base_dmg, player_unlocked
		)


## 收集玩家"未锁"候选（已锁的从 player_picks 排除）
static func _collect_player_unlocked(player_candidates: Array, player_picks: Array) -> Array:
	# 收集已锁牌的 id（从 player_picks 中读 .id）
	var locked_ids: Dictionary = {}
	for p in player_picks:
		if p != null and p is CardData:
			locked_ids[String(p.id)] = true

	var unlocked: Array = []
	for c in player_candidates:
		if c == null:
			continue
		if not (c is CardData):
			continue
		if locked_ids.has(String(c.id)):
			continue  # 已锁的不算"未锁候选"
		unlocked.append(c)
	return unlocked


## 计算"克制查表"结果
## 返回 {counters: [...], countered_by: [...], neutral: [...], summary: "克 X；被 Y 克；中性 Z"}
const _COUNTER_CHAIN := {
	"fire":  {"counters": "wood",  "countered_by": "water"},
	"water": {"counters": "fire",  "countered_by": "wood"},
	"wood":  {"counters": "water", "countered_by": "fire"},
}

static func _compute_counter_info(self_elem: String) -> Dictionary:
	if self_elem == "none" or not _COUNTER_CHAIN.has(self_elem):
		return {
			"counters": [],
			"countered_by": [],
			"neutral": ["fire", "water", "wood", "none"],
			"summary": "中性牌：与所有元素均为 ×1.0，无克制关系",
		}
	var info = _COUNTER_CHAIN[self_elem]
	var counters_elem: String = info["counters"]
	var countered_by_elem: String = info["countered_by"]
	return {
		"counters": [{"element": counters_elem, "multiplier": 1.5}],
		"countered_by": [{"element": countered_by_elem, "multiplier": 1.0}],
		"neutral": [self_elem, "none"],
		"summary": "克 %s（×1.5）；被 %s 克（×1.0 满数值，仅克方拿×1.5奖励）；中性 %s" % [
			counters_elem, countered_by_elem, self_elem
		],
	}


## 构建 vs_current_opponent：当前 slot 对位精确结算
static func _build_vs_current_opponent(matchup: Dictionary, self_elem: String, base_dmg: int) -> Dictionary:
	if matchup == null or matchup.is_empty() or not bool(matchup.get("opponent_locked", false)):
		return {
			"locked": false,
			"note": "玩家在此 slot 未锁定，无法精确结算",
		}
	var opp_elem: String = String(matchup.get("opponent_element", "none"))
	var mult: float = _compute_multiplier(self_elem, opp_elem)
	var actual_dmg: int = ClashResolver.apply_multiplier_int(base_dmg, mult)
	var relation: String = _relation_between(self_elem, opp_elem)
	return {
		"locked": true,
		"opponent_element": opp_elem,
		"multiplier": mult,
		"my_base_damage": base_dmg,
		"my_actual_damage": actual_dmg,
		"relation": relation,
	}


## 构建 vs_each_player_pick_candidate：玩家未锁候选 → 我这张的对位结算
static func _build_vs_each_player_pick(self_elem: String, base_dmg: int,
		player_unlocked: Array) -> Array:
	var arr: Array = []
	for p_card in player_unlocked:
		var p_elem: String = ELEMENT_SHORT.get(p_card.element, "none")
		var mult: float = _compute_multiplier(self_elem, p_elem)
		arr.append({
			"candidate_id": String(p_card.id),
			"candidate_element": p_elem,
			"candidate_damage": p_card.damage,
			"if_player_picks_this": {
				"multiplier": mult,
				"my_actual_damage": ClashResolver.apply_multiplier_int(base_dmg, mult),
				"relation": _relation_between(self_elem, p_elem),
			},
		})
	return arr


## 倍率核心查表（counter_map）
static func _compute_multiplier(self_elem: String, opp_elem: String) -> float:
	if self_elem == "none" or opp_elem == "none":
		return 1.0
	var counter_map := {
		"fire":  {"fire": 1.0, "water": 1.0, "wood": 1.5},
		"water": {"fire": 1.5, "water": 1.0, "wood": 1.0},
		"wood":  {"fire": 1.0, "water": 1.5, "wood": 1.0},
	}
	return float(counter_map.get(self_elem, {}).get(opp_elem, 1.0))


## 元素关系枚举（counters / neutral / countered_by）
## v0.9.4 v5：改用双元素直接判定（旧版靠倍率反推，新规则下被克=1.0 与中性=1.0 倍率相同无法区分）
static func _relation_between(self_elem: String, opp_elem: String) -> String:
	# 同元素或任一为 none → 中性
	if self_elem == opp_elem or self_elem == "none" or opp_elem == "none":
		return "neutral"
	# 克制链：火→木→水→火
	# 自己克对手：fire→wood / wood→water / water→fire
	if (self_elem == "fire" and opp_elem == "wood") \
			or (self_elem == "wood" and opp_elem == "water") \
			or (self_elem == "water" and opp_elem == "fire"):
		return "counters"
	# 否则被克
	return "countered_by"


## 旧 API（已弃用，仅保留兼容性以防外部调用）— 在新规则下被克与中性倍率都是 1.0，无法可靠判定
static func _multiplier_to_relation(mult: float) -> String:
	if mult >= 1.5:
		return "counters"
	elif mult <= 0.5:
		return "countered_by"
	return "neutral"


## v0.9.0：构建"玩家未锁候选威胁档位"顶层字段
## 每张玩家未锁候选三档伤害陈述：
##   - dmg_if_i_neutral: 我出中性元素时吃多少
##   - dmg_if_i_countered: 我元素被它克时吃多少
##   - dmg_if_i_counter: 我元素克它时吃多少
static func _build_player_unlocked_threat_profile(player_unlocked: Array) -> Array:
	var arr: Array = []
	for p_card in player_unlocked:
		var p_elem: String = ELEMENT_SHORT.get(p_card.element, "none")
		var base_dmg: int = p_card.damage
		var armor_threat: float = p_card.armor * 0.7  # 护甲间接计入威胁
		var total_base: float = base_dmg + armor_threat
		arr.append({
			"player_card": String(p_card.id),
			"element": p_elem,
			"base_damage": base_dmg,
			"base_armor": p_card.armor,
			"dmg_if_i_neutral":   int(round(total_base * 1.0)),
			"dmg_if_i_countered": int(round(total_base * 1.5)),
			"dmg_if_i_counter":   int(round(total_base * 1.0)),
		})
	return arr


## v0.9.0：候选内注入"机会成本视图" if_i_pick_this_now
## 告诉 LLM：选这张后我剩余候选能否覆盖玩家未锁候选
## slot 4（最后一个 slot）跳过此字段（后面没 slot 了，省 token）
static func _inject_future_slots_view(candidates: Array, current_slot: int,
		boss_candidates: Array, player_unlocked: Array) -> void:
	# slot 4（current_slot=3）跳过：后面没 slot 待选
	if current_slot >= 3:
		return

	for i in range(candidates.size()):
		var entry: Dictionary = candidates[i]
		if entry.get("picked", false):
			continue
		# 计算"如果我选 entry[i]，剩余候选池"
		var my_remaining: Array = []
		var my_remaining_ids: Array = []
		for j in range(boss_candidates.size()):
			if j == i:
				continue  # 跳过当前选的这张
			if j < candidates.size() and candidates[j].get("picked", false):
				continue  # 跳过已 picked 位
			var c = boss_candidates[j]
			if c != null and c is CardData:
				my_remaining.append(c)
				my_remaining_ids.append(String(c.id))

		# 对玩家每张未锁候选，找我剩余池中的最佳对位
		var coverage: Array = []
		var uncovered_ids: Array = []
		for p_card in player_unlocked:
			var p_elem: String = ELEMENT_SHORT.get(p_card.element, "none")
			var best_card: CardData = null
			var best_mult: float = -1.0
			for my_card in my_remaining:
				var my_elem: String = ELEMENT_SHORT.get(my_card.element, "none")
				var mult: float = _compute_multiplier(my_elem, p_elem)
				if mult > best_mult:
					best_mult = mult
					best_card = my_card
			if best_card == null:
				continue
			var covered: bool = best_mult >= 1.0  # 至少中性才算"覆盖"
			coverage.append({
				"player_card": String(p_card.id),
				"best_in_remaining": {
					"card": String(best_card.id),
					"mult": best_mult,
					"covered": covered,
				},
			})
			if not covered:
				uncovered_ids.append(String(p_card.id))

		entry["if_i_pick_this_now"] = {
			"my_remaining_pool": my_remaining_ids,
			"coverage_per_player_card": coverage,
			"uncovered_player_cards": uncovered_ids,
			"covered_count": coverage.size() - uncovered_ids.size(),
			"uncovered_count": uncovered_ids.size(),
		}


## v0.9.1：模拟"前 N 个已锁 slot"翻盅后的双方 HP/护甲
## 用于解决 LLM 在 slot 4 决策治疗时\"看 self.hp 仍满血\"的盲点
## 复刻 ClashResolver.resolve_clash + BlindClashBattle._resolve_card_with_multiplier 关键逻辑：
##   - 倍率：调 ClashResolver.resolve_clash 拿 multiplier（避免重复克制公式）
##   - 应用：复刻\"伤害（先扣甲）/ 护甲叠加 / 治疗 clamp max_hp\"三件
##   - 不复刻：抽牌（不影响 HP）/ 状态（charge）/ next_attack_bonus（slot 间不传递的简化）
##   - 不复刻：reflect_damage（当前主代码也未实装）
##
## v0.9.3：预测玩家 2:2 平衡 +1 加成
##   - 用\"玩家 picks 全 4 张\"判 2:2（包括未锁但已知的位置 — 当前 BP 模式玩家未锁时为 null）
##   - 若已锁的 player 牌中能确定 2:2（4 张全锁），模拟时玩家方每个非零字段 +1
##   - 部分已锁时无法预测，按无 +1 模拟（保守低估）
##
## @param boss_picks   长度 4 的数组，已锁 slot 为 CardData，未锁为 null
## @param player_picks 同上
## @param current_slot 当前要决策的 slot（仅 0..current_slot-1 视为已锁参与模拟）
## @param boss_hp / boss_max_hp / boss_armor 等都是\"决策前\"的真实值
## @return Dictionary {self_hp, self_armor, player_hp, player_armor, details: [...]}
static func _simulate_locked_slots_outcome(
		boss_picks: Array, player_picks: Array, current_slot: int,
		boss_hp: int, boss_max_hp: int, boss_armor: int,
		player_hp: int, player_max_hp: int, player_armor: int) -> Dictionary:
	# 收集已锁 slot 的牌（仅 current_slot 之前的）
	var locked_boss: Array[CardData] = []
	var locked_player: Array[CardData] = []
	for i in range(min(current_slot, 4)):
		var b: CardData = boss_picks[i] if i < boss_picks.size() else null
		var p: CardData = player_picks[i] if i < player_picks.size() else null
		locked_boss.append(b)
		locked_player.append(p)

	# 初始化模拟变量（不修改真实 combatant）
	var s_hp: int = boss_hp
	var s_armor: int = boss_armor
	var p_hp: int = player_hp
	var p_armor: int = player_armor
	var details: Array = []

	if locked_boss.is_empty():
		# 没有已锁 slot，直接返回当前状态
		return {
			"self_hp": s_hp, "self_armor": s_armor,
			"player_hp": p_hp, "player_armor": p_armor,
			"details": details,
		}

	# v0.9.3：判玩家 2:2 平衡（基于已锁的部分 + 全 4 张 player_picks 中已知 CardData 数量 == 4）
	# - 当玩家 4 张全锁时，可精确判定 2:2 → 模拟应用 +1
	# - 部分已锁时，is_balanced_polarity 在 ClashResolver 里只用部分牌算，必为 false（要求 light=2 dark=2 共4张）
	# 所以这里直接使用 ClashResolver 的判定结果即可（结果中的 balanced_bonus 标记）
	var results: Array = ClashResolver.resolve_clash(locked_player, locked_boss)

	for i in range(results.size()):
		var r: ClashResolver.ClashResult = results[i]
		var slot_detail: Dictionary = {
			"slot": i,
			"self_hp_before": s_hp,
			"player_hp_before": p_hp,
		}

		# 双方同步结算（先各自计算最终值，再同时应用，符合真实结算）
		# Boss 牌效果（caster=boss, target=player）
		var b_dmg_dealt: int = 0
		var b_armor_gain: int = 0
		var b_heal: int = 0
		if r.boss_card != null and r.boss_multiplier > 0:
			var bc: CardData = r.boss_card
			var bm: float = r.boss_multiplier
			if bc.damage > 0:
				b_dmg_dealt = ClashResolver.apply_multiplier_int(bc.damage, bm)
			if bc.armor > 0:
				b_armor_gain = ClashResolver.apply_multiplier_int(bc.armor, bm)
			if bc.heal > 0:
				b_heal = ClashResolver.apply_multiplier_int(bc.heal, bm)

		# Player 牌效果（v0.9.3：玩家方 2:2 平衡 → 倍率后非零字段 +1，由 r.balanced_bonus 标记）
		var p_dmg_dealt: int = 0
		var p_armor_gain: int = 0
		var p_heal: int = 0
		var p_ignore_armor: bool = false
		if r.player_card != null and r.player_multiplier > 0:
			var pc: CardData = r.player_card
			var pm: float = r.player_multiplier
			var p_balanced_plus: int = 1 if r.balanced_bonus else 0
			if pc.damage > 0:
				p_dmg_dealt = ClashResolver.apply_multiplier_int(pc.damage, pm) + p_balanced_plus
				p_ignore_armor = pc.ignore_armor
			if pc.armor > 0:
				p_armor_gain = ClashResolver.apply_multiplier_int(pc.armor, pm) + p_balanced_plus
			if pc.heal > 0:
				p_heal = ClashResolver.apply_multiplier_int(pc.heal, pm) + p_balanced_plus

		var b_ignore_armor: bool = (r.boss_card != null and r.boss_card.ignore_armor)

		# 应用 boss 对 player 的伤害（先扣甲）
		if p_dmg_dealt > 0:
			var dmg_after_armor: int = p_dmg_dealt
			if not b_ignore_armor and p_armor > 0:
				var blocked: int = mini(p_armor, p_dmg_dealt)
				p_armor -= blocked
				dmg_after_armor -= blocked
			pass  # 占位
			p_hp = maxi(p_hp - dmg_after_armor, 0)

		# 应用 player 对 boss 的伤害
		if b_dmg_dealt > 0:
			var dmg_after_armor2: int = b_dmg_dealt
			if not p_ignore_armor and s_armor > 0:
				var blocked2: int = mini(s_armor, b_dmg_dealt)
				s_armor -= blocked2
				dmg_after_armor2 -= blocked2
			s_hp = maxi(s_hp - dmg_after_armor2, 0)

		# 应用各自的护甲叠加
		s_armor += b_armor_gain
		p_armor += p_armor_gain

		# 应用治疗（clamp max_hp）
		if b_heal > 0:
			s_hp = mini(s_hp + b_heal, boss_max_hp)
		if p_heal > 0:
			p_hp = mini(p_hp + p_heal, player_max_hp)

		slot_detail["self_dmg_taken"] = slot_detail["self_hp_before"] - s_hp + b_heal  # 净伤害
		slot_detail["player_dmg_taken"] = slot_detail["player_hp_before"] - p_hp + p_heal
		slot_detail["self_hp_after"] = s_hp
		slot_detail["player_hp_after"] = p_hp
		details.append(slot_detail)

	return {
		"self_hp": s_hp, "self_armor": s_armor,
		"player_hp": p_hp, "player_armor": p_armor,
		"details": details,
	}








## v0.9.1：构建 pre_slot_outlook.summary 的人类可读句
static func _build_pre_slot_summary(boss_hp_orig: int, boss_hp_now: int,
		player_hp_orig: int, player_hp_now: int, current_slot: int) -> String:
	if current_slot == 0:
		return "slot 1 决策：尚无已锁 slot，HP 等于当前显示值"
	var s_diff: int = boss_hp_orig - boss_hp_now
	var p_diff: int = player_hp_orig - player_hp_now
	var s_part: String
	var p_part: String
	if s_diff > 0:
		s_part = "boss HP %d→%d（吃%d伤）" % [boss_hp_orig, boss_hp_now, s_diff]
	elif s_diff < 0:
		s_part = "boss HP %d→%d（治疗+%d）" % [boss_hp_orig, boss_hp_now, -s_diff]
	else:
		s_part = "boss HP %d 不变" % boss_hp_orig
	if p_diff > 0:
		p_part = "玩家 HP %d→%d（吃%d伤）" % [player_hp_orig, player_hp_now, p_diff]
	elif p_diff < 0:
		p_part = "玩家 HP %d→%d（治疗+%d）" % [player_hp_orig, player_hp_now, -p_diff]
	else:
		p_part = "玩家 HP %d 不变" % player_hp_orig
	return "前 %d slot 锁定后：%s，%s" % [current_slot, s_part, p_part]


## v0.9.1：把 pre_slot 的预测 HP/护甲注入候选的 vs_current_opponent
## 给每张候选追加：
##   - my_effective_heal: 治疗已应用倍率 + clamp 到 room_for_heal
##   - my_heal_capped_by_room: 治疗是否被 room 限制（true=部分浪费）
##   - self_hp_after_this: 选这张并 slot 翻盅后 boss 最终 HP（含治疗 / 护甲挡）
##   - player_hp_after_this: 选这张后 player 最终 HP（斩杀判断用）
##   - effective_armor_value: 护甲牌当前 slot 翻盅时的真实挡伤（基于对位牌的 base_dmg）
static func _enrich_candidates_with_pre_slot(candidates: Array,
		boss_hp_pre: int, boss_armor_pre: int, boss_max_hp: int,
		player_hp_pre: int, player_max_hp: int) -> void:
	var room: int = maxi(boss_max_hp - boss_hp_pre, 0)
	for entry in candidates:
		if entry.get("picked", false):
			continue
		var vs: Variant = entry.get("vs_current_opponent", null)
		if vs == null or not (vs is Dictionary):
			continue
		var vs_dict: Dictionary = vs
		if not bool(vs_dict.get("locked", false)):
			# 未锁场景：仍写"决策前 HP"和 room，便于一致性
			vs_dict["self_hp_before_clash"] = boss_hp_pre
			vs_dict["self_hp_room_for_heal"] = room
			continue

		var mult: float = float(vs_dict.get("multiplier", 1.0))
		var base_heal: int = int(entry.get("heal", 0))
		var base_armor_card: int = int(entry.get("armor", 0))
		var actual_dmg: int = int(vs_dict.get("my_actual_damage", 0))

		# 治疗有效收益（应用倍率 + clamp）
		var heal_after_mult: int = 0
		if base_heal > 0:
			heal_after_mult = ClashResolver.apply_multiplier_int(base_heal, mult)
		var heal_capped: int = mini(heal_after_mult, room)
		vs_dict["my_effective_heal"] = heal_capped
		vs_dict["my_heal_capped_by_room"] = (heal_after_mult > heal_capped)

		# 护甲有效价值（已应用倍率，仅信息字段，结算前是直接获得）
		var armor_after_mult: int = 0
		if base_armor_card > 0:
			armor_after_mult = ClashResolver.apply_multiplier_int(base_armor_card, mult)
		vs_dict["my_effective_armor"] = armor_after_mult

		# 选这张并翻盅后的最终 HP 预测（简化版：只考虑这张牌的伤害+治疗，不考虑对位玩家牌反打 boss 的伤害）
		# 备注：对位玩家牌的伤害已在 player_unlocked_threat_profile 给出，LLM 自行综合
		var hp_after: int = boss_hp_pre + heal_capped
		hp_after = mini(hp_after, boss_max_hp)
		vs_dict["self_hp_after_this"] = hp_after

		# 玩家承受这张牌的伤害后 HP（用于斩杀判断）
		var p_hp_after: int = maxi(player_hp_pre - actual_dmg, 0)
		vs_dict["player_hp_after_this"] = p_hp_after

		# 公共字段
		vs_dict["self_hp_before_clash"] = boss_hp_pre
		vs_dict["self_hp_room_for_heal"] = room
		vs_dict["player_hp_before_clash"] = player_hp_pre


## 蛇形出牌辅助：返回指定 slot 的"先出方"
## 偶数 slot（0,2）→ first_picker 先出；奇数 slot（1,3）→ second_picker 先出
static func _get_slot_leader(slot: int, first_picker: String) -> String:
	if slot % 2 == 0:
		return first_picker if first_picker != "" else "player"
	else:
		return "boss" if first_picker == "player" else "player"


## 把候选数组（含 null 已 Pick 位）压成紧凑 JSON
## 已 Pick 位置用 null 占位，保留 index 与原数组一致 → LLM 能正确读出"剩余可选索引"
static func _build_candidates(cards: Array) -> Array:
	var arr: Array = []
	for i in range(cards.size()):
		var c = cards[i]
		if c == null:
			arr.append({"index": i, "picked": true})
			continue
		if c is CardData:
			arr.append({
				"index": i,
				"id": String(c.id),
				"name": c.card_name,
				"type": TYPE_SHORT.get(c.type, "skl"),
				"element": ELEMENT_SHORT.get(c.element, "none"),
				"polarity": POLARITY_SHORT.get(c.polarity, "none"),
				"cost": c.energy_cost,
				"dmg": c.damage,
				"hits": c.hits,
				"armor": c.armor,
				"heal": c.heal,
				"draw": c.draw_cards,
				"enemy_draw_mod": c.enemy_draw_modifier,
				"enemy_energy_mod": c.enemy_energy_modifier,
				"desc": c.description,
			})
	return arr


## 已锁定的 picks 摘要（双方对称）
## 输出长度永远 4（slot 1~4），未锁的为 {slot:N, locked:false}
static func _build_picks_summary(picks: Array) -> Array:
	var arr: Array = []
	for i in range(4):
		var c = null
		if i < picks.size():
			c = picks[i]
		if c == null:
			arr.append({"slot": i + 1, "locked": false})
		elif c is CardData:
			arr.append({
				"slot": i + 1,
				"locked": true,
				"id": String(c.id),
				"name": c.card_name,
				"type": TYPE_SHORT.get(c.type, "skl"),
				"element": ELEMENT_SHORT.get(c.element, "none"),
				"polarity": POLARITY_SHORT.get(c.polarity, "none"),
				"cost": c.energy_cost,
			})
	return arr


## GDD-08 进度上下文（MIRROR 进度系统，供 LLM 决策参考）
## progression 字典来自 RunState.get_state_summary()
static func _build_progression(progression: Dictionary) -> Dictionary:
	if progression.is_empty():
		return {"note": "进度系统未启用"}
	var result: Dictionary = {}
	result["round_index"] = progression.get("round_index", 1)
	result["victory_streak"] = progression.get("victory_streak", 0)
	# 升级历史摘要（最近 2 条，避免 token 膨胀）
	var hist: Array = progression.get("upgrade_history", [])
	if hist.size() > 2:
		hist = hist.slice(hist.size() - 2)
	result["recent_upgrades"] = hist
	# 结构修正
	var mods: Dictionary = progression.get("struct_modifiers", {})
	if not mods.is_empty():
		result["struct_modifiers"] = mods
	if not result.is_empty():
		result["note"] = "MIRROR 进度：牌库每轮互换，你当前的牌库可能不是原始牌库"
	return result


# ------------------------------------------------------------------
# 信息对称校验（运维 / 单测 用）
# ------------------------------------------------------------------
## 校验 Boss 拿到的 player 视图是否违反对称契约
## 返回违规字段列表（空 = 合规）
## 用法：assert(PerceptionBuilder.validate_symmetry(perception).is_empty())
static func validate_symmetry(perception: Dictionary) -> Array[String]:
	var violations: Array[String] = []
	var p: Variant = perception.get("player", null)
	if not (p is Dictionary):
		return violations
	# 禁止字段（对称契约红线）
	var forbidden_keys := [
		"hand",                  # 玩家手牌内容
		"hand_cards",
		"deck",                  # 玩家牌库内容
		"deck_type_counts",      # 玩家牌库类型分布（B 浮层不给 Boss 这个）
		"trap_slot_attack_real", # 陷阱真假
		"trap_slot_skill_real",
		"trap_slot_high_cost_real",
	]
	for k in forbidden_keys:
		if p.has(k):
			violations.append("player.%s" % k)
	return violations
