class_name BossCardUI
extends BaseCardUI
## Boss 专属卡面 UI —— 敌方风格差异化
##
## 视觉规范（由 art-director 定义）：
##   - 尺寸 150×220（与约束令/陷阱对齐，区分玩家 200×280 主视觉）
##   - 主色：血红 (0.95, 0.2, 0.25)，背景深红紫渐变
##   - 类型色沿用玩家的攻红/防青/技绿/协金（保持克制关系可读）
##   - 类型色位置：改为左侧竖条（4px 宽），而非玩家顶部横条
##   - 切角：右上 + 左下 16px 斜切（赛博敌意造型）
##   - 顶部 12px HOSTILE 警戒条（血红底，白字）
##   - 底部代号小字 "[PROC_XX]"
##   - 未使用过的牌叠 alpha 0.3 的故障错位条纹（静态）
##   - 1px 血红边框，无外发光（区别玩家青蓝外发光）

signal card_clicked(card: CardData)

# 类型色（与 CardUI 沿用，保证克制关系一致）
const TYPE_COLORS := {
	CardData.CardType.ATTACK: Color(0.9, 0.2, 0.2, 1.0),
	CardData.CardType.DEFENSE: Color(0.2, 0.7, 0.9, 1.0),
	CardData.CardType.SKILL: Color(0.2, 0.9, 0.4, 1.0),
	CardData.CardType.PROTOCOL: Color(0.9, 0.75, 0.1, 1.0),
}

const TYPE_NAMES := {
	CardData.CardType.ATTACK: "攻",
	CardData.CardType.DEFENSE: "防",
	CardData.CardType.SKILL: "技",
	CardData.CardType.PROTOCOL: "协",
}

const HOSTILE_COLOR := Color(0.95, 0.2, 0.25, 1.0)
const BG_TOP := Color(0.15, 0.05, 0.1, 0.96)
const BG_BOTTOM := Color(0.25, 0.08, 0.15, 0.96)

const CUT_SIZE := 16.0          # 斜切角大小
const HOSTILE_BAR_H := 14.0     # 顶部警戒条高
const TYPE_BAR_W := 4.0         # 左侧类型竖条宽

var card_data: CardData
var boss_code: String = "PROC_01"      # 代号（可由外部 setup 覆盖）
var show_glitch: bool = true            # 是否叠故障纹（"未使用过"视觉）


func setup(data: CardData, code: String = "PROC_01", glitch: bool = true) -> void:
	card_data = data
	boss_code = code
	show_glitch = glitch
	setup_base()


# ------------------------------------------------------------------
# BaseCardUI 覆盖：Boss 卡不使用基类的矩形卡背+边框，自绘全套
# ------------------------------------------------------------------
func get_accent_color() -> Color:
	return HOSTILE_COLOR


## 覆盖基类的整体绘制（Boss 卡有斜切角，不能用基类的 draw_rect 边框）
func _draw() -> void:
	if card_data == null:
		return

	var type_color: Color = TYPE_COLORS.get(card_data.type, Color.WHITE)
	var element: int = card_data.element
	var polarity: int = card_data.polarity
	var has_element: bool = element != CardData.Element.NONE
	var has_polarity: bool = polarity != CardData.Polarity.NONE

	# 1) 斜切角多边形背景
	var poly := _build_cut_polygon()
	if has_element:
		# v0.6.0：Boss 卡也吃元素色——但保留敌意感（叠红色调暗影）
		var elem_col: Color = ElementVisualHelper.get_element_color(element)
		# 敌意调色：往红紫方向压暗 0.85，保留 Boss 视觉一致性
		var boss_elem_col: Color = elem_col.lerp(Color(0.45, 0.10, 0.18), 0.30)
		draw_colored_polygon(poly, boss_elem_col)
		# 顶部覆盖暗紫，营造 Boss 厚重感
		var top_rect := Rect2(0, 0, CARD_WIDTH, CARD_HEIGHT * 0.4)
		draw_rect(top_rect, Color(0.10, 0.04, 0.10, 0.45), true)
	else:
		# 旧路径：双色渐变近似
		_draw_polygon_gradient(poly, BG_TOP, BG_BOTTOM)

	# 2) 故障错位条纹（静态 2 条，仅在 show_glitch 时）
	if show_glitch:
		_draw_glitch_bars()

	# 3) 顶部 HOSTILE 警戒条
	_draw_hostile_bar()

	# 4) 左侧色竖条：v0.6.0 用元素色（更亮的元素色作高亮），否则旧 type 色
	var bar_color: Color = type_color
	if has_element:
		bar_color = ElementVisualHelper.get_element_color(element)
	var type_bar := Rect2(0, HOSTILE_BAR_H, TYPE_BAR_W, CARD_HEIGHT - HOSTILE_BAR_H)
	draw_rect(type_bar, bar_color, true)

	# 5) 顶部条下方 header：v0.6.0 优先显示元素汉字 + 光暗符号 + 能耗
	var header_text: String
	var header_color: Color = bar_color
	if has_element:
		var elem_name: String = ElementHelper.element_name(element)
		header_text = "%s  ⚡%d" % [elem_name, card_data.energy_cost]
		# 光/暗 符号挂在 header 末尾（小巧不抢戏）
		if polarity == CardData.Polarity.LIGHT:
			header_text += "  ☀"
		elif polarity == CardData.Polarity.DARK:
			header_text += "  🌑"
	else:
		header_text = "%s  ⚡%d" % [TYPE_NAMES.get(card_data.type, "?"), card_data.energy_cost]
	draw_string(
		ThemeDB.fallback_font,
		Vector2(TYPE_BAR_W + 8, HOSTILE_BAR_H + 18),
		header_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - TYPE_BAR_W - 16,
		13,
		header_color,
	)

	# 6) 卡名（白字；元素卡时加 1px 黑描边以提高深色背景上的可读性）
	if has_element:
		draw_string_outline(
			ThemeDB.fallback_font,
			Vector2(TYPE_BAR_W + 8, 62),
			card_data.card_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			CARD_WIDTH - TYPE_BAR_W - 16,
			17,
			1,
			Color.BLACK,
		)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(TYPE_BAR_W + 8, 62),
		card_data.card_name,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - TYPE_BAR_W - 16,
		17,
		Color.WHITE,
	)

	# 7) 分隔线（血红细线）
	draw_line(
		Vector2(TYPE_BAR_W + 6, 74),
		Vector2(CARD_WIDTH - 10, 74),
		HOSTILE_COLOR * 0.6,
		1.0,
	)

	# 8) 效果描述（多行）
	var lines: Array[String] = _get_effect_lines()
	var y: float = 94.0
	var desc_color: Color = Color.WHITE if has_element else Color(0.9, 0.75, 0.8)
	for line in lines:
		if has_element:
			draw_string_outline(
				ThemeDB.fallback_font,
				Vector2(TYPE_BAR_W + 8, y),
				line,
				HORIZONTAL_ALIGNMENT_LEFT,
				CARD_WIDTH - TYPE_BAR_W - 16,
				12,
				1,
				Color.BLACK,
			)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(TYPE_BAR_W + 8, y),
			line,
			HORIZONTAL_ALIGNMENT_LEFT,
			CARD_WIDTH - TYPE_BAR_W - 16,
			12,
			desc_color,
		)
		y += 16.0

	# 9) 底部代号
	draw_string(
		ThemeDB.fallback_font,
		Vector2(TYPE_BAR_W + 6, CARD_HEIGHT - 6),
		"[%s]" % boss_code,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - TYPE_BAR_W - 12,
		10,
		HOSTILE_COLOR * 0.7,
	)

	# 10) 边框：v0.6.0 元素卡用光暗描边色；旧路径维持血红
	var border_color: Color
	if has_polarity:
		border_color = ElementVisualHelper.get_polarity_border_color(polarity)
	else:
		border_color = HOSTILE_COLOR if is_hovered() else HOSTILE_COLOR * 0.7
	var border_w: float = 2.0 if has_polarity else (1.5 if is_hovered() else 1.0)
	_draw_polygon_outline(poly, border_color, border_w)


# ------------------------------------------------------------------
# 绘制辅助
# ------------------------------------------------------------------
## 生成右上+左下切角的多边形顶点（顺时针）
func _build_cut_polygon() -> PackedVector2Array:
	var w: float = CARD_WIDTH
	var h: float = CARD_HEIGHT
	var c: float = CUT_SIZE
	return PackedVector2Array([
		Vector2(0, 0),            # 左上
		Vector2(w - c, 0),        # 右上切角起点
		Vector2(w, c),            # 右上切角终点
		Vector2(w, h),            # 右下
		Vector2(c, h),            # 左下切角起点
		Vector2(0, h - c),        # 左下切角终点
	])


## 渐变填充（用单色 polygon 近似：整体填底色 + 上方半透明覆盖顶色）
func _draw_polygon_gradient(poly: PackedVector2Array, top_color: Color, bottom_color: Color) -> void:
	# 底色
	draw_colored_polygon(poly, bottom_color)
	# 顶部半透明覆盖层（上半区域 0~110）
	var top_rect := Rect2(0, 0, CARD_WIDTH, CARD_HEIGHT * 0.5)
	var overlay_color: Color = top_color
	overlay_color.a = 0.6
	draw_rect(top_rect, overlay_color, true)


## 多边形描边
func _draw_polygon_outline(poly: PackedVector2Array, color: Color, width: float) -> void:
	for i in range(poly.size()):
		var p1: Vector2 = poly[i]
		var p2: Vector2 = poly[(i + 1) % poly.size()]
		draw_line(p1, p2, color, width)


## 故障错位条纹（2 条静态横向半透明条）
func _draw_glitch_bars() -> void:
	var bar1 := Rect2(0, 82.0, CARD_WIDTH, 3.0)
	var bar2 := Rect2(0, 148.0, CARD_WIDTH, 2.0)
	var glitch_color := Color(0.9, 0.3, 0.4, 0.28)
	draw_rect(bar1, glitch_color, true)
	draw_rect(bar2, glitch_color * Color(1, 1, 1, 0.7), true)


## 顶部 HOSTILE 警戒条（血红底 + 白字 + 右端菱形标记）
func _draw_hostile_bar() -> void:
	var bar_rect := Rect2(0, 0, CARD_WIDTH, HOSTILE_BAR_H)
	draw_rect(bar_rect, HOSTILE_COLOR, true)
	# 白字 "HOSTILE"
	draw_string(
		ThemeDB.fallback_font,
		Vector2(6, 11),
		"⚠ HOSTILE",
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - 28,
		10,
		Color.WHITE,
	)
	# 右端菱形标记
	var cx: float = CARD_WIDTH - 10
	var cy: float = HOSTILE_BAR_H / 2.0
	var diamond := PackedVector2Array([
		Vector2(cx, cy - 4),
		Vector2(cx + 4, cy),
		Vector2(cx, cy + 4),
		Vector2(cx - 4, cy),
	])
	draw_colored_polygon(diamond, Color.WHITE)


# ------------------------------------------------------------------
# 效果描述（复用 CardUI 的逻辑，简化版）
# ------------------------------------------------------------------
func _get_effect_lines() -> Array[String]:
	var lines: Array[String] = []
	if card_data.damage > 0:
		var dmg := "伤害 %d" % card_data.damage
		if card_data.hits > 1:
			dmg += " ×%d" % card_data.hits
		if card_data.ignore_armor:
			dmg += " 穿甲"
		lines.append(dmg)
	if card_data.armor > 0:
		lines.append("护甲 +%d" % card_data.armor)
	if card_data.heal > 0:
		lines.append("回复 %d" % card_data.heal)
	if card_data.draw_cards > 0:
		lines.append("抽 %d 张牌" % card_data.draw_cards)
	if card_data.grants_charge:
		lines.append("进入蓄力")
	if card_data.requires_charge:
		lines.append("需要: 蓄力")
	if card_data.next_attack_bonus > 0:
		lines.append("下次攻击 +%d" % card_data.next_attack_bonus)
	if card_data.all_attack_bonus > 0:
		lines.append("本回合攻击 +%d" % card_data.all_attack_bonus)
	if card_data.enemy_draw_modifier < 0:
		lines.append("下一回合抽牌%d" % card_data.enemy_draw_modifier)
	if card_data.enemy_energy_modifier < 0:
		lines.append("下一回合能量%d" % card_data.enemy_energy_modifier)
	if lines.is_empty():
		lines.append(card_data.description)
	return lines


# ------------------------------------------------------------------
# 输入（可点击用于未来的详情预览）
# ------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not _position_stored or not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if get_visual_rect_global().has_point(get_global_mouse_position()):
				card_clicked.emit(card_data)
				get_viewport().set_input_as_handled()
