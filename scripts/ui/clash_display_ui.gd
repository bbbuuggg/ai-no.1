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
# 每播完一对的翻牌动画后调一次：apply_cb.call(index)
# 这样 HP/护甲/陷阱效果在 UI 展示该对的瞬间才提交到 Combatant，
# 视觉上 HP 数字会随每对结算逐步变化，而不是动画开始前就一次性扣完。
var _apply_cb: Callable = Callable()

@onready var player_card_area: Control = $HBox/PlayerSide/CardSlot
@onready var boss_card_area: Control = $HBox/BossSide/CardSlot
@onready var versus_label: Label = $HBox/Center/VersusLabel
@onready var result_label: RichTextLabel = $HBox/Center/ResultLabel
@onready var multiplier_label_player: Label = $HBox/PlayerSide/MultLabel
@onready var multiplier_label_boss: Label = $HBox/BossSide/MultLabel
@onready var pair_counter: Label = $TopBar/PairCounter


func _ready() -> void:
	visible = false


func start_clash_animation(results: Array, apply_cb: Callable = Callable()) -> void:
	_results = results
	_current_index = 0
	_is_playing = true
	_apply_cb = apply_cb
	visible = true
	# v0.4.3 修复：场景里 HBox 默认 visible=false（防编辑器阶段误显示），运行时必须强制打开。
	# 不打开会导致翻牌动画完全看不到（牌都 add_child 到 HBox 的孙节点 CardSlot）。
	var hbox := $HBox
	if hbox != null:
		hbox.visible = true
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
	multiplier_label_player.text = ""
	multiplier_label_boss.text = ""
	versus_label.text = "..."
	versus_label.add_theme_color_override("font_color", NEUTRAL_COLOR)

	# === 阶段1：双方同时"出牌背"（牌摆到对决区，但牌面朝下） ===
	var player_ui: Control = null
	var boss_ui: Control = null

	if result.player_card != null:
		player_ui = _create_card_display(result.player_card)
		player_card_area.add_child(player_ui)
		# add_child 之后再 show_back —— 确保节点已就绪、_draw 不会被预设的正面状态短暂闪过
		player_ui.show_back()
		_play_in_animation(player_ui, true)  # 滑入动画（不翻面）
	else:
		_show_empty_slot(player_card_area, "—")

	if result.boss_card != null:
		boss_ui = _create_card_display(result.boss_card)
		boss_card_area.add_child(boss_ui)
		boss_ui.show_back()
		_play_in_animation(boss_ui, false)
	else:
		_show_empty_slot(boss_card_area, "—")

	# 等滑入动画完成（_play_in_animation 内部 0.35s + 一点缓冲）
	await get_tree().create_timer(0.45).timeout

	# === 阶段2：停留 0.55 秒，给玩家"对峙感"（看清两张牌背） ===
	await get_tree().create_timer(0.55).timeout

	# === 阶段3：双方同时翻面（拉长到清晰可见 + 用 await tween.finished 严格等完）===
	var flip_tween_player: Tween = null
	var flip_tween_boss: Tween = null
	if player_ui != null:
		flip_tween_player = _flip_card(player_ui)
	if boss_ui != null:
		flip_tween_boss = _flip_card(boss_ui)
	# 等翻面 tween 真正跑完（防止下面 apply_cb 提前结算）
	if flip_tween_player != null:
		await flip_tween_player.finished
	elif flip_tween_boss != null:
		await flip_tween_boss.finished
	else:
		await get_tree().create_timer(0.5).timeout

	# === 阶段3.5：翻面完成后，**才**真正提交本对的伤害/陷阱效果 ===
	# 这一步触发 BlindClashBattle.apply_clash_pair_at(_current_index)：
	# - HP/护甲变更走 Combatant 信号 → 血条+伤害浮字
	# - 陷阱触发走 trap_triggered_signal → 屏幕特效
	# - clash_pair_resolved 把 result 同步给战斗日志
	# 必须在翻面之后（玩家已经看到正反面）才扣血，避免观感"先掉血再翻牌"
	if _apply_cb.is_valid():
		_apply_cb.call(_current_index)
		# 给一帧让 HP 浮字 / 屏幕震动等开始播放，再叠上倍率文字
		await get_tree().process_frame

	# === 阶段4：显示碰撞结果 ===
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
	# 滑入动画起点：牌正常尺寸，但放在区域外侧+透明
	card_ui.setup(card)
	# 对决区卡牌不应响应 hover（否则会与翻牌动画的 scale/position tween 冲突）
	if card_ui.has_method("disable_hover"):
		card_ui.disable_hover()
	card_ui.modulate = Color(1.0, 1.0, 1.0, 0.0)
	return card_ui


func _play_in_animation(card_ui: Control, is_player: bool) -> void:
	## 出牌滑入动画：从屏幕边缘飞入对决区，仍然是牌背
	var slide_from := Vector2(-200, 0) if is_player else Vector2(200, 0)
	card_ui.position = slide_from
	var tween := card_ui.create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(card_ui, "position", Vector2.ZERO, 0.35)
	tween.tween_property(card_ui, "modulate:a", 1.0, 0.25)


func _flip_card(card_ui: Control) -> Tween:
	## 翻面动画：水平压扁→切换到正面→恢复（返回 Tween 供调用方 await tween.finished）
	# 兜底：再保证一次"开始时是牌背"，防止外部把 card_ui 当作正面绘制
	if card_ui.has_method("show_back"):
		card_ui.show_back()
	var tween := card_ui.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	# 第一步：压扁到 0（拉长到 0.28s，明显可见）
	tween.tween_property(card_ui, "scale:x", 0.0, 0.28)
	# 中间切换到正面
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui) and card_ui.has_method("show_front"):
			card_ui.show_front()
	)
	# 第二步：还原到 1.0（露出正面，0.32s）
	tween.tween_property(card_ui, "scale:x", 1.0, 0.32)
	return tween


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
