---
paths:
  - "scripts/core/**"
  - "scripts/engine/**"
  - "res://scripts/core/**"
---

# 引擎代码规则（GDScript / Godot 4.6）

- 热路径（`_process` / `_physics_process` / 渲染）**零分配** —— 预分配、对象池、复用
- 所有引擎 API 要么线程安全，要么显式注明"仅单线程"
- 优化前后都要 profile——记录测量数字
- 引擎代码**不可**依赖游戏玩法代码（严格依赖方向：engine ← gameplay）
- 每个公开 API 必须在文档注释里有使用示例
- 公开接口变更需要弃用期与迁移指南
- 所有资源用 RAII / 确定性清理（`queue_free()`、`tree_exited` 信号）
- 所有引擎系统必须支持优雅降级
- 写引擎 API 代码前查阅 `docs/engine-reference/`，以参考文档为准

## 示例

**正确**（零分配热路径）：

```gdscript
# 预分配的数组每帧复用
var _nearby_cache: Array[Node3D] = []

func _physics_process(_delta: float) -> void:
    _nearby_cache.clear()  # 复用，不重新分配
    _spatial_grid.query_radius(position, radius, _nearby_cache)
```

**错误**（热路径分配）：

```gdscript
func _physics_process(_delta: float) -> void:
    var nearby: Array[Node3D] = []  # 违规：每帧分配
    nearby = get_tree().get_nodes_in_group("enemies")  # 违规：每帧树查询
```

## Godot 4.6 特定要求

- Autoload 白名单：EventBus / GameManager / SaveManager / AudioManager
- 新增 Autoload 需技术总监批准 ADR
- Autoload **禁止**持有场景特定节点引用
- 频繁字符串比较用 `StringName`（`&"state_name"`）
