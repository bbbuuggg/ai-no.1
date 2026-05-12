---
paths:
  - "tests/**"
---

# 测试规范（GDScript / Godot 4.6）

- 测试命名：`test_[system]_[scenario]_[expected_result]` 模式
- 每个测试必须有清晰的 Arrange / Act / Assert 结构
- 单元测试**不得**依赖外部状态（文件系统、网络、数据库）
- 集成测试必须清理自己（`tearDown` / `queue_free`）
- 性能测试必须指定可接受阈值，超过则失败
- 测试数据在测试里或专用 fixture 定义，**禁止**共享可变状态
- Mock 外部依赖——测试必须快速、确定
- 每个 bug 修复必须配套回归测试（能捕获原 bug）

## Godot 4.6 特定

- 测试框架：GUT（Godot Unit Test）或 GdUnit4
- 测试目录结构：
  ```
  tests/
  ├── unit/               # 单元测试
  │   ├── gameplay/
  │   ├── ui/
  │   └── ai/
  ├── integration/        # 集成测试
  ├── smoke/              # 冒烟测试
  └── fixtures/           # 测试数据
  ```
- 测试脚本头部：
  ```gdscript
  extends GutTest   # 或 GdUnitTestSuite
  class_name TestHealthComponent
  ```

## 示例

**正确**（合规命名 + AAA 结构）：

```gdscript
func test_health_component_take_damage_reduces_current_health() -> void:
    # Arrange
    var health := HealthComponent.new()
    health.max_health = 100.0
    health.current_health = 100.0

    # Act
    health.take_damage(25.0)

    # Assert
    assert_eq(health.current_health, 75.0)
```

**错误**：

```gdscript
func test1() -> void:  # 违规：名字不描述
    var h := HealthComponent.new()
    h.take_damage(25.0)  # 违规：无 Arrange 段，无清晰 Assert
    assert_true(h.current_health < 100.0)  # 违规：断言不精确
```
