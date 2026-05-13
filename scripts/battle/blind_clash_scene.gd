extends Control
## 暗出对决战斗场景主控 — 连接 BlindClashBattle + 所有 UI 组件
## 替代旧 battle_scene.gd

const BlindSelectUI := preload("res://scripts/ui/blind_select_ui.gd")
const TrapDeployUI := preload("res://scripts/ui/trap_deploy_ui.gd")
const ClashDisplayUI := preload("res://scripts/ui/clash_display_ui.gd")
const ProbeDisplayUI := preload("res://scripts/ui/probe_display_ui.gd")
const CyberTheme := preload("res://scripts/ui/cyber_theme.gd")
const CardUI := preload("res://scripts/ui/card_ui.gd")

@onready var battle: BlindClashBattle = $BlindClashBattle
@onready var player_panel: PanelContainer = $UI/UIRoot/PlayerPanel
@onready var boss_panel: PanelContainer = $UI/UIRoot/BossPanel
@onready var blind_select: Control = $UI/UIRoot/BlindSelectUI
@onready var trap_deploy: Control = $UI/UIRoot/TrapDeployUI
@onready var clash_display: Control = $UI/UIRoot/ClashDisplayUI
@onready var probe_display: Control = $UI/UIRoot/ProbeDisplayUI
@onready var log_label: RichTextLabel = $UI/UIRoot/LogPanel/LogText
@onready var round_label: Label = $UI/UIRoot/RoundLabel
@onready var phase_label: Label = $UI/UIRoot/PhaseLabel
@onready var battle_effects: Node = $BattleEffects
@onready var fx_layer: Control = $UI/UIRoot/FxLayer
@onready var boss_count_label: Label = $UI/UIRoot/BossBlindCount
@onready var hand_display: Control = $UI/UIRoot/HandDisplay
@onready var constraint_count_label: Label = $UI/UIRoot/ConstraintPanel/VBox/ResourceCount
@onready var trap_count_label: Label = $UI/UIRoot/ConstraintPanel/VBox/TrapCount

# 查询入口 & 弹层（牌库/Boss牌库/规则）
@onready var player_deck_btn: Button = $UI/UIRoot/QueryButtons/PlayerDeckBtn
@onready var boss_deck_btn: Button = $UI/UIRoot/QueryButtons/BossDeckBtn
@onready var rules_btn: Button = $UI/UIRoot/QueryButtons/RulesBtn
@onready var player_deck_view: DeckViewUI = $UI/PlayerDeckView
@onready var boss_deck_view: DeckViewUI = $UI/BossDeckView
@onready var rules_overlay: RulesOverlayUI = $UI/RulesOverlay
@onready var boss_thinking: BossThinkingOverlay = $UI/BossThinkingOverlay

# LLM AI 引用（供日志读 reasoning）
var _llm_ai_ref: LLMBossAI = null

# v0.4.3 PendingInsightsBanner — 顶部持续提示"下回合开局：Boss 将偷看[X]"
var _pending_banner: VBoxContainer = null
var _pending_banner_entries: Array = []  # [{type, card_id, label_node}]

# v0.4.3 boss "源点"屏幕坐标（宣告动画的射线起点）— 取 boss_panel 中心
func _get_boss_world_pos() -> Vector2:
	if boss_panel == null:
		return Vector2(960, 100)
	return boss_panel.global_position + boss_panel.size / 2.0

# 首战规则弹出持久化标记（仅用户目录写入 1 次）
const TUTORIAL_FLAG_PATH := "user://tutorial_rules_seen.flag"

# 手牌扇形布局参数
const HAND_FAN_ANGLE: float = 3.0  # 每张牌偏转角度
const HAND_SPACING: float = 130.0  # 牌间距
const HAND_ARC_HEIGHT: float = 8.0  # 两边下沉像素

var _player_prev_hp: int = 60
var _boss_prev_hp: int = 55


func _ready() -> void:
	CyberTheme.apply_theme_to_tree($UI/UIRoot)
	var cam_3d: Camera3D = get_node_or_null("Background3D/SubViewport/Scene/Camera3D")
	if battle_effects and cam_3d:
		battle_effects.setup(fx_layer, cam_3d)
	elif battle_effects:
		battle_effects.setup(fx_layer, null)
	# v0.4.3：洞察宣告动画的父容器（在常规 fx_layer 上播放）
	if probe_display.has_method("set_fx_parent"):
		probe_display.set_fx_parent(fx_layer)
	# v0.4.3：构造 PendingInsightsBanner（屏幕顶部居中）
	_setup_pending_banner()
	_connect_signals()
	_setup_query_buttons()
	_setup_battle()
	_maybe_show_first_time_rules()


func _setup_query_buttons() -> void:
	player_deck_btn.pressed.connect(_open_player_deck)
	boss_deck_btn.pressed.connect(_open_boss_deck)
	rules_btn.pressed.connect(_open_rules)
	# 视觉调色：青蓝 / 血红 / 中性
	_style_query_button(player_deck_btn, Color(0.3, 0.85, 1.0))
	_style_query_button(boss_deck_btn, Color(0.95, 0.2, 0.25))
	_style_query_button(rules_btn, Color(0.6, 0.7, 0.85))


func _style_query_button(btn: Button, accent: Color) -> void:
	btn.add_theme_font_size_override("font_size", 26)
	btn.add_theme_color_override("font_color", accent)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = Color(0.05, 0.08, 0.12, 0.85)
	sb_normal.border_color = accent * 0.7
	sb_normal.set_border_width_all(2)
	sb_normal.set_corner_radius_all(8)
	btn.add_theme_stylebox_override("normal", sb_normal)
	var sb_hover := sb_normal.duplicate()
	sb_hover.border_color = accent
	sb_hover.shadow_color = accent * Color(1, 1, 1, 0.6)
	sb_hover.shadow_size = 6
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_hover)


func _open_player_deck() -> void:
	# 合并全牌（抽牌+手牌+弃牌），完整视角
	var all_cards: Array[CardData] = []
	all_cards.append_array(battle.player.deck)
	all_cards.append_array(battle.player.hand)
	all_cards.append_array(battle.player.discard_pile)
	player_deck_view.show_player_deck(all_cards)


func _open_boss_deck() -> void:
	var all_boss: Array[CardData] = []
	all_boss.append_array(battle.boss.deck)
	all_boss.append_array(battle.boss.hand)
	all_boss.append_array(battle.boss.discard_pile)
	boss_deck_view.show_boss_deck(all_boss)


func _open_rules() -> void:
	rules_overlay.open_rules()


func _maybe_show_first_time_rules() -> void:
	# 首次进入战斗，自动弹一次规则
	if FileAccess.file_exists(TUTORIAL_FLAG_PATH):
		return
	# 延迟到下一帧弹，避免与战斗启动信号撞车
	await get_tree().process_frame
	rules_overlay.open_rules()
	var f := FileAccess.open(TUTORIAL_FLAG_PATH, FileAccess.WRITE)
	if f:
		f.store_string("seen")
		f.close()


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed:
		return
	# 任一弹层打开时，不响应快捷键（让弹层自己处理 ESC）
	if player_deck_view.visible or boss_deck_view.visible or rules_overlay.visible:
		return
	match event.keycode:
		KEY_TAB:
			_open_player_deck()
			get_viewport().set_input_as_handled()
		KEY_B:
			_open_boss_deck()
			get_viewport().set_input_as_handled()
		KEY_QUESTION, KEY_SLASH, KEY_F1:
			_open_rules()
			get_viewport().set_input_as_handled()


func _setup_battle() -> void:
	var card_db: Node = get_node("/root/CardDatabase")
	var player_deck: Array[CardData] = card_db.get_player_starter_deck()
	var boss_deck: Array[CardData] = card_db.get_boss_layer1_deck()
	var traps: Array[TrapData] = card_db.get_initial_traps()

	var player := Combatant.new("Player", 60, player_deck)
	var boss := Combatant.new("回响", 55, boss_deck)

	# 初始化血条面板
	player_panel.setup("Player", 60, false)
	boss_panel.setup("回响", 55, true)

	# 连接 Combatant 信号
	player.hp_changed.connect(_on_player_hp_changed)
	player.armor_changed.connect(_on_player_armor_changed)
	player.energy_changed.connect(_on_player_energy_changed)
	player.hand_changed.connect(_on_player_hand_changed)
	boss.hp_changed.connect(_on_boss_hp_changed)
	boss.armor_changed.connect(_on_boss_armor_changed)

	# 【AI 注入】v0.4 默认使用 LLMBossAI（内部按 LLMConfig 自动 fallback 到规则 AI / Mock）
	var llm_ai := LLMBossAI.new()
	llm_ai.attach_to(self)  # HTTPRequest 必须挂在场景树中
	battle.boss_ai = llm_ai
	_llm_ai_ref = llm_ai
	# 调试日志：显示当前 LLM 配置来源
	var cfg: LLMConfig = llm_ai.get_config()
	_add_log("[color=gray][AI] provider=%s key_source=%s force_rule=%s show_reasoning=%s[/color]" % [
		cfg.active_provider, cfg.key_source, str(cfg.force_rule_ai), str(cfg.show_llm_reasoning)
	])

	battle.start_battle(player, boss, traps)


func _connect_signals() -> void:
	# 战斗流程信号
	battle.battle_started.connect(_on_battle_started)
	battle.round_started.connect(_on_round_started)
	battle.deploy_phase_started.connect(_on_deploy_phase)
	battle.blind_phase_started.connect(_on_blind_phase)
	battle.clash_phase_started.connect(_on_clash_phase)
	battle.probe_phase_started.connect(_on_probe_phase)
	battle.round_ended.connect(_on_round_ended)
	battle.battle_ended.connect(_on_battle_ended)
	battle.probe_prediction_announced.connect(_on_probe_prediction)
	battle.probe_result_announced.connect(_on_probe_result)
	battle.insight_effect.connect(_on_insight_effect)
	battle.insight_applied.connect(_on_insight_applied)
	battle.insight_random_triggered.connect(_on_insight_random_triggered)
	battle.trap_triggered_signal.connect(_on_trap_triggered)
	battle.clash_pair_resolved.connect(_on_clash_pair_resolved)

	# UI 交互信号
	blind_select.blind_confirmed.connect(_on_blind_confirmed)
	trap_deploy.deploy_confirmed.connect(_on_deploy_confirmed)
	trap_deploy.probe_jammed.connect(_on_probe_jam_requested)
	clash_display.clash_animation_complete.connect(_on_clash_animation_done)
	probe_display.probe_display_complete.connect(_on_probe_display_done)


# ===== 阶段处理 =====

func _on_battle_started() -> void:
	_add_log("[color=green]战斗开始: Player vs 回响 — 暗出对决模式[/color]")

func _on_round_started(round_num: int) -> void:
	round_label.text = "回合 %d" % round_num
	_add_log("[color=cyan]— 回合 %d 开始 —[/color]" % round_num)

func _on_deploy_phase() -> void:
	phase_label.text = "部署阶段"
	_add_log("[color=yellow]▶ 部署阶段：可部署陷阱/干扰探针[/color]")
	# 隐藏常驻手牌，避免card_ui的全局_input吞掉TrapDeployUI按钮点击
	hand_display.visible = false
	trap_deploy.activate(battle.trap_inventory, battle.constraint_resource)

func _on_deploy_confirmed() -> void:
	# 将部署结果同步到 battle
	var slots: Array = trap_deploy.get_deployed_slots()
	for i in range(3):
		if slots[i] != null:
			battle.deploy_trap(slots[i], i)
	_update_constraint_panel()
	battle.confirm_deploy()

func _on_blind_phase() -> void:
	phase_label.text = "暗出阶段"
	_add_log("[color=yellow]▶ 暗出阶段：选择牌并排列顺序[/color]")
	# Boss 思考状态提示（异步 AI 还在选牌时显示，否则显示已选张数）
	boss_count_label.text = "Boss 选牌中..."
	boss_count_label.visible = true
	# 隐藏常驻手牌（BlindSelectUI有自己的手牌显示）
	hand_display.visible = false
	# 激活暗出选牌UI（v0.4.3 同步把 peeked_cards 传过去做持续标记）
	blind_select.activate(battle.player.hand, battle.player.energy, battle.disrupted_cards, battle.peeked_cards)

func _on_blind_confirmed(cards: Array[CardData], bound_zeros: Dictionary) -> void:
	var success: bool = battle.set_player_blind_cards(cards, bound_zeros)
	if success:
		_add_log("你暗出了 %d 张牌" % cards.size())
		boss_count_label.visible = false
		# 恢复常驻手牌显示
		hand_display.visible = true
		_refresh_hand_display()
		_update_constraint_panel()
		# 播放 Boss 思考演出（最少 3s，等 LLM 就绪最多 8s）
		var ai_ready_check := Callable()
		if _llm_ai_ref != null:
			ai_ready_check = func() -> bool: return not _llm_ai_ref.is_thinking()
		await boss_thinking.play(3.0, 8.0, ai_ready_check)
		# 进入对决：confirm_blind 内会 await select_blind_cards_async()，
		# 该函数返回时 _last_was_fallback / _last_reasoning / _last_error
		# 才是"本回合"的真实状态（第一回合时尤其关键 —— warm_up 完成时机
		# 不一定能赶在 thinking 演出窗口内，必须等 select_blind_cards_async 收口）。
		await battle.confirm_blind()
		# 演出结束 + 决策收口后，输出 AI 状态到战斗日志（在对决动画期间显示也无妨）
		if _llm_ai_ref != null:
			if _llm_ai_ref.was_last_decision_fallback():
				# LLM 失败/超时/降级 → 走了规则 AI（红字醒目提示）
				var err: String = _llm_ai_ref.get_last_error()
				if err.is_empty():
					err = "未知原因"
				_add_log("[color=#ff3333][AI] ⚠ %s — 由规则 AI 接管本回合[/color]" % err)
				# v0.4.2：若本次 fallback 是因 LLM 输出被截断（finish=length，
				# 多半是推理模型把 token 全花在 reasoning_content 上，没产出最终答），
				# 视作 Boss\"过载\"——给玩家一个奖励占位（实装留待后续）
				if _llm_ai_ref.has_method("was_last_truncated") and _llm_ai_ref.was_last_truncated():
					_add_log("[color=#66ddff]✦ Boss过载，触发奖励（未实现）[/color]")
			elif _llm_ai_ref.get_config().show_llm_reasoning:
				# LLM 成功且开启了 reasoning 展示
				var reasoning: String = _llm_ai_ref.get_last_reasoning()
				if reasoning.length() > 0:
					_add_log("[color=#ff5566][LLM] %s[/color]" % reasoning)
	else:
		# 验证失败，重新激活
		blind_select.activate(battle.player.hand, battle.player.energy, battle.disrupted_cards, battle.peeked_cards)

func _on_clash_phase() -> void:
	phase_label.text = "对决阶段"
	_add_log("[color=red]▶ 对决阶段：逐张翻开！[/color]")
	# 仅"预计算"结果（不立即应用伤害/陷阱），把"逐对应用"的回调交给 UI，
	# 这样每播完一对的翻牌动画再扣血/触发陷阱，HP 数字会随对决节奏跳动，
	# 而不是一次性从满血掉到结算后的最终值。
	var results: Array[ClashResolver.ClashResult] = battle.prepare_clash()
	var apply_cb := func(idx: int) -> void:
		battle.apply_clash_pair_at(idx)
	clash_display.start_clash_animation(results, apply_cb)

func _on_clash_pair_resolved(result: ClashResolver.ClashResult) -> void:
	# 记录每对碰撞日志
	var p_name: String = result.player_card.card_name if result.player_card else "—"
	var b_name: String = result.boss_card.card_name if result.boss_card else "—"
	var mult_text: String = ""
	match result.clash_type:
		"counter_player":
			mult_text = "[color=green]克制![/color]"
		"counter_boss":
			mult_text = "[color=red]被克制[/color]"
		"neutral":
			mult_text = "中立"
		"free_player":
			mult_text = "[color=cyan]直接生效[/color]"
		"free_boss":
			mult_text = "[color=orange]Boss直接生效[/color]"
	_add_log("  %s vs %s — %s" % [p_name, b_name, mult_text])
	if result.trap_triggered and result.trap_data:
		if result.trap_data.is_bluff:
			_add_log("  [color=gray]  → 陷阱翻开: 虚张声势[/color]")
		else:
			_add_log("  [color=yellow]  → ⚡陷阱触发: %s[/color]" % result.trap_data.trap_name)
	# v0.4.3 hotfix-4：次要效果播报（抽牌/护甲/回复/绑定 0 费）。
	# 之前这些效果"默默生效"，玩家在翻牌结束后才能看到手牌变化，
	# 容易误以为"抽牌效果没实现"。这里把每种效果都打到日志，并标注绑定加成。
	_log_secondary_effects(result)

func _log_secondary_effects(result: ClashResolver.ClashResult) -> void:
	if result.player_card != null and result.player_multiplier > 0:
		_log_card_secondary("你", result.player_card, result.player_bound_zero, result.player_multiplier)
	if result.boss_card != null and result.boss_multiplier > 0:
		# Boss 牌目前没有绑定 0 费机制，传 null
		_log_card_secondary("Boss", result.boss_card, null, result.boss_multiplier)


func _log_card_secondary(actor: String, card: CardData, bound_zero: CardData, multiplier: float) -> void:
	## 把一张牌（含绑定 0 费）的"非伤害类"效果打到战斗日志。
	## 数值已应用倍率，与 _resolve_card_with_multiplier 的实际结算保持一致。
	var draw: int = card.draw_cards
	var armor: int = card.armor
	var heal: int = card.heal
	if bound_zero != null:
		draw += bound_zero.draw_cards
		armor += bound_zero.armor
		heal += bound_zero.heal
	# 应用倍率（apply_multiplier_int 在 ClashResolver 中是公共静态方法）
	var draw_final: int = ClashResolver.apply_multiplier_int(draw, multiplier) if draw > 0 else 0
	var armor_final: int = ClashResolver.apply_multiplier_int(armor, multiplier) if armor > 0 else 0
	var heal_final: int = ClashResolver.apply_multiplier_int(heal, multiplier) if heal > 0 else 0
	var bind_tag: String = " (含绑定 %s)" % bound_zero.card_name if bound_zero != null else ""
	if draw_final > 0:
		_add_log("  [color=#7cf]  → %s 抽到 %d 张牌%s[/color]" % [actor, draw_final, bind_tag])
	if armor_final > 0:
		_add_log("  [color=#bdf]  → %s 获得 %d 护甲%s[/color]" % [actor, armor_final, bind_tag])
	if heal_final > 0:
		_add_log("  [color=#9f9]  → %s 回复 %d 生命%s[/color]" % [actor, heal_final, bind_tag])

	# v0.4.3 hotfix-6：补播报"下回合修正类"效果（抽牌/能量），避免玩家误以为是"持续生效"。
	# 这些字段实际只生效一回合（_round_start 会消费并清零），但之前没有任何 log，
	# 玩家看到"我又少抽一张"会以为是上回合的效果还在 —— 实际是新一回合 Boss 又出了一张同类牌。
	var opponent: String = "Boss" if actor == "你" else "你"
	# 对手抽牌修正
	var ed_base: int = card.enemy_draw_modifier
	if bound_zero != null:
		ed_base += bound_zero.enemy_draw_modifier
	if ed_base != 0:
		var ed_final: int = ClashResolver.apply_multiplier_int(ed_base, multiplier)
		if ed_final != 0:
			_add_log("  [color=#fa7]  → %s 下回合抽牌 %+d（仅一回合）[/color]" % [opponent, ed_final])
	# 对手能量修正
	var ee_base: int = card.enemy_energy_modifier
	if bound_zero != null:
		ee_base += bound_zero.enemy_energy_modifier
	if ee_base != 0:
		var ee_final: int = ClashResolver.apply_multiplier_int(ee_base, multiplier)
		if ee_final != 0:
			_add_log("  [color=#fa7]  → %s 下回合能量 %+d（仅一回合）[/color]" % [opponent, ee_final])
	# 自身下回合能量
	var en_base: int = card.energy_next_turn
	if en_base != 0:
		var en_final: int = ClashResolver.apply_multiplier_int(en_base, multiplier)
		if en_final != 0:
			_add_log("  [color=#9cf]  → %s 下回合能量 %+d（仅一回合）[/color]" % [actor, en_final])



func _on_clash_animation_done() -> void:
	# 碰撞动画完毕 → 进入认知结算
	if battle.current_phase != BlindClashBattle.Phase.BATTLE_OVER:
		battle.advance_to_end_round()

func _on_probe_phase() -> void:
	phase_label.text = "认知结算"

func _on_probe_prediction(predicted_type: String) -> void:
	probe_display.show_prediction(predicted_type)
	var type_names := {"attack": "攻击", "defense": "防御", "skill": "技能"}
	_add_log("[color=magenta][探针] Boss预判你主打: %s[/color]" % type_names.get(predicted_type, "?"))

func _on_probe_result(correct: bool, streak: int, total: int) -> void:
	probe_display.show_result(correct, streak, total)
	if correct:
		_add_log("[color=red][探针] Boss猜对了！连续%d 累计%d[/color]" % [streak, total])
	else:
		_add_log("[color=green][探针] Boss猜错了[/color]")

func _on_probe_jam_requested() -> void:
	battle.jam_probe()
	probe_display.show_jammed()
	_add_log("[color=yellow][探针] 你干扰了Boss的探针！[/color]")

func _on_insight_effect(effect_type: String, card: CardData) -> void:
	# v0.4.3：本回合 PROBE 宣告 — 播放戏剧化演出 + 顶部 banner 持续提示
	# 真实落地（牌库/手牌操作）会在下回合 ROUND_START 由 _on_insight_applied 处理
	probe_display.show_insight_effect(effect_type, card)
	match effect_type:
		"peek":
			_add_log("[color=#00e5ff]⚠ Boss 将偷看 你的: %s（下回合开局）[/color]" % card.card_name)
		"disrupt":
			_add_log("[color=#ff2a2a]⚠⚠ Boss 将锁定 你的: %s — 下回合不可使用[/color]" % card.card_name)
		"seize":
			_add_log("[color=#ff1144]⚠⚠⚠ Boss 将夺取 你的: %s — 永久失去！[/color]" % card.card_name)

	# 找到对应的手牌 UI（常驻手牌 hand_display 是当前可见的）
	var card_ui_node: Node = _find_hand_card_ui(card)
	var boss_pos: Vector2 = _get_boss_world_pos()
	# 添加 banner 条目（先加，演出过程中也可见）
	_pending_banner_add(effect_type, card)
	# 播放对应宣告动画（若找到 card_ui，没找到则跳过演出仅写日志）
	if card_ui_node != null:
		match effect_type:
			"peek":
				probe_display.play_peek_announcement(card_ui_node, boss_pos)
			"disrupt":
				probe_display.play_disrupt_announcement(card_ui_node, boss_pos)
			"seize":
				probe_display.play_seize_announcement(card_ui_node, boss_pos)
				if battle_effects:
					battle_effects.shake_camera(0.25, 0.4)


# v0.4.3：洞察"真正落地"信号（下回合 ROUND_START）
# peek/disrupt 在手牌上打持续标记；seize 已在 battle 内部物理移除，这里仅刷新 + banner 移除
func _on_insight_applied(effect_type: String, card: CardData) -> void:
	# 根据效果类型，给当前手牌 UI 打持续标记 / 触发刷新
	match effect_type:
		"peek":
			# 找到当前 hand_display 中对应的牌 UI（_refresh_hand_display 已重建过）
			var ui: Node = _find_hand_card_ui(card)
			if ui != null and ui.has_method("set_peeked"):
				ui.set_peeked(true)
			_add_log("[color=#00e5ff]✦ Boss 偷看了 你的: %s（信息已泄露）[/color]" % card.card_name)
		"disrupt":
			var ui2: Node = _find_hand_card_ui(card)
			if ui2 != null and ui2.has_method("set_disrupted"):
				ui2.set_disrupted(true)
			_add_log("[color=#ff2a2a]✦ Boss 锁定了 你的: %s（本回合不可使用）[/color]" % card.card_name)
		"seize":
			# 牌已被移除，常驻手牌已通过 hand_changed 信号刷新
			_refresh_hand_display.call_deferred()
			_add_log("[color=#ff1144]✦ Boss 夺走了 你的: %s（已并入 Boss 牌库）[/color]" % card.card_name)
	# banner 移除该条
	_pending_banner_remove(effect_type, card)


func _find_hand_card_ui(card: CardData) -> Node:
	# 优先查 BlindSelectUI（如果它正在显示）
	if blind_select.visible:
		# blind_select 内部 _hand_cards 私有，借用 hand_area 节点直接遍历
		var blind_hand_area: Node = blind_select.get_node_or_null("VBox/HandArea")
		if blind_hand_area != null:
			for child in blind_hand_area.get_children():
				if child is Control and child.get("card_data") == card:
					return child
	# 然后查常驻 hand_display
	for child in hand_display.get_children():
		if child is Control and child.get("card_data") == card:
			return child
	return null


# v0.4.2 Boss 加强：streak==2 时随机三选一的"洞察预告"
# 当前阶段仅写战斗日志，不应用真实效果（逻辑实装待后续 ADR）。
# 视觉上让玩家更早感受到 Boss 的认知压力。
func _on_insight_random_triggered(effect_type: String) -> void:
	var label_map := {
		"peek": "窥视",
		"disrupt": "干扰",
		"seize": "夺取",
	}
	var label: String = label_map.get(effect_type, effect_type)
	# 紫色（区分于上面 peek/disrupt/seize 的真效果颜色）+ 标注"预告·未生效"
	_add_log("[color=#cc66ff]✦ [洞察觉醒] Boss 触发随机洞察 → %s（预告·效果待实装）[/color]" % label)

func _on_trap_triggered(trap: TrapData, triggered_by: CardData) -> void:
	if battle_effects:
		var screen_center: Vector2 = get_viewport().get_visible_rect().size / 2.0
		if trap.is_bluff:
			battle_effects.spawn_text_effect(screen_center - Vector2(140, 40), "虚张声势！", Color(0.6, 0.6, 0.6), 40)
		else:
			battle_effects.spawn_text_effect(screen_center - Vector2(140, 40), "⚡ %s" % trap.trap_name, Color(1.0, 0.85, 0.2), 48)
			battle_effects.shake_camera(0.12, 0.25)

func _on_probe_display_done() -> void:
	pass  # 认知结算显示完毕，回合结束已由 advance_to_end_round 处理

func _on_round_ended(round_num: int) -> void:
	_add_log("[color=gray]— 回合 %d 结束 —[/color]" % round_num)

func _on_battle_ended(player_won: bool) -> void:
	phase_label.text = "战斗结束"
	if player_won:
		_add_log("[color=green]★ 胜利！Boss 已击溃 ★[/color]")
	else:
		_add_log("[color=red]✖ 失败... 系统重启 ✖[/color]")


# ===== Combatant UI 更新 =====

func _get_player_panel_center() -> Vector2:
	return player_panel.global_position + player_panel.size / 2.0

func _get_boss_panel_center() -> Vector2:
	return boss_panel.global_position + boss_panel.size / 2.0

func _on_player_hp_changed(new_hp: int, max_hp: int) -> void:
	player_panel.set_hp(new_hp, max_hp)
	var diff: int = _player_prev_hp - new_hp
	if diff > 0 and battle_effects:
		battle_effects.spawn_damage_number(_get_player_panel_center(), diff, Color(1.0, 0.3, 0.3))
		battle_effects.shake_camera(0.08, 0.25)
	elif diff < 0 and battle_effects:
		battle_effects.spawn_healing_number(_get_player_panel_center(), -diff)
	_player_prev_hp = new_hp

func _on_player_armor_changed(new_armor: int) -> void:
	player_panel.set_armor(new_armor)

func _on_player_energy_changed(new_energy: int) -> void:
	player_panel.set_energy(new_energy)

func _on_player_hand_changed() -> void:
	# 用 call_deferred 让容器先完成布局再刷新手牌位置
	_refresh_hand_display.call_deferred()
	_update_constraint_panel()


func _refresh_hand_display() -> void:
	## 常驻手牌扇形居中显示
	for child in hand_display.get_children():
		child.queue_free()
	if battle.player == null:
		return

	var hand: Array[CardData] = battle.player.hand
	var count: int = hand.size()
	if count == 0:
		return

	var area_width: float = hand_display.size.x if hand_display.size.x > 100.0 else 1200.0
	var total_width: float = (count - 1) * HAND_SPACING
	var start_x: float = (area_width - total_width) / 2.0
	var center_idx: float = (count - 1) / 2.0

	for i in range(count):
		# 扇形位置
		var x: float = start_x + i * HAND_SPACING
		var y_offset: float = abs(i - center_idx) * HAND_ARC_HEIGHT
		var angle: float = (i - center_idx) * HAND_FAN_ANGLE
		var base_pos := Vector2(x, y_offset)

		var card_ui := Control.new()
		card_ui.set_script(CardUI)
		card_ui.setup(hand[i], base_pos)
		card_ui.rotation_degrees = angle
		hand_display.add_child(card_ui)
		# v0.4.3：常驻手牌也要展示 peek/disrupted 持续标记
		if battle.peeked_cards.has(hand[i]) and card_ui.has_method("set_peeked"):
			card_ui.set_peeked(true)
		if battle.disrupted_cards.has(hand[i]) and card_ui.has_method("set_disrupted"):
			card_ui.set_disrupted(true)

	# 标记已暗出的牌（加阴影）
	_mark_blind_cards_in_hand()


func _mark_blind_cards_in_hand() -> void:
	## 在暗出阶段，已选入暗出区的牌在常驻手牌中不再显示（它们已从hand移除）
	## 这里是给对决阶段后剩余手牌做辨识用——不需要额外处理
	## 阴影标记在 BlindSelectUI 的暗出区实现
	pass


func _update_constraint_panel() -> void:
	constraint_count_label.text = "◆ %d" % battle.constraint_resource
	trap_count_label.text = "剩余 %d 张" % battle.trap_inventory.size()

func _on_boss_hp_changed(new_hp: int, max_hp: int) -> void:
	boss_panel.set_hp(new_hp, max_hp)
	var diff: int = _boss_prev_hp - new_hp
	if diff > 0 and battle_effects:
		battle_effects.spawn_damage_number(_get_boss_panel_center(), diff, Color(1.0, 0.5, 0.2))
	elif diff < 0 and battle_effects:
		battle_effects.spawn_healing_number(_get_boss_panel_center(), -diff)
	_boss_prev_hp = new_hp

func _on_boss_armor_changed(new_armor: int) -> void:
	boss_panel.set_armor(new_armor)


# ===== 日志 =====

func _add_log(text: String) -> void:
	log_label.append_text(text + "\n")


# ============================================================
# v0.4.3 PendingInsightsBanner — 顶部持续提示"下回合开局：Boss 将…"
# ============================================================

func _setup_pending_banner() -> void:
	# 居于屏幕上方 80 像素处，左右居中，宽度自适应
	_pending_banner = VBoxContainer.new()
	_pending_banner.name = "PendingInsightsBanner"
	_pending_banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_pending_banner.offset_top = 80.0
	_pending_banner.offset_left = 0.0
	_pending_banner.offset_right = 0.0
	_pending_banner.alignment = BoxContainer.ALIGNMENT_CENTER
	_pending_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pending_banner.z_index = 50
	$UI/UIRoot.add_child(_pending_banner)


func _pending_banner_add(effect_type: String, card: CardData) -> void:
	if card == null:
		return
	# 防重复添加（同一 effect+card 已在 banner 中则跳过）
	for entry in _pending_banner_entries:
		if entry["type"] == effect_type and entry["card"] == card:
			return
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	var text: String = ""
	var color: Color = Color.WHITE
	match effect_type:
		"peek":
			text = "⚠ 下回合开局：Boss 将偷看 [%s]" % card.card_name
			color = Color(0.0, 0.9, 1.0)
		"disrupt":
			text = "⛓ 下回合开局：Boss 将锁定 [%s] — 下回合不可使用" % card.card_name
			color = Color(1.0, 0.16, 0.16)
		"seize":
			text = "☠ 下回合开局：Boss 将夺取 [%s] — 永久失去" % card.card_name
			color = Color(0.95, 0.1, 0.4)
	label.text = text
	label.add_theme_color_override("font_color", color)
	# 简单背景：用 PanelContainer 包一下做半透明黑底
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_banner_style(color))
	panel.add_child(label)
	_pending_banner.add_child(panel)
	# 出现动画：modulate 0->1 + Y 上滑 -10
	panel.modulate.a = 0.0
	var t := create_tween()
	t.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(panel, "modulate:a", 1.0, 0.35)
	_pending_banner_entries.append({"type": effect_type, "card": card, "node": panel})


func _pending_banner_remove(effect_type: String, card: CardData) -> void:
	for i in range(_pending_banner_entries.size() - 1, -1, -1):
		var entry: Dictionary = _pending_banner_entries[i]
		if entry["type"] == effect_type and entry["card"] == card:
			var node: Control = entry["node"]
			# 淡出 + 自销毁
			var t := create_tween()
			t.tween_property(node, "modulate:a", 0.0, 0.3)
			t.tween_callback(func() -> void:
				if is_instance_valid(node):
					node.queue_free()
			)
			_pending_banner_entries.remove_at(i)


func _make_banner_style(accent: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.08, 0.85)
	sb.border_color = accent
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	sb.shadow_color = accent * Color(1, 1, 1, 0.4)
	sb.shadow_size = 4
	return sb


# ===== 开发模式快捷键 =====

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed:
		# v0.4.3：洞察效果调试 — Ctrl+1/2/3（避免与 Godot 编辑器/系统占用的 F7-F9 冲突）
		# 仅在 ctrl 真按下时触发；其他无修饰的 KEY_1 等正常字符输入不受影响。
		if event.ctrl_pressed and not event.alt_pressed and not event.shift_pressed and not event.meta_pressed:
			match event.keycode:
				KEY_1:
					_debug_trigger_insight("peek")
					get_viewport().set_input_as_handled()
					return
				KEY_2:
					_debug_trigger_insight("disrupt")
					get_viewport().set_input_as_handled()
					return
				KEY_3:
					_debug_trigger_insight("seize")
					get_viewport().set_input_as_handled()
					return
		match event.keycode:
			KEY_F12:
				battle.debug_kill_boss()
				_add_log("[DEBUG] Boss 秒杀")
			KEY_F4:
				battle.debug_god_mode = not battle.debug_god_mode
				_add_log("[DEBUG] 无敌模式: %s" % str(battle.debug_god_mode))
			KEY_F5:
				battle.debug_infinite_energy = not battle.debug_infinite_energy
				_add_log("[DEBUG] 无限能量: %s" % str(battle.debug_infinite_energy))
			KEY_F6:
				battle.debug_fill_constraints()
				_add_log("[DEBUG] 约束资源已填满")


func _debug_trigger_insight(effect_type: String) -> void:
	# v0.4.3：调试触发洞察 — 让 UI 直接指定 hand_idx，避免 random 选完后再用 CardData
	# 引用回查时拿到错牌；同时演出完成后短暂延迟自动落地，banner 才会消失。
	if battle.player == null or battle.player.hand.is_empty():
		_add_log("[color=#ff8866][DEBUG] 触发失败：玩家手牌为空[/color]")
		return
	var idx: int = randi() % battle.player.hand.size()
	var target_card: CardData = battle.debug_trigger_insight(effect_type, idx)
	if target_card == null:
		_add_log("[color=#ff8866][DEBUG] 触发失败：类型非法[/color]")
		return
	var label_map := {"peek": "窥视", "disrupt": "干扰", "seize": "夺取"}
	var label_text: String = label_map.get(effect_type, effect_type)
	_add_log("[color=#cc66ff][DEBUG] 强行触发洞察 → %s · 目标: [%s][/color]" % [label_text, target_card.card_name])
	# 演出已通过 insight_effect 信号自动播放（_on_insight_effect）。
	# 在动画播完 + 看清效果后自动 apply，让 banner 自然消失，便于反复审核。
	# 总时长 ≈ 宣告动画(1.2~2.0s) + 缓冲(1.5s) ≈ 3.5s
	await get_tree().create_timer(3.5).timeout
	if is_instance_valid(self) and battle != null:
		battle.debug_apply_pending_insights()
