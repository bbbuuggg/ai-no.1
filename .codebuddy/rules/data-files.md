---
paths:
  - "assets/data/**"
  - "res://assets/data/**"
---

# 数据文件规则（Godot 4.6）

本项目数据文件优先使用 Godot 原生 **Resource（`.tres`）**，次选 JSON。

## Resource (.tres) —— 推荐

Godot 4.6 的 `Resource` 子类提供类型安全、编辑器集成、Git diff 友好，**比 JSON 更推荐**。

```gdscript
# scripts/data/enemy_data.gd
class_name EnemyData extends Resource

@export var enemy_name: String = ""
@export var base_health: float = 50.0
@export var base_damage: float = 8.0
@export var move_speed: float = 3.5
@export var loot_table: LootTableData  # 引用另一个 Resource
```

然后在编辑器里右键 → New Resource → EnemyData，填参数，另存为 `res://assets/data/enemies/goblin.tres`。

## JSON —— 仅当需要外部工具编辑时

- 所有 JSON 文件必须是有效 JSON——损坏 JSON 会阻塞整条构建管线
- 文件命名：小写下划线，遵循 `[system]_[name].json` 模式
- 每个数据文件必须有文档化 schema（JSON Schema 或设计文档中描述）
- 数值必须有注释或伴随文档解释含义
- JSON 内 key 用 camelCase
- **禁止**孤立数据——每条都必须被代码或其他数据文件引用
- Breaking schema 变更时给数据文件打版本
- 所有可选字段提供合理默认值

## 示例

**正确** (`combat_enemies.json`)：

```json
{
  "goblin": {
    "baseHealth": 50,
    "baseDamage": 8,
    "moveSpeed": 3.5,
    "lootTable": "loot_goblin_common"
  }
}
```

**错误** (`EnemyData.json`)：

```json
{ "Goblin": { "hp": 50 } }
```

违规：大写文件名、大写 key、不符合 `[system]_[name]` 模式、字段不完整。

## 目录规范

```
res://assets/data/
├── enemies/            # .tres 敌人数据
├── weapons/            # .tres 武器数据
├── loot_tables/        # .tres 掉落表
├── config/             # 全局配置
│   └── combat_config.tres
└── json/               # 仅当外部工具生成时
    └── level_layouts.json
```
