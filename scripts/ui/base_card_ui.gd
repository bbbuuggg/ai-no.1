class_name BaseCardUI
extends Control
## 卡片 UI 基类 — 抽象所有卡片类型共用的布局骨架、悬浮动效、点击判定
##
## 设计来源：docs/design/ 约束令/陷阱/手牌统一视觉语言（由 art-director 评审）
## 子类职责：覆盖 _draw_card_front() 渲染自己的卡面内容（主色、图腾、文字）
## 基类职责：
##   - 固定卡片尺寸与 pivot（中心缩放）
##   - 悬浮放大 + 上抬 tween（可被 disable_hover 关闭）
##   - 选中脉冲动效（供"待放置"等状态使用）
##   - 鼠标 hit 判定矩形（滞后阈值防抖）
##   - 基础卡背/卡面/顶部标记条/分隔线等共用绘制工具
##
## 子类必须实现：
##   - _draw_card_front(rect: Rect2, accent: Color) -> void
##   - get_accent_color() -> Color
##
## 子类可选覆盖：
##   - _is_card_usable() -> bool   # 影响禁用态绘制
##   - _on_selected_changed(selected: bool)  # 状态回调

# ------------------------------------------------------------------
# 常量 —— 整套卡片生态统一使用（尺寸/动效/阈值）
# ------------------------------------------------------------------
const CARD_WIDTH := 150
const CARD_HEIGHT := 220
const HOVER_SCALE := 1.25
const NORMAL_SCALE := 1.0
const HOVER_LIFT := 30.0
const HOVER_TWEEN_SEC := 0.12

# 选中脉冲（待放置等状态）
const SELECT_PULSE_SEC := 0.8
const SELECT_SCALE := 1.1

# 禁用态颜色
const DISABLED_COLOR := Color(0.4, 0.4, 0.4, 1.0)

# 通用暗色卡背
const BG_COLOR_DEFAULT := Color(0.06, 0.04, 0.1, 0.95)

# ------------------------------------------------------------------
# 状态
# ------------------------------------------------------------------
var _is_hovered: bool = false
var _is_selected: bool = false
var _base_position: Vector2 = Vector2.ZERO
var _position_stored: bool = false
var _hover_disabled: bool = false

# 选中脉冲 tween 引用（用于切换时终止）
var _pulse_tween: Tween = null
# 当前脉冲因子（由 tween 驱动 queue_redraw）
var _pulse_factor: float = 0.0


# ------------------------------------------------------------------
# 初始化（子类调用 super.setup_base() 完成骨架设置）
# ------------------------------------------------------------------
func setup_base(base_pos: Vector2 = Vector2.ZERO) -> void:
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	pivot_offset = Vector2(CARD_WIDTH / 2.0, CARD_HEIGHT / 2.0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	_base_position = base_pos
	_position_stored = true
	if base_pos != Vector2.ZERO:
		position = base_pos
	queue_redraw()


## 外部设置基准位置（容器管理模式下必须调用）
func set_base_position(pos: Vector2) -> void:
	_base_position = pos
	_position_stored = true
	position = pos


## 禁用 hover 动画（适用于 HBox/VBox 容器管理位置的场景）
func disable_hover() -> void:
	_hover_disabled = true
	_is_hovered = false
	scale = Vector2.ONE
	z_index = 0
	queue_redraw()


# ------------------------------------------------------------------
# 选中态（供子类/外部切换，例如 TrapDeploy 的"待放置"）
# ------------------------------------------------------------------
## 选中态（供子类/外部切换，例如 TrapDeploy 的"待放置"）
##
## 选中时：
##   - 强制回到 base_position + 原始 scale（取消任何进行中的 hover 动画）
##   - 禁用后续 hover 响应（_is_hovered 锁定 false，不再 scale/抬升）
##   - z_index 抬到 20，确保外发光不被相邻卡压住
##   - 启动脉冲边框动画
## 取消选中时：恢复一切默认。
func set_selected(selected: bool) -> void:
	if _is_selected == selected:
		return
	_is_selected = selected
	_on_selected_changed(selected)
	if selected:
		# 锁死：不响应 hover，不再抬升/放大
		_is_hovered = false
		# 终止任何进行中的 hover tween
		_kill_hover_tween()
		# 复位 scale 和 position（位置使用容器分配的真实位置 _container_position）
		scale = Vector2(NORMAL_SCALE, NORMAL_SCALE)
		if _container_position_stored:
			position = _container_position
		z_index = 20  # 选中时强制盖住相邻卡
		_start_pulse()
	else:
		z_index = 0
		_stop_pulse()
	queue_redraw()


# 终止当前正在进行的 hover tween（如果有）
var _hover_tween: Tween = null
# 容器分配给本卡的真实 position（在容器布局完成后捕获）
var _container_position: Vector2 = Vector2.ZERO
var _container_position_stored: bool = false

func _kill_hover_tween() -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = null


func is_selected() -> bool:
	return _is_selected


## 供子类覆盖：选中状态变化时的回调
func _on_selected_changed(_selected: bool) -> void:
	pass


func _start_pulse() -> void:
	_stop_pulse()
	_pulse_tween = create_tween().set_loops()
	_pulse_tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_pulse_tween.tween_method(_set_pulse_factor, 0.0, 1.0, SELECT_PULSE_SEC * 0.5)
	_pulse_tween.tween_method(_set_pulse_factor, 1.0, 0.0, SELECT_PULSE_SEC * 0.5)


func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
	_pulse_factor = 0.0
	queue_redraw()


func _set_pulse_factor(v: float) -> void:
	_pulse_factor = v
	queue_redraw()


# ------------------------------------------------------------------
# 绘制入口 —— 子类覆盖 _draw_card_front
# ------------------------------------------------------------------
func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, CARD_HEIGHT))
	var accent: Color = get_accent_color()
	if not _is_card_usable():
		accent = DISABLED_COLOR

	# 1) 卡背
	draw_rect(rect, BG_COLOR_DEFAULT, true)

	# 2) 子类主卡面（顶部标记条 + 卡名 + 图腾 + 描述等）
	_draw_card_front(rect, accent)

	# 3) 基础边框（hover 时加亮；selected 脉冲叠加发光）
	var border_color: Color = accent if _is_hovered else accent * 0.7
	var border_width: float = 2.5 if _is_hovered else 2.0
	draw_rect(rect, border_color, false, border_width)

	# 4) 选中脉冲外发光（多层边框模拟发光）
	if _is_selected and _pulse_factor > 0.0:
		var glow_color: Color = accent
		glow_color.a = 0.25 + 0.35 * _pulse_factor
		for i in range(3):
			var expand := float(i + 1) * 2.0
			var glow_rect := Rect2(rect.position - Vector2(expand, expand), rect.size + Vector2(expand * 2, expand * 2))
			var c: Color = glow_color
			c.a *= 1.0 - (float(i) / 3.0)
			draw_rect(glow_rect, c, false, 1.5)


## 子类必须覆盖：绘制卡片正面内容
func _draw_card_front(_rect: Rect2, _accent: Color) -> void:
	pass


## 子类必须覆盖：返回当前主色
func get_accent_color() -> Color:
	return Color.WHITE


## 子类可覆盖：是否处于可用状态（影响禁用态绘制）
func _is_card_usable() -> bool:
	return true


# ------------------------------------------------------------------
# 绘制辅助（供子类复用）
# ------------------------------------------------------------------
## 绘制顶部标记条（高度 28px）
func draw_top_bar(accent: Color, text: String) -> void:
	var top_bar := Rect2(0, 0, CARD_WIDTH, 28)
	draw_rect(top_bar, accent * Color(1.0, 1.0, 1.0, 0.3), true)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(8, 20),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - 16,
		14,
		accent,
	)


## 绘制卡名（y=60）
func draw_card_name(card_name: String, color: Color = Color.WHITE) -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(8, 60),
		card_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - 16,
		18,
		color,
	)


## 绘制分隔线（y=70）
func draw_separator(accent: Color) -> void:
	draw_line(Vector2(10, 70), Vector2(CARD_WIDTH - 10, 70), accent * 0.4, 1.0)


## 绘制多行描述文字（从 y=92 起，每行 18px）
func draw_description(lines: Array[String], color: Color, start_y: float = 92.0) -> void:
	var y: float = start_y
	for line in lines:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(8, y),
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			CARD_WIDTH - 16,
			13,
			color,
		)
		y += 18.0


## 绘制底部注记（如 "持续 N 回合" / "即时"）
func draw_footer(text: String, color: Color) -> void:
	draw_string(
		ThemeDB.fallback_font,
		Vector2(8, CARD_HEIGHT - 14),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - 16,
		12,
		color,
	)


## 通用文本换行工具（按字符数粗切，适合等宽 CJK）
func wrap_text(text: String, chars_per_line: int) -> Array[String]:
	var lines: Array[String] = []
	var remaining: String = text
	while remaining.length() > chars_per_line:
		lines.append(remaining.substr(0, chars_per_line))
		remaining = remaining.substr(chars_per_line)
	if remaining.length() > 0:
		lines.append(remaining)
	return lines


# ------------------------------------------------------------------
# 鼠标悬浮与点击判定（滞后阈值防抖）
# ------------------------------------------------------------------
func _process(_delta: float) -> void:
	if not _position_stored:
		return
	if _hover_disabled:
		return
	if _is_selected:
		return  # 选中态：完全锁死位置/缩放，不响应 hover
	if not is_visible_in_tree():
		return
	var mouse_pos_global: Vector2 = get_global_mouse_position()
	var should_hover: bool = _is_mouse_inside_stable(mouse_pos_global)
	if should_hover != _is_hovered:
		_is_hovered = should_hover
		if _is_card_usable():
			_animate_hover(should_hover)
		queue_redraw()


func _is_mouse_inside_stable(mouse_pos_global: Vector2) -> bool:
	# 使用容器实际分配给本卡的位置作为基准（而不是 setup 时的 _base_position，后者在容器管理下永远是 0,0）
	var parent_ctrl: Control = get_parent() as Control
	var parent_global: Vector2 = parent_ctrl.global_position if parent_ctrl else Vector2.ZERO
	var base_local: Vector2 = _container_position if _container_position_stored else _base_position
	var base_global: Vector2 = parent_global + base_local
	if _is_hovered:
		var scaled_size := size * HOVER_SCALE
		var scaled_center := base_global + size / 2.0 + Vector2(0, -HOVER_LIFT)
		var enlarged_rect := Rect2(scaled_center - scaled_size / 2.0, scaled_size)
		enlarged_rect = enlarged_rect.grow(8.0)
		return enlarged_rect.has_point(mouse_pos_global)
	else:
		return Rect2(base_global, size).has_point(mouse_pos_global)


func _animate_hover(hover: bool) -> void:
	# 第一次进入 hover 时，捕获容器当前分配给本卡的 position —— 这是真正的"基准位置"
	if hover and not _container_position_stored:
		_container_position = position
		_container_position_stored = true

	# 终止之前的 hover tween，避免多个 tween 叠加冲突
	_kill_hover_tween()
	_hover_tween = create_tween().set_parallel(true)
	_hover_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	var base_pos: Vector2 = _container_position if _container_position_stored else _base_position
	if hover:
		_hover_tween.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), HOVER_TWEEN_SEC)
		_hover_tween.tween_property(self, "position", base_pos + Vector2(0, -HOVER_LIFT), HOVER_TWEEN_SEC)
		z_index = 10
	else:
		_hover_tween.tween_property(self, "scale", Vector2(NORMAL_SCALE, NORMAL_SCALE), HOVER_TWEEN_SEC)
		_hover_tween.tween_property(self, "position", base_pos, HOVER_TWEEN_SEC)
		z_index = 0


## 当前视觉矩形（供子类点击判定）
func get_visual_rect_global() -> Rect2:
	var target_scale: float = HOVER_SCALE if _is_hovered else NORMAL_SCALE
	var scaled_size: Vector2 = size * target_scale
	var center: Vector2 = global_position + size / 2.0
	var lift_offset: float = -HOVER_LIFT if _is_hovered else 0.0
	center.y += lift_offset / 2.0
	var top_left: Vector2 = center - scaled_size / 2.0
	return Rect2(top_left - Vector2(4, 4), scaled_size + Vector2(8, 8))


func is_hovered() -> bool:
	return _is_hovered
