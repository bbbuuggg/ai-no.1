---
paths:
  - "docs/design/gdd/**"
---

# 设计文档规则

- 每个设计文档**必须**包含 8 个必需章节：Overview / Player Fantasy / Detailed Rules / Formulas / Edge Cases / Dependencies / Tuning Knobs / Acceptance Criteria
- Formulas 必须含变量定义、预期值范围、示例计算
- Edge Cases 必须明确说"会发生什么"，而不是"优雅处理"
- Dependencies 必须双向——如果系统 A 依赖 B，B 的文档也要提 A
- Tuning Knobs 必须指定安全范围和它们影响什么玩法
- Acceptance Criteria 必须可测——QA 能判断 pass/fail
- **禁止**模糊："系统应该感觉好"不是有效规格
- 平衡值必须链接到源公式或理由
- 设计文档**必须**增量写入：先建骨架，再每章一写，每章用户批准后立即写入文件持久化

## Godot 4.6 特定扩展

每个设计文档还应包含以下章节（非强制但推荐）：

### 9. 场景与节点设计
- 建议的节点结构（ASCII 树）
- 需要的 Resource 资源清单（.tres 文件）
- 相关 Autoload 或 EventBus 信号

### 10. 实现任务清单
- [ ] 任务：具体描述（优先级：高/中/低，预估：0.5d/1d/2d/...）
- 每个任务附：输入/输出、节点结构建议、关联系统、验收标准

## 示例章节（用于 8 节中的 Detailed Rules）

**正确**（具体、可实现）：

```markdown
## Detailed Rules

### 攻击流程
1. 玩家按下 attack 键
2. 触发 attack_01 动画（0.35s）
3. 在 0.15s 时启用 Hitbox（Area2D），检测 body_entered
4. 在 0.25s 时禁用 Hitbox
5. 动画结束后回到 idle 状态，or 缓冲下一次 attack（连招）
```

**错误**（模糊）：

```markdown
## Detailed Rules

玩家按键后角色攻击，感觉流畅有力。
```
