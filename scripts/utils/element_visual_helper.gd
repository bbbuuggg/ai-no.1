class_name ElementVisualHelper
extends RefCounted
## 元素+光暗 视觉绘制工具类（纯静态，无状态）
##
## v1.1 视觉规格（决策锁定版，2026-05-14）：
## - 元素色板：火/水/木 不透明铺底（覆盖 card_front_bg.png）
## - 光暗描边：金 4px / 紫黑 4px 全周描边光环
## - 元素图腾：中心水印 ~60px 直径，同色深一档 40% alpha
## - 光暗符号：☀ 八芒星 / 🌑 月牙，绘制于顶部条右侧
## - 文字色：火/水/木 底色统一用白字 + 1px 黑描边
##
## 关联：docs/design/art/elements-polarity-visual-spec.md v1.1
##      scripts/data/card_data.gd（Element / Polarity 枚举）
##      scripts/utils/element_helper.gd（数据层判定，本类只负责绘制）
##
## 设计原则：
## - 所有 API 都是纯函数 / 静态调用
## - 调用方必须是 CanvasItem（draw_* 系列只能在 _draw 上下文中调用）
## - element=NONE / polarity=NONE 时返回兼容旧外观的值或不绘制


# ============================================================================
# 元素色板（v1.1 不透明铺底）
# ============================================================================

const COLOR_FIRE := Color(0.91, 0.29, 0.16, 1.0)   # #E84A2A 暖红橙
const COLOR_WATER := Color(0.23, 0.56, 0.88, 1.0)  # #3A8FE0 冷蓝
const COLOR_WOOD := Color(0.31, 0.69, 0.31, 1.0)   # #4FB050 翠绿
const COLOR_NONE := Color(0.96, 0.94, 0.91, 1.0)   # #F5F1E8 米白（旧 reward 兼容）

# 同色深一档（用于元素图腾水印，避免白色刺眼）
const COLOR_FIRE_DARK := Color(0.541, 0.122, 0.039, 0.4)   # #8A1F0A
const COLOR_WATER_DARK := Color(0.055, 0.227, 0.416, 0.4)  # #0E3A6A
const COLOR_WOOD_DARK := Color(0.102, 0.271, 0.125, 0.4)   # #1A4520

# 光暗极性色板
const COLOR_LIGHT := Color(0.941, 0.816, 0.439, 1.0)   # #F0D070 金
const COLOR_DARK := Color(0.227, 0.102, 0.290, 1.0)    # #3A1A4A 紫黑
const COLOR_DARK_SYMBOL := Color(0.753, 0.627, 0.878, 1.0)  # #C0A0E0 紫白（黑底条上可读）

# 文字色（不透明铺底上）
const COLOR_TEXT_ON_ELEMENT := Color.WHITE
const COLOR_TEXT_OUTLINE := Color.BLACK
const COLOR_TEXT_ON_NONE := Color(0.133, 0.133, 0.133, 1.0)  # 旧路径黑字 #222

# 顶部条黑底（不透明铺底上提供文字可读性）
const COLOR_TOP_BAR_BG := Color(0, 0, 0, 0.6)

# 描边宽度
const POLARITY_BORDER_WIDTH := 4.0
const NONE_BORDER_WIDTH := 2.0


# ============================================================================
# 颜色查询 API
# ============================================================================

## 返回卡面铺底颜色（不透明）
static func get_element_color(element: int) -> Color:
	match element:
		CardData.Element.FIRE:  return COLOR_FIRE
		CardData.Element.WATER: return COLOR_WATER
		CardData.Element.WOOD:  return COLOR_WOOD
		_:                      return COLOR_NONE


## 返回元素图腾水印色（同色深一档 40% alpha）
static func get_element_totem_color(element: int) -> Color:
	match element:
		CardData.Element.FIRE:  return COLOR_FIRE_DARK
		CardData.Element.WATER: return COLOR_WATER_DARK
		CardData.Element.WOOD:  return COLOR_WOOD_DARK
		_:                      return Color(0, 0, 0, 0.0)  # NONE 不画水印


## 返回光暗描边色（外层 4px）
static func get_polarity_border_color(polarity: int) -> Color:
	match polarity:
		CardData.Polarity.LIGHT: return COLOR_LIGHT
		CardData.Polarity.DARK:  return COLOR_DARK
		_:                      return Color(0, 0, 0, 0.0)  # NONE 不画


## 返回光暗符号色（顶部条上的 ☀/🌑）
static func get_polarity_symbol_color(polarity: int) -> Color:
	match polarity:
		CardData.Polarity.LIGHT: return COLOR_LIGHT
		CardData.Polarity.DARK:  return COLOR_DARK_SYMBOL
		_:                      return Color(0, 0, 0, 0.0)


## 返回元素铺底上的文字主色
static func get_text_color_on_element(element: int) -> Color:
	if element == CardData.Element.NONE:
		return COLOR_TEXT_ON_NONE
	return COLOR_TEXT_ON_ELEMENT


## 是否需要画文字描边（不透明元素色铺底时需要）
static func needs_text_outline(element: int) -> bool:
	return element != CardData.Element.NONE


# ============================================================================
# 绘制 API（必须在 CanvasItem._draw() 上下文中调用）
# ============================================================================

## 绘制元素背景层（不透明铺底，整张卡）
## 调用位置：BaseCardUI._draw() 最底层（替换 BG_COLOR_DEFAULT）
static func draw_element_background(canvas: CanvasItem, rect: Rect2, element: int) -> void:
	var bg_color: Color = get_element_color(element)
	canvas.draw_rect(rect, bg_color, true)


## 绘制光暗描边光环（4px 外层 + 1px 内层）
## 调用位置：BaseCardUI._draw() 文字层之前（替换 accent 边框）
## 返回值：是否实际画了描边（true=画了 polarity；false=NONE，调用方应回退到旧 accent 边框）
static func draw_polarity_border(canvas: CanvasItem, rect: Rect2, polarity: int) -> bool:
	if polarity == CardData.Polarity.NONE:
		return false
	var border_color: Color = get_polarity_border_color(polarity)
	# 外层 4px 描边
	canvas.draw_rect(rect, border_color, false, POLARITY_BORDER_WIDTH)
	# 内层 1px 提亮/阴影
	var inner_rect := Rect2(
		rect.position + Vector2(POLARITY_BORDER_WIDTH, POLARITY_BORDER_WIDTH),
		rect.size - Vector2(POLARITY_BORDER_WIDTH * 2, POLARITY_BORDER_WIDTH * 2)
	)
	if polarity == CardData.Polarity.LIGHT:
		canvas.draw_rect(inner_rect, Color(1, 1, 1, 0.3), false, 1.0)
	else:  # DARK
		canvas.draw_rect(inner_rect, Color(0, 0, 0, 0.4), false, 1.0)
	return true


## 绘制顶部条黑底（不透明卡面上提供文字可读性）
## 调用位置：子类 _draw_card_front 顶部条绘制时
static func draw_top_bar_bg(canvas: CanvasItem, card_width: float, bar_height: float = 28.0) -> void:
	canvas.draw_rect(Rect2(0, 0, card_width, bar_height), COLOR_TOP_BAR_BG, true)


## 绘制元素图腾（卡面中心水印）
## cx, cy: 图腾中心
## diameter: 直径（默认 60px，BP 卡背用 80px）
## alpha_override: 可选 alpha 覆盖（默认用规格 0.4）
static func draw_element_totem(
	canvas: CanvasItem,
	element: int,
	cx: float,
	cy: float,
	diameter: float = 60.0,
	alpha_override: float = -1.0,
) -> void:
	if element == CardData.Element.NONE:
		return
	var color: Color = get_element_totem_color(element)
	if alpha_override >= 0.0:
		color.a = alpha_override
	var r: float = diameter / 2.0
	match element:
		CardData.Element.FIRE:
			_draw_fire_totem(canvas, cx, cy, r, color)
		CardData.Element.WATER:
			_draw_water_totem(canvas, cx, cy, r, color)
		CardData.Element.WOOD:
			_draw_wood_totem(canvas, cx, cy, r, color)


## 绘制光暗符号（顶部条右侧 ☀/🌑）
## x, y: 符号左上角参考点（实际中心会偏移到 x+10, y+10）
static func draw_polarity_symbol(canvas: CanvasItem, polarity: int, x: float, y: float) -> void:
	if polarity == CardData.Polarity.NONE:
		return
	var center := Vector2(x + 10, y + 10)
	var color: Color = get_polarity_symbol_color(polarity)
	match polarity:
		CardData.Polarity.LIGHT:
			_draw_sun_symbol(canvas, center, 9.0, color)
		CardData.Polarity.DARK:
			_draw_moon_symbol(canvas, center, 9.0, color)


## 绘制带描边的字符串（白字+1px 黑描边）
## 用于火/水/木 底色上的文字保证对比度
static func draw_string_outlined(
	canvas: CanvasItem,
	pos: Vector2,
	text: String,
	font_size: int,
	color: Color,
	outline_color: Color = COLOR_TEXT_OUTLINE,
	outline_size: int = 1,
) -> void:
	var font: Font = ThemeDB.fallback_font
	# Godot 4 推荐：draw_string 自带 outline
	if outline_size > 0:
		canvas.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, outline_color)
	canvas.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


# ============================================================================
# 元素图腾几何（私有）
# ============================================================================

## 火焰：3 条向上扩散的火舌轮廓
static func _draw_fire_totem(canvas: CanvasItem, cx: float, cy: float, r: float, col: Color) -> void:
	# 主火焰：尖顶 + 底部宽
	var tip := Vector2(cx, cy - r)
	var base_l := Vector2(cx - r * 0.7, cy + r * 0.5)
	var base_r := Vector2(cx + r * 0.7, cy + r * 0.5)
	# 底部弧线（用 polyline 模拟）
	var bottom_pts := PackedVector2Array([
		base_l,
		Vector2(cx - r * 0.4, cy + r * 0.7),
		Vector2(cx, cy + r * 0.6),
		Vector2(cx + r * 0.4, cy + r * 0.7),
		base_r,
	])
	# 左火舌
	canvas.draw_polyline(PackedVector2Array([base_l, Vector2(cx - r * 0.3, cy - r * 0.2), tip]), col, 2.5, true)
	# 右火舌
	canvas.draw_polyline(PackedVector2Array([base_r, Vector2(cx + r * 0.3, cy - r * 0.2), tip]), col, 2.5, true)
	# 底部
	canvas.draw_polyline(bottom_pts, col, 2.5, true)
	# 内焰（小三角，alpha 增强）
	var inner_col: Color = col
	inner_col.a = col.a * 1.3
	if inner_col.a > 1.0:
		inner_col.a = 1.0
	var inner_pts := PackedVector2Array([
		Vector2(cx, cy - r * 0.5),
		Vector2(cx - r * 0.25, cy + r * 0.2),
		Vector2(cx + r * 0.25, cy + r * 0.2),
		Vector2(cx, cy - r * 0.5),
	])
	canvas.draw_polyline(inner_pts, inner_col, 1.5, true)


## 水滴：上半圆 + 下方 V 形尖底
static func _draw_water_totem(canvas: CanvasItem, cx: float, cy: float, r: float, col: Color) -> void:
	# 上半圆：从左侧 PI 到右侧 0 顺时针（即 PI → TAU/PI×2 但我们要画的是上半部分外弧）
	var arc_center := Vector2(cx, cy + r * 0.1)
	var arc_radius: float = r * 0.7
	canvas.draw_arc(arc_center, arc_radius, PI, TAU, 24, col, 2.5)
	# 左下到尖底
	canvas.draw_line(
		Vector2(cx - arc_radius, cy + r * 0.1),
		Vector2(cx, cy + r * 0.95),
		col, 2.5
	)
	# 右下到尖底
	canvas.draw_line(
		Vector2(cx + arc_radius, cy + r * 0.1),
		Vector2(cx, cy + r * 0.95),
		col, 2.5
	)
	# 内部高光（小弧线）
	var hi_col: Color = col
	hi_col.a = col.a * 0.6
	canvas.draw_arc(
		Vector2(cx - r * 0.25, cy - r * 0.05),
		r * 0.18, PI * 1.1, PI * 1.7, 12, hi_col, 1.5
	)


## 木叶：中茎 + 两侧椭圆叶
static func _draw_wood_totem(canvas: CanvasItem, cx: float, cy: float, r: float, col: Color) -> void:
	# 中茎（垂直直线）
	canvas.draw_line(Vector2(cx, cy + r), Vector2(cx, cy - r * 0.9), col, 2.5)
	# 左叶（椭圆轮廓，向左上倾斜）
	_draw_leaf(canvas, cx, cy, r, col, true)
	# 右叶（向右上倾斜）
	_draw_leaf(canvas, cx, cy, r, col, false)


## 单片叶子：用 polyline 近似一个倾斜椭圆
static func _draw_leaf(canvas: CanvasItem, cx: float, cy: float, r: float, col: Color, is_left: bool) -> void:
	var sign_x: float = -1.0 if is_left else 1.0
	# 叶尖与叶根
	var tip := Vector2(cx + sign_x * r * 0.8, cy - r * 0.5)
	var root := Vector2(cx, cy - r * 0.05)
	# 用 8 个点近似椭圆轮廓
	var pts := PackedVector2Array()
	pts.append(root)
	# 上侧弧
	pts.append(Vector2(cx + sign_x * r * 0.25, cy - r * 0.55))
	pts.append(Vector2(cx + sign_x * r * 0.55, cy - r * 0.65))
	pts.append(tip)
	# 下侧弧
	pts.append(Vector2(cx + sign_x * r * 0.55, cy - r * 0.3))
	pts.append(Vector2(cx + sign_x * r * 0.3, cy - r * 0.15))
	pts.append(root)
	canvas.draw_polyline(pts, col, 2.0, true)


# ============================================================================
# 光暗符号几何（私有）
# ============================================================================

## ☀ 太阳：8 条辐射线 + 中心圆
static func _draw_sun_symbol(canvas: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	# 中心小圆
	canvas.draw_circle(center, radius * 0.45, col)
	# 8 条辐射线
	for i in range(8):
		var angle: float = float(i) * TAU / 8.0
		var inner := center + Vector2(cos(angle), sin(angle)) * radius * 0.55
		var outer := center + Vector2(cos(angle), sin(angle)) * radius
		canvas.draw_line(inner, outer, col, 1.5)


## 🌑 月牙：外圆减去偏移的内圆（用两个圆 + 内圆遮挡的方式实现）
## 由于 _draw 不支持布尔运算，这里用主圆 + 紧贴右侧的同色"裁剪圆"模拟
## 但因为没有真正的 mask，改用：画一个圆轮廓，再画一个偏移弧线遮住右半边以形成月牙感
static func _draw_moon_symbol(canvas: CanvasItem, center: Vector2, radius: float, col: Color) -> void:
	# 用 polyline 画月牙的两条弧形成的外形
	# 外弧：从顶部到底部，沿着左侧大半圆
	var pts_outer := PackedVector2Array()
	for i in range(13):
		var t: float = float(i) / 12.0
		var angle: float = PI * 0.5 + t * PI  # 从 90° 顺时针到 270°，走左半圆
		pts_outer.append(center + Vector2(cos(angle), sin(angle)) * radius)
	# 内弧：从底部回到顶部，但偏移过一些以形成月牙
	for i in range(13):
		var t: float = float(i) / 12.0
		var angle: float = PI * 1.5 - t * PI  # 从 270° 逆时针回到 90°
		var offset := Vector2(radius * 0.4, 0)  # 内弧整体右移
		pts_outer.append(center + Vector2(cos(angle), sin(angle)) * radius * 0.9 + offset)
	# 闭合
	pts_outer.append(pts_outer[0])
	canvas.draw_polyline(pts_outer, col, 1.8, true)
	# 中心填充（细线网格模拟实心感）
	# 简化：在月牙内部画一条对角线
	canvas.draw_line(
		center + Vector2(-radius * 0.3, -radius * 0.4),
		center + Vector2(-radius * 0.5, radius * 0.4),
		col, 1.2
	)
