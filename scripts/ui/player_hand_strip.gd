class_name PlayerHandStrip
extends PanelContainer
## 部署阶段底部玩家手牌缩略条
##
## 目的：玩家在部署陷阱时也能一眼扫到自己的手牌组成，
## 因此可以基于"我下回合能打什么"做策略性的陷阱位选择。
##
## 视觉规范：
##   - 紧凑芯片：80×100，每张牌一个，按类型上色
##   - 顶部条：类型缩写 + 能量
##   - 中部：牌名（截断）
##   - 底部：关键数值（伤害/护甲/抽牌等，仅显示最重要那个）
##   - 标记：被 Boss 偷看(👁) / 被锁定(🔒)（GDD 04 信息对称的玩家侧）
##
## 交互：
##   - 悬停芯片：放大 1.1× + 显示完整描述 tooltip
##   - 不响应点击（仅信息展示，避免与 TrapDeployUI 抢输入）
##
## 信号：
##   - hand_card_hovered(card)  — 悬停某张牌时（暂未使用，可用于联动其他 UI）

signal hand_card_hovered(card: CardData)

const TYPE_COLORS := {
	CardData.CardType.ATTACK: Color(0.95, 0.30, 0.30, 1.0),
	CardData.CardType.DEFENSE: Color(0.45, 0.75, 0.95, 1.0),
	CardData.CardType.SKILL: Color(0.40, 0.90, 0.55, 1.0),
	CardData.CardType.PROTOCOL: Color(0.95, 0.78, 0.25, 1.0),
}

const TYPE_SHORT_NAMES := {
	CardData.CardType.ATTACK: "攻",
	CardData.CardType.DEFENSE: "防",
	CardData.CardType.SKILL: "技",
	CardData.CardType.PROTOCOL: "协",
}

# v0.6.0：元素短名（火/水/木）—— 当卡牌带元素时，顶部条优先显示元素
const ELEMENT_SHORT_NAMES := {
	CardData.Element.FIRE: "火",
	CardData.Element.WATER: "水",
	CardData.Element.WOOD: "木",
}

const CHIP_W := 86.0
const CHIP_H := 102.0

var _hand: Array[CardData] = []
# v0.4.3：洞察标记需要外部传入（peeked / disrupted），由场景在 update_hand 时传入
var _peeked_cards: Array[CardData] = []
var _disrupted_cards: Array[CardData] = []

var _title_label: Label
var _chips_container: HBoxContainer
var _empty_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()


func _build_ui() -> void:
	# 背景：玩家主题深青 + 半透明
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.08, 0.88)
	bg.border_color = Color(0.18, 0.55, 0.65, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 12.0
	bg.content_margin_right = 12.0
	bg.content_margin_top = 4.0
	bg.content_margin_bottom = 4.0
	add_theme_stylebox_override("panel", bg)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# 标题
	_title_label = Label.new()
	_title_label.text = "我的\n手牌"
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", Color(0.45, 0.85, 0.95, 1.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.custom_minimum_size = Vector2(70, 0)
	hbox.add_child(_title_label)

	# 竖直分隔线
	var sep := ColorRect.new()
	sep.color = Color(0.18, 0.50, 0.60, 0.6)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(sep)

	# 芯片容器（居中）：让 4 张牌的缩略图始终居于中央
	_chips_container = HBoxContainer.new()
	_chips_container.add_theme_constant_override("separation", 8)
	_chips_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chips_container.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(_chips_container)

	_empty_label = Label.new()
	_empty_label.text = "—— 手牌为空 ——"
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", Color(0.45, 0.55, 0.60))
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	_chips_container.add_child(_empty_label)


## 更新手牌（由 blind_clash_scene 调用）
## peeked / disrupted 可选传入，标记被 Boss 影响的牌
func update_hand(hand: Array[CardData], peeked: Array[CardData] = [], disrupted: Array[CardData] = []) -> void:
	_hand = hand.duplicate()
	_peeked_cards = peeked.duplicate()
	_disrupted_cards = disrupted.duplicate()
	# 更新标题里的张数
	_title_label.text = "我的\n手牌(%d)" % _hand.size()
	_refresh()


func _refresh() -> void:
	for child in _chips_container.get_children():
		if child != _empty_label:
			child.queue_free()

	if _hand.is_empty():
		_empty_label.visible = true
		return
	_empty_label.visible = false

	for card in _hand:
		_chips_container.add_child(_build_chip(card))


func _build_chip(card: CardData) -> Control:
	var is_peeked: bool = _peeked_cards.has(card)
	var is_disrupted: bool = _disrupted_cards.has(card)

	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(CHIP_W, CHIP_H)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = _build_tooltip(card, is_peeked, is_disrupted)

	var sb := StyleBoxFlat.new()
	# v0.6.0：优先用元素色（火/水/木），未带元素的旧卡走类型色
	var col: Color
	var has_element: bool = card.element != CardData.Element.NONE
	if has_element:
		col = ElementVisualHelper.get_element_color(card.element)
	else:
		col = TYPE_COLORS.get(card.type, Color.GRAY)
	# 被锁定的牌：去饱和 + 红边
	if is_disrupted:
		col = col.lerp(Color(0.4, 0.4, 0.4), 0.55)
		sb.border_color = Color(1.0, 0.25, 0.25, 0.95)
		sb.set_border_width_all(2)
	else:
		sb.border_color = col
		sb.set_border_width_all(1)
	sb.bg_color = col * Color(1, 1, 1, 0.85)
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	chip.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 1)
	chip.add_child(vbox)

	# 顶行：v0.6.0 元素短名优先（火/水/木），无元素时回退类型短名（攻/防/技/协）
	#       后接能量；可选光暗符号；可选状态图标
	var header_label_text: String
	if has_element:
		header_label_text = ELEMENT_SHORT_NAMES.get(card.element, "?")
	else:
		header_label_text = TYPE_SHORT_NAMES.get(card.type, "?")
	var top_text: String = "%s · %d" % [header_label_text, card.energy_cost]
	# v0.6.0：光/暗 极性标记（紧跟元素后）
	if card.polarity == CardData.Polarity.LIGHT:
		top_text += " ☀"
	elif card.polarity == CardData.Polarity.DARK:
		top_text += " 🌑"
	if is_peeked:
		top_text = "👁 " + top_text
	if is_disrupted:
		top_text = "🔒 " + top_text
	var top := Label.new()
	top.text = top_text
	top.add_theme_font_size_override("font_size", 12)
	top.add_theme_color_override("font_color", Color(0.05, 0.04, 0.06, 1.0))
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(top)

	# 中行：牌名（自动换行最多 2 行）
	var name_label := Label.new()
	name_label.text = card.card_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.05, 0.04, 0.06, 1.0))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	vbox.add_child(name_label)

	# 底行：关键数值
	var value_text: String = _format_key_value(card)
	if value_text != "":
		var val_label := Label.new()
		val_label.text = value_text
		val_label.add_theme_font_size_override("font_size", 11)
		val_label.add_theme_color_override("font_color", Color(0.08, 0.06, 0.10, 1.0))
		val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(val_label)

	return chip


## 选择牌的"最重要数值"作为芯片底部展示
## 优先级：伤害 > 护甲 > 抽牌 > 回血 > 其他
func _format_key_value(card: CardData) -> String:
	if card.damage > 0:
		var dmg_text: String = "⚔%d" % card.damage
		if card.hits > 1:
			dmg_text += "×%d" % card.hits
		return dmg_text
	if card.armor > 0:
		return "🛡%d" % card.armor
	if card.draw_cards > 0:
		return "✦抽%d" % card.draw_cards
	if card.heal > 0:
		return "❤%d" % card.heal
	if card.gain_constraint_resource > 0:
		return "◆+%d" % card.gain_constraint_resource
	return ""


func _build_tooltip(card: CardData, is_peeked: bool, is_disrupted: bool) -> String:
	var lines: Array[String] = []
	# v0.6.0：tooltip 也优先用元素汉字（火/水/木），加上光/暗
	var head_label: String
	if card.element != CardData.Element.NONE:
		head_label = ElementHelper.element_name(card.element)
		if card.polarity == CardData.Polarity.LIGHT:
			head_label += "·光"
		elif card.polarity == CardData.Polarity.DARK:
			head_label += "·暗"
	else:
		head_label = _get_full_type_name(card.type)
	lines.append("%s [%s · %d能量]" % [
		card.card_name,
		head_label,
		card.energy_cost,
	])
	if card.description != "":
		lines.append(card.description)
	if is_peeked:
		lines.append("⚠ 已被 Boss 偷看")
	if is_disrupted:
		lines.append("⛔ 已被 Boss 锁定 — 下回合不可使用")
	return "\n".join(lines)


func _get_full_type_name(t: int) -> String:
	match t:
		CardData.CardType.ATTACK: return "攻击"
		CardData.CardType.DEFENSE: return "防御"
		CardData.CardType.SKILL: return "技能"
		CardData.CardType.PROTOCOL: return "协议"
	return "?"
