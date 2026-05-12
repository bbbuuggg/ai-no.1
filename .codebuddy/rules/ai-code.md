---
paths:
  - "scripts/ai/**"
  - "res://scripts/ai/**"
---

# AI 代码规则（GDScript / Godot 4.6）

- AI 每帧预算：最多 2ms —— profile 验证
- 所有 AI 参数必须从数据文件可调（行为树权重、感知范围、计时器）——用 `Resource` 子类
- AI 必须可调试：为所有 AI 状态实现可视化 hook（路径、感知圆锥、决策树）
- AI 必须"预兆"意图——给玩家读懂并反应的时间
- 优先效用型或行为树方法，避免硬编码 if/else 链
- 群体 AI 必须支持数据驱动的阵型、包抄、角色分配
- 所有 AI 状态机转换必须打 log（调试）
- **禁止**未经验证信任来自网络的 AI 输入

## Godot 4.6 特定

- 状态机推荐两种实现：
  - 简单：enum + match 语句（小型 NPC）
  - 复杂：节点级状态机（每个状态一个子 Node，实现 enter/exit/process）
- 行为树可用 `LimboAI` addon（技术总监批准后）或自实现
- 感知用 `Area2D` / `Area3D` + signal
- 路径查找用 `NavigationAgent2D` / `NavigationAgent3D`（见 `docs/engine-reference/modules/navigation.md`）

## 示例

**正确**（数据驱动 + 可调试）：

```gdscript
class_name EnemyAI extends Node
@export var ai_data: AIBehaviorData   # Resource 子类
@onready var debug_draw: DebugDrawHelper = %DebugDraw

func _ready() -> void:
    print_log("AI init: %s" % ai_data.behavior_name)

func transition_state(from: State, to: State) -> void:
    print_log("AI transition: %s -> %s" % [State.keys()[from], State.keys()[to]])
    debug_draw.mark_transition(global_position)
```
