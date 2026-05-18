extends Node
## RunState — GDD-08 MIRROR 进度系统跨回合状态（Autoload）
## 流程：胜利 → 互换(SWAP) → 升级(REWARD) → 下一轮战斗

signal decks_swapped       ## 互换完成，通知 RewardScreen 可以显示
signal run_ended(won: bool, streak: int)  ## Run 结束（失败/完美）

var round_index: int = 1
var victory_streak: int = 0
var struct_modifiers: Dictionary = {
	"player": {},  ## {"energy_bonus": 1, "candidate_bonus": 1, ...}
	"boss": {},
}
var upgrade_history: Array = []  ## [{"round":1, "given_to_self":"up_overflow", "given_to_boss":"up_shard"}]

## 本轮已使用的结构升级（同 Run 仅 1 张限制）
var _structural_used_player: Dictionary = {}  ## effect_id -> true
var _structural_used_boss: Dictionary = {}


func reset_for_new_run() -> void:
	round_index = 1
	victory_streak = 0
	struct_modifiers = {"player": {}, "boss": {}}
	upgrade_history.clear()
	_structural_used_player.clear()
	_structural_used_boss.clear()


## 互换前置于升级：胜利后先调用此函数执行互换
## v0.8.2 修复：互换 full_deck（开战时 11 张快照），而不是运行时 deck（可能已抽光）
## v0.8.3：HP/能量按 round 膨胀（B2 模型：玩家 +3/轮，Boss +4/轮，能量 +1/轮）
func execute_swap(player: Combatant, boss: Combatant) -> void:
	# 整套牌库互换（用 full_deck — 战斗开始时的完整 11 张快照）
	var temp_full: Array[CardData] = []
	temp_full.append_array(player.full_deck)
	player.full_deck.clear()
	player.full_deck.append_array(boss.full_deck)
	boss.full_deck.clear()
	boss.full_deck.append_array(temp_full)

	# 同步 deck 为新的 full_deck 副本
	player.deck.clear()
	player.deck.append_array(player.full_deck)
	boss.deck.clear()
	boss.deck.append_array(boss.full_deck)

	# 清空状态
	player.discard_pile.clear()
	boss.discard_pile.clear()
	player.hand.clear()
	boss.hand.clear()

	# v0.8.3：双方都按 round 膨胀（玩家 +3/轮、Boss +4/轮）
	victory_streak += 1
	round_index += 1
	player.max_hp = get_player_max_hp()
	player.hp = player.max_hp
	player.armor = 0
	boss.max_hp = get_boss_max_hp()
	boss.hp = boss.max_hp
	boss.armor = 0

	# v0.8.3：能量也按 round 膨胀（双方同步，base_energy = 6 + (round-1)）
	var new_base_energy: int = get_base_energy()
	player.base_energy = new_base_energy
	boss.base_energy = new_base_energy
	player.energy = new_base_energy
	boss.energy = new_base_energy

	# 发射信号
	player.hp_changed.emit(player.hp, player.max_hp)
	boss.hp_changed.emit(boss.hp, boss.max_hp)
	player.armor_changed.emit(player.armor)
	boss.armor_changed.emit(boss.armor)
	player.energy_changed.emit(player.energy)
	boss.energy_changed.emit(boss.energy)

	decks_swapped.emit()


## 升级阶段完成后记录
func record_upgrade(player_upgrade: UpgradeData, boss_upgrade: UpgradeData) -> void:
	upgrade_history.append({
		"round": round_index - 1,  # 记录刚结束的轮次
		"given_to_self": player_upgrade.id if player_upgrade else &"",
		"given_to_boss": boss_upgrade.id if boss_upgrade else &"",
	})
	# 记录结构升级使用（同 Run 限 1 张）
	if player_upgrade != null and player_upgrade.is_structural:
		_structural_used_player[player_upgrade.effect_id] = true
	if boss_upgrade != null and boss_upgrade.is_structural:
		_structural_used_boss[boss_upgrade.effect_id] = true


## 检查结构升级是否已被使用（同 Run 限 1 张）
func is_structural_used(side: String, effect_id: StringName) -> bool:
	var dict: Dictionary = _structural_used_player if side == "player" else _structural_used_boss
	return dict.has(effect_id)


## v0.8.3 数值膨胀公式（B2 模型，用户拍板 2026-05-18）
## - 玩家 HP：25 + (round-1) × 3 → R1=25, R5=37
## - Boss HP：25 + (round-1) × 4 → R1=25, R5=41（永远比玩家多 0~16 血）
## - 双方能量：6 + (round-1)     → R1=6,  R5=10

const _PLAYER_HP_BASE: int = 25
const _PLAYER_HP_GROWTH: int = 3   # 玩家每轮 +3
const _BOSS_HP_BASE: int = 25
const _BOSS_HP_GROWTH: int = 4     # Boss 每轮 +4
const _ENERGY_BASE: int = 6
const _ENERGY_GROWTH: int = 1      # 双方每轮 +1


## 玩家 HP 缩放公式
func get_player_max_hp() -> int:
	return _PLAYER_HP_BASE + (round_index - 1) * _PLAYER_HP_GROWTH


## Boss HP 缩放公式
func get_boss_max_hp() -> int:
	return _BOSS_HP_BASE + (round_index - 1) * _BOSS_HP_GROWTH


## 双方共享 base_energy（按 round 膨胀）
func get_base_energy() -> int:
	return _ENERGY_BASE + (round_index - 1) * _ENERGY_GROWTH


## 是否达成完美 Run
func is_perfect_run_done() -> bool:
	return victory_streak >= 5


## 获取 Run 状态摘要（用于 LLM perception）
func get_state_summary() -> Dictionary:
	return {
		"round_index": round_index,
		"victory_streak": victory_streak,
		"upgrade_history": upgrade_history,
		"struct_modifiers": struct_modifiers,
	}
