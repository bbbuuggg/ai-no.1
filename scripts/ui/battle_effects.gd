extends Node
## 战斗特效管理器 — 飘字、震动、闪光

var root_control: Control  # 用于添加飘字的画布
var camera_3d: Camera3D  # 用于震动 3D 场景
var _camera_base_transform: Transform3D
var _shake_intensity: float = 0.0
var _shake_time: float = 0.0


func setup(p_root: Control, p_camera: Camera3D) -> void:
	root_control = p_root
	camera_3d = p_camera
	if camera_3d:
		_camera_base_transform = camera_3d.transform
	set_process(true)


func spawn_damage_number(global_pos: Vector2, amount: int, color: Color = Color(1.0, 0.3, 0.3)) -> void:
	if root_control == null:
		return
	var label := Label.new()
	label.text = "-%d" % amount
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 48)
	label.position = global_pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(label)

	var tween := root_control.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", global_pos.y - 100.0, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "position:x", global_pos.x + randf_range(-30, 30), 0.8)
	tween.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func spawn_healing_number(global_pos: Vector2, amount: int) -> void:
	spawn_damage_number_custom(global_pos, "+%d" % amount, Color(0.4, 1.0, 0.5))


func spawn_armor_number(global_pos: Vector2, amount: int) -> void:
	spawn_damage_number_custom(global_pos, "+%d 🛡" % amount, Color(0.5, 0.85, 1.0))


func spawn_damage_number_custom(global_pos: Vector2, text: String, color: Color) -> void:
	if root_control == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", 42)
	label.position = global_pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.add_child(label)

	var tween := root_control.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", global_pos.y - 80.0, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)


func spawn_text_effect(global_pos: Vector2, text: String, color: Color, size: int = 32) -> void:
	if root_control == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_font_size_override("font_size", size)
	label.position = global_pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.scale = Vector2(0.5, 0.5)
	label.pivot_offset = Vector2(0, size)
	root_control.add_child(label)

	var tween := root_control.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	tween.chain().tween_interval(0.6)
	tween.chain().tween_property(label, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(label.queue_free)


## 通用飞行 Toast：从 start 飞向 end 的浮动文字
## 当前无场景调用方（v0.5.0 旧 B-3"Boss 已出 X / 剩 Y"飞行 toast 已废弃，
## 该信息改由部署阶段的 BossBlindLane 持续呈现）。
## 保留此函数作为通用工具，未来如需短时浮提可直接复用。
## duration: 总时长（含飞行+淡出）
func spawn_flying_toast(
	start_pos: Vector2,
	end_pos: Vector2,
	text: String,
	color: Color,
	duration: float = 2.5,
) -> void:
	if root_control == null:
		return
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.04, 0.9))
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_font_size_override("font_size", 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.position = start_pos
	label.scale = Vector2(0.7, 0.7)
	label.pivot_offset = Vector2(0, 18)
	root_control.add_child(label)

	# 飞行轨迹：start → 中点上挑 → end，整体时间约 duration*0.65，最后 35% 淡出
	var fly_time: float = duration * 0.65
	var fade_time: float = duration * 0.35
	# 中点（上挑 60px 营造抛物线感）
	var mid_pos: Vector2 = (start_pos + end_pos) * 0.5 + Vector2(0, -60.0)

	var tween := root_control.create_tween()
	tween.set_parallel(true)
	# 弹出
	tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# 飞行（先到 mid，再到 end）
	tween.chain().tween_property(label, "position", mid_pos, fly_time * 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.chain().tween_property(label, "position", end_pos, fly_time * 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	# 抵达后压扁 + 淡出
	tween.chain().tween_property(label, "scale", Vector2(0.6, 0.6), fade_time * 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, fade_time)
	tween.chain().tween_callback(label.queue_free)


func shake_camera(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_time = duration


func _process(delta: float) -> void:
	if _shake_time > 0.0 and camera_3d:
		_shake_time -= delta
		var current_intensity: float = _shake_intensity * (_shake_time / maxf(_shake_time + delta, 0.001))
		var offset := Vector3(
			randf_range(-current_intensity, current_intensity),
			randf_range(-current_intensity, current_intensity),
			0
		)
		var t := _camera_base_transform
		t.origin += offset
		camera_3d.transform = t
		if _shake_time <= 0.0:
			camera_3d.transform = _camera_base_transform
	elif camera_3d and camera_3d.transform != _camera_base_transform:
		camera_3d.transform = _camera_base_transform
