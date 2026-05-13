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
# v0.4.3 被偷看的牌（玩家可见持续标记，仅视觉）
var _peeked_cards: Array[CardData] = []
# v0.4.3 toast 文案恢复定时器（reject 抖动时使用）
var _info_restore_tween: Tween = null

# 扇形布局参数
const HAND_SPACING: float = 130.0
const HAND_ARC_HEIGHT: float = 8.0
const HAND_FAN_ANGLE: float = 3.0
# v0.4.2：手牌基线 y（中央卡左上角在 HandArea 内的 y 坐标）。
# HandArea 高 400px，卡牌高 280px，要求卡牌底端不超过 HandArea 底部（否则被 clip_contents 裁掉）。
# 中央卡贴底：HAND_BASE_Y = 400 - 280 = 120 → 卡底刚好贴 HandArea 底（全局 y≈804）。
# Hover 上抬 ≈ 85px（HOVER_LIFT 50 + 缩放 1.25 倍向上扩 35），视觉顶 ≈ 120-85 = 35（仍在 HandArea 内）。
# 两端最大上凸 24px（7 张牌时），y_min = 96，底端 376（在 HandArea 内）。
const HAND_BASE_Y: float = 120.0

@onready var hand_area: Control = $VBox/HandArea
# v0.4.2：BlindArea 改成 Control 外壳（固定 240px 高，clip_contents），
# 真正排列暗出牌的 HBoxContainer 是它内部的 BlindRow（anchors_preset=15 撑满）。
# 这样无论暗出区子节点如何变化，都不会撑高外层 VBox，导致下方 InfoBar 跳动。
@onready var blind_area: HBoxContainer = $VBox/BlindArea/BlindRow
@onready var info_label: Label = $VBox/InfoBar/InfoLabel
@onready var energy_label: Label = $VBox/InfoBar/EnergyLabel
@onready var confirm_btn: Button = $VBox/InfoBar/ConfirmBtn
@onready var clear_btn: Button = $VBox/InfoBar/ClearBtn


func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	clear_btn.pressed.connect(_on_clear_all)
	_update_info()


func activate(hand: Array[CardData], energy: int, disrupted: Array[CardData], peeked: Array[CardData] = []) -> void:
	_is_active = true
	_player_energy = energy
	_disrupted_cards = disrupted.duplicate()
	_peeked_cards = peeked.duplicate()
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
		# 扇形位置：以 HAND_BASE_Y 为中央卡基线，两端向上略凸（中央最低 → 贴底）
		var x: float = start_x + i * HAND_SPACING
		var y: float = HAND_BASE_Y - abs(i - center_idx) * HAND_ARC_HEIGHT
		var angle: float = (i - center_idx) * HAND_FAN_ANGLE
		var base_pos := Vector2(x, y)

		var card_ui := Control.new()
		card_ui.set_script(CardUI)
		card_ui.setup(hand[i], base_pos)
		card_ui.rotation_degrees = angle
		card_ui.card_clicked.connect(_on_hand_card_clicked)
		# v0.4.3：disrupted_click_rejected 在 card_ui 自吃点击时 emit
		if card_ui.has_signal("disrupted_click_rejected"):
			card_ui.disrupted_click_rejected.connect(_on_hand_card_disrupt_rejected)
		hand_area.add_child(card_ui)
		_hand_cards.append(card_ui)

		# v0.4.3：标记被干扰的牌（红锁链 + 灰度 + 禁用点击由 card_ui 自身处理）
		if _disrupted_cards.has(hand[i]):
			card_ui.set_disrupted(true)
		# v0.4.3：标记被偷看的牌（青色眼睛 + 扫描光晕，不影响点击）
		if _peeked_cards.has(hand[i]):
			card_ui.set_peeked(true)


func _on_hand_card_clicked(card: CardData) -> void:
	if not _is_active:
		return
	if _disrupted_cards.has(card):
		# v0.4.3：保险兜底（card_ui 已自吃点击，正常不会进这里）
		_show_disrupt_toast(card)
		return

	# 0费牌 → 必须绑定到一张主牌上（GDD 04 §2.5 §5.1：0费牌不独立参与碰撞）
	# 一张主牌最多绑 1 张 0 费；无主牌或都绑满时，0 费牌选不进暗出区。
	if card.energy_cost == 0:
		if _blind_slots.is_empty():
			# 无主牌 → 不能独立暗出，提示玩家先选一张主牌
			_show_zero_bind_reject_toast(card, "请先选一张主牌（≥1费）再绑定 0 费牌")
			return
		var bind_idx: int = _find_bindable_slot()
		if bind_idx < 0:
			# 暗出区只有 0 费牌（理论上不会出现，因为上面已挡住），保险兜底
			_show_zero_bind_reject_toast(card, "需要至少一张 ≥1费 主牌作为绑定对象")
			return
		if _bound_zeros.has(bind_idx):
			# 已经绑过 → 提示"每张主牌最多绑 1 张 0 费"
			_show_zero_bind_reject_toast(card, "每张主牌最多绑定 1 张 0 费牌")
			return
		# 合法绑定
		_bound_zeros[bind_idx] = card
		_remove_from_hand(card)
		_refresh_blind_area()
	else:
		# 普通牌 → 检查能量
		if _total_energy_used + card.energy_cost > _player_energy:
			_show_zero_bind_reject_toast(card, "能量不足，无法选入此牌")
			return
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
		var y: float = HAND_BASE_Y - abs(i - center_idx) * HAND_ARC_HEIGHT
		var angle: float = (i - center_idx) * HAND_FAN_ANGLE

		card_ui.position = Vector2(x, y)
		card_ui.set_base_position(Vector2(x, y))
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
		card_ui.disable_hover()  # 暗出区由容器管理位置，禁用hover动画
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
	if card_ui.has_signal("disrupted_click_rejected"):
		card_ui.disrupted_click_rejected.connect(_on_hand_card_disrupt_rejected)
	# v0.4.3：退回手牌时恢复 peek 持续标记（disrupted 牌从未被选入，不需考虑）
	if _peeked_cards.has(card):
		card_ui.set_peeked(true)
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
	# v0.4.3 hotfix-4：明确 0 费牌必须绑定到主牌（GDD 规则）
	info_label.text = "暗出 %d 张牌 | 点击手牌选入；0费牌自动绑定到上一张主牌（每张主牌最多绑 1 张）" % _blind_slots.size()
	confirm_btn.disabled = false  # 允许出0张（放弃行动）


# v0.4.3：被干扰的牌点击反馈 — InfoLabel 闪红字 1.0s 后还原
func _on_hand_card_disrupt_rejected(card: CardData) -> void:
	_show_disrupt_toast(card)


func _show_disrupt_toast(card: CardData) -> void:
	if card == null:
		return
	if _info_restore_tween != null and _info_restore_tween.is_valid():
		_info_restore_tween.kill()
	var name_text: String = card.card_name if card != null else "?"
	info_label.text = "⛓ 已封印 — %s 本回合不可使用" % name_text
	info_label.add_theme_color_override("font_color", Color(1.0, 0.16, 0.16))
	_info_restore_tween = create_tween()
	_info_restore_tween.tween_interval(1.0)
	_info_restore_tween.tween_callback(func() -> void:
		info_label.remove_theme_color_override("font_color")
		_update_info()
	)


# v0.4.3 hotfix-4：0费牌违规绑定时的 toast（金黄色提示，1.2s 后还原 InfoLabel）
func _show_zero_bind_reject_toast(card: CardData, reason: String) -> void:
	if _info_restore_tween != null and _info_restore_tween.is_valid():
		_info_restore_tween.kill()
	var card_name: String = card.card_name if card != null else "0费牌"
	info_label.text = "⚠ %s — %s" % [card_name, reason]
	info_label.add_theme_color_override("font_color", Color(1.0, 0.78, 0.18))
	_info_restore_tween = create_tween()
	_info_restore_tween.tween_interval(1.2)
	_info_restore_tween.tween_callback(func() -> void:
		info_label.remove_theme_color_override("font_color")
		_update_info()
	)
