class_name TrapCardUI
extends BaseCardUI
## 陷阱牌卡片 UI —— 青蓝⚠标识，与"约束令家族"共享卡片视觉语言
##
## 视觉规范（由 art-director 定义）：
##   accent: Color(0.2, 0.85, 0.95)  青蓝
##   顶部标记条: "消耗 ⚡N ｜ 触发：<槽位图标>"
##   卡面中心: 触发类型图腾水印（40% alpha）
##     - ATTACK    → 红色剑形  (0.9, 0.2, 0.2)
##     - SKILL     → 绿色齿轮  (0.2, 0.9, 0.4)
##     - HIGH_COST → 金色闪电  (0.9, 0.75, 0.1)
##   诱饵牌(is_bluff): 与真陷阱同布局，文字层用青色故障乱码，不满屏???
##
## 状态：
##   set_selected(true)  → 启动脉冲发光（"待放置"状态）
##   可通过 disable_hover() 关闭悬浮抬升（容器管理模式）

signal trap_clicked(trap: TrapData)

const TRAP_COLOR := Color(0.2, 0.85, 0.95, 1.0)

# 触发类型图腾颜色（与 trap_deploy_ui 的槽位色对齐）
const TOTEM_COLORS := {
	TrapData.TrapSlot.ATTACK: Color(0.9, 0.2, 0.2, 1.0),
	TrapData.TrapSlot.SKILL: Color(0.2, 0.9, 0.4, 1.0),
	TrapData.TrapSlot.HIGH_COST: Color(0.9, 0.75, 0.1, 1.0),
}

const SLOT_SHORT_NAMES := {
	TrapData.TrapSlot.ATTACK: "攻",
	TrapData.TrapSlot.SKILL: "技",
	TrapData.TrapSlot.HIGH_COST: "高",
}

var trap_data: TrapData
var is_usable: bool = true


func setup(data: TrapData, usable: bool) -> void:
	trap_data = data
	is_usable = usable
	setup_base()


func set_usable(usable: bool) -> void:
	if is_usable == usable:
		return
	is_usable = usable
	queue_redraw()


# ------------------------------------------------------------------
# BaseCardUI 抽象方法
# ------------------------------------------------------------------
func get_accent_color() -> Color:
	return TRAP_COLOR


func _is_card_usable() -> bool:
	return is_usable


func _draw_card_front(_rect: Rect2, accent: Color) -> void:
	if trap_data == null:
		return

	# 1) 中心触发类型图腾水印（最底层）
	_draw_trigger_totem()

	# 2) 顶部标记条："消耗 ⚡N ｜ 触发：攻/技/高"
	var cost_text: String
	if trap_data.is_bluff:
		cost_text = "消耗 ⚡0"
	else:
		cost_text = "消耗 ⚡%d" % trap_data.resource_cost
	var slot_short: String = SLOT_SHORT_NAMES.get(trap_data.slot, "?")
	var header: String = "%s  触发:%s" % [cost_text, slot_short]
	# 资源不足时"消耗"变红
	var header_color: Color = accent
	if not is_usable and not trap_data.is_bluff:
		header_color = Color(0.9, 0.2, 0.2, 1.0)
	var top_bar := Rect2(0, 0, CARD_WIDTH, 28)
	draw_rect(top_bar, accent * Color(1.0, 1.0, 1.0, 0.3), true)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(8, 20),
		header,
		HORIZONTAL_ALIGNMENT_LEFT,
		CARD_WIDTH - 16,
		14,
		header_color,
	)

	# 3) 卡名（诱饵牌固定显示 ???，真陷阱显示名称）
	var name_color: Color = Color.WHITE if is_usable else DISABLED_COLOR
	if trap_data.is_bluff:
		name_color = Color(0.6, 0.85, 0.95) if is_usable else DISABLED_COLOR
		draw_card_name("???", name_color)
	else:
		draw_card_name(trap_data.trap_name, name_color)

	# 4) 分隔线
	draw_separator(accent)

	# 5) 描述文字
	var desc_color: Color = Color(0.75, 0.9, 0.95) if is_usable else DISABLED_COLOR
	var lines: Array[String] = wrap_text(trap_data.description, 12)
	draw_description(lines, desc_color)

	# 6) 底部注记 — ⚠ 警示图标
	var footer: String = "⚠ 诱饵" if trap_data.is_bluff else "⚠ 陷阱"
	draw_footer(footer, accent * 0.8)


# ------------------------------------------------------------------
# 触发类型图腾（卡面中心水印，40% alpha）
# ------------------------------------------------------------------
func _draw_trigger_totem() -> void:
	var totem_color: Color = TOTEM_COLORS.get(trap_data.slot, TRAP_COLOR)
	totem_color.a = 0.15  # 更低 alpha 避免压文字
	# 图腾中心（偏下，避开顶部标记条与卡名区）
	var cx: float = CARD_WIDTH / 2.0
	var cy: float = 160.0
	match trap_data.slot:
		TrapData.TrapSlot.ATTACK:
			_draw_sword(cx, cy, 60.0, totem_color)
		TrapData.TrapSlot.SKILL:
			_draw_gear(cx, cy, 32.0, totem_color)
		TrapData.TrapSlot.HIGH_COST:
			_draw_bolt(cx, cy, 50.0, totem_color)


## 绘制剑形（向下）
func _draw_sword(cx: float, cy: float, len: float, col: Color) -> void:
	# 刀身
	draw_line(Vector2(cx, cy - len / 2.0), Vector2(cx, cy + len / 2.0), col, 3.0)
	# 护手
	draw_line(Vector2(cx - 12, cy - len / 2.0 + 12), Vector2(cx + 12, cy - len / 2.0 + 12), col, 3.0)
	# 剑尖
	var tip_col: Color = col
	tip_col.a = col.a * 0.7
	draw_line(Vector2(cx - 6, cy + len / 2.0 - 6), Vector2(cx, cy + len / 2.0), tip_col, 2.0)
	draw_line(Vector2(cx + 6, cy + len / 2.0 - 6), Vector2(cx, cy + len / 2.0), tip_col, 2.0)


## 绘制齿轮（简化八角 + 内圆）
func _draw_gear(cx: float, cy: float, radius: float, col: Color) -> void:
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(16):
		var angle: float = float(i) * TAU / 16.0
		var r: float = radius if i % 2 == 0 else radius * 0.75
		points.append(Vector2(cx + cos(angle) * r, cy + sin(angle) * r))
	# 连接点
	for i in range(points.size()):
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[(i + 1) % points.size()]
		draw_line(p1, p2, col, 2.0)
	# 内圆
	draw_arc(Vector2(cx, cy), radius * 0.45, 0.0, TAU, 32, col, 2.0)


## 绘制闪电（Z 字）
func _draw_bolt(cx: float, cy: float, len: float, col: Color) -> void:
	var half: float = len / 2.0
	var pts := PackedVector2Array([
		Vector2(cx + 8, cy - half),
		Vector2(cx - 10, cy - 4),
		Vector2(cx + 2, cy - 2),
		Vector2(cx - 8, cy + half),
	])
	for i in range(pts.size() - 1):
		draw_line(pts[i], pts[i + 1], col, 3.0)


# ------------------------------------------------------------------
# 输入
# ------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not _position_stored:
		return
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var mouse_pos: Vector2 = get_global_mouse_position()
			if get_visual_rect_global().has_point(mouse_pos):
				if is_usable:
					trap_clicked.emit(trap_data)
					get_viewport().set_input_as_handled()
