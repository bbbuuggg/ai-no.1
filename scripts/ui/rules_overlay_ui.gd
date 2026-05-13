class_name RulesOverlayUI
extends Control
## 规则介绍弹层
##
## 内容（由 game-designer + art-director 定义）：
##   1. 口号："读懂协议，压制进程"
##   2. 三角克制图：三顶点 ⚔攻 / ◈防 / ✦技 + 克制箭头（×1.5 标注） + 协议说明
##   3. 回合 5 阶段横向时间轴（DEPLOY / BLIND / CLASH / PROBE / ROUND_END）
##   4. 关键术语速查表（6 条）
##
## 视觉：全息蓝图风（网格底纹 + 青蓝边框 + 无切角 严谨学术感）

signal closed()

# 类型色（全局统一）
const COLOR_ATTACK := Color(0.9, 0.2, 0.2, 1.0)
const COLOR_DEFENSE := Color(0.2, 0.7, 0.9, 1.0)
const COLOR_SKILL := Color(0.2, 0.9, 0.4, 1.0)
const COLOR_PROTOCOL := Color(0.9, 0.75, 0.1, 1.0)
const ACCENT := Color(0.3, 0.85, 1.0, 1.0)
const PANEL_BG := Color(0.04, 0.08, 0.14, 0.97)

const PANEL_W := 1200.0
const PANEL_H := 900.0

var _overlay: ColorRect
var _panel: Panel
var _close_btn: Button


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()


func open_rules() -> void:
	visible = true
	_panel.scale = Vector2(0.92, 0.92)
	_panel.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.12)
	tw.tween_property(_panel, "modulate", Color.WHITE, 0.12)


func close() -> void:
	visible = false
	closed.emit()


# ------------------------------------------------------------------
# UI 构建
# ------------------------------------------------------------------
func _build_ui() -> void:
	# 遮罩
	_overlay = ColorRect.new()
	_overlay.color = Color(0.02, 0.04, 0.08, 0.78)
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_overlay_gui_input)
	add_child(_overlay)

	# 主面板
	_panel = Panel.new()
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_W / 2.0
	_panel.offset_top = -PANEL_H / 2.0
	_panel.offset_right = PANEL_W / 2.0
	_panel.offset_bottom = PANEL_H / 2.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = ACCENT
	sb.set_border_width_all(1)
	sb.set_content_margin_all(24)
	sb.shadow_color = ACCENT * Color(1, 1, 1, 0.3)
	sb.shadow_size = 6
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	# 滚动容器（单页纵向滚动）
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 24.0
	scroll.offset_top = 24.0
	scroll.offset_right = -24.0
	scroll.offset_bottom = -24.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 20)
	scroll.add_child(vbox)

	# 标题栏（含关闭按钮）
	_build_title_bar(vbox)

	# 区块 1：口号
	_build_slogan(vbox)

	# 区块 2：三角克制图（自绘 Control）
	_build_triangle_block(vbox)

	# 区块 3：倍率规则速记
	_build_multiplier_rules(vbox)

	# 区块 4：5 阶段时间轴
	_build_timeline_block(vbox)

	# 区块 5：术语速查表
	_build_glossary(vbox)


func _build_title_bar(parent: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 40)
	parent.add_child(row)

	var title := Label.new()
	title.text = "◢ 游戏规则"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)

	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.custom_minimum_size = Vector2(40, 40)
	_close_btn.add_theme_font_size_override("font_size", 24)
	_close_btn.add_theme_color_override("font_color", ACCENT)
	_close_btn.pressed.connect(close)
	row.add_child(_close_btn)


func _build_slogan(parent: VBoxContainer) -> void:
	var slogan := Label.new()
	slogan.text = "「进攻、防守、技能三种卡牌互相克制」"
	slogan.add_theme_font_size_override("font_size", 22)
	slogan.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	slogan.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(slogan)


func _build_triangle_block(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "— 克制关系 —"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	# 自绘三角
	var triangle := CounterTriangle.new()
	triangle.custom_minimum_size = Vector2(0, 360)
	parent.add_child(triangle)

	# 三角下方的文字说明（3 行克制关系）
	var desc_lines := [
		["⚔", "ATTACK  ▶ SKILL （×1.5）", "攻击牌克制技能牌，数值*1.5", COLOR_ATTACK],
		["✦", "SKILL ▶ DEFENSE （×1.5）", "技能牌克制攻击牌，数值*1.5", COLOR_SKILL],
		["◈", "DEFENSE ▶ ATTACK （×1.5）", "防御牌克制攻击牌，数值*1.5", COLOR_DEFENSE],
	]
	for d in desc_lines:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 8)
		parent.add_child(hb)
		var icon := Label.new()
		icon.text = d[0]
		icon.add_theme_font_size_override("font_size", 20)
		icon.add_theme_color_override("font_color", d[3])
		icon.custom_minimum_size = Vector2(30, 0)
		hb.add_child(icon)
		var title_lbl := Label.new()
		title_lbl.text = d[1]
		title_lbl.add_theme_font_size_override("font_size", 15)
		title_lbl.add_theme_color_override("font_color", d[3])
		title_lbl.custom_minimum_size = Vector2(240, 0)
		hb.add_child(title_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = d[2]
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		hb.add_child(desc_lbl)


func _build_multiplier_rules(parent: VBoxContainer) -> void:
	var rules := RichTextLabel.new()
	rules.bbcode_enabled = true
	rules.fit_content = true
	rules.custom_minimum_size = Vector2(0, 110)
	rules.add_theme_font_size_override("normal_font_size", 13)
	rules.text = (
		"[color=#4ddbff]倍率规则：[/color]\n"
		+ "  • 克制方效果数值 ×1.5（向上取整）\n"
		+ "  • 被克方效果数值 ×0.5\n"
		+ "  • 中立 / 无对手 ×1.0\n"
		+ "  • 倍率作用于该牌的[b]所有数值[/b]——伤害、护甲、治疗、抽牌、能量修正均按比例缩放\n"
		+ "\n"
		+ "[color=#e6bf1a]协议（PROTOCOL）[/color]：在碰撞判定中以 [color=#33e666]SKILL[/color] 身份参与克制。同类型对撞 = 中立。"
	)
	parent.add_child(rules)


func _build_timeline_block(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "— 单回合流程 —"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	# 自绘横向时间轴
	var timeline := PhaseTimeline.new()
	timeline.custom_minimum_size = Vector2(0, 130)
	parent.add_child(timeline)

	# 5 阶段详细说明（每段 bullet + tip）
	var phases := [
		{
			"name": "① DEPLOY · 部署陷阱",
			"core": "埋下陷阱，限制 Boss 的行动路径。",
			"bullets": [
				"消耗【约束资源】向三个触发槽位部署陷阱牌（攻 / 技 / 高费）",
				"可部署【诱饵】——无效果，但会误导 Boss 的预判",
				"可额外选择干扰探针，扰乱 猜测",
			],
			"tip": "⚡ 诱饵牌没有效果但价值很大。",
		},
		{
			"name": "② BLIND · 暗出选牌",
			"core": "选定出手顺序，在黑箱中与 Boss 同时落子。",
			"bullets": [
				"从手牌选 1-3 张，排列执行顺序放入暗出区",
				"双方出牌同时封存，揭示之前互不可见",
				"零能量牌可绑定为附带效果，搭载在主牌之上",
			],
			"tip": "⚡ 顺序本身就是一层博弈。",
		},
		{
			"name": "③ CLASH · 对决结算",
			"core": "同时翻牌，逐对碰撞，计算结果。",
			"bullets": [
				"双方牌依序逐对翻开，按三角克制计算倍率",
				"数值效果实时结算：伤害、护甲、治疗、抽牌……",
				"Boss 打出的牌若匹配陷阱槽位，陷阱立即触发",
			],
			"tip": "⚡ Boss 不会改写已经落下的牌——但你可以用陷阱重写它的后果。",
		},
		{
			"name": "④ PROBE · 认知探针",
			"core": " Boss每回合会猜测玩家的出牌类型。",
			"bullets": [
				"预判玩家下回合出牌的类型倾向（攻 / 防 / 技）",
				"命中则累积【洞察值】",
				"洞察值达阈值，Boss获得单次技能：窥视手牌 / 干扰敌牌 / 夺取能量",
			],
			"tip": "⚡ Boss的随机猜测给牌局创造‘意外’，降低可预测性。",
		},
		{
			"name": "⑤ ROUND_END · 回合结束",
			"core": "清算、维护、重启下一轮协议。",
			"bullets": [
				"护甲按规则结算 / 清除",
				"常驻【约束令】持续生效",
				"状态刷新，进入下一回合",
			],
			"tip": "",
		},
	]

	for p in phases:
		_build_phase_card(parent, p)


func _build_phase_card(parent: VBoxContainer, phase: Dictionary) -> void:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.1, 0.14, 0.8)
	sb.border_color = ACCENT * 0.5
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", sb)
	parent.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)

	# 阶段名
	var name_lbl := Label.new()
	name_lbl.text = String(phase["name"])
	name_lbl.add_theme_font_size_override("font_size", 17)
	name_lbl.add_theme_color_override("font_color", ACCENT)
	vb.add_child(name_lbl)

	# 核心描述
	var core_lbl := Label.new()
	core_lbl.text = String(phase["core"])
	core_lbl.add_theme_font_size_override("font_size", 14)
	core_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	vb.add_child(core_lbl)

	# Bullets
	for b in phase["bullets"]:
		var bullet_lbl := Label.new()
		bullet_lbl.text = "  • " + String(b)
		bullet_lbl.add_theme_font_size_override("font_size", 13)
		bullet_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		vb.add_child(bullet_lbl)

	# Tip
	var tip_lbl := Label.new()
	tip_lbl.text = String(phase["tip"])
	tip_lbl.add_theme_font_size_override("font_size", 12)
	tip_lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	vb.add_child(tip_lbl)


func _build_glossary(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "— 名词定义 —"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	var glossary := [
		["暗出", "封存式出牌——揭示前双方互不可见的博弈阶段"],
		["陷阱", "预先部署到槽位的牌，Boss 打出对应类型时被动触发"],
		["约束令", "玩家主动向 Boss 施加的规则限制（限牌 / 限资源 / 幻觉）"],
		["洞察值", "认知探针命中后累积的资源，用于解锁高级情报权限"],
		["诱饵", "无效果的空白陷阱，用于污染 Boss 的行为判断"],
	]

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)

	for g in glossary:
		var term := Label.new()
		term.text = String(g[0])
		term.add_theme_font_size_override("font_size", 14)
		term.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
		term.custom_minimum_size = Vector2(120, 0)
		grid.add_child(term)
		var def := Label.new()
		def.text = String(g[1])
		def.add_theme_font_size_override("font_size", 13)
		def.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		def.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		def.custom_minimum_size = Vector2(900, 0)
		grid.add_child(def)


# ------------------------------------------------------------------
# 事件
# ------------------------------------------------------------------
func _on_overlay_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			close()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ==================================================================
# 内部类：三角克制图
# ==================================================================
class CounterTriangle extends Control:
	const C_ATK := Color(0.9, 0.2, 0.2, 1.0)
	const C_DEF := Color(0.2, 0.7, 0.9, 1.0)
	const C_SKL := Color(0.2, 0.9, 0.4, 1.0)
	const C_PRO := Color(0.9, 0.75, 0.1, 1.0)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 0 or h <= 0:
			return
		# 三角三顶点（上/左下/右下）
		var cx: float = w / 2.0
		var cy: float = h / 2.0
		var radius: float = min(w, h) * 0.38
		var top := Vector2(cx, cy - radius)
		var bl := Vector2(cx - radius * 0.866, cy + radius * 0.5)
		var br := Vector2(cx + radius * 0.866, cy + radius * 0.5)

		# 克制箭头（沿三角外弧）：ATK→SKL (top→br), SKL→DEF (br→bl), DEF→ATK (bl→top)
		_draw_arrow_curve(top, br, C_ATK, "×1.5")
		_draw_arrow_curve(br, bl, C_SKL, "×1.5")
		_draw_arrow_curve(bl, top, C_DEF, "×1.5")

		# 三顶点圆形节点（半径 36）
		_draw_node(top, C_ATK, "⚔", "ATK")
		_draw_node(bl, C_DEF, "◈", "DEF")
		_draw_node(br, C_SKL, "✦", "SKL")

		# 中心注脚
		draw_string(
			ThemeDB.fallback_font,
			Vector2(cx - 80, cy + 4),
			"同类 / 对协议 = ×1.0",
			HORIZONTAL_ALIGNMENT_CENTER,
			160,
			12,
			Color(0.65, 0.75, 0.85),
		)

		# 协议牌注释（右上角）
		var pro_center := Vector2(w - 100, 50)
		draw_rect(Rect2(pro_center - Vector2(40, 18), Vector2(80, 36)), C_PRO * Color(1, 1, 1, 0.2), true)
		draw_rect(Rect2(pro_center - Vector2(40, 18), Vector2(80, 36)), C_PRO, false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(pro_center.x - 38, pro_center.y - 2), "⚡ PROTOCOL", HORIZONTAL_ALIGNMENT_CENTER, 76, 11, C_PRO)
		draw_string(ThemeDB.fallback_font, Vector2(pro_center.x - 38, pro_center.y + 12), "归为 SKILL", HORIZONTAL_ALIGNMENT_CENTER, 76, 10, Color(0.8, 0.7, 0.4))

	func _draw_node(pos: Vector2, col: Color, icon: String, label: String) -> void:
		var r: float = 36.0
		# 外发光（多层圆环近似）
		for i in range(3):
			var glow := col
			glow.a = 0.25 * (1.0 - float(i) / 3.0)
			draw_arc(pos, r + float(i) * 3.0, 0.0, TAU, 48, glow, 2.0)
		# 填充
		draw_circle(pos, r, col * Color(1, 1, 1, 0.22))
		# 描边
		draw_arc(pos, r, 0.0, TAU, 48, col, 2.5)
		# 图标
		draw_string(ThemeDB.fallback_font, pos + Vector2(-14, 6), icon, HORIZONTAL_ALIGNMENT_CENTER, 28, 24, col)
		# 标签
		draw_string(ThemeDB.fallback_font, pos + Vector2(-24, r + 16), label, HORIZONTAL_ALIGNMENT_CENTER, 48, 14, col)

	func _draw_arrow_curve(from_p: Vector2, to_p: Vector2, col: Color, label: String) -> void:
		# 直线近似（不做贝塞尔，保持简洁），两端收缩避免压节点
		var dir: Vector2 = (to_p - from_p).normalized()
		var start: Vector2 = from_p + dir * 44.0
		var end: Vector2 = to_p - dir * 44.0
		draw_line(start, end, col, 3.0)
		# 外发光：再画一条更宽更淡的
		var glow := col
		glow.a = 0.3
		draw_line(start, end, glow, 6.0)
		# 箭头头
		var arrow_len: float = 12.0
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var p1: Vector2 = end - dir * arrow_len + perp * 6.0
		var p2: Vector2 = end - dir * arrow_len - perp * 6.0
		draw_line(end, p1, col, 3.0)
		draw_line(end, p2, col, 3.0)
		# 中段 ×1.5 标签
		var mid: Vector2 = (start + end) / 2.0
		var label_bg := Rect2(mid - Vector2(20, 10), Vector2(40, 18))
		draw_rect(label_bg, Color(0.05, 0.1, 0.15, 0.9), true)
		draw_rect(label_bg, col, false, 1.0)
		draw_string(ThemeDB.fallback_font, mid + Vector2(-18, 4), label, HORIZONTAL_ALIGNMENT_CENTER, 36, 12, col)


# ==================================================================
# 内部类：5 阶段横向时间轴
# ==================================================================
class PhaseTimeline extends Control:
	const ACCENT := Color(0.3, 0.85, 1.0, 1.0)

	const PHASE_DATA := [
		["①", "DEPLOY", "部署"],
		["②", "BLIND", "暗出"],
		["③", "CLASH", "对决"],
		["④", "PROBE", "探针"],
		["⑤", "ROUND_END", "回合末"],
	]

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 0:
			return
		var n: int = PHASE_DATA.size()
		var margin: float = 60.0
		var step: float = (w - margin * 2.0) / float(n - 1)
		var cy: float = h * 0.45

		# 底部连接线
		draw_line(Vector2(margin, cy), Vector2(w - margin, cy), ACCENT * 0.4, 2.0)

		# 每个阶段节点
		for i in range(n):
			var cx: float = margin + step * float(i)
			var pos := Vector2(cx, cy)
			# 圆形节点
			draw_circle(pos, 26.0, Color(0.05, 0.1, 0.15, 0.95))
			draw_arc(pos, 26.0, 0.0, TAU, 48, ACCENT, 2.0)
			# 中心编号
			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-10, 6),
				String(PHASE_DATA[i][0]),
				HORIZONTAL_ALIGNMENT_CENTER,
				20,
				20,
				ACCENT,
			)
			# 英文代号
			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-50, 44),
				String(PHASE_DATA[i][1]),
				HORIZONTAL_ALIGNMENT_CENTER,
				100,
				12,
				ACCENT,
			)
			# 中文标签
			draw_string(
				ThemeDB.fallback_font,
				pos + Vector2(-50, 60),
				String(PHASE_DATA[i][2]),
				HORIZONTAL_ALIGNMENT_CENTER,
				100,
				11,
				Color(0.8, 0.9, 1.0),
			)
			# 右向箭头（非最后一个）
			if i < n - 1:
				var ax: float = cx + step * 0.5
				draw_line(Vector2(ax - 4, cy - 4), Vector2(ax + 4, cy), ACCENT * 0.7, 1.5)
				draw_line(Vector2(ax - 4, cy + 4), Vector2(ax + 4, cy), ACCENT * 0.7, 1.5)
