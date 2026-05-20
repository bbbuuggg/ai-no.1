extends Control
class_name CustomCardDesigner
## 自调升级牌嵌入式造牌面板（v0.9.4 PR-3 / 嵌入版）
##
## 流程：
##   1. RewardScreen 调 open_designer(player_deck, boss_deck, round_index, sequence) → 计算 budget
##   2. 玩家拨动 6 个 HexDial（damage/armor/heal/cost/element/polarity）+ 3 个附加效果切换
##   3. 实时校验调用 CustomCardValidator.validate → 更新预览卡 + 校验状态
##   4. 玩家点 [确认构建] → emit card_built(CardData)
##   5. 玩家点 [返回] → emit cancelled
##
## v3 嵌入式：本面板直接 fit 父容器（候选区），无独立全屏遮罩
##           父容器（RewardScreen）负责显示/隐藏切换
##           顶部加 [?] 帮助按钮，点击展开/收起规则说明
##
## 视觉风格：全息投影调试器（深紫黑 + 霓虹蓝 + 等宽数字）

signal card_built(card: CardData)
signal cancelled()

const Validator := preload("res://scripts/data/custom_card_validator.gd")
const Factory := preload("res://scripts/data/custom_card_factory.gd")
const DVC := preload("res://scripts/utils/deck_value_calculator.gd")
const HEX_DIAL_SCRIPT := preload("res://scripts/ui/hex_dial.gd")
const CARD_UI_SCRIPT := preload("res://scripts/ui/card_ui.gd")

# 视觉常量
const COLOR_PANEL := Color(0.08, 0.05, 0.12, 0.95)
const COLOR_BORDER := Color(0.0, 0.7, 0.9, 0.7)
const COLOR_ACCENT := Color(0.0, 0.95, 1.0)
const COLOR_OK := Color(0.4, 1.0, 0.6)
const COLOR_WARN := Color(1.0, 0.85, 0.3)
const COLOR_ERR := Color(1.0, 0.4, 0.4)

# 状态
var _budget: int = 6
var _round_index: int = 2
var _seq: int = 0  # CardDatabase 累计序号

# UI 节点
var _budget_label: Label
var _remaining_label: Label
var _validation_label: RichTextLabel
var _confirm_btn: Button
var _cancel_btn: Button
var _help_btn: Button
var _help_panel: PanelContainer       # 帮助浮层（默认隐藏）
var _preview_card: Control            # 实时预览的 CardUI

# 6 个 HexDial
var _dial_dmg: Control
var _dial_armor: Control
var _dial_heal: Control
var _dial_cost: Control
var _dial_element: Control
var _dial_polarity: Control

# 3 个附加效果开关
var _chk_ignore_armor: CheckBox
var _chk_draw: CheckBox
var _chk_reflect: CheckBox

# 当前 spec（实时同步）
var _last_validation: Dictionary = {}


func _ready() -> void:
	# v3 嵌入式：fit 父容器（不再全屏；父级负责显示/隐藏）
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	visible = false
	_build_ui()


## 公开入口：打开面板，传入双方牌库 + 当前轮次
func open_designer(player_deck: Array, boss_deck: Array, round_index: int, sequence: int) -> void:
	_round_index = round_index
	_seq = sequence
	var budget_info: Dictionary = DVC.calc_budget(player_deck, boss_deck, round_index)
	_budget = int(budget_info["budget"])
	_budget_label.text = "可用点数：%d 点（第 %d 关 / 我方牌库强度 %.1f vs 对手 %.1f）" % [
		_budget, round_index,
		float(budget_info.get("player_value", 0.0)),
		float(budget_info.get("boss_value", 0.0)),
	]
	# 重置所有 dial 到默认值
	_dial_dmg.set_value(0)
	_dial_armor.set_value(0)
	_dial_heal.set_value(0)
	_dial_cost.set_value(1)
	_dial_element.set_value(1)  # 默认 火（避开 无=0）
	_dial_polarity.set_value(1) # 默认 光
	_chk_ignore_armor.button_pressed = false
	_chk_draw.button_pressed = false
	_chk_reflect.button_pressed = false
	# 帮助默认收起
	if _help_panel != null:
		_help_panel.visible = false

	visible = true
	_revalidate()


## ============================================================
## UI 构建（嵌入式 — 无独立遮罩，整体作为一个面板嵌入父容器）
## ============================================================

func _build_ui() -> void:
	# 整体容器使用 MarginContainer，以便父容器（候选区）控制大小
	# 自身 fit 父容器
	set_anchors_preset(Control.PRESET_FULL_RECT)

	# 主面板（背景 + 边框）
	var root_panel := _make_panel()
	root_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root_panel)

	# 内边距
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	root_panel.add_child(margin)

	var main_v := VBoxContainer.new()
	main_v.add_theme_constant_override("separation", 8)
	margin.add_child(main_v)

	# === 顶部状态栏：标题 + 预算 + 帮助按钮 + 返回按钮 ===
	_build_top_bar(main_v)

	# === 主体：左输入（3 列横向 + 校验按钮条） + 右预览（HBox）===
	var body_h := HBoxContainer.new()
	body_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_h.add_theme_constant_override("separation", 16)
	main_v.add_child(body_h)

	# 左：输入区 = VBox（上方 3 列 dial / 下方 校验+确认按钮条）
	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 10)
	body_h.add_child(left_v)

	# 左侧 3 列 dial 区
	var left_h := HBoxContainer.new()
	left_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_h.add_theme_constant_override("separation", 18)
	left_v.add_child(left_h)

	# 第 1 列：核心数值（伤害/护甲/治疗）
	var col_main := VBoxContainer.new()
	col_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_main.size_flags_vertical = Control.SIZE_FILL
	col_main.add_theme_constant_override("separation", 8)
	left_h.add_child(col_main)

	# 第 2 列：卡牌属性（费用/元素/极性）
	var col_meta := VBoxContainer.new()
	col_meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_meta.size_flags_vertical = Control.SIZE_FILL
	col_meta.add_theme_constant_override("separation", 8)
	left_h.add_child(col_meta)

	# 第 3 列：附加效果（3 个 CheckBox）
	var col_kw := VBoxContainer.new()
	col_kw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_kw.size_flags_vertical = Control.SIZE_FILL
	col_kw.add_theme_constant_override("separation", 8)
	left_h.add_child(col_kw)

	_build_left_inputs(col_main, col_meta, col_kw)

	# 左下方：校验状态 + 确认按钮（避开被玩家牌库遮挡的右下区域）
	_build_validation_bar(left_v)

	# 右：预览（仅卡面，无校验/按钮）
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(220, 0)
	right_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_theme_constant_override("separation", 6)
	body_h.add_child(right_vbox)

	_build_right_preview(right_vbox)

	# 帮助浮层（覆盖在主体之上，默认隐藏）
	_build_help_panel()


func _build_top_bar(parent: VBoxContainer) -> void:
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 12)
	parent.add_child(top_h)

	# 标题
	var title := Label.new()
	title.text = "⚡ 协议调试器"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", COLOR_ACCENT)
	top_h.add_child(title)

	# 预算（占主要空间）
	_budget_label = Label.new()
	_budget_label.add_theme_font_size_override("font_size", 13)
	_budget_label.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_budget_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_budget_label.text = "可用点数：0 点"
	top_h.add_child(_budget_label)

	# 帮助按钮
	_help_btn = Button.new()
	_help_btn.text = "? 规则"
	_help_btn.custom_minimum_size = Vector2(80, 28)
	_help_btn.toggle_mode = true
	_help_btn.toggled.connect(_on_help_toggled)
	top_h.add_child(_help_btn)

	# 返回按钮（移到顶部更顺手）
	_cancel_btn = Button.new()
	_cancel_btn.text = "返回 4 选 1"
	_cancel_btn.custom_minimum_size = Vector2(110, 28)
	_cancel_btn.pressed.connect(_on_cancel)
	top_h.add_child(_cancel_btn)


func _build_help_panel() -> void:
	# 浮层覆盖在 designer 主体上方，默认隐藏；点击 [? 规则] 切换
	# v3 修复：anchors 限制在 designer 内部，避免溢出被外部牌库 UI 挡住
	_help_panel = PanelContainer.new()
	_help_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_panel.offset_left = 24
	_help_panel.offset_right = -24
	_help_panel.offset_top = 48     # 留出顶部状态栏
	_help_panel.offset_bottom = -16
	_help_panel.visible = false
	_help_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_panel.z_index = 5  # 高于主体 dial 区

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.1, 0.98)
	sb.border_color = Color(0.6, 0.4, 1.0, 0.9)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	_help_panel.add_theme_stylebox_override("panel", sb)
	add_child(_help_panel)

	var help_margin := MarginContainer.new()
	help_margin.add_theme_constant_override("margin_left", 20)
	help_margin.add_theme_constant_override("margin_right", 20)
	help_margin.add_theme_constant_override("margin_top", 16)
	help_margin.add_theme_constant_override("margin_bottom", 16)
	_help_panel.add_child(help_margin)

	var help_v := VBoxContainer.new()
	help_v.add_theme_constant_override("separation", 8)
	help_margin.add_child(help_v)

	var help_title := Label.new()
	help_title.text = "📖 自调升级牌规则"
	help_title.add_theme_font_size_override("font_size", 18)
	help_title.add_theme_color_override("font_color", COLOR_ACCENT)
	help_v.add_child(help_title)

	# v3 修复：帮助内容用 ScrollContainer 包住，避免高度受限时下方内容（重要提醒）被挡
	var help_scroll := ScrollContainer.new()
	help_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	help_v.add_child(help_scroll)

	var help_text := RichTextLabel.new()
	help_text.bbcode_enabled = true
	help_text.fit_content = true
	help_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_text.add_theme_font_size_override("normal_font_size", 12)
	help_text.text = (
		"[color=#aaffcc]【点数兑换】[/color]\n"
		+ "  · 1 点 = 1 伤害（拨多少就是多少伤）\n"
		+ "  · 1 点 = 1.5 护甲（防御稍便宜，鼓励防御构筑）\n"
		+ "  · 1 点 = 1 治疗\n\n"
		+ "[color=#aaffcc]【强制开销】[/color]\n"
		+ "  · 元素：1 点（必选 火/水/木 之一，参与克制）\n"
		+ "  · 极性：免费（必选 光/暗 之一，参与 2:2 平衡）\n\n"
		+ "[color=#aaffcc]【附加效果】[/color]\n"
		+ "  · 无视护甲：3 点（需配伤害）\n"
		+ "  · 抽 1 张牌：5 点（强力，慎选）\n"
		+ "  · 反伤 2：4 点（需配护甲）\n\n"
		+ "[color=#aaffcc]【数值上限（按费用分档）】[/color]\n"
		+ "  · 0 费：伤≤5 / 甲≤7 / 治≤4\n"
		+ "  · 1 费：伤≤8 / 甲≤11 / 治≤7\n"
		+ "  · 2 费：伤≤12 / 甲≤15 / 治≤10\n"
		+ "  · 3 费：伤≤15 / 甲≤22 / 治≤13\n\n"
		+ "[color=#ffaaaa]【重要提醒】[/color]\n"
		+ "  · 0 费会额外扣 3 点（鼓励 1 费起步）\n"
		+ "  · 你设计的牌互换后 [b]对手也会获得[/b]，下一关用同款打你 → 慎造爆牌"
	)
	help_scroll.add_child(help_text)


func _on_help_toggled(pressed: bool) -> void:
	if _help_panel != null:
		_help_panel.visible = pressed


func _build_left_inputs(col_main: VBoxContainer, col_meta: VBoxContainer, col_kw: VBoxContainer) -> void:
	# v3 嵌入式 + 3 列横向：核心数值 / 卡牌属性 / 附加效果
	# 标题/预算/提示已移到顶部状态栏

	# === 第 1 列：核心数值 ===
	var sec_main := Label.new()
	sec_main.text = "// 核心数值"
	sec_main.add_theme_font_size_override("font_size", 12)
	sec_main.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	col_main.add_child(sec_main)

	# v2 改进：dial 拨的是"点数花费"，旁边 suffix 显示"对应数值"
	# damage：1pt = 1 伤；armor：1pt = 1.5 甲；heal：1pt = 1 治
	_dial_dmg = _make_dial("伤害", 0, 13, 0, [], true, "damage")
	col_main.add_child(_dial_dmg)
	_dial_armor = _make_dial("护甲", 0, 13, 0, [], true, "armor")
	col_main.add_child(_dial_armor)
	_dial_heal = _make_dial("治疗", 0, 10, 0, [], true, "heal")
	col_main.add_child(_dial_heal)

	# === 第 2 列：卡牌属性 ===
	var sec_meta := Label.new()
	sec_meta.text = "// 卡牌属性"
	sec_meta.add_theme_font_size_override("font_size", 12)
	sec_meta.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	col_meta.add_child(sec_meta)

	_dial_cost = _make_dial("费用", 0, 3, 1, [], false, "energy_cost")
	col_meta.add_child(_dial_cost)

	_dial_element = _make_dial("元素", 0, 3, 1,
		["无", "火", "水", "木"] as Array[String], false, "element")
	col_meta.add_child(_dial_element)

	_dial_polarity = _make_dial("极性", 0, 2, 1,
		["无", "光", "暗"] as Array[String], false, "polarity")
	col_meta.add_child(_dial_polarity)

	# === 第 3 列：附加效果 ===
	var sec_kw := Label.new()
	sec_kw.text = "// 附加效果（可选）"
	sec_kw.add_theme_font_size_override("font_size", 12)
	sec_kw.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	col_kw.add_child(sec_kw)

	_chk_ignore_armor = _make_checkbox("无视护甲（消耗 3 点）")
	col_kw.add_child(_chk_ignore_armor)

	_chk_draw = _make_checkbox("抽 1 张牌（消耗 5 点）")
	col_kw.add_child(_chk_draw)

	_chk_reflect = _make_checkbox("反伤 2（消耗 4 点）")
	col_kw.add_child(_chk_reflect)


func _build_right_preview(parent: VBoxContainer) -> void:
	# v3.1：右侧仅放预览卡，校验+确认按钮已挪到左下（避开玩家牌库遮挡）
	# 预览标题
	var preview_title := Label.new()
	preview_title.text = "[ 实时预览 ]"
	preview_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_title.add_theme_font_size_override("font_size", 13)
	preview_title.add_theme_color_override("font_color", COLOR_ACCENT)
	parent.add_child(preview_title)

	# 卡面预览区（嵌入版略小）
	var preview_holder := CenterContainer.new()
	preview_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_holder.custom_minimum_size = Vector2(0, 240)
	parent.add_child(preview_holder)

	_preview_card = Control.new()
	_preview_card.set_script(CARD_UI_SCRIPT)
	_preview_card.custom_minimum_size = Vector2(170, 238)
	_preview_card.scale = Vector2(0.85, 0.85)
	preview_holder.add_child(_preview_card)


## v3.1：左下校验状态 + 确认按钮条（避开右下被玩家牌库遮挡的区域）
func _build_validation_bar(parent: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(bar)

	# 左侧（占 2/3）：校验状态文字（剩余预算 + 错误列表）
	var validation_v := VBoxContainer.new()
	validation_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_v.add_theme_constant_override("separation", 4)
	bar.add_child(validation_v)

	_remaining_label = Label.new()
	_remaining_label.add_theme_font_size_override("font_size", 13)
	_remaining_label.text = ""
	validation_v.add_child(_remaining_label)

	_validation_label = RichTextLabel.new()
	_validation_label.fit_content = true
	_validation_label.bbcode_enabled = true
	_validation_label.custom_minimum_size = Vector2(0, 50)
	_validation_label.add_theme_font_size_override("normal_font_size", 11)
	validation_v.add_child(_validation_label)

	# 右侧（占 1/3）：确认按钮（cancel 已在顶部状态栏）
	_confirm_btn = Button.new()
	_confirm_btn.text = "确认构建"
	_confirm_btn.custom_minimum_size = Vector2(140, 50)
	_confirm_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_confirm_btn.pressed.connect(_on_confirm)
	bar.add_child(_confirm_btn)


## ============================================================
## 工厂函数
## ============================================================

func _make_panel() -> Panel:
	var p := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_PANEL
	sb.border_color = COLOR_BORDER
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_separator() -> Control:
	var sep := ColorRect.new()
	sep.color = Color(0.0, 0.6, 0.9, 0.3)
	sep.custom_minimum_size = Vector2(0, 1)
	return sep


func _make_dial(label: String, mn: int, mx: int, init_v: int,
		enum_lbls: Array[String] = [], hex_mode: bool = true,
		code_var: String = "") -> Control:
	var dial := Control.new()
	dial.set_script(HEX_DIAL_SCRIPT)
	dial.configure(label, mn, mx, init_v, enum_lbls, hex_mode, code_var)
	# 监听值变化，触发实时校验
	dial.value_changed.connect(_on_any_value_changed)
	return dial


func _make_checkbox(text: String) -> CheckBox:
	var cb := CheckBox.new()
	cb.text = text
	cb.add_theme_font_size_override("font_size", 12)
	cb.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	cb.toggled.connect(func(_pressed: bool) -> void: _revalidate())
	return cb


## ============================================================
## 校验 + 预览实时刷新
## ============================================================

func _on_any_value_changed(_v: int) -> void:
	_revalidate()


func _revalidate() -> void:
	if _dial_dmg == null:
		return

	# v2：根据当前费用动态调整 dial 上限（点数上限）
	# damage 上限点数 = LIMIT_BY_COST[cost]["damage"]（= 数值上限，因为 1pt=1 伤）
	# armor 上限点数 = ceil(LIMIT_BY_COST[cost]["armor"] / 1.5)
	# heal 上限点数 = LIMIT_BY_COST[cost]["heal"]
	var cost: int = _dial_cost.get_value()
	var limit: Dictionary = Validator.LIMIT_BY_COST.get(cost, Validator.LIMIT_BY_COST[3])
	var dmg_max_pts: int = int(limit["damage"])
	var armor_max_pts: int = int(ceil(float(limit["armor"]) / 1.5))
	var heal_max_pts: int = int(limit["heal"])
	_apply_dial_limit(_dial_dmg, dmg_max_pts)
	_apply_dial_limit(_dial_armor, armor_max_pts)
	_apply_dial_limit(_dial_heal, heal_max_pts)

	# v2：更新 dial suffix（"→ X 伤/甲/治"）
	var dmg_pts: int = _dial_dmg.get_value()
	var armor_pts: int = _dial_armor.get_value()
	var heal_pts: int = _dial_heal.get_value()
	if dmg_pts > 0:
		_dial_dmg.set_suffix_text("→ %d 伤" % Validator.points_to_value("damage", dmg_pts))
	else:
		_dial_dmg.set_suffix_text("")
	if armor_pts > 0:
		_dial_armor.set_suffix_text("→ %d 甲" % Validator.points_to_value("armor", armor_pts))
	else:
		_dial_armor.set_suffix_text("")
	if heal_pts > 0:
		_dial_heal.set_suffix_text("→ %d 治" % Validator.points_to_value("heal", heal_pts))
	else:
		_dial_heal.set_suffix_text("")

	var spec: Dictionary = _build_spec()
	var r: Dictionary = Validator.validate(spec, _budget)
	_last_validation = r

	# 剩余预算
	var remaining: int = int(r["remaining"])
	var total: int = int(r["total_cost"])
	if remaining < 0:
		_remaining_label.add_theme_color_override("font_color", COLOR_ERR)
		_remaining_label.text = "已用 %d / %d ⚠ 超 %d" % [total, _budget, -remaining]
	elif remaining == 0:
		_remaining_label.add_theme_color_override("font_color", COLOR_OK)
		_remaining_label.text = "已用 %d / %d (满载)" % [total, _budget]
	else:
		_remaining_label.add_theme_color_override("font_color", COLOR_ACCENT)
		_remaining_label.text = "已用 %d / %d (剩 %d)" % [total, _budget, remaining]

	# 错误列表
	_refresh_validation_text(r)

	# 预览卡
	_refresh_preview_card(spec)

	# 确认按钮
	_confirm_btn.disabled = not bool(r["is_valid"])
	if r["is_valid"]:
		_confirm_btn.modulate = Color(0.6, 1.0, 0.7)
	else:
		_confirm_btn.modulate = Color(0.5, 0.5, 0.55)


## v2：根据费用动态调整 dial 的点数上限（防止玩家拨超档）
func _apply_dial_limit(dial: Control, new_max: int) -> void:
	if dial == null:
		return
	# 直接修改 max_value（HexDial 内部是 var，可访问）
	dial.max_value = new_max
	# 如果当前值超新上限，clamp 下来（会触发 value_changed → 但我们已在 _revalidate 中，无递归风险）
	if dial.current_value > new_max:
		dial.set_value(new_max)


func _build_spec() -> Dictionary:
	# v2：dial 拨的是\"点数花费\"，需要换算成实际效果数值
	# damage / heal：1pt = 1 数值（dial 值就是数值）
	# armor：1pt = 1.5 甲（floor 取整）
	var dmg_pts: int = _dial_dmg.get_value()
	var armor_pts: int = _dial_armor.get_value()
	var heal_pts: int = _dial_heal.get_value()

	return {
		"damage": Validator.points_to_value("damage", dmg_pts),
		"armor": Validator.points_to_value("armor", armor_pts),
		"heal": Validator.points_to_value("heal", heal_pts),
		"energy_cost": _dial_cost.get_value(),
		"element": _dial_element.get_value(),
		"polarity": _dial_polarity.get_value(),
		"ignore_armor": _chk_ignore_armor.button_pressed,
		"draw_cards": 1 if _chk_draw.button_pressed else 0,
		"reflect_damage": 2 if _chk_reflect.button_pressed else 0,
	}


func _refresh_validation_text(r: Dictionary) -> void:
	var errors: Array = r.get("errors", [])
	if errors.is_empty():
		_validation_label.text = "[color=#66ff99]✓ 校验通过 — 可以构建[/color]"
	else:
		var lines: Array[String] = []
		for e in errors:
			lines.append("[color=#ff6666]" + String(e) + "[/color]")
		_validation_label.text = "\n".join(lines)


func _refresh_preview_card(spec: Dictionary) -> void:
	if _preview_card == null:
		return
	# 用 Factory 生成"草稿"CardData（id 不重要，仅预览用）
	var draft: CardData = Factory.build_card_data(spec, _round_index, _seq)
	if _preview_card.has_method("setup"):
		_preview_card.setup(draft, Vector2.ZERO)
		_preview_card.pivot_offset = Vector2.ZERO
		_preview_card.set("_hover_disabled", true)


## ============================================================
## 按钮事件
## ============================================================

func _on_confirm() -> void:
	if not bool(_last_validation.get("is_valid", false)):
		return
	var spec: Dictionary = _build_spec()
	var card: CardData = Factory.build_card_data(spec, _round_index, _seq)
	visible = false
	card_built.emit(card)


func _on_cancel() -> void:
	visible = false
	cancelled.emit()
