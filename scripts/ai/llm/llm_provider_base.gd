class_name LLMProviderBase
extends RefCounted
## LLM Provider 抽象基类
##
## 各家厂商通过子类实现：
##   - OpenAICompatProvider（DeepSeek/智谱/通义/Moonshot 等所有 OpenAI 兼容协议）
##   - AnthropicProvider（Claude Messages API）
##   - MockProvider（离线测试）
##
## 调用模式（子类必须保持）：
##   var resp: Dictionary = await provider.request_chat(messages, params)
##   resp = {
##     "ok": bool,
##     "content": String,        # 模型返回的文本（理想情况是 JSON 字符串）
##     "error": String,          # 失败原因（ok=false 时填）
##     "raw": Variant,           # 原始响应供调试
##   }

# 信号供 UI 层订阅（调试日志/状态指示）
signal request_started(prompt_tokens: int)
signal request_completed(success: bool, latency_ms: int)


## 配置（由 LLMConfig 注入）
var api_key: String = ""
var base_url: String = ""
var model: String = ""
var temperature: float = 0.7
# 默认值；运行时会被 LLMConfig.make_provider() 覆盖为 LLMConfig.MAX_TOKENS_OVERRIDE。
# 如需调整 max_tokens，请只改 LLMConfig.MAX_TOKENS_OVERRIDE（单一真源），不要改这里。
var max_tokens: int = 2000
var timeout_sec: float = 30.0


## 发起 chat completion 请求（子类实现）
##
## @param messages    [{role, content}, ...] OpenAI 标准格式
## @param json_mode   是否要求严格 JSON 输出（response_format: json_object）
## @return            { ok, content, error, raw }
func request_chat(_messages: Array, _json_mode: bool = true) -> Dictionary:
	push_error("LLMProviderBase.request_chat() 必须被子类实现")
	return {"ok": false, "content": "", "error": "abstract"}


## Provider 名称（调试日志用）
func get_provider_name() -> String:
	return "base"


## 验证配置完整性
func is_configured() -> bool:
	return api_key.length() > 0 and base_url.length() > 0 and model.length() > 0


## 工具方法：组装 HTTP headers
func _build_headers() -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])


## 工具方法：从可能含 markdown code block 的文本中抽取 JSON
static func extract_json_from_text(text: String) -> String:
	# 1. ``` 包裹
	var start_idx: int = text.find("```")
	if start_idx >= 0:
		var lang_end: int = text.find("\n", start_idx)
		if lang_end >= 0:
			var end_idx: int = text.find("```", lang_end)
			if end_idx > lang_end:
				return text.substr(lang_end + 1, end_idx - lang_end - 1).strip_edges()
	# 2. 直接找 { ... }
	var brace_open: int = text.find("{")
	var brace_close: int = text.rfind("}")
	if brace_open >= 0 and brace_close > brace_open:
		return text.substr(brace_open, brace_close - brace_open + 1)
	return text.strip_edges()
