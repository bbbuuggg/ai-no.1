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
##   close()

signal closed()

enum Mode { PLAYER, BOSS }

const PLAYER_COLOR := Color(0.3, 0.85, 1.0, 1.0)
const BOSS_COLOR := Color(0.95, 0.2, 0.25, 1.0)

const PLAYER_CARD_SCALE := 0.6   # 120×168 / 200×280
const BOSS_CARD_SCALE := 1.0     # 150×220 原尺寸

const PANEL_W := 1400.0
const PANEL_H := 820.0

var _mode: int = Mode.PLAYER
var _cards: Array[CardData] = []

# 节点引用（动态构建）
var _overlay: ColorRect
var _panel: Panel
var _title_label: Label
var _count_label: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _close_btn: Button


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
	_apply_theme()
	_refresh_grid()
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
