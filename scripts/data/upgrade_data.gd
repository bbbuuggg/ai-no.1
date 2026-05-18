class_name UpgradeData
extends Resource
## 升级牌数据 — GDD-08 MIRROR 进度系统
## 每张升级牌满足"双向价值约束"（bidirectional_score ≥ 3）

enum Category { NUMERIC, ATTRIBUTE, KEYWORD, STRUCTURAL }

@export var id: StringName = &""
@export var upgrade_name: String = ""
@export var category: Category = Category.NUMERIC
@export var description: String = ""
@export var bidirectional_score: int = 3  ## 1-5，进池门槛 ≥3
@export var is_repeatable: bool = true    ## 同 Run 内可否重复出现在候选
@export var is_structural: bool = false   ## 结构升级（不替换牌库，NEW-Q1=A）

## 升级效果参数（由 UpgradeRegistry 解读并执行）
@export var effect_id: StringName = &""       ## 效果枚举标识
@export var effect_value: int = 0             ## 效果数值
@export var target_element: int = 0           ## 目标元素（ATTRIBUTE 类用）
@export var target_polarity_flip: bool = false ## 是否翻转光暗（ATTRIBUTE 类用）

## 替换约束：限制只能替换某类牌
@export var replace_type_restriction: int = -1  ## CardData.CardType 枚举，-1=不限
