extends Control
## 认知探针面板 UI — 显示Boss预判 + 洞察进度 + 效果提示
## v0.4.3 扩展：洞察"宣告动画"层 — peek/disrupt/seize 三种戏剧化演出
##
## 调用契约（由 BlindClashScene 注入 fx_parent / boss_world_pos）：
##   await play_peek_announcement(card_ui, boss_world_pos)        → 1.2s
##   await play_disrupt_announcement(card_ui, boss_world_pos)     → 1.5s
##   await play_seize_announcement(card_ui, boss_world_pos)       → 2.0s
## 完成时 emit announcement_finished(effect_type, card_id)。

signal probe_display_complete()
signal announcement_finished(effect_type: String, card_id: String)

var _current_prediction: String = ""
var _consecutive_hits: int = 0
var _total_hits: int = 0
var _is_jammed: bool = false
# v0.4.3：宣告动画层（外部注入，通常是 FxLayer）
var _fx_parent: Control = null

const TYPE_DISPLAY := {
	"attack": {"text": "攻击", "color": Color(0.9, 0.2, 0.2)},
	"defense": {"text": "防御", "color": Color(0.2, 0.7, 0.9)},
	"skill": {"text": "技能", "color": Color(0.2, 0.9, 0.4)},
}

# v0.4.3 三色三形语言（与 docs/design/ux/insight-fx-plan.md 一致）
const PEEK_COLOR := Color(0.0, 0.9, 1.0, 1.0)
const DISRUPT_COLOR := Color(1.0, 0.16, 0.16, 1.0)
const SEIZE_COLOR := Color(0.55, 0.0, 0.85, 1.0)  # 紫边
const SEIZE_BG := Color(0.05, 0.0, 0.12, 1.0)     # 黑紫底

@onready var prediction_label: RichTextLabel = $VBox/PredictionPanel/PredText
@onready var insight_bar: Control = $VBox/InsightBar
@onready var streak_label: Label = $VBox/InsightBar/StreakLabel
@onready var total_label: Label = $VBox/InsightBar/TotalLabel
@onready var status_label: Label = $VBox/StatusLabel


func _ready() -> void:
	visible = false


func show_prediction(predicted_type: String) -> void:
	_current_prediction = predicted_type
	_is_jammed = false
	visible = true

	var type_info: Dictionary = TYPE_DISPLAY.get(predicted_type, {"text": "???", "color": Color.WHITE})
	prediction_label.clear()
	prediction_label.push_color(Color(0.7, 0.7, 0.7))
	prediction_label.add_text("[认知探针] Boss预判你主打：")
	prediction_label.push_color(type_info["color"])
	prediction_label.push_bold()
	prediction_label.add_text(type_info["text"])
	prediction_label.pop()
	prediction_label.pop()

	_update_insight_display()


func show_jammed() -> void:
	_is_jammed = true
	status_label.text = "⚡ 探针已被干扰"
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))


func show_result(correct: bool, streak: int, total: int) -> void:
	_consecutive_hits = streak
	_total_hits = total

	if _is_jammed:
		status_label.text = "探针干扰成功 — 本回合判定无效"
		status_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
	elif correct:
		status_label.text = "✓ Boss猜对了！连续 %d 次 | 累计 %d 次" % [streak, total]
		status_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	else:
		status_label.text = "✗ Boss猜错了 — 连续归零"
		status_label.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))

	_update_insight_display()

	# 延迟后隐藏
	await get_tree().create_timer(2.5).timeout
	visible = false
	probe_display_complete.emit()


func show_insight_effect(effect_type: String, card: CardData) -> void:
	var effect_text: String = ""
	var effect_color: Color = Color.WHITE

	match effect_type:
		"peek":
			effect_text = "⚠ Boss窥视了你的手牌: %s" % card.card_name
			effect_color = Color(1.0, 0.7, 0.2)
		"disrupt":
			effect_text = "⚠⚠ Boss干扰了你: %s 下回合不可用" % card.card_name
			effect_color = Color(1.0, 0.4, 0.2)
		"seize":
			effect_text = "⚠⚠⚠ Boss夺取了: %s！永久失去" % card.card_name
			effect_color = Color(1.0, 0.1, 0.1)

	status_label.text = effect_text
	status_label.add_theme_color_override("font_color", effect_color)


func _update_insight_display() -> void:
	streak_label.text = "连续: %d" % _consecutive_hits
	total_label.text = "累计: %d/5" % _total_hits

	# 颜色预警
	if _consecutive_hits >= 2:
		streak_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	elif _consecutive_hits >= 1:
		streak_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	else:
		streak_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

	if _total_hits >= 4:
		total_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	else:
		total_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))


# ============================================================
# v0.4.3 洞察宣告动画层
# ============================================================

## 由 BlindClashScene 注入：宣告动画的父容器（建议 FxLayer 顶层 Control）
func set_fx_parent(parent: Control) -> void:
	_fx_parent = parent


## 通用：构造一个临时 Control 作为单次动画载体，挂在 _fx_parent 上，结束后 queue_free
func _spawn_fx_node() -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.z_index = 100
	if _fx_parent != null:
		_fx_parent.add_child(c)
	else:
		# fallback：挂到 Viewport 根（避免 null）
		get_tree().current_scene.add_child(c)
	return c


## 1.2s：peek 宣告 — 青色扫描线 + 卡四角取景框
func play_peek_announcement(target_card_ui: Node, boss_world_pos: Vector2) -> float:
	if target_card_ui == null:
		return 0.0
	var card_center: Vector2 = _get_card_center(target_card_ui)
	var fx := _spawn_fx_node()
	var painter := PeekFxPainter.new()
	painter.from_pos = boss_world_pos
	painter.to_pos = card_center
	painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(painter)
	painter.queue_redraw()
	# 阶段 1：扫描线推进 0~1（1.0s）
	var t := create_tween()
	t.tween_method(func(v: float): painter.scan_progress = v; painter.queue_redraw(), 0.0, 1.0, 1.0)
	# 阶段 2：取景框收紧/呼吸（0.4s）
	t.tween_method(func(v: float): painter.frame_progress = v; painter.queue_redraw(), 0.0, 1.0, 0.4)
	# 收尾淡出（0.2s 与上一段重叠通过 modulate）
	t.parallel().tween_property(fx, "modulate:a", 0.0, 0.4)
	t.tween_callback(func() -> void:
		fx.queue_free()
		var cid: String = ""
		if target_card_ui != null and target_card_ui.has_method("get") and target_card_ui.get("card_data") != null:
			cid = String(target_card_ui.card_data.id)
		announcement_finished.emit("peek", cid)
	)
	return 1.4


## 1.5s：disrupt 宣告 — 双侧锁链扑向卡 + 红 × 封印 + 屏幕轻震
func play_disrupt_announcement(target_card_ui: Node, boss_world_pos: Vector2) -> float:
	if target_card_ui == null:
		return 0.0
	var card_center: Vector2 = _get_card_center(target_card_ui)
	var fx := _spawn_fx_node()
	var painter := DisruptFxPainter.new()
	painter.from_pos = boss_world_pos
	painter.to_pos = card_center
	painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(painter)
	# 阶段 1：锁链推进 0~1（0.5s）
	var t := create_tween()
	t.tween_method(func(v: float): painter.chain_progress = v; painter.queue_redraw(), 0.0, 1.0, 0.5)
	# 阶段 2：电路冻结闪烁 + 红 × 砸下（0.5s）
	t.tween_method(func(v: float): painter.seal_progress = v; painter.queue_redraw(), 0.0, 1.0, 0.5)
	# 阶段 3：定格收紧（0.3s），淡出 0.2s
	t.tween_interval(0.3)
	t.parallel().tween_property(fx, "modulate:a", 0.0, 0.5)
	t.tween_callback(func() -> void:
		fx.queue_free()
		var cid: String = ""
		if target_card_ui != null and target_card_ui.has_method("get") and target_card_ui.get("card_data") != null:
			cid = String(target_card_ui.card_data.id)
		announcement_finished.emit("disrupt", cid)
	)
	return 1.5


## 2.0s：seize 宣告 — 黑紫裂缝 + 卡片碎裂吸入 + 屏幕色差
func play_seize_announcement(target_card_ui: Node, boss_world_pos: Vector2) -> float:
	if target_card_ui == null:
		return 0.0
	var card_center: Vector2 = _get_card_center(target_card_ui)
	var fx := _spawn_fx_node()
	var painter := SeizeFxPainter.new()
	painter.from_pos = card_center
	painter.to_pos = boss_world_pos
	painter.set_anchors_preset(Control.PRESET_FULL_RECT)
	painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(painter)
	# 同步触发卡牌自身销毁动画（如果支持）
	if target_card_ui != null and target_card_ui.has_method("play_seize_destruction"):
		target_card_ui.play_seize_destruction()
	# 阶段 1：裂缝撕开（0.4s）
	var t := create_tween()
	t.tween_method(func(v: float): painter.crack_progress = v; painter.queue_redraw(), 0.0, 1.0, 0.4)
	# 阶段 2：碎片吸入 + 屏幕色差（0.6s）
	t.tween_method(func(v: float): painter.suck_progress = v; painter.queue_redraw(), 0.0, 1.0, 0.6)
	# 阶段 3：碎片到达 boss（0.5s）+ 余波淡出（0.5s）
	t.tween_method(func(v: float): painter.arrive_progress = v; painter.queue_redraw(), 0.0, 1.0, 0.5)
	t.parallel().tween_property(fx, "modulate:a", 0.0, 0.7)
	t.tween_callback(func() -> void:
		fx.queue_free()
		var cid: String = ""
		if target_card_ui != null and target_card_ui.has_method("get") and target_card_ui.get("card_data") != null:
			cid = String(target_card_ui.card_data.id)
		announcement_finished.emit("seize", cid)
	)
	return 2.0


func _get_card_center(node: Node) -> Vector2:
	if node == null:
		return Vector2.ZERO
	if node.has_method("get_global_center"):
		return node.get_global_center()
	if node is Control:
		var ctrl: Control = node
		return ctrl.global_position + ctrl.size / 2.0
	return Vector2.ZERO


# ============================================================
# v0.4.3 宣告动画 painter 内部类（用 inner class 减少新增文件）
# ============================================================

class PeekFxPainter extends Control:
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO
	var scan_progress: float = 0.0   # 0=从 boss 出发, 1=触达卡牌
	var frame_progress: float = 0.0  # 0=取景框收紧前, 1=完全锁定

	func _draw() -> void:
		if scan_progress > 0.0 and scan_progress < 1.0:
			var cur_pos: Vector2 = from_pos.lerp(to_pos, scan_progress)
			var beam_color := Color(0.0, 0.9, 1.0, 0.85)
			# 主光束（细线，前段更亮）
			draw_line(from_pos, cur_pos, beam_color, 4.0)
			var glow := Color(0.0, 0.9, 1.0, 0.35)
			draw_line(from_pos, cur_pos, glow, 12.0)
			# 头部小光团
			draw_circle(cur_pos, 8.0, beam_color)
		# 取景框（四角 L 形）
		if scan_progress >= 0.95 or frame_progress > 0.0:
			var frame_size: float = lerp(140.0, 95.0, frame_progress)
			var corner_len: float = 32.0
			var alpha: float = 0.4 + 0.6 * sin(frame_progress * PI)
			var c := Color(0.0, 0.9, 1.0, alpha)
			var tl: Vector2 = to_pos + Vector2(-frame_size * 0.5, -frame_size * 0.7)
			var tr: Vector2 = to_pos + Vector2(frame_size * 0.5, -frame_size * 0.7)
			var bl: Vector2 = to_pos + Vector2(-frame_size * 0.5, frame_size * 0.7)
			var br: Vector2 = to_pos + Vector2(frame_size * 0.5, frame_size * 0.7)
			# 左上角
			draw_line(tl, tl + Vector2(corner_len, 0), c, 3.0)
			draw_line(tl, tl + Vector2(0, corner_len), c, 3.0)
			# 右上角
			draw_line(tr, tr + Vector2(-corner_len, 0), c, 3.0)
			draw_line(tr, tr + Vector2(0, corner_len), c, 3.0)
			# 左下角
			draw_line(bl, bl + Vector2(corner_len, 0), c, 3.0)
			draw_line(bl, bl + Vector2(0, -corner_len), c, 3.0)
			# 右下角
			draw_line(br, br + Vector2(-corner_len, 0), c, 3.0)
			draw_line(br, br + Vector2(0, -corner_len), c, 3.0)


class DisruptFxPainter extends Control:
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO
	var chain_progress: float = 0.0  # 锁链扑向目标 0~1
	var seal_progress: float = 0.0   # × 封印砸下 0~1

	func _draw() -> void:
		# 双侧锁链（弧线，从 from 两侧出发）
		if chain_progress > 0.0:
			var chain_color := Color(1.0, 0.16, 0.16, 0.92)
			var p_left: Vector2 = from_pos + Vector2(-80, 0)
			var p_right: Vector2 = from_pos + Vector2(80, 0)
			# 用二次贝塞尔模拟弧线
			_draw_chain_arc(p_left, to_pos, Vector2(p_left.x - 60, (p_left.y + to_pos.y) * 0.5), chain_progress, chain_color)
			_draw_chain_arc(p_right, to_pos, Vector2(p_right.x + 60, (p_right.y + to_pos.y) * 0.5), chain_progress, chain_color)
		# 红色 × 封印（从远到近砸下）
		if seal_progress > 0.0:
			var seal_size: float = lerp(180.0, 90.0, seal_progress)
			var seal_color := Color(1.0, 0.16, 0.16, 0.6 + 0.4 * seal_progress)
			# 红圆背景
			draw_circle(to_pos, seal_size * 0.55, Color(0.06, 0.04, 0.1, 0.85))
			draw_arc(to_pos, seal_size * 0.55, 0.0, TAU, 48, seal_color, 4.0)
			# × 笔画
			var arm: float = seal_size * 0.32
			draw_line(to_pos + Vector2(-arm, -arm), to_pos + Vector2(arm, arm), seal_color, 7.0)
			draw_line(to_pos + Vector2(-arm, arm), to_pos + Vector2(arm, -arm), seal_color, 7.0)

	func _draw_chain_arc(p0: Vector2, p1: Vector2, ctrl: Vector2, t: float, col: Color) -> void:
		# 沿 t 方向逐步绘制贝塞尔曲线段（粗线 + 链节）
		var seg: int = 24
		var prev: Vector2 = p0
		for i in range(1, seg + 1):
			var u: float = float(i) / float(seg)
			if u > t:
				break
			var pt: Vector2 = _bezier(p0, ctrl, p1, u)
			draw_line(prev, pt, col, 6.0)
			# 链节
			if i % 4 == 0:
				draw_circle(pt, 6.0, Color(0.06, 0.04, 0.1, 1.0))
				draw_arc(pt, 6.0, 0.0, TAU, 16, col, 2.0)
			prev = pt

	func _bezier(p0: Vector2, c: Vector2, p1: Vector2, t: float) -> Vector2:
		var q0: Vector2 = p0.lerp(c, t)
		var q1: Vector2 = c.lerp(p1, t)
		return q0.lerp(q1, t)


class SeizeFxPainter extends Control:
	var from_pos: Vector2 = Vector2.ZERO  # 卡牌位置（裂缝出现处）
	var to_pos: Vector2 = Vector2.ZERO    # boss 位置（碎片飞向处）
	var crack_progress: float = 0.0       # 裂缝撕开 0~1
	var suck_progress: float = 0.0        # 碎片飞行 0~1
	var arrive_progress: float = 0.0      # 到达 boss 余波 0~1

	# 碎片缓存（在 _draw 时按 crack_progress 生成 1 次）
	var _shards: Array = []

	func _draw() -> void:
		# 1) 裂缝（从 from 中线向上下撕开）
		if crack_progress > 0.0 and suck_progress < 0.5:
			var crack_h: float = 220.0 * crack_progress
			var crack_color := Color(0.55, 0.0, 0.85, 0.85)
			var bg_color := Color(0.05, 0.0, 0.12, 0.95 * (1.0 - max(0.0, suck_progress * 2.0 - 1.0)))
			# 黑紫底裂缝（菱形）
			var pts := PackedVector2Array([
				from_pos + Vector2(0, -crack_h * 0.5),
				from_pos + Vector2(20, 0),
				from_pos + Vector2(0, crack_h * 0.5),
				from_pos + Vector2(-20, 0),
			])
			draw_colored_polygon(pts, bg_color)
			# 边缘紫光
			for i in range(pts.size()):
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % pts.size()]
				draw_line(a, b, crack_color, 2.5)
		# 2) 碎片吸入（从卡 飞向 boss，碎片大小衰减）
		if suck_progress > 0.0:
			if _shards.is_empty():
				_generate_shards()
			for s in _shards:
				var pt: Vector2 = (from_pos + s["offset"]).lerp(to_pos, suck_progress)
				var sz: float = lerp(s["size"], 2.0, suck_progress)
				var ang: float = s["angle"] + suck_progress * s["spin"]
				var color := Color(0.95, 0.2, 0.25, 0.9 * (1.0 - suck_progress * 0.6))
				_draw_shard(pt, sz, ang, color)
		# 3) 到达余波（boss 处红色光环）
		if arrive_progress > 0.0:
			var ring := Color(1.0, 0.2, 0.3, 0.8 * (1.0 - arrive_progress))
			draw_arc(to_pos, 20.0 + arrive_progress * 60.0, 0.0, TAU, 48, ring, 4.0)

	func _generate_shards() -> void:
		_shards.clear()
		for i in range(10):
			_shards.append({
				"offset": Vector2(randf_range(-60, 60), randf_range(-90, 90)),
				"size": randf_range(8.0, 18.0),
				"angle": randf() * TAU,
				"spin": randf_range(-3.0, 3.0),
			})

	func _draw_shard(center: Vector2, sz: float, angle: float, col: Color) -> void:
		var pts := PackedVector2Array()
		var n: int = 5  # 不规则五边形碎片
		for i in range(n):
			var a: float = angle + float(i) * TAU / float(n)
			var r: float = sz * (0.7 + 0.5 * randf())
			pts.append(center + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, col)
