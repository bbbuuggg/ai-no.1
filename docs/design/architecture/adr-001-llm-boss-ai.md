# ADR-001: 接入 LLM 作为 Boss AI

**状态**：✅ 已实施（v0.4 MVP）
**日期**：2026-05-12
**决策者**：vibe-lead + technical-director + game-designer + lead-programmer
**文档位置**：`docs/design/architecture/adr-001-llm-boss-ai.md`

---

## 上下文

NULL Protocol 是赛博朋克卡牌 Roguelike，核心叙事是「玩家用约束令限制并欺骗 AI 程序」。规则 AI 已经实现（`scripts/ai/blind_clash_ai.gd`），但难以体现"AI 程序在思考"的世界观真实感，且诱饵机制完全依赖 AI 是否会被信息欺骗。

GDD v0.2（`docs/design/gdd/02-symmetric-duel-revision.md`）早已为 LLM 接入预留了完整接口：
- AIPerception JSON Schema
- AIAction JSON Schema
- AIDecisionInterface 抽象基类
- 幻觉注入管线设计

本 ADR 记录 v0.4 落地决策。

---

## 决策

### 1. 接入范围：仅 BLIND 选牌
**为什么**：BLIND 是唯一真正的博弈决策点，规则 AI 在此最受限。每回合只调用 1 次 LLM 是延迟控制的根本前提。

| 阶段 | AI 接入 | 理由 |
|---|---|---|
| DEPLOY | ❌ 无（玩家专属） | Boss 不部署陷阱 |
| **BLIND** | ✅ **LLM** | 核心决策，价值最大 |
| CLASH | ❌ | 自动结算，无决策 |
| PROBE | ❌ 保留规则版 | 规则统计已够好，LLM 无增益 |
| ROUND_END | ❌ | 无决策 |

### 2. 调用模式：异步预取（B 方案）
- DEPLOY 阶段开始时调用 `boss_ai.warm_up()`，提前发起 LLM 请求
- 玩家 DEPLOY 通常 5-15s，足够覆盖 LLM 1-3s 响应
- BLIND 阶段调用 `await boss_ai.select_blind_cards_async()` 取用缓存

### 3. Provider：OpenAI 兼容协议（首选 DeepSeek）
**为什么**：DeepSeek 国内可达 + 最便宜（≈¥0.01/场）+ 协议兼容覆盖 90% 厂商。同一套 `OpenAICompatProvider` 类切换 base_url 即可支持智谱/通义/Moonshot/OpenAI 等。

### 4. API Key 配置：内置开发模板 + 用户配置 + 环境变量
**优先级链**（高→低）：
1. 环境变量 `NULL_LLM_API_KEY`（CI/临时）
2. `user://llm_config.cfg`（玩家自带 Key）
3. `res://config/llm_config.dev.cfg`（开发期内置，已 gitignore）
4. 全部失败 → `active = "mock"` 自动走 MockProvider

### 5. 错误恢复矩阵
| 错误 | 处理 |
|---|---|
| 网络超时 | 立即 fallback 规则 AI |
| JSON 非法 | retry 1 次 → 仍失败 → fallback |
| 牌 ID 不存在 | 静默丢弃此动作（修正） |
| 超能量预算 | 从尾部裁剪（修正） |
| 连续 3 次失败 | 整场战斗剩余回合切规则 AI |

**核心原则**：玩家永远不应感知到 AI 出错。

### 6. Boss 思考演出（决定体验上限）
- BLIND 阶段玩家确认选牌 → 强制 1.5s `BossThinkingOverlay` 演出
- 即使 LLM 返回更快，也演满最短时长（一致性）
- 即使用规则 AI 也走演出（用户无感知模式切换）
- 视觉：扫描线 + "回响 · 正在分析" + 字符流（赛博朋克压迫感）

---

## 实现文件清单

```
scripts/ai/
├── decision/
│   ├── ai_decision_interface.gd      # 抽象基类
│   ├── rule_blind_clash_ai.gd        # 规则 AI 异步外壳
│   └── llm_boss_ai.gd                # LLM 主实现 + fallback
├── llm/
│   ├── llm_provider_base.gd          # Provider 抽象基类
│   ├── perception_builder.gd         # GameState → JSON
│   ├── action_validator.gd           # JSON → Array[CardData] + 修正
│   └── providers/
│       ├── openai_compat_provider.gd # 兼容 DeepSeek/OpenAI/智谱/通义
│       └── mock_provider.gd          # 离线测试
└── config/
    └── llm_config.gd                 # 配置加载器

scripts/ui/
└── boss_thinking_overlay.gd          # 1.5s 演出层

scripts/battle/blind_clash_battle.gd  # 接入 boss_ai + 历史记录
scripts/battle/blind_clash_scene.gd   # 注入 LLMBossAI + 演出接线

config/llm_config.dev.cfg.template    # 开发配置模板（提交）
config/llm_config.dev.cfg             # 开发配置（不提交，gitignored）
```

---

## 后果

### ✅ 正面
- Boss 行为质感巨幅提升（基于 LLM 推理的真实角色感）
- 诱饵机制天然生效（LLM 真的会被槽位占位影响）
- 幻觉注入管线兼容（修改 perception 副本即可）
- 多模型支持架构（一行配置切换 Provider）

### ⚠️ 风险与缓解
- **API 成本**：每场战斗约 ¥0.01-0.04
  - 缓解：免费版本自动走 mock，用户自带 Key 即可付费版
- **延迟可见**：极端情况 LLM > 3s
  - 缓解：硬超时切规则 AI + 演出动画掩盖
- **网络依赖**：用户离线无法用 LLM
  - 缓解：mock provider + force_rule_ai 调试开关
- **API Key 泄露**：开发期 dev.cfg 误提交
  - 缓解：.gitignore 已添加 + 模板文件不含 Key

---

## v0.5 后续优化（不在本 ADR 范围）
- 多 Provider UI 切换面板
- Token 用量统计
- Prompt 压缩（history 摘要）
- 重试 1 次策略
- GUT 单元测试覆盖 ActionValidator

## v0.6+ 远期
- 流式 SSE 实时显示推理过程
- Boss 跨场记忆
- Anthropic Claude Provider
- 本地 LLM（Ollama/llama.cpp）

---

## 相关文档
- GDD：`docs/design/gdd/02-symmetric-duel-revision.md`（v0.2 LLM 接口预定义）
- 规则集：`.codebuddy/rules/ai-code.md`
- commit_log：v0.4 标记
