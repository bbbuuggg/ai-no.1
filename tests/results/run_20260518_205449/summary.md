# LLM 元素克制测试 — 20260518_205449

- 模型: `deepseek-chat`
- 总通过率: **20/23** (86%)
- 每 case 跑 1 次

## 分类通过率

| 类别 | 通过 | 总计 | 通过率 |
|---|---|---|---|
| A | 3 | 3 | 100% |
| B | 3 | 3 | 100% |
| C | 3 | 3 | 100% |
| D | 3 | 3 | 100% |
| E | 3 | 3 | 100% |
| F | 1 | 1 | 100% |
| G | 2 | 3 | 66% |
| H | 2 | 3 | 66% |
| I | 0 | 1 | 0% |

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
| ✅ | E_反向幻觉_玩家近期出fire | (看reasoning) | b_test_fire | 历史显示玩家近 2 回合多次出 fire，LLM 不应误推克制方向 |
| ✅ | E_反向幻觉_玩家近期出water | (看reasoning) | b_test_fire | 历史显示玩家近 2 回合多次出 water，LLM 不应误推克制方向 |
| ✅ | E_反向幻觉_玩家近期出wood | (看reasoning) | b_test_water | 历史显示玩家近 2 回合多次出 wood，LLM 不应误推克制方向 |
| ✅ | F_留空战术_候选全被克且对位威胁低 | skip | skip | 候选 2 张木被 fire 克 ×0.5 + 1 张爆预算，对位 fire 威胁仅 3 → 应主动 skip |
| ✅ | G_能量预算_对手fire | b_low_cost | b_low_cost | slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏 |
| ❌ | G_能量预算_对手water | b_low_cost | b_high_cost | slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏 |
| ✅ | G_能量预算_对手wood | b_low_cost | b_low_cost | slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏 |
| ✅ | H_膨胀能量_R3_base7 | b_3cost_counter | b_3cost_counter | base_energy=7（R3），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克  |
| ❌ | H_膨胀能量_R4_base8 | b_3cost_counter | b_2cost_neutral | base_energy=8（R4），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克  |
| ✅ | H_膨胀能量_R5_base10 | b_3cost_counter | b_3cost_counter | base_energy=10（R5），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克 |
| ❌ | I_治疗有效空间_slot4掉血后 | b_heal_big | b_high_dmg | boss self.hp 显示满血 25，但 pre_slot_outlook 显示 slot 1-3 锁定后真实 HP |

## Reasoning 检查（仅类型 E）

### E_反向幻觉_玩家近期出fire
- reasoning: `玩家预判我出fire克wood;我出水fire同色打乱节奏留wood给slot4。`

### E_反向幻觉_玩家近期出water
- reasoning: `玩家预判我出水克火;我出火同色打乱节奏留水给slot2。`
  - ✓ 正确描述: ['✓ 水克火']

### E_反向幻觉_玩家近期出wood
- reasoning: `玩家候选全light无2:2威胁;我slot1先出,预判玩家可能出fire;出水克fire×1.5=8伤,留fire/wood覆盖后续。`


## 失败用例的 LLM 推理

### ❌ G_能量预算_对手water
- 场景: slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏
- 期望: `b_low_cost`
- 实际: `b_high_cost`
  - Run 1 reasoning: `对位slot1已锁water;我slot1出wood克water×1.5=15伤,低费留能量给后续slot。`

### ❌ H_膨胀能量_R4_base8
- 场景: base_energy=8（R4），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克 / 2 费 fire 中性。LLM 应读 self.base_energy 而非假设 6，并优先选克制色
- 期望: `b_3cost_counter`
- 实际: `b_2cost_neutral`
  - Run 1 reasoning: `玩家预判我出水克fire;我偏出fire同色打乱节奏留water给slot2。`

### ❌ I_治疗有效空间_slot4掉血后
- 场景: boss self.hp 显示满血 25，但 pre_slot_outlook 显示 slot 1-3 锁定后真实 HP=17，room_for_heal=8；候选治疗牌 my_effective_heal=8（不浪费），LLM 应优先选治疗牌而非纯伤
- 期望: `b_heal_big`
- 实际: `b_high_dmg`
  - Run 1 reasoning: `slot4已锁wood;我两牌都克wood×1.5;纯伤火10伤>凤凰击+8伤+8治=16总价值,但治疗已满血浪费;选纯伤火最大化伤害。`
