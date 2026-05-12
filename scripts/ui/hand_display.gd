extends Control
## 扇形手牌布局容器

signal card_played(card: CardData)

const CardUI := preload("res://scripts/ui/card_ui.gd")

var _cards: Array[Control] = []
var fan_angle: float = 3.5
var fan_radius: float = 1400.0
var card_spacing: float = 150.0


func clear_hand() -> void:
	for child in get_children():
		child.queue_free()
	_cards.clear()


func display_hand(hand: Array[CardData]) -> void:
	clear_hand()
	var count: int = hand.size()
	if count == 0:
		return

	for i in range(count):
		var card_ui := Control.new()
		card_ui.set_script(CardUI)
		card_ui.setup(hand[i])
		card_ui.card_clicked.connect(_on_card_clicked)
		add_child(card_ui)
		_cards.append(card_ui)

	# 延迟一帧确保节点就绪后布局
	await get_tree().process_frame
	_layout_fan()


func _layout_fan() -> void:
	var count: int = _cards.size()
	if count == 0:
		return

	var total_width: float = (count - 1) * card_spacing
	var start_x: float = (size.x - total_width) / 2.0
	var center_idx: float = (count - 1) / 2.0

	for i in range(count):
		var card: Control = _cards[i]
		# 水平位置
		var x: float = start_x + i * card_spacing
		# 垂直弧度偏移（中间高两边低）
		var y_offset: float = abs(i - center_idx) * 8.0
		# 扇形角度
		var angle_offset: float = (i - center_idx) * fan_angle

		var pos := Vector2(x, y_offset)
		card.set_base_position(pos)
		card.rotation_degrees = angle_offset


func _on_card_clicked(card: CardData) -> void:
	card_played.emit(card)
