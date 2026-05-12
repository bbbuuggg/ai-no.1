class_name TrapData
extends Resource
## 约束陷阱数据定义

enum TrapSlot { ATTACK, SKILL, HIGH_COST }  # 攻击触发/技能触发/高费触发(≥2能量)
enum TrapType { INTERRUPT, SIPHON, REFLECT, TYPELOCK, BLUFF }

@export var id: StringName = &""
@export var trap_name: String = ""
@export var type: TrapType = TrapType.BLUFF
@export var slot: TrapSlot = TrapSlot.ATTACK  # 可部署的槽位
@export var slot_any: bool = true  # true=可放任意槽位
@export var resource_cost: int = 0  # 约束资源消耗（空白牌=0）
@export var description: String = ""

# 效果参数
@export var interrupt_card: bool = false  # 中断：完全无效化触发牌
@export var energy_drain: int = 0  # 能量虹吸：Boss下回合能量-X
@export var reflect_attack: bool = false  # 反射：攻击伤害反弹给Boss
@export var type_cost_increase: int = 0  # 类型封锁：该类牌永久能量+X
@export var is_bluff: bool = false  # 是否为空白牌（虚张声势）


## 检查Boss出的牌是否匹配此陷阱的触发条件
func matches_trigger(card: CardData) -> bool:
	if is_bluff:
		return true  # 空白牌"匹配"任何东西（但效果为空）
	if slot_any:
		# 通用槽检查
		match slot:
			TrapSlot.ATTACK:
				return card.type == CardData.CardType.ATTACK
			TrapSlot.SKILL:
				return card.type == CardData.CardType.SKILL or card.type == CardData.CardType.PROTOCOL
			TrapSlot.HIGH_COST:
				return card.energy_cost >= 2
	return false
