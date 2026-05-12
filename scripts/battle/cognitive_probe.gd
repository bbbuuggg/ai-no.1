class_name CognitiveProbe
extends RefCounted
## 认知探针系统 — Boss猜测玩家出牌主类型

signal probe_announced(predicted_type: String)
signal probe_result(correct: bool, streak: int, total: int)
signal peek_triggered(card: CardData)  # 窥视：揭示玩家1张手牌
signal disrupt_triggered(card: CardData)  # 干扰：锁定玩家1张手牌
signal seize_triggered(card: CardData)  # 夺取：永久移除玩家1张手牌

## 洞察状态
var consecutive_hits: int = 0  # 连续猜中次数
var total_hits: int = 0  # 累计猜中次数
var current_prediction: String = ""  # 本回合预判("attack"/"defense"/"skill")
var is_jammed: bool = false  # 是否被玩家干扰（本回合猜测无效）

## 历史记录（用于猜测算法）
var player_history: Array[Dictionary] = []  # [{attack: N, defense: N, skill: N}]

## Boss性格参数
var personality_bias: Dictionary = {
	"attack": 0.33,
	"defense": 0.33,
	"skill": 0.34,
}


func setup(bias: Dictionary) -> void:
	personality_bias = bias
	consecutive_hits = 0
	total_hits = 0
	player_history.clear()


## 回合开始时Boss做出预判
func make_prediction() -> String:
	if player_history.is_empty():
		# 首回合：按性格偏好猜
		current_prediction = _weighted_random(personality_bias)
	else:
		# 基于历史分析
		var history_weight := _analyze_history()
		var final_scores := {
			"attack": history_weight.get("attack", 0.33) * 0.7 + personality_bias["attack"] * 0.3,
			"defense": history_weight.get("defense", 0.33) * 0.7 + personality_bias["defense"] * 0.3,
			"skill": history_weight.get("skill", 0.34) * 0.7 + personality_bias["skill"] * 0.3,
		}
		# 加入少量随机扰动
		for key in final_scores:
			final_scores[key] += randf_range(-0.08, 0.08)
		current_prediction = _get_max_key(final_scores)

	is_jammed = false
	probe_announced.emit(current_prediction)
	return current_prediction


## 对决结束后判定结果
func resolve(player_cards: Array[CardData]) -> Dictionary:
	# 统计玩家本回合出牌类型分布
	var type_counts := {"attack": 0, "defense": 0, "skill": 0}
	for card in player_cards:
		match card.type:
			CardData.CardType.ATTACK:
				type_counts["attack"] += 1
			CardData.CardType.DEFENSE:
				type_counts["defense"] += 1
			CardData.CardType.SKILL, CardData.CardType.PROTOCOL:
				type_counts["skill"] += 1

	# 记录历史
	player_history.append(type_counts.duplicate())

	# 找出主类型（数量最多的）
	var max_count: int = 0
	var dominant_types: Array[String] = []
	for key in type_counts:
		if type_counts[key] > max_count:
			max_count = type_counts[key]
			dominant_types = [key]
		elif type_counts[key] == max_count and max_count > 0:
			dominant_types.append(key)

	# 判定是否猜对
	var correct: bool = false
	if not is_jammed and current_prediction in dominant_types:
		correct = true

	if correct:
		consecutive_hits += 1
		total_hits += 1
	else:
		consecutive_hits = 0

	probe_result.emit(correct, consecutive_hits, total_hits)

	return {
		"correct": correct,
		"streak": consecutive_hits,
		"total": total_hits,
		"player_types": type_counts,
		"prediction": current_prediction,
	}


## 玩家消耗约束资源干扰猜测
func jam() -> void:
	is_jammed = true


## 获取当前洞察等级描述
func get_insight_level() -> String:
	if consecutive_hits >= 3:
		return "disrupt"
	elif consecutive_hits >= 2:
		return "peek"
	elif total_hits >= 5:
		return "seize"
	return "none"


## 分析历史出牌倾向
func _analyze_history() -> Dictionary:
	var total := {"attack": 0.0, "defense": 0.0, "skill": 0.0}
	# 最近3回合权重更高
	var recent_count: int = mini(player_history.size(), 3)
	var weight: float = 1.0
	for i in range(player_history.size() - 1, -1, -1):
		var entry: Dictionary = player_history[i]
		var sum: float = float(entry["attack"] + entry["defense"] + entry["skill"])
		if sum > 0:
			total["attack"] += (float(entry["attack"]) / sum) * weight
			total["defense"] += (float(entry["defense"]) / sum) * weight
			total["skill"] += (float(entry["skill"]) / sum) * weight
		weight *= 0.7  # 越早权重越低

	# 归一化
	var grand_total: float = total["attack"] + total["defense"] + total["skill"]
	if grand_total > 0:
		for key in total:
			total[key] /= grand_total
	else:
		total = {"attack": 0.33, "defense": 0.33, "skill": 0.34}
	return total


func _weighted_random(weights: Dictionary) -> String:
	var roll: float = randf()
	var cumulative: float = 0.0
	for key in weights:
		cumulative += weights[key]
		if roll <= cumulative:
			return key
	return "attack"


func _get_max_key(dict: Dictionary) -> String:
	var max_val: float = -999.0
	var max_key: String = "attack"
	for key in dict:
		if dict[key] > max_val:
			max_val = dict[key]
			max_key = key
	return max_key
