class_name RulesOverlayUI
extends Control
## 规则介绍弹层（v0.7.x BP 模式 · 火水木）
##
## 内容：
##   1. 三角克制图（自绘）— 火 / 水 / 木 3-cycle 互克 ×1.5
##   2. 倍率与光暗 2:2 平衡说明
##   3. BP 单回合流程（5 步：抽候选 → 决先手 → 交替 Pick → 翻盅 → 结算）
##   4. 关键参数速查（候选窗 / 槽位 / 能量 / 0 费）
##   5. 名词速查
##
## 视觉：全息蓝图风（深蓝底 + 青蓝边）

signal closed()

# 元素色（与 ElementVisualHelper 同步）
const COLOR_FIRE := Color(0.91, 0.29, 0.16, 1.0)   # 红橙
const COLOR_WATER := Color(0.23, 0.56, 0.88, 1.0)  # 冷蓝
const COLOR_WOOD := Color(0.31, 0.69, 0.31, 1.0)   # 翠绿
const COLOR_LIGHT := Color(1.0, 0.92, 0.55, 1.0)   # 光（金）
const COLOR_DARK := Color(0.55, 0.40, 0.85, 1.0)   # 暗（紫）
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
	vbox.add_theme_constant_override("separation", 18)
	scroll.add_child(vbox)

	# 标题栏（含关闭按钮）
	_build_title_bar(vbox)

	# 区块 1：口号
	_build_slogan(vbox)

	# 区块 2：三角克制图（自绘 Control）
	_build_triangle_block(vbox)

	# 区块 3：倍率规则速记
	_build_multiplier_rules(vbox)

	# 区块 4：BP 流程（5 步）
	_build_bp_flow_block(vbox)

	# 区块 5：关键参数速查
	_build_params_block(vbox)

	# 区块 6：术语速查表
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
	slogan.text = "「火 · 水 · 木 三元素相互克制 — 双盲选牌、同时翻盅」"
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
	triangle.custom_minimum_size = Vector2(0, 320)
	parent.add_child(triangle)

	# 三角下方的文字说明（3 行克制关系）
	var desc_lines := [
		["🔥", "火 ▶ 木 （×1.5）", "火克木", COLOR_FIRE],
		["🌿", "木 ▶ 水 （×1.5）", "木克水", COLOR_WOOD],
		["💧", "水 ▶ 火 （×1.5）", "水克火", COLOR_WATER],
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
	rules.custom_minimum_size = Vector2(0, 180)
	rules.add_theme_font_size_override("normal_font_size", 13)
	rules.text = (
		"[color=#4ddbff]倍率规则：[/color]\n"
		+ "  • 克制方效果数值 ×1.5（向上取整）\n"
		+ "  • 被克方效果数值 ×0.5（向下取整）\n"
		+ "  • 同元素对撞 / 中立 = ×1.0\n"
		+ "  • 倍率作用于该牌的[b]所有数值[/b]——伤害、护甲、治疗、抽牌均按比例缩放\n"
		+ "\n"
		+ "[color=#ffeb8c]☀ 光[/color] / [color=#a780d8]🌑 暗[/color] 极性 · 2:2 平衡协同：\n"
		+ "  • 玩家本回合 4 张牌中正好 [b]2 光 + 2 暗[/b] → 玩家克制倍率 ×1.5 → [b]×2.0[/b]\n"
		+ "  • 不平衡或 0 平衡牌：保持基础 ×1.5\n"
		+ "\n"
		+ "[color=#ff664]⚡ 毫无阻力：[/color]\n"
		+ "  • 某槽位一方出牌而另一方无能量出牌跳过 → 结算时对位为空判定「毫无阻力」→ 出牌方[b]全部效果 ×2[/b]\n"
		+ "  • 宁可出最便宜的牌也不要空槽——空槽 = 让对手双倍痛击"
	)
	parent.add_child(rules)


func _build_bp_flow_block(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "— BP 单回合流程 —"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	# 自绘横向时间轴（5 步）
	var timeline := PhaseTimeline.new()
	timeline.custom_minimum_size = Vector2(0, 130)
	parent.add_child(timeline)

	# 5 步详细说明
	var phases := [
		{
			"name": "① 抽候选 · DRAW",
			"core": "双方各从自己的牌库抽 6 张作为本回合候选窗（明牌可见）。",
			"bullets": [
				"候选窗回合内固定，对手候选你也能看见",
				"回合末候选 6 张全部进入弃牌堆",
			],
			"tip": "⚡ 你能看见 Boss 候选 → 据此预判它最可能往哪个槽放什么。",
		},
		{
			"name": "② 决先手 · FIRST PICKER",
			"core": "随机决定本回合先手方，首回合随机，后续轮流交换。",
			"bullets": [
				"蛇形出牌：偶数槽（Slot 1,3）先手方先出，奇数槽（Slot 2,4）后手方先出",
				"等价 1-2-2-2-1 序列：先手信息优/劣势 2:2 完美平衡",
			],
			"tip": "⚡ 顶部「先手：你 / 先手：回响」横幅会播报。中线 Slot 标签会标注谁先出。",
		},
		{
			"name": "③ 交替 Pick · PICKING",
			"core": "双方按 Slot 1→4 顺序交替从候选窗选牌入槽，对方看不到你选了哪张。",
			"bullets": [
				"每槽出 1 张，共 4 槽 → 共 4 次 Pick / 方",
				"出牌消耗能量：当前能量上限 8，每回合恢复 2",
				"0 费过牌牌（灵光一现）独立通道：不进槽、立即抽 1，每回合最多 2 次",
			],
			"tip": "⚡ Slot 越靠后你看到的对方信息越多，但选择也越受限。",
		},
		{
			"name": "④ 翻盅 · REVEAL",
			"core": "双方 4 槽同时翻开，逐对碰撞，按 火/水/木 3-cycle 计算倍率。",
			"bullets": [
				"Slot 1 vs Slot 1, Slot 2 vs Slot 2 … 一对一对决",
				"克制方 ×1.5，被克方 ×0.5，同元素 ×1.0",
				"玩家本回合 4 张恰好 2 光 + 2 暗 → 克制倍率 ×1.5 → ×2.0",
			],
			"tip": "⚡ 这一刻顺序决定一切，没法反悔。",
		},
		{
			"name": "⑤ 结算 · RESOLVE",
			"core": "按倍率应用伤害、护甲、治疗、抽牌等效果，进入下一回合。",
			"bullets": [
				"每对 0.35s 错峰结算，伤害飘字与扣血同步",
				"4 对全部结算后，候选 6 张全弃 → 进入下一回合抽候选",
				"任意一方血量 ≤ 0 → 战斗结束",
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
	core_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(core_lbl)

	# Bullets
	for b in phase["bullets"]:
		var bullet_lbl := Label.new()
		bullet_lbl.text = "  • " + String(b)
		bullet_lbl.add_theme_font_size_override("font_size", 13)
		bullet_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		bullet_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(bullet_lbl)

	# Tip
	var tip_text := String(phase["tip"])
	if tip_text != "":
		var tip_lbl := Label.new()
		tip_lbl.text = tip_text
		tip_lbl.add_theme_font_size_override("font_size", 12)
		tip_lbl.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
		tip_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(tip_lbl)


func _build_params_block(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "— 关键参数 —"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	var params := [
		["候选窗", "6 张 / 回合", "回合内固定，回合末全弃"],
		["出牌槽位", "4 槽 / 方", "Slot 1 → 4 顺序结算"],
		["能量上限", "8 点", "每回合 +2，可累积不重置"],
		["0 费牌", "每回合限 2 次", "立即生效，不进槽"],
		["先手判定", "蛇形交替", "首回合随机，后续轮流；偶数槽先手先出，奇数槽后手先出"],
	]

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)

	for p in params:
		var k := Label.new()
		k.text = String(p[0])
		k.add_theme_font_size_override("font_size", 14)
		k.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
		k.custom_minimum_size = Vector2(120, 0)
		grid.add_child(k)
		var v := Label.new()
		v.text = String(p[1])
		v.add_theme_font_size_override("font_size", 14)
		v.add_theme_color_override("font_color", ACCENT)
		v.custom_minimum_size = Vector2(180, 0)
		grid.add_child(v)
		var d := Label.new()
		d.text = String(p[2])
		d.add_theme_font_size_override("font_size", 13)
		d.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(700, 0)
		grid.add_child(d)


func _build_glossary(parent: VBoxContainer) -> void:
	var header := Label.new()
	header.text = "— 名词速查 —"
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", ACCENT)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(header)

	var glossary := [
		["候选窗", "本回合可选的 6 张明牌池，回合末全弃"],
		["槽位 (Slot)", "1 ~ 4 共 4 个出牌位，按序逐对碰撞"],
		["先手", "蛇形交替：首回合随机，后续轮流；偶数槽先手先出，奇数槽后手先出"],
		["翻盅", "Pick 完成后双方所有槽同时揭示"],
		["元素", "火 / 水 / 木 — 主克制维度（火克木 / 木克水 / 水克火）"],
		["光暗极性", "光 ☀ / 暗 🌑 — 玩家 4 张 2:2 平衡 → 克制倍率 ×2.0"],
		["0 费过牌", "灵光一现 — 不进槽，立即抽 1，每回合限 2 次"],
		["毫无阻力", "对方无能量跳过 → 对位为空 → 出牌方效果 ×2"],
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
		term.custom_minimum_size = Vector2(140, 0)
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
# 内部类：三角克制图（火/水/木 3-cycle · 玩家可读优先）
# ==================================================================
class CounterTriangle extends Control:
	const C_FIRE := Color(0.91, 0.29, 0.16, 1.0)
	const C_WATER := Color(0.23, 0.56, 0.88, 1.0)
	const C_WOOD := Color(0.31, 0.69, 0.31, 1.0)
	const C_LIGHT := Color(1.0, 0.92, 0.55, 1.0)
	const C_DARK := Color(0.55, 0.40, 0.85, 1.0)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w <= 0 or h <= 0:
			return
		# 三角三顶点（上=火/左下=水/右下=木）
		var cx: float = w / 2.0
		var cy: float = h / 2.0
		var radius: float = min(w, h) * 0.38
		var top := Vector2(cx, cy - radius)
		var bl := Vector2(cx - radius * 0.866, cy + radius * 0.5)
		var br := Vector2(cx + radius * 0.866, cy + radius * 0.5)

		# 克制箭头：火→木（top→br，红），木→水（br→bl，绿），水→火（bl→top，蓝）
		_draw_arrow_curve(top, br, C_FIRE, "×1.5")
		_draw_arrow_curve(br, bl, C_WOOD, "×1.5")
		_draw_arrow_curve(bl, top, C_WATER, "×1.5")

		# 三顶点圆形节点（半径 36）
		_draw_node(top, C_FIRE, "🔥", "FIRE")
		_draw_node(bl, C_WATER, "💧", "WATER")
		_draw_node(br, C_WOOD, "🌿", "WOOD")

		# 中心注脚
		draw_string(
			ThemeDB.fallback_font,
			Vector2(cx - 80, cy + 4),
			"同元素 = ×1.0",
			HORIZONTAL_ALIGNMENT_CENTER,
			160,
			12,
			Color(0.65, 0.75, 0.85),
		)

		# 光暗 2:2 注释（右上角）
		var pol_center := Vector2(w - 110, 50)
		draw_rect(Rect2(pol_center - Vector2(50, 22), Vector2(100, 44)), Color(0.05, 0.06, 0.10, 0.85), true)
		draw_rect(Rect2(pol_center - Vector2(50, 22), Vector2(100, 44)), C_LIGHT, false, 1.0)
		draw_string(ThemeDB.fallback_font, Vector2(pol_center.x - 48, pol_center.y - 4), "☀光 2 · 暗🌑 2", HORIZONTAL_ALIGNMENT_CENTER, 96, 11, C_LIGHT)
		draw_string(ThemeDB.fallback_font, Vector2(pol_center.x - 48, pol_center.y + 14), "→ ×2.0 协同", HORIZONTAL_ALIGNMENT_CENTER, 96, 11, C_DARK)

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
		draw_string(ThemeDB.fallback_font, pos + Vector2(-14, 8), icon, HORIZONTAL_ALIGNMENT_CENTER, 28, 24, col)
		# 标签
		draw_string(ThemeDB.fallback_font, pos + Vector2(-30, r + 16), label, HORIZONTAL_ALIGNMENT_CENTER, 60, 14, col)

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
# 内部类：BP 5 步横向时间轴
# ==================================================================
class PhaseTimeline extends Control:
	const ACCENT := Color(0.3, 0.85, 1.0, 1.0)

	const PHASE_DATA := [
		["①", "DRAW", "抽候选"],
		["②", "FIRST", "决先手"],
		["③", "PICK", "交替 Pick"],
		["④", "REVEAL", "翻盅"],
		["⑤", "RESOLVE", "结算"],
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
