extends Control
## 认知探针面板 UI — 显示Boss预判 + 洞察进度 + 效果提示

signal probe_display_complete()

var _current_prediction: String = ""
var _consecutive_hits: int = 0
var _total_hits: int = 0
var _is_jammed: bool = false

const TYPE_DISPLAY := {
	"attack": {"text": "攻击", "color": Color(0.9, 0.2, 0.2)},
	"defense": {"text": "防御", "color": Color(0.2, 0.7, 0.9)},
	"skill": {"text": "技能", "color": Color(0.2, 0.9, 0.4)},
}

@onready var prediction_label: RichTextLabel = $VBox/PredictionPanel/PredText
@onready var insight_bar: Control = $VBox/InsightBar
@onready var streak_label: Label = $VBox/InsightBar/StreakLabel
@onready var total_label: Label = $VBox/InsightBar/TotalLabel
@onready var status_label: Label = $VBox/StatusLabel


func _ready() -> void:
	visible = false


func show_prediction(predicted_type: String) -> void:
	_current_prediction = predicted_type
	_is_jammed = false
	visible = true

	var type_info: Dictionary = TYPE_DISPLAY.get(predicted_type, {"text": "???", "color": Color.WHITE})
	prediction_label.clear()
	prediction_label.push_color(Color(0.7, 0.7, 0.7))
	prediction_label.add_text("[认知探针] Boss预判你主打：")
	prediction_label.push_color(type_info["color"])
	prediction_label.push_bold()
	prediction_label.add_text(type_info["text"])
	prediction_label.pop()
	prediction_label.pop()

	_update_insight_display()


func show_jammed() -> void:
	_is_jammed = true
	status_label.text = "⚡ 探针已被干扰"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))


func show_result(correct: bool, streak: int, total: int) -> void:
	_consecutive_hits = streak
	_total_hits = total

	if _is_jammed:
		status_label.text = "探针干扰成功 — 本回合判定无效"
		status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
	elif correct:
		status_label.text = "✓ Boss猜对了！连续 %d 次 | 累计 %d 次" % [streak, total]
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		status_label.text = "✗ Boss猜错了 — 连续归零"
		status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))

	_update_insight_display()

	# 延迟后隐藏
	await get_tree().create_timer(2.5).timeout
	visible = false
	probe_display_complete.emit()


func show_insight_effect(effect_type: String, card: CardData) -> void:
	var effect_text: String = ""
	var effect_color: Color = Color.WHITE

	match effect_type:
		"peek":
			effect_text = "⚠ Boss窥视了你的手牌: %s" % card.card_name
			effect_color = Color(1.0, 0.7, 0.2)
		"disrupt":
			effect_text = "⚠⚠ Boss干扰了你: %s 下回合不可用" % card.card_name
			effect_color = Color(1.0, 0.4, 0.2)
		"seize":
			effect_text = "⚠⚠⚠ Boss夺取了: %s！永久失去" % card.card_name
			effect_color = Color(1.0, 0.1, 0.1)

	status_label.text = effect_text
	status_label.add_theme_color_override("font_color", effect_color)


func _update_insight_display() -> void:
	streak_label.text = "连续: %d" % _consecutive_hits
	total_label.text = "累计: %d/5" % _total_hits

	# 颜色预警
	if _consecutive_hits >= 2:
		streak_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif _consecutive_hits >= 1:
		streak_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	else:
		streak_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	if _total_hits >= 4:
		total_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	else:
		total_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
