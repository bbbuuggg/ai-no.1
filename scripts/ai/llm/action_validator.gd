class_name ActionValidator
extends RefCounted
## LLM 输出 JSON 校验与静默修正
##
## 输入：LLM 返回的原始字符串（可能含 markdown code block）
## 输出：ValidationResult { ok, cards: Array[CardData], reasoning, error, was_corrected }
##
## 校验链（任何一步失败都尝试修正而非直接 fallback）：
##   1. 抽取 JSON（去 markdown wrap）
##   2. JSON.parse_string 不为 null
##   3. 必须含 action_sequence 数组
##   4. 每个 action 必须有 card_id
##   5. card_id 必须在 boss.hand 中（不在则丢弃此动作）
##   6. 总能量不超 boss.energy（超过从尾部裁剪）
##   7. 数量不超 max_picks=3（超过截断）
##   8. 校验后非空（若空则视为整体失败，由调用方走 fallback）
##
## 设计原则（game-designer 定调）：
##   - 静默修正优先 —— 玩家不应感知 AI 出错
##   - 仅"完全无 JSON"或"修正后空数组"才返回 ok=false 让调用方 fallback


class ValidationResult:
	var ok: bool = false
	var cards: Array[CardData] = []
	var reasoning: String = ""
	var error: String = ""
	var was_corrected: bool = false  # 是否经过修正（用于日志）


## 主入口
static func parse_and_validate(raw: String, boss: Combatant, max_picks: int = 3) -> ValidationResult:
	var result := ValidationResult.new()

	# 1. 抽取 JSON
	var json_str: String = LLMProviderBase.extract_json_from_text(raw)
	if json_str.is_empty():
		result.error = "无法从响应中抽取 JSON"
		return result

	# 2. 解析
	var parsed: Variant = JSON.parse_string(json_str)
	if parsed == null:
		result.error = "JSON 解析失败"
		return result
	if not parsed is Dictionary:
		result.error = "JSON 根节点非 Object"
		return result

	# 3. action_sequence 字段
	var seq_raw = parsed.get("action_sequence", null)
	if not seq_raw is Array:
		result.error = "缺少 action_sequence 数组"
		return result

	# reasoning 取出（不影响校验）
	result.reasoning = String(parsed.get("reasoning", ""))

	# 4-7. 逐个动作校验
	var hand_id_to_card: Dictionary = {}
	for c in boss.hand:
		hand_id_to_card[String(c.id)] = c

	var picked: Array[CardData] = []
	var used_energy: int = 0
	var available_energy: int = boss.energy

	for action in seq_raw:
		if picked.size() >= max_picks:
			result.was_corrected = true
			break
		if not action is Dictionary:
			result.was_corrected = true
			continue
		var card_id: String = String(action.get("card_id", ""))
		if card_id.is_empty() or not hand_id_to_card.has(card_id):
			result.was_corrected = true
			continue
		var card: CardData = hand_id_to_card[card_id]
		# 同一张牌不能被选两次（hand_id_to_card 是同一引用，picked 列表自检）
		if card in picked:
			result.was_corrected = true
			continue
		# 能量预算
		if used_energy + card.energy_cost > available_energy:
			# 0 费牌总能塞进去；非 0 费超支则放弃此牌
			if card.energy_cost > 0:
				result.was_corrected = true
				continue
		used_energy += card.energy_cost
		picked.append(card)

	# 8. 修正后非空判断
	if picked.is_empty():
		result.error = "修正后无合法牌"
		return result

	result.ok = true
	result.cards = picked
	return result
