# Epic-BP-B' — BP 方案 B' 实施 Epic 拆分 / Implementation Epic Breakdown

> **状态**：🚧 **Epic-BP-1/2/3 已落地（v0.7.0-alpha-skel）→ 等用户烟测 → 决定是否继续 Epic-BP-4~9**
> **版本**：v1.1（2026-05-15 21:30 增补 Epic-BP-1/2/3 实装备注 + 灰色地带 #2 决策）
> **日期**：2026-05-14（创建）/ 2026-05-15（增补）
> **作者**：lead-programmer 思路 + vibe-lead 落盘代笔（subagent 输出未真正写文件）
> **依据**：`docs/design/gdd/07-blind-pick-b-prime.md`（v0.7-locked，Q-BP-1~5 全部 yes）
> **目标版本**：v0.7.0-alpha
>
> **🔒 已锁定决策（追加）**：
> - **灰色地带 #2 LLM 失败降级 = 单次失败立切兜底规则 AI（不累计失败计数）**（用户拍板 2026-05-15）→ 由 LLMBossAI 内部处理；BlindClashBattle 不感知降级
> - **Q-BP-4 0 费机制移除 = 数据层已天然满足**（card_database 现有牌库无 0 费，无需改代码）
>
> **🚧 已落地 Epic（v0.7.0-alpha-skel）**：
> - **Epic-BP-1** ✅ 信号契约 + BPPhase 状态机骨架（10 个 BP 信号 + BP_MODE_ENABLED 开关 + 6 阶段 stub）
> - **Epic-BP-2** ✅ 候选抽取 + 完全可见同步（双方 4 张候选 + bp_candidates_drawn 广播 + 日志展示双方候选）
> - **Epic-BP-3** ✅ 随机先手 + first_picker_banner UI（randi()%2 + 1.5s 横幅淡入停留淡出 + 玩家=青蓝/Boss=血红）
> - **当前形态**：BP 路径骨架贯通，可在 console 看到 6 阶段流转 + 候选名称 + 先手横幅；Pick 阶段为 stub（自动 fill 前 4 张候选），结算正常，回合循环正常
> - **下一批**：Epic-BP-4~9（核心 Pick 循环 + LLM 接口 + UI 重写 + 烟测）

---

## §1 总览 / Overview

**v0.7.0-alpha 目标**：把 v0.6.1 的"暗出+碰撞"双盲心理战循环替换为"明牌 Pick 4 张 + 同时翻盅"的顺序博弈+明牌博弈循环，保留 GDD-04 §2 全部数学结算 + GDD-06 §2/§3 元素+光暗系统不动。

**总工期估算**（lead-programmer 复核 GDD-07 估算后的修正值）：

| 阶段 | 工时区间 |
|---|---|
| Epic 拆分 + 用户审（已完成） | 1-2h |
| Epic-BP-1 ~ Epic-BP-9 实施 | **13-18.5h** |
| 烟测 + 收尾 | 1.5-2h |
| **合计** | **15.5-22.5h** |

> 比 GDD-07 估算（12-18h 实施）略高，buffer 主要加在 Epic-BP-5（LLM 接口重设计）+ Epic-BP-6（UI 重写）两块复杂度较高的 Epic。

**Epic 依赖图**：

```
Epic-BP-1 (信号契约+状态机骨架) ────┬──> Epic-BP-2 (候选抽取+完全可见)
                                    ├──> Epic-BP-3 (随机先手+横幅 UI)
                                    │
Epic-BP-2 ─┐                        │
Epic-BP-3 ─┤                        │
           ├──> Epic-BP-4 (交替 Pick 调度，核心循环)
           │         │
           │         └──> Epic-BP-5 (LLM Boss 接口重设计：4 次轻量+Slot1预热)
           │         │
           │         └──> Epic-BP-6 (pick_select_ui 重写)
           │
Epic-BP-4 完成 ─────> Epic-BP-7 (clash_resolver 调度循环改写+同时翻盅演出)
                          │
                          └──> Epic-BP-8 (回合末清理+0费临时移除+陷阱配置位锁)
                                    │
                                    └──> Epic-BP-9 (烟测脚本+验收清单)
```

---

## §2 Epic 列表 / Epic Catalog

### Epic-BP-1：信号契约 + 战斗状态机骨架

- **目标**：搭出 BP 6 阶段状态机骨架（enum + 信号 + 空 stub），让后续 Epic 在清晰的相位边界上推进。
- **范围（in-scope）**：
  - 在 `blind_clash_battle.gd` 新增 `BPPhase` enum：`{ IDLE, BP_DRAW_CANDIDATES, BP_FIRST_PICKER, BP_PICKING, BP_REVEAL, BP_RESOLVING, BP_ROUND_END, BATTLE_OVER }`（与旧 `Phase` enum **并存**直到 Epic-BP-8 才能清理旧 enum）
  - 新增 7 个 BP 信号（详见 §3 信号契约总表）
  - 新增 `_start_bp_*` 系列空函数 stub（每个相位一个进入函数 + console 日志）
  - 在 `_next_round` 末尾增加分支：`if BP_MODE_ENABLED: _start_bp_draw_candidates() else: 走旧路径`
  - 新增项目级 const `BP_MODE_ENABLED: bool = true`（v0.7.0-alpha 锁 true，v0.6.1 兼容路径只为防止开发期回归）
- **不在范围（out-of-scope）**：任何业务逻辑（抽候选/Pick/翻盅/结算都是空 stub）；UI 层修改；LLM 接口修改
- **改动文件**：
  - `scripts/battle/blind_clash_battle.gd` [改]：新增 enum/signals/stubs
- **新增/修改信号**：详见 §3
- **关键技术决策**：
  1. **不删旧 `Phase` enum + 旧信号**：BP 实施期间双轨并存，避免破坏 v0.6.1 烟测能力
  2. **BPPhase stub 用 print 日志**："[BP] enter phase BP_DRAW_CANDIDATES (round=N)" → 让 Epic-BP-1 完成后能直接跑场景看到 6 个相位按序 print
  3. **BP_MODE_ENABLED 改成 const 而非 export**：避免编辑器测试时误改成 false 又忘关回来
- **验收标准（AC）**：
  1. blind_clash_battle.gd lint 0 错
  2. 启动 blind_clash_scene.tscn → console 按序打印 `[BP] enter BP_DRAW_CANDIDATES → BP_FIRST_PICKER → BP_PICKING → BP_REVEAL → BP_RESOLVING → BP_ROUND_END` 6 行（每行手动 advance 触发）
  3. 旧 v0.6.1 流程在 BP_MODE_ENABLED=false 下仍可完整跑通（双轨保护）
- **预估工时**：1.5-2h
- **依赖**：无
- **风险/未知**：双轨并存可能导致 `_pending_clash_results`/`player_blind_cards` 等字段在两个流程下的语义漂移 → 缓解：BP 流程一律使用新字段名 `_bp_*` 前缀

---

### Epic-BP-2：候选手抽取 + 完全可见同步

- **目标**：实装 Phase 0（双方各抽 4 张候选 + Q-BP-1 完全可见数据通道）。
- **范围**：
  - 新增 `_bp_player_candidates: Array[CardData]` 和 `_bp_boss_candidates: Array[CardData]` 字段
  - 新增 `_start_bp_draw_candidates()` 实装：从双方手牌**临时**抽 4 张作为候选（**不**移出手牌，回合末统一弃）
  - 处理边界：手牌 < 4 张时从牌库补抽到 4 张
  - 触发 `bp_candidates_drawn(player_cards, boss_cards)` 信号
  - **关键 Q-BP-1 兑现**：信号广播双方的完整牌列表（含费用/数值/元素/光暗），UI 后续可全部展示
- **不在范围**：UI 渲染 Boss 候选区（留给 Epic-BP-6）；候选 Pick 后的扣手牌逻辑（Epic-BP-4）
- **改动文件**：
  - `scripts/battle/blind_clash_battle.gd` [改]：候选抽取逻辑
- **新增/修改信号**：
  - `signal bp_candidates_drawn(player_candidates: Array[CardData], boss_candidates: Array[CardData])`
- **关键技术决策**：
  1. **候选 ≠ 手牌副本**：候选是"本回合参与 Pick 的窗口"，手牌仍是来源池。Pick 时再正式从手牌移除 + 扣能量
  2. **手牌 <4 时补抽**：直接调 `combatant.draw_cards(4 - hand.size())` 扩充手牌再选 4 张
  3. **空牌库降级**：若双方牌库 + 弃堆都不足以凑 4 张，能凑几张算几张（边界场景，烟测覆盖）
- **验收标准**：
  1. 跑场景 → bp_candidates_drawn 信号每回合触发一次，参数含 4 张玩家牌 + 4 张 Boss 牌
  2. 玩家手牌数量在 Phase 0 后**不变**（候选只是引用）
  3. console 日志：`[BP] candidates: player=[atk-fire-light, def-water-dark, ...] boss=[...]`
- **预估工时**：1-1.5h
- **依赖**：Epic-BP-1
- **风险**：旧"暗出"流程中 `player_blind_cards` 是已扣手牌的副本，BP 必须改成"候选 = 引用，Pick 才扣"

---

### Epic-BP-3：随机先手 + first_picker_banner UI

- **目标**：实装 Phase 1（randi()%2 决定先手 + 1.5s 横幅演出）。
- **范围**：
  - 新增 `_bp_first_picker: int`（0=player, 1=boss）+ `_bp_current_picker: int`（动态轮换）
  - 实装 `_start_bp_first_picker()`：randi()%2 + emit `bp_first_picker_decided(int)`
  - 新建 `scripts/ui/first_picker_banner.gd`：1.5s 横幅动画（淡入 0.3s → 停留 0.9s → 淡出 0.3s），结束后 emit `banner_finished` 信号
  - 在 `blind_clash_scene.tscn` 顶部加 `first_picker_banner` 节点（CanvasLayer 层，居中）
  - 场景控制器 `blind_clash_scene.gd` 监听 `bp_first_picker_decided` → 显示 banner → 监听 `banner_finished` → 调 `battle._advance_to_picking()`
- **不在范围**：未来"双方申请抢先手→骰子比大小"机制（GDD-07 §3 已说明 v0.8.0 演化）；先手补偿（Q-BP-2 = 不补偿）
- **改动文件**：
  - `scripts/battle/blind_clash_battle.gd` [改]：first_picker 逻辑
  - `scripts/ui/first_picker_banner.gd` [新建]：横幅演出
  - `scenes/battle/blind_clash_scene.tscn` [改]：加 banner 节点
  - `scripts/battle/blind_clash_scene.gd` [改]：监听信号 + advance
- **新增/修改信号**：
  - `signal bp_first_picker_decided(picker_id: int)`（picker_id: 0=player, 1=boss）
  - `signal first_picker_banner.banner_finished()`
- **关键技术决策**：
  1. **横幅文案**："先手：你 ⚔️" / "先手：Boss 🤖"（含 emoji 强化辨识度）
  2. **banner 不阻塞输入**：玩家在 1.5s 内不能 Pick（用 `_bp_current_picker = -1` 做 picker 守卫）
  3. **预留 `first_picker` 字段**：未来抢先手机制只需扩展为"申请阶段→冲突仲裁→写入 first_picker"
- **验收标准**：
  1. 每回合 Phase 1 console 打印 `[BP] first_picker = player` 或 `boss`，比例约 50/50
  2. 横幅在 1.5s 内完成淡入+停留+淡出
  3. 横幅结束后才进入 Pick 阶段
- **预估工时**：1.5-2h
- **依赖**：Epic-BP-1
- **风险**：banner 与现有 `boss_thinking_overlay`/`clash_display_ui` 节点的 z-index 冲突 → 缓解：banner 用独立 CanvasLayer 层级 100

---

### Epic-BP-4：交替 Pick 调度（核心循环）

- **目标**：实装 Phase 2（8 次交替 Pick：先手玩家先 Pick Slot 1 → 后手 Pick Slot 1 → 先手 Pick Slot 2 → ... 直到 4 槽填满）。
- **范围**：
  - 新增 `_bp_player_picks: Array[CardData]`（4 元素，初始全 null）和 `_bp_boss_picks: Array[CardData]`
  - 新增 `_bp_current_slot: int`（0~3）+ `_bp_pick_order_index: int`（0~7）
  - 实装 `_start_bp_picking()`：进入 Phase 2，等待玩家或 Boss 触发 `make_pick`
  - 玩家接口：`make_player_pick(card_index_in_candidates: int)` → 校验当前轮到玩家 + 校验能量 + 从手牌扣牌 → 写入对应 slot → 切换 picker → 检查是否进 Phase 3
  - Boss 接口：`request_boss_pick()` → 调 boss_ai.pick_for_slot_async（Epic-BP-5 实装）→ 拿到结果后写入 slot
  - emit `bp_pick_made(picker: int, slot: int, card: CardData, remaining_energy: int)` 每次 Pick 后
  - emit `bp_all_picks_locked(player_picks, boss_picks, first_picker)` 当 8 次 Pick 全部完成时
- **不在范围**：UI 层（Epic-BP-6 才接入 pick_select_ui）；LLM 实现（Epic-BP-5）
- **改动文件**：
  - `scripts/battle/blind_clash_battle.gd` [改]：Pick 调度核心
- **新增/修改信号**：
  - `signal bp_pick_made(picker_id: int, slot: int, card: CardData, remaining_energy: int)`
  - `signal bp_all_picks_locked(player_picks: Array[CardData], boss_picks: Array[CardData], first_picker: int)`
- **关键技术决策**：
  1. **能量约束在 Pick 时即时校验**：玩家 Pick 不起的牌 UI 应灰显（Epic-BP-6 落地灰显，Epic-BP-4 只校验返回 false）
  2. **picker 切换公式**：`_bp_current_picker = (_bp_first_picker + _bp_pick_order_index) % 2`
  3. **Q-BP-3 兑现**：候选 4 张在 4 个 slot 内固定，不补抽；玩家可以 Pick 同一张牌到不同 slot（**注意**：但每张牌只能 Pick 一次，候选用完即没）→ 候选数组 Pick 后置 null 但保留位置以保持索引稳定
  4. **0 费临时移除**（Q-BP-4）：能量校验改为 `card.energy_cost > 0` 才扣能量；牌库过滤 cost==0 留给 Epic-BP-8
- **验收标准**：
  1. 跑场景 → Phase 2 内能正确 emit 8 次 `bp_pick_made`，picker 交替正确
  2. 玩家无法 Pick 超过当前能量的牌（make_player_pick 返回 false + 日志）
  3. 8 次 Pick 完成后正确 emit `bp_all_picks_locked` 一次，参数含 2 个 4 元素数组
  4. console 日志：`[BP] pick #3: boss → slot 1 (atk-fire, energy left=2)`
- **预估工时**：2-2.5h
- **依赖**：Epic-BP-2, Epic-BP-3
- **风险/未知**：Pick 顺序 vs Slot 索引的映射要清晰（推荐 Pick 顺序 0/2/4/6=先手填 Slot 0/1/2/3，1/3/5/7=后手填同 Slot）；用户可能希望"后手在每个 Slot 跟先手紧贴 Pick"（GDD-07 §3 已锁这种模式）

---

### Epic-BP-5：LLM Boss 接口重设计（4 次轻量调用 + Slot 1 预热）

- **目标**：把 `BlindClashAI.select_blind_cards`（一次性出 4 张+排序）替换为 `pick_for_slot_async(boss, player, board_state, slot_index)`（每个 slot 一次 LLM 调用），并实装 Slot 1 预热并发。
- **范围**：
  - 在 `AIDecisionInterface` 新增 `pick_for_slot_async(boss, player, board_state, slot) -> Dictionary`（返回 `{card: CardData, intent: String}`），废弃旧 `select_blind_cards_async`
  - `BlindClashAI`（规则 AI）实装新接口：单 slot 评分 → 选最优牌（基本是把现有 `_score_card` 拆成单牌打分）
  - `LLMBossAI` 实装新接口：构造单 slot prompt（输入=双方候选+已 Pick 局面+先手方+剩余能量+slot index），输出 = 选哪张 + 一句意图字幕
  - **Slot 1 预热**（GDD-07 §5 方案 C）：在 Phase 1 banner 演出期间（1.5s）就并发发起 Slot 1 的 LLM 调用，结果缓存到 `_bp_slot1_warmup_future`，Phase 2 第 1 次或第 2 次 Boss Pick 时直接消费缓存
  - `perception_builder.gd` 新增 `build_bp_perception(boss, player, board_state, slot_index)` 方法，废弃旧 `build_blind_perception`
- **不在范围**：思考动画 UI 触发（Epic-BP-6 接 boss_thinking_overlay）；意图字幕 UI 渲染（Epic-BP-6）
- **改动文件**：
  - `scripts/ai/ai_decision_interface.gd` [改]：接口签名
  - `scripts/ai/blind_clash_ai.gd` [改]：实装新接口（保留旧接口不删，BP_MODE_ENABLED=false 时仍能跑）
  - `scripts/ai/llm/perception_builder.gd` [改]：BP perception
  - `scripts/ai/llm/llm_boss_ai.gd` [改]：新调用栈
  - `scripts/ai/llm/llm_config.gd` [改]：调整 max_tokens（单 slot 调用应更短，token 预算从 ~800 降到 ~400）
  - `scripts/battle/blind_clash_battle.gd` [改]：Phase 1 banner 期间触发 Slot 1 预热
- **新增/修改信号**：无（异步通过 await 处理）
- **关键技术决策**：
  1. **prompt 结构**：System(角色性格+规则) + User(当前 Slot 上下文：双方 4 候选+已填 Picks+剩余能量+轮到你 Pick Slot N)，要求输出 JSON `{"card_index": 0-3, "intent": "string"}`
  2. **Slot 1 预热风险**：玩家可能在 Pick 时改变了 Boss 候选（不会，候选回合内固定），但需注意预热时 board_state.player_picks 全 null，与实际 Slot 1 调用时一致 → 预热可安全用
  3. **失败降级**（灰色地带 #2）：单次 LLM 失败 → 立刻调规则 AI 兜底；连续 2 次失败 → 整回合切规则 AI 直到下回合再试 LLM
  4. **token 预算**：单场 4 次调用 ≈ 4 × (input 800 + output 100) tokens ≈ 3600 tokens，单价 ¥0.01-0.025/场（GDD-07 估算 ¥0.04-0.10 留 4× 安全 buffer）
- **验收标准**：
  1. lint 0 错
  2. 跑场景 4 回合 → 看到 16 次 LLM 调用日志 + 4 次预热日志
  3. 强制断网 → fallback 到规则 AI，BP 流程不卡住
  4. 单场 token 消耗实测 < 5000
- **预估工时**：3-4h
- **依赖**：Epic-BP-4
- **风险/未知**：
  - LLM 服务延迟若 > 2s，第 2-4 次 Boss Pick 会卡顿（缓解：boss_thinking_overlay 显示思考动画+预测条蒙在 UI 上让玩家有"对方在想"的体感）
  - 灰色地带 #2 失败降级策略需 vibe-lead 1 句话拍板

---

### Epic-BP-6：pick_select_ui 重写

- **目标**：重写暗出 UI 为 BP 模式（候选区 + 出牌位 + 当前激活槽高亮 + 槽位填充动画 + 实时预测条）。
- **范围**：
  - 新建 `scripts/ui/pick_select_ui.gd`：
    - 上区：Boss 4 张候选区（**完整 cardview 但缩小到 80%**，灰色 picker 蒙层标识"对方候选"）
    - 中区：4 个 Slot 出牌位（双方 each-row：玩家 row + Boss row，每 row 4 个 slot），当前激活 slot 高亮闪烁（黄色边框+脉动）
    - 下区：玩家 4 张候选区（点击高亮 → 再点 Slot 完成 Pick；或拖拽到 Slot）
    - 顶部：能量条 + 当前 picker 标识 + 实时预测条（基于已 Pick 局面调用 ClashResolver.resolve_clash 得到当前 4 槽预测倍率）
  - 旧 `blind_select_ui.gd` 保留不删（BP_MODE_ENABLED=false 时回滚）
  - `blind_clash_scene.gd` 根据 `BP_MODE_ENABLED` 选择实例化 pick_select_ui 或 blind_select_ui
  - 接 `boss_thinking_overlay` 在 Boss Pick 等待 LLM 时显示
- **不在范围**：意图字幕动画（暂用 Toast 显示）；翻盅演出（Epic-BP-7）
- **改动文件**：
  - `scripts/ui/pick_select_ui.gd` [新建]
  - `scripts/ui/blind_select_ui.gd` [改]：加 `if not BP_MODE_ENABLED` 守卫，避免在 BP 模式被错误启用
  - `scenes/battle/blind_clash_scene.tscn` [改]：加 pick_select_ui 节点
  - `scripts/battle/blind_clash_scene.gd` [改]：UI 路由
- **新增/修改信号**：UI 内信号
  - `signal player_pick_requested(card_index: int, slot: int)` → 场景控制器接收并调 battle.make_player_pick
- **关键技术决策**：
  1. **Boss 候选展示形态**（灰色地带 #1 已默认决策）：完整 cardview 缩小 80% + 半透明蒙层"敌方候选"
  2. **实时预测条**：基于已 Pick 的部分槽位调 ClashResolver.resolve_clash（剩余 slot 用占位"未知"），显示当前局面的克制走向 → 让玩家直观感受 Pick 决策的影响
  3. **拖拽 vs 点击**：v0.7.0-alpha 先做点击模式（点候选 → 再点 slot），拖拽留 v0.7.x
  4. **Boss Pick 期间禁用玩家候选区点击**：用 `picker_id != PLAYER` 守卫
- **验收标准**：
  1. 跑场景 → 能看到 Boss 候选区（4 张半透明小卡）+ 4 槽出牌位 + 玩家候选区（4 张可点击）
  2. 玩家 Pick 后 → 候选 → slot 飞行动画（0.3s tween）+ 高亮切到下一 slot
  3. Boss Pick 期间 → boss_thinking_overlay 显示 + 1-3s 后自动出现 Boss 的牌
  4. 实时预测条数值正确（用占位调 resolve_clash 不报错）
- **预估工时**：3-4h
- **依赖**：Epic-BP-4, Epic-BP-5
- **风险**：UI 重写工作量易膨胀 → 缓解：v0.7.0-alpha 实时预测条做基础版（仅显示克制方向箭头），不做完整倍率数字预览

---

### Epic-BP-7：clash_resolver 调度循环改写 + 同时翻盅演出

- **目标**：把 BP_REVEAL 阶段的"4 对一次性翻盅"演出做出来，clash_resolver 数学函数 100% 不动。
- **范围**：
  - `_start_bp_reveal()`：调 `prepare_clash_bp(_bp_player_picks, _bp_boss_picks)`（内部就是现有 `ClashResolver.resolve_clash`），结果缓存到 `_bp_pending_clash_results`
  - emit `bp_reveal_started(results)` → UI 4 对一次性展示（背面→正面 0.5s 翻牌动画 + 2:2 平衡光晕）
  - emit `bp_resolve_started()` → 进 BP_RESOLVING 阶段，从 Slot 1 起每 350ms 调 `apply_clash_pair_at(i)` → emit `clash_pair_resolved`（沿用旧信号）→ UI 飘字
  - 4 对全部 apply 完后 emit `bp_resolve_completed` → 进 Phase 4
  - **clash_display_ui.gd**：新增"同时翻盅模式"分支（4 张同时翻 + 间隔 350ms 飘字），保留旧"逐对翻"模式做兼容
- **不在范围**：陷阱触发（Epic-BP-5/8 阶段不涉及 trap）；认知探针（v0.8.0 回归）
- **改动文件**：
  - `scripts/battle/blind_clash_battle.gd` [改]：BP_REVEAL/BP_RESOLVING 实装
  - `scripts/ui/clash_display_ui.gd` [改]：同时翻盅模式
- **新增/修改信号**：
  - `signal bp_reveal_started(results: Array[ClashResolver.ClashResult])`
  - `signal bp_resolve_started()`
  - `signal bp_resolve_completed()`
  - 沿用 `clash_pair_resolved`（旧信号）
- **关键技术决策**：
  1. **clash_resolver 数学函数 100% 复用**：`resolve_clash`、`apply_multiplier_int`、`is_status_nullified` 一字不改
  2. **resolve_clash 入参改名**：旧 `(player_blind_cards, boss_blind_cards)` 概念变成 `(player_picks, boss_picks)`，但参数类型 `Array[CardData]` 不变 → 可直接传 `_bp_player_picks` 进去
  3. **同时翻盅演出节奏**（灰色地带 #3）：350ms/对，单音效（"翻牌"音效一次播完 + 4 次"飘字"音效错开 350ms）
  4. **0 费绑定逻辑**（Q-BP-4）：v0.7.0-alpha 临时禁用 `player_bound_zero_cards`，apply_clash_pair_at 中 `bound_zero` 永远传 null
- **验收标准**：
  1. BP_REVEAL 阶段视觉：4 张牌同时翻面（0.5s tween）+ 2:2 平衡光晕（如果命中）
  2. BP_RESOLVING 阶段：从 Slot 1 起每 350ms 飘字一次（damage/armor/heal 数字）
  3. HP 数字逐对扣减，不瞬间清零
  4. 4 对全部应用后正确进入 BP_ROUND_END
- **预估工时**：2-2.5h
- **依赖**：Epic-BP-4
- **风险**：clash_display_ui 同时翻盅模式与旧逐对模式的状态机要清晰分离 → 缓解：用 `_reveal_mode: String` 字段切换（"sequential" | "simultaneous"）

---

### Epic-BP-8：回合末清理 + 0 费临时移除 + 陷阱配置位锁定

- **目标**：兑现 Q-BP-3（候选 4 张回合末全弃）+ Q-BP-4（v0.7.0-alpha 暂时移除 0 费）+ Q-BP-5（陷阱锁到 v0.8.0）。
- **范围**：
  - `_start_bp_round_end()`：把 `_bp_player_candidates`（4 张）和 `_bp_boss_candidates`（4 张）全部移到弃牌堆（已 Pick 的不重复弃，因为 Pick 时已扣手牌）
  - **0 费机制临时移除**：
    - `card_database.gd` 默认牌库过滤 `cost > 0` 或 `cost >= 1`（双重保险）
    - `combatant.gd` 抽牌时跳过 0 费（防御性）
    - `pick_select_ui` 候选展示时若有 0 费牌（防御性，应抽不到）灰显
  - **陷阱配置位锁定**：在 `blind_clash_battle.gd` 的 `ENABLE_TRAP_PHASE = false` 上加注释 `# v0.8.0 回归（GDD-07 Q-BP-5）`
  - 清理 BP 流程的 `_bp_*` 字段为下回合准备
- **不在范围**：陷阱阶段重启（v0.8.0 单独 epic）；认知探针重启（v0.8.0）
- **改动文件**：
  - `scripts/battle/blind_clash_battle.gd` [改]：清理 + 注释
  - `autoload/card_database.gd` [改]：过滤 0 费
  - `scripts/battle/combatant.gd` [改]：防御性跳过（可选）
  - `scripts/data/card_data.gd` [改]：可能加 deprecation 注释（可选）
- **新增/修改信号**：无
- **关键技术决策**：
  1. **0 费过滤改默认牌库**：避免每张牌都加 if 守卫
  2. **不删 0 费 CardData 资源文件**：保留磁盘上的 .tres，只过滤运行时
  3. **陷阱注释明确版本**：`const ENABLE_TRAP_PHASE: bool = false  # v0.8.0 回归（GDD-07 Q-BP-5 锁定）`
- **验收标准**：
  1. 跑场景 4 回合 → 候选每回合都重新抽 4 张，不复用上回合的
  2. console 永远不出现 cost==0 的牌名
  3. 陷阱相关 UI 节点在场景中不可见
- **预估工时**：1-1.5h
- **依赖**：Epic-BP-7
- **风险**：现有牌库可能有依赖 0 费的测试用例 → 缓解：grep "energy_cost = 0" 找出来标记 deprecated

---

### Epic-BP-9：烟测脚本 + 验收清单

- **目标**：跑通 v0.7.0-alpha 完整烟测，产出验收报告。
- **范围**：
  - 编写烟测清单（10 条），手动跑通整场战斗
  - 性能采样：单场战斗时长、LLM 调用次数、token 消耗
  - 写 v0.7.0-alpha 收尾报告：完成的 Epic / 已知问题 / 下一步建议
- **改动文件**：
  - `docs/qa/smoke-v0.7.0-alpha.md` [新建]：烟测清单 + 实测结果
  - `commit_log.md` [改]：追加 v0.7.0-alpha 完工条目
  - `production/session-state/active.md` [改]：标记 Sprint 完成
- **烟测清单**（10 条，全部要 PASS）：
  1. ✅ Phase 1 横幅每回合显示 1.5s，文案正确
  2. ✅ 双方候选完全互见（Boss 候选区可见 4 张完整牌信息）
  3. ✅ Pick 顺序正确（先手玩家先填 Slot 1，后手紧跟，依此类推到 Slot 4）
  4. ✅ Boss 4 次 LLM 调用都有 console 日志，Slot 1 调用在 banner 期间预热
  5. ✅ 玩家不能 Pick 超过能量的牌（UI 灰显 + 校验失败）
  6. ✅ 同时翻盅演出（4 张 0.5s 同时翻 + 350ms 错开飘字）
  7. ✅ 2:2 平衡 ×2.0 倍率正确触发（GDD-06 §3 数学不变）
  8. ✅ 一场战斗时长 3-4 分钟（GDD-07 §10 估算）
  9. ✅ 一局 8-10 回合内分胜负
  10. ✅ 单场 token 消耗 < 5000，成本 < ¥0.10
- **预估工时**：1.5-2h
- **依赖**：Epic-BP-1 ~ Epic-BP-8 全部完成
- **风险**：烟测发现的 bug 可能反推回前面 Epic 修复 → buffer 已留在总工期

---

## §3 信号契约总表 / Signal Contract Table

| 信号名 | 参数签名 | 发射方 | 接收方 | 时机 |
|---|---|---|---|---|
| `bp_candidates_drawn` | `(player_cards: Array[CardData], boss_cards: Array[CardData])` | blind_clash_battle | pick_select_ui, blind_clash_scene | Phase 0 末，候选抽完 |
| `bp_first_picker_decided` | `(picker_id: int)` (0=player, 1=boss) | blind_clash_battle | first_picker_banner, pick_select_ui | Phase 1 初，randi 后 |
| `bp_pick_made` | `(picker_id: int, slot: int, card: CardData, remaining_energy: int)` | blind_clash_battle | pick_select_ui, boss_thinking_overlay | 每次 Pick 完成 |
| `bp_all_picks_locked` | `(player_picks: Array[CardData], boss_picks: Array[CardData], first_picker: int)` | blind_clash_battle | pick_select_ui, clash_display_ui | 8 次 Pick 全部完成 |
| `bp_reveal_started` | `(results: Array[ClashResolver.ClashResult])` | blind_clash_battle | clash_display_ui | Phase 3 初 |
| `bp_resolve_started` | `()` | blind_clash_battle | clash_display_ui | Phase 4 初 |
| `bp_resolve_completed` | `()` | blind_clash_battle | blind_clash_scene | 4 对全部 apply 完 |
| `clash_pair_resolved` | `(result: ClashResolver.ClashResult)` (沿用旧信号) | blind_clash_battle | clash_display_ui, combatant_panel | 每对 apply 后 |
| `first_picker_banner.banner_finished` | `()` | first_picker_banner | blind_clash_scene | 横幅 1.5s 演出结束 |
| `player_pick_requested` | `(card_index: int, slot: int)` | pick_select_ui | blind_clash_scene | 玩家点击候选+slot |

---

## §4 文件改动清单总表 / File Change Summary

### 新建（4 个）

| 文件 | 用途 | Epic |
|---|---|---|
| `scripts/ui/pick_select_ui.gd` | BP 模式 UI 主体 | Epic-BP-6 |
| `scripts/ui/first_picker_banner.gd` | 先手随机横幅演出 | Epic-BP-3 |
| `docs/qa/smoke-v0.7.0-alpha.md` | 烟测清单+实测 | Epic-BP-9 |
| `docs/design/epics/epic-bp-b-prime.md` | 本文档 | (已完成) |

### 重写/大改（4 个）

| 文件 | 改动摘要 | Epic |
|---|---|---|
| `scripts/battle/blind_clash_battle.gd` | BP 6 阶段状态机 + 信号 + Pick 调度 | Epic-BP-1/2/3/4/7/8 |
| `scripts/ai/blind_clash_ai.gd` | 新增 `pick_for_slot_async` 接口 | Epic-BP-5 |
| `scripts/ai/llm/llm_boss_ai.gd` | 单 slot LLM 调用 + Slot 1 预热 | Epic-BP-5 |
| `scripts/ai/llm/perception_builder.gd` | `build_bp_perception` 新方法 | Epic-BP-5 |

### 小改（6 个）

| 文件 | 改动摘要 | Epic |
|---|---|---|
| `scripts/battle/blind_clash_scene.gd` | UI 路由 + 信号转发 | Epic-BP-3/6 |
| `scripts/ui/clash_display_ui.gd` | 同时翻盅模式分支 | Epic-BP-7 |
| `scripts/ui/blind_select_ui.gd` | 加 BP_MODE 守卫（不删） | Epic-BP-6 |
| `scripts/ai/ai_decision_interface.gd` | 接口签名升级 | Epic-BP-5 |
| `scripts/ai/llm/llm_config.gd` | max_tokens 调整 | Epic-BP-5 |
| `autoload/card_database.gd` | 0 费过滤 | Epic-BP-8 |
| `scenes/battle/blind_clash_scene.tscn` | 加 pick_select_ui + first_picker_banner 节点 | Epic-BP-3/6 |

---

## §5 实施路线（推荐顺序 + 可演示节点） / Implementation Roadmap

| Epic | 完成后用户能看到什么 | 演示价值 |
|---|---|---|
| **Epic-BP-1** | console 按序打印 6 个 BP 阶段 | 骨架活了，结构对齐 |
| **Epic-BP-2** | 候选抽取日志（含双方 4 张牌名） | 数据通道打通 |
| **Epic-BP-3** | **1.5s 先手横幅演出**（视觉化首战体验） | 第一个"看得见"的 v0.7 元素 |
| **Epic-BP-4** | console Pick 调度日志（无 UI 但能 console 模拟点击 advance） | 核心循环 alive |
| **Epic-BP-5** | LLM 4 次调用日志 + 思考动画时间戳 | LLM 接口落地 |
| **Epic-BP-6** | **完整 BP 战斗 UI**（候选区+出牌位+预测条） | v0.7.0-alpha 主视觉成果 |
| **Epic-BP-7** | **同时翻盅演出**（4 张同翻+错开飘字） | 戏剧性峰值 |
| **Epic-BP-8** | 0 费消失 + 陷阱不出现 + 候选回合末全弃 | 收口完成 |
| **Epic-BP-9** | 烟测报告 PASS + v0.7.0-alpha tag | 收尾交付 |

**推荐先做 Epic-BP-1**，理由：
- 零风险锚点（只搭骨架不动业务逻辑）
- 强制对齐效果（信号契约定死后续 Epic 边界自动清晰）
- 2 小时内可演示 6 阶段 console 流转
- 可在实施期间补 3 条灰色地带的决策

如果用户想"最快看到视觉成果"，可改先做 **Epic-BP-3**（1.5h 内能看到先手横幅 1.5s 演出）。

---

## §6 风险与未知 / Risks & Unknowns

### 🔴 高风险

1. **LLM 调用频率提升 4×（1 次/回合 → 4 次/回合）**：网络延迟若 >2s，第 2-4 次 Boss Pick 会卡顿明显。
   - **缓解**：boss_thinking_overlay 显示思考动画 + 实时预测条 + Slot 1 预热（Epic-BP-5 兑现）
   - **应急**：若实测延迟不可接受，回退到"BP 但 Boss 一次性出 4 张"中间方案（保留明牌互见但牺牲顺序博弈）

2. **UI 重写工作量易膨胀**（Epic-BP-6 估 3-4h 但有变 5-6h 风险）
   - **缓解**：v0.7.0-alpha 实时预测条做基础版（仅克制方向箭头），完整倍率数字预览留 v0.7.x

### 🟡 中等风险

3. **双轨并存（v0.6.1 暗出 + v0.7 BP）维护成本**
   - 缓解：BP_MODE_ENABLED const 切换 + 全程烟测两条路径，Epic-BP-9 完成后下一个 sprint 评估是否清理

4. **clash_display_ui 同时翻盅 vs 旧逐对翻**模式状态机分离
   - 缓解：用 `_reveal_mode: String` 字段切换

### 🟢 灰色地带（需 vibe-lead/game-designer 1 句话拍板）

1. **Boss 候选展示形态**：默认采用"完整 cardview 缩小 80% + 半透明蒙层"。是否需要美术指导/UX 主管确认？
2. **LLM 失败降级策略**：单次失败立即兜底规则 AI / 连续 2 次失败整回合切规则 AI / 是否要弹用户提示？
3. **同时翻盅连锁飘字节奏**：默认 350ms/对 + 单音效。是否需要 audio-director 调音？

---

## §7 与 GDD-07 的对照表 / GDD Cross-Reference

| GDD-07 章节 | 对应 Epic |
|---|---|
| §1 设计哲学转变 | (无，纯设计) |
| §2 6 阶段流程图 | Epic-BP-1（状态机骨架） |
| §3 Pick 阶段规则 | Epic-BP-4 |
| §4 同时翻盅+结算 | Epic-BP-7 |
| §5 LLM Boss 接口（方案 C） | Epic-BP-5 |
| §6 UI 流程图 | Epic-BP-3, Epic-BP-6 |
| §7 5 个 Q-BP-* 答案 | Q-BP-1 → Epic-BP-2; Q-BP-2 → 不需要实施; Q-BP-3 → Epic-BP-8; Q-BP-4 → Epic-BP-8; Q-BP-5 → Epic-BP-8 |
| §8 取代关系 | (无，文档级) |
| §9 实施优先级 | 本文档 §5 |
| §10 风险 | 本文档 §6 |

---

> **下一步**：等用户审本文档 → 拍板"按推荐顺序从 Epic-BP-1 开始" / "改先做 Epic-BP-3 优先看视觉" / "对某 Epic 拆得太大要再细" / "对 3 条灰色地带给决策" → 进入实施。
