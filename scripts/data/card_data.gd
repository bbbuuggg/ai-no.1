class_name CardData
extends Resource
## 卡牌数据定义 — 玩家和 Boss 共用同一套类型系统

enum CardType { ATTACK, DEFENSE, SKILL, PROTOCOL }

@export var id: StringName = &""
@export var card_name: String = ""
@export var type: CardType = CardType.ATTACK
@export var energy_cost: int = 1
@export var description: String = ""

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
