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
	_connect_signals()
	_setup_battle()


func _setup_battle() -> void:
	var card_db: Node = get_node("/root/CardDatabase")
	var player_deck: Array[CardData] = card_db.get_player_starter_deck()
	var boss_deck: Array[CardData] = card_db.get_boss_layer1_deck()
	var traps: Array[TrapData] = card_db.get_initial_traps()

	var player := Combatant.new("NULL", 60, player_deck)
	var boss := Combatant.new("回响", 55, boss_deck)

	# 初始化血条面板
	player_panel.setup("NULL", 60, false)
	boss_panel.setup("回响", 55, true)

	# 连接 Combatant 信号
	player.hp_changed.connect(_on_player_hp_changed)
	player.armor_changed.connect(_on_player_armor_changed)
	player.energy_changed.connect(_on_player_energy_changed)
	player.hand_changed.connect(_on_player_hand_changed)
	boss.hp_changed.connect(_on_boss_hp_changed)
	boss.armor_changed.connect(_on_boss_armor_changed)

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
	_add_log("[color=green]战斗开始: NULL vs 回响 — 暗出对决模式[/color]")

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
	# 显示Boss暗出张数
	boss_count_label.text = "Boss暗出: %d 张" % battle.boss_blind_cards.size()
	boss_count_label.visible = true
	# 隐藏常驻手牌（BlindSelectUI有自己的手牌显示）
	hand_display.visible = false
	# 激活暗出选牌UI
	blind_select.activate(battle.player.hand, battle.player.energy, battle.disrupted_cards)

func _on_blind_confirmed(cards: Array[CardData], bound_zeros: Dictionary) -> void:
	var success: bool = battle.set_player_blind_cards(cards, bound_zeros)
	if success:
		_add_log("你暗出了 %d 张牌" % cards.size())
		boss_count_label.visible = false
		# 恢复常驻手牌显示
		hand_display.visible = true
		_refresh_hand_display()
		_update_constraint_panel()
		battle.confirm_blind()
	else:
		# 验证失败，重新激活
		blind_select.activate(battle.player.hand, battle.player.energy, battle.disrupted_cards)

func _on_clash_phase() -> void:
	phase_label.text = "对决阶段"
	_add_log("[color=red]▶ 对决阶段：逐张翻开！[/color]")
	# 执行碰撞结算
	var results: Array[ClashResolver.ClashResult] = battle.resolve_all_clashes()
	# 启动翻牌动画
	clash_display.start_clash_animation(results)

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
	probe_display.show_insight_effect(effect_type, card)
	match effect_type:
		"peek":
			_add_log("[color=orange]⚠ Boss窥视了你的: %s[/color]" % card.card_name)
		"disrupt":
			_add_log("[color=red]⚠ Boss干扰了: %s (下回合不可用)[/color]" % card.card_name)
		"seize":
			_add_log("[color=red]⚠⚠⚠ Boss夺取了: %s！[/color]" % card.card_name)

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


# ===== 开发模式快捷键 =====

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
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
