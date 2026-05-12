extends Control
## 对决翻牌演出 UI — 逐张翻开 + 克制视觉反馈

signal clash_animation_complete()

const CardUI := preload("res://scripts/ui/card_ui.gd")

const COUNTER_PLAYER_COLOR := Color(0.2, 1.0, 0.5, 1.0)  # 玩家克制 - 绿光
const COUNTER_BOSS_COLOR := Color(1.0, 0.3, 0.3, 1.0)  # Boss克制 - 红光
const NEUTRAL_COLOR := Color(0.8, 0.8, 0.8, 0.6)  # 中立 - 灰
const FREE_COLOR := Color(0.0, 0.85, 1.0, 1.0)  # 多余牌 - 青

var _results: Array = []  # Array[ClashResolver.ClashResult]
var _current_index: int = 0
var _is_playing: bool = false

@onready var player_card_area: Control = $HBox/PlayerSide/CardSlot
@onready var boss_card_area: Control = $HBox/BossSide/CardSlot
@onready var versus_label: Label = $HBox/Center/VersusLabel
@onready var result_label: RichTextLabel = $HBox/Center/ResultLabel
@onready var multiplier_label_player: Label = $HBox/PlayerSide/MultLabel
@onready var multiplier_label_boss: Label = $HBox/BossSide/MultLabel
@onready var pair_counter: Label = $TopBar/PairCounter


func _ready() -> void:
	visible = false


func start_clash_animation(results: Array) -> void:
	_results = results
	_current_index = 0
	_is_playing = true
	visible = true
	_show_next_pair()


func _show_next_pair() -> void:
	if _current_index >= _results.size():
		_finish_animation()
		return

	var result: ClashResolver.ClashResult = _results[_current_index]
	pair_counter.text = "第 %d/%d 对" % [_current_index + 1, _results.size()]

	# 清空旧内容
	_clear_area(player_card_area)
	_clear_area(boss_card_area)

	# 显示玩家牌（翻开动画）
	if result.player_card != null:
		var player_ui := _create_card_display(result.player_card)
		player_card_area.add_child(player_ui)
		await _flip_animation(player_ui)
	else:
		_show_empty_slot(player_card_area, "—")

	await get_tree().create_timer(0.6).timeout

	# 显示Boss牌
	if result.boss_card != null:
		var boss_ui := _create_card_display(result.boss_card)
		boss_card_area.add_child(boss_ui)
		await _flip_animation(boss_ui)
	else:
		_show_empty_slot(boss_card_area, "—")

	await get_tree().create_timer(0.5).timeout

	# 显示碰撞结果
	_show_clash_result(result)

	await get_tree().create_timer(2.0).timeout

	_current_index += 1
	_show_next_pair()


func _show_clash_result(result: ClashResolver.ClashResult) -> void:
	result_label.clear()

	match result.clash_type:
		"counter_player":
			versus_label.text = "克制!"
			versus_label.add_theme_color_override("font_color", COUNTER_PLAYER_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 1.5)
			multiplier_label_player.add_theme_color_override("font_color", COUNTER_PLAYER_COLOR)
			multiplier_label_boss.text = _format_calc(result.boss_card, 0.5)
			multiplier_label_boss.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			_flash_border(player_card_area, COUNTER_PLAYER_COLOR)

		"counter_boss":
			versus_label.text = "被克制!"
			versus_label.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 0.5)
			multiplier_label_player.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			multiplier_label_boss.text = _format_calc(result.boss_card, 1.5)
			multiplier_label_boss.add_theme_color_override("font_color", COUNTER_PLAYER_COLOR)
			_flash_border(boss_card_area, COUNTER_BOSS_COLOR)

		"neutral":
			versus_label.text = "VS"
			versus_label.add_theme_color_override("font_color", NEUTRAL_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 1.0)
			multiplier_label_player.add_theme_color_override("font_color", NEUTRAL_COLOR)
			multiplier_label_boss.text = _format_calc(result.boss_card, 1.0)
			multiplier_label_boss.add_theme_color_override("font_color", NEUTRAL_COLOR)

		"free_player":
			versus_label.text = "无对手"
			versus_label.add_theme_color_override("font_color", FREE_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 1.0) + " 直接生效"
			multiplier_label_player.add_theme_color_override("font_color", FREE_COLOR)
			multiplier_label_boss.text = ""

		"free_boss":
			versus_label.text = "无对手"
			versus_label.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			multiplier_label_player.text = ""
			multiplier_label_boss.text = _format_calc(result.boss_card, 1.0) + " 直接生效"
			multiplier_label_boss.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)

	# 陷阱触发提示
	if result.trap_triggered and result.trap_data != null:
		result_label.push_color(Color(1.0, 0.85, 0.2))
		if result.trap_data.is_bluff:
			result_label.add_text("⚡ 陷阱翻开: 虚影协议（虚张声势！）")
		else:
			result_label.add_text("⚡ 陷阱触发: %s!" % result.trap_data.trap_name)
		result_label.pop()


func _create_card_display(card: CardData) -> Control:
	var card_ui := Control.new()
	card_ui.set_script(CardUI)
	card_ui.setup(card)
	# 初始缩小（翻牌动画起始）
	card_ui.scale = Vector2(0.0, 1.0)
	return card_ui


func _flip_animation(card_ui: Control) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(card_ui, "scale", Vector2(1.0, 1.0), 0.35)
	await tween.finished


func _format_calc(card: CardData, multiplier: float) -> String:
	## 生成 "数值 ×倍率 = 结果" 的计算式文本
	if card == null:
		return ""
	# 找到主数值（伤害/护甲/治疗）
	var base_value: int = 0
	var value_type: String = ""
	if card.damage > 0:
		base_value = card.damage
		value_type = "伤害"
		if card.hits > 1:
			value_type = "伤害×%d" % card.hits
	elif card.armor > 0:
		base_value = card.armor
		value_type = "护甲"
	elif card.heal > 0:
		base_value = card.heal
		value_type = "回复"
	elif card.draw_cards > 0:
		base_value = card.draw_cards
		value_type = "抽牌"
	else:
		# 无数值效果的牌（蓄力等）
		if multiplier < 1.0:
			return "效果减半 → 失效"
		return "×%.1f" % multiplier

	var final_value: int = ceili(float(base_value) * multiplier)

	if multiplier == 1.0:
		return "%d %s" % [base_value, value_type]
	else:
		return "%d ×%.1f = %d %s" % [base_value, multiplier, final_value, value_type]


func _flash_border(area: Control, color: Color) -> void:
	var tween := create_tween()
	tween.tween_property(area, "modulate", color, 0.15)
	tween.tween_property(area, "modulate", Color.WHITE, 0.3)


func _show_empty_slot(area: Control, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	area.add_child(lbl)


func _clear_area(area: Control) -> void:
	for child in area.get_children():
		child.queue_free()


func _finish_animation() -> void:
	_is_playing = false
	await get_tree().create_timer(0.5).timeout
	visible = false
	clash_animation_complete.emit()
