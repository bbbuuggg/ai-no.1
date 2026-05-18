class_name PickSelectUI
extends Control
## v0.7 Epic-BP-6：明牌 BP 选牌 UI（pick_select_ui）
##
## 取代旧 BlindSelectUI（暗出 4 张），实现 GDD-07 §6.1 完整布局：
##   ┌── 顶部提示条：回合 N · Slot M · 轮到 你/Boss · 双方能量 ──┐
##   ├── Boss 候选区（4 张明牌横排）                              │
##   ├── Boss 出牌位（4 槽）                                      │
##   ├── 中线 Slot 编号 (1)(2)(3)(4)                              │
##   ├── 玩家出牌位（4 槽）                                       │
##   ├── 玩家候选区（4 张明牌 + 点击交互）                         │
##   └── 底部预测条："光X 暗Y → 距离平衡 N 张" + 跳过按钮          │
##
## 视觉约束（用户拍板 v0.7.0-alpha-pick.3）：
##   - Pick 阶段全程明牌：双方候选/已 Pick 的牌一律正面显示
##   - 卡背→翻面演出仅出现在 Epic-BP-7 翻盅阶段（本 UI 不涉及）
##
## 接口：
##   activate(battle): 绑定到 BlindClashBattle 实例，订阅所有 BP 信号
##   deactivate(): 解绑信号 + 隐藏 UI（Epic-BP-7 翻盅时调用）

const CardUI := preload("res://scripts/ui/card_ui.gd")
const CARD_W: float = 200.0
const CARD_H: float = 280.0
const CARD_SCALE_CANDIDATE: float = 0.85  # 候选区卡片缩放
const CARD_SCALE_SLOT: float = 0.65       # 出牌位卡片缩放
# v0.7.0-alpha-pick.5 hotfix.2：候选/槽用容器持有 scale，间距 = 卡宽×缩放 + gap
const CANDIDATE_W: float = CARD_W * CARD_SCALE_CANDIDATE  # 170
const CANDIDATE_H: float = CARD_H * CARD_SCALE_CANDIDATE  # 238
const SLOT_W: float = CARD_W * CARD_SCALE_SLOT            # 130
const SLOT_H: float = CARD_H * CARD_SCALE_SLOT            # 182
const CANDIDATE_GAP: float = 30.0
const SLOT_GAP: float = 25.0
const CANDIDATE_SPACING: float = CANDIDATE_W + CANDIDATE_GAP  # 200
const SLOT_SPACING: float = SLOT_W + SLOT_GAP                 # 155

# ===== 节点引用（_build_layout 中创建）=====
var _battle: BlindClashBattle = null
var _top_label: Label = null
var _bottom_label: Label = null
var _skip_button: Button = null

# 容器：4 张候选 + 4 槽（双方各一份）
var _player_candidate_container: Control = null
var _boss_candidate_container: Control = null
var _player_slot_container: Control = null
var _boss_slot_container: Control = null
var _slot_indicator_container: Control = null  # 中线 Slot 编号 1234

# 每张候选/槽的 Control 节点缓存
# v0.7.x-rebal：候选 4 → 6（HAND_POOL_SIZE），slot 仍是 4（PICK_SLOTS）
var _player_candidate_uis: Array = [null, null, null, null, null, null]
var _boss_candidate_uis: Array = [null, null, null, null, null, null]
var _player_slot_uis: Array = [null, null, null, null]
var _boss_slot_uis: Array = [null, null, null, null]
var _slot_indicators: Array = [null, null, null, null]


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_build_layout()


## 绑定到 battle 实例并订阅 BP 信号
func activate(battle: BlindClashBattle) -> void:
	if battle == null:
		push_warning("[PickSelectUI] activate 收到 null battle")
		return
	_battle = battle
	visible = true

	# 订阅 BP 信号（与 blind_clash_scene 并行；scene 仍处理日志，UI 处理视觉）
	_battle.bp_phase_changed.connect(_on_bp_phase_changed)
	_battle.bp_candidates_drawn.connect(_on_bp_candidates_drawn)
	_battle.bp_first_picker_decided.connect(_on_bp_first_picker_decided)
	_battle.bp_pick_made.connect(_on_bp_pick_made)
	_battle.bp_all_picks_locked.connect(_on_bp_all_picks_locked)
	_battle.bp_round_cleanup.connect(_on_bp_round_cleanup)
	# Epic-BP-7：翻盅演出信号
	_battle.bp_reveal_started.connect(_on_bp_reveal_started)
	_battle.bp_resolve_completed.connect(_on_bp_resolve_completed)
	# v0.7.x-rebal：0 费立即生效信号
	_battle.bp_zerocost_used.connect(_on_bp_zerocost_used)


func deactivate() -> void:
	if _battle == null:
		return
	# 解绑（避免重复连接）
	if _battle.bp_phase_changed.is_connected(_on_bp_phase_changed):
		_battle.bp_phase_changed.disconnect(_on_bp_phase_changed)
	if _battle.bp_candidates_drawn.is_connected(_on_bp_candidates_drawn):
		_battle.bp_candidates_drawn.disconnect(_on_bp_candidates_drawn)
	if _battle.bp_first_picker_decided.is_connected(_on_bp_first_picker_decided):
		_battle.bp_first_picker_decided.disconnect(_on_bp_first_picker_decided)
	if _battle.bp_pick_made.is_connected(_on_bp_pick_made):
		_battle.bp_pick_made.disconnect(_on_bp_pick_made)
	if _battle.bp_all_picks_locked.is_connected(_on_bp_all_picks_locked):
		_battle.bp_all_picks_locked.disconnect(_on_bp_all_picks_locked)
	if _battle.bp_round_cleanup.is_connected(_on_bp_round_cleanup):
		_battle.bp_round_cleanup.disconnect(_on_bp_round_cleanup)
	if _battle.bp_reveal_started.is_connected(_on_bp_reveal_started):
		_battle.bp_reveal_started.disconnect(_on_bp_reveal_started)
	if _battle.bp_resolve_completed.is_connected(_on_bp_resolve_completed):
		_battle.bp_resolve_completed.disconnect(_on_bp_resolve_completed)
	if _battle.bp_zerocost_used.is_connected(_on_bp_zerocost_used):
		_battle.bp_zerocost_used.disconnect(_on_bp_zerocost_used)
	_battle = null
	visible = false


# ============================================================
# 布局构造（脚本内动态创建，避免 .tscn 维护）
# ============================================================

func _build_layout() -> void:
	# 整个 UI 占满父容器
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# v0.7.x-hotfix3：根 PickSelectUI 设 IGNORE，避免根节点吞兄弟节点（QueryButtons）的点击。
	# 子节点中真正需要响应鼠标的（卡牌）单独设 STOP；不需要响应的全宽容器/Label 都设 IGNORE。
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# ===== 顶部提示条 =====
	_top_label = Label.new()
	_top_label.name = "TopBanner"
	_top_label.position = Vector2(0, 12)
	_top_label.size = Vector2(1920, 36)
	_top_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_top_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_top_label.add_theme_font_size_override("font_size", 24)
	_top_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_top_label.text = "等待 BP 阶段..."
	_top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_top_label)

	# ===== Boss 候选区（最上）=====
	# 卡片缩放后宽 ~170，4 张总宽 ~680 + 30 gap → ~770，居中
	_boss_candidate_container = Control.new()
	_boss_candidate_container.name = "BossCandidates"
	_boss_candidate_container.position = Vector2(0, 60)
	_boss_candidate_container.size = Vector2(1920, CARD_H * CARD_SCALE_CANDIDATE + 12)
	_boss_candidate_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_candidate_container)

	# ===== Boss 出牌位 =====
	_boss_slot_container = Control.new()
	_boss_slot_container.name = "BossSlots"
	_boss_slot_container.position = Vector2(0, 320)
	_boss_slot_container.size = Vector2(1920, CARD_H * CARD_SCALE_SLOT + 12)
	_boss_slot_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_slot_container)

	# ===== 中线 Slot 编号 =====
	_slot_indicator_container = Control.new()
	_slot_indicator_container.name = "SlotIndicators"
	_slot_indicator_container.position = Vector2(0, 510)
	_slot_indicator_container.size = Vector2(1920, 40)
	_slot_indicator_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slot_indicator_container)

	# ===== 玩家出牌位 =====
	_player_slot_container = Control.new()
	_player_slot_container.name = "PlayerSlots"
	_player_slot_container.position = Vector2(0, 558)
	_player_slot_container.size = Vector2(1920, CARD_H * CARD_SCALE_SLOT + 12)
	_player_slot_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player_slot_container)

	# ===== 玩家候选区（最下）=====
	_player_candidate_container = Control.new()
	_player_candidate_container.name = "PlayerCandidates"
	_player_candidate_container.position = Vector2(0, 760)
	_player_candidate_container.size = Vector2(1920, CARD_H * CARD_SCALE_CANDIDATE + 12)
	_player_candidate_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_player_candidate_container)

	# ===== 底部预测条 =====
	_bottom_label = Label.new()
	_bottom_label.name = "PredictionBar"
	# v0.7.x-hotfix3：底栏避开右下 QueryButtons（屏宽 1920，按钮区 1832~1908）
	# 收窄到 1620 宽并居中（左 150 ~ 右 1770），确保不和按钮重叠
	_bottom_label.position = Vector2(150, 1015)
	_bottom_label.size = Vector2(1620, 36)
	_bottom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bottom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bottom_label.add_theme_font_size_override("font_size", 22)
	_bottom_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_bottom_label.text = ""
	_bottom_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bottom_label)

	# ===== 跳过按钮（无能量起牌时兜底）=====
	# v0.7.x-hotfix3：跳过按钮原位置 1700,1010 与右下 QueryButtons 重叠，挪到左下避让
	_skip_button = Button.new()
	_skip_button.name = "SkipButton"
	_skip_button.text = "跳过 (无能量·对手×2)"
	_skip_button.position = Vector2(40, 1010)
	_skip_button.size = Vector2(220, 44)
	_skip_button.add_theme_font_size_override("font_size", 18)
	_skip_button.pressed.connect(_on_skip_pressed)
	_skip_button.visible = false
	add_child(_skip_button)


# ============================================================
# BP 信号 handler
# ============================================================

# v0.7.x-hotfix3：先手横幅期间隐藏整个牌局展示，banner 收尾时淡入
# scene 端在 _on_bp_candidates_drawn 收到候选后立即调 hide_for_banner()，
# 之后在 _on_bp_first_picker_decided 触发 banner 同时调 reveal_after_banner(1.0)
var _stage_visible: bool = true
var _stage_tween: Tween = null


## 淡到完全透明（不响应交互），用于先手横幅期间遮蔽双方牌局
func hide_for_banner() -> void:
	_stage_visible = false
	if _stage_tween != null and _stage_tween.is_running():
		_stage_tween.kill()
	# 立即设为透明（先手横幅会顶在视觉中央，候选/槽位不应抢戏）
	for ctn in _stage_containers():
		if ctn != null:
			ctn.modulate.a = 0.0


## 经过 delay 秒后开始 0.4s 淡入（与先手横幅的 FADE_OUT 段叠加）
func reveal_after_banner(delay: float = 1.0) -> void:
	_stage_visible = true
	if _stage_tween != null and _stage_tween.is_running():
		_stage_tween.kill()
	_stage_tween = create_tween()
	_stage_tween.tween_interval(delay)
	for ctn in _stage_containers():
		if ctn != null:
			_stage_tween.parallel().tween_property(ctn, "modulate:a", 1.0, 0.4)


## 立即恢复（兜底：debug_kill_boss / 跨阶段切换时用）
func snap_show_stage() -> void:
	_stage_visible = true
	if _stage_tween != null and _stage_tween.is_running():
		_stage_tween.kill()
	for ctn in _stage_containers():
		if ctn != null:
			ctn.modulate.a = 1.0


func _stage_containers() -> Array:
	# 双方候选/槽位/中线 Slot 编号一起淡入淡出；顶/底文字条不变（始终可见）
	return [
		_boss_candidate_container,
		_boss_slot_container,
		_slot_indicator_container,
		_player_slot_container,
		_player_candidate_container,
	]


func _on_bp_phase_changed(new_phase: int, _old_phase: int) -> void:
	if _battle == null:
		return
	# 进入 PICKING 时刷新提示条 + 激活当前 Slot 高亮
	if new_phase == BlindClashBattle.BPPhase.BP_PICKING:
		_refresh_top_banner()
		_refresh_slot_indicators()
		_refresh_candidate_interactivity()
	# 进入 REVEAL 时清空候选区（让翻盅演出有干净舞台 — Epic-BP-7 接管）
	elif new_phase == BlindClashBattle.BPPhase.BP_REVEAL:
		_clear_candidates()


func _on_bp_candidates_drawn(p_candidates: Array, b_candidates: Array) -> void:
	# 新一回合候选抽出：清空旧 UI，重建候选区与槽
	_clear_all_card_uis()
	_render_candidates(p_candidates, true)   # 玩家候选（可点）
	_render_candidates(b_candidates, false)  # Boss 候选（明牌不可点）
	_render_empty_slots()
	_render_slot_indicators()
	_refresh_top_banner()
	_refresh_candidate_interactivity()  # hotfix.3：候选画完立刻按当前 picker/能量切交互
	_refresh_prediction_bar()


func _on_bp_first_picker_decided(_picker: String) -> void:
	_refresh_top_banner()


func _on_bp_pick_made(picker: String, slot_index: int, card: CardData) -> void:
	if card == null:
		# 跳过情况：在槽位上画"毫无阻力"占位
		_set_slot_empty_marker(picker, slot_index, "毫无阻力")
	else:
		# 把候选位的卡 UI 置灰打勾，槽位放一张正面明牌
		_grey_out_picked_candidate(picker, card)
		_fill_slot_with_card(picker, slot_index, card)
	_refresh_top_banner()
	_refresh_slot_indicators()
	# v0.7.0-alpha-pick.5 hotfix.6：BUG FIX —— bp_pick_made.emit 发生在 _after_pick_advance 之前，
	#   此时 current_picker 仍是刚 Pick 完的人（如 Boss）；若立刻 _refresh_candidate_interactivity
	#   会把玩家候选全部走 else 分支 set_process_input(false) → 哪怕之后切到 player 也不再有信号
	#   通知 UI 刷新（_advance_pick_turn 在 player 分支只 return，不发任何信号）→ 玩家永远点不动。
	# 修复：延迟一帧，让 _after_pick_advance 先跑完切换 current_picker，再刷新交互态。
	await get_tree().process_frame
	if _battle == null:
		return  # 防御：deactivate 中
	# v0.8.2 修复：slot 高亮在切换后再刷新一次，确保高亮跟随 current_pick_slot 实时更新
	# （之前 L301 的刷新读到的是切换前状态，导致玩家 slot1 出完后还高亮 slot1，要等玩家 slot2 出完才更新）
	_refresh_slot_indicators()
	_refresh_top_banner()
	_refresh_candidate_interactivity()
	_refresh_prediction_bar()


## v0.7.x-rebal：0 费牌使用信号回调
## 只重画候选区（_clear_candidates），不动 slot（避免清掉已 pick 槽）
func _on_bp_zerocost_used(_side: String, _candidate_index: int, _card: CardData,
		_used_count: int, _limit: int) -> void:
	if _battle == null:
		return
	_clear_candidates()
	_render_candidates(_battle.player_candidates, true)
	_render_candidates(_battle.boss_candidates, false)
	_refresh_candidate_interactivity()
	_refresh_top_banner()
	_refresh_prediction_bar()


func _on_bp_all_picks_locked(_p_picks: Array, _b_picks: Array) -> void:
	if _top_label != null:
		_top_label.text = "▶ 全部 Pick 完成 — 翻盅！"
	_skip_button.visible = false


# ============================================================
# Epic-BP-7：翻盅演出（v0.3 方案 — 委派 ClashDisplayUI 全屏翻盅）
# ============================================================
##
## 设计回归：GDD-04 §1 钦定的"双方各 4 张牌移到屏幕中央，牌背朝下，
## 逐对同时翻开"演出。本 UI 不再做就地光晕揭示，
## 而是在 bp_reveal_started 时：
##   1. 入场过渡动画（1.0s，黑幕渐入 + Pick UI 槽位飞出 + 标题上升）
##   2. 唤起 ClashDisplayUI.start_clash_animation(results, apply_cb)
##   3. 等 ClashDisplayUI.clash_animation_complete
##   4. 收尾过渡动画（1.0s，黑幕渐出 + 标题下降）
##
## 信号链时序（v0.3 §2.5.3 修正）：
##   bp_reveal_started → 入场过渡 → confirm_bp_reveal_done()
##   → BPPhase=BP_RESOLVING → start_clash_animation(apply_cb)
##   → 每对翻面后 apply_cb.call(i) → apply_bp_clash_pair_at(i)
##   → bp_resolve_completed → 收尾过渡 → 回合结束
##
## 过渡时长（v0.3 §2.5.1/§2.5.2）：
##   入场 1.0s + 翻盅 ~11.2s + 收尾 1.0s = 总 ~13.2s

# 过渡视觉常量
const TRANSITION_IN_DUR: float = 1.0    # 入场过渡时长
const TRANSITION_OUT_DUR: float = 1.0   # 收尾过渡时长
const BACKDROP_COLOR := Color(0.0, 0.0, 0.05, 0.85)  # 半透明黑幕

# 过渡节点（lazy 创建，复用）
var _backdrop: ColorRect = null
var _transition_title: Label = null


# Phase 4：Reveal 开始 → 入场过渡 → 委派 ClashDisplayUI → 收尾过渡
func _on_bp_reveal_started(results: Array) -> void:
	if _battle == null:
		return
	if _top_label != null:
		_top_label.text = "▶ 翻盅..."

	# === 入场过渡（1.0s）===
	#   黑幕渐入 + 槽位/候选区淡出 + 顶/底栏淡出 + 标题"翻盅"上升
	await _play_transition_in()
	if _battle == null:
		return  # deactivate 中止

	# === 信号链推进：进入 BP_RESOLVING（v0.3 §2.5.3 修正）===
	# 必须在过渡完成后调用，确保 apply_cb 触发时 phase 正确
	_battle.confirm_bp_reveal_done()

	# === 委派 ClashDisplayUI 接管全屏翻盅 ===
	var clash_ui: Control = _get_clash_display_ui()
	if clash_ui == null:
		push_error("[PickSelectUI] ClashDisplayUI not found, fallback to direct apply")
		# 兜底：直接逐对 apply（无演出）
		for i in range(results.size()):
			if _battle == null:
				return
			if _battle.current_bp_phase != BlindClashBattle.BPPhase.BP_RESOLVING:
				return
			_battle.apply_bp_clash_pair_at(i)
			await get_tree().create_timer(0.3).timeout
		await _play_transition_out()
		return

	# 保证 ClashDisplayUI z 序在 PickSelectUI 之上（v0.3 §2.5.4）
	# blind_clash_scene._setup_bp_mode_ui 运行时把 PickSelectUI add_child 到 UIRoot
	# → 兄弟节点后加靠上 → 默认 PickSelectUI 会盖住 ClashDisplayUI，必须 move_to_front
	clash_ui.move_to_front()

	# 接 clash_animation_complete 信号 → 完成后跑收尾过渡
	var done_signal: Signal = clash_ui.clash_animation_complete
	# 用 Callable 包装伤害 apply（每对翻面后由 ClashDisplayUI 回调）
	var apply_cb := func(idx: int) -> void:
		if _battle == null:
			return
		# 防御：apply 时 phase 必须是 BP_RESOLVING
		if _battle.current_bp_phase == BlindClashBattle.BPPhase.BP_RESOLVING:
			_battle.apply_bp_clash_pair_at(idx)

	clash_ui.start_clash_animation(results, apply_cb)
	# 等翻盅演出完整跑完
	await done_signal
	if _battle == null:
		return

	# === 收尾过渡（1.0s）===
	await _play_transition_out()


func _on_bp_resolve_completed() -> void:
	if _top_label != null:
		_top_label.text = "▶ 回合结束"


# ============================================================
# 过渡动画（v0.3 §2.5.1 入场 + §2.5.2 收尾）
# ============================================================

## 入场过渡：黑幕渐入 + Pick UI 元素淡出 + 标题上升
## 总时长 TRANSITION_IN_DUR（1.0s），6 条并行子动画
func _play_transition_in() -> void:
	_ensure_backdrop()
	# 创建/复用标题"翻盅"
	if _transition_title == null:
		_transition_title = _create_title_label("翻盅")
		add_child(_transition_title)
	else:
		_transition_title.visible = true
	_transition_title.modulate.a = 0.0
	# 标题起始位置：屏幕中央偏下 → 飞向中央偏上
	var screen_w: float = 1920.0
	var screen_h: float = 1080.0
	var title_w: float = 400.0
	var title_h: float = 80.0
	_transition_title.size = Vector2(title_w, title_h)
	_transition_title.position = Vector2((screen_w - title_w) * 0.5, screen_h * 0.55)
	_transition_title.move_to_front()

	# 6 条并行 tween（v0.3 §2.5.1 表）
	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# 1) 黑幕透明 → BACKDROP_COLOR
	tw.tween_property(_backdrop, "color:a", BACKDROP_COLOR.a, TRANSITION_IN_DUR * 0.7)

	# 2) Boss 候选区淡出 + 上飞
	if _boss_candidate_container != null:
		tw.tween_property(_boss_candidate_container, "modulate:a", 0.0, TRANSITION_IN_DUR * 0.6)
		var b_cand_pos: Vector2 = _boss_candidate_container.position
		tw.tween_property(_boss_candidate_container, "position", b_cand_pos + Vector2(0, -80), TRANSITION_IN_DUR * 0.7)

	# 3) 玩家候选区淡出 + 下飞
	if _player_candidate_container != null:
		tw.tween_property(_player_candidate_container, "modulate:a", 0.0, TRANSITION_IN_DUR * 0.6)
		var p_cand_pos: Vector2 = _player_candidate_container.position
		tw.tween_property(_player_candidate_container, "position", p_cand_pos + Vector2(0, 80), TRANSITION_IN_DUR * 0.7)

	# 4) 双方槽位 + Slot 编号同步淡出（保持位置，只变透明，让"飞出去"主要由候选区承担视觉）
	for ctn in [_boss_slot_container, _player_slot_container, _slot_indicator_container]:
		if ctn != null:
			tw.tween_property(ctn, "modulate:a", 0.0, TRANSITION_IN_DUR * 0.6)

	# 5) 顶/底栏淡出
	if _top_label != null:
		tw.tween_property(_top_label, "modulate:a", 0.0, TRANSITION_IN_DUR * 0.5)
	if _bottom_label != null:
		tw.tween_property(_bottom_label, "modulate:a", 0.0, TRANSITION_IN_DUR * 0.5)

	# 6) 标题"翻盅"上升 + 淡入（延迟 0.3s 出现）
	var title_target_y: float = screen_h * 0.4
	tw.tween_property(_transition_title, "modulate:a", 1.0, TRANSITION_IN_DUR * 0.5).set_delay(0.3)
	tw.tween_property(_transition_title, "position:y", title_target_y, TRANSITION_IN_DUR * 0.6).set_delay(0.3)

	await tw.finished
	# 标题播完后立即淡出（让 ClashDisplayUI 舞台干净）
	if _transition_title != null:
		var fade_out: Tween = _transition_title.create_tween()
		fade_out.tween_property(_transition_title, "modulate:a", 0.0, 0.25)
		await fade_out.finished
		_transition_title.visible = false


## 收尾过渡：黑幕渐出 + Pick UI 元素淡入恢复 + 标题"回合结束"短暂出现
## 总时长 TRANSITION_OUT_DUR（1.0s），4 条并行子动画
func _play_transition_out() -> void:
	if _battle == null:
		return
	# 显示"回合结束"标题
	if _transition_title != null:
		_transition_title.text = "回合结束"
		_transition_title.modulate.a = 0.0
		_transition_title.visible = true
		var screen_w: float = 1920.0
		var screen_h: float = 1080.0
		var title_w: float = _transition_title.size.x
		_transition_title.position = Vector2((screen_w - title_w) * 0.5, screen_h * 0.4)
		_transition_title.move_to_front()

	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

	# 1) 标题淡入再淡出（前 0.4s 淡入，后 0.4s 淡出）
	if _transition_title != null:
		tw.tween_property(_transition_title, "modulate:a", 1.0, 0.3)
		tw.tween_property(_transition_title, "modulate:a", 0.0, 0.3).set_delay(0.5)

	# 2) 黑幕透明度 → 0
	if _backdrop != null:
		tw.tween_property(_backdrop, "color:a", 0.0, TRANSITION_OUT_DUR * 0.8).set_delay(0.2)

	# 3) Pick UI 各容器位置 + alpha 复位（恢复初始视觉准备下一回合）
	#    位置已被入场动画推开，回合 cleanup → candidates_drawn 时 _clear_all_card_uis 重建子节点
	#    但容器 position 不会被重置，必须主动复原
	if _boss_candidate_container != null:
		tw.tween_property(_boss_candidate_container, "position", Vector2(0, 60), TRANSITION_OUT_DUR * 0.6).set_delay(0.3)
		tw.tween_property(_boss_candidate_container, "modulate:a", 1.0, TRANSITION_OUT_DUR * 0.5).set_delay(0.4)
	if _player_candidate_container != null:
		tw.tween_property(_player_candidate_container, "position", Vector2(0, 760), TRANSITION_OUT_DUR * 0.6).set_delay(0.3)
		tw.tween_property(_player_candidate_container, "modulate:a", 1.0, TRANSITION_OUT_DUR * 0.5).set_delay(0.4)
	for ctn in [_boss_slot_container, _player_slot_container, _slot_indicator_container]:
		if ctn != null:
			tw.tween_property(ctn, "modulate:a", 1.0, TRANSITION_OUT_DUR * 0.5).set_delay(0.4)

	# 4) 顶/底栏淡入
	if _top_label != null:
		tw.tween_property(_top_label, "modulate:a", 1.0, TRANSITION_OUT_DUR * 0.5).set_delay(0.4)
	if _bottom_label != null:
		tw.tween_property(_bottom_label, "modulate:a", 1.0, TRANSITION_OUT_DUR * 0.5).set_delay(0.4)

	await tw.finished
	if _transition_title != null:
		_transition_title.visible = false


## 懒加载黑幕 ColorRect（覆盖屏幕，置于本 UI 最底层之上但低于 ClashDisplayUI）
## v0.3 §2.5.5：动态创建不改 .tscn
func _ensure_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		_backdrop.color = Color(BACKDROP_COLOR.r, BACKDROP_COLOR.g, BACKDROP_COLOR.b, 0.0)
		_backdrop.visible = true
		return
	_backdrop = ColorRect.new()
	_backdrop.name = "TransitionBackdrop"
	_backdrop.color = Color(BACKDROP_COLOR.r, BACKDROP_COLOR.g, BACKDROP_COLOR.b, 0.0)  # 起始全透明
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 加在最前面（其他 UI 元素之下），但 z_index 不动 → 兄弟节点顺序决定层叠
	add_child(_backdrop)
	# 移到子节点列表最后但 z_index=1，让其盖住槽位/候选区，但 ClashDisplayUI 在 UIRoot 兄弟更靠上
	_backdrop.z_index = 1


## 创建过渡用大字标题
func _create_title_label(text: String) -> Label:
	var lbl: Label = Label.new()
	lbl.name = "TransitionTitle"
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 72)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1.0))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.z_index = 2
	return lbl


## 找到场景中的 ClashDisplayUI（路径：UI/UIRoot/ClashDisplayUI）
func _get_clash_display_ui() -> Control:
	# 本 UI 通常 add_child 到 $UI/UIRoot；ClashDisplayUI 是其兄弟
	var parent: Node = get_parent()
	if parent == null:
		return null
	var sibling: Node = parent.get_node_or_null("ClashDisplayUI")
	if sibling != null and sibling is Control:
		return sibling
	# 兜底：从根往下找
	var root: Node = get_tree().current_scene
	if root != null:
		var found: Node = root.find_child("ClashDisplayUI", true, false)
		if found != null and found is Control:
			return found
	return null


func _on_bp_round_cleanup(_p_discarded: Array, _b_discarded: Array) -> void:
	# 回合末：UI 整体淡出准备下回合（_clear 在下回合 candidates_drawn 时再做）
	pass


# ============================================================
# 候选区渲染
# ============================================================

func _render_candidates(candidates: Array, is_player: bool) -> void:
	var container: Control = _player_candidate_container if is_player else _boss_candidate_container
	var ui_array: Array = _player_candidate_uis if is_player else _boss_candidate_uis

	# 清空旧子节点
	for child in container.get_children():
		child.queue_free()

	var count: int = candidates.size()
	if count == 0:
		return

	# v0.7.x-hotfix4：只对"非空候选"做居中布局（不留空位 → 视觉干净）
	# 已被 Pick / 0费弃掉的位置 candidates[i] == null，跳过；剩余卡按视觉序号紧挨居中
	var visible_count: int = 0
	for c in candidates:
		if c != null:
			visible_count += 1
	if visible_count == 0:
		# 所有候选都消耗完（罕见，但兜底）
		for i in range(count):
			ui_array[i] = null
		return

	var total_w: float = visible_count * CANDIDATE_W + (visible_count - 1) * CANDIDATE_GAP
	var start_x: float = (1920.0 - total_w) / 2.0
	var visible_idx: int = 0  # 视觉位（决定 x 坐标）

	for i in range(count):
		var card: CardData = candidates[i]
		if card == null:
			ui_array[i] = null
			continue

		# 包装容器：固定 scale + 卡牌左上角对齐 (0,0)
		# wrapper.size = 卡牌原始尺寸 200×280；scale=0.85 后视觉宽度 170 = CANDIDATE_W ✓
		# pivot=(0,0) 让 scale 从左上角缩放，wrapper.position 即视觉左上点
		var wrapper: Control = Control.new()
		wrapper.name = "Cand%d" % i
		wrapper.position = Vector2(start_x + visible_idx * (CANDIDATE_W + CANDIDATE_GAP), 0)
		wrapper.size = Vector2(CARD_W, CARD_H)
		wrapper.pivot_offset = Vector2.ZERO
		wrapper.scale = Vector2(CARD_SCALE_CANDIDATE, CARD_SCALE_CANDIDATE)
		wrapper.mouse_filter = Control.MOUSE_FILTER_PASS
		container.add_child(wrapper)

		var card_ui: Control = Control.new()
		card_ui.set_script(CardUI)
		card_ui.setup(card, Vector2.ZERO)
		wrapper.add_child(card_ui)

		if is_player:
			# 玩家候选：保留原 CardUI 的 hover 放大 + 全局 _input 点击监听
			# v0.7.0-alpha-pick.5 hotfix.5：用 bind() 显式按值绑定索引，
			# 避免 lambda 闭包对 for 循环变量 i 的捕获歧义（不同 Godot 版本行为不一致）
			card_ui.card_clicked.connect(_on_player_candidate_clicked.bind(i).unbind(1))
		else:
			# Boss 候选：完全静默（无 hover、无点击）
			card_ui.call("disable_hover")
			card_ui.set_process_input(false)
			card_ui.set_process(false)
			card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
			card_ui.modulate = Color(1.0, 0.95, 0.95)  # 微红 tint 区分敌方
		ui_array[i] = card_ui
		visible_idx += 1


## v0.7.x-hotfix4：候选被 Pick / 0 费消耗后，把剩余卡重新居中
## 用 tween 平滑过渡，避免突跳
## v0.7.x-hotfix5：用 is_queued_for_deletion() 过滤已 queue_free 但还在树上的 wrapper
##   （call_deferred 时刻：被 free 的节点仍在 get_children() 列表，仅打了删除标记）
func _relayout_candidate_row(is_player: bool) -> void:
	var container: Control = _player_candidate_container if is_player else _boss_candidate_container
	if container == null:
		return
	# 收集"还存在且未被标记删除"的 wrapper（按子节点顺序 = 当初 i 的相对序）
	var wrappers: Array = []
	for child in container.get_children():
		if not (child is Control):
			continue
		if not is_instance_valid(child):
			continue
		if child.is_queued_for_deletion():
			continue
		wrappers.append(child)
	var n: int = wrappers.size()
	if n == 0:
		return
	var total_w: float = n * CANDIDATE_W + (n - 1) * CANDIDATE_GAP
	var start_x: float = (1920.0 - total_w) / 2.0
	for j in range(n):
		var w: Control = wrappers[j]
		var target_x: float = start_x + j * (CANDIDATE_W + CANDIDATE_GAP)
		# 已在目标位置：跳过（避免空 tween）
		if abs(w.position.x - target_x) < 0.5:
			continue
		var tw: Tween = create_tween()
		tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(w, "position:x", target_x, 0.2)


func _grey_out_picked_candidate(picker: String, card: CardData) -> void:
	## v0.7.x-hotfix4：取消"灰底虚影"——已 Pick 的候选直接从 UI 移除，
	## 然后把同侧剩余卡 tween 居中。每次抽/出/0费都触发重居中，视觉始终干净。
	var ui_array: Array = _player_candidate_uis if picker == "player" else _boss_candidate_uis
	var is_player: bool = picker == "player"
	for i in range(ui_array.size()):
		var ui: Control = ui_array[i]
		if ui == null:
			continue
		var ui_card: CardData = ui.get("card_data")
		if ui_card == card:
			# 关键修复：先强制 reset hover 视觉，避免残留放大状态被冻结
			_reset_card_hover_visual(ui)
			# 直接移除 wrapper（card_ui 的父节点），并清空数组位
			var wrapper: Node = ui.get_parent()
			if wrapper != null and is_instance_valid(wrapper):
				wrapper.queue_free()
			ui_array[i] = null
			break
	# 触发剩余卡重新居中（延迟一帧，等 queue_free 真正生效）
	call_deferred("_relayout_candidate_row", is_player)


func _refresh_candidate_interactivity() -> void:
	## 根据 cost > 当前能量灰显玩家候选；不是玩家轮次时全员禁点
	if _battle == null or _battle.player == null:
		return
	var is_player_turn: bool = (
		_battle.current_bp_phase == BlindClashBattle.BPPhase.BP_PICKING
		and _battle.current_picker == "player"
	)
	var any_playable: bool = false
	for i in range(_player_candidate_uis.size()):
		var ui: Control = _player_candidate_uis[i]
		if ui == null:
			continue
		var card: CardData = ui.get("card_data")
		if card == null:
			continue
		# 已被 Pick / 0费消耗（candidates[i] == null）→ UI 已被 _grey_out_picked_candidate 移除
		if i < _battle.player_candidates.size() and _battle.player_candidates[i] == null:
			continue

		var affordable: bool = (card.energy_cost <= _battle.player.energy)
		# 0 费牌还需检查本回合 0 费使用次数
		if card.energy_cost == 0 and not _battle.player.can_use_zerocost():
			affordable = false
		var clickable: bool = is_player_turn and affordable
		if clickable:
			ui.modulate = Color(1, 1, 1)
			ui.mouse_filter = Control.MOUSE_FILTER_STOP
			ui.set_process_input(true)
			ui.set_process(true)  # 重新允许 hover 追踪
		elif not affordable:
			# 能量不足：灰显，禁全局 input 监听
			# v0.7.0-alpha-pick.5 hotfix.6：禁前先 reset hover 视觉（防止禁 process 后停在放大态）
			_reset_card_hover_visual(ui)
			ui.modulate = Color(0.55, 0.55, 0.6, 0.85)
			ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ui.set_process_input(false)
			ui.set_process(false)
		else:
			# 不是玩家轮次：稍微淡化，禁 input 监听
			_reset_card_hover_visual(ui)
			ui.modulate = Color(0.85, 0.85, 0.9)
			ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ui.set_process_input(false)
			ui.set_process(false)

		if clickable:
			any_playable = true

	# 跳过按钮：玩家轮次 + 没有任何可起的牌 → 显现
	_skip_button.visible = is_player_turn and not any_playable


func _reset_card_hover_visual(ui: Control) -> void:
	## v0.7.0-alpha-pick.5 hotfix.6：强制把 CardUI 的 hover 视觉态恢复到非 hover 状态。
	## 任何"禁 process / 灰显" 之前都应该先调这个，避免 hover tween 中途冻结成放大虚影。
	if ui == null:
		return
	ui.scale = Vector2.ONE
	ui.z_index = 0
	ui.set("_is_hovered", false)
	var base_pos: Vector2 = ui.get("_base_position")
	ui.position = base_pos


func _on_player_candidate_clicked(candidate_index: int) -> void:
	print("[PickUI] 玩家点击候选 idx=%d" % candidate_index)
	if _battle == null:
		print("[PickUI] 拒绝：_battle 为 null")
		return
	if _battle.current_bp_phase != BlindClashBattle.BPPhase.BP_PICKING:
		print("[PickUI] 拒绝：当前 phase=%d 不是 BP_PICKING" % _battle.current_bp_phase)
		return
	if _battle.current_picker != "player":
		print("[PickUI] 拒绝：当前 picker=%s 不是 player" % _battle.current_picker)
		return
	var ok: bool = _battle.make_player_pick(candidate_index)
	if not ok:
		# UI 已经做了 affordable 检查，此处通常不会失败；万一失败让 battle 的 print 自查
		push_warning("[PickSelectUI] make_player_pick 失败 idx=%d" % candidate_index)


func _on_skip_pressed() -> void:
	if _battle == null:
		return
	_battle.skip_player_pick()


# ============================================================
# 出牌位渲染
# ============================================================

func _render_empty_slots() -> void:
	## 4 个空槽：双方各画一行虚线框占位
	for i in range(4):
		_player_slot_uis[i] = _make_slot_placeholder(_player_slot_container, i, true)
		_boss_slot_uis[i] = _make_slot_placeholder(_boss_slot_container, i, false)


func _make_slot_placeholder(container: Control, slot_index: int, is_player: bool) -> Control:
	# 居中：4 槽 × SLOT_W + 3 × SLOT_GAP
	var total_w: float = 4 * SLOT_W + 3 * SLOT_GAP
	var start_x: float = (1920.0 - total_w) / 2.0

	var panel: Panel = Panel.new()
	panel.name = "Slot%d" % (slot_index + 1)
	panel.position = Vector2(start_x + slot_index * (SLOT_W + SLOT_GAP), 0)
	panel.size = Vector2(SLOT_W, SLOT_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 虚线框样式（StyleBoxFlat 没有虚线，用细边框 + 半透模拟）
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.1, 0.4)
	sb.border_color = Color(0.4, 0.5, 0.7, 0.5) if is_player else Color(0.7, 0.4, 0.4, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	container.add_child(panel)

	# 槽内放一个标题 Label（居中）
	var label: Label = Label.new()
	label.text = "Slot %d" % (slot_index + 1)
	label.size = Vector2(SLOT_W, SLOT_H)
	label.position = Vector2.ZERO
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75, 0.7))
	label.add_theme_font_size_override("font_size", 14)
	panel.add_child(label)

	return panel


func _fill_slot_with_card(picker: String, slot_index: int, card: CardData) -> void:
	## 把已 Pick 的卡牌正面塞进对应槽（双方都明牌）
	var slot_panel: Control = (_player_slot_uis if picker == "player" else _boss_slot_uis)[slot_index]
	if slot_panel == null:
		return

	# 移除占位 label
	for child in slot_panel.get_children():
		child.queue_free()

	# 包装容器持有 scale，card_ui 在 wrapper 内左上角对齐
	var wrapper: Control = Control.new()
	wrapper.name = "SlotCardWrapper"
	wrapper.position = Vector2.ZERO
	wrapper.size = Vector2(CARD_W, CARD_H)
	wrapper.scale = Vector2(CARD_SCALE_SLOT, CARD_SCALE_SLOT)
	wrapper.pivot_offset = Vector2.ZERO
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot_panel.add_child(wrapper)

	var card_ui: Control = Control.new()
	card_ui.set_script(CardUI)
	card_ui.setup(card, Vector2.ZERO)
	# 槽内卡牌完全静默：禁 hover、禁 input、禁 process
	card_ui.call("disable_hover")
	card_ui.set_process_input(false)
	card_ui.set_process(false)
	card_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if picker == "boss":
		card_ui.modulate = Color(1.0, 0.95, 0.95)  # 微红 tint
	wrapper.add_child(card_ui)

	# 飞入动画：wrapper 持有 scale tween（card_ui 自身 scale 保持 1）
	wrapper.modulate.a = 0.0
	wrapper.scale = Vector2(CARD_SCALE_SLOT * 1.2, CARD_SCALE_SLOT * 1.2)
	var tw: Tween = create_tween().set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(wrapper, "modulate:a", 1.0, 0.25)
	tw.tween_property(wrapper, "scale", Vector2(CARD_SCALE_SLOT, CARD_SCALE_SLOT), 0.25)


func _set_slot_empty_marker(picker: String, slot_index: int, marker: String) -> void:
	var slot_panel: Control = (_player_slot_uis if picker == "player" else _boss_slot_uis)[slot_index]
	if slot_panel == null:
		return
	for child in slot_panel.get_children():
		child.queue_free()
	var label: Label = Label.new()
	label.text = marker
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-40, -20)
	label.size = Vector2(200, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var marker_color: Color = Color(0.6, 0.4, 0.4) if picker == "player" else Color(0.8, 0.5, 0.3)
	label.add_theme_color_override("font_color", marker_color)
	label.add_theme_font_size_override("font_size", 20)
	slot_panel.add_child(label)


# ============================================================
# Slot 编号指示器（中线 1234）
# ============================================================

func _render_slot_indicators() -> void:
	for child in _slot_indicator_container.get_children():
		child.queue_free()
	# 与 slot panel 对齐：4 槽 × SLOT_W + 3 × SLOT_GAP
	var total_w: float = 4 * SLOT_W + 3 * SLOT_GAP
	var start_x: float = (1920.0 - total_w) / 2.0

	for i in range(4):
		# v0.8.0 蛇形出牌：每个 Slot 标注先出方
		var leader_text: String = ""
		if _battle != null and _battle.first_picker != "":
			var slot_leader: String = _get_slot_leader(i)
			leader_text = " [你先]" if slot_leader == "player" else " [回响先]"
		var label: Label = Label.new()
		label.text = "● Slot %d ●%s" % [i + 1, leader_text]
		label.position = Vector2(start_x + i * (SLOT_W + SLOT_GAP), 0)
		label.size = Vector2(SLOT_W, 36)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7))
		_slot_indicator_container.add_child(label)
		_slot_indicators[i] = label


## v0.8.0 蛇形出牌辅助：返回指定 slot 的"先出方"
func _get_slot_leader(slot: int) -> String:
	if slot % 2 == 0:
		return _battle.first_picker
	else:
		return "boss" if _battle.first_picker == "player" else "player"


func _refresh_slot_indicators() -> void:
	## 当前激活 Slot 高亮成黄/亮色，同时标注先出方
	if _battle == null:
		return
	var active: int = _battle.current_pick_slot
	for i in range(_slot_indicators.size()):
		var label: Label = _slot_indicators[i]
		if label == null:
			continue
		# 先出方标注
		var leader_text: String = ""
		if _battle.first_picker != "":
			var slot_leader: String = _get_slot_leader(i)
			leader_text = " [你先]" if slot_leader == "player" else " [回响先]"
		if i == active and _battle.current_bp_phase == BlindClashBattle.BPPhase.BP_PICKING:
			label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
			label.text = "▶ Slot %d ◀%s" % [i + 1, leader_text]
		elif i < active:
			label.add_theme_color_override("font_color", Color(0.4, 0.7, 0.5, 0.7))
			label.text = "✓ Slot %d ✓%s" % [i + 1, leader_text]
		else:
			label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7))
			label.text = "● Slot %d ●%s" % [i + 1, leader_text]


# ============================================================
# 顶部提示条 + 底部预测条
# ============================================================

func _refresh_top_banner() -> void:
	if _battle == null or _top_label == null:
		return
	var phase: int = _battle.current_bp_phase
	if phase == BlindClashBattle.BPPhase.BP_DRAW_CANDIDATES:
		_top_label.text = "回合 %d · 抽取候选..." % _battle.round_number
	elif phase == BlindClashBattle.BPPhase.BP_FIRST_PICKER:
		var pl: String = "你" if _battle.first_picker == "player" else "回响"
		_top_label.text = "回合 %d · 先手：%s" % [_battle.round_number, pl]
	elif phase == BlindClashBattle.BPPhase.BP_PICKING:
		var picker_label: String = "你" if _battle.current_picker == "player" else "回响"
		_top_label.text = "回合 %d · Slot %d · 轮到 %s · 你 %d⚡  Boss %d⚡" % [
			_battle.round_number,
			_battle.current_pick_slot + 1,
			picker_label,
			_battle.player.energy,
			_battle.boss.energy,
		]
	elif phase == BlindClashBattle.BPPhase.BP_REVEAL:
		_top_label.text = "翻盅..."
	else:
		_top_label.text = ""


func _refresh_prediction_bar() -> void:
	## GDD-06 Sprint B：实时预测条 "光X 暗Y → 距离平衡 N 张"
	## 明牌 BP 下双方都可见（不是玩家专属）
	## 只统计已 Pick 进双方出牌位的牌（候选不算）
	if _battle == null or _bottom_label == null:
		return
	var light_count: int = 0
	var dark_count: int = 0
	for picks in [_battle.player_picks, _battle.boss_picks]:
		for c in picks:
			if c == null:
				continue
			# CardData.Polarity enum: NONE / LIGHT / DARK（GDD-06 §3 光暗平衡）
			match c.polarity:
				CardData.Polarity.LIGHT:
					light_count += 1
				CardData.Polarity.DARK:
					dark_count += 1
	var distance: int = absi(light_count - dark_count)
	var balance_hint: String
	if light_count == 0 and dark_count == 0:
		balance_hint = "尚无光/暗牌"
	elif distance == 0 and (light_count + dark_count) >= 2:
		balance_hint = "☯ 已平衡（×2.0 触发条件就绪）"
	else:
		balance_hint = "距离平衡 %d 张" % distance
	_bottom_label.text = "☯ 光 %d · 暗 %d  →  %s" % [light_count, dark_count, balance_hint]


# ============================================================
# 清理工具
# ============================================================

func _clear_candidates() -> void:
	for container in [_player_candidate_container, _boss_candidate_container]:
		if container == null:
			continue
		for child in container.get_children():
			child.queue_free()
	_player_candidate_uis = [null, null, null, null, null, null]
	_boss_candidate_uis = [null, null, null, null, null, null]


func _clear_all_card_uis() -> void:
	_clear_candidates()
	for container in [_player_slot_container, _boss_slot_container, _slot_indicator_container]:
		if container == null:
			continue
		for child in container.get_children():
			child.queue_free()
	_player_slot_uis = [null, null, null, null]
	_boss_slot_uis = [null, null, null, null]
	_slot_indicators = [null, null, null, null]
