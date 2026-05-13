class_name ConstraintCardUI
extends BaseCardUI
## 约束令卡片 UI —— 紫色◆标识，属于"规则/布局牌"家族
##
## 视觉规范（由 art-director 定义）：
##   accent: Color(0.7, 0.3, 1.0)  紫色
##   顶部标记条文本: "保留 ◆N"
##   底部注记: "持续 N 回合" 或 "即时"

signal constraint_clicked(constraint: ConstraintData)

const CONSTRAINT_COLOR := Color(0.7, 0.3, 1.0, 1.0)

var constraint_data: ConstraintData
var is_usable: bool = true


func setup(data: ConstraintData, usable: bool) -> void:
	constraint_data = data
	is_usable = usable
	setup_base()


# ------------------------------------------------------------------
# BaseCardUI 抽象方法实现
# ------------------------------------------------------------------
func get_accent_color() -> Color:
	return CONSTRAINT_COLOR


func _is_card_usable() -> bool:
	return is_usable


func _draw_card_front(_rect: Rect2, accent: Color) -> void:
	if constraint_data == null:
		return

	# 顶部"保留 ◆N"标记条
	draw_top_bar(accent, "保留 ◆%d" % constraint_data.resource_cost)

	# 卡名
	var name_color: Color = Color.WHITE if is_usable else DISABLED_COLOR
	draw_card_name(constraint_data.constraint_name, name_color)

	# 分隔线
	draw_separator(accent)

	# 效果描述（自动换行）
	var desc_color: Color = Color(0.75, 0.7, 0.9) if is_usable else DISABLED_COLOR
	var lines: Array[String] = wrap_text(constraint_data.description, 12)
	draw_description(lines, desc_color)

	# 底部持续回合
	if constraint_data.duration > 0:
		draw_footer("持续 %d 回合" % constraint_data.duration, accent * 0.8)
	elif constraint_data.duration == 0:
		draw_footer("即时", accent * 0.8)


# ------------------------------------------------------------------
# 输入处理（约束令卡片独立响应点击）
# ------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if not _position_stored:
		return
	if not is_visible_in_tree():
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_hovered() and is_usable:
				constraint_clicked.emit(constraint_data)
				get_viewport().set_input_as_handled()
