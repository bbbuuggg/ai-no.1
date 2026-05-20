extends Node
## CardDatabase — 全局卡牌数据库（Autoload）
## 在此定义所有卡牌，避免依赖 .tres 文件（原型阶段）
##
## v0.6.0 元素+光暗转向（ADR-002 / GDD-06）：
## - 新增 v0.6.0 牌池：玩家 10 张（火3+水3+木4，光6/暗4）+ Boss 10 张（火4+水3+木3，光4/暗6）
## - 新增 _reg_v06() 注册器，支持 element + polarity 字段
## - 旧 v0.5.0 / Sprint A2 牌池保留以防 reward 等模块引用，但 starter_deck 已切换到 v0.6.0

var all_cards: Dictionary = {}  # id -> CardData
var all_traps: Dictionary = {}  # id -> TrapData

# v0.9.4 自调升级牌：runtime 注册的 id 列表（每次 start_new_run 清理）
# 用途：玩家在密码锁面板创造的自调牌（id="up_custom_r{N}_{seq}"）通过 register_runtime_card 注入
var _runtime_card_ids: Array[StringName] = []


func _ready() -> void:
	_register_player_cards()
	_register_boss_layer1_cards()
	_register_v06_player_cards()      # v0.6.0 新增：火水木+光暗
	_register_v06_boss_cards()        # v0.6.0 新增
	_register_v07_zerocost_cards()    # v0.7.x-rebal：3 张 0 费过牌牌
	_register_upgrade_new_cards()     # GDD-08 v0.8.2：4 张升级专属新卡（up_*）
	_register_reward_cards()
	_register_trap_cards()


func get_card(id: StringName) -> CardData:
	return all_cards.get(id, null)


## v0.9.4：注册一张运行时生成的卡（来自 CustomCardFactory 自调升级）
## 调用方负责保证 id 唯一（建议用 up_custom_r{N}_{seq} 格式）
func register_runtime_card(card: CardData) -> void:
	if card == null or card.id == &"":
		push_error("CardDatabase.register_runtime_card: card 或 id 无效")
		return
	if all_cards.has(card.id):
		push_warning("CardDatabase.register_runtime_card: id 冲突 %s（覆盖）" % card.id)
	all_cards[card.id] = card
	if not _runtime_card_ids.has(card.id):
		_runtime_card_ids.append(card.id)


## v0.9.4：清理所有 runtime 注册的卡（开新 run 时调用，避免跨 run id 冲突）
func clear_runtime_cards() -> void:
	for id in _runtime_card_ids:
		all_cards.erase(id)
	_runtime_card_ids.clear()


## v0.9.4：当前 runtime 注册的自调牌数量（供 RewardScreen 生成新 sequence id 用）
func get_runtime_card_count() -> int:
	return _runtime_card_ids.size()



func get_player_starter_deck() -> Array[CardData]:
	# v0.7.x-rebal：玩家牌库 = v0.6.0 火水木 10 张 + v0.7.x 0 费过牌牌 1 张 = 11 张
	# 设计依据：docs/design/proposals/2026-05-15-hand-deck-economy-rebalance.md
	# v0.7.x 移除非 0 费牌的 draw_cards 字段（抽牌只属 0 费），数值已补偿到伤害/护甲
	var deck: Array[CardData] = []
	# 火 3 张
	deck.append(get_card(&"p_fire_solar").duplicate())     # 阳焰  光 1费 4伤+治2
	deck.append(get_card(&"p_fire_blaze").duplicate())     # 业火  暗 2费 9伤
	deck.append(get_card(&"p_fire_radiance").duplicate())  # 烈日  光 2费 7伤（v0.7.x：6伤+抽1 → 7伤）
	# 水 3 张
	deck.append(get_card(&"p_water_moonshield").duplicate())  # 月华盾 光 1费 6甲+治2
	deck.append(get_card(&"p_water_frostmirror").duplicate())  # 寒霜镜 暗 2费 5甲+反3
	deck.append(get_card(&"p_water_spring").duplicate())       # 涌泉   光 1费 5甲+治1（v0.7.x：4甲+抽1 → 5甲+治1）
	# 木 4 张
	deck.append(get_card(&"p_wood_bud").duplicate())        # 春芽   光 1费 4甲（v0.7.x：3甲+抽1 → 4甲）
	deck.append(get_card(&"p_wood_thorn").duplicate())      # 荆棘   暗 2费 7伤无视3甲
	deck.append(get_card(&"p_wood_vine").duplicate())       # 藤甲   光 1费 5甲
	deck.append(get_card(&"p_wood_corrupt").duplicate())    # 蚀根   暗 1费 4伤+敌-1抽
	# v0.7.x-hotfix：保留 1 张 0 费过牌牌（每回合限 2 次）
	# 删除 c_reorganize / c_resonance_loop，仅保留 c_inspiration_surge（抽 1）
	deck.append(get_card(&"c_inspiration_surge").duplicate())  # 灵光一现 0费 抽1
	return deck


func get_boss_layer1_deck() -> Array[CardData]:
	# v0.7.x-rebal：Boss「回响 Echo」牌库 = v0.6.0 火水木 10 张 + v0.7.x 0 费过牌牌 1 张 = 11 张
	# v0.7.x：b_wood_resonance 共鸣芽 抽2 → 4甲+治2（移除抽牌，改续航）
	var deck: Array[CardData] = []
	# 火 4 张
	deck.append(get_card(&"b_fire_echo").duplicate())       # 回响焰   暗 1费 5伤
	deck.append(get_card(&"b_fire_scorch").duplicate())     # 灼烧波   暗 2费 8伤
	deck.append(get_card(&"b_fire_dusk").duplicate())       # 残阳     光 1费 4伤+治3
	deck.append(get_card(&"b_fire_ember").duplicate())      # 余烬     暗 1费 3伤+下回合伤+3
	# 水 3 张
	deck.append(get_card(&"b_water_echoshield").duplicate())  # 回声盾 光 1费 8甲
	deck.append(get_card(&"b_water_freeze").duplicate())      # 冰封   暗 2费 7甲+治2（v0.7.x-hotfix5：移除-1能量，避免空 slot 卡住 BP）
	deck.append(get_card(&"b_water_repair").duplicate())      # 修复泉 光 1费 治8
	# 木 3 张
	deck.append(get_card(&"b_wood_echo_vine").duplicate())    # 回响藤 暗 2费 6伤+无视2甲
	deck.append(get_card(&"b_wood_resonance").duplicate())    # 共鸣芽 光 1费 4甲+治2（v0.7.x：抽2 → 续航防御）
	deck.append(get_card(&"b_wood_parasite").duplicate())     # 寄生   暗 1费 4伤+回血4
	# v0.7.x-hotfix：Boss 共享同一张 0 费过牌牌（仅 c_inspiration_surge）
	deck.append(get_card(&"c_inspiration_surge").duplicate())
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


# ============================================================================
# v0.6.0 火水木+光暗 牌池注册（ADR-002 / GDD-06）
# ============================================================================

func _register_v06_player_cards() -> void:
	# === 火 3 张（攻击系，光1暗2）===
	_reg_v06(&"p_fire_solar",     "阳焰",   CardData.CardType.ATTACK, CardData.Element.FIRE, CardData.Polarity.LIGHT,
		1, "造成4点伤害，回复2点生命",          {&"damage": 4, &"heal": 2})
	_reg_v06(&"p_fire_blaze",     "业火",   CardData.CardType.ATTACK, CardData.Element.FIRE, CardData.Polarity.DARK,
		2, "造成9点伤害（暗黑爆发）",            {&"damage": 9})
	_reg_v06(&"p_fire_radiance",  "烈日",   CardData.CardType.ATTACK, CardData.Element.FIRE, CardData.Polarity.LIGHT,
		2, "造成7点伤害",                        {&"damage": 7})  # v0.7.x：原 6伤+抽1 → 7伤（抽牌只属 0 费）

	# === 水 3 张（防御系，光2暗1）===
	_reg_v06(&"p_water_moonshield", "月华盾", CardData.CardType.DEFENSE, CardData.Element.WATER, CardData.Polarity.LIGHT,
		1, "获得6点护甲，回复2点生命",           {&"armor": 6, &"heal": 2})
	_reg_v06(&"p_water_frostmirror","寒霜镜", CardData.CardType.DEFENSE, CardData.Element.WATER, CardData.Polarity.DARK,
		2, "获得5点护甲，反弹3点伤害",           {&"armor": 5, &"reflect_damage": 3})
	_reg_v06(&"p_water_spring",     "涌泉",   CardData.CardType.DEFENSE, CardData.Element.WATER, CardData.Polarity.LIGHT,
		1, "获得5点护甲，回复1点生命",           {&"armor": 5, &"heal": 1})  # v0.7.x：原 4甲+抽1 → 5甲+治1

	# === 木 4 张（技能/混合系，光3暗1）===
	_reg_v06(&"p_wood_bud",      "春芽",   CardData.CardType.SKILL,   CardData.Element.WOOD, CardData.Polarity.LIGHT,
		1, "获得4点护甲",                         {&"armor": 4})  # v0.7.x：原 3甲+抽1 → 4甲
	_reg_v06(&"p_wood_thorn",    "荆棘",   CardData.CardType.ATTACK,  CardData.Element.WOOD, CardData.Polarity.DARK,
		2, "造成7点伤害，无视3点护甲",            {&"damage": 7, &"ignore_armor": true})
	_reg_v06(&"p_wood_vine",     "藤甲",   CardData.CardType.DEFENSE, CardData.Element.WOOD, CardData.Polarity.LIGHT,
		1, "获得5点护甲",                        {&"armor": 5})
	_reg_v06(&"p_wood_corrupt",  "蚀根",   CardData.CardType.SKILL,   CardData.Element.WOOD, CardData.Polarity.DARK,
		1, "造成4点伤害，对方下回合抽牌-1",       {&"damage": 4, &"enemy_draw_modifier": -1})


func _register_v06_boss_cards() -> void:
	# Boss「回响 Echo」10 张（火4+水3+木3，光4/暗6 偏爆发）— 用户拍板 Boss 不动，仅去赛博词
	# === 火 4 张（光1暗3）===
	_reg_v06(&"b_fire_echo",   "回响焰",   CardData.CardType.ATTACK, CardData.Element.FIRE, CardData.Polarity.DARK,
		1, "造成5点伤害",                        {&"damage": 5})
	_reg_v06(&"b_fire_scorch", "灼烧波",   CardData.CardType.ATTACK, CardData.Element.FIRE, CardData.Polarity.DARK,
		2, "造成8点伤害",                        {&"damage": 8})
	_reg_v06(&"b_fire_dusk",   "残阳",     CardData.CardType.ATTACK, CardData.Element.FIRE, CardData.Polarity.LIGHT,
		1, "造成4点伤害，回复3点生命",           {&"damage": 4, &"heal": 3})
	_reg_v06(&"b_fire_ember",  "余烬",     CardData.CardType.ATTACK, CardData.Element.FIRE, CardData.Polarity.DARK,
		1, "造成3点伤害，下次攻击+3伤害",        {&"damage": 3, &"next_attack_bonus": 3})

	# === 水 3 张（光2暗1）===
	_reg_v06(&"b_water_echoshield", "回声盾", CardData.CardType.DEFENSE, CardData.Element.WATER, CardData.Polarity.LIGHT,
		1, "获得8点护甲",                        {&"armor": 8})
	# v0.7.x-hotfix5：原 6甲+对手-1能量 → 7甲+治2
	# 「敌方-1能量」会让玩家某回合实际能量<3，可能导致 BP 候选无法 Pick 留空 slot 卡住游戏，
	# 本牌改为纯防御-续航，保持 2 费 DARK 元素与 Boss 牌库 13 张数量稳定
	_reg_v06(&"b_water_freeze",     "冰封",   CardData.CardType.DEFENSE, CardData.Element.WATER, CardData.Polarity.DARK,
		2, "获得7点护甲，回复2点生命",            {&"armor": 7, &"heal": 2})
	_reg_v06(&"b_water_repair",     "修复泉", CardData.CardType.DEFENSE, CardData.Element.WATER, CardData.Polarity.LIGHT,
		1, "回复8点生命",                        {&"heal": 8})

	# === 木 3 张（光1暗2）===
	_reg_v06(&"b_wood_echo_vine", "回响藤",   CardData.CardType.ATTACK, CardData.Element.WOOD, CardData.Polarity.DARK,
		2, "造成6点伤害，无视2点护甲",           {&"damage": 6, &"ignore_armor": true})
	_reg_v06(&"b_wood_resonance", "共鸣芽",   CardData.CardType.SKILL,  CardData.Element.WOOD, CardData.Polarity.LIGHT,
		1, "获得4点护甲，回复2点生命",           {&"armor": 4, &"heal": 2})  # v0.7.x：原 抽2 → 4甲+治2（续航防御）
	_reg_v06(&"b_wood_parasite",  "寄生",     CardData.CardType.ATTACK, CardData.Element.WOOD, CardData.Polarity.DARK,
		1, "造成4点伤害，回复4点生命",           {&"damage": 4, &"heal": 4})


# ============================================================================
# v0.7.x-rebal 0 费过牌牌（3 张，玩家/Boss 共享，每回合限 2 次）
# 设计依据：docs/design/proposals/2026-05-15-hand-deck-economy-rebalance.md
# 红线：抽牌效果只属 0 费牌；其它牌一律不带 draw_cards
# ============================================================================

func _register_v07_zerocost_cards() -> void:
	# === c_inspiration_surge 灵光一现 — 抽 1 ===
	# v0.7.x-hotfix：原本三张 0 费牌（c_inspiration_surge / c_reorganize / c_resonance_loop）
	# 因 c_reorganize / c_resonance_loop 与 BP 候选窗交互产生多个边界 bug，
	# 本次精简为「只保留抽 1」一张。Boss 也共享这张，使用后由 _resolve_zerocost_immediate 统一抽 1。
	_reg_v06(&"c_inspiration_surge", "灵光一现", CardData.CardType.SKILL,
		CardData.Element.WOOD, CardData.Polarity.LIGHT,
		0, "[0费] 抽 1 张牌（每回合限 2 次）",
		{&"draw_cards": 1})


# ============================================================================
# GDD-08 v0.8.2 升级专属新卡池（4 张）
# 设计依据：game-designer 双向价值约束（self vs MIRROR 都有意义）
# 类型分布：ATTACK×2 / DEFENSE×1 / SKILL×1
# 元素分布：火×2 / 水×1 / 木×1，光×2 / 暗×2
# 能量曲线：0/1/2/3 各 1 张
# ============================================================================

func _register_upgrade_new_cards() -> void:
	# 凤凰击 — 火/光 1费 8伤+3治
	# self：1费8伤+3治，强力主力；MIRROR：自愈拖战，给玩家更多抽牌机会
	_reg_v06(&"up_phoenix_strike", "凤凰击", CardData.CardType.ATTACK,
		CardData.Element.FIRE, CardData.Polarity.LIGHT,
		1, "造成8伤害，回复3生命",
		{&"damage": 8, &"heal": 3})

	# 潮汐壁垒 — 水/暗 2费 8甲+抽1
	# self：节奏型防御；MIRROR：手牌堆积加速洗牌，给玩家预判机会
	_reg_v06(&"up_tidal_barrier", "潮汐壁垒", CardData.CardType.DEFENSE,
		CardData.Element.WATER, CardData.Polarity.DARK,
		2, "获得8护甲，抽1张牌",
		{&"armor": 8, &"draw_cards": 1})

	# 青翠凝神 — 木/光 0费 抽1+下击+3
	# self：0费 combo 启动；MIRROR：省能量+预警一次重击
	_reg_v06(&"up_verdant_focus", "青翠凝神", CardData.CardType.SKILL,
		CardData.Element.WOOD, CardData.Polarity.LIGHT,
		0, "抽1张，下次攻击+3伤害",
		{&"draw_cards": 1, &"next_attack_bonus": 3})

	# 蚀月裁决 — 火/暗 3费 12无视甲+反伤3
	# self：高伤+站场反伤；MIRROR：极痛但持续触发反伤
	_reg_v06(&"up_eclipse_verdict", "蚀月裁决", CardData.CardType.ATTACK,
		CardData.Element.FIRE, CardData.Polarity.DARK,
		3, "12伤害，无视护甲，反伤3",
		{&"damage": 12, &"ignore_armor": true, &"reflect_damage": 3})

	# ========================================================================
	# v0.8.3 GDD-08：R2/R3/R4 关卡专属升级牌（混合方案 C）
	# 各 4 张，配合 5 轮 rogue-lite 的强度递进 × 战术类型递进主题
	# ========================================================================

	# --- Round 2→3：进阶攻防强化（数值+20%，引入无视甲/反伤双关键字铺垫）---

	# 穿甲斩 — 火暗 ATK 2费 8伤·无视甲
	_reg_v06(&"up_armor_pierce", "穿甲斩", CardData.CardType.ATTACK,
		CardData.Element.FIRE, CardData.Polarity.DARK,
		2, "8伤害，无视护甲",
		{&"damage": 8, &"ignore_armor": true})

	# 棘心壁 — 木光 DEF 1费 6甲·反伤2
	_reg_v06(&"up_thorn_aegis", "棘心壁", CardData.CardType.DEFENSE,
		CardData.Element.WOOD, CardData.Polarity.LIGHT,
		1, "6护甲，反伤2",
		{&"armor": 6, &"reflect_damage": 2})

	# 寒潮锁 — 水暗 SKL 2费 5甲·下击+4
	_reg_v06(&"up_riptide_lock", "寒潮锁", CardData.CardType.SKILL,
		CardData.Element.WATER, CardData.Polarity.DARK,
		2, "5护甲，下次攻击+4伤害",
		{&"armor": 5, &"next_attack_bonus": 4})

	# 日炎闪 — 火光 ATK 1费 5伤·治2
	_reg_v06(&"up_solar_flare", "日炎闪", CardData.CardType.ATTACK,
		CardData.Element.FIRE, CardData.Polarity.LIGHT,
		1, "5伤害，回复2生命",
		{&"damage": 5, &"heal": 2})

	# --- Round 3→4：节奏控制 + 能量战（引入抽 2/能量蓄能机制）---

	# 时之涌 — 水光 SKL 1费 抽2·下回合+1能
	_reg_v06(&"up_chrono_surge", "时之涌", CardData.CardType.SKILL,
		CardData.Element.WATER, CardData.Polarity.LIGHT,
		1, "抽2张，下回合+1能量",
		{&"draw_cards": 2, &"energy_next_turn": 1})

	# 烬流爆 — 火暗 ATK 3费 10伤·抽1
	_reg_v06(&"up_emberflow", "烬流爆", CardData.CardType.ATTACK,
		CardData.Element.FIRE, CardData.Polarity.DARK,
		3, "10伤害，抽1张",
		{&"damage": 10, &"draw_cards": 1})

	# 林之咏 — 木光 DEF 2费 7甲·下回合+1能
	_reg_v06(&"up_grove_chant", "林之咏", CardData.CardType.DEFENSE,
		CardData.Element.WOOD, CardData.Polarity.LIGHT,
		2, "7护甲，下回合+1能量",
		{&"armor": 7, &"energy_next_turn": 1})

	# 虚空拍 — 水暗 SKL 2费 抽2·下击+3
	_reg_v06(&"up_void_tempo", "虚空拍", CardData.CardType.SKILL,
		CardData.Element.WATER, CardData.Polarity.DARK,
		2, "抽2张，下次攻击+3伤害",
		{&"draw_cards": 2, &"next_attack_bonus": 3})

	# --- Round 4→5：神话级终局（双关键字组合，玩家终局神器）---

	# 极光裁 — 水光 ATK 3费 11伤·无视甲·治3
	_reg_v06(&"up_aurora_judgment", "极光裁", CardData.CardType.ATTACK,
		CardData.Element.WATER, CardData.Polarity.LIGHT,
		3, "11伤无视甲，回复3生命",
		{&"damage": 11, &"ignore_armor": true, &"heal": 3})

	# 深渊契 — 水暗 SKL 3费 抽2·下击+6
	_reg_v06(&"up_abyss_pact", "深渊契", CardData.CardType.SKILL,
		CardData.Element.WATER, CardData.Polarity.DARK,
		3, "抽2张，下次攻击+6伤害",
		{&"draw_cards": 2, &"next_attack_bonus": 6})

	# 创世击 — 火光 ATK 3费 10伤·无视甲·下击+4
	_reg_v06(&"up_genesis_strike", "创世击", CardData.CardType.ATTACK,
		CardData.Element.FIRE, CardData.Polarity.LIGHT,
		3, "10伤无视甲，下击+4",
		{&"damage": 10, &"ignore_armor": true, &"next_attack_bonus": 4})

	# 凤极焰 — 火暗 ATK 2费 9伤·治5·反伤3
	_reg_v06(&"up_phoenix_zenith", "凤极焰", CardData.CardType.ATTACK,
		CardData.Element.FIRE, CardData.Polarity.DARK,
		2, "9伤回5血，反伤3",
		{&"damage": 9, &"heal": 5, &"reflect_damage": 3})


## GDD-08 v0.8.3：按当前轮次返回该轮升级阶段的 4 张候选
## - round_index 是 RunState 当前的"下一轮"号（互换+升级时已 +1，所以战胜 R1 后 round_index=2 → 用 R1 升级池）
## - 实际"刚击败的 boss 是哪关"= round_index - 1
## - 我们用 just_beaten = round_index - 1 来索引：
##   · just_beaten=1 → 现有 4 张（凤凰击/潮汐壁垒/青翠凝神/蚀月裁决）
##   · just_beaten=2 → R2 进阶攻防 4 张
##   · just_beaten=3 → R3 节奏能量 4 张
##   · just_beaten=4 → R4 神话终局 4 张
##   · 其他（兜底）→ R1 池
func get_upgrade_card_pool(round_index: int = 2) -> Array[CardData]:
	var just_beaten: int = round_index - 1  # round_index 是即将开始的下一轮
	var ids: Array[StringName] = []
	match just_beaten:
		1:
			ids = [&"up_phoenix_strike", &"up_tidal_barrier",
				   &"up_verdant_focus", &"up_eclipse_verdict"]
		2:
			ids = [&"up_armor_pierce", &"up_thorn_aegis",
				   &"up_riptide_lock", &"up_solar_flare"]
		3:
			ids = [&"up_chrono_surge", &"up_emberflow",
				   &"up_grove_chant", &"up_void_tempo"]
		4:
			ids = [&"up_aurora_judgment", &"up_abyss_pact",
				   &"up_genesis_strike", &"up_phoenix_zenith"]
		_:
			# 兜底：用 R1 池（不应到达，但保险）
			ids = [&"up_phoenix_strike", &"up_tidal_barrier",
				   &"up_verdant_focus", &"up_eclipse_verdict"]
	var pool: Array[CardData] = []
	for id in ids:
		var card: CardData = get_card(id)
		if card != null:
			pool.append(card.duplicate())
	return pool


# v0.6.0 注册器：带 element + polarity
func _reg_v06(id: StringName, card_name: String, type: CardData.CardType,
		element: CardData.Element, polarity: CardData.Polarity,
		cost: int, desc: String, props: Dictionary) -> void:
	var card := CardData.new()
	card.id = id
	card.card_name = card_name
	card.type = type
	card.element = element
	card.polarity = polarity
	card.energy_cost = cost
	card.description = desc
	for key in props:
		card.set(key, props[key])
	all_cards[id] = card


# ============================================================================
# 旧 v0.5.0 / Sprint A2 牌池（保留以防 reward / LLM perception / Sprint4 引用）
# ============================================================================



func _register_player_cards() -> void:
	# === v0.5.0 A2 砍牌库 — 玩家 8 张核心 ===
	_reg(&"atk_strike",      "strike.exe",   CardData.CardType.ATTACK,  1, "造成6点伤害",                        {&"damage": 6})
	_reg(&"atk_pierce",      "pierce.exe",   CardData.CardType.ATTACK,  2, "造成9点伤害，无视护甲",              {&"damage": 9, &"ignore_armor": true})
	_reg(&"atk_overload_v2", "overload.exe", CardData.CardType.ATTACK,  2, "造成12点伤害（高风险）",             {&"damage": 12})  # TODO Sprint3: 自伤3
	_reg(&"def_firewall_v2", "firewall.def", CardData.CardType.DEFENSE, 1, "获得6点护甲",                        {&"armor": 6})
	_reg(&"def_mirror",      "mirror.def",   CardData.CardType.DEFENSE, 2, "获得4护甲，反弹3点伤害",             {&"armor": 4, &"reflect_damage": 3})  # TODO Sprint3: 反弹改为本回合所受 50%
	_reg(&"skl_scan_v2",     "scan.tec",     CardData.CardType.SKILL,   1, "抽2张，下回合+1能量",                {&"draw_cards": 2, &"energy_next_turn": 1})
	_reg(&"skl_purge",       "purge.tec",    CardData.CardType.SKILL,   2, "[占位] 抽2张（Sprint3 改为弃Boss）", {&"draw_cards": 2})  # TODO Sprint3: 弃Boss手牌随机1张
	_reg(&"util_null_op",    "null_op",      CardData.CardType.SKILL,   0, "[占位] 下回合能量+1（Sprint3 蓄力）",{&"energy_next_turn": 1})  # TODO Sprint3: 本回合不出牌+下回合首攻+3

	# === 旧 20 张库（保留以防 reward 等模块引用，不进入 starter deck） ===
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
	# === v0.5.0 A2 砍牌库 — Boss L1 Sentinel 8 张 ===
	_reg(&"boss_l1_strike",    "回响打击", CardData.CardType.ATTACK,   1, "造成5点伤害",            {&"damage": 5})
	_reg(&"boss_l1_pierce",    "裂隙穿刺", CardData.CardType.ATTACK,   1, "4伤害，无视护甲",        {&"damage": 4, &"ignore_armor": true})
	_reg(&"boss_l1_charged",   "蓄能释放", CardData.CardType.ATTACK,   2, "15伤害（需蓄力）",       {&"damage": 15, &"requires_charge": true})
	_reg(&"boss_l1_aegis",     "重装护盾", CardData.CardType.DEFENSE,  1, "获得8点护甲",            {&"armor": 8})
	_reg(&"boss_l1_prism",     "棱镜壁垒", CardData.CardType.DEFENSE,  2, "获得10点护甲",           {&"armor": 10})
	_reg(&"boss_l1_repair",    "自我修复", CardData.CardType.DEFENSE,  1, "回复8点生命",            {&"heal": 8})
	_reg(&"boss_l1_intercept", "频率干扰", CardData.CardType.SKILL,    1, "对方下回合抽牌-1",       {&"enemy_draw_modifier": -1})
	_reg(&"boss_l1_resonance", "回响共鸣", CardData.CardType.PROTOCOL, 2, "本回合所有攻击+3伤害",   {&"all_attack_bonus": 3})

	# === 旧 25 张库保留（防 LLM perception/Sprint4 引用） ===
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
	_reg(&"boss_disrupt", "频率干扰", CardData.CardType.SKILL, 1, "对方下回合抽牌-1", {&"enemy_draw_modifier": -1})
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
