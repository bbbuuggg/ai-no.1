extends SceneTree
## CustomCardValidator + CustomCardFactory 自检脚本（v0.9.4 PR-2 v2）
##
## v2 兑换：
##   - damage / heal: 1pt = 1 数值
##   - armor: 1pt = 1.5 甲 → 反推：armor 数值 N → 点数 = ceil(N/1.5)
##   - element: 2 点 / polarity: 1 点
##   - ignore_armor: 3 / draw 5 / reflect 2

const Validator = preload("res://scripts/data/custom_card_validator.gd")
const Factory = preload("res://scripts/data/custom_card_factory.gd")

var _passed: int = 0
var _failed: int = 0
var _failed_messages: Array = []


func _init() -> void:
	print("=== CustomCardValidator + Factory 自检 (v2) ===\n")

	_test_basic_validate_pass()
	_test_required_fields()
	_test_value_limits()
	_test_keyword_costs()
	_test_budget_overflow()
	_test_points_to_value()
	_test_factory_basic()
	_test_factory_naming_and_desc()

	print("\n=== 汇总 ===")
	print("通过: %d" % _passed)
	print("失败: %d" % _failed)
	if _failed > 0:
		print("\n失败详情：")
		for msg in _failed_messages:
			print("  ✗ %s" % msg)
		quit(1)
	else:
		print("✓ 全部通过")
		quit(0)


## ============================================================
## Validator 测试
## ============================================================

## T1: 合法 spec 通过
func _test_basic_validate_pass() -> void:
	# v3：element 1 + polarity 0 = 1 点
	# 6 伤 1 费 fire light：dmg=6 + element 1 + polarity 0 = 7 点
	var spec: Dictionary = {
		"damage": 6, "energy_cost": 1,
		"element": CardData.Element.FIRE,
		"polarity": CardData.Polarity.LIGHT,
	}
	var r: Dictionary = Validator.validate(spec, 10)
	_assert_true("T1.1 6伤1费 fire light 合法", r["is_valid"])
	_assert_int_eq("T1.2 总点数 = 7", 7, int(r["total_cost"]))
	_assert_int_eq("T1.3 剩余 = 3", 3, int(r["remaining"]))


## T2: 必填字段
func _test_required_fields() -> void:
	# 缺 element
	var spec1: Dictionary = {
		"damage": 4, "energy_cost": 1,
		"polarity": CardData.Polarity.LIGHT,
	}
	var r1: Dictionary = Validator.validate(spec1, 10)
	_assert_false("T2.1 缺 element 应不通过", r1["is_valid"])

	# 缺 polarity
	var spec2: Dictionary = {
		"damage": 4, "energy_cost": 1,
		"element": CardData.Element.FIRE,
	}
	var r2: Dictionary = Validator.validate(spec2, 10)
	_assert_false("T2.2 缺 polarity 应不通过", r2["is_valid"])

	# 全 0 数值
	var spec3: Dictionary = {
		"damage": 0, "armor": 0, "heal": 0, "energy_cost": 1,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var r3: Dictionary = Validator.validate(spec3, 10)
	_assert_false("T2.3 全 0 数值应不通过", r3["is_valid"])


## T3: 数值上限（按费用分档）
func _test_value_limits() -> void:
	# v4：0 费 dmg 上限 5，dmg=6 应 fail
	var spec1: Dictionary = {
		"damage": 6, "energy_cost": 0,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var r1: Dictionary = Validator.validate(spec1, 20)
	_assert_false("T3.1 0费 dmg=6 应超上限（新上限 5）", r1["is_valid"])

	# v4：1 费 dmg 上限 8，dmg=8 应 pass
	var spec2: Dictionary = {
		"damage": 8, "energy_cost": 1,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var r2: Dictionary = Validator.validate(spec2, 12)
	_assert_true("T3.2 1费 dmg=8 应在上限内（新上限 8）", r2["is_valid"])

	# v4：1 费 armor 上限 11，armor=11 应 pass
	var spec3: Dictionary = {
		"armor": 11, "energy_cost": 1,
		"element": CardData.Element.WATER, "polarity": CardData.Polarity.DARK,
	}
	var r3: Dictionary = Validator.validate(spec3, 14)
	_assert_true("T3.3 1费 armor=11 应在上限内（新上限 11）", r3["is_valid"])

	# v4：1 费 armor=12 应 fail
	var spec4: Dictionary = {
		"armor": 12, "energy_cost": 1,
		"element": CardData.Element.WATER, "polarity": CardData.Polarity.DARK,
	}
	var r4: Dictionary = Validator.validate(spec4, 20)
	_assert_false("T3.4 1费 armor=12 应超上限", r4["is_valid"])

	# v4：3 费 dmg 上限 15
	var spec5: Dictionary = {
		"damage": 15, "energy_cost": 3,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.DARK,
	}
	var r5: Dictionary = Validator.validate(spec5, 20)
	_assert_true("T3.5 3费 dmg=15 应在上限内（新上限 15）", r5["is_valid"])


## T4: 附加效果开销
func _test_keyword_costs() -> void:
	# v3：element 1 + polarity 0
	# 6 伤 + 无视甲 1 费 fire light：dmg 6 + element 1 + polarity 0 + ignore 3 = 10
	var spec1: Dictionary = {
		"damage": 6, "energy_cost": 1,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
		"ignore_armor": true,
	}
	var r1: Dictionary = Validator.validate(spec1, 14)
	_assert_int_eq("T4.1 6伤+无视甲点数 = 10", 10, int(r1["total_cost"]))

	# 4 甲 + 反伤 2 1 费 water dark
	# armor 数值 4 → 点数 ceil(4/1.5) = 3
	# element 1 + polarity 0 + reflect 2*2=4
	# 合计 3+1+0+4 = 8
	var spec2: Dictionary = {
		"armor": 4, "energy_cost": 1, "reflect_damage": 2,
		"element": CardData.Element.WATER, "polarity": CardData.Polarity.DARK,
	}
	var r2: Dictionary = Validator.validate(spec2, 12)
	_assert_int_eq("T4.2 4甲+反2点数 = 8", 8, int(r2["total_cost"]))

	# 仅抽 1 无主数值应 fail
	var spec3: Dictionary = {
		"draw_cards": 1, "energy_cost": 1,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var r3: Dictionary = Validator.validate(spec3, 12)
	_assert_false("T4.3 仅抽1无数值应 fail", r3["is_valid"])

	# 4 伤 + 抽 1 1 费：dmg 4 + element 1 + polarity 0 + draw 5 = 10
	var spec4: Dictionary = {
		"damage": 4, "draw_cards": 1, "energy_cost": 1,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var r4: Dictionary = Validator.validate(spec4, 14)
	_assert_int_eq("T4.4 4伤+抽1点数 = 10", 10, int(r4["total_cost"]))


## T5: 超预算
func _test_budget_overflow() -> void:
	# v3：9 伤 2 费 fire light：dmg 9 + element 1 + polarity 0 = 10
	var spec: Dictionary = {
		"damage": 9, "energy_cost": 2,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var r: Dictionary = Validator.validate(spec, 8)  # budget 8 不够
	_assert_false("T5.1 超预算应不通过", r["is_valid"])
	_assert_int_eq("T5.2 总 = 10", 10, int(r["total_cost"]))
	_assert_int_eq("T5.3 剩余 = -2", -2, int(r["remaining"]))


## T6: points_to_value 工具
func _test_points_to_value() -> void:
	_assert_int_eq("T6.1 6pt damage = 6 伤", 6, Validator.points_to_value("damage", 6))
	_assert_int_eq("T6.2 4pt armor = 6 甲", 6, Validator.points_to_value("armor", 4))
	_assert_int_eq("T6.3 5pt heal = 5 治", 5, Validator.points_to_value("heal", 5))
	_assert_int_eq("T6.4 1pt armor = 1 甲（floor 1.5）", 1, Validator.points_to_value("armor", 1))
	_assert_int_eq("T6.5 6pt armor = 9 甲", 9, Validator.points_to_value("armor", 6))


## ============================================================
## Factory 测试
## ============================================================

func _test_factory_basic() -> void:
	var spec: Dictionary = {
		"damage": 6, "energy_cost": 1,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var card: CardData = Factory.build_card_data(spec, 3, 0)

	_assert_str_eq("T7.1 id 格式正确", "up_custom_r3_0", String(card.id))
	_assert_int_eq("T7.2 damage=6", 6, card.damage)
	_assert_int_eq("T7.3 cost=1", 1, card.energy_cost)
	_assert_int_eq("T7.4 element=FIRE", int(CardData.Element.FIRE), int(card.element))
	_assert_int_eq("T7.5 polarity=LIGHT", int(CardData.Polarity.LIGHT), int(card.polarity))
	_assert_int_eq("T7.6 type 推断为 ATTACK", int(CardData.CardType.ATTACK), int(card.type))


func _test_factory_naming_and_desc() -> void:
	# 火光击
	var spec1: Dictionary = {
		"damage": 6, "energy_cost": 1,
		"element": CardData.Element.FIRE, "polarity": CardData.Polarity.LIGHT,
	}
	var c1: CardData = Factory.build_card_data(spec1, 3, 0)
	_assert_str_eq("T8.1 火光击命名", "火光·击", c1.card_name)
	_assert_str_eq("T8.2 描述 = 6伤", "6伤", c1.description)

	# 水暗盾 + 反伤
	var spec2: Dictionary = {
		"armor": 6, "reflect_damage": 2, "energy_cost": 2,
		"element": CardData.Element.WATER, "polarity": CardData.Polarity.DARK,
	}
	var c2: CardData = Factory.build_card_data(spec2, 4, 1)
	_assert_str_eq("T8.3 水暗盾命名", "水暗·盾", c2.card_name)
	_assert_str_eq("T8.4 描述含护甲+反伤", "6甲, 反2", c2.description)

	# 木光治疗
	var spec3: Dictionary = {
		"heal": 5, "energy_cost": 1,
		"element": CardData.Element.WOOD, "polarity": CardData.Polarity.LIGHT,
	}
	var c3: CardData = Factory.build_card_data(spec3, 2, 0)
	_assert_str_eq("T8.5 木光愈命名", "木光·愈", c3.card_name)


## ============================================================
## 工具
## ============================================================

func _assert_true(name: String, cond: bool) -> void:
	if cond:
		_record_pass(name)
	else:
		_record_fail(name + " 期望 true 实际 false")


func _assert_false(name: String, cond: bool) -> void:
	if not cond:
		_record_pass(name)
	else:
		_record_fail(name + " 期望 false 实际 true")


func _assert_int_eq(name: String, expected: int, actual: int) -> void:
	if expected == actual:
		_record_pass("%s = %d" % [name, actual])
	else:
		_record_fail("%s 期望 %d 实际 %d" % [name, expected, actual])


func _assert_str_eq(name: String, expected: String, actual: String) -> void:
	if expected == actual:
		_record_pass("%s = '%s'" % [name, actual])
	else:
		_record_fail("%s 期望 '%s' 实际 '%s'" % [name, expected, actual])


func _record_pass(msg: String) -> void:
	_passed += 1
	print("  ✓ %s" % msg)


func _record_fail(msg: String) -> void:
	_failed += 1
	_failed_messages.append(msg)
	print("  ✗ %s" % msg)
