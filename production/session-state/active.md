# Active Session — 2026-05-15 20:36 UTC+8

## Current Focus
**🧠 LLM 克制感知修复（火水木+光暗 实装契约）+ 🔄 先手机制改版（v0.8.0-locked.1）+ 📐 GDD-08 等用户对 NEW-Q1/Q2 拍板**

刚刚（20:36）修复了一个潜伏近 2 周的"语义鸿沟" bug —— LLM 一直用 ATK/DEF/SKL 旧三角思考克制，实际游戏早已转向火/水/木 + 光暗。Perception 字段层 + 两个 SYSTEM_PROMPT 全部同步到 v0.6.0 实装契约。可立即烟测。

---

## 🧠 2026-05-15 20:36 LLM 克制感知修复（v0.6.0 实装契约对齐）

### 用户指令
> "我注意到 llm 思考中的克制关系还是 atk 对 def，现在应当是火水木三者的克制，然后会对防御/攻击的数值产生影响，请修复"

### 根因（双轨问题）

| 问题 | 文件 | 现象 |
|---|---|---|
| ① 字段层缺失 | `perception_builder.gd` | 卡牌输出 dict 只有 `type`，**没有 `element` / `polarity`** —— LLM 物理上看不到火水木属性 |
| ② Prompt 层过时 | `llm_boss_ai.gd` | 两个 SYSTEM_PROMPT 的"三角克制规则"小节仍写着 `ATTACK ▶ SKILL` 旧规则，没提火水木+光暗 |

### 修复变更

| 文件 | 关键变更 |
|---|---|
| `scripts/ai/llm/perception_builder.gd` | 新增 `ELEMENT_SHORT` / `POLARITY_SHORT` 映射 + 顶层常量 `_RULES_SUMMARY`；4 个 build 方法（hand/leaked/candidates/picks）每张卡 dict 增加 `element` + `polarity`；`_build_self` 新增 `deck_element_counts` / `deck_polarity_counts`；主返回 + BP slot 返回都加 `rules_summary` 字段 |
| `scripts/ai/decision/llm_boss_ai.gd` | 两个 SYSTEM_PROMPT（普通 + BP_SLOT）"三角克制"段全部重写为火水木 3-cycle + 光暗 2:2 协同；新增「感知字段读取指南」+「Boss 反制 2:2 策略」段；Few-shot 示例换成 wood 防御克 water 攻击的新语义 |

### 设计意义

这个 bug 解释了之前用户感知到的"LLM 决策有时显得很奇怪"—— 它不是不会博弈，而是**听不懂战场语言**。修复后 LLM 的 reasoning 应该会从"atk 克 def"自动跃迁到"fire 克 wood"等真实战斗语义，且能利用 leaked_player_cards 的元素信息做精准对位克制。

### 验证方法（建议烟测路径）

1. 跑游戏开 BP 战斗
2. 看战斗日志里 Boss 的 reasoning 一栏：应该出现 `fire/water/wood/light/dark` 而非 `atk/def/skl`
3. 看 `user://llm_log.txt` 的 USER prompt 摘要：应该看到 `element=fire(light)` 这种新字段
4. 看 4 张 picks 翻盅后的克制结算是否合理（玩家凑 2:2 时是否吃 ×2.0）

---

## 🔄 2026-05-15 20:24 先手机制改版（v0.8.0-locked.1）

### 落地变更

| 文件 | 变更 |
|---|---|
| `scripts/battle/blind_clash_battle.gd` | `_start_bp_first_picker` 重写：R1 走 `randi()%2`，R≥2 与上回合相反 |
| `scripts/battle/blind_clash_scene.gd` | 战斗日志：R1=`首回合先手（随机）`，R≥2=`轮流先手` |
| `scripts/ui/first_picker_banner.gd` | `play()` 加 `sub_text` 可选参数；R1 副标题"首回合：随机决定先手"，R≥2"轮流先手 · 第 N 回合换手" |
| `docs/design/gdd/07-blind-pick-b-prime.md` | §0 TL;DR / §2 状态机图 / §6.3 演出 / §术语表 4 处全改 |

### 设计意义
从"每回合公平随机"升级为"宏观公平 + 微观可计算"——玩家可预测下回合先手归谁，呼应 GDD-04「可计算的博弈」原则。

---

## 📐 GDD-08 MIRROR 进度系统（仍待用户拍板）

### 锁定决策一览

| ID | 决策 | 说明 |
|---|---|---|
| Q1 | 互换整套牌库 + 5s 预览 | 双方 13 张完全交换 |
| Q2 | 顺序流程：先 1 给自己 → 再从剩 3 张挑 1 给 Boss | UI 步骤 1/2 |
| Q3 | 单 Run 5 轮封顶 | 完美 Run = 25-35 分钟 |
| Q4 | 单次死即结算（无续命）| rogue-lite 标准 |
| Q5 | 12 张升级牌池起步 | 验证后扩到 24 |
| Q6 | Boss 名直接叫 MIRROR | 不做演化阶梯 |
| **🔒 RULE-Z** | **零膨胀替换** | 每次升级必须替换牌库中现有的 1 张牌，牌库永远 13 张 |

---

## 待用户拍板的两个微决策（NEW-Q）

### NEW-Q1：结构升级是否消耗牌库替换次数？
- **A. 不消耗**（vibe-lead 推荐）
- **B. 消耗**

### NEW-Q2：奖励界面阶段是否完全开放 Boss 牌库查看？
- **A. 完全开放**（vibe-lead 推荐）
- **B. 隐藏部分细节**

**等用户回 "都 A" 或具体偏好** → 派 lead-programmer 拆 Epic-08 任务清单。

---

## What's Done This Session
- [x] vibe-lead 接收用户构想 → 委派 game-designer + creative-director
- [x] creative-director 产出"对镜博弈"情感锚点 + 5-7 轮红线
- [x] vibe-lead 给出 6 问决策大纲
- [x] 用户拍板 6 问 + 新增 RULE-Z 零膨胀原则
- [x] vibe-lead 接管写完 GDD-08（~600 行）
- [x] commit_log.md + active.md 同步刷新（GDD-08 落盘条）
- [x] 20:24 先手机制改版：随机 → 轮流（首回合随机）+ 战斗日志 + GDD-07 同步
- [x] **20:36 LLM 克制感知修复：perception 字段补 element/polarity + 两个 SYSTEM_PROMPT 改写为火水木+光暗**

## Next Suggested Steps（按推荐排序）

### 🥇 第一档（推荐）：用户答 NEW-Q1/Q2 → 派 lead-programmer 拆 Epic-08（~30min 出清单）

### 🥈 第二档：先烟测 LLM 克制感知修复
- 跑 BP 战斗 → 看 Boss reasoning 是否出现 fire/water/wood 字眼 → 看克制结算是否合理
- 烟测时同时验证 v0.8.0-locked.1 先手机制（R2 横幅副标题 + 战斗日志"轮流先手"）

### 🥉 第三档：用户对 GDD-08 整体提反对意见 → 迭代 v0.8.0-locked.2

---

## 🔄 2026-05-15 20:24 先手机制改版（v0.8.0-locked.1）

### 用户指令
> "是轮流先手不是只有我先手，第一回合谁先手随机，记得同步修改里的战斗日志，将随机先手改为轮流先手"

### 落地变更

| 文件 | 变更 |
|---|---|
| `scripts/battle/blind_clash_battle.gd` | `_start_bp_first_picker` 重写：R1 走 `randi()%2`，R≥2 与上回合相反 |
| `scripts/battle/blind_clash_scene.gd` | 战斗日志：R1=`首回合先手（随机）`，R≥2=`轮流先手` |
| `scripts/ui/first_picker_banner.gd` | `play()` 加 `sub_text` 可选参数；R1 副标题"首回合：随机决定先手"，R≥2"轮流先手 · 第 N 回合换手" |
| `docs/design/gdd/07-blind-pick-b-prime.md` | §0 TL;DR / §2 状态机图 / §6.3 演出 / §术语表 4 处全改 |

### 设计意义
从"每回合公平随机"升级为"宏观公平 + 微观可计算"——玩家可预测下回合先手归谁，进一步规划候选保留策略，呼应 GDD-04「可计算的博弈」原则。

### 跨 Run 行为
`first_picker` 在 `reset_battle()` 仍清空 → 每场新战斗（含 MIRROR Run 跨轮互换后）都重新走"首回合随机"，与 GDD-08 互换语义自洽。

---

## 📐 GDD-08 MIRROR 进度系统（仍待用户拍板）

### 锁定决策一览

| ID | 决策 | 说明 |
|---|---|---|
| Q1 | 互换整套牌库 + 5s 预览 | 双方 13 张完全交换 |
| Q2 | 顺序流程：先 1 给自己 → 再从剩 3 张挑 1 给 Boss | UI 步骤 1/2 |
| Q3 | 单 Run 5 轮封顶 | 完美 Run = 25-35 分钟 |
| Q4 | 单次死即结算（无续命）| rogue-lite 标准 |
| Q5 | 12 张升级牌池起步 | 验证后扩到 24 |
| Q6 | Boss 名直接叫 MIRROR | 不做演化阶梯 |
| **🔒 RULE-Z** | **零膨胀替换** | 每次升级必须替换牌库中现有的 1 张牌，牌库永远 13 张 |

### RULE-Z 的设计立柱地位

地位等同于 GDD-04 的"13 张/HP25/6 候选/4 槽 Pick"——任何破坏此规则的提案需重开决策。设计意图：**维持博弈感的核心是牌库小且可计算**。

### 升级牌池（12 张起步，4 类×3 张）

| 类别 | 牌名 | 一句话 |
|---|---|---|
| 数值 | OVERFLOW / SHARD / CAFFEINE | +2 dmg / +2 armor / 跨回合能量 |
| 属性 | NULL_REF / HYDRO_INJECT / PYRO_INJECT | 光暗反转 / 改 WATER / 改 FIRE |
| 关键字 | PARASITE / NULL_PIERCE / KICKBACK | 50% 吸血 / 无视护甲 / 反伤 3 |
| 结构 | KERNEL_BOOST / EXTRA_LOOP / RECURSION | 起始能量+1 / 候选 6→7 / 0 费上限 2→3 |

### 关键公式

- **Boss HP 缩放**：`boss_max_hp(round_index) = 25 + (round_index - 1) × 3`（25→28→31→34→37）
- **升级牌价值上限**：替换基础牌 ×1.4~1.6
- **牌库总数恒等式**：`deck.size() + hand.size() + discard_pile.size() == 13`（任何时刻，双方均成立）

### Epic-08 拆分预览（待用户审）

| Epic | 描述 | 工时 |
|---|---|---|
| 08-A | RunState autoload + UpgradeData Resource | 1.5h |
| 08-B | 12 张升级牌池注册 | 2h |
| 08-C | RewardScreen 场景（4 候选 + 步骤 banner）| 3h |
| 08-D | ReplaceModal（13 张 Grid 选被替换牌）| 1.5h |
| 08-E | SwapPreviewPanel（双栏 + 5s 倒计时 + 互换动画）| 2h |
| 08-F | LLM perception 扩展（round_index/streak/upgrade_history）| 1.5h |
| 08-G | Boss HP 缩放 + struct_modifiers 战斗接入 | 1.5h |
| 08-H | FAILURE_END / PERFECT_RUN_END 结算页 | 1.5h |
| 08-I | 烟测 + 平衡迭代 | 2h |

**总 ~16h ≈ 4-5 个 30min vibe loop ≈ 1.5-2 天迭代窗口**

---

## 待用户拍板的两个微决策（NEW-Q）

### NEW-Q1：结构升级是否消耗牌库替换次数？

- **A. 不消耗**（vibe-lead 推荐）：玩家拿结构升级 = 白拿，但同 Run 仅 1 张防滚雪球
- **B. 消耗**：完全对称的零膨胀，但结构升级感知变弱

### NEW-Q2：奖励界面阶段是否完全开放 Boss 牌库查看？

- **A. 完全开放**（vibe-lead 推荐）：玩家必须能看 Boss 13 张才能选替换目标
- **B. 隐藏部分细节**：增加博弈难度

**等用户回 "都 A" 或具体偏好** → vibe-lead 派 lead-programmer 拆 Epic-08 详细任务清单 → 用户审清单 → 实施。

---

## 📦 历史归档（仅供回查）

### 2026-05-15 16:38 v0.7.x-rebal 阶段 1-4（HP 25 / 能量 6 / 6 候选 / 3 张 0 费 / 第 6 回合枯竭 / QueryButtons z 修复）— 已烟测通过
### 2026-05-15 15:13 Epic-BP-5 LLM 接 Boss Pick PASS（v0.7.0-alpha 闭环）
### 2026-05-15 14:25~14:40 Epic-BP-7 翻盅回归 v0.3 PASS
### 2026-05-15 23:30~hotfix.6 Epic-BP-6 pick_select_ui 全程明牌
### Q-BP-1~5 决策表（GDD-07 锁定）
| ID | 决策 |
|---|---|
| Q-BP-1 | 候选完全可见 |
| Q-BP-2 | 先手不补偿 |
| Q-BP-3 | 4 张回合内固定 + 回合末全弃 |
| Q-BP-4 | v0.7.0-alpha 暂时移除 0 费（v0.7.x 修饰格回归 → v0.7.x-hotfix 改为只保留 c_inspiration_surge）|
| Q-BP-5 | 陷阱 v0.8.0 回归 |

---

## 历史归档（更早，2026-05-14 之前）
- Sprint 1+2 完工（数据层 8+8 + HP 80 + B 浮层 + DEPLOYED 缩略条 + 信息对称契约）
- 元素+光暗题材转向 Sprint A.1 数据层完工（GDD-06 + ADR-002）
- v0.6.0 视觉层 P0 + v0.6.1 视觉收尾
- 详见 commit_log.md 时间轴
