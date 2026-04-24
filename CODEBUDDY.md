# AINo.1 — Godot 2D/3D 游戏项目

## 项目概述

使用 Godot 4.6 + GDScript 开发的游戏项目，通过 Godot MCP 插件实现 AI 辅助开发（Vibe Coding）。

## 技术栈

- **引擎**：Godot 4.6.2 (Forward+)
- **语言**：GDScript（禁止 C#）
- **AI 工具链**：CodeBuddy + Godot MCP (localhost:3100)

## 关键文件

- `commit_log.md` — 项目进度快照（**新对话必须先读此文件**）
- `.codebuddy/rules/` — AI 行为规则（自动加载）

## 项目结构

```
scenes/    → 场景文件
scripts/   → GDScript 脚本
assets/    → 贴图/模型/音频/字体
autoload/  → 全局单例
resources/ → .tres 资源
ui/        → UI 资源
```

## AI 工作流

1. 读取 `commit_log.md` 了解当前进度
2. 执行开发任务（遵循 `.codebuddy/rules/` 中的规则）
3. 保存场景 → 更新 `commit_log.md` → 测试运行
