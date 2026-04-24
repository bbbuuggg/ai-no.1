# Godot MCP 能力边界与使用指南

> 本文档详细说明 Godot MCP（Model Context Protocol）工具的功能范围、能力边界和限制条件。  
> 供 AI 辅助开发（Vibe Coding）过程中参考，确保高效利用工具能力、规避已知限制。

---

## 1. 概述

Godot MCP 是一个连接 AI 助手与 Godot 编辑器的桥梁插件，通过 HTTP 协议在本地 `127.0.0.1:3100` 提供 MCP 接口，使 AI 能够直接读写和操控 Godot 编辑器中的场景、节点、脚本、动画、物理等各个方面。

### 通信架构

```
AI 助手 (CodeBuddy)
	↕  MCP 协议 (JSON over HTTP)
Godot MCP Server (localhost:3100)
	↕  EditorPlugin API
Godot Editor (4.6)
```

---

## 2. 功能模块总览

| 模块 | 工具名 | 能力级别 | 说明 |
|------|--------|---------|------|
| 场景管理 | `scene_management` | ⭐⭐⭐⭐⭐ | 创建/打开/保存/关闭场景 |
| 场景层级 | `scene_hierarchy` | ⭐⭐⭐⭐⭐ | 获取节点树、选中节点 |
| 场景运行 | `scene_run` | ⭐⭐⭐⭐⭐ | 运行/停止场景测试 |
| 节点生命周期 | `node_lifecycle` | ⭐⭐⭐⭐⭐ | 创建/删除/复制/实例化节点 |
| 节点属性 | `node_property` | ⭐⭐⭐⭐⭐ | 读写任意节点属性 |
| 节点变换 | `node_transform` | ⭐⭐⭐⭐⭐ | 位置/旋转/缩放操作 |
| 节点层级 | `node_hierarchy` | ⭐⭐⭐⭐ | 重新挂载父子关系、排序 |
| 节点查询 | `node_query` | ⭐⭐⭐⭐⭐ | 按名称/类型查找节点 |
| 节点可见性 | `node_visibility` | ⭐⭐⭐⭐ | 显示/隐藏、Z序、颜色调制 |
| 节点物理 | `node_physics` | ⭐⭐⭐ | 碰撞层/掩码、施加力/冲量 |
| 节点信号 | `node_signal` | ⭐⭐⭐⭐ | 连接/断开/发射信号 |
| 节点分组 | `node_group` | ⭐⭐⭐⭐ | 分组管理、批量调用 |
| 节点处理 | `node_process` | ⭐⭐⭐ | 启用/禁用 process 回调 |
| 节点元数据 | `node_metadata` | ⭐⭐⭐ | 自定义键值对存储 |
| 节点方法 | `node_call` | ⭐⭐⭐ | 调用节点方法 |
| 脚本管理 | `script_manage` | ⭐⭐⭐⭐⭐ | 创建/读取/写入 GDScript |
| 脚本附加 | `script_attach` | ⭐⭐⭐⭐⭐ | 挂载/卸载脚本 |
| 脚本编辑 | `script_edit` | ⭐⭐⭐⭐ | 添加函数/变量/信号/导出 |
| 脚本编辑器 | `script_open` | ⭐⭐⭐ | 在编辑器中打开脚本 |
| 动画播放器 | `animation_player` | ⭐⭐⭐⭐ | 播放/停止/暂停动画 |
| 动画资源 | `animation_animation` | ⭐⭐⭐⭐ | 创建/删除/循环设置 |
| 动画轨道 | `animation_track` | ⭐⭐⭐⭐ | 添加轨道和关键帧 |
| 动画树 | `animation_animation_tree` | ⭐⭐⭐ | AnimationTree 配置 |
| 状态机 | `animation_state_machine` | ⭐⭐⭐ | 状态/转换管理 |
| 混合空间 | `animation_blend_space` | ⭐⭐ | BlendSpace 配置 |
| 混合树 | `animation_blend_tree` | ⭐⭐ | BlendTree 图节点 |
| Tween | `animation_tween` | ⭐⭐⭐ | 程序化补间动画 |
| 物理体 | `physics_physics_body` | ⭐⭐⭐⭐ | 创建/配置物理体 |
| 碰撞形状 | `physics_collision_shape` | ⭐⭐⭐⭐ | 创建各种碰撞形状 |
| 物理关节 | `physics_physics_joint` | ⭐⭐ | 创建/配置关节 |
| 物理查询 | `physics_physics_query` | ⭐⭐⭐ | 射线检测、形状检测 |
| 材质 | `material_material` | ⭐⭐⭐ | 创建/修改材质属性 |
| 网格 | `material_mesh` | ⭐⭐⭐ | 查询网格、创建基础体 |
| 着色器 | `shader_shader` | ⭐⭐ | 创建/读写 Shader 文件 |
| 着色器材质 | `shader_shader_material` | ⭐⭐ | ShaderMaterial 参数 |
| 灯光 | `lighting_light` | ⭐⭐⭐ | 创建/配置 2D/3D 灯光 |
| 环境 | `lighting_environment` | ⭐⭐⭐ | 环境光、雾、辉光等 |
| 天空 | `lighting_sky` | ⭐⭐ | 天空盒配置 |
| 粒子发射器 | `particle_particles` | ⭐⭐⭐ | GPU/CPU 粒子系统 |
| 粒子材质 | `particle_particle_material` | ⭐⭐ | 粒子行为参数 |
| TileSet | `tilemap_tileset` | ⭐⭐ | TileSet 信息查询 |
| TileMap | `tilemap_tilemap` | ⭐⭐ | 设置/清除 TileMap 单元格 |
| CSG | `geometry_csg` | ⭐⭐⭐ | 构造实体几何 |
| GridMap | `geometry_gridmap` | ⭐⭐ | 3D 网格地图 |
| MultiMesh | `geometry_multimesh` | ⭐⭐ | 批量实例化渲染 |
| 导航 | `navigation_navigation` | ⭐⭐⭐ | 导航网格、寻路代理 |
| 音频总线 | `audio_bus` | ⭐⭐⭐ | 音频总线和效果器 |
| 音频播放 | `audio_player` | ⭐⭐⭐ | 音频播放控制 |
| UI 主题 | `ui_theme` | ⭐⭐⭐ | 主题创建和样式设置 |
| UI 布局 | `ui_control` | ⭐⭐⭐ | 锚点、边距、布局 |
| 项目信息 | `project_info` | ⭐⭐⭐⭐ | 项目配置查询 |
| 项目设置 | `project_settings` | ⭐⭐⭐⭐ | 修改项目设置 |
| 输入映射 | `project_input` | ⭐⭐⭐⭐⭐ | 输入动作和绑定管理 |
| AutoLoad | `project_autoload` | ⭐⭐⭐⭐ | 全局单例管理 |
| 文件系统 | `filesystem_*` | ⭐⭐⭐⭐ | 目录/文件/JSON 读写搜索 |
| 资源管理 | `resource_*` | ⭐⭐⭐⭐ | 资源创建/复制/移动/删除 |
| 编辑器状态 | `editor_*` | ⭐⭐⭐ | 编辑器界面控制 |
| 调试工具 | `debug_*` | ⭐⭐⭐ | 日志/性能/类信息查询 |

---

## 3. 核心能力详解

### 3.1 场景与节点操作 — 最强能力区

MCP 在场景和节点操作方面能力最为完善，几乎覆盖了编辑器的全部手动操作：

**可以做到：**
- 创建任意类型的节点并构建完整的父子层级
- 设置节点的任意属性（位置、缩放、颜色、资源引用等）
- 复制、删除、重命名、重新挂载节点
- 按名称模式或类型搜索场景中的节点
- 保存场景到文件，设置主场景，运行测试

**关键注意事项：**
```
⚠️ 创建节点时 parent_path 必须使用相对路径（如 "." 或 "Player"）
	不要使用 "/root/Main" 这样的绝对路径，否则节点不会保存到 .tscn 文件中。

⚠️ 创建节点后必须手动调用 scene_management.save 保存场景，
	否则关闭编辑器后所有更改丢失。

⚠️ 每次重大修改后建议调用 scene_hierarchy.get_tree 确认节点结构正确。
```

### 3.2 脚本管理 — 强能力区

**可以做到：**
- 创建新的 GDScript 文件并指定继承类
- 完整读写脚本内容（覆盖写入）
- 将脚本附加到节点或从节点卸载
- 增量编辑：添加函数、变量、信号、导出属性
- 在编辑器中打开脚本到指定行

**限制：**
```
⚠️ script_manage.write 是全量覆盖，不支持局部编辑。
	修改脚本前务必先 read 获取完整内容，修改后 write 回去。

⚠️ 脚本修改后需要重新运行场景才能生效。
	编辑器中的运行实例不会热更新脚本。

⚠️ 不支持 C# 脚本的创建和管理，仅支持 GDScript (.gd)。
```

### 3.3 动画系统 — 中强能力区

**可以做到：**
- 创建动画并设置时长、循环
- 添加属性轨道和方法轨道
- 在轨道上插入关键帧（支持 Vector2、Vector3、Color、float 等值类型）
- 播放/停止/暂停动画
- 配置 AnimationTree、状态机、混合空间

**限制：**
```
⚠️ 无法导入外部动画文件（如从 Blender 导出的 .anim）。

⚠️ 不支持骨骼动画（Skeleton2D/3D）的关键帧编辑。

⚠️ 动画曲线的插值类型（线性/贝塞尔/阶梯）配置支持有限。

⚠️ 精灵帧动画（SpriteFrames/AnimatedSprite2D）不在此工具覆盖范围内，
	需要通过 node_property 手动设置或通过脚本代码创建。
```

### 3.4 物理系统 — 中等能力区

**可以做到：**
- 创建 2D/3D 物理体（Rigid、Character、Static、Area）
- 创建碰撞形状（Box、Sphere、Capsule、Cylinder、Polygon）
- 设置碰撞层和碰撞掩码
- 施加力、冲量、设置速度
- 执行射线检测和形状检测

**限制：**
```
⚠️ 不支持直接编辑 ConcavePolygonShape 的顶点数据。

⚠️ 物理关节（Joint）的参数配置较为基础，复杂约束需要脚本实现。

⚠️ 不支持物理材质（PhysicsMaterial）的直接创建，
	需通过 node_property 设置弹性（bounce）和摩擦力（friction）。

⚠️ 射线/形状检测只能在运行时有效，编辑器中无法执行。
```

### 3.5 资源与文件系统 — 中等能力区

**可以做到：**
- 创建/删除目录
- 读写文本文件和 JSON 文件
- 复制/移动/删除资源文件
- 搜索文件名和文件内容
- 触发文件系统扫描

**限制：**
```
⚠️ 不支持导入外部资源（如将 .png 从电脑其他位置复制到项目中）。
	只能操作已在 res:// 下的文件。

⚠️ 不支持二进制文件的读写（图片、音频的原始数据）。

⚠️ .import 文件由引擎自动管理，不应手动修改。
```

---

## 4. 明确不支持的功能（能力边界）

以下功能超出 Godot MCP 当前的能力范围：

### 4.1 视觉编辑类

| 不支持的功能 | 替代方案 |
|-------------|---------|
| 可视化 Shader 图编辑 (VisualShader) | 用 `shader_shader` 编写文本 Shader 代码 |
| 精细的 UV 映射编辑 | 在 Blender 等外部工具中完成 |
| 2D 路径编辑 (Path2D 控制点) | 通过脚本代码动态构建 Curve2D |
| Terrain3D / 地形编辑 | 在编辑器中手动操作或使用插件 |
| Skeleton2D/3D 骨骼绑定 | 在 Blender 中完成骨骼设置后导入 |

### 4.2 资源导入类

| 不支持的功能 | 替代方案 |
|-------------|---------|
| 导入外部图片/模型/音频到项目 | 手动拖拽文件到 Godot 文件系统面板 |
| 配置资源导入参数（如贴图过滤模式） | 在编辑器 Import 面板中手动设置 |
| 创建 SpriteFrames 资源 | 通过脚本代码 + `node_property` 设置 |
| 字体资源的导入和配置 | 手动放置字体文件后通过属性引用 |

### 4.3 编辑器专属功能

| 不支持的功能 | 替代方案 |
|-------------|---------|
| 编辑器插件 (EditorPlugin) 的开发 | 手动编写插件代码 |
| GDExtension / C++ 模块 | 需要独立的 C++ 开发环境 |
| 导出游戏为可执行文件 | 在编辑器中通过 Export 菜单操作 |
| 版本控制（Git）操作 | 使用 CodeBuddy 的终端执行 git 命令 |

### 4.4 运行时限制

| 不支持的功能 | 说明 |
|-------------|------|
| 运行时调试（断点、步进） | MCP 操作的是编辑器，非运行中的游戏实例 |
| 获取运行时游戏画面/截图 | 无法捕获游戏窗口的渲染输出 |
| 运行时修改游戏状态 | 只能修改编辑器中的场景，不是运行中的实例 |
| 读取游戏运行时日志 | 需要在 Godot 编辑器的 Output 面板中查看 |

---

## 5. 已知陷阱与最佳实践

### 5.1 节点路径陷阱

```
❌ 错误：使用绝对路径创建节点
   parent_path: "/root/Main"
   → 节点挂在运行时的 SceneTree 上，不会保存到 .tscn

✅ 正确：使用相对路径
   parent_path: "."          → 场景根节点
   parent_path: "Player"     → 根节点下的 Player 子节点
```

### 5.2 输入映射陷阱

```
❌ 错误：使用内置 ui_* 动作做游戏操控
   Input.get_axis("ui_left", "ui_right")
   → A/D 键可能被 UI 焦点系统拦截，表现不一致

✅ 正确：使用自定义动作
   Input.get_axis("move_left", "move_right")
   → 完全自主控制，无冲突
```

### 5.3 场景保存时机

```
❌ 错误：创建了大量节点后忘记保存
   → 下次打开编辑器全部丢失

✅ 正确：每完成一个功能模块就调用 scene_management.save
   → 增量保存，降低丢失风险
```

### 5.4 脚本修改流程

```
❌ 错误：直接 write 覆盖脚本
   → 可能丢失手动在编辑器中做的修改

✅ 正确：先 read → 修改内容 → write 回去
   → 保证不丢失任何已有代码
```

### 5.5 碰撞形状创建陷阱

```
❌ 错误：创建 CollisionShape2D 节点后不设置形状
   → 运行时报错 "CollisionShape2D: shape is null"

✅ 正确：创建节点后立即调用 create_box / create_sphere 等设置形状
```

---

## 6. 推荐工作流

### 6.1 创建新场景的标准流程

```
1. scene_management.create        → 创建场景，指定根节点类型
2. node_lifecycle.create          → 逐个创建子节点（使用相对路径）
3. physics_collision_shape.*      → 为物理节点配置碰撞形状
4. node_property.set              → 设置关键属性（贴图、颜色等）
5. node_transform.set_position    → 设置节点位置
6. script_manage.create + write   → 编写脚本
7. script_attach.attach           → 挂载脚本到节点
8. animation_animation.create     → 创建动画
9. animation_track.*              → 添加轨道和关键帧
10. scene_management.save         → 保存场景！
11. scene_run.play_main           → 运行测试
```

### 6.2 修改现有场景的标准流程

```
1. scene_management.open          → 打开目标场景
2. scene_hierarchy.get_tree       → 确认当前节点结构
3. script_manage.read             → 读取现有脚本
4. 执行修改操作...
5. scene_management.save          → 保存
6. scene_run.play_current         → 测试
```

### 6.3 调试问题的标准流程

```
1. scene_hierarchy.get_tree       → 检查节点层级是否正确
2. node_property.get              → 检查关键属性值
3. node_query.find_by_type        → 确认特定类型节点存在
4. script_manage.read             → 检查脚本逻辑
5. project_input.get_action       → 检查输入绑定
6. physics_collision_shape.get_info → 检查碰撞形状配置
```

---

## 7. 工具能力速查表

### 适合用 MCP 做的事

| 场景 | 示例 |
|------|------|
| 搭建节点树 | 创建 Player → Sprite2D → CollisionShape2D 层级 |
| 批量设置属性 | 设置所有敌人的 speed 属性为 150 |
| 编写完整脚本 | 从零编写 player.gd 的全部逻辑 |
| 动画配置 | 创建 idle/walk/jump 动画并添加关键帧 |
| 项目配置 | 设置输入映射、主场景、窗口大小 |
| 快速原型 | 5 分钟搭建一个可运行的移动+跳跃 demo |
| 文件管理 | 重构目录结构，移动/重命名资源 |

### 应交给编辑器手动操作的事

| 场景 | 原因 |
|------|------|
| 精细的粒子效果调参 | 需要实时视觉反馈，MCP 无法预览 |
| TileMap 大面积绘制 | 编辑器画笔工具远比逐格设置高效 |
| 导入外部美术资源 | MCP 无法访问项目外的文件系统 |
| Shader 可视化编辑 | VisualShader 是拖拽式 UI，无法通过 MCP 操作 |
| 导出游戏包 | 需要在编辑器中配置导出模板和签名 |

### 应交给脚本代码实现的事

| 场景 | 原因 |
|------|------|
| 程序化生成地形/关卡 | 运行时生成，MCP 只操作编辑器 |
| 复杂的 AI 行为树 | 逻辑复杂度超出 MCP 的单次操作范围 |
| 网络多人同步 | 需要完整的网络架构代码 |
| 存档/读档系统 | 涉及文件 I/O 和序列化逻辑 |
| 动态资源加载 | `ResourceLoader` 相关逻辑需要在脚本中实现 |

---

## 8. 版本信息

| 项 | 值 |
|----|-----|
| 文档版本 | 1.0 |
| 适用 Godot 版本 | 4.6.x |
| MCP 服务地址 | `http://127.0.0.1:3100/mcp` |
| 插件路径 | `res://addons/godot_mcp/` |
| 最后更新 | 2026-04-24 |
