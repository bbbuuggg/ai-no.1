class_name MockLLMProvider
extends LLMProviderBase
## 离线测试用 Provider —— 返回固定/伪随机的合法 JSON
##
## 用法：
##   1. user://llm_config.cfg → [provider] active = "mock"
##   2. 或者 debug.force_rule_ai = false 但无网络
##
## 行为：模拟 0.8s 延迟（接近真实 LLM），随机选 1-3 张牌，输出合法 JSON

var _delay_sec: float = 0.8


func get_provider_name() -> String:
	return "mock"


func is_configured() -> bool:
	return true  # mock 总是可用


func request_chat(messages: Array, _json_mode: bool = true) -> Dictionary:
	# 模拟延迟
	await Engine.get_main_loop().create_timer(_delay_sec).timeout

	# 从 user message 中粗略解析"可用牌"
	var hand_ids: Array = []
	var energy: int = 3
	for msg in messages:
		if not msg is Dictionary:
			continue
		if String(msg.get("role", "")) != "user":
			continue
		var content := String(msg.get("content", ""))
		# 抓 own_hand 与 own_energy
		var hand_match := RegEx.new()
		hand_match.compile("\"own_hand\"\\s*:\\s*\\[([^\\]]*)\\]")
		var m := hand_match.search(content)
		if m != null:
			var ids_str := m.get_string(1)
			for raw in ids_str.split(","):
				var s := raw.strip_edges().trim_prefix("\"").trim_suffix("\"")
				if s.length() > 0:
					hand_ids.append(s)
		var energy_match := RegEx.new()
		energy_match.compile("\"own_energy\"\\s*:\\s*(\\d+)")
		var em := energy_match.search(content)
		if em != null:
			energy = int(em.get_string(1))

	# 构造一个合法的 action_sequence（随机 1-2 张）
	var picks: Array = []
	if not hand_ids.is_empty():
		var pick_count: int = mini(hand_ids.size(), randi_range(1, 2))
		hand_ids.shuffle()
		for i in range(pick_count):
			picks.append({"action": "play_card", "card_id": hand_ids[i]})

	var fake_response := {
		"action_sequence": picks,
		"reasoning": "[MOCK] 随机选了 %d 张牌（能量预算 %d）" % [picks.size(), energy],
	}
	return {
		"ok": true,
		"content": JSON.stringify(fake_response),
		"error": "",
		"raw": null,
	}
