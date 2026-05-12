class_name BossIntent
extends RefCounted
## Boss 意图预告数据结构

enum IntentType {
	ATTACK,        # 攻击意图
	HEAVY_ATTACK,  # 重击（大于某阈值）
	MULTI_ATTACK,  # 多段攻击
	DEFEND,        # 防御姿态
	BUFF,          # 增益/蓄力
	DEBUFF,        # 干扰玩家
	HEAL,          # 治疗
	DRAW,          # 抽牌/资源
	UNKNOWN,       # 未知（被约束令干扰后）
}

var type: IntentType = IntentType.UNKNOWN
var value: int = 0           # 数值估算（伤害/护甲/等）
var hit_count: int = 1       # 多段次数
var description: String = ""  # 简短描述


static func analyze_actions(actions: Array[CardData]) -> BossIntent:
	## 从 AI 决策序列推导出主要意图
	var intent := BossIntent.new()
	if actions.is_empty():
		intent.type = IntentType.UNKNOWN
		intent.description = "观望..."
		return intent

	var total_damage: int = 0
	var total_armor: int = 0
	var total_heal: int = 0
	var total_draw: int = 0
	var has_buff: bool = false
	var has_debuff: bool = false
	var attack_count: int = 0
	var max_single_hit: int = 0

	for card in actions:
		if card.damage > 0:
			var this_dmg: int = card.damage * card.hits
			total_damage += this_dmg
			attack_count += 1
			max_single_hit = maxi(max_single_hit, card.damage)
		if card.armor > 0:
			total_armor += card.armor
		if card.heal > 0:
			total_heal += card.heal
		if card.draw_cards > 0:
			total_draw += card.draw_cards
		if card.grants_charge or card.all_attack_bonus > 0 or card.next_attack_bonus > 0:
			has_buff = true
		if card.enemy_draw_modifier < 0 or card.enemy_energy_modifier < 0:
			has_debuff = true

	# 优先级：伤害 > 治疗 > 防御 > buff > debuff > 抽牌
	if total_damage > 0:
		intent.value = total_damage
		if attack_count > 1:
			intent.type = IntentType.MULTI_ATTACK
			intent.hit_count = attack_count
			intent.description = "多段攻击"
		elif max_single_hit >= 10:
			intent.type = IntentType.HEAVY_ATTACK
			intent.description = "重击来袭"
		else:
			intent.type = IntentType.ATTACK
			intent.description = "攻击"
	elif total_heal > 0:
		intent.type = IntentType.HEAL
		intent.value = total_heal
		intent.description = "自我修复"
	elif total_armor > 0:
		intent.type = IntentType.DEFEND
		intent.value = total_armor
		intent.description = "防御姿态"
	elif has_buff:
		intent.type = IntentType.BUFF
		intent.description = "蓄势增益"
	elif has_debuff:
		intent.type = IntentType.DEBUFF
		intent.description = "干扰协议"
	elif total_draw > 0:
		intent.type = IntentType.DRAW
		intent.value = total_draw
		intent.description = "数据收集"
	else:
		intent.type = IntentType.UNKNOWN
		intent.description = "???"

	return intent


func get_icon() -> String:
	match type:
		IntentType.ATTACK: return "⚔"
		IntentType.HEAVY_ATTACK: return "💀"
		IntentType.MULTI_ATTACK: return "⚔⚔"
		IntentType.DEFEND: return "🛡"
		IntentType.BUFF: return "✨"
		IntentType.DEBUFF: return "⚡"
		IntentType.HEAL: return "✚"
		IntentType.DRAW: return "📋"
		_: return "?"


func get_color() -> Color:
	match type:
		IntentType.ATTACK, IntentType.HEAVY_ATTACK, IntentType.MULTI_ATTACK:
			return Color(1.0, 0.35, 0.3)
		IntentType.DEFEND:
			return Color(0.3, 0.8, 1.0)
		IntentType.BUFF:
			return Color(1.0, 0.8, 0.3)
		IntentType.DEBUFF:
			return Color(0.9, 0.4, 1.0)
		IntentType.HEAL:
			return Color(0.4, 1.0, 0.5)
		IntentType.DRAW:
			return Color(0.7, 0.9, 1.0)
		_:
			return Color(0.6, 0.6, 0.6)


func get_display_text() -> String:
	# 不显示数值，保留博弈性
	return description
