# Epic-BP-7 翻盅演出回归方案（v0.3 · 定稿）

> 撰写：vibe-lead 整合 game-designer + ux-lead 产出
> 日期：2026-05-15
> 状态：**已定稿** —— 用户拍板"全推荐"+ 追加"切场过渡动画"
> 历史：v0.1（含 7 决策待审）→ v0.2（用户拍板：1A 2B 3B 4B 5B 6N/A 7同意）→ v0.3（追加 §2.5 过渡动画 + 信号链修正 + z 顺序保障）

---

## 0. TL;DR

把 BP 模式（明牌 Pick 完成后）的"翻盅演出"，**从 hotfix.7 在 pick_select_ui 上的"就地光晕揭示"**，**回归到 GDD-04 §1 钦定的"全屏翻盅 + 牌背朝下 + 同时翻面"**演出，复用已存在的 `scripts/ui/clash_display_ui.gd`（CRPG 模式仍在用）。

**核心改动一句话**：`pick_select_ui._on_bp_reveal_started` 不再就地画光晕，而是 **播 1s 仪式过渡 → 唤起 clash_display_ui 接管 → 演出结束播 1s 收尾过渡**。

---

## 1. 设计意图与 GDD 锚点

### 1.1 GDD 引用

**GDD-04 §1「回合结构」对决阶段的原始描述**（`docs/design/gdd/04-blind-clash-revision.md` L51-58，**节选**，已剥离已废的陷阱条目）：

> ```
> │ 4. 对决阶段（Clash Phase）—— 逐张翻开                        │
> │    • 第1对：玩家翻#1 ↔ Boss翻#1 → 碰撞结算                  │
> │    • 第2对：玩家翻#2 ↔ Boss翻#2 → 碰撞结算                  │
> │    • ...                                                     │
> │    • 多余牌（某方出牌更多）：逐张翻开，按原效果100%直接生效   │
> │    • 0费绑定牌随主牌一起翻开，效果叠加到主牌结算中           │
> ```

**关键词**：「**逐张翻开**」「翻 #1」「**翻**」——隐含"牌一开始是背面，翻面动作本身是仪式"。

> 📝 **说明**：GDD-04 原文还提到"陷阱触发追加结算"，但**陷阱系统在 Epic-BP-6/7 重写中已整体移除**（v0.7 阶段废弃）。本方案**不再处理陷阱**。

### 1.2 hotfix.7 偏离 GDD 的三大问题

| # | 问题 | 后果 |
|---|---|---|
| 1 | **没有"翻面"动作**：明牌 Pick 阶段牌已正面朝上，hotfix.7 沿用这个状态在槽位上画光晕 | 失去"揭晓瞬间"的戏剧张力，演出像"加了滤镜" |
| 2 | **演出舞台缺失**：4 对在 pick UI 4 个槽位上同时演出，玩家视线分散 | 心理负载高，4 对挤在视野里很难逐对欣赏 |
| 3 | **信息节奏不分层**：Pick 已经把所有信息透明化，演出阶段如果再不"刻意制造未知 → 揭晓"，就压平了情绪曲线 | 戏剧感为 0，仪式感缺失 |

### 1.3 BP 哲学的"信息分层"

```
┌─────────────────────────┬─────────────────────────┐
│ 策略层（Pick 阶段）     │ 演出层（Clash 阶段）    │
├─────────────────────────┼─────────────────────────┤
│ 全程明牌                │ 牌背 → 翻面 → 揭晓     │
│ 玩家全知 / Boss 全知    │ 刻意"重置未知"          │
│ 心理博弈、预判、抢先 Pick│ 仪式 / 节奏 / 情绪释放  │
│ 用户决策中枢            │ 用户感受确认中枢        │
└─────────────────────────┴─────────────────────────┘
```

两层职责完全不同。Pick 的"明"和 Clash 的"翻"**不矛盾**——Clash 的"翻"不是为了隐藏信息（玩家已经知道结果），而是**为了让玩家"经历"那个揭晓的瞬间**。

---

## 2. 演出流程（用户视角时间轴 · 决策 5B：单对 2.8s）

```
T = 0.00s   第 8 张 Pick 锁定 → battle._start_bp_reveal() 预算 results → emit bp_reveal_started(results)

═══════ 【入场过渡】1.0s 仪式开场（v0.3 新增）═══════
T = 0.00s   pick_select_ui._on_bp_reveal_started(results)
              ① 顶部条："▶ 全部 Pick 完成 — 翻盅！" 高亮金 → 渐隐（0.5s）
              ② 4 对槽位"被 Pick 中"的卡牌：modulate.a 1.0 → 0.0（0.4s）
              ③ 4 对槽位框：金色高亮闪一次（modulate → 金 0.18s → 还原 0.32s）
              ④ 候选区残牌（被灰显的）+ 底部预测条：modulate.a → 0（0.4s）
              ⑤ 屏幕级 ColorRect 黑幕：alpha 0 → 0.65（0.6s ease-out）
              ⑥ "翻盅" 大字（96pt 金 outline 8）：scale 1.4→1.0 fade-in（0.5~0.75s）→ 停 0.1s → fade-out（0.85~1.0s）
T = 1.00s   入场过渡完成
              ↓ pick_select_ui 调 battle.confirm_bp_reveal_done() 切到 BP_RESOLVING
              ↓ pick_select_ui 调 clash_display_ui.start_clash_animation(results, apply_cb)

═══════ 【翻盅阶段】单对 2.8s × 4 对 = 11.2s ═══════
【第 1 对】
T = 1.00s   双方 #1 槽的牌（牌背）从两侧滑入中央对决区（0.30s）
T = 1.30s   中央两张牌背静止"对峙"（0.40s）—— 期待感
T = 1.70s   双方同时翻面（压扁 0.24s → 切正面 → 还原 0.26s = 0.50s）
T = 2.20s   apply_cb(0)：扣血/护甲/抽牌 → Combatant 信号 → 飘字 + 血条变化
            克制反馈（决策 4B）：克制方牌金色边框 + 1.05× 缩放 + 屏幕轻震 100ms
T = 2.20s   飘字按双拍 stagger（决策 2B）：
              • T+0.00s  伤害 ↓-N（强拍，承伤方牌正上方）
              • T+0.35s  护甲 🛡+N + HP ↑+N（防御类同时，收益方牌正上方）
              • T+0.70s  抽牌 🃏+N（弱拍，收益方牌正上方）
T = 3.80s   当前对淡出（无停顿，立即接下一对）

【第 2-4 对】重复 × 3 = 8.40s

═══════ 【收尾过渡】1.0s 退场 ═══════
T = 12.20s  4 对完成 → clash_display_ui 内容（HBox + PairCounter）淡出（0.5s）
T = 12.50s  ColorRect 黑幕 alpha 0.65 → 0（0.5s 渐出，与上一步重叠 0.2s）
T = 12.70s  pick_select_ui 顶部条 → "▶ 回合结束"金，槽位框 modulate 渐回 0.5（0.5s）
T = 13.20s  emit bp_resolve_completed → battle._start_bp_round_end()
            bp_round_cleanup → 候选 4 张全弃 → 进入下一回合 Pick
```

**总演出时长**：约 **13.2s**（含 1.0s 入场过渡 + 11.2s 翻盅 + 1.0s 收尾过渡）

> **跳过键（决策 3B 双轨制）**：
> - 长按空格 = ×0.3 即时加速（松开恢复）
> - 单击空格 = 跳过当前对（直接进入下一对）
> - 设置滑条 = 0.5×~2× 持久化倍率
> - **入场/收尾过渡不可跳过**（仪式锚点，各 1.0s 不长）

---

## 2.5. 过渡动画详细分解（v0.3 核心新增）

### 2.5.1 入场过渡（0.0s → 1.0s）

**驱动方**：`pick_select_ui._on_bp_reveal_started()` 内部用 Tween 编排（6 条并行子动画）

| # | 目标节点 | 属性 | 起 → 终 | 时间窗 | Ease |
|---|---|---|---|---|---|
| ① | `_top_label` | text + modulate | "▶ Pick 完成"白 → "" 渐隐 | 0.0~0.5s | OUT_QUAD |
| ② | 8 张槽位卡 wrapper | modulate.a | 1.0 → 0.0 | 0.0~0.4s | IN_QUAD |
| ③ | 8 个 slot Panel | modulate（金闪） | WHITE → 金(1,0.85,0.3) → WHITE | 0.0~0.18→0.32s | IN_OUT_QUAD |
| ④ | 候选 wrapper + bottom_label | modulate.a | 1.0 → 0.0 | 0.0~0.4s | OUT_QUAD |
| ⑤ | clash_display_ui 内 ColorRect | color.a | 0.0 → 0.65 | 0.0~0.6s | OUT_CUBIC |
| ⑥ | "翻盅" 标题 Label（动态创建） | scale + modulate.a | 1.4 / 0 → 1.0 / 1.0 → 0.0 | 0.5~0.75 in / 0.85~1.0 out | OUT_CUBIC |

**关键代码骨架**（vibe-lead 给出参考，最终由 godot-gdscript-specialist 实现）：

```gdscript
# pick_select_ui.gd
func _on_bp_reveal_started(results: Array) -> void:
    if _battle == null:
        return
    # 1. 准备：clash_display_ui 提到顶层 + lazy 创建黑幕 ColorRect
    var clash_ui: Control = get_parent().get_node_or_null("ClashDisplayUI")
    if clash_ui == null:
        push_warning("[PickUI] 找不到 ClashDisplayUI，回退直接 confirm")
        _battle.confirm_bp_reveal_done()
        return
    clash_ui.move_to_front()
    clash_ui.visible = true
    var backdrop: ColorRect = _ensure_backdrop(clash_ui)

    # 2. 播 6 条入场过渡（1.0s）
    await _play_transition_in(clash_ui, backdrop)

    if _battle == null:
        return  # 异常退出

    # 3. 切阶段 + 启动 clash 演出
    _battle.confirm_bp_reveal_done()  # → BP_RESOLVING
    if _battle.current_bp_phase != BlindClashBattle.BPPhase.BP_RESOLVING:
        return
    var apply_cb := func(idx: int) -> void:
        if _battle != null:
            _battle.apply_bp_clash_pair_at(idx)
    clash_ui.start_clash_animation(results, apply_cb)
    await clash_ui.clash_animation_complete

    # 4. 收尾过渡（§2.5.2）
    await _play_transition_out(clash_ui, backdrop)
```

### 2.5.2 收尾过渡（12.2s → 13.2s）

| # | 目标 | 属性 | 起 → 终 | 时间窗 | Ease |
|---|---|---|---|---|---|
| A | clash_display_ui HBox | modulate.a | 1.0 → 0.0 | 0.0~0.5s | IN_QUAD |
| B | ColorRect 黑幕 | color.a | 0.65 → 0.0 | 0.3~0.8s | IN_CUBIC |
| C | pick_select_ui top_label | text + modulate | "" / 透明 → "▶ 回合结束"金 / 1.0 | 0.5~0.8s | OUT_QUAD |
| D | 8 个 slot Panel | modulate.a | 0.0 → 0.5（淡显作"已 Pick 历史"） | 0.5~1.0s | OUT_QUAD |

收尾完成后 `clash_ui.visible = false`，`backdrop.color.a = 0`（保留节点供下回合复用）。battle 内 `_finish_resolving_after_delay`（v0.3 改回 0.6s）会自动推进到 BP_ROUND_END，触发 `bp_round_cleanup`，pick_select_ui 在 `_on_bp_round_cleanup` 重置准备下一回合。

### 2.5.3 信号链（v0.3 修正版）

> ⚠️ **v0.2 信号链时序需校正**：`apply_bp_clash_pair_at` 必须在 `BPPhase.BP_RESOLVING` 才能成功（battle.gd L1290）。**v0.3 在入场过渡完成时（T=1.0s）调用 `confirm_bp_reveal_done`，确保后续 apply_cb 调用时 phase 正确**：

```
T = 0.0s   battle emit bp_reveal_started(results)              BPPhase = BP_REVEAL
           ↓
           pick_select_ui._on_bp_reveal_started(results)
           ↓ ① 播 1.0s 入场过渡（§2.5.1）
T = 1.0s   ↓ ② battle.confirm_bp_reveal_done()                 BPPhase = BP_RESOLVING ✓
           ↓ ③ clash_display_ui.start_clash_animation(results, apply_cb)
           ↓ ④ clash_display_ui 内逐对：滑入 → 翻面 → apply_cb(idx) → 飘字
T = 2.2s   ↓ ⑤ apply_cb(0) → battle.apply_bp_clash_pair_at(0)  状态正确 ✓
           ↓ ... 第 2/3/4 对类似
T = 12.2s  ↓ ⑥ 最后一对 apply 后 battle 自动 emit bp_resolve_completed
           ↓ ⑦ battle._finish_resolving_after_delay(0.6s) 自动推到 BP_ROUND_END
           ↓ pick_select_ui 收 clash_animation_complete → 播收尾过渡（§2.5.2）
T = 13.2s  ↓ 演出完全结束
```

### 2.5.4 z 顺序保障

`scenes/battle/blind_clash_scene.tscn` 中 `ClashDisplayUI` 是 tscn 静态节点（在 `$UI/UIRoot/ClashDisplayUI`）；`pick_select_ui` 是 `_setup_bp_mode_ui()` 运行时 add_child 到 `$UI/UIRoot` 的——**默认 pick_select_ui z 序更高**（兄弟节点后加靠上）。实施时必须：

```gdscript
clash_ui.move_to_front()  # 入场过渡前调用，把 ClashDisplayUI 挪到 UIRoot 子节点末尾
```

CRPG 模式不受影响（CRPG 的 clash 调用走 `blind_clash_scene.gd` 自己的路径，不经过 pick_select_ui）。

### 2.5.5 ColorRect 黑幕节点（动态创建，不改 tscn）

```
ClashDisplayUI (Control)
├── Backdrop (ColorRect, lazy 创建)         ← 黑幕，子节点最底
│   anchor_preset = FULL_RECT
│   color = (0, 0, 0, 0) 初始
│   mouse_filter = STOP（吃掉下层点击）
├── TopBar / PairCounter                     （tscn 原有）
└── HBox / PlayerSide CardSlot / Center / BossSide CardSlot
```

由 pick_select_ui 在转场时 lazy 创建（`get_node_or_null("Backdrop")` 判空），后续回合复用同一节点（color.a 直接 tween）。

```gdscript
func _ensure_backdrop(clash_ui: Control) -> ColorRect:
    var backdrop: ColorRect = clash_ui.get_node_or_null("Backdrop") as ColorRect
    if backdrop != null:
        return backdrop
    backdrop = ColorRect.new()
    backdrop.name = "Backdrop"
    backdrop.color = Color(0, 0, 0, 0)
    backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
    backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
    clash_ui.add_child(backdrop)
    clash_ui.move_child(backdrop, 0)  # 子节点最底
    return backdrop
```

---

## 3. 各阶段视觉/听觉/反馈设计（定稿）

### 3.1 阶段时长表（决策 5B）

| 阶段 | 时长 | 视觉 | 飘字 |
|---|---|---|---|
| 入场过渡 | 1.0s | 槽位淡出 + 黑幕渐入 + "翻盅"大字 | — |
| 滑入 | 0.30s | 牌背从两侧飞入中央对决区 | — |
| 对峙 | 0.40s | 两张牌背静止居中 | — |
| 同时翻面 | 0.50s | 压扁→正面→还原（同步 tween） | — |
| 结算 | 1.60s | 克制方金边框 + 1.05× 缩放 + 屏震 100ms；血条 tween | 双拍 stagger 4 条飘字 |
| 衔接 | 0.0s | 当前对淡出立即接下一对 | — |
| 收尾过渡 | 1.0s | clash 内容淡出 + 黑幕淡出 + pick UI 渐显 | — |

### 3.2 飘字方案（决策 1A + 2B + 7同意）

**位置（决策 1A 牌身锚定）**：
- 伤害飘字 → 承伤方那张牌正上方（屏幕中央对决区里的"对方牌"）
- 增益飘字（甲/HP/抽） → 收益方那张牌正上方
- 多条增益**纵向堆叠**，由 stagger 时间错开避免空间挤占

**时间节奏（决策 2B 双拍）**：

| 时刻 | 内容 | 强弱 |
|---|---|---|
| T+0.00s | 伤害 ↓-N | 强拍 |
| T+0.35s | 护甲 🛡+N **同时** HP ↑+N | 中拍（合并） |
| T+0.70s | 抽牌 🃏+N | 弱拍 |

叙事："挨打 → 回血 → 顺带抽牌"

**符号前缀（决策 7 同意默认加）**：
- 伤害：`↓-N`（红）
- 治疗：`↑+N`（绿）
- 护甲：`🛡+N`（蓝）
- 抽牌：`🃏+N`（白）

色弱玩家关闭颜色后仍可通过符号区分。

**字体规约**：
- font_size = 34
- outline = 5（黑色描边）
- 生命周期 1.5s（淡入 0.1s → 持有 1.0s → 淡出 0.4s）
- 上飘距离 90px

### 3.3 反馈层次（决策 4B 视觉化）

**保留**：
- 倍率标签（1.5× / 2.0×）小字显示在牌侧
- 屏幕轻震（克制方占优时 100ms / 0.5° 抖动）

**新增**：
- 克制方牌**金色边框**（4px，半透明发光）
- 克制方牌**1.05× 缩放**（0.2s tween in，0.3s tween out）

**移除**：
- 现有 clash_display_ui 的"克制!"/"被克制!"/"VS"大字（4 对连看会腻）

### 3.4 跳过与节奏（决策 3B 双轨制）

| 输入 | 行为 |
|---|---|
| 长按空格 | 演出 ×0.3 加速（松开恢复 1.0×） |
| 单击空格 | 跳过当前对（立即触发 apply_cb，进入下一对） |
| 设置滑条 | 0.5× ~ 2.0× 全局持久倍率（保存到用户配置） |

**不采用**："已见效果自动加速"——违反 UX 可预测性原则。

---

## 4. 与 Pick UI 的状态衔接

### 4.1 演出期间 pick_select_ui 状态

- 4 对槽位**卡片**淡到 alpha=0（入场过渡 ②）
- 4 对**槽位框**先金闪一次（入场过渡 ③），收尾时还原到 alpha=0.5 作"已 Pick 历史"参考
- 顶部 / 底部信息条 modulate.a → 0（入场过渡 ① ④）
- pick_select_ui 整体不 hide，作为 clash_display_ui 的底版（黑幕 ColorRect 盖在它上面）

### 4.2 演出完成后

`clash_animation_complete` 触发 → 收尾过渡 1.0s 后：
1. clash_display_ui.visible = false
2. pick_select_ui 顶部条显示"▶ 回合结束"
3. battle 内 `_finish_resolving_after_delay(0.6s)` 自动 emit `bp_round_cleanup`
4. pick_select_ui 在 `_on_bp_round_cleanup` 重置 → 进入下一回合 Pick（`bp_candidates_drawn` 触发 UI 重建）

---

## 5. 数据流与代码改动范围（不写代码、只点路径）

### 5.1 信号链（最终版）

```
battle._start_bp_reveal()
   ↓ emit bp_reveal_started(results)
pick_select_ui._on_bp_reveal_started(results)
   ↓ 1. 准备 clash_ui.move_to_front() + lazy 创建 Backdrop ColorRect
   ↓ 2. await _play_transition_in()  // 1.0s 入场（§2.5.1）
   ↓ 3. battle.confirm_bp_reveal_done()  // 切到 BP_RESOLVING
   ↓ 4. clash_display_ui.start_clash_animation(results, apply_cb)
        其中 apply_cb = func(idx): _battle.apply_bp_clash_pair_at(idx)
   ↓ 5. await clash_display_ui.clash_animation_complete
   ↓ 6. await _play_transition_out()  // 1.0s 收尾（§2.5.2）
battle._finish_resolving_after_delay(0.6s) → emit bp_resolve_completed → bp_round_end
```

### 5.2 pick_select_ui.gd 改动

**删除项**：
- 常量：`REVEAL_GLOW_DUR`、`RESOLVE_PAIR_DUR`、`FLOAT_NUM_LIFETIME`、`FLOAT_STAGGER_*` ×4、`FLOAT_X_OFFSET_*` ×4、`REVEAL_COLOR_*` ×3
- 方法：`_play_reveal_for_pair`、`_spawn_effect_floats_for_card`、`_spawn_floating_text`、`_flash_panel`、`_spawn_multiplier_label`、`_spawn_pair_floating_numbers`

**改写**：
- `_on_bp_reveal_started` 删除现有就地揭示逻辑，改为 §2.5.1 骨架（含 z 顺序、黑幕、过渡、唤起 clash_display）
- `_on_bp_resolve_completed` 改为空实现或仅更新 top_label（收尾过渡由 clash_animation_complete 后的 await 段处理）

**新增**：
- `_play_transition_in(clash_ui, backdrop) -> void`（async）
- `_play_transition_out(clash_ui, backdrop) -> void`（async）
- `_ensure_backdrop(clash_ui) -> ColorRect`
- `_create_title_label(clash_ui) -> Label`（创建"翻盅"96pt 大字）

### 5.3 clash_display_ui.gd 改动

| 项 | 改动 |
|---|---|
| 现有 `start_clash_animation(results, apply_cb)` 接口 | **保持不变** |
| 节奏参数 | 从硬编码改为 const：滑入 0.30 / 对峙 0.40 / 翻面 0.50 / 结算 1.60s（决策 5B） |
| 克制反馈 | **删除**"克制!"/"被克制!"大字（versus_label 仅保留 "VS"，且静音淡显）；**新增**克制方 CardSlot 金色边框 + 1.05× 缩放（tween）+ 全屏轻震 100ms |
| 飘字驱动 | 仍由 Combatant 信号触发；apply_cb 调用前后各 stagger 一段，按 §3.2 双拍节奏 |
| 飘字位置 | 改为牌身锚定：spawn 到 PlayerSide/CardSlot 或 BossSide/CardSlot 的子节点（屏幕中央对决区里牌的正上方） |
| 飘字符号前缀 | ↓-N（伤害） / ↑+N（治疗） / 🛡+N（甲） / 🃏+N（抽） |
| 跳过键 | 新增 `_input(event)` 处理 Space：长按 ×0.3 时间倍率 / 单击 emit 当前对快进信号 / 设置滑条由后续 settings UI 接入（本期先内置默认 1.0×） |

### 5.4 battle.gd 改动

- `_finish_resolving_after_delay` 的延迟 `1.0s` **改回 `0.6s`**（hotfix.7 拉长是为了配合就地飘字 1.8s 生命周期，回归 clash_display_ui 后由它自己控制节奏）

### 5.5 blind_clash_scene.gd 改动

- **不需要改**！scene 在 BP 模式下不直接调 clash_display.start_clash_animation（让 pick_select_ui 接管）
- CRPG 模式（非 BP）继续走原有路径

### 5.6 飘字驱动协议（关键澄清）

clash_display_ui 内部**不直接画飘字**，而是依靠 apply_cb 触发 Combatant 信号链 → battle_effects 路径生成飘字。

但有两个调整：
1. **飘字 spawn 父节点改为 clash_display_ui 内的 PlayerSide/BossSide CardSlot**（牌身锚定）—— 这需要 battle_effects 在 BP_RESOLVING 阶段使用 clash_display 的 anchor，而不是 pick_select_ui 的槽位
2. **stagger 由 apply_cb 内部分批 emit 信号实现**——apply_bp_clash_pair_at 在结算时按 0/0.35/0.70s 三批 emit Combatant 信号

**实施 hint**：可以在 `apply_bp_clash_pair_at` 内部加 `await` 节奏分批，或者在 clash_display_ui 内拦截信号自己 stagger。**实施时让 godot-gdscript-specialist 评估更稳的方案**——本方案不强制具体实现路径，只验收最终视觉效果（QA §6 第 2 条）。

---

## 6. 验收标准（QA Checklist · 9 + 3 条）

### 6.1 翻盅核心

1. ✅ **翻面同步**：双方第 N 对的牌**同时**完成翻面动作（误差 ≤ 1 帧）
2. ✅ **飘字不重叠**：同对同张牌的多条飘字（伤害/甲/HP/抽）按双拍 stagger 错开，1080p 屏幕下都能完整看清
3. ✅ **血条同步**：HP/护甲条变化时机与翻面**同步或稍后**，绝不能"先掉血再翻牌"
4. ✅ **4 对完整**：从第 1 对到第 4 对全部播完，无缺失、无错位
5. ✅ **克制反馈明显**：克制方牌可见金色边框 + 1.05× 缩放 + 屏幕轻震，**无残留"克制!"大字**
6. ✅ **跳过键有效**：长按空格 ×0.3 加速，松开恢复正常；单击空格跳过当前对
7. ✅ **无残留光晕**：演出结束后，pick_select_ui 4 对槽位无 hotfix.7 遗留的光晕/边框/倍率标签
8. ✅ **return_phase 正确**：演出结束 → BP_RESOLVING 完成 → BP_ROUND_END → 进入下一回合 Pick
9. ✅ **色弱兼容**：飘字符号前缀（↓↑🛡🃏）在关闭颜色后仍可区分四种效果

### 6.2 过渡动画（v0.3 新增）

10. ✅ **入场不突兀**：从 Pick 完成到第 1 对牌滑入中央，**有可见的 1.0s 过渡**（槽位淡出 + 黑幕渐入 + "翻盅"大字）
11. ✅ **z 顺序正确**：clash_display_ui 黑幕完全盖住 pick_select_ui，不漏底
12. ✅ **收尾不跳变**：4 对结算完后**有可见的 1.0s 收尾**（clash 内容淡出 + 黑幕淡出 + pick_select 渐显），不是"啪"地直接消失

---

## 7. 风险与开放问题

### 7.1 风险

| 风险 | 等级 | 缓解 |
|---|---|---|
| clash_display_ui 节奏从 3.5s 砍到 2.8s 影响仪式感 | 低 | 决策 3B 滑条让玩家自定义 0.5×~2.0× |
| 飘字 spawn 位置切换（pick_select 槽 → clash_display 卡区）涉及 battle_effects 重连 | 中 | §5.6 给 godot-gdscript-specialist 自由选择实现路径 |
| ColorRect 黑幕首次创建 + tween 可能在低性能机首帧抖动 | 低 | lazy 创建 + alpha 0 起 tween 已规避 |
| pick_select_ui 在 PRESET_FULL_RECT 占满 UIRoot，clash_display 也占满 → tween 同源时 z 抢占 | 低 | move_to_front 解决（§2.5.4） |
| 战斗中途死亡（某对结算后 HP=0）打断收尾过渡 | 中 | clash_display 已有 `current_bp_phase != BP_RESOLVING` 早退；过渡 await 内同样判 _battle 是否仍合法 |

### 7.2 已关闭决策（用户拍板：全推荐 + 加过渡）

| # | 决策项 | 定稿 |
|---|---|---|
| 1 | 飘字位置 | **A 牌身锚定** |
| 2 | stagger 节奏 | **B 双拍** |
| 3 | 跳过键 | **B 双轨制** |
| 4 | 克制反馈 | **B 视觉化** |
| 5 | 单对时长 | **B 2.8s** |
| 6 | 陷阱飘字 | **N/A**（陷阱已废） |
| 7 | 色弱符号 | **同意默认加** |
| 8 (v0.3) | **过渡动画** | **入场 1.0s + 收尾 1.0s**（§2.5） |

---

## 8. 下一步实施计划

1. ✅ **方案定稿** —— 当前文档（v0.3）
2. 派 `godot-gdscript-specialist` 实施（4 步）：
   - **Step 1**：删除 pick_select_ui.gd 的 hotfix.7 块（§5.2 删除项）
   - **Step 2**：改写 `_on_bp_reveal_started` 走过渡 + 唤起 clash_display_ui（§5.2 改写 + 新增）
   - **Step 3**：clash_display_ui.gd 按 §5.3 改造（节奏参数化 / 克制视觉化 / 飘字双拍 + 牌身锚定 + 符号 / Space 跳过）
   - **Step 4**：battle.gd `_finish_resolving_after_delay` 延迟 1.0s → 0.6s
3. 烟测（QA §6 12 条 checklist 全过）
4. 用户验收
5. 更新 `commit_log.md` v0.7 段落
6. 派 audio-director 后续接入翻面音效（克制/被克/中立三层差异）

---

> ✅ **方案 v0.3 定稿，进入实施阶段**
