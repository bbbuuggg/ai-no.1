class_name CustomCardValidator
extends RefCounted
## 自调升级牌合法性校验器（v0.9.4 自调升级牌 PR-2 / 改进版 v2）
##
## 用途：玩家在密码锁面板调好数值 → 调 validate(spec) → 拿到 {is_valid, errors[], total_cost}
##
## v2 改进（用户反馈："点数兑换数值不直观，玩家以为点数=数值"）：
##   - 改为\"点数即数值\"心智：玩家拨 dial 直接得到效果数值，不再隐式换算
##   - damage / heal：1pt = 1 数值（对等）
##   - armor：1pt = 1.5 甲（防御略便宜，鼓励防御构筑）
##   - 数值上限按费用分档，armor 上限 = dmg 上限 × 1.5
##
## spec 字典格式（玩家从密码锁面板组装）：
##   {
##     "damage": int,        # 伤害效果数值（同时也是花费的点数）
##     "armor": int,         # 护甲效果数值（点数 = ceil(armor / 1.5)）
##     "heal": int,          # 治疗（点数 = heal）
##     "energy_cost": int,   # 费用 0~3
##     "element": int,       # CardData.Element 枚举（必须 ≠ NONE）
##     "polarity": int,      # CardData.Polarity 枚举（必须 ≠ NONE）
##     "ignore_armor": bool, # 可选附加效果
##     "draw_cards": int,    # 可选附加效果
##     "reflect_damage": int,# 可选附加效果
##   }


## ============================================================
## 兑换比率（v2：点数即数值）
## ============================================================

## 主资源：每点效果对应的\"点数花费\"
const POINTS_PER_DAMAGE: float = 1.0     # 1 伤 = 1 点
const POINTS_PER_ARMOR: float = 1.0 / 1.5  # 1 甲 ≈ 0.667 点（即 1.5 甲 = 1 点）
const POINTS_PER_HEAL: float = 1.0       # 1 治 = 1 点

## 必填强制开销（v3：从 element 2 + polarity 1 = 3 点，减半为 element 1 + polarity 0 = 1 点）
## 理由：旧设计强制开销吃掉 6 点预算的一半，玩家造的牌远弱于牌库现有牌；
##      极性（光/暗）不影响游戏强度（仅参与 2:2 平衡），不应额外收费。
const COST_ELEMENT: int = 1     # 选 element（非 NONE）
const COST_POLARITY: int = 0    # 选 polarity（非 NONE） — 免费

## 附加效果开销
const COST_IGNORE_ARMOR: int = 3
const COST_DRAW_PER_CARD: int = 5
const COST_REFLECT_DAMAGE_PER: int = 2

## 费用减免：cost -1 = 多花 3 点（最低 0 费）
const POINTS_PER_COST_REDUCTION: int = 3
const DEFAULT_BASE_COST: int = 1   # spec 没指定 cost 时假设的默认 cost（1 费）


## ============================================================
## 数值上限（按费用分档）— v4 调整
## ============================================================

## key = energy_cost (0~3+)，value = {dmg, armor, heal} 上限
## v4：再次放宽，对齐升级牌强度（\"凤凰击 8伤+3治 1费\" / \"业火 9伤 2费\" 等）
##    让玩家造的牌至少和升级牌池等强，而非弱于
const LIMIT_BY_COST: Dictionary = {
	0: {"damage": 5, "armor": 7, "heal": 4},
	1: {"damage": 8, "armor": 11, "heal": 7},
	2: {"damage": 12, "armor": 15, "heal": 10},
	3: {"damage": 15, "armor": 22, "heal": 13},
}


## ============================================================
## 公开 API
## ============================================================

## 校验 spec 合法性 + 计算总点数
## @param spec  Dictionary（见顶部注释格式）
## @param budget  玩家可用预算（用于检查是否超支）
## @return Dictionary {
##   is_valid: bool,
##   errors: Array[String]（每条一个用户可读错误句）,
##   total_cost: int（spec 总点数）,
##   remaining: int（budget - total_cost）,
##   breakdown: Dictionary（各项成本明细，UI 显示用）
## }
static func validate(spec: Dictionary, budget: int) -> Dictionary:
	var errors: Array[String] = []
	var breakdown: Dictionary = {}

	var damage: int = int(spec.get("damage", 0))
	var armor: int = int(spec.get("armor", 0))
	var heal: int = int(spec.get("heal", 0))
	var cost: int = int(spec.get("energy_cost", DEFAULT_BASE_COST))
	var element: int = int(spec.get("element", CardData.Element.NONE))
	var polarity: int = int(spec.get("polarity", CardData.Polarity.NONE))
	var ignore_armor: bool = bool(spec.get("ignore_armor", false))
	var draw_cards: int = int(spec.get("draw_cards", 0))
	var reflect_damage: int = int(spec.get("reflect_damage", 0))

	# 1. 必须有数值（不能造 0 数值的废牌）
	if damage <= 0 and armor <= 0 and heal <= 0:
		errors.append("⚠ 必须分配至少 1 点到 伤害 / 护甲 / 治疗")

	# 2. 数值不能为负
	if damage < 0:
		errors.append("⚠ 伤害不能为负")
	if armor < 0:
		errors.append("⚠ 护甲不能为负")
	if heal < 0:
		errors.append("⚠ 治疗不能为负")
	if cost < 0:
		errors.append("⚠ 费用不能为负")

	# 3. 必须选 element + polarity
	if element == CardData.Element.NONE:
		errors.append("⚠ 必须选择元素（火/水/木）— 强制纳入克制体系")
	if polarity == CardData.Polarity.NONE:
		errors.append("⚠ 必须选择极性（光/暗）— 强制纳入 2:2 平衡体系")

	# 4. 数值上限按费用分档
	var limit: Dictionary = LIMIT_BY_COST.get(cost, LIMIT_BY_COST[3])  # 3 费以上按 3 费档（保守）
	if damage > int(limit["damage"]):
		errors.append("⚠ %d 费伤害上限 %d，当前 %d" % [cost, int(limit["damage"]), damage])
	if armor > int(limit["armor"]):
		errors.append("⚠ %d 费护甲上限 %d，当前 %d" % [cost, int(limit["armor"]), armor])
	if heal > int(limit["heal"]):
		errors.append("⚠ %d 费治疗上限 %d，当前 %d" % [cost, int(limit["heal"]), heal])

	# 5. 计算总点数（即使有错误也算，方便 UI 反馈）
	var total: float = 0.0

	# 主资源（v2：点数即数值）
	# damage/heal: 1pt = 1 数值
	# armor: 1pt = 1.5 甲（即 ceil(armor / 1.5) 点）
	var dmg_cost: int = damage  # 直接 = 数值
	var armor_cost: int = int(ceil(armor * POINTS_PER_ARMOR))
	var heal_cost: int = heal
	total += dmg_cost + armor_cost + heal_cost
	breakdown["damage_cost"] = dmg_cost
	breakdown["armor_cost"] = armor_cost
	breakdown["heal_cost"] = heal_cost

	# element + polarity 强制开销（仅在已选时计入；未选时另有 errors 提示）
	if element != CardData.Element.NONE:
		total += COST_ELEMENT
		breakdown["element_cost"] = COST_ELEMENT
	if polarity != CardData.Polarity.NONE:
		total += COST_POLARITY
		breakdown["polarity_cost"] = COST_POLARITY

	# 附加效果
	if ignore_armor:
		if damage <= 0:
			errors.append("⚠ 无视护甲必须配伤害（damage>0）")
		else:
			total += COST_IGNORE_ARMOR
			breakdown["ignore_armor_cost"] = COST_IGNORE_ARMOR
	if draw_cards > 0:
		total += draw_cards * COST_DRAW_PER_CARD
		breakdown["draw_cost"] = draw_cards * COST_DRAW_PER_CARD
	if reflect_damage > 0:
		if armor <= 0:
			errors.append("⚠ 反伤通常需要配护甲（armor>0），否则触发不到")
		total += reflect_damage * COST_REFLECT_DAMAGE_PER
		breakdown["reflect_cost"] = reflect_damage * COST_REFLECT_DAMAGE_PER

	# 费用减免：cost < DEFAULT_BASE_COST 时多扣点（鼓励 1 费、惩罚 0 费）
	if cost < DEFAULT_BASE_COST:
		var reduction: int = (DEFAULT_BASE_COST - cost) * POINTS_PER_COST_REDUCTION
		total += reduction
		breakdown["cost_reduction_extra"] = reduction
	# cost > DEFAULT_BASE_COST 时不返还（高费牌靠数值上限放宽自然平衡）

	var total_int: int = int(round(total))
	var remaining: int = budget - total_int

	# 6. 超预算
	if total_int > budget:
		errors.append("⚠ 超出预算：已用 %d / 可用 %d" % [total_int, budget])

	return {
		"is_valid": errors.is_empty(),
		"errors": errors,
		"total_cost": total_int,
		"remaining": remaining,
		"breakdown": breakdown,
	}


## v2 工具：根据玩家\"想花的点数\"反推能买到的数值
## 供 UI 实时显示\"X 点 → Y 数值\"
## @param resource_type "damage" / "armor" / "heal"
## @param points 玩家想花的点数
## @return 能买到的数值
static func points_to_value(resource_type: String, points: int) -> int:
	match resource_type:
		"damage":
			return points  # 1pt = 1 伤
		"armor":
			return int(floor(points * 1.5))  # 1pt = 1.5 甲（向下取整保守）
		"heal":
			return points  # 1pt = 1 治
		_:
			return 0
