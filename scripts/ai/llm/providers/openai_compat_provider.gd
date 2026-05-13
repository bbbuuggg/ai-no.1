class_name OpenAICompatProvider
extends LLMProviderBase
## OpenAI 兼容协议 Provider
##
## 适用厂商（共享同一套 /chat/completions 协议）：
##   - DeepSeek    base_url = https://api.deepseek.com/v1   model = deepseek-chat
##   - OpenAI      base_url = https://api.openai.com/v1     model = gpt-4o-mini
##   - 智谱 GLM     base_url = https://open.bigmodel.cn/api/paas/v4
##   - 通义千问     base_url = https://dashscope.aliyuncs.com/compatible-mode/v1
##   - Moonshot    base_url = https://api.moonshot.cn/v1
##
## 由 LLMConfig 决定具体使用哪家。

var _http: HTTPRequest


func _init() -> void:
	_http = HTTPRequest.new()
	_http.timeout = timeout_sec


func get_provider_name() -> String:
	return "openai_compat[%s]" % model


## HTTPRequest 必须挂在场景树才能工作 —— 由 LLMBossAI 在 _ready 时设置
func attach_to(host: Node) -> void:
	if _http.get_parent() == null:
		host.add_child(_http)
	_http.timeout = timeout_sec


func request_chat(messages: Array, json_mode: bool = true) -> Dictionary:
	if not is_configured():
		return {"ok": false, "content": "", "error": "未配置 API Key/base_url/model"}
	if _http.get_parent() == null:
		return {"ok": false, "content": "", "error": "HTTPRequest 未挂载到场景树（请先调用 attach_to）"}

	# 【单一真源】max_tokens 由 LLMConfig.MAX_TOKENS_OVERRIDE 控制，此处不再做下限兜底。
	# 历史：曾用 maxi(max_tokens, 1200) 兜底防 DeepSeek 截断，
	# 但会"吃掉"上层调高 max_tokens 的意图，导致 log 里 completion_tokens 永远卡在 1200。
	# 现在统一以 LLMConfig.MAX_TOKENS_OVERRIDE 为唯一调节点。
	var effective_max_tokens: int = max_tokens

	var url: String = base_url.rstrip("/") + "/chat/completions"
	var body: Dictionary = {
		"model": model,
		"messages": messages,
		"temperature": temperature,
		"max_tokens": effective_max_tokens,
		"stream": false,
	}
	if json_mode:
		body["response_format"] = {"type": "json_object"}

	var body_str: String = JSON.stringify(body)
	var t0: int = Time.get_ticks_msec()
	request_started.emit(body_str.length())

	var err: int = _http.request(url, _build_headers(), HTTPClient.METHOD_POST, body_str)
	if err != OK:
		return {"ok": false, "content": "", "error": "HTTPRequest.request() 错误码 %d" % err}

	# 等待响应
	var result: Array = await _http.request_completed
	var http_result: int = result[0]
	var response_code: int = result[1]
	# var headers: PackedStringArray = result[2]  # 暂未使用
	var response_body: PackedByteArray = result[3]

	var latency: int = Time.get_ticks_msec() - t0
	request_completed.emit(response_code == 200, latency)

	if http_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "content": "", "error": "HTTP 失败 result=%d" % http_result, "latency_ms": latency, "status": response_code}
	if response_code != 200:
		var err_text: String = response_body.get_string_from_utf8()
		return {"ok": false, "content": "", "error": "HTTP %d: %s" % [response_code, err_text], "latency_ms": latency, "status": response_code}

	var raw_text: String = response_body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(raw_text)
	if parsed == null or not parsed is Dictionary:
		return {"ok": false, "content": "", "error": "响应非合法 JSON: " + raw_text.left(200), "latency_ms": latency, "status": response_code}

	# OpenAI 标准结构：choices[0].message.content
	var choices = parsed.get("choices", [])
	if not choices is Array or choices.is_empty():
		return {"ok": false, "content": "", "error": "响应无 choices: " + raw_text.left(200), "latency_ms": latency, "status": response_code}
	var first = choices[0]
	if not first is Dictionary:
		return {"ok": false, "content": "", "error": "choices[0] 非对象", "latency_ms": latency, "status": response_code}
	var message = first.get("message", {})
	if not message is Dictionary:
		return {"ok": false, "content": "", "error": "无 message 字段", "latency_ms": latency, "status": response_code}
	var content: String = String(message.get("content", ""))

	# 提取 token 用量（供日志展示）
	var usage: Dictionary = parsed.get("usage", {})
	if not usage is Dictionary:
		usage = {}

	return {
		"ok": true,
		"content": content,
		"error": "",
		"raw": parsed,
		"latency_ms": latency,
		"status": response_code,
		"usage": usage,
		"finish_reason": String(first.get("finish_reason", "")),
		"effective_max_tokens": effective_max_tokens,  # 实际发给 API 的 max_tokens（已包含 1200 下限兜底）
	}
