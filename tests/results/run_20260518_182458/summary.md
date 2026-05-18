# LLM 元素克制测试 — 20260518_182458

- 模型: `deepseek-chat`
- 总通过率: **18/19** (94%)
- 每 case 跑 1 次

## 分类通过率

| 类别 | 通过 | 总计 | 通过率 |
|---|---|---|---|
| A | 3 | 3 | 100% |
| B | 3 | 3 | 100% |
| C | 3 | 3 | 100% |
| D | 3 | 3 | 100% |
| E | 3 | 3 | 100% |
| F | 0 | 1 | 0% |
| G | 3 | 3 | 100% |

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
| ✅ | C_数值陷阱_对手wood | b_high_same | b_high_same | 末 slot 数值陷阱：低伤克 4×1.5=6  vs  高伤同色 10×1.0=10，应选高伤同色 |
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

## Reasoning 检查（仅类型 E）

### E_反向幻觉_玩家近期出fire
- reasoning: `先出方slot1,玩家候选2火1水1木;预判玩家出火概率高,我出水克火×1.5=7.5伤,留火木给后续。`
  - ✓ 正确描述: ['✓ 水克火']

### E_反向幻觉_玩家近期出water
- reasoning: `先出方无对位信息;玩家候选2火1水1木,预判玩家可能出火;我出水克火×1.5,留火木给后续。`
  - ✓ 正确描述: ['✓ 水克火']

### E_反向幻觉_玩家近期出wood
- reasoning: `slot1我先出,玩家候选火水木各一;预判玩家可能出火或木;我出水平衡留火木给后续,水克火×1.5。`
  - ✓ 正确描述: ['✓ 水克火']


## 失败用例的 LLM 推理

### ❌ F_留空战术_候选全被克且对位威胁低
- 场景: 候选 2 张木被 fire 克 ×0.5 + 1 张爆预算，对位 fire 威胁仅 3 → 应主动 skip
- 期望: `skip`
- 实际: `b_wood_a`
  - Run 1 reasoning: `对位slot1已锁fire;我slot1出wood克fire×1.5,木A低费保后续节奏,木B爆预算不选。`
