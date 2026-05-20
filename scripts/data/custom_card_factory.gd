class_name CustomCardFactory
extends RefCounted
## 自调升级牌生成工厂（v0.9.4 自调升级牌 PR-2）
##
## 用途：把校验通过的 spec 字典转换为 CardData 实例 + 生成唯一 id + 中文 description
## 配套：调用方应先用 CustomCardValidator.validate() 通过后再调本工厂


## ============================================================
## 公开 API
## ============================================================

## 把 spec 转换为 CardData
## @param spec        合法的 spec 字典（应已通过 CustomCardValidator.validate）
## @param round_index 当前轮次 1~5（id 用）
## @param sequence    本 run 内自调牌序号 0~N（保证 id 唯一）
## @return CardData 新实例（未注册到 CardDatabase；调用方负责注册）
static func build_card_data(spec: Dictionary, round_index: int, sequence: int) -> CardData:
	var card: CardData = CardData.new()

	# id：up_custom_r{N}_{seq}（与固定升级 up_* 同前缀，避开数据库 _reg 冲突）
	card.id = StringName("up_custom_r%d_%d" % [round_index, sequence])

	# 数值字段
	card.damage = int(spec.get("damage", 0))
	card.armor = int(spec.get("armor", 0))
	card.heal = int(spec.get("heal", 0))
	card.energy_cost = int(spec.get("energy_cost", 1))
	card.element = int(spec.get("element", CardData.Element.NONE))
	card.polarity = int(spec.get("polarity", CardData.Polarity.NONE))

	# 附加效果
	card.ignore_armor = bool(spec.get("ignore_armor", false))
	card.draw_cards = int(spec.get("draw_cards", 0))
	card.reflect_damage = int(spec.get("reflect_damage", 0))

	# CardType：根据主数值推断（damage>0=ATTACK / heal>0=SKILL / 否则 DEFENSE）
	if card.damage > 0 and card.damage >= card.armor and card.damage >= card.heal:
		card.type = CardData.CardType.ATTACK
	elif card.heal > 0 and card.heal >= card.armor:
		card.type = CardData.CardType.SKILL
	else:
		card.type = CardData.CardType.DEFENSE

	# 卡名：「自调」+ element + polarity 标签（中文短词）
	card.card_name = _build_name(card)

	# 描述：自动拼接（≤28 字符）
	card.description = _build_description(card)

	return card


## ============================================================
## 内部工具
## ============================================================

static func _build_name(card: CardData) -> String:
	# 元素短名：火/水/木 + 光/暗 + 「协议」
	var elem_str: String = ""
	match card.element:
		CardData.Element.FIRE: elem_str = "火"
		CardData.Element.WATER: elem_str = "水"
		CardData.Element.WOOD: elem_str = "木"
		_: elem_str = "无"
	var pol_str: String = ""
	match card.polarity:
		CardData.Polarity.LIGHT: pol_str = "光"
		CardData.Polarity.DARK: pol_str = "暗"
		_: pol_str = ""
	# 主功能后缀
	var role: String = ""
	if card.damage > 0 and card.damage >= card.armor and card.damage >= card.heal:
		role = "击"
	elif card.heal > 0 and card.heal >= card.armor:
		role = "愈"
	else:
		role = "盾"
	return "%s%s·%s" % [elem_str, pol_str, role]


static func _build_description(card: CardData) -> String:
	# 拼接关键效果，逗号分隔，最多 4 段，控制 ≤ 28 字符
	var parts: Array[String] = []
	if card.damage > 0:
		var dmg_text: String = "%d伤" % card.damage
		if card.ignore_armor:
			dmg_text += "穿甲"
		parts.append(dmg_text)
	if card.armor > 0:
		parts.append("%d甲" % card.armor)
	if card.heal > 0:
		parts.append("%d治" % card.heal)
	if card.draw_cards > 0:
		parts.append("抽%d" % card.draw_cards)
	if card.reflect_damage > 0:
		parts.append("反%d" % card.reflect_damage)

	var desc: String = ", ".join(parts)
	# 软上限 28（中文 1 字符 = 1 width 假设；超长时截断 + …）
	if desc.length() > 28:
		desc = desc.substr(0, 26) + "…"
	return desc
