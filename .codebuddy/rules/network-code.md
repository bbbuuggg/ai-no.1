---
paths:
  - "scripts/network/**"
  - "res://scripts/network/**"
---

# 网络代码规则（GDScript / Godot 4.6）

**项目默认策略**：本项目默认**单机游戏**。除非游戏策划在 GDD 中明确写入"联机需求"且技术总监批准 ADR，否则不写网络代码。

如果未来引入联机：

- 所有来自网络的数据**必须**验证——来源、范围、时序
- **禁止**信任客户端输入——服务器权威
- 每个 RPC 必须文档化：触发条件、数据 schema、权威方、错误处理
- 延迟补偿策略必须在 ADR 记录（客户端预测 / 服务器回滚 / 插值）
- 所有网络状态变化有 replay 能力（调试用）
- 用 Godot `MultiplayerAPI` + `MultiplayerSpawner` + `MultiplayerSynchronizer`
- 见 `docs/engine-reference/modules/networking.md`

## 反模式

- 客户端直接修改权威数据
- 未验证网络输入进入游戏逻辑
- 每帧广播所有状态（用 Delta 压缩）
