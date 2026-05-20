class_name HexDial
extends Control
## HexDial — Hex 滚动条组件（v0.9.4 自调升级牌密码锁面板用）
##
## 视觉形态：
##   ╭────────────────────────────────╮
##   │  DAMAGE   [▶ ███████░░░] 07    │  ← 离散刻度块 + 拖动读取头
##   │  > SET damage = 0x07           │  ← 下方伪代码反馈
##   ╰────────────────────────────────╯
##
## 操作方式：
##   - 鼠标点击/拖动：定位读取头到对应刻度
##   - 鼠标滚轮：±1 微调
##   - 上下/左右箭头键（focused 时）：±1
##   - PageUp/Down：±5
##
## 信号：
##   - value_changed(new_value: int)
##
## 用途：每个面板字段（damage/armor/heal/cost/element/polarity）配一个 HexDial
##   - 数值字段：min=0, max=15
##   - 枚举字段（element / polarity）：min=0, max=N，配 enum_labels 数组

signal value_changed(new_value: int)

# 配置（外部 setup 设置）
var dial_label: String = "VALUE"        # 顶部左侧标题（中文也 OK）
var code_var_name: String = ""           # 伪代码变量名（英文，仅用于底部 > SET xxx 反馈；空时退化用 dial_label）
var min_value: int = 0
var max_value: int = 15
var current_value: int = 0
var enum_labels: Array[String] = []      # 枚举模式：每个 index 显示什么文字
var hex_mode: bool = true                # true=显示 16 进制；false=10 进制
var disabled: bool = false               # 禁用态（灰色，不响应输入）
var suffix_text: String = ""             # v2 新增：值后缀（如 "→ 6 甲"）

# 内部状态
var _hovered: bool = false
var _dragging: bool = false

# 内部节点
var _label_node: Label
var _bar_panel: Panel
var _bar_fill: ColorRect
var _bar_head: ColorRect
var _value_label: Label
var _suffix_label: Label                 # v2 新增：值后缀显示
var _code_label: Label

# 视觉常量
const DIAL_HEIGHT: float = 60.0
const BAR_HEIGHT: float = 18.0
const HEAD_WIDTH: float = 4.0
const COLOR_BAR_BG := Color(0.1, 0.13, 0.18, 1.0)
const COLOR_BAR_FILL := Color(0.0, 0.7, 0.9, 0.6)       # 蓝青
const COLOR_BAR_FILL_OVER := Color(1.0, 0.4, 0.3, 0.7)   # 超支红
const COLOR_HEAD := Color(0.0, 0.95, 1.0, 1.0)
const COLOR_HEAD_DISABLED := Color(0.5, 0.5, 0.55, 0.8)
const COLOR_CODE_NORMAL := Color(0.5, 1.0, 0.7, 0.85)    # 绿（OK）
const COLOR_CODE_WARN := Color(1.0, 0.85, 0.3, 0.95)     # 黄（必选未填）


func _ready() -> void:
	custom_minimum_size = Vector2(280, DIAL_HEIGHT)
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_refresh()


func _build_ui() -> void:
	# 顶部：标题 + 数值（HBox）
	var top := HBoxContainer.new()
	top.position = Vector2(0, 0)
	top.size = Vector2(custom_minimum_size.x, 16)
	top.add_theme_constant_override("separation", 8)
	add_child(top)

	_label_node = Label.new()
	_label_node.text = dial_label
	_label_node.add_theme_font_size_override("font_size", 13)
	_label_node.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_label_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_label_node)

	_value_label = Label.new()
	_value_label.text = "00"
	_value_label.add_theme_font_size_override("font_size", 14)
	_value_label.add_theme_color_override("font_color", Color(0.0, 1.0, 1.0))
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_value_label)

	# v2 新增：值后缀（如 "→ 6 甲"），紧跟 value_label
	_suffix_label = Label.new()
	_suffix_label.text = ""
	_suffix_label.add_theme_font_size_override("font_size", 13)
	_suffix_label.add_theme_color_override("font_color", Color(0.5, 0.95, 0.7))
	top.add_child(_suffix_label)

	# 中间：滚动条（Panel + 填充 + 读取头）
	_bar_panel = Panel.new()
	_bar_panel.position = Vector2(0, 22)
	_bar_panel.size = Vector2(custom_minimum_size.x, BAR_HEIGHT)
	_bar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_BAR_BG
	sb.border_color = Color(0.0, 0.7, 0.9, 0.5)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	_bar_panel.add_theme_stylebox_override("panel", sb)
	add_child(_bar_panel)

	_bar_fill = ColorRect.new()
	_bar_fill.position = Vector2(1, 1)
	_bar_fill.size = Vector2(0, BAR_HEIGHT - 2)
	_bar_fill.color = COLOR_BAR_FILL
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_panel.add_child(_bar_fill)

	_bar_head = ColorRect.new()
	_bar_head.color = COLOR_HEAD
	_bar_head.size = Vector2(HEAD_WIDTH, BAR_HEIGHT - 2)
	_bar_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_panel.add_child(_bar_head)

	# 底部：> SET xxx = 0xNN 伪代码反馈
	_code_label = Label.new()
	_code_label.position = Vector2(0, 44)
	_code_label.size = Vector2(custom_minimum_size.x, 14)
	_code_label.add_theme_font_size_override("font_size", 11)
	_code_label.add_theme_color_override("font_color", COLOR_CODE_NORMAL)
	_code_label.text = ""
	add_child(_code_label)


## 配置 dial（外部 setup）
func configure(p_label: String, p_min: int, p_max: int, p_initial: int = 0,
		p_enum_labels: Array[String] = [], p_hex_mode: bool = true,
		p_code_var_name: String = "") -> void:
	dial_label = p_label
	code_var_name = p_code_var_name if p_code_var_name != "" else p_label.to_lower().replace(" ", "_")
	min_value = p_min
	max_value = p_max
	current_value = clampi(p_initial, p_min, p_max)
	enum_labels = p_enum_labels
	hex_mode = p_hex_mode
	if _label_node != null:
		_label_node.text = p_label
	_refresh()


func set_value(v: int) -> void:
	var clamped: int = clampi(v, min_value, max_value)
	if clamped != current_value:
		current_value = clamped
		_refresh()
		value_changed.emit(current_value)


func get_value() -> int:
	return current_value


func set_disabled(d: bool) -> void:
	disabled = d
	if disabled:
		modulate = Color(0.6, 0.6, 0.6, 0.7)
	else:
		modulate = Color.WHITE


## v2：设置值后缀文字（如 "→ 6 甲"），用于实时显示\"点数→数值\"换算
func set_suffix_text(text: String) -> void:
	suffix_text = text
	if _suffix_label != null:
		_suffix_label.text = text


## 刷新视觉显示
func _refresh() -> void:
	if _bar_panel == null:
		return
	var range_size: int = max(max_value - min_value, 1)
	var ratio: float = float(current_value - min_value) / float(range_size)
	var bar_w: float = _bar_panel.size.x - 2

	# 填充宽度
	_bar_fill.size = Vector2(maxf(bar_w * ratio, 0.0), BAR_HEIGHT - 2)

	# 读取头位置（在填充末端）
	_bar_head.position = Vector2(maxf(bar_w * ratio - HEAD_WIDTH * 0.5, 0.0), 1)

	# 数值显示
	if not enum_labels.is_empty() and current_value < enum_labels.size():
		_value_label.text = enum_labels[current_value]
	elif hex_mode:
		_value_label.text = "0x%02X" % current_value
	else:
		_value_label.text = "%d" % current_value

	# 伪代码反馈
	var var_name: String = code_var_name if code_var_name != "" else dial_label.to_lower().replace(" ", "_")
	if not enum_labels.is_empty() and current_value < enum_labels.size():
		_code_label.text = "> SET %s = %s" % [var_name, enum_labels[current_value].to_upper()]
	else:
		_code_label.text = "> SET %s = %s" % [var_name, _value_label.text]


## 鼠标事件处理
func _gui_input(event: InputEvent) -> void:
	if disabled:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_set_value_from_position(mb.position)
				grab_focus()
			else:
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			set_value(current_value + 1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			set_value(current_value - 1)

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_set_value_from_position(mm.position)

	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT, KEY_DOWN:
				set_value(current_value - 1)
				accept_event()
			KEY_RIGHT, KEY_UP:
				set_value(current_value + 1)
				accept_event()
			KEY_PAGEUP:
				set_value(current_value + 5)
				accept_event()
			KEY_PAGEDOWN:
				set_value(current_value - 5)
				accept_event()


## 把鼠标 X 坐标映射到值
func _set_value_from_position(local_pos: Vector2) -> void:
	if _bar_panel == null:
		return
	var bar_x: float = local_pos.x - _bar_panel.position.x
	var bar_w: float = _bar_panel.size.x
	if bar_w <= 0:
		return
	var ratio: float = clampf(bar_x / bar_w, 0.0, 1.0)
	var range_size: int = max(max_value - min_value, 1)
	var new_v: int = min_value + int(round(ratio * range_size))
	set_value(new_v)
