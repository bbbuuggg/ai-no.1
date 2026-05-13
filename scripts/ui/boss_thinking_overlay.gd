class_name BossThinkingOverlay
extends Control
## Boss 思考演出层 —— 在 BLIND 阶段确认选牌后播放
##
## 视觉设计（art-director 定稿）：
##   - 全屏半透明遮罩 (0.02, 0.04, 0.08, 0.55)
##   - 中央偏上"NULL_PROCESS / 回响 正在分析..." 大字（血红 + 故障字效）
##   - 上下两条扫描线（血红，从中心向上下扩展）
##   - 字符流粒子（数据流幻觉）
##   - 1.5s 默认时长，可被外部强制延长（等 LLM）
##
## 调用：
##   var overlay = $UI/BossThinkingOverlay
##   await overlay.play(min_duration_sec, ai_done_signal_or_null)

signal finished()

const HOSTILE := Color(0.95, 0.2, 0.25, 1.0)
const SCAN_THICKNESS := 2.0

# 状态
var _start_time_ms: int = 0
var _min_duration_ms: int = 1500
var _glitch_phase: float = 0.0

# 节点引用
var _overlay_bg: ColorRect
var _title_label: Label
var _sub_label: Label
var _scan_canvas: Control


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不阻挡点击
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()


func _build_ui() -> void:
	# 遮罩
	_overlay_bg = ColorRect.new()
	_overlay_bg.color = Color(0.02, 0.04, 0.08, 0.55)
	_overlay_bg.anchor_right = 1.0
	_overlay_bg.anchor_bottom = 1.0
	_overlay_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay_bg)

	# 标题
	_title_label = Label.new()
	_title_label.text = "回响 · 正在分析"
	_title_label.add_theme_font_size_override("font_size", 56)
	_title_label.add_theme_color_override("font_color", HOSTILE)
	_title_label.anchor_left = 0.5
	_title_label.anchor_top = 0.5
	_title_label.anchor_right = 0.5
	_title_label.anchor_bottom = 0.5
	_title_label.offset_left = -260.0
	_title_label.offset_top = -80.0
	_title_label.offset_right = 260.0
	_title_label.offset_bottom = -20.0
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title_label)

	# 副标题（字符流）
	_sub_label = Label.new()
	_sub_label.text = "▶ scanning_player_pattern.exe"
	_sub_label.add_theme_font_size_override("font_size", 18)
	_sub_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.95))
	_sub_label.anchor_left = 0.5
	_sub_label.anchor_top = 0.5
	_sub_label.anchor_right = 0.5
	_sub_label.anchor_bottom = 0.5
	_sub_label.offset_left = -300.0
	_sub_label.offset_top = 0.0
	_sub_label.offset_right = 300.0
	_sub_label.offset_bottom = 30.0
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_sub_label)

	# 扫描线层（自绘）
	_scan_canvas = Control.new()
	_scan_canvas.anchor_right = 1.0
	_scan_canvas.anchor_bottom = 1.0
	_scan_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scan_canvas.set_script(_create_scan_script())
	add_child(_scan_canvas)


func _create_scan_script() -> GDScript:
	# 内联脚本：扫描线动画绘制
	var src := """
extends Control
const HOSTILE := Color(0.95, 0.2, 0.25, 0.85)
var time: float = 0.0
func _process(delta: float) -> void:
	time += delta
	queue_redraw()
func _draw() -> void:
	if size.y <= 0:
		return
	var cy := size.y / 2.0
	var t := fmod(time, 1.5) / 1.5
	var spread: float = ease(t, 0.5) * size.y / 2.0
	var alpha: float = 1.0 - t
	var c := HOSTILE
	c.a = 0.65 * alpha
	# 上扫描线
	draw_rect(Rect2(0, cy - spread, size.x, 2.0), c, true)
	# 下扫描线
	draw_rect(Rect2(0, cy + spread - 2.0, size.x, 2.0), c, true)
	# 中央细线（持续）
	var c2 := HOSTILE
	c2.a = 0.3
	draw_rect(Rect2(0, cy - 1.0, size.x, 2.0), c2, true)
"""
	var s := GDScript.new()
	s.source_code = src
	s.reload()
	return s


## 播放演出
##
## @param min_duration_sec  最少播放多久（即使 ai 已完成也等够）
## @param max_duration_sec  最长等多久（若 ai_check 一直 false，超过就强制结束）
## @param ai_ready_check    Callable 返回 bool。为 null 时仅按 min_duration。
##                          非 null 时：到 min_duration 后，若未 ready 则继续每 0.1s 轮询直到 ready 或超 max。
##
## 典型使用：
##   await overlay.play(3.0, 8.0, func(): return not boss_ai.is_thinking())
func play(min_duration_sec: float = 3.0, max_duration_sec: float = 8.0, ai_ready_check: Callable = Callable()) -> void:
	visible = true
	_start_time_ms = Time.get_ticks_msec()
	_min_duration_ms = int(min_duration_sec * 1000.0)
	_glitch_phase = 0.0

	# 入场动画
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)

	# 等最短时长
	await get_tree().create_timer(min_duration_sec).timeout

	# 若给了 AI 检查函数，继续等到 AI 就绪或超过 max
	if ai_ready_check.is_valid():
		var max_wait_ms: int = int(max_duration_sec * 1000.0)
		while not ai_ready_check.call() and (Time.get_ticks_msec() - _start_time_ms) < max_wait_ms:
			await get_tree().create_timer(0.1).timeout

	# 退场动画
	var tw2 := create_tween()
	tw2.tween_property(self, "modulate", Color(1, 1, 1, 0), 0.25)
	await tw2.finished
	visible = false
	finished.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	# 标题字符流抖动
	_glitch_phase += delta * 6.0
	var jitter_x: float = sin(_glitch_phase * 3.0) * 1.5
	_title_label.offset_left = -260.0 + jitter_x
	_title_label.offset_right = 260.0 + jitter_x

	# 副标题循环字符流
	var pool := ["▶ scanning_player_pattern.exe", "▶ probing_hand_distribution.dat", "▶ evaluating_counter_matrix...", "▶ optimizing_action_sequence"]
	var idx: int = int(_glitch_phase / 6.0) % pool.size()
	_sub_label.text = pool[idx]
