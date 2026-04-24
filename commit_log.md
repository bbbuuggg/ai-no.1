# AINo.1 项目进度文档 (commit_doc)

> **⚠️ 强制规则：AI 每次完成代码修改后必须同步更新本文档。详见 CONVENTIONS.md 第 12 节。**  
> 本文档供新对话窗口快速了解项目当前状态，无需上下文即可立即进入工作。  
> 最后更新：2026-04-24 14:23

---

## 第一部分：项目当前状态

### 1.1 项目基础信息

| 属性 | 值 |
|------|-----|
| 项目名称 | AINo.1 |
| Godot 版本 | 4.6.2-stable |
| 渲染器 | Forward+ |
| 脚本语言 | GDScript |
| 主场景 | `res://scenes/main.tscn` |
| 窗口大小 | 1152 × 648 |
| MCP 服务 | `http://127.0.0.1:3100/mcp` |
| MCP 插件 | `res://addons/godot_mcp/plugin.cfg`（已启用） |

### 1.2 目录结构

```
res://
├── addons/                  # 编辑器插件
│   └── godot_mcp/           # MCP 通信插件（已启用）
├── assets/                  # 静态资源
│   ├── sprites/             # 2D 贴图（空）
│   ├── models/              # 3D 模型（空）
│   ├── audio/               # 音效音乐（空）
│   └── fonts/               # 字体（空）
├── autoload/                # 全局单例（空）
├── resources/               # .tres 资源（空）
├── scenes/                  # 场景文件
│   └── main.tscn            # 主场景
├── scripts/                 # 脚本文件
│   └── player.gd            # 玩家控制脚本
├── ui/                      # UI 资源（空）
├── CONVENTIONS.md            # 项目约定文档（含 AI 操作规范和陷阱清单）
├── GODOT_MCP_GUIDE.md        # MCP 能力边界说明文档
├── icon.svg                 # 项目图标（同时用作玩家占位贴图）
└── project.godot            # 项目配置文件
```

### 1.3 场景节点树

**`res://scenes/main.tscn`** — 主场景：

```
Main (Node2D)
├── Player (CharacterBody2D)          # 位置: (400, 300)，脚本: res://scripts/player.gd
│   ├── Sprite2D                      # 贴图: icon.svg，缩放: (0.5, 0.5)
│   ├── CollisionShape2D              # 形状: RectangleShape2D (64×64)
│   └── AnimationPlayer               # 动画: idle, walk, jump
└── Ground (StaticBody2D)             # 位置: (400, 500)
	└── CollisionShape2D              # 形状: RectangleShape2D (800×50)
```

### 1.4 脚本清单

| 脚本路径 | 继承类 | 挂载节点 | 功能 |
|---------|--------|---------|------|
| `res://scripts/player.gd` | CharacterBody2D | Player | 左右移动、跳跃、动画切换 |

**`player.gd` 核心参数：**
- `SPEED = 300.0` — 移动速度
- `JUMP_VELOCITY = -400.0` — 跳跃力度
- 重力读取自 `physics/2d/default_gravity`
- 使用自定义输入动作：`move_left`, `move_right`, `jump`

### 1.5 动画配置

| 动画名 | 所属节点 | 时长 | 循环 | 轨道 | 效果 |
|--------|---------|------|------|------|------|
| `idle` | Player/AnimationPlayer | 1.0s | ✅ | Sprite2D:scale | 呼吸缩放脉冲 (0.5↔0.52/0.48) |
| `walk` | Player/AnimationPlayer | 0.5s | ✅ | Sprite2D:rotation | 左右摇摆 (0↔±0.2 rad) |
| `jump` | Player/AnimationPlayer | 0.5s | ❌ | Sprite2D:scale | 拉长变形 (0.4,0.6→0.5,0.5) |

### 1.6 输入映射（自定义动作）

| 动作名 | 主键 | 备选键 | 用途 | 状态 |
|--------|------|--------|------|------|
| `move_left` | A | Left Arrow | 向左移动 | ✅ 已配置 |
| `move_right` | D | Right Arrow | 向右移动 | ✅ 已配置 |
| `move_up` | W | Up Arrow | 向上移动 | ✅ 已配置 |
| `move_down` | S | Down Arrow | 向下移动 | ✅ 已配置 |
| `jump` | Space | — | 跳跃 | ✅ 已配置 |
| `attack` | Mouse Left | J | 攻击 | ✅ 已配置（暂未使用） |
| `interact` | E | F | 交互 | ✅ 已配置（暂未使用） |
| `dash` | Shift | — | 冲刺 | ✅ 已配置（暂未使用） |
| `pause` | Escape | — | 暂停 | ✅ 已配置（暂未使用） |
| `inventory` | Tab | I | 背包 | ✅ 已配置（暂未使用） |

### 1.7 已有文档

| 文档 | 路径 | 内容摘要 |
|------|------|---------|
| 项目约定 | `CONVENTIONS.md` | 目录规范、命名规范、输入映射、碰撞层、脚本结构、MCP 陷阱清单（9 条）、操作前检查清单 |
| MCP 指南 | `GODOT_MCP_GUIDE.md` | 40+ 工具的能力评级、功能/限制说明、标准工作流、能做/不能做速查表 |
| 进度文档 | `commit_log.md`（本文件） | 项目状态快照 + 操作变更日志 |

---

## 第二部分：操作变更日志

> 按时间倒序排列，最新的在最上面。

### [2026-04-24] Session 1 — 项目规范化与文档体系建立

#### 操作 5：创建 commit_doc 并更新 CONVENTIONS.md 强制规则
- **创建** `commit_doc.md`（本文件）
- **修改** `CONVENTIONS.md`：新增第 12 节"commit_doc 强制更新规则"

#### 操作 4：MCP 陷阱写入规范
- **修改** `CONVENTIONS.md`：新增第 10 节"MCP 操作陷阱清单"（9 条实战陷阱）和第 11 节"MCP 操作前检查清单"

#### 操作 3：修复脚本引用断裂
- **问题**：迁移 `player.gd` 到 `scripts/` 后，场景中 Player 节点仍引用旧路径 `res://player.gd`
- **修复**：detach 旧脚本 → attach `res://scripts/player.gd` → save 场景
- **教训**：记录为陷阱 2（移动资源后引用断裂）

#### 操作 2：项目目录结构优化 + 输入映射 + 文档
- **创建目录**：`scenes/`, `scripts/`, `assets/sprites/`, `assets/models/`, `assets/audio/`, `assets/fonts/`, `ui/`, `autoload/`, `resources/`
- **迁移文件**：`player.gd` → `scripts/player.gd`，`main.tscn` → `scenes/main.tscn`
- **更新配置**：`application/run/main_scene` → `res://scenes/main.tscn`
- **添加输入映射**：`move_up`(W/Up), `move_down`(S/Down), `attack`(鼠标左/J), `interact`(E/F), `dash`(Shift), `pause`(Esc), `inventory`(Tab/I)
- **创建文档**：`CONVENTIONS.md`（项目约定），`GODOT_MCP_GUIDE.md`（MCP 能力指南）

---

### [2026-04-23] Session 0 — 项目初始化与基础 Demo

#### 操作 3：修复 A/D 键无效
- **问题**：脚本使用 `ui_left`/`ui_right` 导致 A/D 键被 UI 焦点系统拦截
- **修复**：创建自定义动作 `move_left`(A/Left), `move_right`(D/Right), `jump`(Space)
- **修改** `player.gd`：将 `ui_left`/`ui_right`/`ui_accept` 替换为 `move_left`/`move_right`/`jump`

#### 操作 2：修复空白场景
- **问题**：创建节点时使用 `/root` 绝对路径，导致节点不属于 .tscn 文件
- **修复**：使用相对路径 `.` 和 `Player` 重新创建全部节点
- **补充**：为三个动画添加了属性轨道和关键帧（之前只创建了空动画）

#### 操作 1：创建基础 2.5D Demo
- **创建场景** `main.tscn`（Node2D 根节点）
- **创建 Player**：CharacterBody2D + Sprite2D(icon.svg) + CollisionShape2D(64×64) + AnimationPlayer
- **创建 Ground**：StaticBody2D + CollisionShape2D(800×50)
- **编写** `player.gd`：左右移动 + 重力 + 跳跃 + 动画状态切换
- **创建动画**：idle(呼吸)、walk(摇摆)、jump(拉伸)
- **设置**：主场景、窗口配置

---

## 第三部分：已知问题与待办

### 已知问题
- 根目录残留旧文件 `main.tscn`（已迁移到 `scenes/`，残留文件可删除）
- 根目录残留 `player.gd.uid`（引擎自动生成的 UID 文件）

### 待办事项（尚无具体排期）
- [ ] 为角色添加真正的精灵贴图替换占位的 icon.svg
- [ ] 实现 attack、interact、dash 等已映射但未使用的动作
- [ ] 创建敌人角色和基础 AI
- [ ] 添加 UI（血条、暂停菜单）
- [ ] 配置碰撞层（当前全部使用默认层 1）
- [ ] 创建 AutoLoad 全局管理器（按需）
