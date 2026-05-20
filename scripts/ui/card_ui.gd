extends Control
## 单张卡牌 UI 组件 — 贴图底 + 动态文字层，hover 放大

signal card_clicked(card: CardData)
# v0.4.3：被干扰的牌被点击时 emit（外层 UI 用来播抖动 + toast）
signal disrupted_click_rejected(card: CardData)

const CARD_WIDTH := 200
const CARD_HEIGHT := 280
const HOVER_SCALE := 1.25
const NORMAL_SCALE := 1.0
const HOVER_LIFT := 50.0

# 贴图资源（懒加载，避免每张牌都重复加载）
const FRONT_BG_TEX_PATH := "res://assets/cards/card_front_bg.png"
const BACK_TEX_PATH := "res://assets/cards/card_back.png"
static var _cached_front_bg: Texture2D = null
static var _cached_back: Texture2D = null

var card_data: CardData
var _is_hovered: bool = false
var _base_position: Vector2 = Vector2.ZERO
var _position_stored: bool = false
var _show_back: bool = false  # true=显示牌背, false=显示正面
var _hover_disabled: bool = false  # true=禁用hover动画（适用于容器管理的卡牌）

# v0.4.3 洞察状态（持续标记）
var _is_peeked: bool = false       # 被 Boss 偷看 — 青色眼睛 + 扫描光晕
var _is_disrupted: bool = false    # 被 Boss 干扰 — 灰度 + 红锁链 + 不可点击
# 扫描光晕动画时间累计（_process 驱动 queue_redraw）
var _peek_anim_time: float = 0.0
# 抖动反馈 tween（点击 disrupted 牌时使用）
var _shake_tween: Tween = null

# 颜色映射
const TYPE_COLORS := {
	0: Color(0.9, 0.2, 0.2, 1.0),   # ATTACK - 红
	1: Color(0.2, 0.7, 0.9, 1.0),   # DEFENSE - 青
	2: Color(0.2, 0.9, 0.4, 1.0),   # SKILL - 绿
	3: Color(0.9, 0.75, 0.1, 1.0),  # PROTOCOL - 金
}

const TYPE_NAMES := {
	0: "攻击",
	1: "防御",
	2: "技能",
	3: "协议",
}


func setup(data: CardData, base_pos: Vector2 = Vector2.ZERO) -> void:
	card_data = data
	custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	pivot_offset = Vector2(CARD_WIDTH / 2.0, CARD_HEIGHT / 2.0)  # 中心缩放
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	# 显式初始化基准位置
	_base_position = base_pos
	_position_stored = true
	position = base_pos
	# 预加载贴图（仅首张牌触发）
	_ensure_textures_loaded()
	# 初始绘制
	queue_redraw()


static func _ensure_textures_loaded() -> void:
	if _cached_front_bg == null and ResourceLoader.exists(FRONT_BG_TEX_PATH):
		_cached_front_bg = load(FRONT_BG_TEX_PATH) as Texture2D
	if _cached_back == null and ResourceLoader.exists(BACK_TEX_PATH):
		_cached_back = load(BACK_TEX_PATH) as Texture2D


## 切换为牌背显示（用于Boss暗出牌等场景）
func show_back() -> void:
	_show_back = true
	queue_redraw()


## 切换为正面显示
func show_front() -> void:
	_show_back = false
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(CARD_WIDTH, CARD_HEIGHT))
	if card_data == null:
		# 卡背模式下也可能没设 card_data（极少见兜底）
		if _show_back:
			_draw_back_fallback(rect)
		return

	var element: int = card_data.element
	var polarity: int = card_data.polarity
	var has_element: bool = element != CardData.Element.NONE
	var has_polarity: bool = polarity != CardData.Polarity.NONE

	# === 牌背模式（v1.1 决策 Q2-A2：全露元素+光暗）===
	if _show_back:
		if has_element:
			# 元素色不透明铺底（替换 card_back.png）
			ElementVisualHelper.draw_element_background(self, rect, element)
			# 顶部条黑底 + 光暗符号（无能耗、无卡名）
			ElementVisualHelper.draw_top_bar_bg(self, CARD_WIDTH, 32)
			if has_polarity:
				ElementVisualHelper.draw_polarity_symbol(self, polarity, CARD_WIDTH - 30, 6)
				# 光暗汉字
				var pol_name: String = "光" if polarity == CardData.Polarity.LIGHT else "暗"
				var pol_text_color: Color = ElementVisualHelper.get_polarity_symbol_color(polarity)
				draw_string(ThemeDB.fallback_font, Vector2(CARD_WIDTH - 60, 23), pol_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, pol_text_color)
			# 中心大元素图腾（直径 110px，比正面的 60px 更显眼）
			ElementVisualHelper.draw_element_totem(
				self, element,
				CARD_WIDTH / 2.0, CARD_HEIGHT / 2.0 + 10,
				110.0, 0.55
			)
			# ??? 替代卡名
			var q_color := Color(1, 1, 1, 0.7)
			draw_string_outline(ThemeDB.fallback_font, Vector2(CARD_WIDTH / 2.0 - 30, CARD_HEIGHT - 30), "?  ?  ?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, 1, Color.BLACK)
			draw_string(ThemeDB.fallback_font, Vector2(CARD_WIDTH / 2.0 - 30, CARD_HEIGHT - 30), "?  ?  ?", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, q_color)
			# 光暗描边光环
			if has_polarity:
				ElementVisualHelper.draw_polarity_border(self, rect, polarity)
			else:
				draw_rect(rect, Color(0.5, 0.5, 0.5, 0.8), false, 2.0)
		else:
			# 无元素的旧 reward 牌：维持旧 card_back.png 路径
			_draw_back_fallback(rect)
		return

	# === 正面模式 ===
	var type_color: Color = TYPE_COLORS.get(card_data.type, Color.WHITE)

	# 1) 底层：元素铺底 / 旧贴图
	if has_element:
		ElementVisualHelper.draw_element_background(self, rect, element)
	else:
		# 旧路径：card_front_bg.png
		if _cached_front_bg != null:
			draw_texture_rect(_cached_front_bg, rect, false)
		else:
			draw_rect(rect, Color(0.08, 0.1, 0.14, 0.95), true)

	# 2) 中心元素图腾水印（在背景之上、文字之下）
	if has_element:
		ElementVisualHelper.draw_element_totem(
			self, element,
			CARD_WIDTH / 2.0, CARD_HEIGHT * 0.55,
			60.0
		)

	# 3) 顶部标记条
	if has_element:
		# v1.1：黑底 60% alpha 提供对比
		ElementVisualHelper.draw_top_bar_bg(self, CARD_WIDTH, 32)
	else:
		# 旧路径：type 色半透明
		var type_bar := Rect2(0, 0, CARD_WIDTH, 32)
		draw_rect(type_bar, type_color * Color(1.0, 1.0, 1.0, 0.45), true)

	# 4) 顶部条左侧：能耗 + 类型文字 / 能耗 + 元素文字
	var header_left_color: Color = type_color
	var header_left_text: String
	if has_element:
		# 元素卡：◆N + 元素汉字
		header_left_color = Color.WHITE
		var elem_name: String = ElementHelper.element_name(element)
		header_left_text = "◆%d  %s" % [card_data.energy_cost, elem_name]
	else:
		# 旧路径
		var type_text: String = TYPE_NAMES.get(card_data.type, "?")
		header_left_text = "%s   ◆%d" % [type_text, card_data.energy_cost]
	if has_element:
		draw_string_outline(ThemeDB.fallback_font, Vector2(8, 22), header_left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 1, Color.BLACK)
	draw_string(ThemeDB.fallback_font, Vector2(8, 22), header_left_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, header_left_color)

	# 5) 顶部条右侧：光暗符号 + 汉字
	if has_polarity:
		ElementVisualHelper.draw_polarity_symbol(self, polarity, CARD_WIDTH - 30, 6)
		var pol_name: String = "光" if polarity == CardData.Polarity.LIGHT else "暗"
		var pol_color: Color = ElementVisualHelper.get_polarity_symbol_color(polarity)
		draw_string_outline(ThemeDB.fallback_font, Vector2(CARD_WIDTH - 56, 22), pol_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 1, Color.BLACK)
		draw_string(ThemeDB.fallback_font, Vector2(CARD_WIDTH - 56, 22), pol_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, pol_color)

	# 6) 卡名（白字 + 黑描边，元素卡时；旧路径直接白字）
	var name_color: Color = Color.WHITE
	if has_element:
		draw_string_outline(ThemeDB.fallback_font, Vector2(10, 64), card_data.card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 1, Color.BLACK)
	draw_string(ThemeDB.fallback_font, Vector2(10, 64), card_data.card_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, name_color)

	# 7) 分隔线
	var sep_color: Color = Color(1, 1, 1, 0.5) if has_element else type_color * 0.5
	draw_line(Vector2(12, 76), Vector2(CARD_WIDTH - 12, 76), sep_color, 1.0)

	# 8) 效果文本（多行）
	var effect_lines: Array[String] = _get_effect_lines()
	var y_offset: float = 98.0
	var effect_color: Color = Color.WHITE if has_element else Color(0.85, 0.9, 0.95)
	for line in effect_lines:
		if has_element:
			draw_string_outline(ThemeDB.fallback_font, Vector2(10, y_offset), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 1, Color.BLACK)
		draw_string(ThemeDB.fallback_font, Vector2(10, y_offset), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, effect_color)
		y_offset += 20.0

	# 9) 边框：光暗描边 / 旧 type 边框
	var drew_polarity := false
	if has_polarity:
		drew_polarity = ElementVisualHelper.draw_polarity_border(self, rect, polarity)
	if not drew_polarity:
		# 旧路径：type 色边框 + hover 加亮
		var border_color: Color = type_color if _is_hovered else type_color * 0.6
		var border_width: float = 3.0 if _is_hovered else 1.5
		draw_rect(rect, border_color, false, border_width)

	# v0.4.3 洞察持续标记叠加层（在最上层，越过类型条/效果文本）
	if _is_disrupted:
		_draw_disrupt_overlay(rect)
	elif _is_peeked:
		_draw_peek_overlay(rect)


## 牌背 fallback：当卡数据为 NONE 元素或缺失时，走旧 card_back.png 路径
func _draw_back_fallback(rect: Rect2) -> void:
	if _cached_back != null:
		draw_texture_rect(_cached_back, rect, false)
	else:
		draw_rect(rect, Color(0.05, 0.08, 0.12, 1.0), true)
		draw_rect(rect, Color(0.0, 0.7, 0.9, 0.8), false, 2.0)


# ------------------------------------------------------------------
# v0.4.3 洞察持续状态绘制
# ------------------------------------------------------------------
const PEEK_COLOR := Color(0.0, 0.9, 1.0, 1.0)
const DISRUPT_COLOR := Color(1.0, 0.16, 0.16, 1.0)


## peek：左上角青色眼睛图标 + 边缘呼吸式扫描光晕（不影响点击）
func _draw_peek_overlay(rect: Rect2) -> void:
	# 1) 边缘呼吸光晕（青色）
	var pulse: float = 0.5 + 0.5 * sin(_peek_anim_time * TAU * 0.5)  # 2s 一周期
	var glow_color := PEEK_COLOR
	glow_color.a = 0.18 + 0.22 * pulse
	for i in range(3):
		var expand := float(i + 1) * 1.5
		var glow_rect := Rect2(rect.position - Vector2(expand, expand), rect.size + Vector2(expand * 2, expand * 2))
		var c := glow_color
		c.a *= 1.0 - (float(i) / 4.0)
		draw_rect(glow_rect, c, false, 1.5)
	# 2) 上下游走的扫描线（青色细线）
	var scan_y: float = fmod(_peek_anim_time * 90.0, CARD_HEIGHT - 20.0) + 10.0
	var scan_color := PEEK_COLOR
	scan_color.a = 0.55
	draw_line(Vector2(6, scan_y), Vector2(CARD_WIDTH - 6, scan_y), scan_color, 1.5)
	# 3) 左上角眼睛图标（22×22 简化版：椭圆 + 圆心瞳孔）
	var eye_center := Vector2(20, 20)
	var bg := Color(0.06, 0.04, 0.1, 0.85)
	draw_circle(eye_center, 12.0, bg)
	draw_arc(eye_center, 12.0, 0.0, TAU, 24, PEEK_COLOR, 1.5)
	# 椭圆瞳孔（用线条近似）
	draw_circle(eye_center, 4.5, PEEK_COLOR)
	draw_circle(eye_center, 2.0, Color(0.06, 0.04, 0.1, 1.0))


## disrupt：整张灰度+红色锁链+中央封印（覆盖正面，禁用点击由外部处理）
func _draw_disrupt_overlay(rect: Rect2) -> void:
	# 1) 灰度蒙版（半透深色降低饱和度）
	draw_rect(rect, Color(0.0, 0.0, 0.0, 0.45), true)
	# 2) 斜向锁链（左上→右下，5 节链节，宽 12）
	var chain_color := DISRUPT_COLOR
	chain_color.a = 0.85
	var p_start := Vector2(8, 8)
	var p_end := Vector2(CARD_WIDTH - 8, CARD_HEIGHT - 8)
	# 主线
	draw_line(p_start, p_end, chain_color, 6.0)
	# 链节小圈（每隔 ~50px 一个）
	var dist: float = p_start.distance_to(p_end)
	var dir: Vector2 = (p_end - p_start) / dist
	var seg_count: int = int(dist / 48.0)
	for i in range(1, seg_count):
		var pt: Vector2 = p_start + dir * (float(i) * 48.0)
		draw_circle(pt, 8.0, Color(0.06, 0.04, 0.1, 1.0))
		draw_arc(pt, 8.0, 0.0, TAU, 16, chain_color, 2.0)
	# 3) 中央红色 × 封印（60×60）
	var center := Vector2(CARD_WIDTH / 2.0, CARD_HEIGHT / 2.0)
	var size_half := 30.0
	# 红圆背景
	draw_circle(center, size_half + 4.0, Color(0.06, 0.04, 0.1, 0.92))
	draw_arc(center, size_half + 4.0, 0.0, TAU, 32, DISRUPT_COLOR, 2.5)
	# × 笔画
	draw_line(center + Vector2(-size_half * 0.55, -size_half * 0.55),
		center + Vector2(size_half * 0.55, size_half * 0.55), DISRUPT_COLOR, 5.0)
	draw_line(center + Vector2(-size_half * 0.55, size_half * 0.55),
		center + Vector2(size_half * 0.55, -size_half * 0.55), DISRUPT_COLOR, 5.0)
	# 4) 边框红色高亮
	draw_rect(rect, DISRUPT_COLOR, false, 3.0)


## v0.4.3 持续标记 API：被 Boss 偷看（不影响点击）
func set_peeked(enabled: bool) -> void:
	if _is_peeked == enabled:
		return
	_is_peeked = enabled
	_peek_anim_time = 0.0
	queue_redraw()


## v0.4.3 持续标记 API：被 Boss 干扰（外部应同时禁用点击）
func set_disrupted(enabled: bool) -> void:
	if _is_disrupted == enabled:
		return
	_is_disrupted = enabled
	if enabled:
		# 干扰锁定时取消 hover 状态，恢复原尺寸位置
		_is_hovered = false
		scale = Vector2.ONE
		if _position_stored:
			position = _base_position
		z_index = 0
	queue_redraw()


func is_disrupted() -> bool:
	return _is_disrupted


func is_peeked() -> bool:
	return _is_peeked


## v0.4.3：玩家点击被干扰的牌时调用 — 整张牌左右抖动 0.3s（视觉拒绝反馈）
func play_disrupt_reject_shake() -> void:
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var origin: Vector2 = _base_position if _position_stored else position
	_shake_tween = create_tween()
	_shake_tween.set_trans(Tween.TRANS_SINE)
	# 左右抖动 3 次 ±8px
	for i in range(3):
		_shake_tween.tween_property(self, "position", origin + Vector2(-8, 0), 0.05)
		_shake_tween.tween_property(self, "position", origin + Vector2(8, 0), 0.05)
	_shake_tween.tween_property(self, "position", origin, 0.05)


## v0.4.3：返回卡牌全局中心点（供 ProbeDisplayUI 宣告动画作锚点）
func get_global_center() -> Vector2:
	return global_position + size / 2.0


## v0.4.3：播放被夺取的销毁动画（裂缝→碎片→真空吸入）。返回总时长（秒）。
## 注意：这里只播放卡片自身的"撕裂消失"。屏幕色差与吸入到 Boss 的轨迹由 ProbeDisplayUI 负责。
func play_seize_destruction() -> float:
	# 中心 pivot 已在 setup 时设好
	var t := create_tween().set_parallel(true)
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# 0~0.4s：先放大轻抖（裂缝出现）；0.4~1.0s：缩小+旋转+淡出（碎片吸走）
	t.tween_property(self, "scale", Vector2(1.15, 0.85), 0.4)
	t.chain().tween_property(self, "scale", Vector2(0.0, 0.0), 0.6)
	t.parallel().tween_property(self, "rotation_degrees", rotation_degrees + 35.0, 1.0)
	t.parallel().tween_property(self, "modulate:a", 0.0, 1.0)
	return 1.0


func _get_effect_lines() -> Array[String]:
	var lines: Array[String] = []
	if card_data.damage > 0:
		var dmg_text: String = "伤害 %d" % card_data.damage
		if card_data.hits > 1:
			dmg_text += " ×%d" % card_data.hits
		if card_data.ignore_armor:
			dmg_text += " (穿甲)"
		lines.append(dmg_text)
	if card_data.armor > 0:
		lines.append("护甲 +%d" % card_data.armor)
	if card_data.heal > 0:
		lines.append("回复 %d" % card_data.heal)
	if card_data.draw_cards > 0:
		lines.append("抽 %d 张牌" % card_data.draw_cards)
	if card_data.grants_charge:
		lines.append("进入蓄力状态")
	if card_data.requires_charge:
		lines.append("需要: 蓄力")
	if card_data.next_attack_bonus > 0:
		lines.append("下次攻击 +%d" % card_data.next_attack_bonus)
	if card_data.all_attack_bonus > 0:
		lines.append("本回合攻击 +%d" % card_data.all_attack_bonus)
	if card_data.energy_next_turn > 0:
		lines.append("下回合能量 +%d" % card_data.energy_next_turn)
	if card_data.enemy_draw_modifier < 0:
		lines.append("对手下回合抽牌%d" % card_data.enemy_draw_modifier)
	if card_data.enemy_energy_modifier < 0:
		lines.append("对手下回合能量%d" % card_data.enemy_energy_modifier)
	if card_data.discard_hand_and_draw > 0:
		lines.append("弃全部手牌抽 %d" % card_data.discard_hand_and_draw)
	if card_data.gain_constraint_resource > 0:
		lines.append("约束资源 +%d" % card_data.gain_constraint_resource)
	if lines.is_empty():
		lines.append(card_data.description)
	return lines


func _gui_input(_event: InputEvent) -> void:
	# 不再依赖 _gui_input，改为在 _process 中处理全局鼠标事件
	pass


func _input(event: InputEvent) -> void:
	if not _position_stored:
		return
	if not is_visible_in_tree():
		return  # 自己或父节点不可见时不响应
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# v0.7.0-alpha-pick.5 hotfix.5：双重命中保险——
			#   实时矩形（含 hover lift+scale）OR 稳定 base 矩形（同 hover 进入判定）
			#   覆盖 tween 过程中的所有可能位置，避免"能 hover 但点不动"
			var mouse_pos: Vector2 = get_global_mouse_position()
			var visual_rect: Rect2 = _get_visual_rect_global()
			var base_rect: Rect2 = _get_stable_base_rect_global()
			var hit: bool = visual_rect.has_point(mouse_pos) or base_rect.has_point(mouse_pos)
			# 诊断：如果鼠标点击但矩形未命中，打印一行帮助定位
			if card_data != null and not hit:
				# 只在鼠标"接近"卡牌（hover 矩形扩大版）时打印，避免刷屏
				var diag_rect: Rect2 = base_rect.grow(40.0)
				if diag_rect.has_point(mouse_pos):
					print("[CardUI MISS] card=%s mouse=%s visual=%s base=%s" % [
						card_data.card_name, mouse_pos, visual_rect, base_rect
					])
			if hit:
				if _is_disrupted:
					# v0.4.3：被干扰牌不可选 — emit reject 让外层播抖动 + toast
					disrupted_click_rejected.emit(card_data)
					play_disrupt_reject_shake()
					get_viewport().set_input_as_handled()
					return
				print("[CardUI CLICK] card=%s emit card_clicked" % card_data.card_name)
				card_clicked.emit(card_data)
				get_viewport().set_input_as_handled()


func _has_point(point: Vector2) -> bool:
	return Rect2(Vector2.ZERO, size).has_point(point)


func _process(delta: float) -> void:
	if card_data == null:
		return
	# v0.4.3：peek 光晕呼吸动画（无视 hover_disabled，因为暗出区也想看到这个状态）
	if _is_peeked:
		_peek_anim_time += delta
		queue_redraw()
	if not _position_stored:
		# 未被外部设置 base_position，暂不启用 hover 追踪（避免跳到0,0）
		return
	if _hover_disabled:
		return  # 禁用hover（如暗出选入区的卡牌）
	if _is_disrupted:
		# 被干扰时不响应 hover（保持原位 + 锁链覆盖层）
		if _is_hovered:
			_is_hovered = false
			_animate_hover(false)
		return
	# 使用稳定的判定矩形（始终基于 base_position 计算，不受 hover 状态影响）
	var mouse_pos_global: Vector2 = get_global_mouse_position()
	var should_hover: bool = _is_mouse_inside_stable(mouse_pos_global)
	if should_hover != _is_hovered:
		_is_hovered = should_hover
		_animate_hover(should_hover)
		queue_redraw()


func _is_mouse_inside_stable(mouse_pos_global: Vector2) -> bool:
	## 稳定的 hover 判定：始终以基准位置+原始尺寸计算，
	## 通过滞后阈值（进入窄、退出宽）避免边缘抖动。
	var parent_ctrl: Control = get_parent() as Control
	var parent_global: Vector2 = parent_ctrl.global_position if parent_ctrl else Vector2.ZERO
	var base_global: Vector2 = parent_global + _base_position
	var base_rect := Rect2(base_global, size)

	# 进入 hover 时判定窄一点（hover 灵敏），退出时放宽 8px（避免 tween 过程抖动）
	if _is_hovered:
		# 已 hover，退出阈值放宽：用放大后的矩形判定（tween 完成后是这个尺寸）
		var scaled_size := size * HOVER_SCALE
		var scaled_center := base_global + size / 2.0 + Vector2(0, -HOVER_LIFT)
		var enlarged_rect := Rect2(scaled_center - scaled_size / 2.0, scaled_size)
		enlarged_rect = enlarged_rect.grow(8.0)  # 再外扩8px滞后
		return enlarged_rect.has_point(mouse_pos_global)
	else:
		# 未 hover，用原始矩形判定
		return base_rect.has_point(mouse_pos_global)


## 禁用hover动画（适用于VBox等容器管理位置的场景）
func disable_hover() -> void:
	_hover_disabled = true
	_is_hovered = false
	scale = Vector2.ONE
	z_index = 0
	queue_redraw()


func _get_visual_rect_global() -> Rect2:
	## 用于点击判定——覆盖当前实际视觉范围
	## v0.7.0-alpha-pick.5 hotfix.5：彻底重写，支持 wrapper 模式（父节点持 scale）。
	##
	## 关键事实：
	##   - self.size 永远是 200×280（原始 CARD_WIDTH×CARD_HEIGHT），不受任何 scale 影响
	##   - 父节点（wrapper）可能持有 scale（如 0.85），导致视觉尺寸 = size × parent.scale
	##   - hover 时 self.scale 被 tween 改成 (1.25,1.25)，并对 self.position 做 -HOVER_LIFT 上移
	##   - parent.global_position 是 wrapper 在 viewport 的左上点（已经过其父级链变换）
	##   - 视觉左上锚点 = parent.global_position + self.position * parent.scale
	##     （hover 时 self.position = _base_position + (0, -HOVER_LIFT)，scale 已自动包进 base 计算）
	##   - 视觉尺寸 = self.size × parent.scale × self.scale
	##
	## 与 hover 判定 _is_mouse_inside_stable 的区别：那里用的是原始 base_position（无 lift），
	## 这里要跟随当前实际渲染位置（含 lift），否则鼠标 hover 后卡片飘走但命中矩形还在原地。
	var parent_ctrl: Control = get_parent() as Control
	var parent_global: Vector2 = parent_ctrl.global_position if parent_ctrl else Vector2.ZERO
	var parent_scale: Vector2 = parent_ctrl.scale if parent_ctrl else Vector2.ONE

	# 当前实际渲染左上点 = 父global + self.position × 父scale
	var visual_top_left: Vector2 = parent_global + position * parent_scale
	# 当前实际渲染尺寸 = size × 父scale × self.scale
	var visual_size: Vector2 = size * parent_scale * scale

	# 容差：外扩 6px，方便点击边缘
	return Rect2(visual_top_left - Vector2(6, 6), visual_size + Vector2(12, 12))


func _get_stable_base_rect_global() -> Rect2:
	## v0.7.0-alpha-pick.5 hotfix.5：稳定基准矩形——以 _base_position（不含 hover lift）为锚点。
	## 用于点击双重命中：即使 hover tween 还在进行中或 hover 已飘起来，
	## 鼠标若仍在卡牌**原始视觉位置**（base_position）上也能点中。
	var parent_ctrl: Control = get_parent() as Control
	var parent_global: Vector2 = parent_ctrl.global_position if parent_ctrl else Vector2.ZERO
	var parent_scale: Vector2 = parent_ctrl.scale if parent_ctrl else Vector2.ONE
	var base_top_left: Vector2 = parent_global + _base_position * parent_scale
	var base_size: Vector2 = size * parent_scale  # 不乘 self.scale，永远是非 hover 视觉尺寸
	return Rect2(base_top_left - Vector2(6, 6), base_size + Vector2(12, 12))


func set_base_position(pos: Vector2) -> void:
	_base_position = pos
	_position_stored = true
	position = pos


func _animate_hover(hover: bool) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	if hover:
		tween.tween_property(self, "scale", Vector2(HOVER_SCALE, HOVER_SCALE), 0.15)
		tween.parallel().tween_property(self, "position", _base_position + Vector2(0, -HOVER_LIFT), 0.15)
		z_index = 10
	else:
		tween.tween_property(self, "scale", Vector2(NORMAL_SCALE, NORMAL_SCALE), 0.15)
		tween.parallel().tween_property(self, "position", _base_position, 0.15)
		z_index = 0
