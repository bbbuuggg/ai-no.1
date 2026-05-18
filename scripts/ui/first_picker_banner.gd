class_name FirstPickerBanner
extends Control
## v0.7 BP 方案 B' — 先手宣告横幅（Epic-BP-3）
##
## 由 BlindClashBattle.bp_first_picker_decided 信号触发，
## v0.7.x-hotfix4 起总时长 2.0s：淡入(0.3s) → 停留(1.4s) → 淡出(0.3s)
## battle 端兜底 timer 同步设为 2.5s（保留 0.5s 缓冲）
##
## 视觉设计（vibe-lead 占位规格，UX 后续可调）：
##   - 屏幕顶部居中带状（宽 720，高 110，y=180 避开 BossPanel）
##   - 半透明黑底 + 边框（玩家=青蓝 / Boss=血红）
##   - 上行大字主文：「先手：你」/「先手：回响」
##   - 下行小字注释：「Slot 1 占位威慑 vs Slot 4 信息最全」
##   - 整体淡入淡出 + 顶部装饰线呼吸
##
## 调用：
##   await banner.play("player")  # 或 "boss"
##   → 2.0s 后自动 emit finished

signal finished()

const FRIENDLY := Color(0.3, 0.85, 1.0, 1.0)   # 青蓝（玩家先手）
const HOSTILE := Color(0.95, 0.2, 0.25, 1.0)   # 血红（Boss 先手）
const FADE_IN_SEC: float = 0.3
const HOLD_SEC: float = 1.4
const FADE_OUT_SEC: float = 0.3

var _panel: PanelContainer
var _title_label: Label
var _sub_label: Label
var _is_playing: bool = false


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE  # 不阻挡点击
	# 顶部居中（屏幕宽 1920，banner 宽 720）
	anchor_left = 0.5
	anchor_top = 0.0
	anchor_right = 0.5
	anchor_bottom = 0.0
	offset_left = -360.0
	offset_top = 180.0
	offset_right = 360.0
	offset_bottom = 290.0
	z_index = 80
	_build_ui()


func _build_ui() -> void:
	# 主面板（先建样式，play 时动态切换颜色）
	_panel = PanelContainer.new()
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)

	# 内部 VBox：上行大字 + 下行小字
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 42)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_title_label)

	_sub_label = Label.new()
	_sub_label.add_theme_font_size_override("font_size", 18)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sub_label.add_theme_color_override("font_color", Color(0.75, 0.78, 0.85, 1.0))
	_sub_label.text = "Slot 1 占位威慑　·　Slot 4 信息最全"
	vbox.add_child(_sub_label)


## 播放横幅演出（picker = "player" | "boss"）
## 整段时长固定 2.0s，await 此函数等结束
## v0.8.0-locked.1：可选传入 sub_text 覆盖默认副标题（用于显示"轮流先手 R2"等回合信息）
func play(picker: String, sub_text: String = "") -> void:
	if _is_playing:
		return
	_is_playing = true

	# 设置颜色 + 文案
	var accent: Color = FRIENDLY if picker == "player" else HOSTILE
	var title_text: String = "先手：你" if picker == "player" else "先手：回响"
	_title_label.text = title_text
	_title_label.add_theme_color_override("font_color", accent)
	# 副标题：若调用方传入则覆盖，否则用默认占位威慑提示
	if sub_text != "":
		_sub_label.text = sub_text
	else:
		_sub_label.text = "Slot 1 占位威慑　·　Slot 4 信息最全"
	_panel.add_theme_stylebox_override("panel", _make_banner_style(accent))

	# 起始状态：透明 + 略微下偏
	visible = true
	modulate.a = 0.0
	position.y = 180.0 + 12.0  # 比目标位置低 12px，淡入时上滑

	var t := create_tween()
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# 淡入 + 上滑
	t.tween_property(self, "modulate:a", 1.0, FADE_IN_SEC)
	t.parallel().tween_property(self, "position:y", 180.0, FADE_IN_SEC)
	# 停留
	t.tween_interval(HOLD_SEC)
	# 淡出 + 微缩
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	t.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC)

	await t.finished
	visible = false
	_is_playing = false
	finished.emit()


func _make_banner_style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.10, 0.92)
	sb.border_color = accent
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 14.0
	sb.content_margin_bottom = 14.0
	sb.shadow_color = accent * Color(1, 1, 1, 0.5)
	sb.shadow_size = 8
	return sb
