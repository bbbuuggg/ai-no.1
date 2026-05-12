class_name RuleAI
extends RefCounted
## Boss 规则 AI — 三层优先级决策（开发阶段，后期替换为 LLM）

var behavior_weights: Dictionary = {
	"aggression": 0.7,
	"defense": 0.3,
	"greed": 0.5,
	"threat_response": 0.8,
}


func make_decision(boss: Combatant, player: Combatant) -> Array[CardData]:
	var legal_hand: Array[CardData] = _get_legal_cards(boss)
	if legal_hand.is_empty():
		return []

	var actions: Array[CardData] = []
	var remaining_energy: int = boss.energy

	# 优先级 1：生存检查 — HP < 30% 优先防御
	if boss.hp < boss.max_hp * 0.3:
		var defense_cards: Array[CardData] = legal_hand.filter(
			func(c: CardData) -> bool: return c.type == CardData.CardType.DEFENSE
		)
		for card in defense_cards:
			if card.energy_cost <= remaining_energy:
				actions.append(card)
				remaining_energy -= card.energy_cost
				legal_hand.erase(card)

	# 优先级 2：击杀检查 — 能一波带走就全力攻击
	var total_possible_damage: int = 0
	for card in legal_hand:
		if card.damage > 0 and card.energy_cost <= remaining_energy:
			total_possible_damage += card.damage * card.hits
	if total_possible_damage >= player.hp:
		var attack_cards: Array[CardData] = legal_hand.filter(
			func(c: CardData) -> bool: return c.damage > 0
		)
		attack_cards.sort_custom(func(a: CardData, b: CardData) -> bool:
			return (a.damage * a.hits) > (b.damage * b.hits)
		)
		for card in attack_cards:
			if card.energy_cost <= remaining_energy:
				actions.append(card)
				remaining_energy -= card.energy_cost

		return actions

	# 优先级 3：价值最大化 — 按效率打牌
	var scored: Array[Dictionary] = []
	for card in legal_hand:
		var score: float = _score_card(card, boss, player)
		scored.append({"card": card, "score": score})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["score"] > b["score"]
	)

	for entry in scored:
		var card: CardData = entry["card"]
		if card.energy_cost <= remaining_energy:
			actions.append(card)
			remaining_energy -= card.energy_cost

	return actions


func _score_card(card: CardData, boss: Combatant, player: Combatant) -> float:
	var cost: float = maxf(card.energy_cost, 0.5)
	var value: float = 0.0

	# 攻击价值
	if card.damage > 0:
		value += card.damage * card.hits * behavior_weights["aggression"]
		if card.ignore_armor:
			value += 2.0
	# 防御价值
	if card.armor > 0:
		var threat_factor: float = 1.0 - (float(boss.hp) / float(boss.max_hp))
		value += card.armor * behavior_weights["defense"] * (1.0 + threat_factor)
	# 治疗价值
	if card.heal > 0:
		var heal_need: float = 1.0 - (float(boss.hp) / float(boss.max_hp))
		value += card.heal * heal_need * 1.5
	# 抽牌价值
	if card.draw_cards > 0:
		value += card.draw_cards * 2.0 * behavior_weights["greed"]
	# 蓄力价值
	if card.grants_charge:
		# 检查手牌中是否有需要蓄力的牌
		var has_charged_card: bool = boss.hand.any(
			func(c: CardData) -> bool: return c.requires_charge
		)
		value += 5.0 if has_charged_card else 1.0
	# 蓄力释放
	if card.requires_charge and boss.is_charged:
		value += card.damage * 1.5
	elif card.requires_charge and not boss.is_charged:
		value = -10.0  # 没蓄力不要打

	# 全攻击加成
	if card.all_attack_bonus > 0:
		var attack_count: int = boss.hand.filter(
			func(c: CardData) -> bool: return c.damage > 0
		).size()
		value += card.all_attack_bonus * attack_count * 0.8

	return value / cost


func _get_legal_cards(boss: Combatant) -> Array[CardData]:
	var legal: Array[CardData] = []
	for card in boss.hand:
		if card.energy_cost <= boss.energy:
			legal.append(card)
	return legal
