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
## 输出 schema 示例：
## {
##   "self": {"hp":48, "armor":0, "energy":3, "deck_count":12, "discard_count":4,
##            "deck_type_counts":{"atk":3,"def":2,"skl":4,"pro":3}},
##   "self_hand": [
##     {"id":"boss_pulse", "name":"回响脉冲", "type":"atk", "cost":1, "dmg":5, "desc":"造成5伤害"}
##   ],
##   "player": {"hp":52, "armor":2, "energy":3, "hand_count":4,
##              "trap_slot_attack":"occupied", "trap_slot_skill":"empty", "trap_slot_high_cost":"empty"},
##   "history": [
##     {"turn":3, "boss_played":["atk×2"], "player_typed":["atk","def"], "result":"draw"}
##   ],
##   "rules_summary": "三角克制：攻克技、技克防、防克攻；命中×1.5，被克×0.5",
##   "round": 4,
##   "energy_budget": 3,
##   "max_picks": 3
## }

const TYPE_SHORT := {
	CardData.CardType.ATTACK: "atk",
	CardData.CardType.DEFENSE: "def",
	CardData.CardType.SKILL: "skl",
	CardData.CardType.PROTOCOL: "pro",
}


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
	peeked_cards: Array = []
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
		"round": round_number,
		"energy_budget": boss.energy,
		"max_picks": 3,
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
		"note": "规则 AI 基于三角克制+陷阱威慑给出的推荐。你可以采纳或偏离。",
	}


## 自己侧（不含手牌明细，由 self_hand 单独给）
static func _build_self(boss: Combatant) -> Dictionary:
	var deck_counts := {"atk": 0, "def": 0, "skl": 0, "pro": 0}
	for c in boss.deck:
		var key: String = TYPE_SHORT.get(c.type, "skl")
		deck_counts[key] += 1
	return {
		"hp": boss.hp,
		"max_hp": boss.max_hp,
		"armor": boss.armor,
		"energy": boss.energy,
		"is_charged": boss.is_charged,
		"deck_count": boss.deck.size(),
		"discard_count": boss.discard_pile.size(),
		"deck_type_counts": deck_counts,
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
			"cost": c.energy_cost,
			"dmg": c.damage,
			"hits": c.hits,
			"armor": c.armor,
			"heal": c.heal,
			"draw": c.draw_cards,
			"ignore_armor": c.ignore_armor,
			"requires_charge": c.requires_charge,
			"grants_charge": c.grants_charge,
			"all_atk_bonus": c.all_attack_bonus,
			"desc": c.description,
		})
	return arr


## 对方（玩家）视角 —— 不能看牌
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
