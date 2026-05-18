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
##   "rules_summary": "克制(主)：火克木 / 木克水 / 水克火 → 命中×1.5 被克×0.5；玩家方 4 张正好 2 光 2 暗 → 克制倍率 1.5 升 2.0",
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
const _RULES_SUMMARY := "克制仅在同slot对位之间判定(你slot1只vs玩家slot1);克制链单向闭环：火→木→水→火(火克木/木克水/水克火)→命中×1.5被克×0.5同元素中立;⚠反向必错:不存在'水克木/木克火/火克水';协同：玩家方4张正好2光2暗→玩家克制倍率1.5升2.0;治疗满血=0(不溢出不保留);倍率作用于该牌全部数值（伤害/护甲/治疗/抽牌/能量）;毫无阻力:某slot一方出牌对方无能量跳过(对位为空)→出牌方全部效果×2;蛇形出牌(Snake Draft):偶数slot先手方先出奇数slot后手方先出→先手信息优劣势2:2平衡"


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
	# v0.8.3：再追加 vs_opponent_*（精确克制倍率，避免 LLM 推理方向出错）
	var self_candidates_view: Array = _build_candidates_with_budget_outlook(
		boss_candidates, current_slot, boss.energy
	)
	_inject_vs_opponent_multiplier(self_candidates_view, matchup, boss_candidates)
	# 当前 slot 对位玩家牌的"威胁估值"（用于 LLM 判断是否值得 skip）
	var opponent_threat: int = _compute_opponent_threat(matchup, player_picks, current_slot)
	# Skip 战术合法性提示（恒为 true，但显式给 LLM 信号）
	var skip_legal: bool = true

	return {
		"mode": "bp_slot_pick",
		"self": _build_self(boss),
		"self_candidates": self_candidates_view,
		"self_picks": _build_picks_summary(boss_picks),
		"player": _build_player_view(player, []),  # BP 路径下 trap_slots 永远空
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


## v0.8.3：给每张未 picked 候选注入精确的"vs 对位"克制倍率字段
## 目的：杜绝 LLM 自己推理克制方向（实测会出现"wood 克 fire"反向幻觉）
## 字段：
##   - vs_opponent_element: "fire"/"water"/"wood"/"none"  对位玩家元素（matchup 未锁时为 "none"）
##   - vs_opponent_multiplier: 0.5 / 1.0 / 1.5 / null      精确倍率（未锁时为 null）
##   - vs_opponent_label: "克制"/"被克"/"中性"/"对位未锁"  人类可读
static func _inject_vs_opponent_multiplier(candidates: Array, matchup: Dictionary,
		boss_candidates: Array) -> void:
	# 未锁场景：标记所有候选为"对位未锁"
	if matchup == null or matchup.is_empty() or not bool(matchup.get("opponent_locked", false)):
		for entry in candidates:
			if entry.get("picked", false):
				continue
			entry["vs_opponent_element"] = "none"
			entry["vs_opponent_multiplier"] = null
			entry["vs_opponent_label"] = "对位未锁"
		return

	var opp_elem: String = String(matchup.get("opponent_element", "none"))
	# 克制规则：FIRE→WOOD→WATER→FIRE
	# 你出 X 对手出 Y → 倍率
	var counter_map := {
		"fire":  {"fire": 1.0, "water": 0.5, "wood": 1.5},
		"water": {"fire": 1.5, "water": 1.0, "wood": 0.5},
		"wood":  {"fire": 0.5, "water": 1.5, "wood": 1.0},
	}

	for i in range(candidates.size()):
		var entry: Dictionary = candidates[i]
		if entry.get("picked", false):
			continue
		# 从 candidates 列表里直接读 element 字段（已经填好）
		var self_elem: String = String(entry.get("element", "none"))
		entry["vs_opponent_element"] = opp_elem
		if self_elem == "none" or opp_elem == "none":
			entry["vs_opponent_multiplier"] = 1.0
			entry["vs_opponent_label"] = "中性（无元素）"
			continue
		var mult: float = counter_map.get(self_elem, {}).get(opp_elem, 1.0)
		entry["vs_opponent_multiplier"] = mult
		match mult:
			1.5:
				entry["vs_opponent_label"] = "你克 ×1.5"
			0.5:
				entry["vs_opponent_label"] = "你被克 ×0.5"
			_:
				entry["vs_opponent_label"] = "同色 ×1.0"


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
