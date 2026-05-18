class_name CardData
extends Resource
## 卡牌数据定义 — 玩家和 Boss 共用同一套类型系统
##
## v0.6.0 元素+光暗转向（2026-05-14, ADR-002）：
## - 新增 element 字段（FIRE/WATER/WOOD）作为克制判定主维度，取代原 type 三角克制
## - 新增 polarity 字段（LIGHT/DARK）作为正交协同维度，触发 2:2 平衡 ×2.0 倍率
## - type（ATTACK/DEFENSE/SKILL/PROTOCOL）保留，仅作"角色定位"语义 + 陷阱触发槽位匹配
## - 旧牌（未设置 element 的）默认 NONE，碰撞时视为中立（无克制）

enum CardType { ATTACK, DEFENSE, SKILL, PROTOCOL }

## v0.6.0：元素维度（火/水/木 3-cycle 克制）
## NONE = 无元素（不参与元素克制，碰撞视为中立）
enum Element { NONE, FIRE, WATER, WOOD }

## v0.6.0：极性维度（光明/暗黑 2:2 平衡协同）
## NONE = 旧牌兼容（不计入光暗比统计）
enum Polarity { NONE, LIGHT, DARK }

@export var id: StringName = &""
@export var card_name: String = ""
@export var type: CardType = CardType.ATTACK
@export var energy_cost: int = 1
@export var description: String = ""

# v0.6.0 元素+光暗双维度
@export var element: Element = Element.NONE
@export var polarity: Polarity = Polarity.NONE

# 效果数值
@export var damage: int = 0
@export var armor: int = 0
@export var draw_cards: int = 0
@export var heal: int = 0

# 特殊效果标志
@export var ignore_armor: bool = false
@export var hits: int = 1  # 多段攻击次数
@export var next_attack_bonus: int = 0  # 下次攻击+X
@export var energy_next_turn: int = 0  # 下回合能量+X
@export var enemy_draw_modifier: int = 0  # 对手下回合抽牌修正
@export var enemy_energy_modifier: int = 0  # 对手下回合能量修正
@export var requires_charge: bool = false  # 需要蓄力状态
@export var grants_charge: bool = false  # 给予蓄力状态
@export var all_attack_bonus: int = 0  # 本回合所有攻击+X
@export var discard_hand_and_draw: int = 0  # 弃所有手牌抽X张
@export var reshuffle_discard: bool = false  # v0.7.x-rebal：洗弃牌堆回牌库（0 费 c_resonance_loop 用）
@export var bonus_if_attacked_this_turn: int = 0  # 本回合已出过攻击则额外伤害
@export var reflect_damage: int = 0  # 反弹伤害
@export var armor_on_hit: int = 0  # 受伤时额外护甲
@export var constraint_discount: int = 0  # 下次约束令代价-X
@export var gain_constraint_resource: int = 0  # 获得约束资源

# v0.3 暗出对决系统新增
@export var can_bind_as_zero: bool = false  # 是否可作为0费绑定牌（自动判断：energy_cost==0时为true）


## 判断此牌是否可以作为绑定的0费牌
func is_bindable_zero() -> bool:
	return energy_cost == 0
