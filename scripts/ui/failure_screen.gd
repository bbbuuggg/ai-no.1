extends ColorRect
## FailureScreen — 玩家死亡后的失败结算页（GDD-08 §3.1 FAILURE_END）
## 显示击败次数 + "再来一次"按钮 → emit restart_requested 由场景接管

signal restart_requested  ## 玩家点了"再来一次"

const TITLE: String = "运 行 结 束"
const SUBTITLE_DEFEAT: String = "MIRROR 击溃了你的协议"
const HINT_FORMAT: String = "本次共击败 MIRROR  %d  次"

var _title_label: Label
var _streak_label: Label
var _subtitle_label: Label
var _record_label: Label
var _restart_btn: Button


func _ready() -> void:
	_setup_ui()


func _setup_ui() -> void:
	# 全屏深色遮罩（覆盖战斗画面）
	anchor_right = 1.0
	anchor_bottom = 1.0
	color = Color(0.04, 0.02, 0.06, 0.96)  # 深紫黑（NULL Protocol 主题）
	mouse_filter = Control.MOUSE_FILTER_STOP  # 拦截所有点击
	z_index = 100

	# 中心垂直布局容器
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -360
	vbox.offset_top = -240
	vbox.offset_right = 360
	vbox.offset_bottom = 240
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 18)
	add_child(vbox)

	# 顶部装饰线
	var top_line := ColorRect.new()
	top_line.color = Color(0.85, 0.15, 0.2, 0.85)
	top_line.custom_minimum_size = Vector2(560, 3)
	top_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(top_line)

	# 主标题
	_title_label = Label.new()
	_title_label.text = TITLE
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 56)
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.32, 0.36))
	_title_label.add_theme_color_override("font_outline_color", Color(0.2, 0.0, 0.0))
	_title_label.add_theme_constant_override("outline_size", 3)
	vbox.add_child(_title_label)

	# 副标题
	_subtitle_label = Label.new()
	_subtitle_label.text = SUBTITLE_DEFEAT
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 22)
	_subtitle_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.85))
	vbox.add_child(_subtitle_label)

	# 间隔
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer1)

	# 击败次数（核心数据，大号金色）
	_streak_label = Label.new()
	_streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_streak_label.add_theme_font_size_override("font_size", 38)
	_streak_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_streak_label.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.0))
	_streak_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_streak_label)

	# 历史最佳（底部小字提示）
	_record_label = Label.new()
	_record_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_record_label.add_theme_font_size_override("font_size", 16)
	_record_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	vbox.add_child(_record_label)

	# 间隔
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer2)

	# "再来一次"按钮
	_restart_btn = Button.new()
	_restart_btn.text = "再 来 一 次"
	_restart_btn.custom_minimum_size = Vector2(280, 56)
	_restart_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_restart_btn.add_theme_font_size_override("font_size", 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.18, 0.28, 1.0)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.4, 0.7, 0.95)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(0.4, 0.7, 0.95, 0.4)
	sb.shadow_size = 5
	_restart_btn.add_theme_stylebox_override("normal", sb)
	var sb_hover := sb.duplicate()
	sb_hover.bg_color = Color(0.2, 0.28, 0.42, 1.0)
	_restart_btn.add_theme_stylebox_override("hover", sb_hover)
	_restart_btn.add_theme_color_override("font_color", Color(0.85, 0.92, 1.0))
	_restart_btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))
	_restart_btn.pressed.connect(_on_restart_pressed)
	vbox.add_child(_restart_btn)

	# 底部装饰线
	var bottom_line := ColorRect.new()
	bottom_line.color = Color(0.85, 0.15, 0.2, 0.85)
	bottom_line.custom_minimum_size = Vector2(560, 3)
	bottom_line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(bottom_line)


## 用 RunState 数据填充并播淡入动画
## @param victory_streak 本次 Run 击败的 Boss 次数（从 RunState.victory_streak 读）
## @param best_record 历史最佳（暂时与本次相同；GDD-08 §3.1 后续接入存档系统时改）
func show_with_streak(victory_streak: int, best_record: int = -1) -> void:
	_streak_label.text = HINT_FORMAT % victory_streak

	if best_record < 0 or best_record <= victory_streak:
		_record_label.text = "★  这是你迄今为止最好的成绩  ★" if victory_streak > 0 else "下次会更好"
		_record_label.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.4) if victory_streak > 0 else Color(0.6, 0.65, 0.75))
	else:
		_record_label.text = "历史最佳：%d 次" % best_record

	# 淡入 + 文字依次出现
	visible = true
	modulate.a = 0.0
	_title_label.modulate.a = 0.0
	_subtitle_label.modulate.a = 0.0
	_streak_label.modulate.a = 0.0
	_record_label.modulate.a = 0.0
	_restart_btn.modulate.a = 0.0

	var t := create_tween()
	t.set_parallel(false)
	t.tween_property(self, "modulate:a", 1.0, 0.5)
	t.tween_property(_title_label, "modulate:a", 1.0, 0.5)
	t.tween_property(_subtitle_label, "modulate:a", 1.0, 0.4)
	t.tween_property(_streak_label, "modulate:a", 1.0, 0.6)
	t.tween_property(_record_label, "modulate:a", 1.0, 0.4)
	t.tween_property(_restart_btn, "modulate:a", 1.0, 0.4)


func _on_restart_pressed() -> void:
	restart_requested.emit()
