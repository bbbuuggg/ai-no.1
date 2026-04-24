# AINo.1 项目约定文档 (CONVENTIONS)

> 本文档为 AI 辅助开发（Vibe Coding）的核心参考规范。  
> 所有 AI 生成的代码、场景和资源必须遵循以下约定。

---

## 1. 基础信息

| 项目属性 | 值 |
|---------|-----|
| 项目名称 | AINo.1 |
| Godot 版本 | 4.6 |
| 渲染器 | Forward+ |
| 脚本语言 | **GDScript（禁止使用 C#）** |
| 主场景 | `res://scenes/main.tscn` |

---

## 2. 目录结构

```
res://
├── scenes/              # 所有场景文件 (.tscn)
│   ├── main.tscn        # 主场景 / 入口场景
│   ├── levels/          # 关卡场景
│   ├── characters/      # 角色场景（玩家、敌人、NPC）
│   └── ui/              # UI 场景
├── scripts/             # 所有 GDScript 脚本 (.gd)
│   ├── player.gd        # 玩家控制脚本
│   ├── enemies/         # 敌人脚本
│   ├── systems/         # 系统脚本（伤害、存档等）
│   └── utils/           # 工具函数脚本
├── assets/              # 静态资源
│   ├── sprites/         # 2D 贴图、精灵表
│   ├── models/          # 3D 模型 (.glb, .gltf)
│   ├── audio/           # 音效和音乐 (.wav, .ogg, .mp3)
│   └── fonts/           # 字体文件 (.ttf, .otf)
├── ui/                  # UI 专用资源（主题、样式）
├── autoload/            # 全局单例脚本（AutoLoad）
├── resources/           # .tres 资源文件（材质、动画库等）
├── addons/              # 编辑器插件
│   └── godot_mcp/       # MCP 通信插件
└── icon.svg             # 项目图标
```

### 文件放置规则

- `.tscn` 场景文件 → `scenes/` 及其子目录
- `.gd` 脚本文件 → `scripts/` 及其子目录
- 图片 / 贴图 → `assets/sprites/`
- 音频文件 → `assets/audio/`
- 3D 模型 → `assets/models/`
- 全局管理器 → `autoload/`
- **禁止**在项目根目录直接放置 `.gd` 或 `.tscn` 文件

---

## 3. 命名规范

### 节点命名 — PascalCase

```
Player, EnemyGoblin, HealthBar, MainCamera, CollisionShape2D
```

### 脚本变量 / 函数 — snake_case

```gdscript
var move_speed = 300.0
var is_on_ground = false
func take_damage(amount: int) -> void:
func _on_button_pressed() -> void:
```

### 常量 — UPPER_SNAKE_CASE

```gdscript
const MAX_HEALTH = 100
const GRAVITY = 980.0
const JUMP_VELOCITY = -400.0
```

### 信号 — snake_case（过去时态）

```gdscript
signal health_changed(new_value: int)
signal died
signal item_collected(item_name: String)
```

### 文件名 — snake_case

```
player.gd, enemy_goblin.gd, main_menu.tscn, health_bar.tscn
```

---

## 4. 输入映射（Input Map）

> **核心规则：禁止使用 `ui_*` 系列内置动作控制角色行为。**  
> 所有游戏逻辑必须使用以下自定义动作名。

### 移动

| 动作名 | 主键 | 备选键 | 用途 |
|--------|------|--------|------|
| `move_left` | A | Left Arrow | 向左移动 |
| `move_right` | D | Right Arrow | 向右移动 |
| `move_up` | W | Up Arrow | 向上移动 |
| `move_down` | S | Down Arrow | 向下移动 |

### 动作

| 动作名 | 主键 | 备选键 | 用途 |
|--------|------|--------|------|
| `jump` | Space | — | 跳跃 |
| `attack` | Mouse Left | J | 攻击 |
| `interact` | E | F | 交互（对话、拾取） |
| `dash` | Shift | — | 冲刺 / 闪避 |

### 系统

| 动作名 | 主键 | 备选键 | 用途 |
|--------|------|--------|------|
| `pause` | Escape | — | 暂停 / 菜单 |
| `inventory` | Tab | I | 打开背包 |

### 在脚本中使用输入

```gdscript
# ✅ 正确：使用自定义动作
var direction = Input.get_axis("move_left", "move_right")
if Input.is_action_just_pressed("jump"):
if Input.is_action_just_pressed("attack"):

# ❌ 错误：禁止使用内置 UI 动作控制角色
var direction = Input.get_axis("ui_left", "ui_right")   # 不要这样做
if Input.is_action_just_pressed("ui_accept"):             # 不要这样做
```

---

## 5. 碰撞层约定

| 层编号 | 名称 | 用途 |
|--------|------|------|
| 1 | Player | 玩家角色 |
| 2 | Enemy | 敌人 |
| 3 | Terrain | 地形、平台、墙壁 |
| 4 | Projectile | 子弹、投射物 |
| 5 | Pickup | 可拾取物品 |
| 6 | Trigger | 触发区域（不产生物理碰撞） |

### 碰撞矩阵

- **Player (1)**：检测 Terrain (3)、Enemy (2)、Pickup (5)、Trigger (6)
- **Enemy (2)**：检测 Terrain (3)、Player (1)、Projectile (4)
- **Projectile (4)**：检测 Enemy (2)、Terrain (3)

---

## 6. 场景节点结构约定

### 2D 角色（CharacterBody2D）

```
Player (CharacterBody2D)
├── Sprite2D                 # 角色外观
├── CollisionShape2D         # 碰撞形状
├── AnimationPlayer          # 动画控制
├── HitboxArea (Area2D)      # 攻击判定区域（可选）
│   └── CollisionShape2D
└── HurtboxArea (Area2D)     # 受伤判定区域（可选）
	└── CollisionShape2D
```

### 3D 角色（CharacterBody3D）

```
Player (CharacterBody3D)
├── MeshInstance3D / Model   # 角色模型
├── CollisionShape3D         # 碰撞形状
├── AnimationPlayer          # 动画控制
├── Camera3D                 # 摄像机（可选）
└── NavigationAgent3D        # 寻路（NPC 用）
```

### 关卡场景

```
Level (Node2D / Node3D)
├── Environment              # 环境（光照、天空）
├── Terrain                  # 地形
├── SpawnPoints              # 出生点
├── Enemies                  # 敌人容器
├── Pickups                  # 拾取物容器
└── Camera                   # 摄像机
```

---

## 7. 脚本结构约定

每个 GDScript 文件应按以下顺序组织：

```gdscript
extends CharacterBody2D
class_name Player           # 可选：全局类名

## ---- 信号 ----
signal health_changed(value: int)
signal died

## ---- 导出变量 ----
@export var max_health: int = 100
@export var move_speed: float = 300.0

## ---- 常量 ----
const JUMP_VELOCITY = -400.0

## ---- 成员变量 ----
var current_health: int = 100
var is_alive: bool = true

## ---- @onready 引用 ----
@onready var sprite = $Sprite2D
@onready var anim_player = $AnimationPlayer

## ---- 生命周期函数 ----
func _ready() -> void:
	pass

func _physics_process(delta: float) -> void:
	pass

func _input(event: InputEvent) -> void:
	pass

## ---- 公共方法 ----
func take_damage(amount: int) -> void:
	pass

## ---- 私有方法 ----
func _update_animation() -> void:
	pass

## ---- 信号回调 ----
func _on_area_body_entered(body: Node2D) -> void:
	pass
```

---

## 8. AutoLoad 全局单例约定

| 单例名 | 脚本路径 | 用途 |
|--------|----------|------|
| GameManager | `res://autoload/game_manager.gd` | 游戏状态、场景切换 |
| AudioManager | `res://autoload/audio_manager.gd` | 音频管理 |
| SaveManager | `res://autoload/save_manager.gd` | 存档读档 |
| EventBus | `res://autoload/event_bus.gd` | 全局事件总线 |

> 仅在需要时创建单例，不必一开始全部创建。

---

## 9. AI 协作注意事项

1. **始终通过 MCP 工具操作编辑器**，不要让用户手动在编辑器中操作。
2. **节点路径使用相对路径 `.`**（不要使用 `/root/` 绝对路径），以确保保存到 `.tscn` 文件。
3. **每次创建完节点后及时保存场景** (`scene_management.save`)。
4. **修改脚本后需要重新运行场景** 才能看到效果。
5. **新创建的输入动作** 需要重启游戏才能生效（editor 中修改会写入 `project.godot`）。

---

## 10. MCP 操作陷阱清单（必读）

> 以下均为实际开发中踩过的坑，AI 在每次操作前必须检查是否会触发这些陷阱。

### 陷阱 1：节点创建路径错误导致不保存

```
❌ 错误操作：
   node_lifecycle.create → parent_path: "/root"  或  "/root/Main"
   结果：节点挂载到运行时 SceneTree，不属于 .tscn 文件，保存后丢失。

✅ 正确操作：
   node_lifecycle.create → parent_path: "."      （场景根节点）
   node_lifecycle.create → parent_path: "Player"  （根节点的子节点）
   结果：节点属于当前编辑的场景，保存后持久存在。

🔍 验证方法：
   创建后调用 scene_hierarchy.get_tree 确认节点出现在树中。
```

### 陷阱 2：移动资源后引用断裂

```
❌ 错误操作：
   resource_manage.move 移动 .gd 或 .tscn 文件后不更新引用。
   结果：场景中脚本引用仍指向旧路径 → "File not found" 错误。

✅ 正确操作：
   移动文件后必须执行以下步骤：
   1. scene_management.open  → 打开引用该资源的场景
   2. script_attach.detach   → 卸载旧路径脚本
   3. script_attach.attach   → 挂载新路径脚本
   4. scene_management.save  → 保存场景
   对于 .tscn 场景文件的移动，还需更新 project_settings 中的 main_scene 路径。

🔍 检查清单：
   移动任何文件后，搜索项目中所有 .tscn 文件确认无断裂引用。
```

### 陷阱 3：使用内置 ui_* 动作控制角色

```
❌ 错误操作：
   Input.get_axis("ui_left", "ui_right")
   结果：A/D 键被 Godot UI 焦点系统拦截，只有方向键有效。

✅ 正确操作：
   使用项目自定义的动作名（见第 4 节输入映射表）。
   Input.get_axis("move_left", "move_right")

📌 根因：
   ui_* 是引擎保留用于 UI 控件焦点导航的，混用会被 UI 层拦截。
```

### 陷阱 4：创建 CollisionShape 后忘记设置形状

```
❌ 错误操作：
   node_lifecycle.create → type: "CollisionShape2D" → 完毕
   结果：运行时警告 "CollisionShape2D: A shape must be provided"，碰撞无效。

✅ 正确操作：
   创建节点后立即调用：
   physics_collision_shape.create_box / create_sphere / create_capsule
   为其指定具体的形状和尺寸。
```

### 陷阱 5：动画只建了资源没添加轨道和关键帧

```
❌ 错误操作：
   animation_animation.create → name: "walk" → 完毕
   结果：动画存在但播放时无任何视觉效果。

✅ 正确操作：
   创建动画后必须完成以下步骤：
   1. animation_track.add_property_track → 添加属性轨道（如 "Sprite2D:scale"）
   2. animation_track.add_key → 至少添加 2 个关键帧（起始帧 + 结束帧）
   3. animation_animation.set_loop → 按需设置循环
```

### 陷阱 6：脚本 write 覆盖丢失内容

```
❌ 错误操作：
   script_manage.write → 直接写入新内容
   结果：用户在编辑器中手动修改的代码被全量覆盖丢失。

✅ 正确操作：
   1. script_manage.read  → 先读取当前完整内容
   2. 在读取内容的基础上修改
   3. script_manage.write → 写入修改后的完整内容
```

### 陷阱 7：忘记保存场景

```
❌ 错误操作：
   连续创建了多个节点、设置了属性、挂载了脚本... 然后直接运行或关闭编辑器。
   结果：所有修改丢失，下次打开场景恢复到上次保存的状态。

✅ 正确操作：
   每完成一个功能模块（如创建完 Player 及其子节点）就调用：
   scene_management.save
   
📌 保存时机建议：
   - 创建完一组相关节点后
   - 挂载脚本后
   - 配置完动画后
   - 任何运行测试之前
```

### 陷阱 8：project_settings 修改后未重启生效

```
❌ 错误操作：
   project_input.add_action → 添加了新输入动作 → 直接在运行中的游戏里测试
   结果：新动作在当前运行实例中不存在。

✅ 正确操作：
   修改 project_settings / project_input 后：
   1. scene_run.stop  → 停止当前运行
   2. scene_run.play_main → 重新启动游戏
   输入映射、物理设置等项目级配置需要重启游戏才能加载。
```

### 陷阱 9：场景运行时 MCP 修改不影响运行实例

```
⚠️ 注意：
   MCP 操作的是编辑器中的场景数据，不是正在运行的游戏实例。
   在游戏运行期间通过 MCP 修改节点属性、脚本等，不会实时反映到运行中的游戏。

✅ 正确流程：
   1. scene_run.stop   → 停止游戏
   2. 执行 MCP 修改操作
   3. scene_management.save → 保存
   4. scene_run.play_main → 重新运行查看效果
```

---

## 11. MCP 操作前检查清单

> AI 在每次执行 MCP 操作前，应快速过一遍此清单。

| 操作类型 | 检查项 |
|---------|--------|
| 创建节点 | parent_path 是否使用相对路径？ |
| 创建 CollisionShape | 是否紧接着设置了具体形状？ |
| 创建动画 | 是否添加了轨道和至少 2 个关键帧？ |
| 移动/重命名文件 | 是否更新了所有场景中的引用？ |
| 修改脚本 | 是否先 read 再 write？ |
| 修改项目设置 | 是否需要重启游戏才能生效？ |
| 完成一组操作 | 是否调用了 scene_management.save？ |
| 运行测试前 | 是否已保存所有更改？ |
| **任何修改完成后** | **是否已更新 `commit_doc.md`？（强制）** |

---

## 12. commit_log 强制更新规则（最高优先级）

> **这是强制性步骤，不可跳过。违反此规则等同于"忘记保存场景"。**

### 12.1 什么是 commit_log

`commit_log.md` 是项目根目录下的进度快照文档，包含：
- **第一部分**：项目当前完整状态（目录结构、场景节点树、脚本清单、输入映射、动画配置等）
- **第二部分**：按时间倒序排列的操作变更日志
- **第三部分**：已知问题与待办事项

其核心目的是：**让任何新打开的 AI 对话窗口，仅通过阅读此文件就能完全了解项目当前进度，无需任何额外上下文。**

### 12.2 何时必须更新

以下任何操作完成后，**必须立即**更新 `commit_doc.md`：

| 触发条件 | 更新内容 |
|---------|---------|
| 创建/删除/修改场景 | 更新第一部分的场景节点树 |
| 创建/修改/移动脚本 | 更新第一部分的脚本清单 |
| 添加/修改输入映射 | 更新第一部分的输入映射表 |
| 创建/修改动画 | 更新第一部分的动画配置表 |
| 创建/删除目录或文件 | 更新第一部分的目录结构 |
| 修改项目设置 | 更新第一部分的项目基础信息 |
| 添加 AutoLoad | 更新第一部分的相关章节 |
| **以上任何操作** | **在第二部分顶部追加变更日志条目** |
| 发现新问题 | 更新第三部分已知问题 |
| 完成某个待办 | 更新第三部分待办事项状态 |

### 12.3 变更日志条目格式

```markdown
#### 操作 N：简要描述
- **创建/修改/删除/修复** `文件路径`：具体做了什么
- **问题**（如有）：遇到了什么问题
- **修复**（如有）：如何解决的
```

### 12.4 操作流程中的位置

```
1. 执行功能开发 / bug 修复
2. scene_management.save → 保存场景
3. ✅ 更新 commit_doc.md → 记录变更（本步骤不可跳过）
4. scene_run.play_main → 运行测试（可选）
```

### 12.5 新对话窗口的启动流程

新 AI 对话窗口打开后，应按以下顺序快速进入工作状态：

```
1. 读取 commit_doc.md     → 了解项目当前状态和最近变更
2. 读取 CONVENTIONS.md    → 了解项目编码规范和 MCP 陷阱
3. 读取 GODOT_MCP_GUIDE.md → 了解 MCP 工具能力边界（按需）
4. 开始接受用户指令并执行
```
