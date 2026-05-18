#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LLM 元素克制 + 战术决策综合测试套件 — 直接调 DeepSeek API

用法:
  python tests/llm_element_check.py
  python tests/llm_element_check.py --quick     # 只跑基础 9 组
  python tests/llm_element_check.py --no-save   # 不写入历史日志
  python tests/llm_element_check.py --runs 3    # 同一组 case 跑 3 次取多数

输出:
  tests/results/run_YYYYMMDD_HHMMSS/
    ├─ summary.md       — 汇总（人类可读）
    ├─ summary.json     — 汇总（机器可读）
    ├─ system_prompt.txt — 本次用的 prompt（便于追溯）
    └─ cases/<test_name>.json — 每个 case 的 perception + LLM raw 响应

测试矩阵：
  A. 基础对位克制（9 组：3 self_element × 3 opponent_element）
  B. Edge 2 张候选（被克 + 克对方 → 应选克对方）
  C. 数值陷阱（低伤克 vs 高伤同色 → 应选高伤同色）
  D. 后续 slot 预判（验证 LLM 是否把"克制"概念用到未锁定对位预判上）
  E. 反向幻觉诱导（玩家近回合多次出 water → LLM 是否会误推"水克木"）
  F. 留空（skip）战术（候选都被克 + 对位威胁低 → 应选 skip 而非硬出）
  G. 能量预算保留（slot 1 候选高费爆预算 → 应选低费）

依赖: requests
"""

import argparse
import json
import os
import re
import sys
import time
from configparser import ConfigParser
from datetime import datetime
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
CONFIG_PATH = ROOT / "config" / "llm_config.dev.cfg"
SCRIPT_PATH = ROOT / "scripts" / "ai" / "decision" / "llm_boss_ai.gd"
RESULTS_ROOT = ROOT / "tests" / "results"


# ============================================================
# 配置加载 + Prompt 提取
# ============================================================

def load_config():
    cp = ConfigParser()
    cp.read_string(
        "\n".join(
            line for line in CONFIG_PATH.read_text(encoding="utf-8").splitlines()
            if not line.strip().startswith(";")
        )
    )
    return {
        "api_key": cp["deepseek"]["api_key"].strip().strip('"'),
        "base_url": cp["deepseek"]["base_url"].strip().strip('"'),
        "model": cp["deepseek"]["model"].strip().strip('"'),
    }


def extract_system_prompt():
    text = SCRIPT_PATH.read_text(encoding="utf-8")
    m = re.search(
        r'const\s+SYSTEM_PROMPT_BP_SLOT\s*:?=\s*"""(.+?)"""',
        text,
        flags=re.DOTALL,
    )
    if not m:
        raise RuntimeError("未找到 SYSTEM_PROMPT_BP_SLOT 常量")
    return m.group(1).strip()


# ============================================================
# 元素克制查表
# ============================================================

ELEMENTS = ["fire", "water", "wood"]
COUNTERS = {"fire": "wood", "wood": "water", "water": "fire"}     # X 克 COUNTERS[X]
COUNTER_OF = {v: k for k, v in COUNTERS.items()}                  # 克 X 的元素 = COUNTER_OF[X]


# ============================================================
# Perception 构造工具
# ============================================================

def make_card(idx, cid, name, element, polarity="dark", cost=1, dmg=5,
              armor=0, heal=0, type_="atk",
              energy_after=5, slots_left_after=3, affordable=True, picked=False):
    """构造单张候选牌"""
    if picked:
        return {"index": idx, "picked": True}
    return {
        "index": idx, "id": cid, "name": name, "type": type_,
        "element": element, "polarity": polarity,
        "cost": cost, "dmg": dmg, "armor": armor, "heal": heal,
        "energy_after_if_pick": energy_after,
        "slots_left_after": slots_left_after,
        "affordable_for_remaining": affordable,
    }


def make_picks(picks_data):
    """
    构造 picks 数组（4 个 slot）
    picks_data: [(slot, locked_element_or_None), ...]
    """
    arr = []
    for slot in range(1, 5):
        match = next((p for p in picks_data if p[0] == slot), None)
        if match and match[1]:
            elem = match[1]
            arr.append({
                "slot": slot, "locked": True,
                "id": f"p_locked_{slot}", "name": f"玩家slot{slot}",
                "type": "atk", "element": elem, "polarity": "light",
                "cost": 1, "dmg": 5,
            })
        else:
            arr.append({"slot": slot, "locked": False})
    return arr


def base_perception(self_candidates, player_candidates, player_picks_data,
                    current_slot=0, slot_leader="boss", energy=6,
                    history=None, opponent_threat=5, base_energy=None):
    """
    基础 perception 模板
    @param current_slot: 0~3 (LLM 在为哪个 slot 决策)
    @param player_picks_data: [(slot_num, element_or_None), ...] 已锁定的玩家 picks
    @param base_energy: 当前关卡的 base_energy（v0.8.3 膨胀），默认等于 energy（保持向后兼容）
    """
    ppicks = make_picks(player_picks_data or [])
    cur_slot_pick = next(
        (p for p in ppicks if p["slot"] == current_slot + 1 and p["locked"]),
        None,
    )

    matchup = {
        "slot": current_slot + 1,
        "opponent_locked": cur_slot_pick is not None,
    }
    if cur_slot_pick:
        matchup.update({
            "opponent_element": cur_slot_pick["element"],
            "opponent_polarity": cur_slot_pick["polarity"],
            "opponent_id": cur_slot_pick["id"],
            "opponent_name": cur_slot_pick["name"],
            "note": f"你的 slot {current_slot + 1} 只与对手的 slot {current_slot + 1} 对位结算",
        })
    else:
        matchup["note"] = f"对手 slot{current_slot + 1} 尚未锁定"

    slots_left = 4 - current_slot

    # v0.8.3：给每张候选注入 vs_opponent_multiplier / vs_opponent_label
    # 模拟 perception_builder._inject_vs_opponent_multiplier 行为
    _COUNTER_MAP = {
        "fire":  {"fire": 1.0, "water": 0.5, "wood": 1.5},
        "water": {"fire": 1.5, "water": 1.0, "wood": 0.5},
        "wood":  {"fire": 0.5, "water": 1.5, "wood": 1.0},
    }
    if matchup.get("opponent_locked"):
        opp_e = matchup.get("opponent_element", "none")
        for c in self_candidates:
            if c.get("picked"):
                continue
            self_e = c.get("element", "none")
            if self_e == "none" or opp_e == "none":
                c["vs_opponent_element"] = opp_e
                c["vs_opponent_multiplier"] = 1.0
                c["vs_opponent_label"] = "中性（无元素）"
                continue
            mult = _COUNTER_MAP.get(self_e, {}).get(opp_e, 1.0)
            c["vs_opponent_element"] = opp_e
            c["vs_opponent_multiplier"] = mult
            c["vs_opponent_label"] = (
                "你克 ×1.5" if mult == 1.5
                else "你被克 ×0.5" if mult == 0.5
                else "同色 ×1.0"
            )
    else:
        for c in self_candidates:
            if c.get("picked"):
                continue
            c["vs_opponent_element"] = "none"
            c["vs_opponent_multiplier"] = None
            c["vs_opponent_label"] = "对位未锁"

    return {
        "mode": "bp_slot_pick",
        "self": {"hp": 25, "max_hp": 25, "armor": 0, "energy": energy,
                 "base_energy": base_energy if base_energy is not None else energy},
        "self_candidates": self_candidates,
        "self_picks": [
            {"slot": s, "locked": False} for s in range(1, 5)
        ],
        "player": {"hp": 25, "max_hp": 25, "armor": 0, "energy": energy, "hand_count": 4},
        "player_candidates": player_candidates,
        "player_picks": ppicks,
        "current_slot_matchup": matchup,
        "current_slot": current_slot,
        "current_slot_human": current_slot + 1,
        "slot_leader": slot_leader,
        "slot_leader_is_self": slot_leader == "boss",
        "first_picker": "boss",
        "slots_total": 4,
        "slots_left_including_current": slots_left,
        "energy_remaining": energy,
        "avg_energy_budget_per_slot": max(energy // max(slots_left, 1), 1),
        "skip_is_legal": True,
        "opponent_locked_threat": opponent_threat,
        "rule_ai_suggestion": {"cards": [], "note": "无推荐"},
        "rules_summary": "克制链单向闭环：火→木→水→火(火克木/木克水/水克火)→命中×1.5被克×0.5同元素中立;⚠反向必错:不存在'水克木/木克火/火克水'",
        "history": history or [],
        "round": 1,
    }


# ============================================================
# 测试用例工厂
# ============================================================

def case_basic(opp_element):
    """A. 基础：候选含 3 元素，对位玩家 X → 应选克 X 的元素"""
    expected = COUNTER_OF[opp_element]
    cands = [
        make_card(0, "b_test_fire",  "测试火",  "fire",  cost=1, dmg=5),
        make_card(1, "b_test_water", "测试水",  "water", cost=1, dmg=5),
        make_card(2, "b_test_wood",  "测试木",  "wood",  cost=1, dmg=5),
    ]
    pcands = [
        make_card(0, "p_lock", "玩家锁定牌", opp_element, polarity="light", dmg=5),
    ]
    perc = base_perception(cands, pcands, [(1, opp_element)], current_slot=0)
    perc["rule_ai_suggestion"]["cards"] = [
        {"id": f"b_test_{expected}", "element": expected,
         "note": "规则 AI 推荐克制对手元素"}
    ]
    return {
        "name": f"A_基础_对手{opp_element}",
        "expected": f"b_test_{expected}",
        "expected_alt": [],
        "scenario": f"玩家 slot1 锁定 {opp_element}，候选 3 张元素齐全，应选克制色 {expected}",
        "perception": perc,
    }


def case_edge_2cards(opp_element):
    """B. 候选只剩 2 张（被克 + 克对方）→ 必选克对方"""
    expected = COUNTER_OF[opp_element]
    countered = COUNTERS[opp_element]
    cands = [
        {"index": 0, "picked": True},
        make_card(1, f"b_bad_{countered}", f"被克_{countered}",
                  countered, cost=1, dmg=6),
        make_card(2, f"b_good_{expected}", f"克_{expected}",
                  expected, cost=1, dmg=5),
        {"index": 3, "picked": True},
    ]
    pcands = [make_card(0, "p_lock", "玩家锁定牌", opp_element,
                        polarity="light", dmg=5)]
    perc = base_perception(cands, pcands, [(1, opp_element)], current_slot=0)
    return {
        "name": f"B_Edge2张_对手{opp_element}",
        "expected": f"b_good_{expected}",
        "expected_alt": [],
        "scenario": f"候选只剩被克牌+克制牌，必选克制 {expected}",
        "perception": perc,
    }


def case_numeric_trap(opp_element):
    """C. 数值陷阱：低伤克 vs 高伤同色（应选高伤同色，因为最后 slot 没必要留）"""
    expected_counter = COUNTER_OF[opp_element]
    cands = [
        make_card(0, f"b_low_{expected_counter}",
                  f"低伤克_{expected_counter}",
                  expected_counter, cost=1, dmg=4),
        make_card(1, "b_high_same", f"高伤同色_{opp_element}",
                  opp_element, cost=1, dmg=10),
    ]
    pcands = [make_card(0, "p_lock", "玩家锁定牌", opp_element,
                        polarity="light", dmg=5)]
    # 注意：放在 current_slot=3（最后一个 slot），明确告诉 LLM "没有后续 slot 可留"
    perc = base_perception(cands, pcands, [(4, opp_element)], current_slot=3)
    return {
        "name": f"C_数值陷阱_对手{opp_element}",
        "expected": "b_high_same",
        "expected_alt": [],
        "scenario": f"末 slot 数值陷阱：低伤克 4×1.5=6  vs  高伤同色 10×1.0=10，应选高伤同色",
        "perception": perc,
    }


def case_predict_future_slot(opp_element):
    """
    D. 后续 slot 预判：当前 slot1 对手未锁，但 player_candidates 中有 opp_element。
    LLM 可以选 克制色（直接克）或 同色（反预判博弈）—— 两者都合理
    通过条件：选了 克 opp 或 同 opp 的牌（不选第三色被克牌）
    """
    cands = [
        make_card(0, "b_test_fire",  "测试火",  "fire",  cost=1, dmg=5),
        make_card(1, "b_test_water", "测试水",  "water", cost=1, dmg=5),
        make_card(2, "b_test_wood",  "测试木",  "wood",  cost=1, dmg=5),
    ]
    pcands = [
        make_card(i, f"p_{opp_element}_{i}", f"玩家{opp_element}_{i}",
                  opp_element, polarity="light", dmg=5)
        for i in range(4)
    ]
    perc = base_perception(cands, pcands, [], current_slot=0)
    counter = COUNTER_OF[opp_element]
    countered = COUNTERS[opp_element]  # 这个是被对方克的，绝不该选
    return {
        "name": f"D_预判后续_对手未锁但候选全{opp_element}",
        "expected": f"b_test_{counter}",   # 主期望：克对方
        "expected_alt": [f"b_test_{opp_element}"],  # 也可：同色反预判
        "scenario": f"对位 slot1 未锁，玩家候选全 {opp_element}（确定性博弈）→ 应选克 {counter} 或同色 {opp_element}（反预判）；不应选 {countered}（被克）",
        "perception": perc,
    }


def case_reverse_hallucination(opp_element):
    """
    E. 反向幻觉诱导：history 中写"玩家近 2 回合连出 X"
    LLM 应推断"玩家牌库 X 减少 → 后续可能出非 X"，但不应误认为"X 克 Y"反向
    无强期望，看 reasoning 文本
    """
    cands = [
        make_card(0, "b_test_fire",  "测试火",  "fire",  cost=1, dmg=5),
        make_card(1, "b_test_water", "测试水",  "water", cost=1, dmg=5),
        make_card(2, "b_test_wood",  "测试木",  "wood",  cost=1, dmg=5),
    ]
    pcands = [
        make_card(i, f"p_unknown_{i}", f"玩家_{i}",
                  ELEMENTS[i % 3], polarity="light", dmg=5)
        for i in range(4)
    ]
    perc = base_perception(cands, pcands, [], current_slot=0,
                           history=[{"summary": f"玩家近 2 回合多次出 {opp_element}"}])
    return {
        "name": f"E_反向幻觉_玩家近期出{opp_element}",
        "expected": None,  # 无强期望，只看 reasoning 不出错即可
        "expected_alt": [],
        "scenario": f"历史显示玩家近 2 回合多次出 {opp_element}，LLM 不应误推克制方向",
        "perception": perc,
        "check_reasoning": True,
    }


def case_skip_tactic():
    """
    F. 留空战术：候选都对当前对位无克制 + 都被克 + 高费 + 对位威胁低 → 应选 skip
    构造：对位玩家 fire (低威胁 dmg=3), 候选 [wood cost=2 被克, wood cost=3 被克]
    """
    cands = [
        make_card(0, "b_wood_a", "木A", "wood", cost=2, dmg=4,
                  energy_after=4, slots_left_after=3, affordable=True),
        make_card(1, "b_wood_b", "木B", "wood", cost=3, dmg=6,
                  energy_after=3, slots_left_after=3, affordable=False),  # 爆预算
    ]
    pcands = [
        make_card(0, "p_lock", "玩家小火", "fire",
                  polarity="light", cost=1, dmg=3),  # 低威胁
    ]
    perc = base_perception(cands, pcands, [(1, "fire")], current_slot=0,
                           opponent_threat=3)
    return {
        "name": "F_留空战术_候选全被克且对位威胁低",
        "expected": "skip",
        "expected_alt": [],
        "scenario": "候选 2 张木被 fire 克 ×0.5 + 1 张爆预算，对位 fire 威胁仅 3 → 应主动 skip",
        "perception": perc,
    }


def case_energy_budget(opp_element):
    """
    G. 能量预算保留：slot1 候选有高费（爆预算）+ 低费克制
    应选低费，而非高费（高费选了后面 slot 没能量）
    """
    expected = COUNTER_OF[opp_element]
    cands = [
        make_card(0, "b_high_cost", "高费爆预算",
                  expected, cost=4, dmg=10,
                  energy_after=2, slots_left_after=3, affordable=False),  # 4 → 还剩 2 给 3slot
        make_card(1, "b_low_cost", "低费克制",
                  expected, cost=1, dmg=5,
                  energy_after=5, slots_left_after=3, affordable=True),
    ]
    pcands = [make_card(0, "p_lock", "玩家锁定牌", opp_element,
                        polarity="light", dmg=5)]
    perc = base_perception(cands, pcands, [(1, opp_element)], current_slot=0,
                           opponent_threat=5)
    return {
        "name": f"G_能量预算_对手{opp_element}",
        "expected": "b_low_cost",
        "expected_alt": [],
        "scenario": f"slot1 选 4费爆预算后剩 2 能量给 3slot → 应选 1费克制保节奏",
        "perception": perc,
    }


def case_inflated_energy(round_label, base_energy):
    """
    H. v0.8.3 膨胀能量场景：base_energy=7/8/10 时 LLM 是否正确读 self.base_energy
    场景：slot1 候选有 3费高伤克 + 1费克 + 2费克，对位玩家高威胁
        在 base_energy=8 时玩家可以梭哈 3 费，预期选 3费克制（不再是 R1 的"低费保节奏"）
    """
    cands = [
        make_card(0, "b_3cost_counter", "3费高伤克",
                  "water", cost=3, dmg=11,
                  energy_after=base_energy - 3,
                  slots_left_after=3,
                  affordable=(base_energy - 3) >= 3),
        make_card(1, "b_1cost_counter", "1费小克",
                  "water", cost=1, dmg=4,
                  energy_after=base_energy - 1, slots_left_after=3, affordable=True),
        make_card(2, "b_2cost_neutral", "2费同色",
                  "fire", cost=2, dmg=7,
                  energy_after=base_energy - 2, slots_left_after=3, affordable=True),
    ]
    pcands = [make_card(0, "p_lock", "玩家fire核心", "fire",
                        polarity="dark", dmg=8)]
    perc = base_perception(cands, pcands, [(1, "fire")], current_slot=0,
                           energy=base_energy, base_energy=base_energy,
                           opponent_threat=8)  # 高威胁迫使必须出克
    # 期望：base_energy>=6 都能负担 3 费且仍留 5 能量给 3 slot 平均 1.67 费 → 选 3 费克
    # 但若 base_energy=6，3费选完只剩 3 给 3 slot 平均 1 → 仍能选 3 费克（边缘）
    return {
        "name": f"H_膨胀能量_{round_label}_base{base_energy}",
        "expected": "b_3cost_counter",
        "expected_alt": ["b_1cost_counter"],  # 1费克也合理（保守）
        "scenario": f"base_energy={base_energy}（{round_label}），玩家锁高威胁fire；候选 3 费 water 强克 / 1 费 water 弱克 / 2 费 fire 中性。LLM 应读 self.base_energy 而非假设 6，并优先选克制色",
        "perception": perc,
    }


def build_test_suite(quick=False):
    """构造完整测试套件"""
    tests = []

    # A. 基础三组
    for opp in ELEMENTS:
        tests.append(case_basic(opp))
    if quick:
        return tests

    # B. Edge 2 张
    for opp in ELEMENTS:
        tests.append(case_edge_2cards(opp))
    # C. 数值陷阱（末 slot）
    for opp in ELEMENTS:
        tests.append(case_numeric_trap(opp))
    # D. 后续 slot 预判
    for opp in ELEMENTS:
        tests.append(case_predict_future_slot(opp))
    # E. 反向幻觉
    for opp in ELEMENTS:
        tests.append(case_reverse_hallucination(opp))
    # F. 留空战术（单测）
    tests.append(case_skip_tactic())
    # G. 能量预算
    for opp in ELEMENTS:
        tests.append(case_energy_budget(opp))

    # H. v0.8.3 膨胀能量场景（验证 LLM 读 self.base_energy 而非假设 6）
    tests.append(case_inflated_energy("R3", 7))
    tests.append(case_inflated_energy("R4", 8))
    tests.append(case_inflated_energy("R5", 10))

    return tests


# ============================================================
# Reasoning 文本检查（检测错误克制描述）
# ============================================================
# 正则要求："X 克 Y" 紧邻（中间最多 1 个字符如空格或顿号），避免误匹配"留 water/wood 给后续"等

WRONG_PATTERNS = [
    (r"水克木|水[ ]?克[ ]?木|water[\s/]{0,2}counters?[\s/]{0,2}wood|water[\s]?>[\s]?wood",
     "❌ 水克木（错）"),
    (r"木克火|木[ ]?克[ ]?火|wood[\s/]{0,2}counters?[\s/]{0,2}fire|wood[\s]?>[\s]?fire",
     "❌ 木克火（错）"),
    (r"火克水|火[ ]?克[ ]?水|fire[\s/]{0,2}counters?[\s/]{0,2}water|fire[\s]?>[\s]?water",
     "❌ 火克水（错）"),
]
RIGHT_PATTERNS = [
    (r"水克火|水[ ]?克[ ]?火|water[\s/]{0,2}counters?[\s/]{0,2}fire|water[\s]?>[\s]?fire",
     "✓ 水克火"),
    (r"木克水|木[ ]?克[ ]?水|wood[\s/]{0,2}counters?[\s/]{0,2}water|wood[\s]?>[\s]?water",
     "✓ 木克水"),
    (r"火克木|火[ ]?克[ ]?木|fire[\s/]{0,2}counters?[\s/]{0,2}wood|fire[\s]?>[\s]?wood",
     "✓ 火克木"),
]


def check_reasoning_text(reasoning: str) -> dict:
    """检查 reasoning 中是否出现错误克制描述"""
    wrong = []
    right = []
    for pat, label in WRONG_PATTERNS:
        if re.search(pat, reasoning, re.IGNORECASE):
            wrong.append(label)
    for pat, label in RIGHT_PATTERNS:
        if re.search(pat, reasoning, re.IGNORECASE):
            right.append(label)
    return {"wrong_patterns": wrong, "right_patterns": right}


# ============================================================
# DeepSeek API
# ============================================================

def call_deepseek(api_key, base_url, model, system_prompt, user_payload, retries=2):
    url = f"{base_url}/chat/completions"
    headers = {"Authorization": f"Bearer {api_key}",
               "Content-Type": "application/json"}
    payload = {
        "model": model,
        "temperature": 0.0,
        "max_tokens": 800,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)},
        ],
    }
    for attempt in range(retries + 1):
        try:
            r = requests.post(url, headers=headers, json=payload, timeout=60)
            if r.status_code != 200:
                print(f"  [HTTP {r.status_code}] {r.text[:200]}")
                if attempt < retries:
                    time.sleep(2)
                    continue
                return {"ok": False, "error": f"HTTP {r.status_code}",
                        "raw_text": r.text[:500]}
            data = r.json()
            content = data["choices"][0]["message"]["content"]
            return {"ok": True, "content": content,
                    "usage": data.get("usage", {}),
                    "raw": data}
        except Exception as e:
            print(f"  [EXC] {e}")
            if attempt < retries:
                time.sleep(2)
                continue
            return {"ok": False, "error": str(e)}


def parse_response(content):
    s = content.strip()
    s = re.sub(r"^```(?:json)?\s*", "", s)
    s = re.sub(r"\s*```$", "", s)
    try:
        return json.loads(s)
    except Exception:
        m = re.search(r"\{.*\}", s, flags=re.DOTALL)
        if m:
            try:
                return json.loads(m.group(0))
            except Exception:
                pass
        return {"_parse_error": True, "_raw": s[:500]}


# ============================================================
# 单 case 执行 + 结果记录
# ============================================================

def run_case(test, sys_prompt, cfg, runs=1):
    """跑单 case，runs > 1 时取多数票"""
    perception = test["perception"]
    expected = test["expected"]

    runs_data = []
    for run_idx in range(runs):
        resp = call_deepseek(cfg["api_key"], cfg["base_url"], cfg["model"],
                            sys_prompt, perception)
        if not resp.get("ok"):
            runs_data.append({
                "ok": False, "error": resp.get("error", "unknown"),
                "card_id": None, "reasoning": "", "usage": {},
            })
            continue
        parsed = parse_response(resp["content"])
        if parsed.get("_parse_error"):
            runs_data.append({
                "ok": False, "error": "JSON 解析失败",
                "card_id": None, "reasoning": parsed.get("_raw", ""),
                "raw_content": resp["content"], "usage": resp["usage"],
            })
            continue

        card_id = parsed.get("card_id", "")
        reasoning = parsed.get("reasoning", "")
        runs_data.append({
            "ok": True, "card_id": card_id, "reasoning": reasoning,
            "raw_content": resp["content"], "usage": resp["usage"],
            "reasoning_check": check_reasoning_text(reasoning),
        })
        if runs > 1 and run_idx < runs - 1:
            time.sleep(0.8)

    # 多数票
    valid_picks = [r["card_id"] for r in runs_data if r["ok"]]
    if not valid_picks:
        majority_pick = None
    else:
        from collections import Counter
        cnt = Counter(valid_picks)
        majority_pick, _ = cnt.most_common(1)[0]

    # 通过判定
    if test.get("check_reasoning"):
        # E 类：只要 reasoning 不出错就通过
        passed = all(
            not r.get("reasoning_check", {}).get("wrong_patterns")
            for r in runs_data if r["ok"]
        )
    elif expected is None:
        passed = bool(majority_pick)
    else:
        passed = majority_pick == expected or (
            test.get("expected_alt") and majority_pick in test["expected_alt"]
        )

    return {
        "test": test,
        "runs": runs_data,
        "majority_pick": majority_pick,
        "passed": passed,
    }


# ============================================================
# 主流程 + 结果输出
# ============================================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true",
                       help="只跑基础 9 组")
    parser.add_argument("--no-save", action="store_true",
                       help="不保存到 tests/results/")
    parser.add_argument("--runs", type=int, default=1,
                       help="同一 case 跑几次（默认 1，建议 3 取多数）")
    args = parser.parse_args()

    print("=" * 70)
    print("LLM 元素克制 + 战术决策综合测试")
    print("=" * 70)

    cfg = load_config()
    if not cfg["api_key"]:
        print("❌ DeepSeek API key 未配置")
        return 1
    print(f"Provider: {cfg['model']} @ {cfg['base_url']}")

    sys_prompt = extract_system_prompt()
    print(f"SYSTEM_PROMPT_BP_SLOT: {len(sys_prompt)} 字符\n")

    tests = build_test_suite(quick=args.quick)
    print(f"测试用例: {len(tests)} 个，每个 case 跑 {args.runs} 次\n")

    # 准备结果目录
    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = RESULTS_ROOT / f"run_{run_id}"
    if not args.no_save:
        out_dir.mkdir(parents=True, exist_ok=True)
        (out_dir / "cases").mkdir(exist_ok=True)
        (out_dir / "system_prompt.txt").write_text(sys_prompt, encoding="utf-8")
        print(f"结果目录: {out_dir.relative_to(ROOT)}\n")

    results = []
    for i, test in enumerate(tests, 1):
        print(f"\n[{i:02d}/{len(tests)}] {test['name']}")
        print(f"     场景: {test['scenario']}")
        print(f"     期望: {test['expected'] if test['expected'] else '(看 reasoning)'}")

        result = run_case(test, sys_prompt, cfg, runs=args.runs)
        results.append(result)

        # 打印
        if args.runs == 1:
            r = result["runs"][0]
            if r["ok"]:
                print(f"     LLM 选: {r['card_id']}")
                print(f"     reasoning: {r['reasoning']}")
                if r.get("reasoning_check", {}).get("wrong_patterns"):
                    for w in r["reasoning_check"]["wrong_patterns"]:
                        print(f"     ⚠ reasoning 出现错误描述: {w}")
            else:
                print(f"     ❌ API 失败: {r.get('error')}")
        else:
            picks = [r["card_id"] for r in result["runs"] if r["ok"]]
            print(f"     {args.runs} 次 picks: {picks}")
            print(f"     多数票: {result['majority_pick']}")

        print(f"     {'✅ PASS' if result['passed'] else '❌ FAIL'}")

        # 保存 case
        if not args.no_save:
            case_data = {
                "name": test["name"],
                "scenario": test["scenario"],
                "expected": test["expected"],
                "perception": test["perception"],
                "runs": result["runs"],
                "majority_pick": result["majority_pick"],
                "passed": result["passed"],
            }
            (out_dir / "cases" / f"{test['name']}.json").write_text(
                json.dumps(case_data, ensure_ascii=False, indent=2),
                encoding="utf-8",
            )

        time.sleep(1.0)

    # 汇总
    print("\n" + "=" * 70)
    print("=== 汇总 ===")
    pass_n = sum(1 for r in results if r["passed"])
    print(f"通过: {pass_n}/{len(results)}")

    # 按类型分组
    by_prefix = {}
    for r in results:
        prefix = r["test"]["name"].split("_")[0]
        by_prefix.setdefault(prefix, []).append(r)
    for prefix in sorted(by_prefix):
        rs = by_prefix[prefix]
        pn = sum(1 for r in rs if r["passed"])
        print(f"  {prefix}: {pn}/{len(rs)}")

    # 详细
    print("\n详细：")
    for r in results:
        symbol = "✅" if r["passed"] else "❌"
        print(f"  {symbol} {r['test']['name']:50s} → {r['majority_pick']}")

    # 保存 summary
    if not args.no_save:
        summary = {
            "run_id": run_id,
            "timestamp": datetime.now().isoformat(),
            "model": cfg["model"],
            "total": len(results),
            "passed": pass_n,
            "runs_per_case": args.runs,
            "by_category": {
                p: {"passed": sum(1 for r in rs if r["passed"]), "total": len(rs)}
                for p, rs in by_prefix.items()
            },
            "details": [
                {
                    "name": r["test"]["name"],
                    "scenario": r["test"]["scenario"],
                    "expected": r["test"]["expected"],
                    "majority_pick": r["majority_pick"],
                    "passed": r["passed"],
                }
                for r in results
            ],
        }
        (out_dir / "summary.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

        # 写 markdown 汇总
        md = []
        md.append(f"# LLM 元素克制测试 — {run_id}\n")
        md.append(f"- 模型: `{cfg['model']}`")
        md.append(f"- 总通过率: **{pass_n}/{len(results)}** ({pass_n*100//len(results)}%)")
        md.append(f"- 每 case 跑 {args.runs} 次\n")
        md.append("## 分类通过率\n")
        md.append("| 类别 | 通过 | 总计 | 通过率 |")
        md.append("|---|---|---|---|")
        for p, rs in sorted(by_prefix.items()):
            pn = sum(1 for r in rs if r["passed"])
            md.append(f"| {p} | {pn} | {len(rs)} | {pn*100//len(rs)}% |")

        md.append("\n## 详细结果\n")
        md.append("| 状态 | 用例 | 期望 | 实际 | 场景 |")
        md.append("|---|---|---|---|---|")
        for r in results:
            sym = "✅" if r["passed"] else "❌"
            md.append(
                f"| {sym} | {r['test']['name']} | "
                f"{r['test']['expected'] or '(看reasoning)'} | "
                f"{r['majority_pick']} | {r['test']['scenario'][:60]} |"
            )

        md.append("\n## Reasoning 检查（仅类型 E）\n")
        for r in results:
            if r["test"].get("check_reasoning"):
                md.append(f"### {r['test']['name']}")
                for run in r["runs"]:
                    if run.get("ok"):
                        wrong = run.get("reasoning_check", {}).get("wrong_patterns", [])
                        right = run.get("reasoning_check", {}).get("right_patterns", [])
                        md.append(f"- reasoning: `{run['reasoning']}`")
                        if wrong:
                            md.append(f"  - ⚠ 错误描述: {wrong}")
                        if right:
                            md.append(f"  - ✓ 正确描述: {right}")
                md.append("")

        md.append("\n## 失败用例的 LLM 推理\n")
        for r in results:
            if r["passed"]:
                continue
            md.append(f"### ❌ {r['test']['name']}")
            md.append(f"- 场景: {r['test']['scenario']}")
            md.append(f"- 期望: `{r['test']['expected']}`")
            md.append(f"- 实际: `{r['majority_pick']}`")
            for ridx, run in enumerate(r["runs"], 1):
                md.append(f"  - Run {ridx} reasoning: `{run.get('reasoning', '')}`")
            md.append("")

        (out_dir / "summary.md").write_text("\n".join(md), encoding="utf-8")
        print(f"\n报告已保存: {out_dir.relative_to(ROOT)}/summary.md")

    return 0 if pass_n == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
