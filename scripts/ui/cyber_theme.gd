extends Control
## 赛博朋克 UI 主题初始化 — 运行时设置暗色风格

const BG_COLOR := Color(0.05, 0.06, 0.09, 0.85)
const PANEL_COLOR := Color(0.08, 0.1, 0.14, 0.9)
const BORDER_COLOR := Color(0.0, 0.7, 0.9, 0.6)
const TEXT_COLOR := Color(0.85, 0.9, 0.95, 1.0)
const ACCENT_CYAN := Color(0.0, 0.85, 1.0, 1.0)
const ACCENT_ORANGE := Color(1.0, 0.5, 0.1, 1.0)
const ACCENT_RED := Color(1.0, 0.2, 0.2, 1.0)
const ACCENT_GREEN := Color(0.2, 1.0, 0.5, 1.0)
const BUTTON_BG := Color(0.1, 0.12, 0.18, 0.95)
const BUTTON_HOVER := Color(0.15, 0.2, 0.3, 0.95)
const BUTTON_PRESSED := Color(0.0, 0.5, 0.7, 0.95)


static func create_panel_stylebox() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	return sb


static func create_button_normal() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BUTTON_BG
	sb.border_color = ACCENT_CYAN * 0.5
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


static func create_button_hover() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BUTTON_HOVER
	sb.border_color = ACCENT_CYAN
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


static func create_button_pressed() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BUTTON_PRESSED
	sb.border_color = ACCENT_CYAN
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(6)
	return sb


static func apply_theme_to_tree(root: Control) -> void:
	## 递归给所有 Control 节点应用赛博主题
	_apply_to_node(root)
	for child in root.get_children():
		if child is Control:
			apply_theme_to_tree(child)


static func _apply_to_node(node: Control) -> void:
	if node is PanelContainer:
		node.add_theme_stylebox_override("panel", create_panel_stylebox())
	elif node is Button:
		node.add_theme_stylebox_override("normal", create_button_normal())
		node.add_theme_stylebox_override("hover", create_button_hover())
		node.add_theme_stylebox_override("pressed", create_button_pressed())
		node.add_theme_color_override("font_color", TEXT_COLOR)
		node.add_theme_color_override("font_hover_color", ACCENT_CYAN)
		node.add_theme_font_size_override("font_size", 18)
	elif node is Label:
		node.add_theme_color_override("font_color", TEXT_COLOR)
		node.add_theme_font_size_override("font_size", 18)
	elif node is RichTextLabel:
		node.add_theme_color_override("default_color", TEXT_COLOR)
		node.add_theme_font_size_override("normal_font_size", 18)
