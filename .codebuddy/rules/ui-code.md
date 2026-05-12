---
paths:
  - "scripts/ui/**"
  - "res://scripts/ui/**"
---

# UI 代码规则（GDScript / Godot 4.6）

- UI **绝不**拥有或直接修改游戏状态——仅显示，用信号/命令请求变化
- 所有面向用户文字必须走本地化系统——**禁止**硬编码 UI 字符串（用 `TranslationServer` + `.csv`）
- 所有交互元素必须同时支持键鼠和手柄
- 所有动画必须可跳过，并遵守用户动效/可访问性偏好
- UI 音效通过音频事件系统触发，不直接播放（通过 EventBus 或 AudioManager）
- UI **禁止**阻塞主线程（大数据用 `ResourceLoader.load_threaded_*`）
- 可缩放文本与色盲模式是**必须**不是可选
- 所有屏幕在最小和最大支持分辨率下都测试

## Godot 4.6 特定

- 用 `Control` 节点族（`Button`, `Label`, `VBoxContainer` 等）
- 共享 `Theme` 资源于 `res://assets/themes/`
- 锚点（Anchor）优先于硬编码坐标——Control 节点自动缩放
- `GridContainer` / `VBoxContainer` / `HBoxContainer` 优先于手动定位
- UI 信号：按钮 `pressed` / `toggled`、输入框 `text_changed`

## 示例

**正确**（UI 请求，不修改状态）：

```gdscript
# ui/inventory_panel.gd
class_name InventoryPanel extends Control
signal item_use_requested(item: Item)

func _on_use_button_pressed() -> void:
    item_use_requested.emit(selected_item)
    # 状态变化由 gameplay 监听这个信号处理
```

**错误**（UI 直接改状态）：

```gdscript
func _on_use_button_pressed() -> void:
    Player.inventory.remove(selected_item)  # 违规：UI 直接改游戏状态
    Player.heal(selected_item.heal_amount)   # 违规：应发信号
```
