extends Control
## 单张卡牌 UI 组件 — 卡面直接显示效果，hover 放大

signal card_clicked(card: CardData)

const CARD_WIDTH := 200
const CARD_HEIGHT := 280
const HOVER_SCALE := 1.25
const NORMAL_SCALE := 1.0
const HOVER_LIFT := 50.0

var card_data: CardData
var _is_hovered: bool = false
var _base_position: Vector2 = Vector2.ZERO
var _position_stored: bool = false

# 颜色映射
const TYPE_COLORS := {
	0: Color(0.9, 0.2, 0.2, 1.0),   # ATTACK - 红
	1: Color(0.2, 0.7, 0.9, 1.0),   # DEFENSE - 青
	2: Color(0.2, 0.9, 0.4, 1.0),   # SKILL - 绿
	3: Color(0.9, 0.75, 0.1, 1.0),  # PROTOCOL - 金
}

const TYPE_NAMES := {
	0: "攻击",
	1: "防御",
	2: "技能",
	3: "协议",
}


func setup(data: CardData, base_pos: Vector2 = Vector2.ZERO) -> void:
	card_data = data
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	pivot_offset = Vector2(CARD_WIDTH / 2.0, CARD_HEIGHT / 2.0)  # 中心缩放
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	# 显式初始化基准位置
	_base_position = base_pos
	_position_stored = true
	position = base_pos
	# 初始绘制
	queue_redraw()


func _draw() -> void:
	if card_data == null:
		return

	var rect := Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, CARD_HEIGHT))
	var type_color: Color = TYPE_COLORS.get(card_data.type, Color.WHITE)

	# 卡背
	var bg_color := Color(0.08, 0.1, 0.14, 0.95)
	draw_rect(rect, bg_color, true)

	# 边框
	var border_color := type_color * 0.8
	if _is_hovered:
		border_color = type_color
	draw_rect(rect, border_color, false, 2.0)

	# 顶部类型条
	var type_bar := Rect2(0, 0, CARD_WIDTH, 32)
	draw_rect(type_bar, type_color * 0.3, true)

	# 类型文字 + 能量
	var type_text: String = TYPE_NAMES.get(card_data.type, "?")
	var header_text: String = "%s   ◆%d" % [type_text, card_data.energy_cost]
	draw_string(ThemeDB.fallback_font, Vector2(10, 23), header_text, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 20, 15, type_color)

	# 卡名
	draw_string(ThemeDB.fallback_font, Vector2(10, 64), card_data.card_name, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 20, 20, Color.WHITE)

	# 分隔线
	draw_line(Vector2(12, 76), Vector2(CARD_WIDTH - 12, 76), type_color * 0.5, 1.0)

	# 效果文本（多行）
	var effect_lines: Array[String] = _get_effect_lines()
	var y_offset: float = 98.0
	for line in effect_lines:
		draw_string(ThemeDB.fallback_font, Vector2(10, y_offset), line, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 20, 14, Color(0.8, 0.85, 0.9))
		y_offset += 20.0


func _get_effect_lines() -> Array[String]:
	var lines: Array[String] = []
	if card_data.damage > 0:
		var dmg_text: String = "伤害 %d" % card_data.damage
		if card_data.hits > 1:
			dmg_text += " ×%d" % card_data.hits
		if card_data.ignore_armor:
			dmg_text += " (穿甲)"
		lines.append(dmg_text)
	if card_data.armor > 0:
		lines.append("护甲 +%d" % card_data.armor)
	if card_data.heal > 0:
		lines.append("回复 %d" % card_data.heal)
	if card_data.draw_cards > 0:
		lines.append("抽 %d 张牌" % card_data.draw_cards)
	if card_data.grants_charge:
		lines.append("进入蓄力状态")
	if card_data.requires_charge:
		lines.append("需要: 蓄力")
	if card_data.next_attack_bonus > 0:
		lines.append("下次攻击 +%d" % card_data.next_attack_bonus)
	if card_data.all_attack_bonus > 0:
		lines.append("本回合攻击 +%d" % card_data.all_attack_bonus)
	if card_data.energy_next_turn > 0:
		lines.append("下回合能量 +%d" % card_data.energy_next_turn)
	if card_data.enemy_draw_modifier < 0:
		lines.append("对手抽牌 %d" % card_data.enemy_draw_modifier)
	if card_data.enemy_energy_modifier < 0:
		lines.append("对手能量 %d" % card_data.enemy_energy_modifier)
	if card_data.discard_hand_and_draw > 0:
		lines.append("弃全部手牌抽 %d" % card_data.discard_hand_and_draw)
	if card_data.gain_constraint_resource > 0:
		lines.append("约束资源 +%d" % card_data.gain_constraint_resource)
	if lines.is_empty():
		lines.append(card_data.description)
	return lines


func _gui_input(event: InputEvent) -> void:
	# 不再依赖 _gui_input，改为在 _process 中处理全局鼠标事件
	pass


func _input(event: InputEvent) -> void:
	if not _position_stored:
		return
	if not is_visible_in_tree():
		return  # 自己或父节点不可见时不响应
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# 实时检查鼠标是否真的在此卡牌视觉区域内
			var mouse_pos: Vector2 = get_global_mouse_position()
			if _get_visual_rect_global().has_point(mouse_pos):
				card_clicked.emit(card_data)
				get_viewport().set_input_as_handled()


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)


func _process(_delta: float) -> void:
	if card_data == null:
		return
	if not _position_stored:
		# 未被外部设置 base_position，暂不启用 hover 追踪（避免跳到0,0）
		return
	# 自己判断鼠标是否在卡牌视觉区域内
	var mouse_pos_global: Vector2 = get_global_mouse_position()
	var visual_rect := _get_visual_rect_global()
	var should_hover: bool = visual_rect.has_point(mouse_pos_global)
	if should_hover != _is_hovered:
		_is_hovered = should_hover
		_animate_hover(should_hover)
		queue_redraw()


func _get_visual_rect_global() -> Rect2:
	# 视觉区域 = 以当前 position 为起点 + size × scale
	# 由于 pivot 在中心，缩放以中心扩展
	var target_scale: float = HOVER_SCALE if _is_hovered else NORMAL_SCALE
	# 使用稳定的比例避免动画中间态抖动
	var scaled_size: Vector2 = size * target_scale
	var center: Vector2 = global_position + size / 2.0
	# 考虑 hover 时的位置抬升
	var lift_offset: float = -HOVER_LIFT if _is_hovered else 0.0
	center.y += lift_offset / 2.0  # 视觉中心会跟着动画移动，这里做近似补偿
	var top_left: Vector2 = center - scaled_size / 2.0
	# 稍微扩大一点防止边界抖动
	return Rect2(top_left - Vector2(4, 4), scaled_size + Vector2(8, 8))


func set_base_position(pos: Vector2) -> void:
	_base_position = pos
	_position_stored = true
	position = pos


func _animate_hover(hover: bool) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	if hover:
		tween.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), 0.15)
		tween.parallel().tween_property(self, "position", _base_position + Vector2(0, -HOVER_LIFT), 0.15)
		z_index = 10
	else:
		tween.tween_property(self, "scale", Vector2(NORMAL_SCALE, NORMAL_SCALE), 0.15)
		tween.parallel().tween_property(self, "position", _base_position, 0.15)
		z_index = 0
