# LLM Boss AI 提示词维护指南

> 本文档是 `scripts/ai/decision/llm_boss_ai.gd` 中两套系统提示词的"设计意图说明书"。
> **任何修改提示词之前请先通读本文档**，避免重蹈已知陷阱。

---

## 1. 架构概览

项目包含两套独立的系统提示词，对应两种对战模式：

| 常量 | 模式 | 输出格式 | 请求频次 |
|------|------|----------|----------|
| `SYSTEM_PROMPT` | 暗出对决（Blind Clash） | `action_sequence` 数组（1-3 张） | 每回合 1 次 |
| `SYSTEM_PROMPT_BP_SLOT` | 明牌 Pick（BP Slot Pick） | 单个 `card_id` | 每回合 4 次（逐 slot） |

两套提示词共享同一套游戏规则（元素克制、光暗协同等），但**信息可见性**和**决策粒度**不同，因此必须分别维护。

### 感知数据来源

| 常量 | 感知构建函数 | 文件 |
|------|-------------|------|
| `SYSTEM_PROMPT` | `PerceptionBuilder.build()` | `scripts/ai/llm/perception_builder.gd` |
| `SYSTEM_PROMPT_BP_SLOT` | `PerceptionBuilder.build_for_slot_pick()` | 同上 |

感知构建器的 `_RULES_SUMMARY` 常量会作为 `rules_summary` 字段注入每次请求，相当于系统提示词的"在线补强"。**修改克制规则时必须三处同步**：
1. `SYSTEM_PROMPT` 中的元素克制节
2. `SYSTEM_PROMPT_BP_SLOT` 中的元素克制节
3. `perception_builder.gd` 中的 `_RULES_SUMMARY`

---

## 2. 提示词结构拆解（按节顺序）

两套提示词的节排列遵循"规则 → 信息 → 角色 → 决策 → 输出"的认知递进，**不要打乱顺序**——LLM 对靠前的内容赋予更高权重。

### 2.1 元素三角克制节

**设计意图**：这是 LLM 最容易出错的机制，因此放在最前面（仅次于角色定义）。

**已知陷阱 & 修复历史**：

| 陷阱 | 症状 | 根因 | 修复 |
|------|------|------|------|
| 克制方向反 | LLM 输出"木克火" | Few-shot Example A reasoning 中写了 "wood克fire×1.5" | 重写 Example A 为正确的 "water克fire×1.5" |
| 两套克制系统混淆 | LLM 同时引用 ATK/DEF/SKL 克制和元素克制 | 提示词中保留了旧 type 三角克制的兼容描述 | 删除旧克制描述，`clash_resolver.gd` 移除 `_legacy_type_counter` fallback |
| 跨 slot 克制 | LLM 把自己 slot2 的牌与玩家 slot1 的牌比元素 | 提示词未显式声明 + `player_picks` 数据结构让跨 slot 信息同样可达 | 三管齐下：①克制节首条加 ⚠⚠⚠ ②`current_slot_matchup` 字段直接给出对位 ③常见错误 anti-pattern + Step 0 决策步骤 |

**当前写法要点**：
- 首条用 ⚠⚠⚠ 加粗"克制仅在【同 slot 对位】之间判定"
- 3 条克制都补全双方倍率（如"火方×1.5，木方×0.5"），不给 LLM 只看单侧的机会
- 末条加口诀"火→木→水→火（箭头方向 = 克制方向）"
- 显式声明"type 不决定克制"

**修改守则**：
- 如果新增/删除元素，**必须**同时更新 3 处（见第 1 节末尾）
- 克制方向如果改变，**必须**检查 Few-shot 示例的 reasoning 是否还正确
- **绝不要**在克制节中同时描述多套克制系统——旧系统已移除，不要再加回来

### 2.2 光暗 2:2 平衡协同节

**设计意图**：这是玩家方专属的"奖励机制"，Boss 不享受但需要反制。LLM 需要知道这个机制的存在才能正确判断"是否要阻止玩家凑 2:2"。

**当前写法要点**：
- 明确"仅放大已成立的克制"——2:2 不产生克制，只放大已有的 ×1.5 → ×2.0
- 明确"被克 0.5 不变"——玩家被克时不会因为 2:2 而变好
- Boss 反制点：让玩家偏色

**修改守则**：
- 如果未来给 Boss 也加 2:2 加成，需要重写此节 + 修改 `clash_resolver.gd` 的判定逻辑
- 如果倍率从 2.0 改为其他值，需要同步 `_RULES_SUMMARY`

### 2.3 感知字段说明节

**设计意图**：告诉 LLM 输入 JSON 中哪些字段与克制判断相关。这是"信息到决策"的桥梁。

**暗出模式** vs **BP 模式**的差异：

| 字段 | 暗出 | BP |
|------|------|-----|
| `self_hand` | ✓（全量手牌） | ✗（改为 `self_candidates`） |
| `self_candidates` | ✗ | ✓（4 张候选，已 Pick 的为 picked=true） |
| `player_candidates` | ✗ | ✓（4 张明牌，BP 独有） |
| `player_picks` | ✗ | ✓（逐 slot 锁定） |
| `current_slot_matchup` | ✗ | ✓（**v0.7.1 新增**，直接告知当前 slot 的对位对手） |
| `leaked_player_cards` | ✓（探针泄露） | ✗（BP 暂无探针） |
| `trap_slot_*` | ✓ | ✗（BP 无陷阱） |
| `probe_hint` | ✓ | ✗ |

**修改守则**：
- 如果 `PerceptionBuilder` 新增/删除字段，**必须**在此节同步更新
- 不要在此节描述不存在的字段——LLM 会尝试在输入中寻找并可能幻觉

### 2.4 模式特有机制节

#### 暗出模式：能量 + 陷阱 + 认知探针

**设计意图**：这三个机制是暗出模式独有的博弈维度。

- **能量机制**：强调"不可累积"——LLM 容易以为能量可以存到下回合
- **陷阱槽**：明确"优先级（高费槽 > 类型槽）"+"槽位一次性"+"occupied ≠ 真陷阱"
- **认知探针**：给出 2/3/5 次命中的阶梯奖励，LLM 需要知道 probe_hint 字段的含义

#### BP 模式：BP 核心机制 6 条

**设计意图**：逐条解释 BP 模式与暗出模式的差异，防止 LLM 把暗出逻辑套用到 BP。

**关键条目及原因**：
1. "候选完全可见"——BP 的核心博弈前提，信息差为零
2. "只能为当前 slot 选 1 张"——防止 LLM 一次输出多个 slot
3. "已锁定的 picks 出现在 self_picks / player_picks"——这是 LLM 做对位预判的数据来源
4. "严格按 slot index 对位翻盅"——**这是克制仅在同 slot 判定的制度保证**，与 2.1 节呼应
5. "能量重置 + avg_energy_budget_per_slot"——LLM 需要理解能量是稀缺资源
6. "0 费牌自动打出"——防止 LLM 尝试 pick 一张 already picked 的 0 费牌

### 2.5 关键决策维度节（仅 BP）

**设计意图**：BP 模式下 LLM 每次只决策 1 个 slot，容易"只看眼前"。此节显式列出 A~F 六个维度，引导 LLM 从"当前 slot 对位"扩展到"全局 4 对结算"。

**已知陷阱**：
- 维度 B 的原始写法"预判后让你的剩余候选能压制"导致 LLM 误以为自己的 slot2 可以克玩家的 slot1——已修复为显式声明"你的 slot2 克玩家的 slot2"

**修改守则**：
- 任何涉及"预判玩家后续 slot"的措辞，**必须**同时声明克制只发生在同 slot 对位之间

### 2.6 数值期望评估节

**设计意图**：LLM 的天然倾向是"看到克制就选"，需要显式纠正为"基础数值 × 倍率 = 期望"。

**核心反例**：×1.5 的 3 伤害(=4.5) < 同色 ×1.0 的 6 伤害(=6)。

**修改守则**：
- 如果新增数值维度（如反弹、穿透），需要在此节补充期望计算
- 不要删除反例——这是 LLM 最容易犯的错

### 2.6.1 治疗效率规则节（v0.7.1 新增）

**设计意图**：LLM 的另一个天然倾向是"治疗 = 生存 = 好"，但治疗与护甲有本质差异——护甲可保留，治疗不可。满血时出大治疗牌是纯粹的浪费。

**已知陷阱**：
| 陷阱 | 症状 | 根因 | 修复 |
|------|------|------|------|
| 满血出大治疗 | Boss 满血时出 heal=8 的牌 | 提示词未区分治疗与护甲的保留性差异 | 新增【治疗效率规则】节，显式声明"治疗不可溢出/保留，满血=0收益" |

**关键公式**：`治疗实际收益 = min(heal_amount × 克制倍率, max_hp - hp)`

**修改守则**：
- 如果游戏机制改为治疗可溢出/保留，需要**完全重写**此节
- 如果新增"吸血"类效果（同时造成伤害和治疗），治疗的溢出规则仍适用

### 2.7 长远牌局预测节

**设计意图**：防止 LLM 只做单回合最优化。

**暗出模式** vs **BP 模式**的差异：
- 暗出：多回合视角（斩杀线、对方手牌结构推断、陷阱真假、资源滚雪球）
- BP：单回合 4 对结算视角（4 张总伤害预估、玩家 pick 链推断、自身候选搭配、能量曲线）

### 2.8 决策流节

**设计意图**：强制 LLM 先走博弈检测（Step 1），再走数值优先级（Step 2）。这是"角色感"的核心——纯数值玩家不是"回响"。

**⚠ 先走 Step 1 再走 Step 2**：这个 ⚠ 是刻意放的，因为 LLM 经常跳过 Step 1 直接数值。

**BP 模式的 Step 0（v0.7.1 新增）**：
- 在 Step 1 之前新增 Step 0 "锁定当前 slot 对位"——读 `current_slot_matchup` 字段
- 这一步只看当前 slot，绝对不看其他 slot 的 `player_picks`
- **为什么需要 Step 0**：LLM 有强倾向使用所有可用信息。`player_picks` 数组把所有 slot 的元素平铺在一起，LLM 在决定 slot2 时容易"顺手"用 slot1 的元素做克制判断。Step 0 强制 LLM 先锁定对位，减少跨 slot 误判。

### 2.8.1 常见错误 Anti-pattern 节（v0.7.1 新增）

**设计意图**：文字警告（"克制仅在同 slot 对位之间"）对 LLM 的约束力有限，LLM 仍然会"不经意"地使用跨 slot 信息。显式列出 ❌ 错误示例 + ✅ 正确做法，比纯正面规则更有效。

**当前列出的错误**：
1. ❌ 决定 slot2 时考虑 slot1 的克制 → ✅ 只看 current_slot_matchup
2. ❌ 满血出大治疗 → ✅ 治疗收益=min(heal, max_hp-hp)，满血=0
3. ❌ 为 ×1.5 克制选低基础牌 → ✅ 基础×1.0 可能 > 低基础×1.5

**修改守则**：
- 发现新的 LLM 误判模式时，优先加到此节——anti-pattern 比"加强正面规则"更有效
- 每个 anti-pattern 必须同时给 ❌ 和 ✅

### 2.9 角色 & 对手建模节

**设计意图**：赋予 LLM "回响"的人格，使其推理有博弈深度。一阶/二阶/三阶推理框架是提示词工程中的"思维链脚手架"。

**修改守则**：
- "30% 概率放弃数值最优"这个数字不是硬编码到代码的，它只是提示词中的"软指令"——LLM 不一定精确遵守，但能影响分布
- 如果发现 LLM 太激进（总反预判导致数值崩盘），可以调低这个概率或加"当 self.hp ≤ 阈值时回到数值优先"

### 2.10 思考方式 & 输出格式 & 约束节

**设计意图**：
- **reasoning ≤ 80 字**：token 上限约束。LLM 的 reasoning 越长，越容易在后续输出中"自我矛盾"或被截断
- **先 reasoning 再选牌**：强制 chain-of-thought
- **reasoning 必须包含对玩家行为的判断**：防止 LLM 只写数值计算

**暗出** vs **BP 的输出差异**：
- 暗出：`action_sequence` 数组（1-3 张牌）
- BP：单个 `card_id`

**修改守则**：
- 80 字限制是经验值，如果 LLM 上下文窗口增大可以适当放宽，但不要太长——长 reasoning 导致截断后 JSON 不完整
- 如果修改输出格式，**必须**同步修改 `llm_boss_ai.gd` 中的 JSON 解析逻辑（`_parse_response` / `_parse_bp_response`）

### 2.11 Few-shot 示例节

**设计意图**：LLM 对 Few-shot 的学习权重极高——**甚至高于规则描述**。示例中的任何事实性错误都会被 LLM 直接学到。

**已知陷阱**：
- Example A 曾经写了 "wood克fire×1.5"（克制方向反），LLM 直接学到了反的克制关系——这是最严重的 bug 类型

**修改守则**：
- **修改任何机制后，必须回头检查 Few-shot 的 reasoning 是否还与机制一致**
- 示例 reasoning 中提到 slot 对位时，**必须**用"我slotN克玩家slotN的X"这种显式格式，不要省略为"克X"（容易让 LLM 误解为跨 slot 克制）
- 示例的输入数据（self_hand / self_candidates / player_candidates）中的 element 字段**必须**与当前 `card_database.gd` 中的定义一致

---

## 3. 提示词修改清单（Checklist）

修改提示词时，按以下清单逐项检查：

- [ ] **克制规则 3 处同步**：`SYSTEM_PROMPT` + `SYSTEM_PROMPT_BP_SLOT` + `_RULES_SUMMARY`
- [ ] **治疗效率规则同步**：如果修改了治疗溢出/保留机制，必须同步两套提示词的【治疗效率规则】节 + `_RULES_SUMMARY`
- [ ] **Few-shot 示例一致性**：reasoning 中的克制方向、倍率、slot 对位是否与规则一致
- [ ] **跨 slot 克制**：任何新增的"预判玩家后续 slot"措辞是否同时声明"克制仅在同 slot 对位之间"
- [ ] **`current_slot_matchup` 字段同步**：如果修改了 `build_for_slot_pick` 的参数/结构，检查 `current_slot_matchup` 字段是否仍正确构建
- [ ] **感知字段同步**：`perception_builder.gd` 中新增/删除的字段是否在提示词的"感知字段说明节"中同步
- [ ] **信息对称契约**：如果修改了 `_build_player_view`，检查 `perception_builder.gd` 文件头的镜像表
- [ ] **输出格式同步**：如果修改了 JSON 输出格式，同步 `_parse_response` / `_parse_bp_response`
- [ ] **两套提示词差异**：暗出 vs BP 的机制差异是否在各自提示词中正确反映（陷阱/探针/BP 6 条）
- [ ] **token 预算**：新增内容后，reasoning 的 80 字限制是否仍然合理；系统提示词 + 感知 JSON 是否超出上下文窗口
- [ ] **常见错误 anti-pattern**：发现新的 LLM 误判模式时，优先加到【常见错误】节

---

## 4. 已知问题 & 待优化

| 问题 | 状态 | 备注 |
|------|------|------|
| 克制方向反转 | ✅ 已修复 | Few-shot Example A 重写 + 旧 type 克制移除 |
| 跨 slot 克制误解 | ✅ 已修复(v2) | v1: ⚠⚠⚠ 首条；v2: `current_slot_matchup` 字段 + anti-pattern + Step 0 |
| 旧 ATK/DEF/SKL 三角克制残留 | ✅ 已修复 | `_legacy_type_counter` 移除，`Element.NONE` 牌视为中立 |
| 满血出大治疗 | ✅ 已修复 | 新增【治疗效率规则】节 + anti-pattern + `_RULES_SUMMARY` 同步 |
| LLM 有时仍忽略"先博弈后数值" | 🔍 观察中 | Step 1 的 ⚠ 已加，但 LLM 仍可能跳过 |
| reasoning 超过 80 字被截断 | 🔍 观察中 | 与模型能力和上下文长度相关 |
| BP Few-shot 示例 B 的 self_picks 格式简略 | 📝 待优化 | `self_picks: [slot1=fire, slot2=picked:true]` 不如完整 JSON 清晰 |

---

## 5. 相关文件索引

| 文件 | 作用 |
|------|------|
| `scripts/ai/decision/llm_boss_ai.gd` | 两套系统提示词 + LLM 调用 + JSON 解析 |
| `scripts/ai/llm/perception_builder.gd` | 感知 JSON 构建 + `_RULES_SUMMARY` + 信息对称校验 |
| `scripts/ai/config/llm_config.gd` | LLM 提供商配置（模型名、温度、max_tokens 等） |
| `scripts/battle/clash_resolver.gd` | 克制判定实现（`ElementHelper` 调用方） |
| `scripts/utils/element_helper.gd` | 元素克制倍率计算（单向权威来源） |
| `autoload/card_database.gd` | 牌库定义（元素、极性、数值——提示词中引用的 ID/element 必须与此一致） |
| `scripts/data/card_data.gd` | CardData 类定义（Element/Polarity 枚举） |
| `docs/design/architecture/adr-001-llm-boss-ai.md` | LLM Boss AI 的架构决策记录 |
