extends PanelContainer
## 战斗者信息面板 — HP条/护甲条/能量条

@export var combatant_name: String = ""
@export var is_boss: bool = false

var _max_hp: int = 0
var _current_hp: int = 0
var _displayed_hp: float = 0.0  # 平滑动画用
var _armor: int = 0
var _energy: int = 0
var _max_energy: int = 6  # v0.7.x-rebal：base_energy=6（之前默认 3 已过时，导致 Boss UI 显示 3 格）
var _hand_count: int = -1  # -1 = 不显示徽章；用于 Boss 手牌张数（B 浮层 HAND 区，GDD 04:78 暗出张数公开衍生）

var _hp_shake_offset: float = 0.0
var _hp_flash_time: float = 0.0

const HP_COLOR := Color(0.9, 0.2, 0.25)
const HP_BG_COLOR := Color(0.15, 0.05, 0.06)
const ARMOR_COLOR := Color(0.5, 0.75, 0.9)
const ARMOR_BG_COLOR := Color(0.08, 0.12, 0.18)
const ENERGY_COLOR := Color(1.0, 0.85, 0.2)
const ENERGY_BG_COLOR := Color(0.18, 0.15, 0.05)


func _ready() -> void:
	custom_minimum_size = Vector2(320, 240)
	set_process(true)


func setup(p_name: String, max_hp: int, boss: bool = false) -> void:
	combatant_name = p_name
	is_boss = boss
	_max_hp = max_hp
	_current_hp = max_hp
	_displayed_hp = float(max_hp)
	queue_redraw()


func set_hp(new_hp: int, max_hp: int) -> void:
	if new_hp < _current_hp:
		# 受伤震动+闪光
		_hp_shake_offset = 8.0
		_hp_flash_time = 0.3
	_current_hp = new_hp
	_max_hp = max_hp
	queue_redraw()


func set_armor(armor: int) -> void:
	_armor = armor
	queue_redraw()


func set_energy(energy: int) -> void:
	_energy = energy
	if energy > _max_energy:
		_max_energy = energy
	queue_redraw()


## 显式设置最大能量（格数）—— 用于回合开始重置时恢复正确格数
func set_max_energy(max_energy: int) -> void:
	_max_energy = max(max_energy, 1)
	queue_redraw()


## 设置手牌张数徽章（Boss 专用，is_boss=false 时不显示）
## 传 -1 隐藏徽章
func set_hand_count(count: int) -> void:
	_hand_count = count
	queue_redraw()


func _process(delta: float) -> void:
	# HP 条平滑追赶
	if abs(_displayed_hp - float(_current_hp)) > 0.1:
		_displayed_hp = lerp(_displayed_hp, float(_current_hp), 5.0 * delta)
		queue_redraw()
	elif _displayed_hp != float(_current_hp):
		_displayed_hp = float(_current_hp)
		queue_redraw()

	# 震动衰减
	if _hp_shake_offset > 0.01:
		_hp_shake_offset = lerp(_hp_shake_offset, 0.0, 8.0 * delta)
		queue_redraw()

	# 闪光衰减
	if _hp_flash_time > 0.0:
		_hp_flash_time = maxf(_hp_flash_time - delta, 0.0)
		queue_redraw()


func _draw() -> void:
	var w: float = size.x - 24.0
	var start_x: float = 12.0
	var y: float = 12.0

	# 名字
	var name_prefix: String = "◆ " if is_boss else "◇ "
	draw_string(ThemeDB.fallback_font, Vector2(start_x, y + 22), name_prefix + combatant_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)

	# 手牌张数徽章（Boss 专用 / B 浮层 HAND 区）
	# 视觉：右上角 "🂠 N" 青蓝胶囊，仅显示张数不显示内容
	if is_boss and _hand_count >= 0:
		_draw_hand_count_badge(start_x, y, w)

	y += 40.0

	# HP 条
	var hp_shake_x: float = randf_range(-_hp_shake_offset, _hp_shake_offset)
	var hp_bar_rect := Rect2(start_x + hp_shake_x, y, w, 28)
	draw_rect(hp_bar_rect, HP_BG_COLOR, true)
	var hp_ratio: float = clampf(_displayed_hp / maxf(float(_max_hp), 1.0), 0.0, 1.0)
	var hp_fill_rect := Rect2(start_x + hp_shake_x, y, w * hp_ratio, 28)
	var hp_color := HP_COLOR
	if _hp_flash_time > 0.0:
		hp_color = HP_COLOR.lerp(Color.WHITE, _hp_flash_time / 0.3)
	draw_rect(hp_fill_rect, hp_color, true)
	draw_rect(hp_bar_rect, Color(0.4, 0.2, 0.25), false, 2.0)
	# HP 文字
	var hp_text: String = "HP  %d / %d" % [_current_hp, _max_hp]
	draw_string(ThemeDB.fallback_font, Vector2(start_x + 10 + hp_shake_x, y + 20), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1.0, 0.95, 0.95))
	y += 40.0

	# 护甲条
	var armor_bar_rect := Rect2(start_x, y, w, 22)
	draw_rect(armor_bar_rect, ARMOR_BG_COLOR, true)
	if _armor > 0:
		# 护甲无上限，显示为段落式
		var armor_display_max: int = maxi(_armor, 10)
		var armor_ratio: float = clampf(float(_armor) / float(armor_display_max), 0.0, 1.0)
		var armor_fill_rect := Rect2(start_x, y, w * armor_ratio, 22)
		draw_rect(armor_fill_rect, ARMOR_COLOR, true)
	draw_rect(armor_bar_rect, Color(0.3, 0.4, 0.5), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(start_x + 10, y + 16), "护甲  %d" % _armor, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.9, 0.95))
	y += 32.0

	# 能量条（分段显示，类似能量水晶）
	draw_string(ThemeDB.fallback_font, Vector2(start_x, y + 18), "能量", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.85, 0.6))
	var crystal_size: float = 22.0
	var crystal_spacing: float = 6.0
	var crystal_start_x: float = start_x + 70.0
	for i in range(_max_energy):
		var cx: float = crystal_start_x + i * (crystal_size + crystal_spacing)
		var crystal_rect := Rect2(cx, y + 2, crystal_size, crystal_size)
		if i < _energy:
			draw_rect(crystal_rect, ENERGY_COLOR, true)
			draw_rect(crystal_rect, Color(1.0, 1.0, 0.6), false, 1.5)
		else:
			draw_rect(crystal_rect, ENERGY_BG_COLOR, true)
			draw_rect(crystal_rect, Color(0.3, 0.25, 0.1), false, 1.5)


## 手牌张数徽章 — Boss 专用（B 浮层 HAND 区）
## 位置：面板右上角，与名字同一行
## 视觉：青蓝胶囊背景 + "🂠 N"
func _draw_hand_count_badge(start_x: float, y: float, w: float) -> void:
	const BADGE_BG := Color(0.12, 0.35, 0.42, 0.85)
	const BADGE_BORDER := Color(0.2, 0.85, 0.95, 1.0)
	const BADGE_TEXT := Color(0.85, 0.97, 1.0, 1.0)
	var badge_w: float = 64.0
	var badge_h: float = 28.0
	var badge_x: float = start_x + w - badge_w
	var badge_y: float = y + 4.0
	var badge_rect := Rect2(badge_x, badge_y, badge_w, badge_h)
	# 背景胶囊（用矩形+圆角描边近似）
	draw_rect(badge_rect, BADGE_BG, true)
	draw_rect(badge_rect, BADGE_BORDER, false, 1.5)
	# 文字 "🂠 N"
	var text: String = "🂠 %d" % _hand_count
	draw_string(
		ThemeDB.fallback_font,
		Vector2(badge_x + 8.0, badge_y + 20.0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		badge_w - 16.0,
		15,
		BADGE_TEXT,
	)
