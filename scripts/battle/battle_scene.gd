extends Control
## 战斗场景主控 — 连接 UI 与 BattleManager

@onready var battle_manager: BattleManager = $BattleManager
@onready var player_panel: PanelContainer = $UI/UIRoot/PlayerPanel
@onready var boss_panel: PanelContainer = $UI/UIRoot/BossPanel
@onready var constraint_badge: Label = $UI/UIRoot/PlayerPanel/ConstraintBadge
@onready var hand_display: Control = $UI/UIRoot/HandDisplay
@onready var constraint_display: HBoxContainer = $UI/UIRoot/ConstraintDisplay
@onready var log_label: RichTextLabel = $UI/UIRoot/LogPanel/LogText
@onready var end_turn_btn: Button = $UI/UIRoot/EndTurnButton
@onready var turn_label: Label = $UI/UIRoot/TurnLabel
@onready var view_boss_deck_btn: Button = $UI/UIRoot/ViewBossDeckButton
@onready var boss_deck_popup: PanelContainer = $UI/UIRoot/BossDeckPopup
@onready var intent_display: Control = $UI/UIRoot/IntentDisplay
@onready var battle_effects: Node = $BattleEffects
@onready var fx_layer: Control = $UI/UIRoot/FxLayer

var ai: RuleAI = RuleAI.new()


func _ready() -> void:
	# 应用赛博朋克暗色主题
	var CyberTheme := preload("res://scripts/ui/cyber_theme.gd")
	CyberTheme.apply_theme_to_tree($UI/UIRoot)
	# 初始化特效管理器（关联 3D 摄像机）
	var cam_3d: Camera3D = get_node_or_null("Background3D/SubViewport/Scene/Camera3D")
	battle_effects.setup(fx_layer, cam_3d)
	_setup_battle()
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	view_boss_deck_btn.pressed.connect(_on_view_boss_deck_pressed)
	hand_display.card_played.connect(_on_card_button_pressed)
	boss_deck_popup.visible = false
	boss_deck_popup.get_node("VBox/Header/CloseBtn").pressed.connect(func(): boss_deck_popup.visible = false)
	# 开发快捷键
	set_process_input(true)


func _setup_battle() -> void:
	var card_db: Node = get_node("/root/CardDatabase")
	var player_deck: Array[CardData] = card_db.get_player_starter_deck()
	var boss_deck: Array[CardData] = card_db.get_boss_layer1_deck()
	var constraints: Array[ConstraintData] = card_db.get_initial_constraints()

	var player := Combatant.new("NULL", 60, player_deck)
	var boss := Combatant.new("回响", 55, boss_deck)

	# 初始化血条面板
	player_panel.setup("NULL", 60, false)
	boss_panel.setup("回响", 55, true)

	# 连接信号
	player.hp_changed.connect(_on_player_hp_changed)
	player.armor_changed.connect(_on_player_armor_changed)
	player.energy_changed.connect(_on_player_energy_changed)
	player.hand_changed.connect(_on_player_hand_changed)
	boss.hp_changed.connect(_on_boss_hp_changed)
	boss.armor_changed.connect(_on_boss_armor_changed)
	boss.energy_changed.connect(_on_boss_energy_changed)

	battle_manager.battle_started.connect(_on_battle_started)
	battle_manager.player_phase_started.connect(_on_player_phase_started)
	battle_manager.boss_phase_started.connect(_on_boss_phase_started)
	battle_manager.card_played.connect(_on_card_played)
	battle_manager.constraint_used.connect(_on_constraint_used)
	battle_manager.turn_started.connect(_on_turn_started)
	battle_manager.battle_ended.connect(_on_battle_ended)
	battle_manager.boss_intent_ready.connect(_on_boss_intent_ready)

	battle_manager.start_battle(player, boss, constraints)


# ===== UI 更新 =====

var _player_prev_hp: int = 60
var _boss_prev_hp: int = 55
var _player_prev_armor: int = 0
var _boss_prev_armor: int = 0

func _get_player_panel_center() -> Vector2:
	return player_panel.global_position + player_panel.size / 2.0

func _get_boss_panel_center() -> Vector2:
	return boss_panel.global_position + boss_panel.size / 2.0

func _on_player_hp_changed(new_hp: int, max_hp: int) -> void:
	player_panel.set_hp(new_hp, max_hp)
	var diff: int = _player_prev_hp - new_hp
	if diff > 0:
		battle_effects.spawn_damage_number(_get_player_panel_center(), diff, Color(1.0, 0.3, 0.3))
		battle_effects.shake_camera(0.08, 0.25)
	elif diff < 0:
		battle_effects.spawn_healing_number(_get_player_panel_center(), -diff)
	_player_prev_hp = new_hp

func _on_player_armor_changed(new_armor: int) -> void:
	player_panel.set_armor(new_armor)
	var diff: int = new_armor - _player_prev_armor
	if diff > 0:
		battle_effects.spawn_armor_number(_get_player_panel_center() + Vector2(0, -20), diff)
	_player_prev_armor = new_armor

func _on_player_energy_changed(new_energy: int) -> void:
	player_panel.set_energy(new_energy)

func _on_boss_hp_changed(new_hp: int, max_hp: int) -> void:
	boss_panel.set_hp(new_hp, max_hp)
	var diff: int = _boss_prev_hp - new_hp
	if diff > 0:
		battle_effects.spawn_damage_number(_get_boss_panel_center(), diff, Color(1.0, 0.5, 0.2))
	elif diff < 0:
		battle_effects.spawn_healing_number(_get_boss_panel_center(), -diff)
	_boss_prev_hp = new_hp

func _on_boss_armor_changed(new_armor: int) -> void:
	boss_panel.set_armor(new_armor)
	var diff: int = new_armor - _boss_prev_armor
	if diff > 0:
		battle_effects.spawn_armor_number(_get_boss_panel_center() + Vector2(0, -20), diff)
	_boss_prev_armor = new_armor

func _on_boss_energy_changed(new_energy: int) -> void:
	boss_panel.set_energy(new_energy)

func _on_player_hand_changed() -> void:
	hand_display.display_hand(battle_manager.player.hand)
	_update_constraint_buttons()

func _on_player_phase_started() -> void:
	end_turn_btn.disabled = false
	constraint_badge.text = "约束: %d" % battle_manager.constraint_resource
	_add_log("[color=cyan]— 你的回合 —[/color]")

func _on_boss_phase_started() -> void:
	end_turn_btn.disabled = true
	intent_display.hide_intent()
	_add_log("[color=red]— Boss 回合 —[/color]")
	await get_tree().create_timer(0.3).timeout
	# 使用玩家回合开始时预判的 actions
	var actions: Array[CardData] = battle_manager.boss.pending_actions
	# 如果约束令改变了状态（如新增了约束），让 AI 重新决策以反映真实可打出的牌
	# 简化处理：直接用预判结果，执行时会检查约束
	for card in actions:
		if battle_manager.current_phase == BattleManager.Phase.BATTLE_OVER:
			return
		var success: bool = battle_manager.execute_boss_action(card)
		if success:
			await get_tree().create_timer(0.6).timeout
		else:
			await get_tree().create_timer(0.2).timeout
	if battle_manager.current_phase != BattleManager.Phase.BATTLE_OVER:
		await get_tree().create_timer(0.3).timeout
		battle_manager.finish_boss_turn()


func _on_boss_intent_ready(intent: BossIntent) -> void:
	intent_display.show_intent(intent)

func _on_card_played(who: String, card: CardData) -> void:
	var effect_text: String = _get_card_effect_text(card)
	if who == "boss_blocked":
		_add_log("[color=yellow][Boss] %s → ⚡已阻止（效果无效）[/color]" % card.card_name)
		# 屏幕中央文字 + 震屏
		var screen_center: Vector2 = get_viewport().get_visible_rect().size / 2.0
		battle_effects.spawn_text_effect(screen_center - Vector2(180, 40), "⚡ 约束生效", Color(1.0, 0.85, 0.2), 52)
		battle_effects.shake_camera(0.15, 0.3)
		return
	var tag: String = "[你]" if who == "player" else "[Boss]"
	var color: String = "white" if who == "player" else "orange"
	_add_log("[color=%s]%s %s → %s[/color]" % [color, tag, card.card_name, effect_text])


func _get_card_effect_text(card: CardData) -> String:
	var parts: Array[String] = []
	if card.damage > 0:
		if card.hits > 1:
			parts.append("%d伤害×%d" % [card.damage, card.hits])
		else:
			parts.append("%d伤害" % card.damage)
		if card.ignore_armor:
			parts[-1] += "(穿甲)"
	if card.armor > 0:
		parts.append("%d护甲" % card.armor)
	if card.heal > 0:
		parts.append("回复%d" % card.heal)
	if card.draw_cards > 0:
		parts.append("抽%d张" % card.draw_cards)
	if card.grants_charge:
		parts.append("进入蓄力")
	if card.requires_charge:
		parts.append("(蓄力释放)")
	if card.next_attack_bonus > 0:
		parts.append("下次攻击+%d" % card.next_attack_bonus)
	if card.all_attack_bonus > 0:
		parts.append("全攻击+%d" % card.all_attack_bonus)
	if card.energy_next_turn > 0:
		parts.append("下回合能量+%d" % card.energy_next_turn)
	if card.enemy_draw_modifier < 0:
		parts.append("对手抽牌%d" % card.enemy_draw_modifier)
	if card.enemy_energy_modifier < 0:
		parts.append("对手能量%d" % card.enemy_energy_modifier)
	if card.discard_hand_and_draw > 0:
		parts.append("弃手牌抽%d张" % card.discard_hand_and_draw)
	if card.gain_constraint_resource > 0:
		parts.append("+%d约束" % card.gain_constraint_resource)
	if parts.is_empty():
		return card.description
	return ", ".join(parts)

func _on_constraint_used(constraint: ConstraintData) -> void:
	_add_log("[color=yellow]>>> 约束令: %s[/color]" % constraint.constraint_name)
	constraint_badge.text = "约束: %d" % battle_manager.constraint_resource

func _on_turn_started(turn_number: int) -> void:
	turn_label.text = "回合 %d" % turn_number

func _on_battle_started() -> void:
	_add_log("[color=green]战斗开始: NULL vs 回响[/color]")
	_on_player_hp_changed(60, 60)
	_on_boss_hp_changed(55, 55)

func _on_battle_ended(player_won: bool) -> void:
	end_turn_btn.disabled = true
	if player_won:
		_add_log("[color=green]★ 胜利！Boss 已击溃 ★[/color]")
		await get_tree().create_timer(1.0).timeout
		_start_reward_phase()
	else:
		_add_log("[color=red]✖ 失败... 系统重启 ✖[/color]")


# ===== 交互 =====

func _on_card_button_pressed(card: CardData) -> void:
	battle_manager.player_play_card(card)

func _on_end_turn_pressed() -> void:
	battle_manager.player_end_turn()

func _on_view_boss_deck_pressed() -> void:
	boss_deck_popup.visible = not boss_deck_popup.visible
	if boss_deck_popup.visible:
		_populate_boss_deck_popup()

func _populate_boss_deck_popup() -> void:
	var container: VBoxContainer = boss_deck_popup.get_node("ScrollContainer/DeckList")
	for child in container.get_children():
		child.queue_free()
	# 按类型分组显示 Boss 完整牌库
	var deck: Array[CardData] = battle_manager.boss.full_deck
	var type_names: Dictionary = {
		CardData.CardType.ATTACK: "[color=red]攻击[/color]",
		CardData.CardType.DEFENSE: "[color=cyan]防御[/color]",
		CardData.CardType.SKILL: "[color=green]技能[/color]",
		CardData.CardType.PROTOCOL: "[color=yellow]协议[/color]",
	}
	# 统计每张牌出现次数
	var card_counts: Dictionary = {}
	for card in deck:
		if card.id in card_counts:
			card_counts[card.id]["count"] += 1
		else:
			card_counts[card.id] = {"card": card, "count": 1}
	# 显示
	for id in card_counts:
		var entry: Dictionary = card_counts[id]
		var card: CardData = entry["card"]
		var lbl := RichTextLabel.new()
		lbl.bbcode_enabled = true
		lbl.fit_content = true
		lbl.custom_minimum_size.y = 22
		lbl.text = "%s  %s ×%d  [能量%d] %s" % [
			type_names.get(card.type, ""),
			card.card_name,
			entry["count"],
			card.energy_cost,
			card.description,
		]
		container.add_child(lbl)

func _on_constraint_button_pressed(constraint: ConstraintData) -> void:
	battle_manager.player_use_constraint(constraint)
	_update_constraint_buttons()

func _update_constraint_buttons() -> void:
	for child in constraint_display.get_children():
		child.queue_free()
	for constraint in battle_manager.constraints_inventory:
		var card_ui := ConstraintCardUI.new()
		card_ui.setup(constraint, constraint.resource_cost <= battle_manager.constraint_resource)
		card_ui.constraint_clicked.connect(_on_constraint_button_pressed)
		constraint_display.add_child(card_ui)


func _add_log(text: String) -> void:
	log_label.append_text(text + "\n")


# ===== 层间奖励 =====

var _reward_round: int = 0
var _reward_pool: Array[CardData] = []
@onready var reward_screen: Control = $UI/UIRoot/RewardScreen

func _start_reward_phase() -> void:
	var card_db: Node = get_node("/root/CardDatabase")
	# 获取全部 6 张奖励牌
	var all_rewards: Array[CardData] = []
	for id in [&"reward_chain", &"reward_core", &"reward_adapt", &"reward_reflect", &"reward_predict", &"reward_siphon"]:
		all_rewards.append(card_db.get_card(id).duplicate())
	all_rewards.shuffle()
	_reward_pool = all_rewards
	_reward_round = 1
	_show_next_reward_pick()


func _show_next_reward_pick() -> void:
	# 每次展示 3 张
	var start_idx: int = (_reward_round - 1) * 3
	var pick: Array[CardData] = []
	for i in range(start_idx, mini(start_idx + 3, _reward_pool.size())):
		pick.append(_reward_pool[i])
	reward_screen.show_rewards(pick, _reward_round)
	# 连接一次性信号
	if not reward_screen.card_chosen.is_connected(_on_reward_card_chosen):
		reward_screen.card_chosen.connect(_on_reward_card_chosen)
	if not reward_screen.skipped.is_connected(_on_reward_skipped):
		reward_screen.skipped.connect(_on_reward_skipped)


func _on_reward_card_chosen(card: CardData) -> void:
	# 加入玩家牌组
	battle_manager.player.deck.append(card)
	battle_manager.player.full_deck.append(card)
	_add_log("[color=green]+ 获得: %s[/color]" % card.card_name)
	_advance_reward()


func _on_reward_skipped() -> void:
	_add_log("[color=gray]跳过奖励[/color]")
	_advance_reward()


func _advance_reward() -> void:
	if _reward_round < 2:
		_reward_round += 1
		await get_tree().create_timer(0.3).timeout
		_show_next_reward_pick()
	else:
		_add_log("[color=cyan]层间结束。准备下一场...[/color]")
		# TODO: 启动下一层 Boss 战


# ===== 开发模式快捷键 =====

func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F12:
				battle_manager.debug_kill_boss()
				_add_log("[DEBUG] Boss 秒杀")
			KEY_F4:
				battle_manager.debug_god_mode = not battle_manager.debug_god_mode
				_add_log("[DEBUG] 无敌模式: %s" % str(battle_manager.debug_god_mode))
			KEY_F5:
				battle_manager.debug_infinite_energy = not battle_manager.debug_infinite_energy
				_add_log("[DEBUG] 无限能量: %s" % str(battle_manager.debug_infinite_energy))
			KEY_F6:
				battle_manager.debug_fill_constraints()
				_add_log("[DEBUG] 约束资源已填满")
				_update_constraint_buttons()
