extends SceneTree
## DeckValueCalculator 自检脚本（v0.9.4 PR-1）
##
## 运行方式（项目根目录）：
##   "D:\Godot_GDScript\Godot_v4.6.2-stable_win64.exe" --headless --path . --script tests/deck_value_calculator_check.gd
##
## 退出码：
##   0 = 全部通过
##   1 = 至少一个用例失败
##
## 注：CLI --script 模式下 class_name 全局可能未注册，使用 preload 直接拿到脚本
const DVC = preload("res://scripts/utils/deck_value_calculator.gd")

var _passed: int = 0
var _failed: int = 0
var _failed_messages: Array = []


func _init() -> void:
	print("=== DeckValueCalculator 自检 ===\n")

	_test_single_card_basic()
	_test_single_card_keywords()
	_test_deck_total_value()
	_test_budget_formula()
	_test_budget_clamp()
	_test_round_baseline()

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
## 测试用例
## ============================================================

func _test_single_card_basic() -> void:
	# 4 伤 1 费 → 4 - 1 = 3.0
	var c1: CardData = _make_card(4, 0, 0, 1, CardData.Element.NONE, CardData.Polarity.NONE)
	_assert_close("T1.1 4伤1费裸数值", 3.0, DVC.calc_card_value(c1))

	# 4 伤 1 费 fire light → 4 - 1 + 1.5 + 1.0 = 5.5
	var c2: CardData = _make_card(4, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT)
	_assert_close("T1.2 4伤1费 fire light", 5.5, DVC.calc_card_value(c2))

	# 6 甲 1 费 fire light → 6×0.7 - 1 + 1.5 + 1.0 = 5.7
	var c3: CardData = _make_card(0, 6, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT)
	_assert_close("T1.3 6甲1费", 5.7, DVC.calc_card_value(c3))

	# 5 治 1 费 water light → 5 - 1 + 1.5 + 1.0 = 6.5
	var c4: CardData = _make_card(0, 0, 5, 1, CardData.Element.WATER, CardData.Polarity.LIGHT)
	_assert_close("T1.4 5治1费", 6.5, DVC.calc_card_value(c4))

	# 0 费 0 数值 fire light → 1.5 + 1.0 = 2.5
	var c5: CardData = _make_card(0, 0, 0, 0, CardData.Element.FIRE, CardData.Polarity.LIGHT)
	_assert_close("T1.5 0费空牌", 2.5, DVC.calc_card_value(c5))

	_assert_close("T1.6 null 卡", 0.0, DVC.calc_card_value(null))


func _test_single_card_keywords() -> void:
	# 8 伤 2 费 fire dark + 无视甲 → 8 - 2 + 1.5 + 1.0 + 1.5 = 10.0
	var c1: CardData = _make_card(8, 0, 0, 2, CardData.Element.FIRE, CardData.Polarity.DARK)
	c1.ignore_armor = true
	_assert_close("T2.1 8伤2费+无视甲", 10.0, DVC.calc_card_value(c1))

	# 抽 1 牌 1 费 → 1×2.5 - 1 = 1.5
	var c2: CardData = _make_card(0, 0, 0, 1, CardData.Element.NONE, CardData.Polarity.NONE)
	c2.draw_cards = 1
	_assert_close("T2.2 抽1牌1费", 1.5, DVC.calc_card_value(c2))

	# 反伤 2 + 4 甲 1 费 fire light → 4×0.7 - 1 + 1.5 + 1.0 + 2×0.8 = 5.9
	var c3: CardData = _make_card(0, 4, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT)
	c3.reflect_damage = 2
	_assert_close("T2.3 4甲+反伤2", 5.9, DVC.calc_card_value(c3))

	# 多段 hits=2 4 伤 fire light 1 费 → 4 + 1×0.5×4 = 6 - 1 + 1.5 + 1.0 = 7.5
	var c4: CardData = _make_card(4, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT)
	c4.hits = 2
	_assert_close("T2.4 多段攻击 hits=2", 7.5, DVC.calc_card_value(c4))


func _test_deck_total_value() -> void:
	var deck: Array = []
	# 4 伤 1 费 fire light × 2 → 5.5 × 2 = 11
	deck.append(_make_card(4, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT))
	deck.append(_make_card(4, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT))
	# 5 伤 2 费 fire dark × 2 → 5.5 × 2 = 11
	deck.append(_make_card(5, 0, 0, 2, CardData.Element.FIRE, CardData.Polarity.DARK))
	deck.append(_make_card(5, 0, 0, 2, CardData.Element.FIRE, CardData.Polarity.DARK))
	# 4 甲 1 费 water light × 2 → 4.3 × 2 = 8.6
	deck.append(_make_card(0, 4, 0, 1, CardData.Element.WATER, CardData.Polarity.LIGHT))
	deck.append(_make_card(0, 4, 0, 1, CardData.Element.WATER, CardData.Polarity.LIGHT))
	# 6 甲 2 费 water dark × 2 → 4.7 × 2 = 9.4
	deck.append(_make_card(0, 6, 0, 2, CardData.Element.WATER, CardData.Polarity.DARK))
	deck.append(_make_card(0, 6, 0, 2, CardData.Element.WATER, CardData.Polarity.DARK))
	# 3 治 1 费 wood light × 2 → 4.5 × 2 = 9.0
	deck.append(_make_card(0, 0, 3, 1, CardData.Element.WOOD, CardData.Polarity.LIGHT))
	deck.append(_make_card(0, 0, 3, 1, CardData.Element.WOOD, CardData.Polarity.LIGHT))
	# 2 伤 0 费 wood dark → 4.5
	deck.append(_make_card(2, 0, 0, 0, CardData.Element.WOOD, CardData.Polarity.DARK))

	# 总值 = 11+11+8.6+9.4+9.0+4.5 = 53.5
	_assert_close("T3.1 11张完整牌库总值", 53.5, DVC.calc_deck_value(deck))
	_assert_close("T3.2 空牌库", 0.0, DVC.calc_deck_value([]))


func _test_budget_formula() -> void:
	# 持平：5 张 8伤1费 fire light，单张 9.5 → 总 47.5
	var deck_a: Array = []
	for i in range(5):
		deck_a.append(_make_card(8, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT))
	var deck_b: Array = []
	for i in range(5):
		deck_b.append(_make_card(8, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT))
	var r1: Dictionary = DVC.calc_budget(deck_a, deck_b, 3)
	# v4：R3 base 上调 9 → 13
	_assert_int_eq("T4.1 持平 R3 应=base 13", 13, int(r1["budget"]))

	# 玩家落后：deck_strong 单张 11.5，5 张 57.5；与 47.5 差 10
	# adjust = round(10×0.4) = 4 → budget = 9+4 = 13
	var deck_strong: Array = []
	for i in range(5):
		deck_strong.append(_make_card(10, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT))
	# v4：玩家落后 10 价值，adjust=+4 → 13+4=17
	var r2: Dictionary = DVC.calc_budget(deck_a, deck_strong, 3)
	_assert_int_eq("T4.2 玩家落后 10 价值 R3 budget=17", 17, int(r2["budget"]))

	# v4：玩家领先 10：adjust=-4 → 13-4=9
	var r3: Dictionary = DVC.calc_budget(deck_strong, deck_a, 3)
	_assert_int_eq("T4.3 玩家领先 10 价值 R3 budget=9", 9, int(r3["budget"]))


func _test_budget_clamp() -> void:
	var weak: Array = []
	for i in range(11):
		weak.append(_make_card(1, 0, 0, 2, CardData.Element.NONE, CardData.Polarity.NONE))
	var strong: Array = []
	for i in range(11):
		strong.append(_make_card(15, 0, 0, 0, CardData.Element.FIRE, CardData.Polarity.LIGHT))

	var r1: Dictionary = DVC.calc_budget(weak, strong, 3)
	var v1: int = int(r1["budget"])
	if v1 < 4 or v1 > 18:
		_record_fail("T5.1 极端弱 vs 极强：budget=%d 应在 [4,18]" % v1)
	else:
		_record_pass("T5.1 极端弱 vs 极强：budget=%d ∈ [4,18]" % v1)

	var r2: Dictionary = DVC.calc_budget(strong, weak, 3)
	# v4：base=13 + 极端领先 adjust=-5（MAX_GAP_ADJUST 上限）= 8，仍在 MIN 之上
	_assert_int_eq("T5.2 玩家极强 R3 budget=8", 8, int(r2["budget"]))


func _test_round_baseline() -> void:
	var deck_a: Array = []
	var deck_b: Array = []
	for i in range(5):
		deck_a.append(_make_card(8, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT))
		deck_b.append(_make_card(8, 0, 0, 1, CardData.Element.FIRE, CardData.Polarity.LIGHT))

	# v4：基础预算上调 R2/R3/R4 = 10/13/15
	_assert_int_eq("T6.1 R2 持平 base", 10, int(DVC.calc_budget(deck_a, deck_b, 2)["budget"]))
	_assert_int_eq("T6.2 R3 持平 base", 13, int(DVC.calc_budget(deck_a, deck_b, 3)["budget"]))
	_assert_int_eq("T6.3 R4 持平 base", 15, int(DVC.calc_budget(deck_a, deck_b, 4)["budget"]))
	_assert_int_eq("T6.4 R99 未知轮次默认 6", 6, int(DVC.calc_budget(deck_a, deck_b, 99)["budget"]))


## ============================================================
## 工具
## ============================================================

func _make_card(dmg: int, arm: int, hl: int, cost: int, elem: int, pol: int) -> CardData:
	var c: CardData = CardData.new()
	c.id = &"test_card"
	c.card_name = "Test"
	c.damage = dmg
	c.armor = arm
	c.heal = hl
	c.energy_cost = cost
	c.element = elem
	c.polarity = pol
	return c


func _assert_close(name: String, expected: float, actual: float, eps: float = 0.01) -> void:
	if absf(expected - actual) <= eps:
		_record_pass("%s = %.2f" % [name, actual])
	else:
		_record_fail("%s 期望 %.2f 实际 %.2f" % [name, expected, actual])


func _assert_int_eq(name: String, expected: int, actual: int) -> void:
	if expected == actual:
		_record_pass("%s = %d" % [name, actual])
	else:
		_record_fail("%s 期望 %d 实际 %d" % [name, expected, actual])


func _record_pass(msg: String) -> void:
	_passed += 1
	print("  ✓ %s" % msg)


func _record_fail(msg: String) -> void:
	_failed += 1
	_failed_messages.append(msg)
	print("  ✗ %s" % msg)
