extends ColorRect
## SwapAnimation — GDD-08 牌库互换动画层（v0.8.2 简化版）
## 单一动画：双方牌库标题上下平滑交换到对方位置 → 停顿 → 完成
## 不使用白屏闪烁/紫色脉冲，纯位置过渡

signal swap_animation_finished()

# 布局常量（屏幕坐标系）
const BOSS_START_Y: float = 120.0      # Boss 标题起始位置（屏幕上方）
const PLAYER_TARGET_Y: float = 120.0   # 玩家标题目标位置（互换后到屏幕上方）
const LABEL_HEIGHT: float = 60.0
const BOTTOM_MARGIN: float = 180.0     # 距屏幕底部的边距（玩家起始 / Boss 目标）

var _player_label: Label
var _boss_label: Label
var _center_text: Label


func _ready() -> void:
	# 全屏覆盖
	anchor_right = 1.0
	anchor_bottom = 1.0
	color = Color(0, 0, 0, 0.92)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	_setup_ui()
	visible = false


func _setup_ui() -> void:
	# 用 anchor TOP_LEFT + position 直接控制屏幕坐标，避免 anchor preset 的隐式偏移
	_boss_label = _make_label("BossLabel", "MIRROR 牌库", 42, Color(1.0, 0.3, 0.3))
	add_child(_boss_label)

	_center_text = _make_label("CenterText", "⇅ MIRROR ⇅", 56, Color(1.0, 0.85, 0.1))
	add_child(_center_text)

	_player_label = _make_label("PlayerLabel", "你的牌库", 42, Color(0.25, 0.85, 1.0))
	add_child(_player_label)


func _make_label(p_name: String, text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.name = p_name
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.set_anchors_preset(Control.PRESET_TOP_LEFT)
	return lbl


## 把 3 个 label 重置到初始位置 + 初始文字 + 初始颜色
## 每次 play_swap_animation 开头调用（保证多次播放可重入）
func _reset_to_initial_state() -> void:
	var screen_size: Vector2 = get_viewport_rect().size
	var screen_w: float = screen_size.x
	var screen_h: float = screen_size.y

	# Label 宽度全屏，便于水平居中（HORIZONTAL_ALIGNMENT_CENTER）
	_boss_label.size = Vector2(screen_w, LABEL_HEIGHT)
	_boss_label.position = Vector2(0, BOSS_START_Y)
	_boss_label.text = "MIRROR 牌库"
	_boss_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	_boss_label.modulate.a = 1.0

	_player_label.size = Vector2(screen_w, LABEL_HEIGHT)
	_player_label.position = Vector2(0, screen_h - BOTTOM_MARGIN)
	_player_label.text = "你的牌库"
	_player_label.add_theme_color_override("font_color", Color(0.25, 0.85, 1.0))
	_player_label.modulate.a = 1.0

	_center_text.size = Vector2(screen_w, 80)
	_center_text.position = Vector2(0, (screen_h - 80) / 2.0)
	_center_text.text = "⇅ MIRROR ⇅"
	_center_text.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_center_text.modulate.a = 1.0


## 播放互换动画（总时长 ~3.4s）
##   阶段 1：淡入 (0~0.6s)
##   阶段 2：上下平滑交换 (0.6~2.0s)
##   阶段 3：停顿展示 (2.0~2.8s)
##   阶段 4：淡出 (2.8~3.4s)
func play_swap_animation() -> void:
	# 关键：每次播放前先重置到初始位置（避免第二次重叠在屏幕上方）
	_reset_to_initial_state()

	visible = true
	modulate.a = 0.0

	var screen_h: float = get_viewport_rect().size.y
	var boss_start_y: float = BOSS_START_Y
	var boss_target_y: float = screen_h - BOTTOM_MARGIN          # Boss 滑到下方
	var player_start_y: float = screen_h - BOTTOM_MARGIN
	var player_target_y: float = PLAYER_TARGET_Y                  # 玩家滑到上方

	# === 阶段 1：淡入 (0~0.6s) ===
	var t1 := create_tween()
	t1.tween_property(self, "modulate:a", 1.0, 0.6)
	await t1.finished

	# === 阶段 2：上下平滑交换 (0.6~2.0s) ===
	var t2 := create_tween().set_parallel(true)
	t2.tween_property(_boss_label, "position:y", boss_target_y, 1.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t2.tween_property(_player_label, "position:y", player_target_y, 1.4)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	# 中央文字淡化让玩家专注交换
	t2.tween_property(_center_text, "modulate:a", 0.4, 1.4)
	await t2.finished

	# === 阶段 3：停顿展示 + 标题更新 (2.0~2.8s) ===
	# 玩家位置（屏幕上方）现在挂着 _player_label（蓝），它代表 MIRROR 旧牌库（现归你）→ 改红色
	# Boss 位置（屏幕下方）现在挂着 _boss_label（红），它代表你的旧牌库（现归 MIRROR）→ 改蓝色
	_player_label.text = "MIRROR 旧牌库（现归你）"
	_player_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	_boss_label.text = "你的旧牌库（现归 MIRROR）"
	_boss_label.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	_center_text.text = "↻ 互换完成"
	_center_text.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	var t3 := create_tween()
	t3.tween_property(_center_text, "modulate:a", 1.0, 0.4)
	await get_tree().create_timer(0.8).timeout

	# === 阶段 4：淡出 (2.8~3.4s) ===
	var t4 := create_tween()
	t4.tween_property(self, "modulate:a", 0.0, 0.6)
	await t4.finished

	visible = false
	swap_animation_finished.emit()
	# 注意：不在此处 reset，由下次 play_swap_animation 入口的 _reset_to_initial_state 处理
