extends Control
## Boss 意图预告 UI — 显示在 Boss 区域附近

const WIDTH := 340
const HEIGHT := 120

var current_intent: BossIntent = null
var _pulse_time: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_intent(intent: BossIntent) -> void:
	current_intent = intent
	visible = true
	queue_redraw()
	# 弹入动画
	modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, 0.3)


func hide_intent() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): visible = false)


func _process(delta: float) -> void:
	if current_intent != null and visible:
		_pulse_time += delta
		queue_redraw()


func _draw() -> void:
	if current_intent == null:
		return

	var color: Color = current_intent.get_color()
	var rect := Rect2(Vector2.ZERO, size)

	# 背景
	draw_rect(rect, Color(0.03, 0.04, 0.07, 0.9), true)

	# 脉冲发光边框
	var pulse: float = 0.7 + 0.3 * sin(_pulse_time * 3.0)
	var border_color: Color = color * pulse
	draw_rect(rect, border_color, false, 2.0)

	# 顶部标签
	draw_string(ThemeDB.fallback_font, Vector2(16, 26), "◆ 下回合意图", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.75, 0.8))

	# 图标 + 描述
	var icon: String = current_intent.get_icon()
	draw_string(ThemeDB.fallback_font, Vector2(16, 68), icon, HORIZONTAL_ALIGNMENT_LEFT, -1, 32, color)

	var text: String = current_intent.get_display_text()
	draw_string(ThemeDB.fallback_font, Vector2(62, 68), text, HORIZONTAL_ALIGNMENT_LEFT, WIDTH - 72, 22, color)

	# 底部提示（如果是危险意图）
	if current_intent.type == BossIntent.IntentType.HEAVY_ATTACK:
		draw_string(ThemeDB.fallback_font, Vector2(16, 102), "⚠ 建议防御或约束", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.4, 0.3))
	elif current_intent.type == BossIntent.IntentType.BUFF:
		draw_string(ThemeDB.fallback_font, Vector2(16, 102), "⚠ 封印或否决", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.7, 0.3))
	elif current_intent.type == BossIntent.IntentType.HEAL:
		draw_string(ThemeDB.fallback_font, Vector2(16, 102), "⚠ 阻止其回复", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.4, 1.0, 0.5))
