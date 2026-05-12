extends Control
## 约束令卡牌 UI — 与手牌风格统一，紫色标识，带"保留"标记

signal constraint_clicked(constraint: ConstraintData)

const CARD_WIDTH := 150
const CARD_HEIGHT := 220
const HOVER_SCALE := 1.25
const NORMAL_SCALE := 1.0
const HOVER_LIFT := 30.0

const CONSTRAINT_COLOR := Color(0.7, 0.3, 1.0, 1.0)  # 紫色
const DISABLED_COLOR := Color(0.4, 0.4, 0.4, 1.0)

var constraint_data: ConstraintData
var is_usable: bool = true
var _is_hovered: bool = false
var _base_position: Vector2 = Vector2.ZERO
var _position_stored: bool = false


func setup(data: ConstraintData, usable: bool) -> void:
	constraint_data = data
	is_usable = usable
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	pivot_offset = Vector2(CARD_WIDTH / 2.0, CARD_HEIGHT / 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	queue_redraw()


func _draw() -> void:
	if constraint_data == null:
		return

	var rect := Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, CARD_HEIGHT))
	var accent: Color = CONSTRAINT_COLOR if is_usable else DISABLED_COLOR

	# 卡背
	var bg_color := Color(0.06, 0.04, 0.1, 0.95)
	draw_rect(rect, bg_color, true)

	# 边框
	var border: Color = accent if _is_hovered else accent * 0.7
	draw_rect(rect, border, false, 2.0)

	# 顶部"保留"标记条
	var top_bar := Rect2(0, 0, CARD_WIDTH, 28)
	draw_rect(top_bar, accent * 0.3, true)
	draw_string(ThemeDB.fallback_font, Vector2(8, 20), "保留 ◆%d" % constraint_data.resource_cost, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 16, 14, accent)

	# 卡名
	var name_color: Color = Color.WHITE if is_usable else DISABLED_COLOR
	draw_string(ThemeDB.fallback_font, Vector2(8, 60), constraint_data.constraint_name, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 16, 18, name_color)

	# 分隔线
	draw_line(Vector2(10, 70), Vector2(CARD_WIDTH - 10, 70), accent * 0.4, 1.0)

	# 效果描述（自动换行）
	var desc: String = constraint_data.description
	var lines: Array[String] = _wrap_text(desc, 12)
	var y: float = 92.0
	var desc_color: Color = Color(0.75, 0.7, 0.9) if is_usable else DISABLED_COLOR
	for line in lines:
		draw_string(ThemeDB.fallback_font, Vector2(8, y), line, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 16, 13, desc_color)
		y += 18.0

	# 持续回合
	if constraint_data.duration > 0:
		var dur_text: String = "持续 %d 回合" % constraint_data.duration
		draw_string(ThemeDB.fallback_font, Vector2(8, CARD_HEIGHT - 14), dur_text, HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 16, 12, accent * 0.8)
	elif constraint_data.duration == 0:
		draw_string(ThemeDB.fallback_font, Vector2(8, CARD_HEIGHT - 14), "即时", HORIZONTAL_ALIGNMENT_LEFT, CARD_WIDTH - 16, 12, accent * 0.8)


func _wrap_text(text: String, chars_per_line: int) -> Array[String]:
	var lines: Array[String] = []
	var remaining: String = text
	while remaining.length() > chars_per_line:
		lines.append(remaining.substr(0, chars_per_line))
		remaining = remaining.substr(chars_per_line)
	if remaining.length() > 0:
		lines.append(remaining)
	return lines


func _gui_input(event: InputEvent) -> void:
	pass


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if _is_hovered and is_usable:
				constraint_clicked.emit(constraint_data)
				get_viewport().set_input_as_handled()


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)


func _process(_delta: float) -> void:
	if constraint_data == null:
		return
	if not _position_stored:
		_base_position = position
		_position_stored = true
	var mouse_pos_global: Vector2 = get_global_mouse_position()
	var visual_rect := _get_visual_rect_global()
	var should_hover: bool = visual_rect.has_point(mouse_pos_global)
	if should_hover != _is_hovered:
		_is_hovered = should_hover
		if is_usable:
			_animate_hover(should_hover)
		queue_redraw()


func _get_visual_rect_global() -> Rect2:
	var target_scale: float = HOVER_SCALE if _is_hovered else NORMAL_SCALE
	var scaled_size: Vector2 = size * target_scale
	var center: Vector2 = global_position + size / 2.0
	var lift_offset: float = -HOVER_LIFT if _is_hovered else 0.0
	center.y += lift_offset / 2.0
	var top_left: Vector2 = center - scaled_size / 2.0
	return Rect2(top_left - Vector2(4, 4), scaled_size + Vector2(8, 8))


func _animate_hover(hover: bool) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	if hover:
		tween.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), 0.12)
		tween.parallel().tween_property(self, "position", _base_position + Vector2(0, -HOVER_LIFT), 0.12)
		z_index = 10
	else:
		tween.tween_property(self, "scale", Vector2(NORMAL_SCALE, NORMAL_SCALE), 0.12)
		tween.parallel().tween_property(self, "position", _base_position, 0.12)
		z_index = 0
