extends Control
## 陷阱部署 UI — 3个槽位 + 陷阱牌选择

signal deploy_confirmed()
signal probe_jammed()

var _trap_inventory: Array[TrapData] = []
var _constraint_resource: int = 0
var _slots: Array = [null, null, null]  # TrapData or null
var _is_active: bool = false

const SLOT_NAMES := ["攻击触发", "技能触发", "高费触发"]
const SLOT_COLORS := [
	Color(0.9, 0.2, 0.2, 0.8),  # 攻击 - 红
	Color(0.2, 0.9, 0.4, 0.8),  # 技能 - 绿
	Color(0.9, 0.75, 0.1, 0.8), # 高费 - 金
]

@onready var slots_container: HBoxContainer = $VBox/SlotsArea
@onready var traps_container: HBoxContainer = $VBox/TrapsArea
@onready var resource_label: Label = $VBox/InfoBar/ResourceLabel
@onready var jam_btn: Button = $VBox/InfoBar/JamBtn
@onready var confirm_btn: Button = $VBox/InfoBar/ConfirmBtn


func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	jam_btn.pressed.connect(_on_jam)


func activate(traps: Array[TrapData], resource: int) -> void:
	_trap_inventory = traps.duplicate()
	_constraint_resource = resource
	_slots = [null, null, null]
	_is_active = true
	visible = true
	_refresh_all()


func deactivate() -> void:
	_is_active = false
	visible = false


func get_deployed_slots() -> Array:
	return _slots.duplicate()


func _refresh_all() -> void:
	_refresh_slots()
	_refresh_traps()
	_update_info()


func _refresh_slots() -> void:
	for child in slots_container.get_children():
		child.queue_free()

	for i in range(3):
		var slot_panel := PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(180, 120)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		# 槽位标题
		var title := Label.new()
		title.text = SLOT_NAMES[i]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", SLOT_COLORS[i])
		vbox.add_child(title)

		# 槽位内容
		var content := Label.new()
		if _slots[i] != null:
			var trap: TrapData = _slots[i]
			content.text = trap.trap_name if not trap.is_bluff else "???"
			content.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2) if not trap.is_bluff else Color(0.6, 0.6, 0.6))
			# 添加移除按钮
			var remove_btn := Button.new()
			remove_btn.text = "移除"
			remove_btn.add_theme_font_size_override("font_size", 14)
			remove_btn.pressed.connect(_on_remove_slot.bind(i))
			vbox.add_child(remove_btn)
		else:
			content.text = "[ 空 ]"
			content.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_theme_font_size_override("font_size", 18)
		vbox.add_child(content)

		slot_panel.add_child(vbox)

		# 给空槽位设置边框样式
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.1, 0.14, 0.9)
		sb.border_color = SLOT_COLORS[i] * (0.8 if _slots[i] != null else 0.3)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		slot_panel.add_theme_stylebox_override("panel", sb)

		slots_container.add_child(slot_panel)


func _refresh_traps() -> void:
	for child in traps_container.get_children():
		child.queue_free()

	for trap in _trap_inventory:
		var vbox := VBoxContainer.new()
		vbox.custom_minimum_size = Vector2(200, 0)

		var btn := Button.new()
		var cost_text: String = "[消耗%d]" % trap.resource_cost if not trap.is_bluff else "[免费]"
		btn.text = "%s %s" % [trap.trap_name, cost_text]
		btn.add_theme_font_size_override("font_size", 16)
		# 能否使用的判断
		var can_use: bool = trap.is_bluff or trap.resource_cost <= _constraint_resource
		btn.disabled = not can_use
		btn.pressed.connect(_on_trap_selected.bind(trap))
		btn.tooltip_text = trap.description
		vbox.add_child(btn)

		# 效果描述标签（始终可见）
		var desc_label := Label.new()
		desc_label.text = trap.description
		desc_label.add_theme_font_size_override("font_size", 13)
		desc_label.add_theme_color_override("font_color", Color(0.7, 0.8, 0.9))
		desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		desc_label.custom_minimum_size = Vector2(200, 0)
		vbox.add_child(desc_label)

		traps_container.add_child(vbox)


var _pending_trap: TrapData = null  # 等待选择槽位的陷阱

func _on_trap_selected(trap: TrapData) -> void:
	if not _is_active:
		return
	# 进入"选择槽位"模式：高亮所有空槽位
	_pending_trap = trap
	_refresh_slots_for_selection()


func _deploy_to_slot(trap: TrapData, slot_index: int) -> void:
	if not trap.is_bluff:
		if trap.resource_cost > _constraint_resource:
			return
		_constraint_resource -= trap.resource_cost

	_slots[slot_index] = trap
	_trap_inventory.erase(trap)
	_pending_trap = null
	_refresh_all()


func _refresh_slots_for_selection() -> void:
	## 槽位进入"选择模式"：空槽位变为可点击按钮
	for child in slots_container.get_children():
		child.queue_free()

	for i in range(3):
		var slot_panel := PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(180, 120)

		var vbox := VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER

		var title := Label.new()
		title.text = SLOT_NAMES[i]
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 16)
		title.add_theme_color_override("font_color", SLOT_COLORS[i])
		vbox.add_child(title)

		if _slots[i] != null:
			# 已占用
			var content := Label.new()
			content.text = _slots[i].trap_name
			content.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			content.add_theme_font_size_override("font_size", 16)
			content.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			vbox.add_child(content)
		else:
			# 空槽 → 变成"放置到此"按钮
			var place_btn := Button.new()
			place_btn.text = "▶ 放置到此"
			place_btn.add_theme_font_size_override("font_size", 16)
			place_btn.pressed.connect(_on_slot_chosen.bind(i))
			vbox.add_child(place_btn)

		slot_panel.add_child(vbox)

		# 高亮空槽位
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.08, 0.1, 0.14, 0.9)
		if _slots[i] == null:
			sb.border_color = Color(1.0, 1.0, 0.3, 0.9)  # 高亮黄色
		else:
			sb.border_color = SLOT_COLORS[i] * 0.4
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(8)
		slot_panel.add_theme_stylebox_override("panel", sb)

		slots_container.add_child(slot_panel)


func _on_slot_chosen(slot_index: int) -> void:
	if _pending_trap == null:
		return
	_deploy_to_slot(_pending_trap, slot_index)


func _on_remove_slot(slot_index: int) -> void:
	if _slots[slot_index] == null:
		return
	var trap: TrapData = _slots[slot_index]
	# 退回资源和库存
	if not trap.is_bluff:
		_constraint_resource += trap.resource_cost
	_trap_inventory.append(trap)
	_slots[slot_index] = null
	_refresh_all()


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
