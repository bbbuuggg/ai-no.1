class_name BossBlindLane
extends PanelContainer
## 部署阶段顶部 Boss 信息栏（v0.5.0 改造）
##
## 设计目标：玩家在部署陷阱时需要"算牌" —— 知道 Boss 手里大概有什么类型，
## 才能合理选择陷阱槽（攻/技/高费）。
##
## 信息构成（左→右）：
##   1. [标题] "BOSS 手牌"
##   2. [类型芯片] 按类型聚合（攻×N / 防×N / 技×N / 协×N），不显示具体牌名（信息对称：玩家不应知道具体是哪张牌）
##   3. [分隔]
##   4. [统计] 手牌总数 / 牌库剩余 / 累计已出
##
## 交互：整条点击 → emit deck_view_requested（外层打开 BossDeckView 完整视图）
##
## 设计原则：
##   - 仅部署阶段显示，紧凑（80px 高），不破坏暗出时序
##   - 类型颜色与 BossDeckView 保持一致（攻红/防青/技绿/协金）
##   - 4 张手牌仅显示"几张攻/几张防/几张技/几张协" → 玩家既能算牌又不会泄露具体牌信息

signal deck_view_requested()

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

# 类型芯片尺寸（紧凑，不抢主舞台）
const CHIP_W := 64.0
const CHIP_H := 56.0

var _hand_cards: Array[CardData] = []
var _total_played: int = 0
var _deck_remaining: int = 0

# 视觉节点
var _title_label: Label
var _chips_container: HBoxContainer
var _stats_label: RichTextLabel
var _empty_label: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "点击查看 Boss 牌库详情"
	_build_ui()
	gui_input.connect(_on_gui_input)


func _build_ui() -> void:
	# 背景：Boss 主题深红 + 半透明
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.06, 0.03, 0.04, 0.88)
	bg.border_color = Color(0.55, 0.18, 0.22, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(6)
	bg.content_margin_left = 12.0
	bg.content_margin_right = 12.0
	bg.content_margin_top = 6.0
	bg.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", bg)

	# 主体水平布局：[标题][芯片区(居中)][分隔][统计]
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(hbox)

	# 标题
	_title_label = Label.new()
	_title_label.text = "BOSS\n手牌"
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.50, 1.0))
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.custom_minimum_size = Vector2(76, 0)
	hbox.add_child(_title_label)

	# 竖直分隔线
	hbox.add_child(_make_vertical_separator())

	# 芯片区（居中）：聚合后的类型分布
	_chips_container = HBoxContainer.new()
	_chips_container.add_theme_constant_override("separation", 8)
	_chips_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chips_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chips_container.alignment = BoxContainer.ALIGNMENT_CENTER  # 居中
	hbox.add_child(_chips_container)

	_empty_label = Label.new()
	_empty_label.text = "Boss 手牌为空"
	_empty_label.add_theme_font_size_override("font_size", 14)
	_empty_label.add_theme_color_override("font_color", Color(0.55, 0.45, 0.48))
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	_chips_container.add_child(_empty_label)

	# 竖直分隔线
	hbox.add_child(_make_vertical_separator())

	# 统计（右侧）
	_stats_label = RichTextLabel.new()
	_stats_label.bbcode_enabled = true
	_stats_label.fit_content = true
	_stats_label.scroll_active = false
	_stats_label.custom_minimum_size = Vector2(180, 0)
	_stats_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stats_label.add_theme_font_size_override("normal_font_size", 12)
	hbox.add_child(_stats_label)


func _make_vertical_separator() -> Control:
	var sep := ColorRect.new()
	sep.color = Color(0.45, 0.20, 0.24, 0.6)
	sep.custom_minimum_size = Vector2(1, 0)
	sep.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return sep


## 更新数据
## @param hand_cards   Boss 当前手牌（用于按类型聚合，不展示具体牌名）
## @param total_played 累计已打出（discard_pile.size()）
## @param deck_remaining 牌库剩余
func update_data(hand_cards: Array[CardData], total_played: int, deck_remaining: int) -> void:
	_hand_cards = hand_cards.duplicate()
	_total_played = total_played
	_deck_remaining = deck_remaining
	_refresh()


func _refresh() -> void:
	# 重建芯片区
	for child in _chips_container.get_children():
		if child != _empty_label:
			child.queue_free()

	# 按类型聚合
	var type_counts: Dictionary = {}  # CardType -> int
	for card in _hand_cards:
		type_counts[card.type] = type_counts.get(card.type, 0) + 1

	if type_counts.is_empty():
		_empty_label.visible = true
	else:
		_empty_label.visible = false
		# 固定顺序：攻 → 防 → 技 → 协（视觉一致性）
		var ordered_types: Array = [
			CardData.CardType.ATTACK,
			CardData.CardType.DEFENSE,
			CardData.CardType.SKILL,
			CardData.CardType.PROTOCOL,
		]
		for t in ordered_types:
			if type_counts.has(t):
				_chips_container.add_child(_build_type_chip(t, type_counts[t]))

	# 统计
	_stats_label.clear()
	_stats_label.append_text("[color=#cccc88]手牌: [b]%d[/b][/color]\n" % _hand_cards.size())
	_stats_label.append_text("[color=#aaccdd]牌库剩余: [b]%d[/b][/color]\n" % _deck_remaining)
	_stats_label.append_text("[color=#dd9999]已出: [b]%d[/b][/color]" % _total_played)


## 按类型聚合的芯片：[类型缩写] × [数量]
func _build_type_chip(card_type: int, count: int) -> Control:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(CHIP_W, CHIP_H)
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.tooltip_text = "Boss 手牌中有 %d 张「%s」类型的牌\n（具体牌名信息不可见）" % [
		count,
		_get_full_type_name(card_type),
	]

	var sb := StyleBoxFlat.new()
	var col: Color = TYPE_COLORS.get(card_type, Color.GRAY)
	sb.bg_color = col * Color(1, 1, 1, 0.85)
	sb.border_color = col
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 3.0
	sb.content_margin_bottom = 3.0
	chip.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_child(vbox)

	# 顶行：类型缩写
	var top := Label.new()
	top.text = TYPE_SHORT_NAMES.get(card_type, "?")
	top.add_theme_font_size_override("font_size", 18)
	top.add_theme_color_override("font_color", Color(0.05, 0.04, 0.06, 1.0))
	top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(top)

	# 底行：×N
	var count_label := Label.new()
	count_label.text = "×%d" % count
	count_label.add_theme_font_size_override("font_size", 14)
	count_label.add_theme_color_override("font_color", Color(0.05, 0.04, 0.06, 1.0))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(count_label)

	return chip


func _get_full_type_name(t: int) -> String:
	match t:
		CardData.CardType.ATTACK: return "攻击"
		CardData.CardType.DEFENSE: return "防御"
		CardData.CardType.SKILL: return "技能"
		CardData.CardType.PROTOCOL: return "协议"
	return "?"


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			deck_view_requested.emit()
			accept_event()
