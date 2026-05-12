class_name ConstraintData
extends Resource
## 约束令数据定义

enum ConstraintType { LOCK_CARD, SEAL_TYPE, VETO, SUFFOCATE, DEPLETE, COMPRESS, PHANTOM, FOG, MIRROR }

@export var id: StringName = &""
@export var constraint_name: String = ""
@export var type: ConstraintType = ConstraintType.LOCK_CARD
@export var resource_cost: int = 1
@export var duration: int = 1  # 持续回合数，-1=永久，0=即时
@export var description: String = ""

# 效果参数
@export var seal_card_type: CardData.CardType = CardData.CardType.ATTACK  # 封印的牌类型
@export var energy_cost_increase: int = 0  # 类型封印：该类牌能量+X
@export var draw_reduction: int = 0  # 窒息：抽牌-X
@export var energy_reduction: int = 0  # 枯竭：能量-X
@export var hand_limit_reduction: int = 0  # 压缩：手牌上限-X

# 幻觉参数
@export var phantom_card_id: StringName = &""  # 虚影：虚假手牌ID
@export var fake_armor_bonus: int = 0  # 迷雾：虚假护甲加值
@export var fake_discard_card_id: StringName = &""  # 镜像：虚假弃牌堆牌ID
