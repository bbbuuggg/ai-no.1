# LLM 元素克制测试 — 20260518_191310

- 模型: `deepseek-chat`
- 总通过率: **20/22** (90%)
- 每 case 跑 1 次

## 分类通过率

| 类别 | 通过 | 总计 | 通过率 |
|---|---|---|---|
| A | 3 | 3 | 100% |
| B | 3 | 3 | 100% |
| C | 2 | 3 | 66% |
| D | 3 | 3 | 100% |
| E | 3 | 3 | 100% |
| F | 0 | 1 | 0% |
| G | 3 | 3 | 100% |
| H | 3 | 3 | 100% |

## 详细结果

| 状态 | 用例 | 期望 | 实际 | 场景 |
|---|---|---|---|---|
| ✅ | A_基础_对手fire | b_test_water | b_test_water | 玩家 slot1 锁定 fire，候选 3 张元素齐全，应选克制色 water |
| ✅ | A_基础_对手water | b_test_wood | b_test_wood | 玩家 slot1 锁定 water，候选 3 张元素齐全，应选克制色 wood |
| ✅ | A_基础_对手wood | b_test_fire | b_test_fire | 玩家 slot1 锁定 wood，候选 3 张元素齐全，应选克制色 fire |
| ✅ | B_Edge2张_对手fire | b_good_water | b_good_water | 候选只剩被克牌+克制牌，必选克制 water |
| ✅ | B_Edge2张_对手water | b_good_wood | b_good_wood | 候选只剩被克牌+克制牌，必选克制 wood |
| ✅ | B_Edge2张_对手wood | b_good_fire | b_good_fire | 候选只剩被克牌+克制牌，必选克制 fire |
| ✅ | C_数值陷阱_对手fire | b_high_same | b_high_same | 末 slot 数值陷阱：低伤克 4×1.5=6  vs  高伤同色 10×1.0=10，应选高伤同色 |
| ✅ | C_数值陷阱_对手water | b_high_same | b_high_same | 末 slot 数值陷阱：低伤克 4×1.5=6  vs  高伤同色 10×1.0=10，应选高伤同色 |
| ❌ | C_数值陷阱_对手wood | b_high_same | b_low_fire | 末 slot 数值陷阱：低伤克 4×1.5=6  vs  高伤同色 10×1.0=10，应选高伤同色 |
| ✅ | D_预判后续_对手未锁但候选全fire | b_test_water | b_test_water | 对位 slot1 未锁，玩家候选全 fire（确定性博弈）→ 应选克 water 或同色 fire（反预判）；不应选 w |
| ✅ | D_预判后续_对手未锁但候选全water | b_test_wood | b_test_wood | 对位 slot1 未锁，玩家候选全 water（确定性博弈）→ 应选克 wood 或同色 water（反预判）；不应选  |
| ✅ | D_预判后续_对手未锁但候选全wood | b_test_fire | b_test_fire | 对位 slot1 未锁，玩家候选全 wood（确定性博弈）→ 应选克 fire 或同色 wood（反预判）；不应选 wa |
| ✅ | E_反向幻觉_玩家近期出fire | (看reasoning) | b_test_water | 历史显示玩家近 2 回合多次出 fire，LLM 不应误推克制方向 |
| ✅ | E_反向幻觉_玩家近期出water | (看reasoning) | b_test_water | 历史显示玩家近 2 回合多次出 water，LLM 不应误推克制方向 |
| ✅ | E_反向幻觉_玩家近期出wood | (看reasoning) | b_test_water | 历史显示玩家近 2 回合多次出 wood，LLM 不应误推克制方向 |
| ❌ | F_留空战术_候选全被克且对位威胁低 | skip | b_wood_a | 候选 2 张木被 fire 克 ×0.5 + 1 张爆预算，对位 fire 威胁仅 3 → 应主动 skip |
| ✅ | G_能量预算_对手fire | b_low_cost | b_low_cost | slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏 |
| ✅ | G_能量预算_对手water | b_low_cost | b_low_cost | slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏 |
| ✅ | G_能量预算_对手wood | b_low_cost | b_low_cost | slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏 |
| ✅ | H_膨胀能量_R3_base7 | b_3cost_counter | b_3cost_counter | base_energy=7（R3），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克  |
| ✅ | H_膨胀能量_R4_base8 | b_3cost_counter | b_3cost_counter | base_energy=8（R4），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克  |
| ✅ | H_膨胀能量_R5_base10 | b_3cost_counter | b_3cost_counter | base_energy=10（R5），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克 |

## Reasoning 检查（仅类型 E）

### E_反向幻觉_玩家近期出fire
- reasoning: `Slot1我先出,玩家候选2火1水1木;预判玩家可能出火,我出水×1.5克火,同时留火木给后续。`

### E_反向幻觉_玩家近期出water
- reasoning: `Slot1我先出,玩家候选2火1水1木;预判玩家可能出火或水;我出水克火×1.5,留火木给后续。`
  - ✓ 正确描述: ['✓ 水克火']

### E_反向幻觉_玩家近期出wood
- reasoning: `Slot1我先出,玩家候选2火1水1木;预判玩家可能出火或木;我出水克火×1.5,留火木给后续。`
  - ✓ 正确描述: ['✓ 水克火']


## 失败用例的 LLM 推理

### ❌ C_数值陷阱_对手wood
- 场景: 末 slot 数值陷阱：低伤克 4×1.5=6  vs  高伤同色 10×1.0=10，应选高伤同色
- 期望: `b_high_same`
- 实际: `b_low_fire`
  - Run 1 reasoning: `对位slot4已锁wood;我slot4出fire克wood×1.5=6伤,高伤同色wood被克×0.5=5伤,选fire稳赢。`

### ❌ F_留空战术_候选全被克且对位威胁低
- 场景: 候选 2 张木被 fire 克 ×0.5 + 1 张爆预算，对位 fire 威胁仅 3 → 应主动 skip
- 期望: `skip`
- 实际: `b_wood_a`
  - Run 1 reasoning: `对位slot1已锁fire;我slot1出wood克fire×1.5=6伤,木B虽强但affordable=false会爆预算,选木A稳节奏。`
