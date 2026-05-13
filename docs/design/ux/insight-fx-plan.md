# UX § — 洞察三效果视觉方案（v0.4.3 草案）

> 作者：ux-lead（vibe-lead 综合）  
> 状态：**视觉方案，未实施**。  
> 关联：`docs/design/gdd/05-insight-application.md`、`scripts/ui/probe_display_ui.gd`、`scripts/ui/base_card_ui.gd`、`scripts/ui/blind_select_ui.gd`

---

## 0. 设计原则

> **三色三形语言完全不重叠** —— 玩家瞥一眼就能区分发生的是哪种洞察。

| 效果 | 主色 | 形状语言 | 情绪基调 |
|------|------|----------|----------|
| peek（窥视） | 青色 #00E5FF | 扫描线 + 取景框四角 | 监视、被注视 |
| disrupt（干扰） | 血红 #FF2A2A | 锁链 + 电路冻结 | 剥夺、僵硬 |
| seize（夺取） | 黑+紫 #1A0033 边 | 裂缝 + 真空吸力 | 恐怖、永久丧失 |

---

## 1. 阶段一：本回合"宣告动画"（PROBE 阶段）

### 1.1 peek（窥视）— 监视感

**触发**：`insight_effect("peek", card)` emit 时，目标卡为玩家手牌中的某张实体 `BaseCardUI`。

**演出**：
1. 从 Boss 全息体（屏幕上方）射出**青色扫描光线**（细线，宽 4px，发光），1.0s 横扫至目标卡位置。
2. 扫描线触达卡牌瞬间，卡四角浮现**青色取景框**（L 形角标，每个 32px），缓动放大→收紧锁定，0.3s。
3. 卡正面从顶部到底部刷过一道**数据流粒子**（小光点向下流），玩家短暂能看到这张牌（即使是 BLIND 状态也短暂揭示），0.5s 后粒子消失。
4. 取景框留在原地呼吸 0.4s，淡出。
5. 总时长 **1.2s**。

**最终状态**：取景框收回，卡保持原貌，但已被打上"被窥视"内部标记（视觉上无明显残留，等下回合应用时才显现持续标记）。

### 1.2 disrupt（干扰）— 剥夺感

**演出**：
1. Boss 全息体两侧射出**两条血红色锁链**（粗 8px，带链节纹理），呈对称弧线扑向目标卡，0.5s。
2. 锁链触卡瞬间，卡牌**蓝白色电路冻结**（短促闪烁 3 次，每次 0.05s）+ 屏幕轻微震动。
3. 卡牌中央浮现**红色"×"封印图标**（120×120px），从远到近砸下，伴随重音。
4. 锁链缠绕收紧 0.5s 后定格在卡上。
5. 总时长 **1.5s**。

**最终状态**：锁链 + 红 × 封印淡出（视觉痕迹保留极短），等下回合开局再"重新落下"持续标记。

### 1.3 seize（夺取）— 恐怖感

**演出**：
1. 目标卡中央先出现**黑色裂缝**（从中线向上下撕开，发紫光），0.4s。
2. 裂缝撕至边缘，整张卡开始向 Boss 方向**真空吸力扭曲**（拉伸+轻微旋转），0.6s。
3. 卡牌**碎片崩解**（沿裂缝分成 8–12 个多边形碎片），向 Boss 飞去同时缩小，0.6s。
4. 期间屏幕短暂**色差抖动**（红/绿通道分离 4px，0.3s）+ 重低音 + 强度震动 0.4s。
5. 碎片在 Boss 全息体处汇成一张红色卡轮廓，被吸入 Boss 牌库图标（屏幕右上）。
6. 总时长 **2.0s**。

**最终状态**：玩家手牌位置出现一道短暂的**黑色裂缝剪影**（持续 0.5s 后淡出），下回合应用时此剪影会重新出现在弃牌区上方。

---

## 2. 阶段二：下回合手牌持续状态（应用后）

### 2.1 peek 持续标记

- 卡牌**左上角**显示 24×24 青色眼睛图标（半透明 0.7）。
- 卡牌边缘有**呼吸式扫描线光晕**（从上到下循环，2s 一周期），暗示"信息持续被监视"。
- 不影响选牌、点击、拖动 — 只是信息泄露。
- 玩家打出该牌后，标记随消费。

### 2.2 disrupt 持续标记（关键）

- 整张牌**灰度化**（饱和度 0.3，亮度 0.7）。
- 牌面斜向覆盖**红色锁链**（从左上到右下，链节清晰，宽 12px）。
- 牌中央 60×60 红色"已封印"图标。
- `mouse_filter` 改为 IGNORE，hover 不响应。
- **强行点击反馈**：BlindSelectUI 检测到点击 disrupted 牌时，整张牌左右**抖动**（±8px，3 次，0.3s 总）+ 右上角弹出红色 toast"⛓ 已封印 — 本回合不可使用"。
- 该回合 BLIND 结束后自动解锁（变回正常状态）。

### 2.3 seize 持续痕迹

- 玩家手牌中**直接消失**（牌已被永久夺走）。
- **弃牌区图标上方**保留一个**黑色裂缝剪影**（半透明 0.5）+ 旁边小数字"+1 失落"，持续 1 整回合后淡出。
- 战斗结束后的复盘界面（如有）应单独展示"被 Boss 夺走的卡：[列表]"。

---

## 3. 音/震动反馈

| 效果 | 音色 | 强度 | 震动 |
|------|------|------|------|
| peek | 低频脉冲扫描音（70Hz 正弦 → 200Hz 滑频） | 弱 | 极轻（0.05 振幅, 0.1s）|
| disrupt | 金属锁链碰撞声 + 短促电流爆响 | 中 | 中（0.15, 0.25s）|
| seize | 低吼撕裂 + 真空吸气 + 玻璃碎裂三层叠 | 强 | 强（0.3, 0.4s + 色差抖动）|

> 音频文件名建议（待 audio-director 提供资产）：`fx_peek_scan.ogg` / `fx_disrupt_chains.ogg` / `fx_seize_rip.ogg`

---

## 4. 程序员调用契约草案

### 4.1 `probe_display_ui.gd` 新增方法

```gdscript
## 播放 peek 宣告动画。返回总时长（秒），UI 据此决定下一阶段时机。
func play_peek_announcement(target_card_ui: BaseCardUI, boss_world_pos: Vector2) -> float

## 播放 disrupt 宣告动画。
func play_disrupt_announcement(target_card_ui: BaseCardUI, boss_world_pos: Vector2) -> float

## 播放 seize 宣告动画。
func play_seize_announcement(target_card_ui: BaseCardUI, boss_world_pos: Vector2) -> float

## 演出完成信号
signal announcement_finished(effect_type: String, card_id: String)
```

### 4.2 `base_card_ui.gd` 新增方法/状态

```gdscript
## 状态枚举扩展
enum CardVisualState { NORMAL, PEEKED, DISRUPTED, BEING_SEIZED }

## 设置被窥视持续标记（眼睛 + 扫描光晕）
func set_peeked(enabled: bool) -> void

## 设置被干扰持续标记（灰度 + 锁链 + 禁用点击）
func set_disrupted(enabled: bool) -> void

## 播放夺取销毁动画（裂缝 + 碎片 + 吸力），返回时长
func play_seize_destruction() -> float

## 提供卡牌全局中心点（供宣告动画作锚点）
func get_global_center() -> Vector2
```

### 4.3 调用时序示例

```
PROBE 阶段：
  battle.insight_effect("peek", card) emit
    → blind_clash_scene._on_insight_effect()
    → 找到对应 card_ui = hand_card_uis[card]
    → probe_display.play_peek_announcement(card_ui, boss_pos)
    → await announcement_finished
    → pending_insights_banner.show("下回合开局：Boss 将偷看 [基础攻击]")

下回合 ROUND_START：
  battle.insight_applied("peek", card) emit
    → 找到下回合的 card_ui
    → card_ui.set_peeked(true)  # 持续标记
```

---

## 5. 验收清单

- [ ] 三种宣告动画时长精确（peek 1.2s / disrupt 1.5s / seize 2.0s）
- [ ] 三色三形语言无视觉混淆
- [ ] disrupt 持续状态点击有抖动反馈
- [ ] seize 弃牌区裂缝剪影正确出现并淡出
- [ ] 屏幕色差/震动只在 seize 触发，避免疲劳
- [ ] PendingInsightsBanner 文案与设计稿一致
- [ ] 音频钩子接口预留（即使资产缺失也能跑）
