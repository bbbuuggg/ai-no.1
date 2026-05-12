extends Control
## 层间奖励界面 — 击败 Boss 后三选一加牌

signal card_chosen(card: CardData)
signal skipped()

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var cards_container: HBoxContainer = $Panel/VBox/CardsContainer
@onready var skip_btn: Button = $Panel/VBox/SkipButton

var _available_cards: Array[CardData] = []


func _ready() -> void:
	skip_btn.pressed.connect(func(): skipped.emit(); visible = false)
	visible = false


func show_rewards(cards: Array[CardData], round_num: int = 1) -> void:
	_available_cards = cards
	title_label.text = "选择奖励 (%d/2)" % round_num
	_populate_cards()
	visible = true


func _populate_cards() -> void:
	for child in cards_container.get_children():
		child.queue_free()

	for card in _available_cards:
		var card_panel := PanelContainer.new()
		card_panel.custom_minimum_size = Vector2(180, 220)

		var vbox := VBoxContainer.new()
		card_panel.add_child(vbox)

		# 类型标签
		var type_label := Label.new()
		var type_colors: Dictionary = {
			CardData.CardType.ATTACK: "red",
			CardData.CardType.DEFENSE: "cyan",
			CardData.CardType.SKILL: "green",
			CardData.CardType.PROTOCOL: "yellow",
		}
		var type_names: Dictionary = {
			CardData.CardType.ATTACK: "攻击",
			CardData.CardType.DEFENSE: "防御",
			CardData.CardType.SKILL: "技能",
			CardData.CardType.PROTOCOL: "协议",
		}
		type_label.text = type_names.get(card.type, "?")
		type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		type_label.add_theme_font_size_override("font_size", 11)
		vbox.add_child(type_label)

		# 名称
		var name_label := Label.new()
		name_label.text = card.card_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 16)
		vbox.add_child(name_label)

		# 能量
		var cost_label := Label.new()
		cost_label.text = "能量: %d" % card.energy_cost
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(cost_label)

		# 分隔
		var sep := HSeparator.new()
		vbox.add_child(sep)

		# 效果描述
		var desc_label := Label.new()
		desc_label.text = card.description
		desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_label)

		# 选择按钮
		var btn := Button.new()
		btn.text = "选择"
		btn.size_flags_vertical = Control.SIZE_SHRINK_END
		btn.pressed.connect(_on_card_selected.bind(card))
		vbox.add_child(btn)

		cards_container.add_child(card_panel)


func _on_card_selected(card: CardData) -> void:
	card_chosen.emit(card)
	visible = false
