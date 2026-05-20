extends Control
## 对决翻牌演出 UI — 逐张翻开 + 克制视觉反馈
##
## v0.3 改造（Epic-BP-7 翻盅回归）：
##   - 节奏参数化：SLIDE_IN_DUR / STANDOFF_DUR / FLIP_DUR / RESOLVE_DUR
##   - 克制视觉化：金色边框 + 1.05× 缩放 + 屏震，弱化"克制!"文字
##   - Space 跳过键：单击跳过当前对（_skip_current_pair=true）+ 长按 ×0.3 加速
##   - 总演出时长 ~11.2s（4 对 × ~2.8s）

signal clash_animation_complete()

const CardUI := preload("res://scripts/ui/card_ui.gd")

# === 节奏参数（v0.3 §2.1）===
const SLIDE_IN_DUR: float = 0.30   # 滑入起始
const STANDOFF_DUR: float = 0.40   # 牌背对峙
const FLIP_DUR: float = 0.50       # 翻面（压扁→还原）
const RESOLVE_DUR: float = 1.60    # 结算停留（看清结果 + 飘字播完）

# === 克制视觉色（v0.3 §3.2 收敛）===
const COUNTER_PLAYER_COLOR := Color(0.2, 1.0, 0.5, 1.0)  # 玩家克制 - 绿光
const COUNTER_BOSS_COLOR := Color(1.0, 0.3, 0.3, 1.0)  # Boss克制 - 红光
const NEUTRAL_COLOR := Color(0.8, 0.8, 0.8, 0.9)  # 中立 - 灰白
const FREE_COLOR := Color(0.0, 0.85, 1.0, 1.0)  # 多余牌 - 青
const COUNTER_HIGHLIGHT_GOLD := Color(1.0, 0.85, 0.3, 1.0)  # 克制方金色边框 + 1.05×

# === Space 跳过键状态 ===
var _skip_current_pair: bool = false
var _hold_speedup: bool = false  # Space 长按 → 时间缩放 ×0.3

var _results: Array = []  # Array[ClashResolver.ClashResult]
var _current_index: int = 0
var _is_playing: bool = false
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
	# 让本 UI 在演出期间能接 Space input
	set_process_unhandled_input(false)


func start_clash_animation(results: Array, apply_cb: Callable = Callable()) -> void:
	_results = results
	_current_index = 0
	_is_playing = true
	_apply_cb = apply_cb
	_skip_current_pair = false
	_hold_speedup = false
	visible = true
	# v0.4.3 修复：场景里 HBox 默认 visible=false（防编辑器阶段误显示），运行时必须强制打开。
	# 不打开会导致翻牌动画完全看不到（牌都 add_child 到 HBox 的孙节点 CardSlot）。
	var hbox := $HBox
	if hbox != null:
		hbox.visible = true
	# 演出期间监听 Space 跳过键
	set_process_unhandled_input(true)
	_show_next_pair()


func _unhandled_input(event: InputEvent) -> void:
	## v0.3 §6 Space 跳过键：
	##   - 短按（按下 → 抬起 < 0.3s）：跳过当前对到下一对
	##   - 长按（持续按住）：演出 ×0.3 加速（实际由各 await 动态读 _hold_speedup）
	if not _is_playing:
		return
	if event is InputEventKey:
		var key_event: InputEventKey = event
		if key_event.keycode == KEY_SPACE:
			if key_event.pressed and not key_event.echo:
				_hold_speedup = true
				_skip_current_pair = true  # 单击同时也跳过当前对
			elif not key_event.pressed:
				_hold_speedup = false


## 当前节奏因子（长按 Space 时为 0.3，否则为 1.0）
func _speed_factor() -> float:
	return 0.3 if _hold_speedup else 1.0


## 等待秒数（自动应用 _speed_factor）
func _wait(seconds: float) -> void:
	var dur: float = max(0.01, seconds * _speed_factor())
	await get_tree().create_timer(dur).timeout


func _show_next_pair() -> void:
	if _current_index >= _results.size():
		_finish_animation()
		return

	# 每对开始前重置跳过 flag
	_skip_current_pair = false

	var result: ClashResolver.ClashResult = _results[_current_index]
	pair_counter.text = "第 %d/%d 对" % [_current_index + 1, _results.size()]

	# 清空旧内容
	_clear_area(player_card_area)
	_clear_area(boss_card_area)
	multiplier_label_player.text = ""
	multiplier_label_boss.text = ""
	versus_label.text = "..."
	versus_label.add_theme_color_override("font_color", NEUTRAL_COLOR)
	# 复位卡区缩放（防上一对克制方残留 1.05×）
	player_card_area.scale = Vector2.ONE
	boss_card_area.scale = Vector2.ONE
	player_card_area.modulate = Color.WHITE
	boss_card_area.modulate = Color.WHITE

	# === 阶段1：双方同时"出牌背" ===
	var player_ui: Control = null
	var boss_ui: Control = null

	if result.player_card != null:
		player_ui = _create_card_display(result.player_card)
		player_card_area.add_child(player_ui)
		player_ui.show_back()
		_play_in_animation(player_ui, true)
	else:
		_show_empty_slot(player_card_area, "—")

	if result.boss_card != null:
		boss_ui = _create_card_display(result.boss_card)
		boss_card_area.add_child(boss_ui)
		boss_ui.show_back()
		_play_in_animation(boss_ui, false)
	else:
		_show_empty_slot(boss_card_area, "—")

	# 等滑入完成（_play_in_animation 0.30s + 0.05 缓冲）
	await _wait(SLIDE_IN_DUR + 0.05)
	if _skip_current_pair:
		await _fast_forward_to_resolve(player_ui, boss_ui, result)
		return

	# === 阶段2：牌背对峙 STANDOFF_DUR ===
	await _wait(STANDOFF_DUR)
	if _skip_current_pair:
		await _fast_forward_to_resolve(player_ui, boss_ui, result)
		return

	# === 阶段3：双方同时翻面（_flip_card 内部 ~FLIP_DUR）===
	var flip_tween_player: Tween = null
	var flip_tween_boss: Tween = null
	if player_ui != null:
		flip_tween_player = _flip_card(player_ui)
	if boss_ui != null:
		flip_tween_boss = _flip_card(boss_ui)
	if flip_tween_player != null:
		await flip_tween_player.finished
	elif flip_tween_boss != null:
		await flip_tween_boss.finished
	else:
		await _wait(FLIP_DUR)

	# === 阶段3.5：翻面完成 → 提交本对伤害（apply_cb）===
	if _apply_cb.is_valid():
		_apply_cb.call(_current_index)
		await get_tree().process_frame

	# === 阶段4：显示克制结果（金色边框 + 1.05× 缩放 + 屏震）===
	_show_clash_result(result)

	# === 阶段5：结算停留 RESOLVE_DUR ===
	# v0.9.4：本对触发玩家 2:2 平衡 → 延长 0.8s 让玩家看清"⚡+1"脉冲（含金色文字 + 跳动）
	var resolve_extra: float = 0.8 if result.balanced_bonus else 0.0
	await _wait(RESOLVE_DUR + resolve_extra)

	_current_index += 1
	_show_next_pair()


## 跳过当前对的快进路径：直接显示克制结果 + 短停留 + apply_cb，进入下一对
func _fast_forward_to_resolve(player_ui: Control, boss_ui: Control, result: ClashResolver.ClashResult) -> void:
	# 如果还没翻面，直接 show_front
	if player_ui != null and player_ui.has_method("show_front"):
		player_ui.show_front()
	if boss_ui != null and boss_ui.has_method("show_front"):
		boss_ui.show_front()
	if _apply_cb.is_valid():
		_apply_cb.call(_current_index)
		await get_tree().process_frame
	_show_clash_result(result)
	# 跳过模式下停留缩短到 0.4s 让玩家瞄一眼
	await get_tree().create_timer(0.4).timeout
	_current_index += 1
	_show_next_pair()


func _show_clash_result(result: ClashResolver.ClashResult) -> void:
	result_label.clear()

	match result.clash_type:
		"counter_player":
			# v0.3：弱化"克制!"文字 → 用 VS + 小字提示
			versus_label.text = "VS"
			versus_label.add_theme_color_override("font_color", COUNTER_PLAYER_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 1.5, result.balanced_bonus)
			multiplier_label_player.add_theme_color_override("font_color", COUNTER_PLAYER_COLOR)
			multiplier_label_boss.text = _format_calc(result.boss_card, 0.5)
			multiplier_label_boss.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			# 克制方视觉化：金色边框 + 1.05× 缩放 + 屏震
			_apply_counter_highlight(player_card_area)
			_flash_border(player_card_area, COUNTER_PLAYER_COLOR)
			_screen_shake()

		"counter_boss":
			versus_label.text = "VS"
			versus_label.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 0.5, result.balanced_bonus)
			multiplier_label_player.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			multiplier_label_boss.text = _format_calc(result.boss_card, 1.5)
			multiplier_label_boss.add_theme_color_override("font_color", COUNTER_PLAYER_COLOR)
			_apply_counter_highlight(boss_card_area)
			_flash_border(boss_card_area, COUNTER_BOSS_COLOR)
			_screen_shake()

		"neutral":
			versus_label.text = "VS"
			versus_label.add_theme_color_override("font_color", NEUTRAL_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 1.0, result.balanced_bonus)
			multiplier_label_player.add_theme_color_override("font_color", NEUTRAL_COLOR)
			multiplier_label_boss.text = _format_calc(result.boss_card, 1.0)
			multiplier_label_boss.add_theme_color_override("font_color", NEUTRAL_COLOR)

		"free_player":
			versus_label.text = "无对手"
			versus_label.add_theme_color_override("font_color", FREE_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 1.0, result.balanced_bonus) + " 直接生效"
			multiplier_label_player.add_theme_color_override("font_color", FREE_COLOR)
			multiplier_label_boss.text = ""

		"free_boss":
			versus_label.text = "无对手"
			versus_label.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			multiplier_label_player.text = ""
			multiplier_label_boss.text = _format_calc(result.boss_card, 1.0) + " 直接生效"
			multiplier_label_boss.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)

		"unopposed_player":
			versus_label.text = "毫无阻力×2"
			versus_label.add_theme_color_override("font_color", FREE_COLOR)
			multiplier_label_player.text = _format_calc(result.player_card, 2.0, result.balanced_bonus) + " 毫无阻力×2"
			multiplier_label_player.add_theme_color_override("font_color", FREE_COLOR)
			multiplier_label_boss.text = ""
			_apply_counter_highlight(player_card_area)
			_screen_shake()

		"unopposed_boss":
			versus_label.text = "毫无阻力×2"
			versus_label.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			multiplier_label_player.text = ""
			multiplier_label_boss.text = _format_calc(result.boss_card, 2.0) + " 毫无阻力×2"
			multiplier_label_boss.add_theme_color_override("font_color", COUNTER_BOSS_COLOR)
			_apply_counter_highlight(boss_card_area)
			_screen_shake()

	# v0.9.4：玩家方 2:2 平衡触发 → 玩家计算式 Label 跳动金色脉冲，强化"⚡+1"可见度
	if result.balanced_bonus and result.player_card != null:
		_pulse_balanced_label(multiplier_label_player)


## v0.9.4：平衡 +1 强调脉冲（金色 + 1.15 倍跳动 + 持续脉冲，让玩家清楚看到 ⚡+1）
func _pulse_balanced_label(label: Label) -> void:
	if label == null:
		return
	const GOLD := Color(1.0, 0.85, 0.3, 1.0)
	# 字号瞬时放大 ×1.0 → ×1.18 → ×1.0，做 2 次脉冲
	label.add_theme_color_override("font_color", GOLD)
	label.pivot_offset = label.size * 0.5
	var tw: Tween = label.create_tween().set_loops(2)
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(label, "scale", Vector2(1.18, 1.18), 0.30)
	tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.30)


## 克制方视觉强化：金色边框模拟（modulate 偏金）+ 1.05× 缩放
func _apply_counter_highlight(area: Control) -> void:
	var tw: Tween = area.create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(area, "scale", Vector2(1.05, 1.05), 0.18)
	# 借 modulate 偏金色营造金边感（无独立边框节点，简化实现）
	tw.tween_property(area, "modulate", COUNTER_HIGHLIGHT_GOLD, 0.18)


## 屏震：本 UI 自身位置短促抖动（非全局相机震动，避免影响 PickUI 收尾过渡）
func _screen_shake() -> void:
	var orig_pos: Vector2 = position
	var tw: Tween = create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	for i in range(5):
		var offset := Vector2(randf_range(-6, 6), randf_range(-4, 4))
		tw.tween_property(self, "position", orig_pos + offset, 0.04)
	tw.tween_property(self, "position", orig_pos, 0.05)


func _create_card_display(card: CardData) -> Control:
	var card_ui := Control.new()
	card_ui.set_script(CardUI)
	card_ui.setup(card)
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
	tween.tween_property(card_ui, "position", Vector2.ZERO, SLIDE_IN_DUR)
	tween.tween_property(card_ui, "modulate:a", 1.0, SLIDE_IN_DUR * 0.7)


func _flip_card(card_ui: Control) -> Tween:
	## 翻面动画：水平压扁→切换到正面→恢复（返回 Tween 供调用方 await tween.finished）
	if card_ui.has_method("show_back"):
		card_ui.show_back()
	var tween := card_ui.create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	# 第一步：压扁到 0
	tween.tween_property(card_ui, "scale:x", 0.0, FLIP_DUR * 0.5)
	# 中间切换到正面
	tween.tween_callback(func() -> void:
		if is_instance_valid(card_ui) and card_ui.has_method("show_front"):
			card_ui.show_front()
	)
	# 第二步：还原到 1.0
	tween.tween_property(card_ui, "scale:x", 1.0, FLIP_DUR * 0.5)
	return tween


func _format_calc(card: CardData, multiplier: float, balanced_plus_one: bool = false) -> String:
	## 生成 "数值 ×倍率 = 结果" 的计算式文本
	## v0.3 §3.4 色弱兼容：在数值前加符号前缀（↓伤害 / ↑增益 / 🛡甲 / 🃏抽）
	## v0.9.4：balanced_plus_one=true 时，倍率后追加 [color=#ffd84d]+1[/color] 平衡加成
	##         返回值带 BBCode，调用方需用 RichTextLabel 才能正确显示颜色（这里 Label 也能容忍，
	##         但金色 +1 会被去掉。为兼容已有 Label，用单色 emoji ⚡ 标记代替 BBCode。）
	if card == null:
		return ""
	var base_value: int = 0
	var value_type: String = ""
	var prefix: String = ""
	# v0.9.4：是否为受 +1 加成的字段类型（仅 dmg/armor/heal）
	var plus_one_applies: bool = false
	if card.damage > 0:
		base_value = card.damage
		value_type = "伤害"
		prefix = "↓"
		if card.hits > 1:
			value_type = "伤害×%d" % card.hits
		plus_one_applies = balanced_plus_one
	elif card.armor > 0:
		base_value = card.armor
		value_type = "护甲"
		prefix = "🛡"
		plus_one_applies = balanced_plus_one
	elif card.heal > 0:
		base_value = card.heal
		value_type = "回复"
		prefix = "↑"
		plus_one_applies = balanced_plus_one
	elif card.draw_cards > 0:
		base_value = card.draw_cards
		value_type = "抽牌"
		prefix = "🃏"
	else:
		# 无数值效果的牌（蓄力等）
		if multiplier < 1.0:
			return "效果减半 → 失效"
		return "×%.1f" % multiplier

	# v0.9.4：先按倍率算
	var mid_value: int = ceili(float(base_value) * multiplier)
	# 再按平衡 +1
	var final_value: int = mid_value + (1 if plus_one_applies else 0)

	if multiplier == 1.0:
		if plus_one_applies:
			# 1.0 倍率 + +1：直接 5 +1 = 6
			return "%s%d ⚡+1 = %d %s" % [prefix, base_value, final_value, value_type]
		return "%s%d %s" % [prefix, base_value, value_type]
	else:
		if plus_one_applies:
			# 5 ×1.5 ⚡+1 = 9
			return "%s%d ×%.1f ⚡+1 = %d %s" % [prefix, base_value, multiplier, final_value, value_type]
		return "%s%d ×%.1f = %d %s" % [prefix, base_value, multiplier, final_value, value_type]


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
	set_process_unhandled_input(false)
	# 复位克制方残留 scale/modulate
	player_card_area.scale = Vector2.ONE
	boss_card_area.scale = Vector2.ONE
	player_card_area.modulate = Color.WHITE
	boss_card_area.modulate = Color.WHITE
	await get_tree().create_timer(0.3).timeout
	visible = false
	clash_animation_complete.emit()
