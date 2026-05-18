class_name MatchupHintUI
extends Control
## 左下角常驻克制关系小 UI（v0.7.x-hotfix4）
##
## 始终显示在屏幕左下角，提示玩家三类元素的克制关系：
##   火 ▶ 木 ▶ 水 ▶ 火 （3-cycle，火克木，木克水，水克火）
##
## 紧凑尺寸（180×180），仅作视觉提示，不响应鼠标事件（mouse_filter = IGNORE）。
## 详细规则仍由右下 [?] 按钮打开 RulesOverlayUI 查看。

const COLOR_FIRE := Color(0.91, 0.29, 0.16, 1.0)   # #E84A2A 暖红橙
const COLOR_WATER := Color(0.23, 0.56, 0.88, 1.0)  # #3A8FE0 冷蓝
const COLOR_WOOD := Color(0.31, 0.69, 0.31, 1.0)   # #4FB050 翠绿
const ACCENT := Color(0.3, 0.85, 1.0, 1.0)
const PANEL_BG := Color(0.04, 0.08, 0.14, 0.85)

const PANEL_W: float = 180.0
const PANEL_H: float = 180.0

var _bg: Panel
var _title: Label
var _triangle: TriangleMini


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	# 锚到左下角（offset 由父节点位置决定，详见 tscn 中的 anchors_preset = 2）
	_build_ui()


func _build_ui() -> void:
	# 半透明深色底板
	_bg = Panel.new()
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT * Color(1, 1, 1, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.shadow_color = ACCENT * Color(1, 1, 1, 0.25)
	sb.shadow_size = 4
	_bg.add_theme_stylebox_override("panel", sb)
	add_child(_bg)

	# 标题
	_title = Label.new()
	_title.text = "克制关系"
	_title.add_theme_font_size_override("font_size", 13)
	_title.add_theme_color_override("font_color", ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.position = Vector2(0, 6)
	_title.size = Vector2(PANEL_W, 18)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)

	# 三角图主体
	_triangle = TriangleMini.new()
	_triangle.position = Vector2(0, 24)
	_triangle.size = Vector2(PANEL_W, PANEL_H - 24)
	_triangle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_triangle)


# ==================================================================
# 内部类：紧凑三角图（火/水/木 3-cycle）
# 火克木 → 木克水 → 水克火 → 火（循环）
# ==================================================================
class TriangleMini extends Control:
	const C_FIRE := Color(0.91, 0.29, 0.16, 1.0)
	const C_WATER := Color(0.23, 0.56, 0.88, 1.0)
	const C_WOOD := Color(0.31, 0.69, 0.31, 1.0)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 0 or h <= 0:
			return
		var cx: float = w / 2.0
		var cy: float = h / 2.0 + 4.0
		var radius: float = min(w, h) * 0.36
		# 顶=火（红）、左下=水（蓝）、右下=木（绿）
		var top := Vector2(cx, cy - radius)
		var bl := Vector2(cx - radius * 0.866, cy + radius * 0.5)
		var br := Vector2(cx + radius * 0.866, cy + radius * 0.5)

		# 克制箭头：火→木（top→br，红箭头），木→水（br→bl，绿箭头），水→火（bl→top，蓝箭头）
		_draw_arrow(top, br, C_FIRE)
		_draw_arrow(br, bl, C_WOOD)
		_draw_arrow(bl, top, C_WATER)

		# 三顶点节点
		_draw_node(top, C_FIRE, "🔥", "火")
		_draw_node(bl, C_WATER, "💧", "水")
		_draw_node(br, C_WOOD, "🌿", "木")

	func _draw_node(pos: Vector2, col: Color, icon: String, label: String) -> void:
		var r: float = 18.0
		# 外发光
		for i in range(2):
			var glow := col
			glow.a = 0.3 * (1.0 - float(i) / 2.0)
			draw_arc(pos, r + float(i) * 2.0, 0.0, TAU, 32, glow, 1.5)
		# 填充
		draw_circle(pos, r, col * Color(1, 1, 1, 0.25))
		# 描边
		draw_arc(pos, r, 0.0, TAU, 32, col, 1.8)
		# 图标（字体可能不带 emoji，回退用单字汉字）
		draw_string(ThemeDB.fallback_font, pos + Vector2(-7, 5), icon, HORIZONTAL_ALIGNMENT_CENTER, 14, 14, col)
		# 标签
		draw_string(ThemeDB.fallback_font, pos + Vector2(-12, r + 12), label, HORIZONTAL_ALIGNMENT_CENTER, 24, 12, col)

	func _draw_arrow(from_p: Vector2, to_p: Vector2, col: Color) -> void:
		var dir: Vector2 = (to_p - from_p).normalized()
		var start: Vector2 = from_p + dir * 22.0
		var end: Vector2 = to_p - dir * 22.0
		# 主体线
		draw_line(start, end, col, 2.0)
		# 外发光
		var glow := col
		glow.a = 0.3
		draw_line(start, end, glow, 4.0)
		# 箭头头
		var arrow_len: float = 8.0
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var p1: Vector2 = end - dir * arrow_len + perp * 4.0
		var p2: Vector2 = end - dir * arrow_len - perp * 4.0
		draw_line(end, p1, col, 2.0)
		draw_line(end, p2, col, 2.0)
