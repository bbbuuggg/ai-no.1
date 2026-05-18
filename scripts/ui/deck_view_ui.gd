class_name DeckViewUI
extends Control
## 通用牌库弹层 —— 支持 我方牌库 / Boss 牌库 两种模式
##
## 交互：
##   半模态（背景 75% 黑遮罩）/ ESC 或点击遮罩或右上 × 关闭
##   网格布局 + 垂直滚动 / 无 Tab（v1 简化版）
##
## 视觉：
##   我方：青蓝主题 `(0.3, 0.85, 1.0)`，使用 CardUI（200×280 缩放到 120×168）
##   Boss：血红主题 `(0.95, 0.2, 0.25)`，使用 BossCardUI（150×220 原尺寸）
##
## API:
##   show_player_deck(cards: Array[CardData])
##   show_boss_deck(cards: Array[CardData])
##   show_boss_deck_with_zones(draw: Array[CardData], hand_count: int, discard: Array[CardData])
##     - DRAW 区：在标题下方显示类型分布横条（默认横条+图标，鼠标悬停 tooltip 显示精确数字）
##     - 网格：仍展示 draw + hand + discard 全集
##   close()

signal closed()

enum Mode { PLAYER, BOSS }

const PLAYER_COLOR := Color(0.3, 0.85, 1.0, 1.0)
const BOSS_COLOR := Color(0.95, 0.2, 0.25, 1.0)

const PLAYER_CARD_SCALE := 0.6   # 120×168 / 200×280
const BOSS_CARD_SCALE := 1.0     # 150×220 原尺寸

const PANEL_W := 1400.0
const PANEL_H := 820.0

# DRAW 区分类型颜色（与战斗区共用语义）
const TYPE_COLORS := {
	CardData.CardType.ATTACK: Color(0.95, 0.30, 0.30, 1.0),    # 红
	CardData.CardType.DEFENSE: Color(0.45, 0.75, 0.95, 1.0),   # 蓝
	CardData.CardType.SKILL: Color(0.40, 0.90, 0.55, 1.0),     # 绿
	CardData.CardType.PROTOCOL: Color(0.95, 0.78, 0.25, 1.0),  # 金
}

const TYPE_SHORT_NAMES := {
	CardData.CardType.ATTACK: "攻",
	CardData.CardType.DEFENSE: "防",
	CardData.CardType.SKILL: "技",
	CardData.CardType.PROTOCOL: "协",
}

var _mode: int = Mode.PLAYER
var _cards: Array[CardData] = []
# DRAW 区数据（仅 Boss 模式 show_boss_deck_with_zones 时填充）
var _draw_cards: Array[CardData] = []
var _zone_summary_visible: bool = false

# 节点引用（动态构建）
var _overlay: ColorRect
var _panel: Panel
var _title_label: Label
var _count_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _close_btn: Button
var _zone_summary_row: HBoxContainer  # DRAW 区类型分布横条容器


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 全屏填充
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	_build_ui()


# ------------------------------------------------------------------
# 公共 API
# ------------------------------------------------------------------
func show_player_deck(cards: Array[CardData]) -> void:
	_mode = Mode.PLAYER
	_cards = cards.duplicate()
	_apply_theme()
	_refresh_grid()
	_open()


func show_boss_deck(cards: Array[CardData]) -> void:
	_mode = Mode.BOSS
	_cards = cards.duplicate()
	_draw_cards = []
	_zone_summary_visible = false
	_apply_theme()
	_refresh_grid()
	_refresh_zone_summary(-1)
	_open()


## B 浮层入口 — 显式区分 Boss 牌库三个分区
## DRAW 区类型分布会显示在标题下方横条
## hand_count 仅显示张数（不展开内容，符合 GDD 04:78 信息对称原则）
func show_boss_deck_with_zones(draw: Array[CardData], hand_count: int, discard: Array[CardData]) -> void:
	_mode = Mode.BOSS
	# 网格仍展示全集（draw + 占位 hand_count + discard），保留旧的"按类型→能量"排序体验
	# 注意：hand 内容不展开（信息对称），只在网格末尾用占位卡背显示
	var combined: Array[CardData] = []
	combined.append_array(draw)
	combined.append_array(discard)
	_cards = combined
	_draw_cards = draw.duplicate()
	_zone_summary_visible = true
	_apply_theme()
	_refresh_grid()
	_refresh_zone_summary(hand_count)
	_open()


func close() -> void:
	visible = false
	closed.emit()


# ------------------------------------------------------------------
# UI 构建
# ------------------------------------------------------------------
func _build_ui() -> void:
	# 1) 遮罩
	_overlay = ColorRect.new()
	_overlay.color = Color(0.02, 0.04, 0.08, 0.75)
	_overlay.anchor_right = 1.0
	_overlay.anchor_bottom = 1.0
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.gui_input.connect(_on_overlay_gui_input)
	add_child(_overlay)

	# 2) 主面板
	_panel = Panel.new()
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.anchor_left = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_bottom = 0.5
	_panel.offset_left = -PANEL_W / 2.0
	_panel.offset_top = -PANEL_H / 2.0
	_panel.offset_right = PANEL_W / 2.0
	_panel.offset_bottom = PANEL_H / 2.0
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 20.0
	vbox.offset_top = 16.0
	vbox.offset_right = -20.0
	vbox.offset_bottom = -20.0
	vbox.add_theme_constant_override("separation", 12)
	_panel.add_child(vbox)

	# 3) 标题栏
	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size = Vector2(0, 44)
	vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 24)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	_count_label = Label.new()
	_count_label.add_theme_font_size_override("font_size", 18)
	title_row.add_child(_count_label)

	# 关闭按钮
	_close_btn = Button.new()
	_close_btn.text = "×"
	_close_btn.custom_minimum_size = Vector2(40, 40)
	_close_btn.add_theme_font_size_override("font_size", 24)
	_close_btn.pressed.connect(close)
	title_row.add_child(_close_btn)

	# 3.5) DRAW 区类型分布横条（仅 Boss 模式 + show_boss_deck_with_zones 时显示）
	_zone_summary_row = HBoxContainer.new()
	_zone_summary_row.custom_minimum_size = Vector2(0, 56)
	_zone_summary_row.add_theme_constant_override("separation", 16)
	_zone_summary_row.visible = false
	vbox.add_child(_zone_summary_row)

	# 分隔线
	var sep := HSeparator.new()
	vbox.add_child(sep)

	# 4) 滚动容器 + 网格
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_grid = GridContainer.new()
	_grid.columns = 8  # 动态按模式调整
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 18)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_grid)


# ------------------------------------------------------------------
# 主题切换（我方 vs Boss）
# ------------------------------------------------------------------
func _apply_theme() -> void:
	var accent: Color = PLAYER_COLOR if _mode == Mode.PLAYER else BOSS_COLOR
	# 面板底色 + 边框
	var sb := StyleBoxFlat.new()
	if _mode == Mode.PLAYER:
		sb.bg_color = Color(0.05, 0.08, 0.12, 0.95)
	else:
		sb.bg_color = Color(0.12, 0.05, 0.06, 0.95)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	# 外发光用阴影近似
	sb.shadow_color = accent * Color(1, 1, 1, 0.35)
	sb.shadow_size = 8
	_panel.add_theme_stylebox_override("panel", sb)

	# 标题
	var prefix: String = "◢ 我的牌库 / PLAYER_DECK.dat" if _mode == Mode.PLAYER else "⚠ HOSTILE_DECK / 敌方程序库"
	_title_label.text = prefix
	_title_label.add_theme_color_override("font_color", accent)

	# 计数
	_count_label.add_theme_color_override("font_color", Color.WHITE)

	# 关闭按钮样式
	_close_btn.add_theme_color_override("font_color", accent)
	_close_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.3, 0.3))

	# 网格列数
	_grid.columns = 8 if _mode == Mode.PLAYER else 7


# ------------------------------------------------------------------
# DRAW 区类型分布横条（B 浮层核心信息密度组件）
# ------------------------------------------------------------------
## 刷新标题下方的 DRAW 区分类横条
## hand_count >= 0 时显示 HAND 区张数标记；< 0 时整行隐藏（旧 API 兼容）
func _refresh_zone_summary(hand_count: int) -> void:
	if not _zone_summary_visible or _mode != Mode.BOSS:
		_zone_summary_row.visible = false
		return
	_zone_summary_row.visible = true
	# 清空旧内容
	for child in _zone_summary_row.get_children():
		child.queue_free()

	# === DRAW 段 ===
	var draw_seg := _build_zone_segment("DRAW", _draw_cards.size(), _draw_cards, true)
	_zone_summary_row.add_child(draw_seg)

	# 分隔
	var divider1 := VSeparator.new()
	divider1.custom_minimum_size = Vector2(2, 40)
	_zone_summary_row.add_child(divider1)

	# === HAND 段（仅张数）===
	var hand_label := _build_hand_segment(hand_count)
	_zone_summary_row.add_child(hand_label)

	# 分隔
	var divider2 := VSeparator.new()
	divider2.custom_minimum_size = Vector2(2, 40)
	_zone_summary_row.add_child(divider2)

	# === DEPLOYED 段（弃牌堆张数 + 类型分布缩略，但不展示精确数字）===
	var deployed_cards: Array[CardData] = _extract_deployed_cards()
	var deployed_seg := _build_zone_segment("DEPLOYED", deployed_cards.size(), deployed_cards, false)
	_zone_summary_row.add_child(deployed_seg)


func _extract_deployed_cards() -> Array[CardData]:
	# 在 _cards (= draw + discard) 里去掉 _draw_cards，剩下的就是 discard
	var draw_set := {}
	for c in _draw_cards:
		draw_set[c] = true
	var deployed: Array[CardData] = []
	for c in _cards:
		if not draw_set.has(c):
			deployed.append(c)
	return deployed


## 构建一个分区单元（标签 + 数字 + 横条）
## with_tooltip: 是否在横条上挂 tooltip 显示精确数字（DRAW 区为 true，DEPLOYED 区为 false 减少认知负荷）
func _build_zone_segment(label_text: String, count: int, cards: Array[CardData], with_tooltip: bool) -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)

	# 顶行：标签 + 计数
	var top := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = "%s  %d" % [label_text, count]
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", BOSS_COLOR)
	top.add_child(lbl)
	vbox.add_child(top)

	# 横条
	var bar := _build_type_distribution_bar(cards, with_tooltip)
	vbox.add_child(bar)
	return vbox


## 类型分布横条（默认模糊横条，悬停显示精确数字 tooltip）
func _build_type_distribution_bar(cards: Array[CardData], with_tooltip: bool) -> Control:
	const BAR_HEIGHT := 22.0
	var bar_root := Control.new()
	bar_root.custom_minimum_size = Vector2(260, BAR_HEIGHT)
	bar_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 统计类型分布
	var type_counts := _count_by_type(cards)
	var total: int = cards.size()

	# 背景条
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.10, 0.14, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.add_child(bg)

	if total == 0:
		# 空牌库时显示灰色提示
		var empty := Label.new()
		empty.text = "—— 空 ——"
		empty.anchor_right = 1.0
		empty.anchor_bottom = 1.0
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
		empty.add_theme_font_size_override("font_size", 12)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_root.add_child(empty)
		return bar_root

	# 横条分段（按 ATTACK→DEFENSE→SKILL→PROTOCOL 顺序，颜色见 TYPE_COLORS）
	var ordered_types := [
		CardData.CardType.ATTACK,
		CardData.CardType.DEFENSE,
		CardData.CardType.SKILL,
		CardData.CardType.PROTOCOL,
	]
	# 用 HBoxContainer 自动布局，比例靠 stretch_ratio
	var hbox := HBoxContainer.new()
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	hbox.add_theme_constant_override("separation", 0)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_root.add_child(hbox)

	for t in ordered_types:
		var n: int = type_counts.get(t, 0)
		if n <= 0:
			continue
		var seg := ColorRect.new()
		seg.color = TYPE_COLORS.get(t, Color.GRAY)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.size_flags_stretch_ratio = float(n)
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 段内中心放图标短码（小字）
		var seg_label := Label.new()
		seg_label.text = TYPE_SHORT_NAMES.get(t, "?")
		seg_label.anchor_right = 1.0
		seg_label.anchor_bottom = 1.0
		seg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		seg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		seg_label.add_theme_color_override("font_color", Color(0.05, 0.05, 0.08, 1.0))
		seg_label.add_theme_font_size_override("font_size", 12)
		seg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		seg.add_child(seg_label)
		hbox.add_child(seg)

	# Tooltip：默认横条 + 悬停显示精确数字（vibe-lead Q2=C 折中方案）
	if with_tooltip:
		bar_root.mouse_filter = Control.MOUSE_FILTER_PASS
		bar_root.tooltip_text = _build_distribution_tooltip(type_counts, total)
	else:
		bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE

	return bar_root


func _count_by_type(cards: Array[CardData]) -> Dictionary:
	var d := {}
	for c in cards:
		d[c.type] = int(d.get(c.type, 0)) + 1
	return d


func _build_distribution_tooltip(type_counts: Dictionary, total: int) -> String:
	var lines: Array[String] = []
	lines.append("剩 %d 张" % total)
	var ordered_types := [
		CardData.CardType.ATTACK,
		CardData.CardType.DEFENSE,
		CardData.CardType.SKILL,
		CardData.CardType.PROTOCOL,
	]
	for t in ordered_types:
		var n: int = type_counts.get(t, 0)
		if n > 0:
			lines.append("%s: %d" % [TYPE_SHORT_NAMES.get(t, "?"), n])
	return "\n".join(lines)


## HAND 段（仅张数，不展开内容；GDD 04:78 信息对称原则）
func _build_hand_segment(hand_count: int) -> Control:
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(180, 0)
	vbox.add_theme_constant_override("separation", 4)
	# 顶行
	var lbl := Label.new()
	lbl.text = "HAND  %d" % maxi(hand_count, 0)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", BOSS_COLOR)
	vbox.add_child(lbl)
	# 占位行：用卡背图标 🂠 重复 hand_count 次
	var icons := Label.new()
	var icon_str := ""
	for i in range(maxi(hand_count, 0)):
		icon_str += "🂠 "
	icons.text = icon_str if hand_count > 0 else "—"
	icons.add_theme_font_size_override("font_size", 16)
	icons.add_theme_color_override("font_color", Color(0.85, 0.97, 1.0, 0.8))
	icons.tooltip_text = "Boss 手牌：%d 张（内容暗）" % maxi(hand_count, 0)
	vbox.add_child(icons)
	return vbox


# ------------------------------------------------------------------
# 刷新网格
# ------------------------------------------------------------------
func _refresh_grid() -> void:
	for child in _grid.get_children():
		child.queue_free()

	_count_label.text = "%d / %d" % [_cards.size(), _cards.size()]

	if _cards.is_empty():
		var empty := Label.new()
		empty.text = "// 数据流已空 ——  DECK_EMPTY"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", Color(0.5, 0.6, 0.7))
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_grid.add_child(empty)
		return

	# 排序：按类型 → 能量升序
	var sorted: Array[CardData] = _cards.duplicate()
	sorted.sort_custom(func(a: CardData, b: CardData) -> bool:
		if a.type != b.type:
			return a.type < b.type
		return a.energy_cost < b.energy_cost
	)

	for card in sorted:
		var card_view := _make_card_view(card)
		_grid.add_child(card_view)


func _make_card_view(card: CardData) -> Control:
	# 包装在一个 Control 里以支持缩放+容器对齐
	var wrapper := Control.new()

	if _mode == Mode.PLAYER:
		var CardUIScript := preload("res://scripts/ui/card_ui.gd")
		var view = CardUIScript.new()
		view.setup(card, Vector2.ZERO)
		view.disable_hover()
		view.scale = Vector2(PLAYER_CARD_SCALE, PLAYER_CARD_SCALE)
		# 包装尺寸 = 原尺寸 × 缩放
		wrapper.custom_minimum_size = Vector2(200 * PLAYER_CARD_SCALE, 280 * PLAYER_CARD_SCALE)
		wrapper.add_child(view)
	else:
		var view := BossCardUI.new()
		# Boss 卡用该层代号 PROC_01（占位）
		view.setup(card, "PROC_01", true)
		view.disable_hover()
		view.scale = Vector2(BOSS_CARD_SCALE, BOSS_CARD_SCALE)
		wrapper.custom_minimum_size = Vector2(150 * BOSS_CARD_SCALE, 220 * BOSS_CARD_SCALE)
		wrapper.add_child(view)

	return wrapper


# ------------------------------------------------------------------
# 打开 / 关闭 / 输入
# ------------------------------------------------------------------
func _open() -> void:
	visible = true
	# 入场动画：缩放 0.92 → 1.0 + 淡入 120ms
	_panel.scale = Vector2(0.92, 0.92)
	_panel.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_panel, "scale", Vector2.ONE, 0.12)
	tw.tween_property(_panel, "modulate", Color.WHITE, 0.12)


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
