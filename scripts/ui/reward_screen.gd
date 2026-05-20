extends Control
## RewardScreen — GDD-08 升级阶段 UI（v0.8.2 简化版）
## 布局：上方 Boss 完整牌库 ｜ 中间 [左规则 + 4 张候选新牌 + 右规则] ｜ 下方玩家完整牌库
## 候选 = 4 张新卡（从全卡池随机），用来替换牌库中的任意一张
## v0.9.4：候选区末位增加 ⭐ 自行设计按钮，打开 CustomCardDesigner 自调升级牌

signal reward_completed()

const CARD_UI_SCRIPT := preload("res://scripts/ui/card_ui.gd")
const CUSTOM_DESIGNER_SCRIPT := preload("res://scripts/ui/custom_card_designer.gd")
const DECK_CARD_SCALE: float = 0.7   # 牌库展示缩放（200x280 → 140x196）
const CANDIDATE_CARD_SCALE: float = 0.85  # 候选牌缩放

# 步骤枚举
enum Step { CANDIDATES, PICK_FOR_SELF, PICK_FOR_BOSS, SUMMARY }

var current_step: Step = Step.CANDIDATES
var candidates: Array[CardData] = []         # 4 张新卡候选
var self_pick: CardData = null
var boss_pick: CardData = null
var remaining_candidates: Array[CardData] = []

# v0.9.4：玩家本回合是否已使用自调升级（用过 → MIRROR 不再有自调选项；未用 → MIRROR 也可自调）
var _player_used_custom: bool = false

# 引用
var _run_state: RunState = null
var _player_deck: Array[CardData] = []
var _boss_deck: Array[CardData] = []

# 当前替换上下文（"" = 未在替换模式）
var _replace_side: String = ""

# UI 节点
var _dim_bg: ColorRect
var _boss_deck_title: Label
var _boss_deck_grid: HBoxContainer
var _player_deck_title: Label
var _player_deck_grid: HBoxContainer
var _candidates_container: HBoxContainer
var _step_indicator: Label
var _banner: Label
var _summary_panel: Control

# v0.9.4：自调升级面板
var _custom_designer: Control = null


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	visible = false
	z_index = 90
	_build_ui()
	_build_custom_designer()


func _build_custom_designer() -> void:
	# v0.9.4 v3 嵌入式：把 designer 嵌入到候选区位置（与候选卡互斥显示）
	# 而非独立全屏遮罩
	_custom_designer = Control.new()
	_custom_designer.set_script(CUSTOM_DESIGNER_SCRIPT)
	# 让 designer 填满候选容器的同级位置 — 把它 add 到 _candidates_container 的父级
	# 并紧跟 candidates_container 排列；切换 visible 即可"原地替换"显示
	if _candidates_container != null and _candidates_container.get_parent() != null:
		var center_vbox: Node = _candidates_container.get_parent()
		center_vbox.add_child(_custom_designer)
		# 让 designer 紧跟在 candidates_container 之后（排序相同位置）
		var idx: int = _candidates_container.get_index() + 1
		center_vbox.move_child(_custom_designer, idx)
		_custom_designer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_custom_designer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		# v3 横向 3 列布局后，高度紧凑（只需容纳 3 行 dial + 顶部状态栏 + 预览）
		_custom_designer.custom_minimum_size = Vector2(0, 320)
	else:
		# 兜底：直接挂 self
		add_child(_custom_designer)
	_custom_designer.card_built.connect(_on_custom_card_built)
	_custom_designer.cancelled.connect(_on_custom_designer_cancelled)


func _build_ui() -> void:
	# 背景遮罩
	_dim_bg = ColorRect.new()
	_dim_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim_bg.color = Color(0, 0, 0, 0.94)
	_dim_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim_bg)

	# ===== 全屏三段式布局 =====
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_vbox.offset_left = 30
	root_vbox.offset_right = -30
	root_vbox.offset_top = 15
	root_vbox.offset_bottom = -15
	root_vbox.add_theme_constant_override("separation", 6)
	add_child(root_vbox)

	# ----- 上方：Boss 完整牌库 -----
	_boss_deck_title = Label.new()
	_boss_deck_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_deck_title.add_theme_font_size_override("font_size", 18)
	_boss_deck_title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_boss_deck_title.text = "MIRROR 牌库"
	root_vbox.add_child(_boss_deck_title)

	var boss_scroll := ScrollContainer.new()
	# 牌高度 280*0.7=196，加上滚动条预留 + 上下 padding
	boss_scroll.custom_minimum_size = Vector2(0, 220)
	boss_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	boss_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(boss_scroll)

	# CenterContainer 让牌库居中（牌不多时）
	var boss_center := CenterContainer.new()
	boss_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	boss_scroll.add_child(boss_center)

	_boss_deck_grid = HBoxContainer.new()
	_boss_deck_grid.add_theme_constant_override("separation", 8)
	_boss_deck_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	boss_center.add_child(_boss_deck_grid)

	# ----- 中间：[左规则 + 候选 + 右规则] -----
	var center_h := HBoxContainer.new()
	center_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_h.add_theme_constant_override("separation", 20)
	center_h.alignment = BoxContainer.ALIGNMENT_CENTER
	root_vbox.add_child(center_h)

	# 左侧规则面板（固定大小，不拉伸）
	var left_rules := _build_rule_panel(true)
	left_rules.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_h.add_child(left_rules)

	# 中间候选区
	var center_vbox := VBoxContainer.new()
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_vbox.add_theme_constant_override("separation", 8)
	center_h.add_child(center_vbox)

	_step_indicator = Label.new()
	_step_indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_indicator.add_theme_font_size_override("font_size", 26)
	_step_indicator.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	center_vbox.add_child(_step_indicator)

	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
	center_vbox.add_child(_banner)

	_candidates_container = HBoxContainer.new()
	_candidates_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_candidates_container.add_theme_constant_override("separation", 18)
	_candidates_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center_vbox.add_child(_candidates_container)

	# 右侧规则面板（固定大小，不拉伸）
	var right_rules := _build_rule_panel(false)
	right_rules.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	center_h.add_child(right_rules)

	# ----- 下方：玩家完整牌库 -----
	var player_scroll := ScrollContainer.new()
	player_scroll.custom_minimum_size = Vector2(0, 220)
	player_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	player_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(player_scroll)

	var player_center := CenterContainer.new()
	player_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_scroll.add_child(player_center)

	_player_deck_grid = HBoxContainer.new()
	_player_deck_grid.add_theme_constant_override("separation", 8)
	_player_deck_grid.alignment = BoxContainer.ALIGNMENT_CENTER
	player_center.add_child(_player_deck_grid)

	_player_deck_title = Label.new()
	_player_deck_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_player_deck_title.add_theme_font_size_override("font_size", 18)
	_player_deck_title.add_theme_color_override("font_color", Color(0.25, 0.85, 1.0))
	_player_deck_title.text = "我方牌库"
	root_vbox.add_child(_player_deck_title)

	# ----- 升级总结面板（叠加层） -----
	_summary_panel = Control.new()
	_summary_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_summary_panel.visible = false
	_summary_panel.z_index = 95
	add_child(_summary_panel)


## 构造左/右规则说明面板
func _build_rule_panel(is_left: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.16, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.border_color = Color(0.3, 0.5, 0.7, 0.6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)

	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.custom_minimum_size = Vector2(196, 0)
	body.add_theme_font_size_override("normal_font_size", 14)

	if is_left:
		title.text = "⚡ 互换规则"
		title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
		body.text = (
			"[color=#ffcc66]· 每轮战斗结束[/color]\n"
			+ "[color=#cccccc]胜方与败方交换牌库[/color]\n\n"
			+ "[color=#ffcc66]· 你现在的牌库[/color]\n"
			+ "[color=#cccccc]是 MIRROR 上一轮的牌库[/color]\n\n"
			+ "[color=#ffcc66]· MIRROR 现在的牌库[/color]\n"
			+ "[color=#cccccc]是你上一轮的牌库[/color]\n\n"
			+ "[color=#88ccff]→ HP/能量已重置[/color]\n"
			+ "[color=#88ccff]→ Boss HP 每轮+3[/color]"
		)
	else:
		title.text = "🛠 升级规则"
		title.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6))
		body.text = (
			"[color=#aaffaa]· 4 张候选新卡[/color]\n"
			+ "[color=#cccccc]每轮抽取 4 张备用[/color]\n\n"
			+ "[color=#aaffaa]· 第 1 步[/color]\n"
			+ "[color=#cccccc]为自己选 1 张新卡[/color]\n"
			+ "[color=#cccccc]点击我方牌库中的牌替换[/color]\n\n"
			+ "[color=#aaffaa]· 第 2 步[/color]\n"
			+ "[color=#cccccc]为 MIRROR 选 1 张新卡[/color]\n"
			+ "[color=#cccccc]点击对方牌库中的牌替换[/color]\n\n"
			+ "[color=#ff8866]⚠ 双方牌库完全开放[/color]\n"
			+ "[color=#ff8866]互相可见，慎重选择[/color]"
		)

	vbox.add_child(title)
	vbox.add_child(body)
	return panel


## 激活奖励界面
func activate(player_deck: Array[CardData], boss_deck: Array[CardData]) -> void:
	_player_deck = player_deck
	_boss_deck = boss_deck
	_run_state = get_node_or_null("/root/RunState")

	# 抽 4 张随机新卡作为候选
	candidates = _draw_random_card_candidates(4)

	self_pick = null
	boss_pick = null
	remaining_candidates.clear()
	_replace_side = ""
	_player_used_custom = false  # v0.9.4：每次升级阶段重置

	current_step = Step.CANDIDATES
	visible = true
	_refresh_deck_grids()
	_show_candidates()


## 从 CardDatabase 取升级专属池（GDD-08 v0.8.3：按 round 返回每关 4 张专属升级牌）
func _draw_random_card_candidates(count: int) -> Array[CardData]:
	var card_db: Node = get_node_or_null("/root/CardDatabase")
	if card_db == null:
		return []
	# v0.8.3：从 RunState 读当前 round_index 并传给池函数
	# RunState.round_index 在 execute_swap 已 +1（即"即将开始的下一轮"号）
	var run_state_node: Node = get_node_or_null("/root/RunState")
	var round_idx: int = 2  # 默认按 R1 击败后处理
	if run_state_node != null:
		round_idx = run_state_node.round_index
	var pool: Array[CardData] = card_db.get_upgrade_card_pool(round_idx)
	pool.shuffle()
	var result: Array[CardData] = []
	for i in range(mini(count, pool.size())):
		result.append(pool[i])
	return result


# ===== 牌库网格（完整卡面） =====

func _refresh_deck_grids() -> void:
	_refresh_deck_grid(_boss_deck_grid, _boss_deck, "boss")
	_refresh_deck_grid(_player_deck_grid, _player_deck, "player")
	_update_deck_highlights()


func _refresh_deck_grid(grid: HBoxContainer, deck: Array[CardData], side: String) -> void:
	for child in grid.get_children():
		child.queue_free()

	var is_replace_mode: bool = (_replace_side == side)

	for i in range(deck.size()):
		var card: CardData = deck[i]
		var wrapper := _create_deck_card_full(card, i, side, is_replace_mode)
		grid.add_child(wrapper)


## 创建一张完整卡面（缩放，不截断、不变形）
## 关键：通过 card_clicked 信号接收点击（CardUI 自身处理鼠标命中），而不是 wrapper.gui_input
##       setup 内部会把 pivot_offset 设为中心，必须在 setup **之后** 强制改为 (0,0)
func _create_deck_card_full(card: CardData, deck_index: int, side: String,
		clickable: bool) -> Control:
	var card_w: float = 200.0 * DECK_CARD_SCALE
	var card_h: float = 280.0 * DECK_CARD_SCALE

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(card_w, card_h)
	wrapper.size = Vector2(card_w, card_h)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS  # 让 CardUI 自己接收点击
	wrapper.clip_contents = false

	var card_ui := Control.new()
	card_ui.set_script(CARD_UI_SCRIPT)
	wrapper.add_child(card_ui)
	card_ui.position = Vector2.ZERO
	card_ui.scale = Vector2(DECK_CARD_SCALE, DECK_CARD_SCALE)
	card_ui.setup(card, Vector2.ZERO)
	# setup() 内部强制 pivot=中心，必须在之后覆盖为左上角，否则缩放后整体偏移
	card_ui.pivot_offset = Vector2.ZERO
	card_ui.set("_hover_disabled", true)

	# 通过信号接收点击（CardUI 自己处理 hit-test，已支持缩放容差）
	if clickable:
		card_ui.card_clicked.connect(func(_card: CardData) -> void:
			_on_deck_card_clicked(deck_index, side)
		)

		# v0.8.2：可点击牌也改为金边（不覆盖卡面）+ 闪烁呼吸
		var hilite_border := _make_glow_border(card_w, card_h, Color(1.0, 0.85, 0.2), 3.0)
		wrapper.add_child(hilite_border)
		var t := wrapper.create_tween().set_loops()
		t.tween_property(hilite_border, "modulate:a", 1.0, 0.6)
		t.tween_property(hilite_border, "modulate:a", 0.45, 0.6)

	# v0.8.2：升级牌（up_* id）右上角贴静止徽章（替换入牌库后的标记）
	if String(card.id).begins_with("up_"):
		var static_badge := _make_upgrade_badge(false)
		# 缩放到与 deck card 比例匹配（候选 0.85→ deck 0.7，徽章按 deck 卡面相对大小再调一点）
		var badge_scale: float = DECK_CARD_SCALE / CANDIDATE_CARD_SCALE  # ≈0.82
		static_badge.scale = Vector2(badge_scale, badge_scale)
		# 右上角：徽章中心对准卡牌右上角顶点附近
		static_badge.position = Vector2(card_w - 22 * badge_scale, -8 * badge_scale)
		wrapper.add_child(static_badge)

	return wrapper


func _update_deck_highlights() -> void:
	if _replace_side == "boss":
		_boss_deck_title.text = "⬇ 点击 MIRROR 牌库中的牌完成替换 ⬇"
		_boss_deck_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		_player_deck_title.text = "我方牌库"
		_player_deck_title.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	elif _replace_side == "player":
		_player_deck_title.text = "⬆ 点击我方牌库中的牌完成替换 ⬆"
		_player_deck_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
		_boss_deck_title.text = "MIRROR 牌库"
		_boss_deck_title.add_theme_color_override("font_color", Color(0.4, 0.5, 0.6))
	else:
		_boss_deck_title.text = "MIRROR 牌库"
		_boss_deck_title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		_player_deck_title.text = "我方牌库"
		_player_deck_title.add_theme_color_override("font_color", Color(0.25, 0.85, 1.0))


func _on_deck_card_clicked(deck_index: int, side: String) -> void:
	if _replace_side != side:
		return
	var deck: Array[CardData] = _player_deck if side == "player" else _boss_deck
	if deck_index < 0 or deck_index >= deck.size():
		return
	_apply_replace(deck_index, side)


# ===== Step A：候选展示 =====

func _show_candidates() -> void:
	_step_indicator.text = "升级阶段"
	_banner.text = "4 张新卡候选 — 点击 1 张作为你的升级"
	# v0.9.4 v3：确保 designer 隐藏 + 候选区显示
	if _custom_designer != null:
		_custom_designer.visible = false
	_candidates_container.visible = true
	_clear_candidates()
	for i in range(candidates.size()):
		var card: CardData = candidates[i]
		var node := _create_candidate_card(card, i)
		_candidates_container.add_child(node)

	# v0.9.4：候选区末尾追加 ⭐ 自行设计按钮（仅在解锁条件下显示）
	if _is_custom_card_unlocked():
		var custom_btn := _create_custom_design_button()
		_candidates_container.add_child(custom_btn)


## v0.9.4：创建 ⭐ 自行设计按钮（与候选卡同尺寸 = 170×238，居中不拉伸）
func _create_custom_design_button() -> Control:
	var card_w: float = 200.0 * CANDIDATE_CARD_SCALE
	var card_h: float = 280.0 * CANDIDATE_CARD_SCALE

	# 用 Control wrapper 锁定尺寸（与 _create_candidate_card 保持一致）
	# 否则 Button 直接放在 HBoxContainer 中会被拉伸
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(card_w, card_h)
	wrapper.size = Vector2(card_w, card_h)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.text = "⭐\n\n自行设计\n\n协议\n调试器\n\n点击进入\n自由造牌"
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(0.0, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(0.4, 1.0, 1.0))

	# 自定义样式：紫色边框 + 全息感
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.08, 0.05, 0.15, 0.9)
	sb_normal.border_color = Color(0.6, 0.4, 1.0, 0.8)
	sb_normal.set_border_width_all(2)
	sb_normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sb_normal)

	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.12, 0.08, 0.22, 0.95)
	sb_hover.border_color = Color(0.8, 0.6, 1.0, 1.0)
	sb_hover.set_border_width_all(3)
	sb_hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", sb_hover)

	btn.pressed.connect(_on_custom_design_clicked)
	wrapper.add_child(btn)
	return wrapper


## v0.9.4：MIRROR 用 ⭐ 自行设计按钮（与玩家版同尺寸，副标题改为"为 MIRROR"）
func _create_custom_design_button_for_boss() -> Control:
	var card_w: float = 200.0 * CANDIDATE_CARD_SCALE
	var card_h: float = 280.0 * CANDIDATE_CARD_SCALE

	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(card_w, card_h)
	wrapper.size = Vector2(card_w, card_h)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS

	var btn := Button.new()
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.text = "⭐\n\n为 MIRROR\n自行设计\n\n协议\n调试器\n\n点击进入"
	btn.add_theme_font_size_override("font_size", 14)
	btn.add_theme_color_override("font_color", Color(1.0, 0.6, 0.6))   # MIRROR 红色调
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.85))

	# 红紫边框（区别玩家版的蓝紫）
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.15, 0.05, 0.08, 0.9)
	sb_normal.border_color = Color(1.0, 0.4, 0.5, 0.8)
	sb_normal.set_border_width_all(2)
	sb_normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", sb_normal)

	var sb_hover := StyleBoxFlat.new()
	sb_hover.bg_color = Color(0.22, 0.08, 0.12, 0.95)
	sb_hover.border_color = Color(1.0, 0.6, 0.7, 1.0)
	sb_hover.set_border_width_all(3)
	sb_hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", sb_hover)

	btn.pressed.connect(_on_custom_design_for_boss_clicked)
	wrapper.add_child(btn)
	return wrapper


## v0.9.4：MIRROR 走自调流程入口
func _on_custom_design_for_boss_clicked() -> void:
	if _custom_designer == null:
		return
	var round_idx: int = 2
	if _run_state != null:
		round_idx = _run_state.round_index
	var seq: int = 0
	var card_db: Node = get_node_or_null("/root/CardDatabase")
	if card_db != null and card_db.has_method("get_runtime_card_count"):
		seq = card_db.get_runtime_card_count()
	# 隐藏候选区 + 显示 designer
	_candidates_container.visible = false
	_banner.text = "为 MIRROR 自行设计 — 拨动数值后点击「确认构建」"
	# 临时替换 designer 的回调（用 boss 路径），完成后再恢复
	# 简化方案：用一次性连接 + 直接改 _on_custom_card_built 行为靠 current_step 区分
	_custom_designer.open_designer(_player_deck, _boss_deck, round_idx, seq)


## v0.9.4：自调升级解锁判定
## TODO：未来接入 ConfigFile 持久化"完成过的 run 数"，目前简化为 victory_streak >= 1（每关都解锁）
##       便于测试。后续按 Q3(b) 实现 2 周目解锁
func _is_custom_card_unlocked() -> bool:
	if _run_state == null:
		return false
	# 临时实现：当前 run 内连胜 >= 1（即至少打过一关 boss）就解锁自调
	# 严格 2 周目实现需新增持久存档，留给后续迭代
	return _run_state.victory_streak >= 1


## v0.9.4：玩家点击 ⭐ 自行设计按钮
func _on_custom_design_clicked() -> void:
	if _custom_designer == null:
		return
	var round_idx: int = 2
	if _run_state != null:
		round_idx = _run_state.round_index
	var seq: int = 0
	var card_db: Node = get_node_or_null("/root/CardDatabase")
	if card_db != null and card_db.has_method("get_runtime_card_count"):
		seq = card_db.get_runtime_card_count()
	# v3 嵌入式：隐藏候选区 + 显示 designer（同位置）
	_candidates_container.visible = false
	_banner.text = "自行设计升级牌 — 拨动数值后点击「确认构建」"
	_custom_designer.open_designer(_player_deck, _boss_deck, round_idx, seq)


## v0.9.4：玩家在 designer 内确认构建 → 注册到 CardDatabase + 进入"选我方牌替换"流程
## v0.9.4 bugfix：保留原本 4 张候选作为 MIRROR pick 池（自调牌只用于玩家方互换）
## v0.9.4 v5：current_step 区分玩家路径 / MIRROR 路径
func _on_custom_card_built(card: CardData) -> void:
	if card == null:
		return
	# 注册到 CardDatabase（让全系统可通过 get_card(id) 查询）
	var card_db: Node = get_node_or_null("/root/CardDatabase")
	if card_db != null and card_db.has_method("register_runtime_card"):
		card_db.register_runtime_card(card)

	# 恢复候选区可见性
	_candidates_container.visible = true

	# 根据当前 step 区分两条路径
	if current_step == Step.PICK_FOR_BOSS:
		# MIRROR 走自调路径：自调牌成为 boss_pick，进入"为 MIRROR 选要替换的牌"
		boss_pick = card
		_banner.text = "MIRROR 将获得「%s」→ 点击上方 MIRROR 牌库中要被替换的牌" % boss_pick.card_name
		_replace_side = "boss"
		_clear_candidates()
		_refresh_deck_grids()
	else:
		# 玩家走自调路径：自调牌成为 self_pick
		_player_used_custom = true
		self_pick = card
		# remaining_candidates = 原 4 张候选（MIRROR 之后从这 4 张选）
		remaining_candidates.clear()
		remaining_candidates.append_array(candidates)
		current_step = Step.PICK_FOR_SELF
		_step_indicator.text = "第 1 步 / 共 2 步"
		_banner.text = "你将获得「%s」→ 点击下方我方牌库中要被替换的牌" % self_pick.card_name
		_replace_side = "player"
		_clear_candidates()
		_refresh_deck_grids()


## v0.9.4：玩家在 designer 内取消 → 回到 4 选 1 候选界面
func _on_custom_designer_cancelled() -> void:
	# v3 嵌入式：恢复候选区显示
	_candidates_container.visible = true
	# v0.9.4：根据当前 step 恢复正确的提示文案
	if current_step == Step.PICK_FOR_BOSS:
		_banner.text = "为 MIRROR 选 1 张新卡"
	else:
		_banner.text = "4 张新卡候选 — 点击 1 张作为你的升级"


## 用 CardUI 创建候选新卡（完整卡面，可点击，不变形不截断）
## 通过 card_clicked 信号接收点击；setup 之后必须强制 pivot_offset=(0,0)
func _create_candidate_card(card: CardData, index: int) -> Control:
	var card_w: float = 200.0 * CANDIDATE_CARD_SCALE
	var card_h: float = 280.0 * CANDIDATE_CARD_SCALE
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(card_w, card_h)
	wrapper.size = Vector2(card_w, card_h)
	wrapper.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
	wrapper.clip_contents = false

	var card_ui := Control.new()
	card_ui.set_script(CARD_UI_SCRIPT)
	wrapper.add_child(card_ui)
	card_ui.position = Vector2.ZERO
	card_ui.scale = Vector2(CANDIDATE_CARD_SCALE, CANDIDATE_CARD_SCALE)
	card_ui.setup(card, Vector2.ZERO)
	# setup() 内部强制 pivot=中心，必须在之后覆盖为左上角
	card_ui.pivot_offset = Vector2.ZERO
	card_ui.set("_hover_disabled", true)

	# 通过 card_clicked 信号接收点击
	card_ui.card_clicked.connect(func(_card: CardData) -> void:
		_on_candidate_selected(index)
	)

	# v0.8.2：升级徽章（右上角外凸 ⌀32px），呼吸闪烁
	var badge := _make_upgrade_badge(true)
	# 定位到卡牌右上角，外凸（中心对齐到卡牌右上角顶点）
	badge.position = Vector2(card_w - 22, -10)
	wrapper.add_child(badge)

	return wrapper


## 创建升级徽章（金色圆 + ↑UP 字样），用于标识"升级牌"
## @param breathing true=候选阶段呼吸闪烁；false=替换入牌库后静止
## 自动设置 z_index、pivot_offset，调用方只需 add_child 并设置 position
func _make_upgrade_badge(breathing: bool) -> Control:
	const BADGE_SIZE: float = 32.0
	var badge := Control.new()
	badge.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.custom_minimum_size = Vector2(BADGE_SIZE, BADGE_SIZE)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.z_index = 5  # 浮在卡面之上
	# pivot 设为徽章中心，让缩放呼吸从中心进行
	badge.pivot_offset = Vector2(BADGE_SIZE / 2.0, BADGE_SIZE / 2.0)

	# 金色圆背景（StyleBoxFlat 圆角全 = 半径）
	var bg := Panel.new()
	bg.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	bg.position = Vector2.ZERO
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.78, 0.18, 1.0)
	sb.set_corner_radius_all(int(BADGE_SIZE / 2.0))
	sb.set_border_width_all(2)
	sb.border_color = Color(0.4, 0.25, 0.05, 1.0)
	sb.shadow_color = Color(1.0, 0.85, 0.2, 0.5)
	sb.shadow_size = 5
	bg.add_theme_stylebox_override("panel", sb)
	badge.add_child(bg)

	# 中心 "↑UP" 字样
	var label := Label.new()
	label.text = "↑UP"
	label.size = Vector2(BADGE_SIZE, BADGE_SIZE)
	label.position = Vector2.ZERO
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.15, 0.08, 0.0))
	label.add_theme_color_override("font_outline_color", Color(1.0, 0.95, 0.7))
	label.add_theme_constant_override("outline_size", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(label)

	# 呼吸闪烁（仅候选阶段）：scale 1.0 ↔ 1.18 + alpha 1.0 ↔ 0.7
	if breathing:
		var t := badge.create_tween().set_loops()
		t.set_parallel(true)
		t.tween_property(badge, "scale", Vector2(1.18, 1.18), 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(badge, "modulate:a", 0.72, 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.chain().set_parallel(true)
		t.tween_property(badge, "scale", Vector2(1.0, 1.0), 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(badge, "modulate:a", 1.0, 0.6)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	return badge


## 创建一个"只画 4 条边"的金色描边控件（不覆盖卡面）
## 用 4 个 ColorRect 拼边框：上 / 下 / 左 / 右
func _make_glow_border(w: float, h: float, color: Color, thickness: float = 3.0) -> Control:
	var border := Control.new()
	border.custom_minimum_size = Vector2(w, h)
	border.size = Vector2(w, h)
	border.position = Vector2.ZERO
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 上边
	var top := ColorRect.new()
	top.color = color
	top.position = Vector2.ZERO
	top.size = Vector2(w, thickness)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(top)

	# 下边
	var bottom := ColorRect.new()
	bottom.color = color
	bottom.position = Vector2(0, h - thickness)
	bottom.size = Vector2(w, thickness)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(bottom)

	# 左边
	var left := ColorRect.new()
	left.color = color
	left.position = Vector2.ZERO
	left.size = Vector2(thickness, h)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(left)

	# 右边
	var right := ColorRect.new()
	right.color = color
	right.position = Vector2(w - thickness, 0)
	right.size = Vector2(thickness, h)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.add_child(right)

	return border


# ===== Step B：玩家自选 =====

func _on_candidate_selected(index: int) -> void:
	if current_step == Step.CANDIDATES:
		current_step = Step.PICK_FOR_SELF
		_on_self_pick(index)
	elif current_step == Step.PICK_FOR_SELF:
		_on_self_pick(index)
	elif current_step == Step.PICK_FOR_BOSS:
		_on_boss_pick(index)


func _on_self_pick(index: int) -> void:
	if index < 0 or index >= candidates.size():
		return
	self_pick = candidates[index]
	_step_indicator.text = "第 1 步 / 共 2 步"
	_banner.text = "你将获得「%s」→ 点击下方我方牌库中要被替换的牌" % self_pick.card_name

	remaining_candidates.clear()
	for i in range(candidates.size()):
		if i != index:
			remaining_candidates.append(candidates[i])

	# 进入替换模式：高亮玩家牌库
	_replace_side = "player"
	_clear_candidates()
	_refresh_deck_grids()


# ===== Step C：给 MIRROR 选 =====

func _go_to_boss_pick_step() -> void:
	current_step = Step.PICK_FOR_BOSS
	_step_indicator.text = "第 2 步 / 共 2 步"
	_banner.text = "为 MIRROR 选 1 张新卡"
	_replace_side = ""
	_refresh_deck_grids()
	_clear_candidates()
	for i in range(remaining_candidates.size()):
		var card: CardData = remaining_candidates[i]
		var node := _create_candidate_card(card, i)
		_candidates_container.add_child(node)

	# v0.9.4：玩家本回合若未用自调（走的 4 选 1 路径），MIRROR 也可以走自调
	# 玩家用过自调 → MIRROR 只能走 4 选 1（每回合各方至多用 1 次自调）
	if not _player_used_custom and _is_custom_card_unlocked():
		var custom_btn := _create_custom_design_button_for_boss()
		_candidates_container.add_child(custom_btn)


func _on_boss_pick(index: int) -> void:
	if index < 0 or index >= remaining_candidates.size():
		return
	boss_pick = remaining_candidates[index]
	_banner.text = "MIRROR 将获得「%s」→ 点击上方 MIRROR 牌库中要被替换的牌" % boss_pick.card_name
	_replace_side = "boss"
	_clear_candidates()
	_refresh_deck_grids()


# ===== 替换逻辑 =====

func _apply_replace(deck_index: int, side: String) -> void:
	if side == "player" and self_pick != null:
		_player_deck[deck_index] = self_pick.duplicate()
	elif side == "boss" and boss_pick != null:
		_boss_deck[deck_index] = boss_pick.duplicate()

	_replace_side = ""
	_refresh_deck_grids()

	if side == "player":
		_go_to_boss_pick_step()
	else:
		_go_to_summary()


# ===== Step D：升级总结 =====

func _go_to_summary() -> void:
	current_step = Step.SUMMARY
	_step_indicator.text = "升级完成 — 准备下一轮"
	_banner.text = ""
	_clear_candidates()
	_replace_side = ""
	_refresh_deck_grids()

	_build_summary_panel()


func _build_summary_panel() -> void:
	for child in _summary_panel.get_children():
		child.queue_free()

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0.7)
	_summary_panel.add_child(bg)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -400
	vbox.offset_top = -200
	vbox.offset_right = 400
	vbox.offset_bottom = 200
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	_summary_panel.add_child(vbox)

	var self_label := Label.new()
	self_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	self_label.add_theme_font_size_override("font_size", 22)
	self_label.add_theme_color_override("font_color", Color(0.25, 0.85, 1.0))
	self_label.text = "你的新牌：%s" % (self_pick.card_name if self_pick != null else "无")
	vbox.add_child(self_label)

	var boss_label := Label.new()
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 22)
	boss_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	boss_label.text = "MIRROR 的新牌：%s" % (boss_pick.card_name if boss_pick != null else "无")
	vbox.add_child(boss_label)

	var fight_btn := Button.new()
	fight_btn.text = "⚡ 开战！"
	fight_btn.add_theme_font_size_override("font_size", 28)
	fight_btn.custom_minimum_size = Vector2(200, 60)
	fight_btn.pressed.connect(_on_fight_pressed)
	vbox.add_child(fight_btn)

	_summary_panel.visible = true


func _on_fight_pressed() -> void:
	visible = false
	_summary_panel.visible = false
	reward_completed.emit()


# ===== 工具 =====

func _clear_candidates() -> void:
	for child in _candidates_container.get_children():
		child.queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if _replace_side != "":
					_replace_side = ""
					_refresh_deck_grids()
					if current_step == Step.PICK_FOR_SELF:
						_banner.text = "4 张新卡候选 — 点击 1 张作为你的升级"
						current_step = Step.CANDIDATES
						_show_candidates()
					elif current_step == Step.PICK_FOR_BOSS:
						_banner.text = "为 MIRROR 选 1 张新卡"
						_clear_candidates()
						for i in range(remaining_candidates.size()):
							var c: CardData = remaining_candidates[i]
							var node := _create_candidate_card(c, i)
							_candidates_container.add_child(node)
					get_viewport().set_input_as_handled()
