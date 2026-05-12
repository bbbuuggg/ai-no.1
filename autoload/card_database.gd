extends Node
## CardDatabase — 全局卡牌数据库（Autoload）
## 在此定义所有卡牌，避免依赖 .tres 文件（原型阶段）

var all_cards: Dictionary = {}  # id -> CardData
var all_traps: Dictionary = {}  # id -> TrapData


func _ready() -> void:
	_register_player_cards()
	_register_boss_layer1_cards()
	_register_reward_cards()
	_register_trap_cards()


func get_card(id: StringName) -> CardData:
	return all_cards.get(id, null)


func get_player_starter_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	deck.append_array(_copies(&"atk_pulse", 4))
	deck.append_array(_copies(&"atk_precise", 2))
	deck.append_array(_copies(&"atk_overload", 1))
	deck.append_array(_copies(&"atk_arc", 1))
	deck.append_array(_copies(&"def_firewall", 4))
	deck.append_array(_copies(&"def_emergency", 2))
	deck.append_array(_copies(&"def_fullguard", 1))
	deck.append_array(_copies(&"skl_scan", 2))
	deck.append_array(_copies(&"skl_recycle", 2))
	deck.append_array(_copies(&"skl_mark", 1))
	return deck


func get_boss_layer1_deck() -> Array[CardData]:
	var deck: Array[CardData] = []
	deck.append_array(_copies(&"boss_pulse", 4))
	deck.append_array(_copies(&"boss_pierce", 2))
	deck.append_array(_copies(&"boss_double", 1))
	deck.append_array(_copies(&"boss_charged", 2))
	deck.append_array(_copies(&"boss_decay", 1))
	deck.append_array(_copies(&"boss_shield", 4))
	deck.append_array(_copies(&"boss_prism", 1))
	deck.append_array(_copies(&"boss_heal", 2))
	deck.append_array(_copies(&"boss_scan", 2))
	deck.append_array(_copies(&"boss_charge", 2))
	deck.append_array(_copies(&"boss_disrupt", 2))
	deck.append_array(_copies(&"boss_resonance", 1))
	deck.append_array(_copies(&"boss_reorg", 1))
	return deck


func get_initial_constraints() -> Array[ConstraintData]:
	var list: Array[ConstraintData] = []
	list.append(_make_constraint(&"constraint_lock", "行为锁定", ConstraintData.ConstraintType.LOCK_CARD, 2, 1, "Boss 1回合内无法打出攻击牌"))
	list.append(_make_constraint(&"constraint_seal", "类型封印", ConstraintData.ConstraintType.SEAL_TYPE, 3, 1, "Boss 1回合内无法打出技能牌"))
	list[1].seal_card_type = CardData.CardType.SKILL
	list.append(_make_constraint(&"constraint_veto", "协议否决", ConstraintData.ConstraintType.VETO, 1, 0, "即时取消Boss正在打出的1张牌"))
	return list


# ===== 内部注册方法 =====

func _copies(id: StringName, count: int) -> Array[CardData]:
	var arr: Array[CardData] = []
	for i in range(count):
		arr.append(get_card(id).duplicate())
	return arr


func _register_player_cards() -> void:
	_reg(&"atk_pulse", "数据脉冲", CardData.CardType.ATTACK, 1, "造成5伤害", {&"damage": 5})
	_reg(&"atk_precise", "精确打击", CardData.CardType.ATTACK, 1, "3伤害，无视护甲", {&"damage": 3, &"ignore_armor": true})
	_reg(&"atk_overload", "过载冲击", CardData.CardType.ATTACK, 2, "造成12伤害", {&"damage": 12})
	_reg(&"atk_arc", "残余电弧", CardData.CardType.ATTACK, 0, "造成3伤害", {&"damage": 3})
	_reg(&"def_firewall", "防火墙", CardData.CardType.DEFENSE, 1, "获得5护甲", {&"armor": 5})
	_reg(&"def_emergency", "应急屏障", CardData.CardType.DEFENSE, 0, "获得3护甲", {&"armor": 3})
	_reg(&"def_fullguard", "全面防护", CardData.CardType.DEFENSE, 2, "8护甲，抽1张", {&"armor": 8, &"draw_cards": 1})
	_reg(&"skl_scan", "系统扫描", CardData.CardType.SKILL, 1, "抽2张牌", {&"draw_cards": 2})
	_reg(&"skl_recycle", "能量回收", CardData.CardType.SKILL, 0, "下回合能量+1", {&"energy_next_turn": 1})
	_reg(&"skl_mark", "弱点标记", CardData.CardType.SKILL, 1, "下次攻击+4", {&"next_attack_bonus": 4})


func _register_boss_layer1_cards() -> void:
	_reg(&"boss_pulse", "回响脉冲", CardData.CardType.ATTACK, 1, "造成5伤害", {&"damage": 5})
	_reg(&"boss_pierce", "裂隙穿刺", CardData.CardType.ATTACK, 1, "4伤害，无视护甲", {&"damage": 4, &"ignore_armor": true})
	_reg(&"boss_double", "双重打击", CardData.CardType.ATTACK, 2, "5伤害×2次", {&"damage": 5, &"hits": 2})
	_reg(&"boss_charged", "蓄能释放", CardData.CardType.ATTACK, 2, "15伤害(需蓄力)", {&"damage": 15, &"requires_charge": true})
	_reg(&"boss_decay", "衰变射线", CardData.CardType.ATTACK, 0, "造成3伤害", {&"damage": 3})
	_reg(&"boss_shield", "回响护盾", CardData.CardType.DEFENSE, 1, "获得6护甲", {&"armor": 6})
	_reg(&"boss_prism", "棱镜壁垒", CardData.CardType.DEFENSE, 2, "获得10护甲", {&"armor": 10})
	_reg(&"boss_heal", "自我修复", CardData.CardType.DEFENSE, 1, "回复8生命", {&"heal": 8})
	_reg(&"boss_scan", "深层扫描", CardData.CardType.SKILL, 1, "抽2张牌", {&"draw_cards": 2})
	_reg(&"boss_charge", "蓄力协议", CardData.CardType.SKILL, 1, "获得蓄力状态", {&"grants_charge": true})
	_reg(&"boss_disrupt", "频率干扰", CardData.CardType.SKILL, 1, "对手下回合抽牌-1", {&"enemy_draw_modifier": -1})
	_reg(&"boss_resonance", "回响共鸣", CardData.CardType.PROTOCOL, 2, "本回合攻击+3", {&"all_attack_bonus": 3})
	_reg(&"boss_reorg", "数据重组", CardData.CardType.PROTOCOL, 1, "弃手牌抽4张", {&"discard_hand_and_draw": 4})


func _register_reward_cards() -> void:
	_reg(&"reward_chain", "连锁协议", CardData.CardType.ATTACK, 1, "4伤害(已攻击则8)", {&"damage": 4, &"bonus_if_attacked_this_turn": 4})
	_reg(&"reward_core", "过载核心", CardData.CardType.ATTACK, 2, "9伤害，敌能量-1", {&"damage": 9, &"enemy_energy_modifier": -1})
	_reg(&"reward_adapt", "自适应壁垒", CardData.CardType.DEFENSE, 1, "4护甲+受伤时+3", {&"armor": 4, &"armor_on_hit": 3})
	_reg(&"reward_reflect", "反射协议", CardData.CardType.DEFENSE, 2, "6护甲+反弹3", {&"armor": 6, &"reflect_damage": 3})
	_reg(&"reward_predict", "预判引擎", CardData.CardType.SKILL, 1, "抽2张，约束-1", {&"draw_cards": 2, &"constraint_discount": 1})
	_reg(&"reward_siphon", "资源虹吸", CardData.CardType.SKILL, 1, "3伤害+1约束", {&"damage": 3, &"gain_constraint_resource": 1})


func _reg(id: StringName, card_name: String, type: CardData.CardType, cost: int, desc: String, props: Dictionary) -> void:
	var card := CardData.new()
	card.id = id
	card.card_name = card_name
	card.type = type
	card.energy_cost = cost
	card.description = desc
	for key in props:
		card.set(key, props[key])
	all_cards[id] = card


func _make_constraint(id: StringName, cname: String, type: ConstraintData.ConstraintType, cost: int, duration: int, desc: String) -> ConstraintData:
	var c := ConstraintData.new()
	c.id = id
	c.constraint_name = cname
	c.type = type
	c.resource_cost = cost
	c.duration = duration
	c.description = desc
	return c


# ===== v0.3 陷阱牌系统 =====

func get_initial_traps() -> Array[TrapData]:
	## 获取玩家初始陷阱牌库
	var traps: Array[TrapData] = []
	traps.append(get_trap(&"trap_interrupt").duplicate())
	traps.append(get_trap(&"trap_siphon").duplicate())
	traps.append(get_trap(&"trap_reflect").duplicate())
	traps.append(get_trap(&"trap_bluff_a").duplicate())
	traps.append(get_trap(&"trap_bluff_b").duplicate())
	return traps


func get_trap(id: StringName) -> TrapData:
	return all_traps.get(id, null)


func _register_trap_cards() -> void:
	_reg_trap(&"trap_interrupt", "中断协议", TrapData.TrapType.INTERRUPT, 2, "触发时完全无效化Boss该牌", {&"interrupt_card": true})
	_reg_trap(&"trap_siphon", "能量虹吸", TrapData.TrapType.SIPHON, 2, "触发时Boss下回合能量-1", {&"energy_drain": 1})
	_reg_trap(&"trap_reflect", "反射棱镜", TrapData.TrapType.REFLECT, 3, "触发时攻击伤害反弹给Boss", {&"reflect_attack": true})
	_reg_trap(&"trap_typelock", "类型封锁", TrapData.TrapType.TYPELOCK, 3, "触发时该类型牌永久能量+1", {&"type_cost_increase": 1})
	_reg_trap(&"trap_bluff_a", "虚影协议", TrapData.TrapType.BLUFF, 0, "虚张声势：占位但无效果", {&"is_bluff": true})
	_reg_trap(&"trap_bluff_b", "虚影协议", TrapData.TrapType.BLUFF, 0, "虚张声势：占位但无效果", {&"is_bluff": true})


func _reg_trap(id: StringName, trap_name: String, type: TrapData.TrapType, cost: int, desc: String, props: Dictionary) -> void:
	var trap := TrapData.new()
	trap.id = id
	trap.trap_name = trap_name
	trap.type = type
	trap.resource_cost = cost
	trap.description = desc
	trap.slot_any = true
	trap.is_bluff = props.get(&"is_bluff", false)
	for key in props:
		trap.set(key, props[key])
	all_traps[id] = trap
