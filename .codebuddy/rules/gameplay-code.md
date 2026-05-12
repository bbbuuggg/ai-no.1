---
paths:
  - "scripts/gameplay/**"
  - "res://scripts/gameplay/**"
---

# 游戏玩法代码规则（GDScript / Godot 4.6）

- 所有游戏数值 **必须**来自外部配置/数据文件（`.tres` Resource 或 `.json`），**禁止**硬编码
- 所有时间相关计算使用 `delta`（帧率无关）
- **禁止**直接引用 UI 代码——用信号/事件做跨系统通信
- 每个游戏系统必须有清晰接口
- 状态机必须有显式转换表和文档化状态
- 游戏逻辑写单元测试——将逻辑与表现分离（用 GUT 或 GdUnit4）
- 代码注释中记录每个功能对应的设计文档路径
- **禁止**用静态单例持有游戏状态——用依赖注入或 EventBus

## 示例

**正确**（数据驱动）：

```gdscript
# config.tres 是 Resource 子类 CombatConfig
var damage: float = config.base_damage
var speed: float = stats_resource.movement_speed * delta
```

**错误**（硬编码）：

```gdscript
var damage: float = 25.0   # 违规：硬编码游戏值
var speed: float = 5.0     # 违规：没从配置来，也没用 delta
```

## Godot 4.6 特定要求

- 优先信号通信：`signal health_changed(new: float, max: float)`
- 场景通信用 EventBus Autoload，避免节点间硬耦合
- 节点引用用 `@onready` + `%UniqueName`，**禁止**在 `_process()` 里 `get_node()`
