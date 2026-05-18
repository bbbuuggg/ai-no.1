extends Control
## 陷阱部署 UI — 卡片化重构
##
## 视觉规范（由 art-director 定义）：
##   - 候选区：TrapCardUI 卡片横排，青蓝主色+⚠标识+触发类型图腾
##   - 3 槽位：卡位剪影（150×220 同等尺寸），虚线边框+垂直扫描线
##   - 选中待放置：TrapCardUI.set_selected(true) 脉冲发光
##     + 合法槽位同步点亮扫描线
##   - 槽位色：攻=红 / 技=绿 / 高费=金
##
## 交互流：
##   点击候选卡 → _pending_trap 置为该卡 → 该卡脉冲发光 + 空槽位扫描线启动
##   → 点击空槽位 → 部署 + 清除 pending 状态
##   → 点击"移除"按钮 → 退回资源和候选区

signal deploy_confirmed()
signal probe_jammed()
signal constraint_changed(new_value: int)  # UI 内部约束资源变动时通知 HUD 同步

var _trap_inventory: Array[TrapData] = []
var _constraint_resource: int = 0
var _slots: Array = [null, null, null]  # TrapData or null
var _is_active: bool = false

# 待放置的陷阱 + 对应的候选卡 UI 引用（用于切换选中态）
var _pending_trap: TrapData = null
var _pending_card: TrapCardUI = null

# 槽位 → TrapData.TrapSlot 映射（3 槽位分别代表 ATTACK/SKILL/HIGH_COST 触发类型）
const SLOT_TYPES: Array[int] = [
	TrapData.TrapSlot.ATTACK,
	TrapData.TrapSlot.SKILL,
	TrapData.TrapSlot.HIGH_COST,
]

const SLOT_NAMES := ["攻击触发", "技能触发", "高费触发"]
const SLOT_COLORS := [
	Color(0.9, 0.2, 0.2, 0.9),   # 攻击 - 红
	Color(0.2, 0.9, 0.4, 0.9),   # 技能 - 绿
	Color(0.9, 0.75, 0.1, 0.9),  # 高费 - 金
]

# 卡位/卡片尺寸（与 BaseCardUI 一致）
const SILHOUETTE_WIDTH := 150
const SILHOUETTE_HEIGHT := 220

@onready var slots_container: HBoxContainer = $VBox/SlotsArea
@onready var traps_container: HBoxContainer = $VBox/TrapsArea
@onready var resource_label: Label = $VBox/InfoBar/ResourceLabel
@onready var jam_btn: Button = $VBox/InfoBar/JamBtn
@onready var confirm_btn: Button = $VBox/InfoBar/ConfirmBtn


func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	jam_btn.pressed.connect(_on_jam)
	# 候选区拉开间距给卡片 hover 抬升留空间
	traps_container.add_theme_constant_override("separation", 16)
	slots_container.add_theme_constant_override("separation", 24)


func activate(traps: Array[TrapData], resource: int) -> void:
	_trap_inventory = traps.duplicate()
	_constraint_resource = resource
	_slots = [null, null, null]
	_pending_trap = null
	_pending_card = null
	_is_active = true
	visible = true
	_refresh_all()


func deactivate() -> void:
	_is_active = false
	visible = false


func get_deployed_slots() -> Array:
	return _slots.duplicate()


## 返回 UI 内当前剩余的约束资源（已扣除部署消耗与干扰消耗）
## 用于 _on_deploy_confirmed 时把 UI 的最终值回写到 battle，避免 battle 二次扣款
func get_remaining_resource() -> int:
	return _constraint_resource


# ------------------------------------------------------------------
# 总刷新
# ------------------------------------------------------------------
func _refresh_all() -> void:
	_refresh_slots()
	_refresh_traps()
	_update_info()


# ------------------------------------------------------------------
# 槽位（卡位剪影）
# ------------------------------------------------------------------
func _refresh_slots() -> void:
	for child in slots_container.get_children():
		child.queue_free()

	for i in range(3):
		var slot_view := _make_slot_view(i)
		slots_container.add_child(slot_view)


func _make_slot_view(index: int) -> Control:
	var slot_type: int = SLOT_TYPES[index]
	var slot_color: Color = SLOT_COLORS[index]
	var trap: TrapData = _slots[index]
	# 高亮条件：候选为待放置 + 槽位为空
	var is_highlight: bool = _pending_trap != null and trap == null

	var root := SlotSilhouette.new()
	root.custom_minimum_size = Vector2(SILHOUETTE_WIDTH, SILHOUETTE_HEIGHT)
	root.configure(index, slot_type, slot_color, trap, is_highlight, SLOT_NAMES[index])
	root.slot_clicked.connect(_on_slot_pressed)
	root.remove_requested.connect(_on_remove_slot)
	return root


# ------------------------------------------------------------------
# 候选区（卡片）
# ------------------------------------------------------------------
func _refresh_traps() -> void:
	# 幽灵卡防御：queue_free 是延迟销毁，在新卡 ready 前的过渡帧
	# 旧卡仍可能响应 _input。先批量禁用 is_usable，再 queue_free。
	for child in traps_container.get_children():
		var old_card := child as TrapCardUI
		if old_card != null:
			old_card.is_usable = false  # 直接设字段，绕过 set_usable 的早返回判定
		child.queue_free()

	for trap in _trap_inventory:
		var card := TrapCardUI.new()
		var can_use: bool = trap.is_bluff or trap.resource_cost <= _constraint_resource
		card.setup(trap, can_use)
		card.trap_clicked.connect(_on_trap_selected)
		traps_container.add_child(card)
		# 若该卡就是 pending，恢复选中态（activate 时不会遇到，refresh 中会用到）
		if _pending_trap != null and trap == _pending_trap:
			card.set_selected(true)
			_pending_card = card


# ------------------------------------------------------------------
# 候选卡点击 → 进入"待放置"
# ------------------------------------------------------------------
func _on_trap_selected(trap: TrapData) -> void:
	if not _is_active:
		return
	# 如果点击的是当前已选中的卡，视为取消
	if _pending_trap == trap:
		_clear_pending()
		_refresh_slots()
		return

	# 切换选中：旧卡取消 → 新卡选中
	if _pending_card != null and is_instance_valid(_pending_card):
		_pending_card.set_selected(false)
	_pending_trap = trap
	# 找到对应的新卡
	_pending_card = _find_card_for_trap(trap)
	if _pending_card != null:
		_pending_card.set_selected(true)
	# 刷新槽位高亮
	_refresh_slots()


func _find_card_for_trap(trap: TrapData) -> TrapCardUI:
	for child in traps_container.get_children():
		var c := child as TrapCardUI
		if c != null and c.trap_data == trap:
			return c
	return null


func _clear_pending() -> void:
	if _pending_card != null and is_instance_valid(_pending_card):
		_pending_card.set_selected(false)
	_pending_trap = null
	_pending_card = null


# ------------------------------------------------------------------
# 槽位点击 → 部署
# ------------------------------------------------------------------
func _on_slot_pressed(slot_index: int) -> void:
	if not _is_active:
		return
	if _pending_trap == null:
		return
	if _slots[slot_index] != null:
		return
	_deploy_to_slot(_pending_trap, slot_index)


func _deploy_to_slot(trap: TrapData, slot_index: int) -> void:
	if not trap.is_bluff:
		if trap.resource_cost > _constraint_resource:
			return
		_constraint_resource -= trap.resource_cost
	_slots[slot_index] = trap
	_trap_inventory.erase(trap)
	_clear_pending()
	_refresh_all()


func _on_remove_slot(slot_index: int) -> void:
	if _slots[slot_index] == null:
		return
	var trap: TrapData = _slots[slot_index]
	if not trap.is_bluff:
		_constraint_resource += trap.resource_cost
	_trap_inventory.append(trap)
	_slots[slot_index] = null
	_refresh_all()


# ------------------------------------------------------------------
# 干扰 / 确认 / 资源显示
# ------------------------------------------------------------------
func _on_jam() -> void:
	if _constraint_resource < 1:
		return
	_constraint_resource -= 1
	jam_btn.disabled = true
	jam_btn.text = "已干扰"
	probe_jammed.emit()
	_update_info()


func _on_confirm() -> void:
	deploy_confirmed.emit()
	deactivate()


func _update_info() -> void:
	resource_label.text = "约束资源: %d" % _constraint_resource
	jam_btn.disabled = _constraint_resource < 1
	# 通知外部 HUD 实时同步（视觉一致性：避免"HUD 显示 ◆1 但 UI 内已 0"的错位）
	constraint_changed.emit(_constraint_resource)
	# 刷新候选卡的 usable 态（资源变化后部分卡可能可用/禁用切换）
	for child in traps_container.get_children():
		var c := child as TrapCardUI
		if c != null and c.trap_data != null:
			var can_use: bool = c.trap_data.is_bluff or c.trap_data.resource_cost <= _constraint_resource
			c.set_usable(can_use)


# ==================================================================
# 内部类：卡位剪影（槽位 UI）
# 支持虚线边框、扫描线高亮、点击/移除
# ==================================================================
class SlotSilhouette extends Control:
	signal slot_clicked(index: int)
	signal remove_requested(index: int)

	const TITLE_H := 28.0
	const DASH_LEN := 8.0
	const DASH_GAP := 6.0

	var _index: int = 0
	var _slot_type: int = 0
	var _slot_color: Color = Color.WHITE
	var _trap: TrapData = null
	var _is_highlight: bool = false
	var _title: String = ""
	var _scan_time: float = 0.0
	var _is_hovered: bool = false
	var _remove_btn: Button = null

	func configure(idx: int, slot_type: int, slot_color: Color, trap: TrapData, is_highlight: bool, title: String) -> void:
		_index = idx
		_slot_type = slot_type
		_slot_color = slot_color
		_trap = trap
		_is_highlight = is_highlight
		_title = title
		mouse_filter = Control.MOUSE_FILTER_STOP
		_ensure_remove_btn()
		queue_redraw()

	func _ensure_remove_btn() -> void:
		# 已占用 → 显示底部"移除"按钮
		if _trap != null and _remove_btn == null:
			_remove_btn = Button.new()
			_remove_btn.text = "移除"
			_remove_btn.add_theme_font_size_override("font_size", 12)
			_remove_btn.custom_minimum_size = Vector2(60, 24)
			_remove_btn.position = Vector2(45, 186)
			_remove_btn.pressed.connect(func(): remove_requested.emit(_index))
			add_child(_remove_btn)
		elif _trap == null and _remove_btn != null:
			_remove_btn.queue_free()
			_remove_btn = null

	func _process(delta: float) -> void:
		if _is_highlight:
			_scan_time += delta
			queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				if _trap == null and _is_highlight:
					slot_clicked.emit(_index)
					get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion:
			var hovered: bool = Rect2(Vector2.ZERO, size).has_point(event.position)
			if hovered != _is_hovered:
				_is_hovered = hovered
				queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		var rect := Rect2(Vector2.ZERO, Vector2(w, h))

		# 1) 剪影背景（更暗的槽位色调）
		var bg := Color(0.04, 0.06, 0.08, 0.85)
		draw_rect(rect, bg, true)

		# 2) 触发类型水印图腾（中心，20% alpha 的槽位色）
		var totem := _slot_color
		totem.a = 0.2
		_draw_slot_totem(w / 2.0, h / 2.0 + 20.0, totem)

		# 3) 顶部标题条
		draw_rect(Rect2(0, 0, w, TITLE_H), _slot_color * Color(1, 1, 1, 0.25), true)
		draw_string(
			ThemeDB.fallback_font,
			Vector2(8, 20),
			_title,
			HORIZONTAL_ALIGNMENT_LEFT,
			w - 16,
			14,
			_slot_color,
		)

		# 4) 边框
		if _trap != null:
			# 已占用：实线边框 + 陷阱名
			var border: Color = _slot_color
			draw_rect(rect, border, false, 2.0)
			draw_string(
				ThemeDB.fallback_font,
				Vector2(8, h / 2.0 - 6),
				_trap.trap_name if not _trap.is_bluff else "???",
				HORIZONTAL_ALIGNMENT_CENTER,
				w - 16,
				16,
				Color(1.0, 0.85, 0.2) if not _trap.is_bluff else Color(0.6, 0.8, 0.9),
			)
		else:
			# 空槽：虚线边框
			var dash_color: Color = _slot_color * (1.0 if _is_highlight else 0.4)
			dash_color.a = 0.9
			_draw_dashed_rect(rect, dash_color, 2.0)

			# 空槽提示文字
			if _is_highlight:
				draw_string(
					ThemeDB.fallback_font,
					Vector2(0, h / 2.0 - 6),
					"▶ 放置到此",
					HORIZONTAL_ALIGNMENT_CENTER,
					w,
					16,
					Color(1.0, 1.0, 0.4, 0.95),
				)
			else:
				draw_string(
					ThemeDB.fallback_font,
					Vector2(0, h / 2.0 - 6),
					"[ 空 ]",
					HORIZONTAL_ALIGNMENT_CENTER,
					w,
					14,
					Color(0.4, 0.4, 0.4),
				)

			# 5) 扫描线（高亮时 1.5s 上下循环）
			if _is_highlight:
				var cycle: float = fmod(_scan_time, 1.5) / 1.5
				var y: float = TITLE_H + cycle * (h - TITLE_H - 30.0)
				var scan_color: Color = _slot_color
				scan_color.a = 0.7
				draw_rect(Rect2(6, y, w - 12, 2.0), scan_color, true)

	func _draw_slot_totem(cx: float, cy: float, col: Color) -> void:
		match _slot_type:
			TrapData.TrapSlot.ATTACK:
				# 剑
				draw_line(Vector2(cx, cy - 40), Vector2(cx, cy + 40), col, 4.0)
				draw_line(Vector2(cx - 16, cy - 28), Vector2(cx + 16, cy - 28), col, 4.0)
			TrapData.TrapSlot.SKILL:
				# 齿轮
				var pts: PackedVector2Array = PackedVector2Array()
				for i in range(16):
					var ang: float = float(i) * TAU / 16.0
					var r: float = 36.0 if i % 2 == 0 else 28.0
					pts.append(Vector2(cx + cos(ang) * r, cy + sin(ang) * r))
				for i in range(pts.size()):
					draw_line(pts[i], pts[(i + 1) % pts.size()], col, 2.0)
				draw_arc(Vector2(cx, cy), 16.0, 0.0, TAU, 32, col, 2.0)
			TrapData.TrapSlot.HIGH_COST:
				# 闪电
				var bolt := PackedVector2Array([
					Vector2(cx + 10, cy - 36),
					Vector2(cx - 14, cy - 4),
					Vector2(cx + 4, cy),
					Vector2(cx - 10, cy + 36),
				])
				for i in range(bolt.size() - 1):
					draw_line(bolt[i], bolt[i + 1], col, 4.0)

	func _draw_dashed_rect(rect: Rect2, color: Color, width: float) -> void:
		# 顶 / 底
		_draw_dashed_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.end.x, rect.position.y), color, width)
		_draw_dashed_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.end.y), color, width)
		# 左 / 右
		_draw_dashed_line(Vector2(rect.position.x, rect.position.y), Vector2(rect.position.x, rect.end.y), color, width)
		_draw_dashed_line(Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.end.y), color, width)

	func _draw_dashed_line(from_p: Vector2, to_p: Vector2, color: Color, width: float) -> void:
		var diff: Vector2 = to_p - from_p
		var total: float = diff.length()
		if total <= 0.0:
			return
		var dir: Vector2 = diff / total
		var step: float = DASH_LEN + DASH_GAP
		var traveled: float = 0.0
		while traveled < total:
			var seg_end: float = min(traveled + DASH_LEN, total)
			draw_line(from_p + dir * traveled, from_p + dir * seg_end, color, width)
			traveled += step
