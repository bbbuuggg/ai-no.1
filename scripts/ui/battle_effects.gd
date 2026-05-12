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
