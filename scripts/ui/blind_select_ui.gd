extends Control
## 暗出选牌区域 — 玩家从手牌中选择牌并排列暗出顺序
## 支持：选牌、排列顺序、0费牌绑定

signal blind_confirmed(cards: Array[CardData], bound_zeros: Dictionary)
signal card_selected(card: CardData)
signal card_deselected(card: CardData)

const CardUI := preload("res://scripts/ui/card_ui.gd")

# 手牌区域
var _hand_cards: Array[Control] = []
# 暗出区域（已选牌，按顺序排列）
var _blind_slots: Array[CardData] = []
var _blind_slot_uis: Array[Control] = []
# 0费绑定
var _bound_zeros: Dictionary = {}  # {slot_index: CardData}

# 状态
var _player_energy: int = 3
var _total_energy_used: int = 0
var _is_active: bool = false
# 被干扰不可用的牌
var _disrupted_cards: Array[CardData] = []

# 扇形布局参数
const HAND_SPACING: float = 130.0
const HAND_ARC_HEIGHT: float = 8.0
const HAND_FAN_ANGLE: float = 3.0

@onready var hand_area: Control = $VBox/HandArea
@onready var blind_area: HBoxContainer = $VBox/BlindArea
@onready var info_label: Label = $VBox/InfoBar/InfoLabel
@onready var energy_label: Label = $VBox/InfoBar/EnergyLabel
@onready var confirm_btn: Button = $VBox/InfoBar/ConfirmBtn
@onready var clear_btn: Button = $VBox/InfoBar/ClearBtn


func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	clear_btn.pressed.connect(_on_clear_all)
	_update_info()


func activate(hand: Array[CardData], energy: int, disrupted: Array[CardData]) -> void:
	_is_active = true
	_player_energy = energy
	_disrupted_cards = disrupted.duplicate()
	_blind_slots.clear()
	_bound_zeros.clear()
	_total_energy_used = 0
	_display_hand(hand)
	_refresh_blind_area()
	_update_info()
	visible = true
	confirm_btn.disabled = false


func deactivate() -> void:
	_is_active = false
	visible = false


func _display_hand(hand: Array[CardData]) -> void:
	# 清空手牌区域
	for child in hand_area.get_children():
		child.queue_free()
	_hand_cards.clear()

	var count: int = hand.size()
	if count == 0:
		return

	# 手动扇形布局（避免容器自动布局与card_ui._process冲突）
	var area_width: float = hand_area.size.x if hand_area.size.x > 0 else 1200.0
	var total_width: float = (count - 1) * HAND_SPACING
	var start_x: float = (area_width - total_width) / 2.0
	var center_idx: float = (count - 1) / 2.0

	for i in range(count):
		# 扇形位置
		var x: float = start_x + i * HAND_SPACING
		var y_offset: float = abs(i - center_idx) * HAND_ARC_HEIGHT
		var angle: float = (i - center_idx) * HAND_FAN_ANGLE
		var base_pos := Vector2(x, y_offset)

		var card_ui := Control.new()
		card_ui.set_script(CardUI)
		card_ui.setup(hand[i], base_pos)
		card_ui.rotation_degrees = angle
		card_ui.card_clicked.connect(_on_hand_card_clicked)
		hand_area.add_child(card_ui)
		_hand_cards.append(card_ui)

		# 标记被干扰的牌
		if _disrupted_cards.has(hand[i]):
			card_ui.modulate = Color(0.4, 0.4, 0.4, 0.7)


func _on_hand_card_clicked(card: CardData) -> void:
	if not _is_active:
		return
	if _disrupted_cards.has(card):
		return  # 被干扰牌不可用

	# 0费牌 → 尝试绑定到最后一个暗出槽
	if card.energy_cost == 0:
		if _blind_slots.is_empty():
			# 没有主牌，0费牌也可以独立暗出（不消耗能量）
			_add_to_blind(card)
		else:
			# 绑定到最后一个非0费暗出牌
			var bind_idx: int = _find_bindable_slot()
			if bind_idx >= 0 and not _bound_zeros.has(bind_idx):
				_bound_zeros[bind_idx] = card
				_remove_from_hand(card)
				_refresh_blind_area()
			else:
				# 没有可绑定的或已绑满，独立暗出
				_add_to_blind(card)
	else:
		# 普通牌 → 检查能量
		if _total_energy_used + card.energy_cost > _player_energy:
			return  # 能量不够
		_add_to_blind(card)

	_update_info()
	card_selected.emit(card)


func _add_to_blind(card: CardData) -> void:
	_blind_slots.append(card)
	_total_energy_used += card.energy_cost
	_remove_from_hand(card)
	_refresh_blind_area()


func _remove_from_hand(card: CardData) -> void:
	for ui in _hand_cards:
		if ui.card_data == card:
			ui.queue_free()
			_hand_cards.erase(ui)
			break
	# 重新布局剩余手牌
	_relayout_hand()


func _relayout_hand() -> void:
	## 手动扇形重新布局当前手牌
	var count: int = _hand_cards.size()
	if count == 0:
		return

	var area_width: float = hand_area.size.x if hand_area.size.x > 0 else 1200.0
	var total_width: float = (count - 1) * HAND_SPACING
	var start_x: float = (area_width - total_width) / 2.0
	var center_idx: float = (count - 1) / 2.0

	for i in range(count):
		var card_ui: Control = _hand_cards[i]
		var x: float = start_x + i * HAND_SPACING
		var y_offset: float = abs(i - center_idx) * HAND_ARC_HEIGHT
		var angle: float = (i - center_idx) * HAND_FAN_ANGLE

		card_ui.position = Vector2(x, y_offset)
		card_ui.set_base_position(Vector2(x, y_offset))
		card_ui.rotation_degrees = angle


func _find_bindable_slot() -> int:
	## 找到最后一个能量>0的暗出牌（可绑定0费）
	for i in range(_blind_slots.size() - 1, -1, -1):
		if _blind_slots[i].energy_cost > 0:
			return i
	return -1


func _refresh_blind_area() -> void:
	for child in blind_area.get_children():
		child.queue_free()
	_blind_slot_uis.clear()

	for i in range(_blind_slots.size()):
		var slot_container := VBoxContainer.new()
		slot_container.custom_minimum_size = Vector2(140, 240)

		# 序号标签
		var idx_label := Label.new()
		idx_label.text = "#%d" % (i + 1)
		idx_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		idx_label.add_theme_font_size_override("font_size", 16)
		idx_label.add_theme_color_override("font_color", Color(0.0, 0.85, 1.0))
		slot_container.add_child(idx_label)

		# 主牌显示
		var card_ui := Control.new()
		card_ui.set_script(CardUI)
		card_ui.setup(_blind_slots[i])
		card_ui.card_clicked.connect(_on_blind_card_clicked)
		slot_container.add_child(card_ui)

		# 阴影标记（暗出区辨别用）
		var shadow := ColorRect.new()
		shadow.custom_minimum_size = Vector2(140, 6)
		shadow.color = Color(0.0, 0.6, 1.0, 0.5)
		slot_container.add_child(shadow)

		# 绑定0费牌标签
		if _bound_zeros.has(i):
			var bind_label := Label.new()
			bind_label.text = "+ %s" % _bound_zeros[i].card_name
			bind_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			bind_label.add_theme_font_size_override("font_size", 13)
			bind_label.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
			slot_container.add_child(bind_label)

		blind_area.add_child(slot_container)
		_blind_slot_uis.append(slot_container)


func _on_blind_card_clicked(card: CardData) -> void:
	## 点击暗出区的牌 → 退回手牌
	if not _is_active:
		return

	var idx: int = _blind_slots.find(card)
	if idx < 0:
		return

	# 如果有绑定的0费牌也退回
	if _bound_zeros.has(idx):
		var zero_card: CardData = _bound_zeros[idx]
		_bound_zeros.erase(idx)
		_return_to_hand(zero_card)

	_blind_slots.remove_at(idx)
	_total_energy_used -= card.energy_cost
	_return_to_hand(card)

	# 重建索引（绑定映射需要更新）
	var new_bounds: Dictionary = {}
	for key in _bound_zeros:
		if key > idx:
			new_bounds[key - 1] = _bound_zeros[key]
		else:
			new_bounds[key] = _bound_zeros[key]
	_bound_zeros = new_bounds

	_refresh_blind_area()
	_update_info()
	card_deselected.emit(card)


func _return_to_hand(card: CardData) -> void:
	var card_ui := Control.new()
	card_ui.set_script(CardUI)
	card_ui.setup(card)
	card_ui.card_clicked.connect(_on_hand_card_clicked)
	hand_area.add_child(card_ui)
	_hand_cards.append(card_ui)
	# 重新布局所有手牌
	_relayout_hand()


func _on_confirm() -> void:
	if not _is_active:
		return
	var cards: Array[CardData] = _blind_slots.duplicate()
	blind_confirmed.emit(cards, _bound_zeros.duplicate())
	deactivate()


func _on_clear_all() -> void:
	# 全部退回手牌
	while not _blind_slots.is_empty():
		var card: CardData = _blind_slots.pop_back()
		_total_energy_used -= card.energy_cost
		_return_to_hand(card)
	for key in _bound_zeros:
		_return_to_hand(_bound_zeros[key])
	_bound_zeros.clear()
	_refresh_blind_area()
	_update_info()


func _update_info() -> void:
	var remaining_energy: int = _player_energy - _total_energy_used
	energy_label.text = "能量: %d/%d" % [remaining_energy, _player_energy]
	info_label.text = "暗出 %d 张牌 | 点击手牌选入，点击暗出区退回" % _blind_slots.size()
	confirm_btn.disabled = false  # 允许出0张（放弃行动）
