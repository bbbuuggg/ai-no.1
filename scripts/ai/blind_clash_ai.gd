class_name BlindClashAI
extends RefCounted
## Boss 暗出决策AI — 选牌 + 排列 + 陷阱规避

## Boss 性格配置
var aggression: float = 0.7
var defense_bias: float = 0.3
var risk_tolerance: float = 0.5  # 面对陷阱的冒险倾向
var clash_style: String = "aggressive"  # aggressive/defensive/unpredictable


## 选择暗出牌序列
func select_blind_cards(boss: Combatant, player: Combatant, trap_slots: Array, _probe: CognitiveProbe) -> Array[CardData]:
	var selected: Array[CardData] = []
	var remaining_energy: int = boss.energy

	# 1. 获取可打出的牌（排除0费，0费不占能量但Boss不用绑定机制）
	var playable: Array[CardData] = []
	for card in boss.hand:
		if card.energy_cost <= remaining_energy and card.energy_cost > 0:
			playable.append(card)
		elif card.energy_cost == 0:
			playable.append(card)  # Boss的0费牌直接可出

	if playable.is_empty():
		return []

	# 2. 评估场面，确定攻防倾向
	var stance: String = _evaluate_stance(boss, player)

	# 3. 考虑陷阱规避
	var trap_aware_cards: Array[CardData] = _filter_by_trap_awareness(playable, trap_slots)

	# 4. 打分排序
	var scored: Array[Dictionary] = []
	for card in trap_aware_cards:
		var score: float = _score_card(card, boss, player, stance, trap_slots)
		scored.append({"card": card, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"]
	)

	# 5. 贪心选取
	for entry in scored:
		var card: CardData = entry["card"]
		if card.energy_cost <= remaining_energy:
			selected.append(card)
			remaining_energy -= card.energy_cost

	# 6. 排列顺序
	selected = _arrange_order(selected, stance)

	# 从Boss手牌移除已选的牌
	for card in selected:
		boss.hand.erase(card)
	boss.hand_changed.emit()

	return selected


## 纯读取版：返回规则 AI 会选的牌，但**不**从 boss.hand 中移除
## 供 LLMBossAI 作为"建议参考"时调用
func preview_blind_cards(boss: Combatant, player: Combatant, trap_slots: Array, _probe: CognitiveProbe) -> Array[CardData]:
	var selected: Array[CardData] = []
	var remaining_energy: int = boss.energy

	var playable: Array[CardData] = []
	for card in boss.hand:
		if card.energy_cost <= remaining_energy and card.energy_cost > 0:
			playable.append(card)
		elif card.energy_cost == 0:
			playable.append(card)

	if playable.is_empty():
		return []

	var stance: String = _evaluate_stance(boss, player)
	var trap_aware_cards: Array[CardData] = _filter_by_trap_awareness(playable, trap_slots)

	var scored: Array[Dictionary] = []
	for card in trap_aware_cards:
		var score: float = _score_card(card, boss, player, stance, trap_slots)
		scored.append({"card": card, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"]
	)

	for entry in scored:
		var card: CardData = entry["card"]
		if card.energy_cost <= remaining_energy:
			selected.append(card)
			remaining_energy -= card.energy_cost

	selected = _arrange_order(selected, stance)
	# **不**修改 boss.hand，这是 preview 的关键
	return selected


func _evaluate_stance(boss: Combatant, player: Combatant) -> String:
	var hp_ratio: float = float(boss.hp) / float(boss.max_hp)

	# 能击杀 → 全攻
	var total_damage: int = 0
	for card in boss.hand:
		if card.damage > 0:
			total_damage += card.damage * card.hits
	if total_damage >= player.hp:
		return "kill"

	# 低血 → 防守
	if hp_ratio < 0.3:
		return "defensive"

	# 正常 → 按性格
	if aggression > 0.6:
		return "aggressive"
	elif defense_bias > 0.5:
		return "defensive"
	return "balanced"


func _filter_by_trap_awareness(cards: Array[CardData], trap_slots: Array) -> Array[CardData]:
	## 根据陷阱槽位情况过滤/降权牌
	##
	## 【关键】Boss 只知道"哪个槽位有占位"，不知道真假（诱饵 is_bluff 对 Boss 不可见）。
	## 这是诱饵牌生效的前提 —— 它与真陷阱对 AI 决策的影响完全相同。
	var result: Array[CardData] = []

	for card in cards:
		var would_trigger_slot: int = _card_triggers_slot(card)
		if would_trigger_slot >= 0 and trap_slots[would_trigger_slot] != null:
			# 这张牌会触发一个被占的陷阱槽
			# 根据冒险倾向决定是否保留
			if randf() < risk_tolerance:
				result.append(card)  # 冒险，照常出
			# 否则跳过（规避）
		else:
			result.append(card)

	# 如果全被过滤了，至少保留原始列表（不能一张都不出）
	if result.is_empty():
		return cards
	return result


## 计算陷阱威慑因子（供 _score_card 使用）
## 占位槽越多、牌能量越高/伤害越高，威慑越强
func _trap_deterrent_penalty(card: CardData, trap_slots: Array) -> float:
	var occupied_count: int = 0
	for slot in trap_slots:
		if slot != null:
			occupied_count += 1
	if occupied_count == 0:
		return 0.0

	var trigger_slot: int = _card_triggers_slot(card)
	# 若该牌不会触发任何槽位（理论上每张牌都会至少触发一个，保守兜底）
	if trigger_slot < 0:
		return 0.0
	# 该牌对应槽位是否被占？若被占，最大威慑；若未被占但别处有，小威慑（间接不安）
	var slot_is_occupied: bool = trap_slots[trigger_slot] != null

	var penalty: float = 0.0
	if slot_is_occupied:
		# 高能量牌（≥3）损失最大，被打断一次几乎等于空一回合
		if card.energy_cost >= 3:
			penalty += 15.0
		elif card.energy_cost >= 2:
			penalty += 8.0
		else:
			penalty += 3.0
		# 高伤害牌（怕反弹 / 怕被虹吸）
		if card.damage >= 6:
			penalty += 8.0
		elif card.damage >= 3:
			penalty += 3.0
	else:
		# 对应槽位没被占，但 Boss 整体警觉度略升（看到陷阱氛围紧张）
		penalty += 1.5 * float(occupied_count)

	# 冒险倾向：risk_tolerance 越高越无视威慑
	penalty *= (1.0 - risk_tolerance * 0.6)
	return penalty


func _card_triggers_slot(card: CardData) -> int:
	## 返回这张牌会触发哪个陷阱槽位（-1=无）
	match card.type:
		CardData.CardType.ATTACK:
			return 0
		CardData.CardType.SKILL, CardData.CardType.PROTOCOL:
			return 1
	if card.energy_cost >= 2:
		return 2
	return -1


func _score_card(card: CardData, boss: Combatant, player: Combatant, stance: String, trap_slots: Array = []) -> float:
	var cost: float = maxf(card.energy_cost, 0.5)
	var value: float = 0.0

	# 攻击价值
	if card.damage > 0:
		var atk_weight: float = 1.5 if stance in ["aggressive", "kill"] else 0.8
		value += card.damage * card.hits * atk_weight
		if card.ignore_armor:
			value += 2.0

	# 防御价值
	if card.armor > 0:
		var def_weight: float = 1.5 if stance == "defensive" else 0.6
		value += card.armor * def_weight

	# 治疗价值
	if card.heal > 0:
		var heal_need: float = 1.0 - (float(boss.hp) / float(boss.max_hp))
		value += card.heal * heal_need * 2.0

	# 抽牌
	if card.draw_cards > 0:
		value += card.draw_cards * 2.5

	# 蓄力
	if card.grants_charge:
		var has_charged_card: bool = boss.hand.any(
			func(c: CardData) -> bool: return c.requires_charge
		)
		value += 4.0 if has_charged_card else 0.5

	if card.requires_charge and boss.is_charged:
		value += card.damage * 2.0
	elif card.requires_charge and not boss.is_charged:
		value = -10.0

	# 全攻击加成
	if card.all_attack_bonus > 0:
		value += card.all_attack_bonus * 3.0

	# 【陷阱威慑扣分】 — 诱饵/真陷阱都在此生效（AI 无法区分）
	if not trap_slots.is_empty():
		value -= _trap_deterrent_penalty(card, trap_slots)

	return value / cost


func _arrange_order(cards: Array[CardData], stance: String) -> Array[CardData]:
	## 根据风格排列暗出顺序
	var sorted_cards: Array[CardData] = cards.duplicate()

	match clash_style:
		"aggressive":
			# 攻击牌排前（试图克制对手的技能牌）
			sorted_cards.sort_custom(func(a: CardData, b: CardData) -> bool:
				return _type_priority_aggressive(a.type) < _type_priority_aggressive(b.type)
			)
		"defensive":
			# 防御牌排前（安全优先，克制对手的攻击牌）
			sorted_cards.sort_custom(func(a: CardData, b: CardData) -> bool:
				return _type_priority_defensive(a.type) < _type_priority_defensive(b.type)
			)
		"unpredictable":
			sorted_cards.shuffle()
		_:
			# balanced: 按价值排
			pass

	return sorted_cards


func _type_priority_aggressive(type: CardData.CardType) -> int:
	match type:
		CardData.CardType.ATTACK: return 0
		CardData.CardType.PROTOCOL: return 1
		CardData.CardType.SKILL: return 2
		CardData.CardType.DEFENSE: return 3
	return 4


func _type_priority_defensive(type: CardData.CardType) -> int:
	match type:
		CardData.CardType.DEFENSE: return 0
		CardData.CardType.SKILL: return 1
		CardData.CardType.PROTOCOL: return 2
		CardData.CardType.ATTACK: return 3
	return 4
